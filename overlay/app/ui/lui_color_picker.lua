require("lui_edit_box")
require("lui_button")

local TWO_PI = math.pi * 2
local KELVIN_POWER = 2.812914447
local PICKER_WIDTH = 420
local PICKER_HEIGHT = 220
local WHEEL_TEXTURE = "color_picker_wheel.png"
local HUE_TEXTURE = "color_picker_hue_strip.png"
local PICK_BUTTON_W = 34
local PICK_BUTTON_H = 20
local PICK_BUTTON_GAP = 4
local RGB_SPACE_BUTTON_W = 86
local RGB_SPACE_BUTTON_H = 18
local PREVIEW_SWATCH_GAP = 4
local FAVORITES_FILE_NAME = "color_picker_favorites.txt"
local HOVER_PICK_TIMER_DELAY = 25
local TEMP_MIN = 1800
local TEMP_MAX = 17140
local FAVORITE_COUNT = 5
local FAVORITE_SWATCH_SIZE = 18
local FAVORITE_SWATCH_GAP = 6
local TEMP_RAMP_SEGMENT_COUNT = 32
local PRESET_SWATCH_SIZE = 18
local PRESET_SWATCH_GAP = 4
local PRESET_ROW_GAP = 4
local PRESET_MAX_SWATCHES = 4
local TEMP_PRESET_BUTTON_W = 64
local TEMP_PRESET_BUTTON_H = 16
local TEMP_PRESET_GAP = 4
local PRESET_SCHEME_DEFS = {
  {Name = "Mono", Count = 3},
  {Name = "Complement", Count = 2},
  {Name = "Analogous", Count = 3},
  {Name = "Triadic", Count = 3},
  {Name = "Split Comp", Count = 3},
  {Name = "Tetradic", Count = 4}
}
local TEMP_PRESET_DEFS = {
  {Name = "Candlelight", Temp = 1800, Label = "Fire"},
  {Name = "Extra Warm White", Temp = 2800, Label = "Lamp"},
  {Name = "Cool White (Moonlight)", Temp = 4000, Label = "Moon"},
  {Name = "Daylight", Temp = 5000, Label = "Sun"},
  {Name = "Overcast Sky", Temp = 7000, Label = "Overcast"},
  {Name = "Blue Sky", Temp = 10000, Label = "Sky"}
}

local NUMBER_DESC = {Type = "number"}
local STRING_DESC = {Type = "string"}

local COLOR_WHITE = LUIRGBA(255, 255, 255, 255)
local COLOR_LABEL = LUIRGBA(220, 220, 220, 255)
local COLOR_MARKER = LUIRGBA(185, 185, 185, 255)
local COLOR_EMPTY_SWATCH = LUIRGBA(58, 58, 58, 255)
local COLOR_EMPTY_BORDER = LUIRGBA(88, 88, 88, 255)
local COLOR_TAB_ACTIVE = LUIRGBA(92, 92, 92, 255)
local COLOR_TAB_INACTIVE = LUIRGBA(64, 64, 64, 255)

local RGB_DISPLAY_RENDERING = "rendering"
local RGB_DISPLAY_PICKER = "picker"

LUIVTCreate("LUIColorPicker", "LUIControl", "LUIWindow")
LUIWindowHookVTIndex(LUIColorPickerVT)
LUIVTCreate("LUIColorPickerButton", "LUITextButton")
LUIVTCreate("LUIColorPickerRGBSpaceButton", "LUITextButton")
LUIVTCreate("LUIColorPickerWheel", "LUIQuad")
LUIVTCreate("LUIColorPickerBar", "LUIQuad")
LUIVTCreate("LUIColorPickerSwatch", "LUIQuad")

local toggleRGBDisplaySpace

function LUIColorPickerButtonVT:onLClick()
  local picker = LUIWindowGetParent(self, "LUIColorPicker")
  if picker then
    picker:onStartPickColor(self)
  end
end

function LUIColorPickerRGBSpaceButtonVT:onLClick()
  local picker = LUIWindowGetParent(self, "LUIColorPicker")
  if picker and toggleRGBDisplaySpace then
    toggleRGBDisplaySpace(picker)
  end
end

local function clamp01(value)
  value = tonumber(value) or 0
  if value < 0 then
    return 0
  elseif value > 1 then
    return 1
  end
  return value
end

local function clampMin0(value)
  value = tonumber(value) or 0
  if value < 0 then
    return 0
  end
  return value
end

local function clampByte(value)
  return math.max(0, math.min(255, math.floor(255 * (value or 0) + 0.5)))
end

local function clampTemperature(value)
  value = tonumber(value) or TEMP_MIN
  if value < TEMP_MIN then
    return TEMP_MIN
  elseif value > TEMP_MAX then
    return TEMP_MAX
  end
  return value
end

local function parseEditableNumber(text)
  if type(text) ~= "string" then
    return nil
  end
  return tonumber((text:gsub(",", ".")))
end

local function temperatureToNormalized(value)
  local normalized = (clampTemperature(value) - TEMP_MIN) / (TEMP_MAX - TEMP_MIN)
  return math.pow(normalized, 1 / KELVIN_POWER)
end

local function normalizedToTemperature(value)
  return TEMP_MIN + math.pow(clamp01(value), KELVIN_POWER) * (TEMP_MAX - TEMP_MIN)
end

local function copyRGB(rgb)
  return {
    tonumber(rgb and rgb[1]) or 0,
    tonumber(rgb and rgb[2]) or 0,
    tonumber(rgb and rgb[3]) or 0
  }
end

local function isRGBPickerDisplay(self)
  return self and self._RGBDisplaySpace == RGB_DISPLAY_PICKER
end

local function getDisplayedRGB(self)
  if isRGBPickerDisplay(self) then
    return self._PickerRGB
  end
  return self._RGB
end

local function copyRGBList(colors)
  local copied = {}
  for index, rgb in ipairs(colors or {}) do
    copied[index] = copyRGB(rgb)
  end
  return copied
end

local function sanitizeRenderingRGB(rgb)
  if type(rgb) == "number" then
    return {rgb, rgb, rgb}
  elseif type(rgb) == "table" then
    return copyRGB(rgb)
  end
  return {0, 0, 0}
end

local function sanitizePickerRGB(rgb)
  rgb = sanitizeRenderingRGB(rgb)
  return {
    clampMin0(rgb[1]),
    clampMin0(rgb[2]),
    clampMin0(rgb[3])
  }
end

local function rgbToUIColor(rgb)
  return LUIRGB(clampByte(rgb[1]), clampByte(rgb[2]), clampByte(rgb[3]))
end

local function formatNumber(value)
  local text = string.format("%.3f", tonumber(value) or 0)
  text = text:gsub("0+$", "")
  text = text:gsub("%.$", "")
  return text ~= "" and text or "0"
end

local function formatKelvin(value)
  return tostring(math.floor(clampTemperature(value) + 0.5))
end

local function colorsEqual(a, b)
  if not a or not b then
    return false
  end
  return math.abs((a[1] or 0) - (b[1] or 0)) < 1e-6 and math.abs((a[2] or 0) - (b[2] or 0)) < 1e-6 and math.abs((a[3] or 0) - (b[3] or 0)) < 1e-6
end

local function getFavoritesFilePath()
  local base = os.getenv("APPDATA") or os.getenv("USERPROFILE")
  if not base or base == "" then
    return nil
  end
  return base .. "\\Guerilla2\\" .. FAVORITES_FILE_NAME
end

local function loadFavoritePaletteFromFile()
  local path = getFavoritesFilePath()
  if not path then
    return nil
  end

  local file = io.open(path, "r")
  if not file then
    return nil
  end

  local favorites = {}
  for line in file:lines() do
    local r, g, b = string.match(line, "^%s*([%+%-]?[%d%.eE]+)%s+([%+%-]?[%d%.eE]+)%s+([%+%-]?[%d%.eE]+)%s*$")
    if r and g and b then
      favorites[#favorites + 1] = sanitizeRenderingRGB({tonumber(r), tonumber(g), tonumber(b)})
      if #favorites >= FAVORITE_COUNT then
        break
      end
    end
  end
  file:close()
  return favorites
end

local function saveFavoritePaletteToFile(favorites)
  local path = getFavoritesFilePath()
  if not path then
    return false
  end

  local dir = string.match(path, "^(.*)\\[^\\]+$")
  if dir and dir ~= "" then
    os.execute('if not exist "' .. dir .. '" mkdir "' .. dir .. '" >nul 2>nul')
  end

  local file = io.open(path, "w")
  if not file then
    return false
  end

  for index = 1, math.min(#favorites, FAVORITE_COUNT) do
    local rgb = sanitizeRenderingRGB(favorites[index])
    file:write(string.format("%.9f %.9f %.9f\n", rgb[1], rgb[2], rgb[3]))
  end
  file:close()
  return true
end

local function getPreferences()
  local ok, preferences = pcall(function()
    return GADocumentGetPreferences(Document)
  end)
  return ok and preferences or nil
end

local favoritePaletteCache = nil

local function getFavoritePaletteFromPreferences()
  local preferences = getPreferences()
  if preferences and preferences.ColorPickerPalette and preferences.ColorPickerPalette.get then
    local palette = preferences.ColorPickerPalette:get() or {}
    local favorites = {}
    for index = 1, math.min(#palette, FAVORITE_COUNT) do
      favorites[index] = sanitizeRenderingRGB(palette[index])
    end
    return favorites
  end
  return {}
end

local function getFavoritePalette()
  if not favoritePaletteCache then
    favoritePaletteCache = getFavoritePaletteFromPreferences()
    if not favoritePaletteCache or #favoritePaletteCache == 0 then
      favoritePaletteCache = loadFavoritePaletteFromFile()
      if favoritePaletteCache and #favoritePaletteCache > 0 then
        local preferences = getPreferences()
        if preferences and preferences.ColorPickerPalette and preferences.ColorPickerPalette.set then
          local palette = {}
          for index = 1, math.min(#favoritePaletteCache, FAVORITE_COUNT) do
            palette[index] = copyRGB(favoritePaletteCache[index])
          end
          preferences.ColorPickerPalette:set(palette, true)
        end
      end
    end
    if not favoritePaletteCache then
      favoritePaletteCache = {}
    end
  end
  return copyRGBList(favoritePaletteCache)
end

local function setFavoritePalette(favorites)
  favoritePaletteCache = {}
  for index = 1, math.min(#favorites, FAVORITE_COUNT) do
    favoritePaletteCache[index] = copyRGB(favorites[index])
  end

  local preferences = getPreferences()
  if preferences and preferences.ColorPickerPalette and preferences.ColorPickerPalette.set then
    local palette = {}
    for index = 1, math.min(#favoritePaletteCache, FAVORITE_COUNT) do
      palette[index] = copyRGB(favoritePaletteCache[index])
    end
    preferences.ColorPickerPalette:set(palette, true)
  end
end

function colorPickerDisplayColor(rgb)
  local pickerRGB = sanitizePickerRGB(ocio.renderingtopicker(sanitizeRenderingRGB(rgb)))
  return rgbToUIColor(pickerRGB)
end

function colorPickerMemorizeColor(rgb)
  rgb = sanitizeRenderingRGB(rgb)
  local favorites = getFavoritePalette()
  table.insert(favorites, 1, rgb)
  while #favorites > FAVORITE_COUNT do
    table.remove(favorites)
  end
  setFavoritePalette(favorites)
end

function colorPickerForgetColor(rgb)
  rgb = sanitizeRenderingRGB(rgb)
  local favorites = getFavoritePalette()
  for index = #favorites, 1, -1 do
    if colorsEqual(favorites[index], rgb) then
      table.remove(favorites, index)
    end
  end
  setFavoritePalette(favorites)
end

function LUIColorPickerParseHex(text)
  if type(text) ~= "string" then
    return nil
  end
  local hex = text:gsub("%s+", "")
  if string.sub(hex, 1, 1) == "#" then
    hex = string.sub(hex, 2)
  end
  hex = string.upper(hex)
  if #hex == 3 and string.match(hex, "^[0-9A-F]+$") then
    hex = string.gsub(hex, ".", function(char)
      return char .. char
    end)
  end
  if #hex ~= 6 or not string.match(hex, "^[0-9A-F]+$") then
    return nil
  end
  return {
    tonumber(string.sub(hex, 1, 2), 16) / 255,
    tonumber(string.sub(hex, 3, 4), 16) / 255,
    tonumber(string.sub(hex, 5, 6), 16) / 255
  }, hex
end

function LUIColorPickerHexToRenderingRGB(text)
  local pickerRGB, hex = LUIColorPickerParseHex(text)
  if not pickerRGB then
    return nil
  end
  return sanitizeRenderingRGB(ocio.pickertorendering(pickerRGB)), hex
end

local function pickerRGBToHex(rgb)
  return string.format("%02X%02X%02X", clampByte(rgb[1]), clampByte(rgb[2]), clampByte(rgb[3]))
end

local function wrapHue(value)
  value = tonumber(value) or 0
  value = value % 1
  if value < 0 then
    value = value + 1
  end
  return value
end

local function pickerRGBToHSV(rgb, fallbackHue)
  local r = clampMin0(rgb and rgb[1])
  local g = clampMin0(rgb and rgb[2])
  local b = clampMin0(rgb and rgb[3])
  local maxValue = math.max(r, g, b)
  local minValue = math.min(r, g, b)
  local delta = maxValue - minValue

  local h = wrapHue(fallbackHue or 0)
  local s = 0
  local v = maxValue

  if maxValue > 0 then
    s = delta / maxValue
  end

  if delta > 1e-6 then
    if maxValue == r then
      h = ((g - b) / delta) % 6
    elseif maxValue == g then
      h = ((b - r) / delta) + 2
    else
      h = ((r - g) / delta) + 4
    end
    h = wrapHue(h / 6)
  end

  return h, s, v
end

local function hsvToPickerRGB(h, s, v)
  h = wrapHue(h)
  s = clampMin0(s)
  v = clampMin0(v)

  local c = v * s
  local hh = h * 6
  local x = c * (1 - math.abs((hh % 2) - 1))
  local r1, g1, b1 = 0, 0, 0

  if hh < 1 then
    r1, g1, b1 = c, x, 0
  elseif hh < 2 then
    r1, g1, b1 = x, c, 0
  elseif hh < 3 then
    r1, g1, b1 = 0, c, x
  elseif hh < 4 then
    r1, g1, b1 = 0, x, c
  elseif hh < 5 then
    r1, g1, b1 = x, 0, c
  else
    r1, g1, b1 = c, 0, x
  end

  local m = v - c
  return {
    clampMin0(r1 + m),
    clampMin0(g1 + m),
    clampMin0(b1 + m)
  }
end

local function hsvToRenderingRGB(h, s, v)
  return sanitizeRenderingRGB(ocio.pickertorendering(hsvToPickerRGB(h, clamp01(s), clampMin0(v))))
end

local function buildPresetSchemes(self)
  local h = self._HSV[1] or 0
  local s = math.max(0.18, clamp01(self._HSV[2]))
  local v = math.max(0.25, clamp01(self._HSV[3]))
  local monoS1 = math.max(0.12, s * 0.45)
  local monoS2 = math.max(0.18, s * 0.72)
  local monoV1 = math.max(0.18, v * 0.42)
  local monoV2 = math.max(0.34, v * 0.70)

  return {
    {
      Name = "Mono",
      Colors = {
        hsvToRenderingRGB(h, monoS1, monoV1),
        hsvToRenderingRGB(h, monoS2, monoV2),
        hsvToRenderingRGB(h, s, v)
      }
    },
    {
      Name = "Complement",
      Colors = {
        hsvToRenderingRGB(h, s, v),
        hsvToRenderingRGB(h + 0.5, s, v)
      }
    },
    {
      Name = "Analogous",
      Colors = {
        hsvToRenderingRGB(h - (1 / 12), s, v),
        hsvToRenderingRGB(h, s, v),
        hsvToRenderingRGB(h + (1 / 12), s, v)
      }
    },
    {
      Name = "Triadic",
      Colors = {
        hsvToRenderingRGB(h, s, v),
        hsvToRenderingRGB(h + (1 / 3), s, v),
        hsvToRenderingRGB(h + (2 / 3), s, v)
      }
    },
    {
      Name = "Split Comp",
      Colors = {
        hsvToRenderingRGB(h, s, v),
        hsvToRenderingRGB(h + (5 / 12), s, v),
        hsvToRenderingRGB(h + (7 / 12), s, v)
      }
    },
    {
      Name = "Tetradic",
      Colors = {
        hsvToRenderingRGB(h, s, v),
        hsvToRenderingRGB(h + (1 / 6), s, v),
        hsvToRenderingRGB(h + 0.5, s, v),
        hsvToRenderingRGB(h + (2 / 3), s, v)
      }
    }
  }
end

local function atan2(y, x)
  if x > 0 then
    return math.atan(y / x)
  elseif x < 0 then
    return math.atan(y / x) + (y >= 0 and math.pi or -math.pi)
  elseif y > 0 then
    return math.pi * 0.5
  elseif y < 0 then
    return -math.pi * 0.5
  end
  return 0
end

local function hsvToWheelPoint(h, s)
  local angle = (tonumber(h) or 0) * TWO_PI
  local radius = clamp01(s) * 0.5
  return 0.5 + math.cos(angle) * radius, 0.5 - math.sin(angle) * radius
end

local function isPointInsideWheel(px, py)
  local dx = (px or 0) - 0.5
  local dy = 0.5 - (py or 0)
  return dx * dx + dy * dy <= 0.25
end

local function wheelPointToHSV(px, py, currentHue)
  local dx = (px or 0) - 0.5
  local dy = 0.5 - (py or 0)
  local length = math.sqrt(dx * dx + dy * dy)
  local sat = clamp01(length * 2)
  if length > 0.5 then
    dx = dx / length * 0.5
    dy = dy / length * 0.5
  end
  if sat == 0 then
    return currentHue or 0, 0
  end
  local hue = atan2(dy, dx) / TWO_PI
  if hue < 0 then
    hue = hue + 1
  end
  return hue, sat
end

local function sliderValue(self, name)
  if name == "R" then
    return clamp01(getDisplayedRGB(self)[1])
  elseif name == "G" then
    return clamp01(getDisplayedRGB(self)[2])
  elseif name == "B" then
    return clamp01(getDisplayedRGB(self)[3])
  elseif name == "H" then
    return clamp01(self._HSV[1])
  elseif name == "S" then
    return clamp01(self._HSV[2])
  elseif name == "V" then
    return clamp01(self._HSV[3])
  elseif name == "K" then
    return temperatureToNormalized(self._Temperature)
  end
  return 0
end

local function setQuadHorizontalGradient(quad, leftRGB, rightRGB)
  local left = rgbToUIColor(leftRGB)
  local right = rgbToUIColor(rightRGB)
  quad.Color = nil
  quad.ColorBL = left
  quad.ColorTL = left
  quad.ColorBR = right
  quad.ColorTR = right
end

local function setQuadHorizontalGradientColors(quad, left, right)
  quad.Color = nil
  quad.ColorBL = left
  quad.ColorTL = left
  quad.ColorBR = right
  quad.ColorTR = right
end

local function temperatureRampUIColor(normalized)
  local rgb = ocio.temperaturetorendering(normalizedToTemperature(normalized))
  local pickerRGB = sanitizePickerRGB(ocio.renderingtopicker(sanitizeRenderingRGB(rgb)))
  return rgbToUIColor(pickerRGB)
end

local function updateTemperatureRampSegments(bar)
  if not (bar and bar._RampSegments) then
    return
  end
  for index, quad in ipairs(bar._RampSegments) do
    local left = (index - 1) / TEMP_RAMP_SEGMENT_COUNT
    local right = index / TEMP_RAMP_SEGMENT_COUNT
    setQuadHorizontalGradientColors(quad, temperatureRampUIColor(left), temperatureRampUIColor(right))
  end
end

local function layoutTemperatureRampSegments(bar, width, height)
  if not (bar and bar._RampSegments) then
    return
  end
  for index, quad in ipairs(bar._RampSegments) do
    local x0 = math.floor((index - 1) * width / TEMP_RAMP_SEGMENT_COUNT)
    local x1 = math.floor(index * width / TEMP_RAMP_SEGMENT_COUNT)
    LUIWindowSetX(quad, x0)
    LUIWindowSetY(quad, 0)
    LUIWindowSetW(quad, math.max(1, x1 - x0))
    LUIWindowSetH(quad, height)
  end
end

local updateSwatchWidget

local function updatePreview(self)
  if self._PreviewBefore then
    updateSwatchWidget(self._PreviewBefore, self._OriginalRGB)
  end
  if self._Preview then
    updateSwatchWidget(self._Preview, self._RGB)
  end
end

local function updateSliderGradients(self)
  local displayedRGB = getDisplayedRGB(self)
  local r, g, b = clamp01(displayedRGB[1]), clamp01(displayedRGB[2]), clamp01(displayedRGB[3])
  local h, s, v = self._HSV[1], clamp01(self._HSV[2]), clamp01(self._HSV[3])
  local s0r, s0g, s0b = LUIHSV2RGB(h, 0, v)
  local s1r, s1g, s1b = LUIHSV2RGB(h, 1, v)
  local v1r, v1g, v1b = LUIHSV2RGB(h, s, 1)

  if isRGBPickerDisplay(self) then
    setQuadHorizontalGradient(self._Bars.R, {0, g, b}, {1, g, b})
    setQuadHorizontalGradient(self._Bars.G, {r, 0, b}, {r, 1, b})
    setQuadHorizontalGradient(self._Bars.B, {r, g, 0}, {r, g, 1})
  else
    setQuadHorizontalGradientColors(
      self._Bars.R,
      colorPickerDisplayColor({0, g, b}),
      colorPickerDisplayColor({1, g, b})
    )
    setQuadHorizontalGradientColors(
      self._Bars.G,
      colorPickerDisplayColor({r, 0, b}),
      colorPickerDisplayColor({r, 1, b})
    )
    setQuadHorizontalGradientColors(
      self._Bars.B,
      colorPickerDisplayColor({r, g, 0}),
      colorPickerDisplayColor({r, g, 1})
    )
  end
  setQuadHorizontalGradient(self._Bars.S, {s0r, s0g, s0b}, {s1r, s1g, s1b})
  setQuadHorizontalGradient(self._Bars.V, {0, 0, 0}, {v1r, v1g, v1b})

  self._Bars.H.Color = COLOR_WHITE
  self._Bars.H.ColorBL = COLOR_WHITE
  self._Bars.H.ColorTL = COLOR_WHITE
  self._Bars.H.ColorBR = COLOR_WHITE
  self._Bars.H.ColorTR = COLOR_WHITE

  self._Bars.K.Color = COLOR_WHITE
  self._Bars.K.ColorBL = COLOR_WHITE
  self._Bars.K.ColorTL = COLOR_WHITE
  self._Bars.K.ColorBR = COLOR_WHITE
  self._Bars.K.ColorTR = COLOR_WHITE
  updateTemperatureRampSegments(self._Bars.K)
end

updateSwatchWidget = function(swatch, rgb)
  swatch._RGB = rgb and copyRGB(rgb) or nil
  swatch.BorderColor = swatch._RGB and LUIRGBA(16, 16, 16, 255) or COLOR_EMPTY_BORDER
  if swatch._RGB then
    swatch.Color = colorPickerDisplayColor(swatch._RGB)
  else
    swatch.Color = COLOR_EMPTY_SWATCH
  end
end

local function setOriginalRGB(self, rgb)
  self._OriginalRGB = sanitizeRenderingRGB(rgb)
  if self._PreviewBefore then
    updateSwatchWidget(self._PreviewBefore, self._OriginalRGB)
  end
end

local function updateSwatches(self)
  local favorites = getFavoritePalette()
  for index, swatch in ipairs(self._FavoriteSwatches) do
    updateSwatchWidget(swatch, favorites[index])
  end
  local presetRows = buildPresetSchemes(self)
  for rowIndex, row in ipairs(self._PresetRows or {}) do
    local scheme = presetRows[rowIndex]
    if row.Label and scheme then
      LUITextSetText(row.Label, scheme.Name)
    end
    for swatchIndex, swatch in ipairs(row.Swatches or {}) do
      local rgb = scheme and scheme.Colors[swatchIndex] or nil
      swatch._SchemeActive = rgb ~= nil
      updateSwatchWidget(swatch, rgb)
    end
  end
end

local function updateTempPresetButtons(self)
  for _, item in ipairs(self._TempPresetButtons or {}) do
    local active = math.abs((self._Temperature or 0) - item.Temp) <= math.max(100, item.Temp * 0.04)
    LUIWindowSetColor(item.Button, active and COLOR_TAB_ACTIVE or COLOR_TAB_INACTIVE)
    if item.Button._Children and item.Button._Children.text then
      LUITextSetColor(item.Button._Children.text, active and COLOR_WHITE or COLOR_LABEL)
    end
  end
end

local function updatePickButton(self)
  if not self._PickButton then
    return
  end

  local active = self._PickingColor == true
  self._PickButton.ForceColor = active and COLOR_TAB_ACTIVE or nil
  if self._PickButton.updateState then
    self._PickButton:updateState()
  else
    LUIWindowSetColor(self._PickButton, active and COLOR_TAB_ACTIVE or COLOR_TAB_INACTIVE)
  end
  if self._PickButton._Children and self._PickButton._Children.text then
    LUITextSetColor(self._PickButton._Children.text, active and COLOR_WHITE or COLOR_LABEL)
  end
end

local function updateRGBSpaceButton(self)
  if not self._RGBSpaceButton then
    return
  end

  local pickerDisplay = isRGBPickerDisplay(self)
  local label = pickerDisplay and "RGB: View" or "RGB: Raw"
  if self._RGBSpaceButton.settext then
    self._RGBSpaceButton:settext(label)
  end
  LUIWindowSetColor(self._RGBSpaceButton, pickerDisplay and COLOR_TAB_ACTIVE or COLOR_TAB_INACTIVE)
  if self._RGBSpaceButton._Children and self._RGBSpaceButton._Children.text then
    LUITextSetText(self._RGBSpaceButton._Children.text, label)
    LUITextSetColor(self._RGBSpaceButton._Children.text, pickerDisplay and COLOR_WHITE or COLOR_LABEL)
  end
end

function _LUIColorPickerUpdateControler(self, merge)
  self._SyncingControlValue = true
  self._LastAction = LUIControlSetValue(self, copyRGB(self._RGB), merge and self._LastAction or nil, true)
  self._SyncingControlValue = false
end

function _LUIColorPickerUpdateMarkers(self)
  if not self._WheelMarker then
    return
  end

  local px, py = hsvToWheelPoint(self._HSV[1], self._HSV[2])
  LUIWindowSetX(self._WheelMarker, 0, px, 0.5)
  LUIWindowSetY(self._WheelMarker, 0, py, 0.5)
  LUIWindowSetColor(self._WheelShade, LUIRGBA(0, 0, 0, math.floor((1 - clamp01(self._HSV[3])) * 255 + 0.5)))

  for name, bar in pairs(self._Bars) do
    LUIWindowSetX(bar._Marker, 0, sliderValue(self, name), 0.5)
  end
end

local function refreshFields(self, sourceField)
  local displayedRGB = getDisplayedRGB(self)
  self._SuspendFieldCallbacks = true
  for name, field in pairs(self._Fields) do
    if name ~= sourceField then
      if name == "R" then
        LUIEditBoxSetText(field.Box, formatNumber(displayedRGB[1]))
      elseif name == "G" then
        LUIEditBoxSetText(field.Box, formatNumber(displayedRGB[2]))
      elseif name == "B" then
        LUIEditBoxSetText(field.Box, formatNumber(displayedRGB[3]))
      elseif name == "H" then
        LUIEditBoxSetText(field.Box, formatNumber(self._HSV[1]))
      elseif name == "S" then
        LUIEditBoxSetText(field.Box, formatNumber(self._HSV[2]))
      elseif name == "V" then
        LUIEditBoxSetText(field.Box, formatNumber(self._HSV[3]))
      elseif name == "K" then
        LUIEditBoxSetText(field.Box, formatKelvin(self._Temperature))
      elseif name == "Hex" then
        LUIEditBoxSetText(field.Box, pickerRGBToHex(self._PickerRGB))
      end
    end
  end
  self._SuspendFieldCallbacks = false
end

local function updateVisuals(self, sourceField)
  updatePreview(self)
  updateSliderGradients(self)
  updateRGBSpaceButton(self)
  refreshFields(self, sourceField)
  updateSwatches(self)
  updateTempPresetButtons(self)
  _LUIColorPickerUpdateMarkers(self)
  LUIWindowInvalidateBatch(self)
end

local function applyRenderingRGB(self, rgb, sourceField)
  self._RGB = sanitizeRenderingRGB(rgb)
  self._PickerRGB = sanitizePickerRGB(ocio.renderingtopicker(self._RGB))
  local h, s, v = pickerRGBToHSV(self._PickerRGB, self._HSV[1])
  if s == 0 and self._HSV[1] ~= nil then
    h = self._HSV[1]
  end
  self._HSV[1] = h
  self._HSV[2] = s
  self._HSV[3] = v
  self._Temperature = clampTemperature(ocio.renderingtotemperature(self._RGB))
  updateVisuals(self, sourceField)
end

local function setPickerRGB(self, pickerRGB, merge, final, sourceField)
  pickerRGB = sanitizePickerRGB(pickerRGB)
  local h, s, v = pickerRGBToHSV(pickerRGB, self._HSV[1])
  if s == 0 and self._HSV[1] ~= nil then
    h = self._HSV[1]
  end
  self._PickerRGB = pickerRGB
  self._HSV[1] = h
  self._HSV[2] = s
  self._HSV[3] = v
  self._RGB = sanitizeRenderingRGB(ocio.pickertorendering(pickerRGB))
  self._Temperature = clampTemperature(ocio.renderingtotemperature(self._RGB))
  updateVisuals(self, sourceField)
  _LUIColorPickerUpdateControler(self, merge)
end

local function setRenderingRGB(self, rgb, merge, final, sourceField)
  applyRenderingRGB(self, rgb, sourceField)
  _LUIColorPickerUpdateControler(self, merge)
end

local function setRGBDisplayComponent(self, componentIndex, value, merge, final, sourceField)
  if isRGBPickerDisplay(self) then
    local rgb = copyRGB(self._PickerRGB)
    rgb[componentIndex] = clampMin0(value)
    setPickerRGB(self, rgb, merge, final, sourceField)
  else
    local rgb = copyRGB(self._RGB)
    rgb[componentIndex] = clampMin0(value)
    setRenderingRGB(self, rgb, merge, final, sourceField)
  end
end

local function setRGBDisplaySpace(self, space)
  self._RGBDisplaySpace = space == RGB_DISPLAY_PICKER and RGB_DISPLAY_PICKER or RGB_DISPLAY_RENDERING
  updateVisuals(self)
end

toggleRGBDisplaySpace = function(self)
  if isRGBPickerDisplay(self) then
    setRGBDisplaySpace(self, RGB_DISPLAY_RENDERING)
  else
    setRGBDisplaySpace(self, RGB_DISPLAY_PICKER)
  end
end

function LUIColorPickerSetRGB(self, rgb, sourceField)
  applyRenderingRGB(self, rgb, sourceField)
end

function LUIColorPickerSetHSVM(self, h, s, v, m, merge, final, forceH, forceMul, sourceField, allowExtended)
  h = tonumber(h) or 0
  if h < 0 or h > 1 then
    h = h % 1
    if h < 0 then
      h = h + 1
    end
  end
  s = allowExtended and clampMin0(s) or clamp01(s)
  v = allowExtended and clampMin0(v) or clamp01(v)
  if s == 0 and not forceH and self._HSV[1] ~= nil then
    h = self._HSV[1]
  end
  self._HSV[1] = h
  self._HSV[2] = s
  self._HSV[3] = v
  self._PickerRGB = sanitizePickerRGB(hsvToPickerRGB(h, s, v))
  self._RGB = sanitizeRenderingRGB(ocio.pickertorendering(self._PickerRGB))
  self._Temperature = clampTemperature(ocio.renderingtotemperature(self._RGB))
  updateVisuals(self, sourceField)
  _LUIColorPickerUpdateControler(self, merge)
end

function LUIColorPickerSetT(self, temperature, merge, final, sourceField)
  temperature = clampTemperature(temperature)
  self._Temperature = temperature
  applyRenderingRGB(self, ocio.temperaturetorendering(temperature), sourceField or "K")
  _LUIColorPickerUpdateControler(self, merge)
end

local function setHexText(self, text, merge, final, sourceField)
  local pickerRGB = LUIColorPickerParseHex(text)
  if pickerRGB then
    setPickerRGB(self, pickerRGB, merge, final, sourceField)
    return true
  end
  return false
end

local function createField(self, name, labelText, desc, onChange)
  local label = LUITextCreate(name .. "Label", self)
  local box = LUIEditBoxCreate(name .. "Edit", self, LUIDefaultEditBoxStyle)
  local edit = LUIEditGetEdit(box)

  local function commitFieldText(text)
    if self._SuspendFieldCallbacks then
      return
    end
    if type(text) == "string" then
      onChange(text)
    end
  end

  local function getCurrentFieldText()
    if edit and type(edit._Text) == "string" then
      return edit._Text
    end
    if box._edit and type(box._edit._Text) == "string" then
      return box._edit._Text
    end
    if type(box._Text) == "string" then
      return box._Text
    end
    return nil
  end

  LUITextSetText(label, labelText .. ":")
  LUIWindowSetColor(label, COLOR_LABEL)
  LUIEditBoxSetDescription(box, desc)

  box.editchanged = function(_, text)
    commitFieldText(text)
  end

  local defaultOnKeyDown = edit and edit.onKeyDown or nil
  edit.onLostFocus = function(editSelf)
    LUIEditBoxEditVT.onLostFocus(editSelf)
    commitFieldText(getCurrentFieldText())
    refreshFields(self)
  end

  edit.onKeyDown = function(editSelf, c, modifier, _repeat)
    if c == LUI_KEY_RETURN and modifier == 0 then
      commitFieldText(getCurrentFieldText())
      refreshFields(self)
      return true
    end
    if defaultOnKeyDown then
      return defaultOnKeyDown(editSelf, c, modifier, _repeat)
    end
  end

  self._Fields[name] = {
    Label = label,
    Box = box,
    Edit = edit
  }
end

local function createPickButton(self)
  local button = LUITextButtonCreate("pickButton", self, nil, "Pick")
  LUIVTSetClass(button, LUIColorPickerButtonVT)

  self._PickButton = button
  updatePickButton(self)
end

local function createRGBSpaceButton(self)
  local button = LUITextButtonCreate("rgbSpaceButton", self, nil, "RGB: View")
  LUIVTSetClass(button, LUIColorPickerRGBSpaceButtonVT)
  button.Layer = 50
  button.buttonclicked = function()
    toggleRGBDisplaySpace(self)
  end

  self._RGBSpaceButton = button
  updateRGBSpaceButton(self)
end

local function createBar(self, name)
  local bar = LUIQuadCreate(name .. "Bar", self)
  local marker = LUIQuadCreate("marker", bar)

  LUIVTSetClass(bar, LUIColorPickerBarVT)
  bar.Component = name
  bar._Owner = self
  bar._Marker = marker
  bar.BorderColor = LUIRGBA(18, 18, 18, 255)

  if name == "H" then
    LUIQuadSetTexture(bar, HUE_TEXTURE, false)
  else
    LUIQuadSetTexture(bar, "white", false)
  end

  LUIQuadSetTexture(marker, "white", false)
  LUIWindowSetColor(marker, COLOR_MARKER)
  marker.Layer = 10
  marker.NoHitTest = true

  if name == "K" then
    bar._RampSegments = {}
    for index = 1, TEMP_RAMP_SEGMENT_COUNT do
      local quad = LUIQuadCreate("segment" .. index, bar)
      LUIQuadSetTexture(quad, "white", false)
      quad.NoHitTest = true
      quad.Layer = 1
      bar._RampSegments[index] = quad
    end
    updateTemperatureRampSegments(bar)
  end

  self._Bars[name] = bar
end

local function createSwatch(self, name, index, kind)
  local swatch = LUIQuadCreate(name .. index, self)
  LUIVTSetClass(swatch, LUIColorPickerSwatchVT)
  LUIQuadSetTexture(swatch, "white", false)
  swatch._EnableRDown = true
  swatch._EnableRCDown = true
  swatch.Index = index
  swatch.Kind = kind
  swatch._Owner = self
  swatch.BorderColor = COLOR_EMPTY_BORDER
  swatch.Color = COLOR_EMPTY_SWATCH
  return swatch
end

local function applySwatchColor(owner, rgb)
  if rgb then
    setPickerRGB(owner, sanitizePickerRGB(ocio.renderingtopicker(rgb)), false, true, nil)
  end
end

local function saveFavoriteAt(index, rgb)
  local favorites = getFavoritePalette()
  index = math.max(1, math.min(FAVORITE_COUNT, index))
  favorites[index] = sanitizeRenderingRGB(rgb)
  while #favorites > FAVORITE_COUNT do
    table.remove(favorites)
  end
  setFavoritePalette(favorites)
end

local function removeFavoriteAt(index)
  local favorites = getFavoritePalette()
  index = tonumber(index)
  if not index or index < 1 or index > #favorites then
    return false
  end
  table.remove(favorites, index)
  setFavoritePalette(favorites)
  return true
end

local function updateTabButtons(self)
  local tabs = {
    {self._ColorTab, self._Mode == "color"},
    {self._TempTab, self._Mode == "temp"},
    {self._PresetTab, self._Mode == "preset"}
  }
  for _, item in ipairs(tabs) do
    local tab = item[1]
    local active = item[2]
    LUIWindowSetColor(tab, active and COLOR_TAB_ACTIVE or COLOR_TAB_INACTIVE)
    if tab._Children and tab._Children.text then
      LUITextSetColor(tab._Children.text, active and COLOR_WHITE or COLOR_LABEL)
    end
  end
end

local function updateModeVisibility(self)
  local showPickerTools = true
  local showPickButton = self._Mode == "color" or self._Mode == "temp"
  local hexField = self._Fields.Hex

  if showPickerTools then
    LUIWindowShow(self._Wheel)
    LUIWindowShow(self._WheelShade)
    LUIWindowShow(self._WheelMarker)
    LUIWindowShow(self._PreviewBefore)
    LUIWindowShow(self._Preview)
    if self._PreviewBeforeLabel then
      LUIWindowHide(self._PreviewBeforeLabel)
    end
    if self._PreviewAfterLabel then
      LUIWindowHide(self._PreviewAfterLabel)
    end
    LUIWindowShow(hexField.Label)
    LUIWindowShow(hexField.Box)
  else
    LUIWindowHide(self._Wheel)
    LUIWindowHide(self._WheelShade)
    LUIWindowHide(self._WheelMarker)
    LUIWindowHide(self._PreviewBefore)
    LUIWindowHide(self._Preview)
    if self._PreviewBeforeLabel then
      LUIWindowHide(self._PreviewBeforeLabel)
    end
    if self._PreviewAfterLabel then
      LUIWindowHide(self._PreviewAfterLabel)
    end
    LUIWindowHide(hexField.Label)
    LUIWindowHide(hexField.Box)
  end

  if self._PickButton then
    if showPickButton then
      LUIWindowShow(self._PickButton)
    else
      LUIWindowHide(self._PickButton)
    end
  end

  if self._RGBSpaceButton then
    if self._Mode == "color" then
      LUIWindowShow(self._RGBSpaceButton)
    else
      LUIWindowHide(self._RGBSpaceButton)
    end
  end

  local colorRows = {"R", "G", "B", "H", "S", "V"}
  for _, name in ipairs(colorRows) do
    local field = self._Fields[name]
    local bar = self._Bars[name]
    if self._Mode == "color" then
      LUIWindowShow(field.Label)
      LUIWindowShow(field.Box)
      LUIWindowShow(bar)
      LUIWindowShow(bar._Marker)
    else
      LUIWindowHide(field.Label)
      LUIWindowHide(field.Box)
      LUIWindowHide(bar)
      LUIWindowHide(bar._Marker)
    end
  end

  do
    local field = self._Fields.K
    local bar = self._Bars.K
    if self._Mode == "temp" then
      LUIWindowShow(field.Label)
      LUIWindowShow(field.Box)
      LUIWindowShow(bar)
      LUIWindowShow(bar._Marker)
    else
      LUIWindowHide(field.Label)
      LUIWindowHide(field.Box)
      LUIWindowHide(bar)
      LUIWindowHide(bar._Marker)
    end
  end

  for _, item in ipairs(self._TempPresetButtons or {}) do
    if self._Mode == "temp" then
      LUIWindowShow(item.Button)
    else
      LUIWindowHide(item.Button)
    end
  end

  for _, swatch in ipairs(self._FavoriteSwatches or {}) do
    if self._Mode == "color" then
      LUIWindowShow(swatch)
    else
      LUIWindowHide(swatch)
    end
  end

  if self._PresetRows then
    for _, row in ipairs(self._PresetRows) do
      if self._Mode == "preset" then
        LUIWindowShow(row.Label)
        for _, swatch in ipairs(row.Swatches) do
          if swatch._SchemeActive then
            LUIWindowShow(swatch)
          else
            LUIWindowHide(swatch)
          end
        end
      end
      if self._Mode ~= "preset" then
        LUIWindowHide(row.Label)
        for _, swatch in ipairs(row.Swatches) do
          LUIWindowHide(swatch)
        end
      end
    end
  end

  updateTabButtons(self)
end

local function setMode(self, mode)
  if mode == "temp" then
    self._Mode = "temp"
  elseif mode == "preset" then
    self._Mode = "preset"
  else
    self._Mode = "color"
  end
  updateModeVisibility(self)
  self:onSizeChanged()
  LUIWindowInvalidateBatch(self)
end

function LUIColorPickerVT:onDestroy()
  if rawget(_G, "LUIColorPickerWindow") == self then
    rawset(_G, "LUIColorPickerWindow", nil)
  end
  if LUIColorPicker == self then
    LUIOnEndColorPicker()
  end
end

function LUIColorPickerVT:onStartPickColor(pickButton, add, hover, oneShot)
  if self.PickButton and self.PickButton ~= pickButton then
    self.PickButton.ForceColor = nil
    if self.PickButton.updateState then
      self.PickButton:updateState()
    end
  end
  self.PickButton = pickButton or self._PickButton
  if add then
    self._CurrentPicked = {0, 0, 0}
    self._NbPicked = 0
  else
    self._CurrentPicked = nil
    self._NbPicked = nil
  end
  self._HoverPicking = hover == true
  self._OneShotPickColor = oneShot == true
  self._PickingColor = true
  updatePickButton(self)
  LUIOnStartColorPicker(self)
  if self._HoverPicking and not self._PickTimerActive then
    self._PickTimerActive = true
    self:onPickColor(LUIWindowPickColor())
    LUIUpdateDisplay()
    LUITimerAdd(self, HOVER_PICK_TIMER_DELAY)
  end
end

function LUIColorPickerVT:onToggleTemp()
end

function LUIColorPickerVT:onPickColor(rgb)
  if rgb then
    rgb = sanitizeRenderingRGB(ocio.pickertorendering(sanitizePickerRGB(rgb)))
    if self._CurrentPicked then
      self._NbPicked = (self._NbPicked or 0) + 1
      self._CurrentPicked[1] = (self._CurrentPicked[1] or 0) + rgb[1]
      self._CurrentPicked[2] = (self._CurrentPicked[2] or 0) + rgb[2]
      self._CurrentPicked[3] = (self._CurrentPicked[3] or 0) + rgb[3]
      rgb = {
        self._CurrentPicked[1] / self._NbPicked,
        self._CurrentPicked[2] / self._NbPicked,
        self._CurrentPicked[3] / self._NbPicked
      }
    end
    applyRenderingRGB(self, rgb)
    _LUIColorPickerUpdateControler(self, true)
    if self._OneShotPickColor then
      self._OneShotPickColor = false
      LUIOnEndColorPicker()
    end
  end
end

function LUIColorPickerVT:onEndPickColor()
  self._HoverPicking = false
  self._OneShotPickColor = false
  self._PickingColor = false
  if self.PickButton then
    self.PickButton.ForceColor = nil
    if self.PickButton.updateState then
      self.PickButton:updateState()
    end
  end
  updatePickButton(self)
end

function LUIColorPickerVT:onUpdateControl2(updatedByControl)
  local rgb = LUIControlGetValue(self)
  LUIColorPickerSetRGB(self, rgb)
  if not self._SyncingControlValue then
    setOriginalRGB(self, rgb)
  end
end

function LUIColorPickerVT:onUpdateView2()
  return LUIColorPickerVT.Parent.onUpdateView2(self)
end

function LUIColorPickerVT:onTimer(last)
  if not last then
    return
  end
  if self.Destroyed or LUIWindowIsDestroyed(self) then
    self._PickTimerActive = false
    return
  end
  if self._PickingColor and self._HoverPicking then
    self:onPickColor(LUIWindowPickColor())
    LUIUpdateDisplay()
    LUITimerAdd(self, HOVER_PICK_TIMER_DELAY)
  else
    self._PickTimerActive = false
  end
end

function LUIColorPickerVT:onKeyDown(c, modifier)
  if c == LUI_KEY_C and modifier == LUI_MODIFIER_CTRL then
    LUIClipboardPut(LUICopyObjectIntoBuffer(self._RGB, LUIPSTypeColor))
    return true
  elseif c == LUI_KEY_V and modifier == LUI_MODIFIER_CTRL then
    local text = LUIClipboardGet()
    if setHexText(self, text, false, true, "Hex") then
      return true
    end
    local rgb = LUIPasteObjectFromClipboard(LUIPSTypeColor)
    if rgb and type(rgb[1]) == "number" and type(rgb[2]) == "number" and type(rgb[3]) == "number" then
      self._SyncingControlValue = true
      LUIControlSetValue(self, rgb, nil, false)
      self._SyncingControlValue = false
      return true
    end
  end
  return false
end

function LUIColorPickerVT:onSizeChanged()
  if not (
    self._Fields and self._Bars and
    self._Fields.Hex and self._Fields.R and self._Fields.G and self._Fields.B and
    self._Fields.H and self._Fields.S and self._Fields.V and self._Fields.K and
    self._Bars.R and self._Bars.G and self._Bars.B and
    self._Bars.H and self._Bars.S and self._Bars.V and self._Bars.K
  ) then
    return
  end

  local w = LUIWindowGetW(self)
  local pad = 10
  local wheelSize = 118
  local previewH = 16
  local hexH = 20
  local sliderRowH = 22
  local leftX = pad
  local leftY = pad + 4
  local rightX = leftX + wheelSize + 12
  local rightW = w - rightX - pad
  local labelW = 14
  local numberW = 36
  local rowH = sliderRowH
  local barH = 18
  local fieldGap = 4
  local barGap = 8
  local tabH = 19
  local swatchSize = FAVORITE_SWATCH_SIZE
  local presetSize = PRESET_SWATCH_SIZE
  local presetGap = PRESET_SWATCH_GAP
  local topY = pad + 26
  local barX = rightX + labelW + fieldGap + numberW + barGap
  local barW = math.max(120, rightW - (barX - rightX))
  local previewY = leftY + wheelSize + 8
  local previewW = wheelSize
  local previewTopY = previewY
  local previewBottomY = previewTopY + previewH + PREVIEW_SWATCH_GAP
  local hexY = previewBottomY + previewH + 8
  local hexRight = leftX + wheelSize
  local pickX = hexRight - PICK_BUTTON_W
  local hexBoxX = leftX + 28
  local favoriteY = hexY + math.floor((hexH - swatchSize) * 0.5)
  local favoriteRangeX = math.max(rightX, pickX + PICK_BUTTON_W + 10)
  local favoriteGap = FAVORITE_SWATCH_GAP
  local rgbSpaceButtonX = w - pad - RGB_SPACE_BUTTON_W
  local presetContentX = rightX
  local presetContentY = topY + 1
  local presetLabelW = 82
  local presetSwatchX = presetContentX + presetLabelW + 6
  local presetRowH = presetSize + PRESET_ROW_GAP
  local presetTextY = math.floor((presetSize - 14) * 0.5)
  local tempPresetCols = 4
  local tempPresetX = rightX + math.max(0, math.floor((rightW - (TEMP_PRESET_BUTTON_W * tempPresetCols + TEMP_PRESET_GAP * (tempPresetCols - 1))) * 0.5))
  local tempPresetY = topY + rowH + 8

  LUIWindowSetX(self._ColorTab, rightX)
  LUIWindowSetY(self._ColorTab, pad)
  LUIWindowSetW(self._ColorTab, 46)
  LUIWindowSetH(self._ColorTab, tabH)

  LUIWindowSetX(self._TempTab, rightX + 50)
  LUIWindowSetY(self._TempTab, pad)
  LUIWindowSetW(self._TempTab, 44)
  LUIWindowSetH(self._TempTab, tabH)

  LUIWindowSetX(self._PresetTab, rightX + 98)
  LUIWindowSetY(self._PresetTab, pad)
  LUIWindowSetW(self._PresetTab, 54)
  LUIWindowSetH(self._PresetTab, tabH)

  LUIWindowSetX(self._Wheel, leftX)
  LUIWindowSetY(self._Wheel, leftY)
  LUIWindowSetW(self._Wheel, wheelSize)
  LUIWindowSetH(self._Wheel, wheelSize)

  LUIWindowSetX(self._WheelShade, 0)
  LUIWindowSetY(self._WheelShade, 0)
  LUIWindowSetW(self._WheelShade, 0, 1)
  LUIWindowSetH(self._WheelShade, 0, 1)

  LUIWindowSetX(self._Preview, leftX)
  LUIWindowSetY(self._Preview, previewTopY)
  LUIWindowSetW(self._Preview, previewW)
  LUIWindowSetH(self._Preview, previewH)

  LUIWindowSetX(self._PreviewBefore, leftX)
  LUIWindowSetY(self._PreviewBefore, previewBottomY)
  LUIWindowSetW(self._PreviewBefore, previewW)
  LUIWindowSetH(self._PreviewBefore, previewH)

  local hexField = self._Fields.Hex
  LUIWindowSetX(hexField.Label, leftX)
  LUIWindowSetY(hexField.Label, hexY + 3)
  LUIWindowSetW(hexField.Label, 24)
  LUIWindowSetH(hexField.Label, hexH)
  LUIWindowSetX(hexField.Box, leftX + 28)
  LUIWindowSetY(hexField.Box, hexY)
  LUIWindowSetW(hexField.Box, math.max(48, pickX - PICK_BUTTON_GAP - hexBoxX))
  LUIWindowSetH(hexField.Box, hexH)
  if self._PickButton then
    LUIWindowSetX(self._PickButton, pickX)
    LUIWindowSetY(self._PickButton, hexY)
    LUIWindowSetW(self._PickButton, PICK_BUTTON_W)
    LUIWindowSetH(self._PickButton, PICK_BUTTON_H)
  end

  do
    local rows = {"R", "G", "B", "H", "S", "V"}
    for index, name in ipairs(rows) do
      local y = topY + (index - 1) * rowH
      local field = self._Fields[name]
      local bar = self._Bars[name]

      LUIWindowSetX(field.Label, rightX)
      LUIWindowSetY(field.Label, y + 2)
      LUIWindowSetW(field.Label, labelW)
      LUIWindowSetH(field.Label, rowH)

      LUIWindowSetX(field.Box, rightX + labelW + fieldGap)
      LUIWindowSetY(field.Box, y)
      LUIWindowSetW(field.Box, numberW)
      LUIWindowSetH(field.Box, rowH - 1)

      LUIWindowSetX(bar, barX)
      LUIWindowSetY(bar, y + math.floor((rowH - barH) * 0.5))
      LUIWindowSetW(bar, barW)
      LUIWindowSetH(bar, barH)

      LUIWindowSetW(bar._Marker, 5)
      LUIWindowSetH(bar._Marker, barH + 6)
      LUIWindowSetY(bar._Marker, -3)
    end
  end

  do
    local field = self._Fields.K
    local bar = self._Bars.K
    local y = topY

    LUIWindowSetX(field.Label, rightX)
    LUIWindowSetY(field.Label, y + 2)
    LUIWindowSetW(field.Label, labelW)
    LUIWindowSetH(field.Label, rowH)

    LUIWindowSetX(field.Box, rightX + labelW + fieldGap)
    LUIWindowSetY(field.Box, y)
    LUIWindowSetW(field.Box, numberW)
    LUIWindowSetH(field.Box, rowH - 1)

    LUIWindowSetX(bar, barX)
    LUIWindowSetY(bar, y + math.floor((rowH - barH) * 0.5))
    LUIWindowSetW(bar, barW)
    LUIWindowSetH(bar, barH)

    layoutTemperatureRampSegments(bar, barW, barH)

    LUIWindowSetW(bar._Marker, 5)
    LUIWindowSetH(bar._Marker, barH + 6)
    LUIWindowSetY(bar._Marker, -3)
  end

  for index, swatch in ipairs(self._FavoriteSwatches) do
    LUIWindowSetX(swatch, favoriteRangeX + (index - 1) * (swatchSize + favoriteGap))
    LUIWindowSetY(swatch, favoriteY)
    LUIWindowSetW(swatch, swatchSize)
    LUIWindowSetH(swatch, swatchSize)
  end

  if self._RGBSpaceButton then
    LUIWindowSetX(self._RGBSpaceButton, rgbSpaceButtonX)
    LUIWindowSetY(self._RGBSpaceButton, favoriteY)
    LUIWindowSetW(self._RGBSpaceButton, RGB_SPACE_BUTTON_W)
    LUIWindowSetH(self._RGBSpaceButton, RGB_SPACE_BUTTON_H)
  end

  for rowIndex, row in ipairs(self._PresetRows or {}) do
    local y = presetContentY + (rowIndex - 1) * presetRowH
    LUIWindowSetX(row.Label, presetContentX)
    LUIWindowSetY(row.Label, y + presetTextY)
    LUIWindowSetW(row.Label, presetLabelW)
    LUIWindowSetH(row.Label, 14)

    for swatchIndex, swatch in ipairs(row.Swatches) do
      LUIWindowSetX(swatch, presetSwatchX + (swatchIndex - 1) * (presetSize + presetGap))
      LUIWindowSetY(swatch, y)
      LUIWindowSetW(swatch, presetSize)
      LUIWindowSetH(swatch, presetSize)
    end
  end

  for index, item in ipairs(self._TempPresetButtons or {}) do
    local col = (index - 1) % tempPresetCols
    local row = math.floor((index - 1) / tempPresetCols)
    LUIWindowSetX(item.Button, tempPresetX + col * (TEMP_PRESET_BUTTON_W + TEMP_PRESET_GAP))
    LUIWindowSetY(item.Button, tempPresetY + row * (TEMP_PRESET_BUTTON_H + TEMP_PRESET_GAP))
    LUIWindowSetW(item.Button, TEMP_PRESET_BUTTON_W)
    LUIWindowSetH(item.Button, TEMP_PRESET_BUTTON_H)
  end

  updateModeVisibility(self)
  _LUIColorPickerUpdateMarkers(self)
end

local function updateWheelFromMouse(wheel, x, y, merge, final, allowOutside)
  local px = (wheel._W ~= 0) and (x / wheel._W) or 0
  local py = (wheel._H ~= 0) and (y / wheel._H) or 0
  if not allowOutside and not isPointInsideWheel(px, py) then
    return false
  end
  local h, s = wheelPointToHSV(px, py, wheel._Parent._HSV[1])
  LUIColorPickerSetHSVM(wheel._Parent, h, s, wheel._Parent._HSV[3], 1, merge, final, s > 0, true)
  return true
end

local function updateBarFromMouse(bar, x, merge, final)
  local value = (bar._W ~= 0) and clamp01(x / bar._W) or 0
  local picker = bar._Owner
  if bar.Component == "R" then
    setRGBDisplayComponent(picker, 1, value, merge, final, "R")
  elseif bar.Component == "G" then
    setRGBDisplayComponent(picker, 2, value, merge, final, "G")
  elseif bar.Component == "B" then
    setRGBDisplayComponent(picker, 3, value, merge, final, "B")
  elseif bar.Component == "H" then
    LUIColorPickerSetHSVM(picker, value, picker._HSV[2], picker._HSV[3], 1, merge, final, true, true, "H")
  elseif bar.Component == "S" then
    LUIColorPickerSetHSVM(picker, picker._HSV[1], value, picker._HSV[3], 1, merge, final, false, true, "S")
  elseif bar.Component == "V" then
    LUIColorPickerSetHSVM(picker, picker._HSV[1], picker._HSV[2], value, 1, merge, final, false, true, "V")
  elseif bar.Component == "K" then
    LUIColorPickerSetT(picker, normalizedToTemperature(value), merge, final, "K")
  end
end

function LUIColorPickerWheelVT:onLDrag(x, y, lx, ly)
  if not self._DragStartedInside then
    return x, y
  end
  self._Parent._Interactive = true
  updateWheelFromMouse(self, lx, ly, true, false, true)
  return x, y
end

function LUIColorPickerWheelVT:onLDown(x, y)
  self._DragStartedInside = updateWheelFromMouse(self, x, y)
end

function LUIColorPickerWheelVT:onLDragEnd(x, y)
  if self._DragStartedInside then
    updateWheelFromMouse(self, x, y, true, true, true)
  end
  self._DragStartedInside = false
  self._Parent._Interactive = false
end

function LUIColorPickerBarVT:onLDrag(x, y, lx, ly)
  self._Owner._Interactive = true
  updateBarFromMouse(self, lx, true)
  return x, y
end

function LUIColorPickerBarVT:onLDown(x, y)
  updateBarFromMouse(self, x)
end

function LUIColorPickerBarVT:onLDragEnd(x, y)
  self._Owner._Interactive = false
  updateBarFromMouse(self, x, true, true)
end

function LUIColorPickerSwatchVT:onLDown(x, y)
  if self._RGB then
    applySwatchColor(self._Owner, self._RGB)
  elseif self.Kind == "favorite" then
    saveFavoriteAt(self.Index, self._Owner._RGB)
    updateSwatches(self._Owner)
    LUIUpdateDisplay()
  end
end

function LUIColorPickerSwatchVT:onRDown(x, y)
  if self.Kind == "favorite" and removeFavoriteAt(self.Index) then
    updateSwatches(self._Owner)
    LUIUpdateDisplay()
  end
end

function LUIColorPickerSwatchVT:onRCDown(x, y)
  if self.Kind == "favorite" then
    saveFavoriteAt(self.Index, self._Owner._RGB)
    updateSwatches(self._Owner)
    LUIUpdateDisplay()
  end
end

function LUIColorPickerSwatchVT:onLDoubleClick(x, y)
  if self.Kind == "favorite" then
    saveFavoriteAt(self.Index, self._Owner._RGB)
    updateSwatches(self._Owner)
  end
end

function LUIColorPickerCreate(name, parent, style)
  local self = LUIWindowCreate(name, parent, style)
  LUIVTSetClass(self, LUIColorPickerVT)

  self.Focusable = true
  self._EnableRDown = true
  self._Interactive = false
  self._Mode = "color"
  self._HSV = {0, 0, 1}
  self._RGB = {1, 1, 1}
  self._PickerRGB = {1, 1, 1}
  self._RGBDisplaySpace = RGB_DISPLAY_PICKER
  self._OriginalRGB = {1, 1, 1}
  self._Temperature = TEMP_MIN
  self._Fields = {}
  self._Bars = {}
  self._FavoriteSwatches = {}
  self._PresetRows = {}
  self._TempPresetButtons = {}
  self._PickingColor = false
  self._HoverPicking = false
  self._PickTimerActive = false

  self._Wheel = LUIQuadCreate("wheel", self)
  LUIVTSetClass(self._Wheel, LUIColorPickerWheelVT)
  LUIQuadSetTexture(self._Wheel, WHEEL_TEXTURE, true)

  self._WheelShade = LUIQuadCreate("wheelShade", self._Wheel)
  LUIQuadSetTexture(self._WheelShade, WHEEL_TEXTURE, true)

  self._WheelMarker = LUIQuadCreate("wheelMarker", self._Wheel)
  LUIQuadSetTexture(self._WheelMarker, "color_picker_picker.png", true)

  self._PreviewBefore = createSwatch(self, "previewBefore", 1, "preview")
  self._Preview = createSwatch(self, "previewAfter", 2, "preview")

  self._ColorTab = LUITextButtonCreate("colorTab", self, nil, "Color")
  self._TempTab = LUITextButtonCreate("tempTab", self, nil, "Temp")
  self._PresetTab = LUITextButtonCreate("presetTab", self, nil, "Preset")
  self._ColorTab.buttonclicked = function()
    setMode(self, "color")
  end
  self._TempTab.buttonclicked = function()
    setMode(self, "temp")
  end
  self._PresetTab.buttonclicked = function()
    setMode(self, "preset")
  end

  createField(self, "Hex", "Hex", STRING_DESC, function(text)
    setHexText(self, text, false, true, "Hex")
  end)
  createPickButton(self)

  createField(self, "R", "R", NUMBER_DESC, function(text)
    local value = parseEditableNumber(text)
    if value ~= nil then
      setRGBDisplayComponent(self, 1, value, false, true, "R")
    end
  end)

  createField(self, "G", "G", NUMBER_DESC, function(text)
    local value = parseEditableNumber(text)
    if value ~= nil then
      setRGBDisplayComponent(self, 2, value, false, true, "G")
    end
  end)

  createField(self, "B", "B", NUMBER_DESC, function(text)
    local value = parseEditableNumber(text)
    if value ~= nil then
      setRGBDisplayComponent(self, 3, value, false, true, "B")
    end
  end)

  createField(self, "H", "H", NUMBER_DESC, function(text)
    local value = parseEditableNumber(text)
    if value ~= nil then
      LUIColorPickerSetHSVM(self, value, self._HSV[2], self._HSV[3], 1, false, true, true, true, "H", true)
    end
  end)

  createField(self, "S", "S", NUMBER_DESC, function(text)
    local value = parseEditableNumber(text)
    if value ~= nil then
      LUIColorPickerSetHSVM(self, self._HSV[1], value, self._HSV[3], 1, false, true, false, true, "S", true)
    end
  end)

  createField(self, "V", "V", NUMBER_DESC, function(text)
    local value = parseEditableNumber(text)
    if value ~= nil then
      LUIColorPickerSetHSVM(self, self._HSV[1], self._HSV[2], value, 1, false, true, false, true, "V", true)
    end
  end)

  createField(self, "K", "K", NUMBER_DESC, function(text)
    local value = parseEditableNumber(text)
    if value ~= nil then
      LUIColorPickerSetT(self, value, false, true, "K")
    end
  end)

  createBar(self, "R")
  createBar(self, "G")
  createBar(self, "B")
  createBar(self, "H")
  createBar(self, "S")
  createBar(self, "V")
  createBar(self, "K")

  for index = 1, FAVORITE_COUNT do
    self._FavoriteSwatches[index] = createSwatch(self, "favoriteSwatch", index, "favorite")
  end

  for rowIndex, scheme in ipairs(PRESET_SCHEME_DEFS) do
    local row = {
      Label = LUITextCreate("presetLabel" .. rowIndex, self),
      Swatches = {}
    }
    LUITextSetText(row.Label, scheme.Name)
    LUIWindowSetColor(row.Label, COLOR_LABEL)
    for swatchIndex = 1, PRESET_MAX_SWATCHES do
      row.Swatches[swatchIndex] = createSwatch(self, "presetSwatch" .. rowIndex .. "_", swatchIndex, "preset")
    end
    self._PresetRows[rowIndex] = row
  end

  for index, def in ipairs(TEMP_PRESET_DEFS) do
    local button = LUITextButtonCreate("tempPreset" .. index, self, nil, def.Label)
    button.buttonclicked = function()
      LUIColorPickerSetT(self, def.Temp, false, true, "K")
    end
    self._TempPresetButtons[index] = {
      Button = button,
      Temp = def.Temp,
      Name = def.Name
    }
  end

  createRGBSpaceButton(self)

  ViewPlug(self, "Input", LUI_PLUG_NO_SERIAL + LUI_PLUG_THROUGH, LUIPSTypeColor)
  rawset(_G, "LUIColorPickerWindow", self)

  LUIColorPickerSetRGB(self, {1, 1, 1})
  setOriginalRGB(self, self._RGB)
  self:onSizeChanged()
  updateSwatches(self)
  setMode(self, "color")
  self:setfocus()

  return self
end

function LUIColorPickerBoxCreate(attributes, x, y)
  local self = LUITitledWindowCreate(1, LUIRootWindow, nil, attributes)
  LUIWindowSetW(self, PICKER_WIDTH)
  LUIWindowSetH(self, PICKER_HEIGHT)
  local picker = LUIColorPickerCreate("properties", self)
  ViewPlug(self, "Input", LUI_PLUG_NO_SERIAL + LUI_PLUG_THROUGH, LUIPSTypeColor)
  LUIPlugAddDependencies(picker.Input, self.Input)
  LUITitleWindowAroundCursor(self, x, y)
  LUITitledWindowSetTitle(self, "Color Picker")
  self:show()
  LUIWindowSetFocus(picker)
  return self
end
