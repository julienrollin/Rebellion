local DEFAULT_INTERVAL_SECONDS = 35 * 60
local DEFAULT_POLL_MS = 60 * 1000
local DEFAULT_FOLDER = "autosave"
local DEFAULT_SUFFIX = "_bkp"
local MAX_BACKUP_INDEX = 9999
local PREF_ENABLED = "GRAutoSaveEnabled"
local PREF_INTERVAL_MINUTES = "GRAutoSaveIntervalMinutes"
local PREF_GROUP_LABEL = "Auto Save"

local state = rawget(_G, "_GRAutoSaveState")
if type(state) ~= "table" then
  state = {
    Busy = false,
    LastCheck = os.time(),
    LastBackup = nil,
    LastSavedSignature = nil,
    LastSkippedBackup = nil,
    LastError = nil,
    TimerWindow = nil,
    TimerInstalled = false,
  }
  rawset(_G, "_GRAutoSaveState", state)
end
if not state.LastCheck or state.LastCheck == 0 then
  state.LastCheck = os.time()
end

local function setGlobal(name, value)
  rawset(_G, name, value)
  local ok, env = pcall(function()
    return getfenv and getfenv(0)
  end)
  if ok and type(env) == "table" and env ~= _G then
    rawset(env, name, value)
  end
end

local function getGlobal(name)
  local value = rawget(_G, name)
  if value ~= nil then
    return value
  end
  local ok, env = pcall(function()
    return getfenv and getfenv(0)
  end)
  if ok and type(env) == "table" then
    return rawget(env, name)
  end
end

local function log(message)
  if getGlobal("GRAutoSaveDebug") and print then
    print("[GR-145 autosave] " .. tostring(message))
  end
end

local function normalizePath(path)
  if type(path) ~= "string" then
    return nil
  end
  path = path:gsub("\\", "/")
  path = path:gsub("/+$", "")
  return path
end

local function samePath(left, right)
  left = normalizePath(left)
  right = normalizePath(right)
  if not left or not right then
    return false
  end
  return left:lower() == right:lower()
end

local function getDocument()
  return getGlobal("Document")
end

local function documentFilename()
  local document = getDocument()
  if not document then
    return nil
  end
  local ok, filename = pcall(function()
    return document:getfilename()
  end)
  if ok and type(filename) == "string" and filename ~= "" then
    return filename
  end
end

local function documentHasChanged()
  local document = getDocument()
  if not document or not document.haschanged then
    return true
  end
  local ok, changed = pcall(function()
    return document:haschanged()
  end)
  if ok and changed ~= nil then
    return changed and true or false
  end
  return true
end

local function getPreferences()
  if not GADocumentGetPreferences then
    return nil
  end
  local document = getDocument()
  if not document then
    return nil
  end
  local ok, preferences = pcall(function()
    return GADocumentGetPreferences(document)
  end)
  if ok then
    return preferences
  end
end

local function getPreferencePlug(name)
  local preferences = getPreferences()
  return preferences and preferences[name] or nil
end

local function getPlugValue(plug)
  if plug and plug.get then
    local ok, value = pcall(function()
      return plug:get()
    end)
    if ok then
      return value
    end
  end
end

local function createIntervalType()
  if types and types.int then
    local ok, value = pcall(function()
      return types.int({min = 1, slidermax = 240})
    end)
    if ok and value then
      return value
    end
  end
  return LUIPSTypeUInt
end

local function ensurePreferencePlugs(preferences)
  preferences = preferences or getPreferences()
  if not preferences or not Plug then
    return nil
  end
  local noSerial = Plug.NoSerial or getGlobal("LUI_PLUG_NO_SERIAL")
  local refReadOnly = Plug.RefReadOnly or getGlobal("LUI_PLUG_REF_READ_ONLY") or 0
  if not noSerial then
    return preferences
  end
  local flags = noSerial + refReadOnly
  if not preferences[PREF_ENABLED] and LocalPlug and LUIPSTypeBool then
    pcall(LocalPlug, preferences, PREF_ENABLED, flags, LUIPSTypeBool, true)
  end
  if not preferences[PREF_INTERVAL_MINUTES] and LocalPlug then
    local intervalType = createIntervalType()
    if intervalType then
      pcall(LocalPlug, preferences, PREF_INTERVAL_MINUTES, flags, intervalType, math.floor(DEFAULT_INTERVAL_SECONDS / 60))
    end
  end
  return preferences
end

local function isEnabled()
  local override = getGlobal("GRAutoSaveEnabled")
  if override ~= nil then
    return override ~= false
  end
  local value = getPlugValue(getPreferencePlug(PREF_ENABLED))
  if value ~= nil then
    return value and true or false
  end
  return true
end

local function intervalSeconds()
  local value = tonumber(getGlobal("GRAutoSaveIntervalSeconds"))
  if value and value > 0 then
    return math.max(1, value)
  end
  local minutes = tonumber(getPlugValue(getPreferencePlug(PREF_INTERVAL_MINUTES)))
  if minutes and minutes > 0 then
    return math.max(1, math.floor(minutes * 60 + 0.5))
  end
  return DEFAULT_INTERVAL_SECONDS
end

local function resetIntervalClock()
  state.LastCheck = os.time()
end

local function pollMs()
  local value = tonumber(getGlobal("GRAutoSavePollMs"))
  if value and value > 0 then
    return math.max(250, value)
  end
  return DEFAULT_POLL_MS
end

local function autosaveFolderName()
  local value = getGlobal("GRAutoSaveFolderName")
  if type(value) == "string" and value ~= "" then
    return value
  end
  return DEFAULT_FOLDER
end

local function backupSuffix()
  local value = getGlobal("GRAutoSaveBackupSuffix")
  if type(value) == "string" and value ~= "" then
    return value
  end
  return DEFAULT_SUFFIX
end

local function stripFrameSubExtension(stem)
  if type(stem) ~= "string" then
    return stem
  end
  return stem:match("^(.*)%.%d%d%d%d%d$") or stem:match("^(.*)%.%d%d%d%d$") or stem
end

local function splitTrailingNumber(stem)
  if type(stem) ~= "string" then
    return nil
  end
  local prefix, number = stem:match("^(.-)(%d+)$")
  if not prefix or not number then
    return nil
  end
  return prefix, number, #number, tonumber(number)
end

local function splitProjectPath(path)
  path = normalizePath(path)
  if not path then
    return nil
  end
  local directory, filename = path:match("^(.*)/(.-)$")
  if not directory or directory == "" or not filename or filename == "" then
    return nil
  end
  local stem = filename:match("^(.*)%.gproject$")
  if not stem or stem == "" then
    return nil
  end
  return directory, stem
end

local function fileExists(path)
  local file = io.open(path, "rb")
  if file then
    file:close()
    return true
  end
  return false
end

local function fileSignature(path)
  local file = io.open(path, "rb")
  if not file then
    return nil
  end
  local size = 0
  local h1 = 5381
  local h2 = 0
  while true do
    local chunk = file:read(65536)
    if not chunk then
      break
    end
    for index = 1, #chunk do
      local byte = string.byte(chunk, index)
      size = size + 1
      h1 = (h1 * 33 + byte) % 4294967291
      h2 = (h2 + byte * ((size % 65521) + 1)) % 4294967279
    end
  end
  file:close()
  return tostring(size) .. ":" .. tostring(math.floor(h1)) .. ":" .. tostring(math.floor(h2))
end

local function removeFile(path)
  if type(path) == "string" and path ~= "" and os and os.remove then
    pcall(os.remove, path)
  end
end

local function quoteForCmd(path)
  path = tostring(path or ""):gsub("/", "\\")
  return '"' .. path:gsub('"', '') .. '"'
end

local function ensureDirectory(path)
  if fileExists(path) then
    return true
  end
  local command = "mkdir " .. quoteForCmd(path) .. " 2>nul"
  os.execute(command)
  return fileExists(path) or true
end

local function nextBackupPath(projectPath)
  local directory, stem = splitProjectPath(projectPath)
  if not directory then
    return nil, "invalid project path"
  end
  local folder = directory .. "/" .. autosaveFolderName()
  ensureDirectory(folder)
  local suffix = backupSuffix()
  stem = stripFrameSubExtension(stem)
  local prefix, _, width, numberValue = splitTrailingNumber(stem)
  if prefix and numberValue then
    for offset = 0, MAX_BACKUP_INDEX do
      local version = numberValue + offset
      local candidate = string.format("%s/%s%0" .. tostring(width) .. "d%s.gproject", folder, prefix, version, suffix)
      if not fileExists(candidate) then
        return candidate
      end
    end
    return nil, "backup version limit reached"
  end

  for index = 1, MAX_BACKUP_INDEX do
    local candidate = string.format("%s/%s%s_%03d.gproject", folder, stem, suffix, index)
    if not fileExists(candidate) then
      return candidate
    end
  end
  return nil, "backup index limit reached"
end

local function saveBackup(backupPath, originalPath)
  local document = getDocument()
  if not document or not document.savefile then
    return false, "Document:savefile unavailable"
  end
  local guardedSave = getGlobal("LUIIsolateLightSaveFileWithOriginalState")
  if not guardedSave then
    pcall(require, "ga_isolate_light")
    guardedSave = getGlobal("LUIIsolateLightSaveFileWithOriginalState")
  end
  local result
  if guardedSave then
    local ok, saved, err = pcall(guardedSave, backupPath)
    if not ok then
      return false, saved
    end
    if not saved then
      return false, err
    end
    result = err
  else
    local ok, saveResult = pcall(function()
      return document:savefile(backupPath)
    end)
    if not ok then
      return false, saveResult
    end
    result = saveResult
  end
  if result == false then
    return false, "Document:savefile returned false"
  end
  local afterPath = documentFilename()
  if afterPath and originalPath and not samePath(afterPath, originalPath) then
    return false, "active document path changed"
  end
  if not fileExists(backupPath) then
    return false, "backup file was not written"
  end
  return true
end

local function runAutosave(forceInterval, forceSave)
  local now = os.time()
  if state.Busy then
    return false, "busy"
  end
  if not isEnabled() then
    return false, "disabled"
  end
  local projectPath = documentFilename()
  if not projectPath then
    state.LastError = "no saved project path"
    return false, state.LastError
  end
  if not state.CurrentProject or not samePath(state.CurrentProject, projectPath) then
    state.CurrentProject = projectPath
    state.LastSavedSignature = nil
    state.LastSkippedBackup = nil
    state.LastCheck = now
    if not forceInterval then
      return false, "project-changed"
    end
  end
  if not forceInterval and state.LastCheck and now - state.LastCheck < intervalSeconds() then
    return false, "waiting"
  end

  state.LastCheck = now
  if not forceSave and not documentHasChanged() then
    state.LastError = nil
    return false, "clean"
  end

  local backupPath, pathError = nextBackupPath(projectPath)
  if not backupPath then
    state.LastError = pathError
    return false, pathError
  end

  state.Busy = true
  local ok, err = saveBackup(backupPath, projectPath)
  state.Busy = false
  if not ok then
    state.LastError = tostring(err)
    log("failed: " .. state.LastError)
    return false, state.LastError
  end

  local signature = fileSignature(backupPath)
  if not forceSave and signature and state.LastSavedSignature and state.LastProject and samePath(state.LastProject, projectPath) and signature == state.LastSavedSignature then
    removeFile(backupPath)
    state.LastSkippedBackup = backupPath
    state.LastError = nil
    log("unchanged " .. backupPath)
    return false, "unchanged"
  end

  state.LastBackup = backupPath
  state.LastProject = projectPath
  state.LastSavedSignature = signature
  state.LastSkippedBackup = nil
  state.LastError = nil
  log("saved " .. backupPath)
  return true, backupPath
end

local function timerAlive(timer)
  if not timer then
    return false
  end
  if LUIWindowIsDestroyed then
    local ok, destroyed = pcall(LUIWindowIsDestroyed, timer)
    if ok and destroyed then
      return false
    end
  end
  return true
end

local function defineTimerClass()
  if rawget(_G, "GRAutoSaveTimerVT") then
    return true
  end
  if not LUIVTCreate then
    return false
  end
  local ok = pcall(LUIVTCreate, "GRAutoSaveTimer", "LUIWindow")
  if not ok then
    return false
  end
  if LUIWindowHookVTIndex then
    pcall(LUIWindowHookVTIndex, GRAutoSaveTimerVT)
  end
  function GRAutoSaveTimerVT:onTimer(last)
    state.LastTimerTick = os.time()
    local ok, err = pcall(runAutosave, false, false)
    if not ok then
      state.LastError = tostring(err)
      log("timer failed: " .. state.LastError)
    end
    if timerAlive(self) and LUITimerAdd then
      local rearmed, timerErr = pcall(LUITimerAdd, self, pollMs())
      if not rearmed then
        state.TimerInstalled = false
        state.LastError = tostring(timerErr)
        log("timer rearm failed: " .. state.LastError)
      end
    end
  end
  return true
end

local installSaveEventHook
local installPreferencesHook

local function installTimer()
  installSaveEventHook()
  pcall(installPreferencesHook)
  if state.TimerInstalled and timerAlive(state.TimerWindow) then
    return true
  end
  if not LUIWindowCreate or not LUIRootWindow or not LUITimerAdd or not LUIVTSetClass then
    return false
  end
  if not defineTimerClass() then
    return false
  end
  local ok, timer = pcall(LUIWindowCreate, "_GRAutoSaveTimer", LUIRootWindow)
  if not ok or not timer then
    return false
  end
  LUIVTSetClass(timer, GRAutoSaveTimerVT)
  if LUIWindowHide then
    pcall(LUIWindowHide, timer)
  end
  state.TimerWindow = timer
  state.TimerInstalled = true
  LUITimerAdd(timer, pollMs())
  return true
end

installSaveEventHook = function()
  if state.SaveEventInstalled then
    return true
  end
  local eventApi = getGlobal("event")
  if not eventApi or not eventApi.register then
    return false
  end
  local ok = pcall(function()
    eventApi.register("savedocument", function()
      if not state.Busy then
        resetIntervalClock()
      end
    end, "GR145AutoSaveResetClock")
  end)
  if ok then
    state.SaveEventInstalled = true
    return true
  end
  return false
end

local function autosavePreferenceDocs()
  return {
    Enabled = "Enable automatic backup saves next to the active project.",
    Interval = "Minutes between automatic backups, measured from project open/change or last native save.",
  }
end

local function appendAutoSaveTemplate(preferences, template)
  if type(template) ~= "table" then
    return template
  end
  preferences = ensurePreferencePlugs(preferences)
  if not preferences or not preferences[PREF_ENABLED] or not preferences[PREF_INTERVAL_MINUTES] then
    return template
  end
  for _, group in ipairs(template) do
    if group and group[1] == PREF_GROUP_LABEL then
      return template
    end
  end
  local docs = autosavePreferenceDocs()
  template[#template + 1] = {
    PREF_GROUP_LABEL,
    {
      {"Enabled", preferences[PREF_ENABLED], nil, docs.Enabled},
      {"Every (minutes)", preferences[PREF_INTERVAL_MINUTES], nil, docs.Interval},
    },
  }
  return template
end

installPreferencesHook = function()
  pcall(ensurePreferencePlugs)
  local preferencesVT = rawget(_G, "GAPreferencesVT") or rawget(_G, "PreferencesVT") or rawget(_G, "Preferences")
  if type(preferencesVT) ~= "table" or type(preferencesVT.onGetLocalSettingsTemplate) ~= "function" then
    return false
  end
  if rawget(_G, "_GRAutoSavePreferencesHookInstalled") then
    return true
  end
  local original = preferencesVT.onGetLocalSettingsTemplate
  preferencesVT.onGetLocalSettingsTemplate = function(self, ...)
    local template = original(self, ...)
    return appendAutoSaveTemplate(self, template)
  end
  rawset(_G, "_GRAutoSavePreferencesHookInstalled", true)
  return true
end

local function status()
  pcall(ensurePreferencePlugs)
  return {
    Enabled = isEnabled(),
    Busy = state.Busy,
    LastCheck = state.LastCheck,
    LastTimerTick = state.LastTimerTick,
    LastBackup = state.LastBackup,
    LastSavedSignature = state.LastSavedSignature,
    LastSkippedBackup = state.LastSkippedBackup,
    LastProject = state.LastProject,
    LastError = state.LastError,
    TimerInstalled = state.TimerInstalled and timerAlive(state.TimerWindow) or false,
    SaveEventInstalled = state.SaveEventInstalled == true,
    PreferencesInstalled = rawget(_G, "_GRAutoSavePreferencesHookInstalled") == true,
    IntervalSeconds = intervalSeconds(),
  }
end

setGlobal("GRAutoSaveNextBackupPath", nextBackupPath)
setGlobal("GRAutoSaveTick", function(forceInterval)
  return runAutosave(forceInterval == true, false)
end)
setGlobal("GRAutoSaveNow", function()
  return runAutosave(true, true)
end)
setGlobal("GRAutoSaveStatus", status)
setGlobal("GRAutoSaveInstall", installTimer)

pcall(installSaveEventHook)
pcall(installPreferencesHook)
pcall(installTimer)

return true
