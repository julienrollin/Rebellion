require("ga_camera_gizmo_dof")
require("ga_camera_gizmo_focal")
require("ga_camera_gizmo_stereo")
require("lui_gizmo_cylinder_fallof")
require("lui_gizmo_cone_fallof")
require("lui_gizmo_sphere_fallof")
require("ga_camera_gizmo_fov")
require("ga_light_gizmo_scale")

local function LUIHasFlag(mask, flag)
  return mask and mask % (flag * 2) >= flag
end

local GIZMO_INDEXES_BY_TOOL = {
  move = {1, 2, 3, 4, 5, 6, 7},
  rotate = {12, 13, 14, 15, 16},
  scale = {17, 18, 19, 20, 21, 22, 23}
}

local function LUIIsRotateGizmo(object)
  return object and type(object) ~= "string" and (isclassof(object, "LUIGizmoRotate") or isclassof(object, "LUIGizmoMultiRotate"))
end

local function LUIGetTransformToolName()
  local globals = rawget(_G, "LUIGlobals")
  return globals and globals.TransformTool and LUIPlugGetValue(globals.TransformTool)
end

local function LUIGetCurrentTool()
  return rawget(_G, "LUIToolCurrent")
end

for _, name in ipairs({
  "LUIIsGizmoPivotEditActive",
  "LUISetGizmoPivotEditMode",
  "LUIToggleGizmoPivotEditMode",
  "LUIResetPivotTransform",
  "LUIGetPivotMatrix",
  "LUIGetGizmoDisplayMatrix",
  "LUIGetGizmoPivotEditPlug",
  "LUIBeginGizmoPivotEditDrag",
  "LUIEndGizmoPivotEditDrag",
  "LUIBeginGizmoPivotTransformDrag",
  "LUIEndGizmoPivotTransformDrag",
  "LUIBeginGizmoPivotFollowDrag",
  "LUIEndGizmoPivotFollowDrag",
  "LUIApplyGizmoPivotFollowTranslation",
  "LUIApplyGizmoPivotTranslation",
  "LUIApplyGizmoPivotRotation",
  "LUIApplyGizmoPivotScale"
}) do
  rawset(_G, name, nil)
end

local function LUIGetActiveToolGizmos()
  local indexes = GIZMO_INDEXES_BY_TOOL[LUIGetTransformToolName()]
  local tool = LUIGetCurrentTool()
  if not indexes or not tool or not tool._PrimGizmos then
    return
  end
  local gizmos = {}
  for _, index in ipairs(indexes) do
    local gizmo = tool._PrimGizmos[index]
    if gizmo then
      gizmos[gizmo] = true
    end
  end
  return gizmos
end

local function LUISafeIndex(object, key)
  if not object or type(object) == "string" then
    return
  end
  local ok, value = pcall(function()
    return object[key]
  end)
  if ok then
    return value
  end
end

local function LUIGetObjectOwner(object)
  local getowner = LUISafeIndex(object, "getowner")
  if type(getowner) ~= "function" then
    return
  end
  local ok, owner = pcall(getowner, object)
  if ok then
    return owner
  end
end

local function LUIResolveActiveGizmoFromObject(object, activeGizmos)
  local current = object
  for _ = 1, 4 do
    if not current or type(current) == "string" then
      return
    end
    if activeGizmos[current] then
      return current
    end
    local gizmo = LUISafeIndex(current, "_Gizmo")
    if gizmo and activeGizmos[gizmo] then
      return gizmo
    end
    current = LUIGetObjectOwner(current)
  end
end

local function LUIResolveActiveGizmoFromObjects(objects, activeGizmos)
  if not objects or not activeGizmos then
    return
  end
  for _, object in ipairs(objects) do
    local gizmo = LUIResolveActiveGizmoFromObject(object, activeGizmos)
    if gizmo then
      return gizmo
    end
  end
end

local function LUIGetActiveMultiRotateGizmo()
  local globals = rawget(_G, "LUIGlobals")
  local tool = LUIGetCurrentTool()
  if not globals or not tool or LUIPlugGetValue(globals.TransformTool) ~= "rotate" then
    return
  end
  local gizmo = tool._PrimGizmos and tool._PrimGizmos[16]
  if gizmo and gizmo.PrimitiveSelected and LUIPlugGetValue(gizmo.PrimitiveSelected) then
    return gizmo
  end
end

local function LUIGetCustomMultiRotateHit(view, x, y)
  local gizmo = LUIGetActiveMultiRotateGizmo()
  if not gizmo or not view or not rawget(_G, "LUI3d2dToSphere") or not rawget(_G, "_LUI3dComputeScaleFactor") then
    return
  end
  local gizmoMatrix = gizmo.Transform:get():getmatrix()
  local center = gizmoMatrix:gettranslation()
  local radius = _LUI3dComputeScaleFactor(view, center) * LUIPlugGetValue(gizmo.MeshScaleFactor) * 5
  if LUI3d2dToSphere(view, x, y, center, radius) then
    return gizmo
  end
end

local GIZMO_PROXIMITY_OFFSETS = {
  {0, 0},
  {0, -3},
  {0, 3},
  {-3, 0},
  {3, 0},
  {-2, -2},
  {2, -2},
  {-2, 2},
  {2, 2},
  {0, -5},
  {0, 5},
  {-5, 0},
  {5, 0},
  {-4, -4},
  {4, -4},
  {-4, 4},
  {4, 4},
  {0, -7},
  {0, 7},
  {-7, 0},
  {7, 0},
  {-5, -5},
  {5, -5},
  {-5, 5},
  {5, 5}
}

local function LUIGetActiveGizmoHit(view, originalOnGetObjects, x, y, forceAllObjects, activeGizmos)
  if not activeGizmos then
    return
  end
  for _, offset in ipairs(GIZMO_PROXIMITY_OFFSETS) do
    local sampleX = x + offset[1]
    local sampleY = y + offset[2]
    local objects = originalOnGetObjects(view, sampleX, sampleY, 0, 0, true, forceAllObjects)
    local target = objects and objects[1]
    if target and activeGizmos[target] then
      return target, objects
    end
    local gizmo = LUIResolveActiveGizmoFromObjects(objects, activeGizmos)
    if gizmo then
      return gizmo, objects
    end
    gizmo = LUIGetCustomMultiRotateHit(view, sampleX, sampleY)
    if gizmo then
      return gizmo, objects
    end
  end
end

local function LUISetGizmoSelected(gizmo, selected)
  local plug = gizmo and gizmo.Selected
  if not plug then
    return
  end
  selected = selected and true or false
  if LUIPlugGetValue(plug) ~= selected then
    plug:set(selected)
  end
end

local function LUISyncGizmoHoverSelection(activeGizmos, hoveredGizmo)
  local tool = LUIGetCurrentTool()
  if tool and tool._DraggedGizmo then
    return
  end
  if activeGizmos then
    for gizmo in pairs(activeGizmos) do
      LUISetGizmoSelected(gizmo, gizmo == hoveredGizmo)
    end
  end
  local previousGizmo = rawget(_G, "_GizmoHoverSelected")
  if previousGizmo and previousGizmo ~= hoveredGizmo and (not activeGizmos or not activeGizmos[previousGizmo]) then
    LUISetGizmoSelected(previousGizmo, false)
  end
  rawset(_G, "_GizmoHoverSelected", hoveredGizmo)
end

local function LUIClearGizmoHoverSelection()
  if rawget(_G, "_GizmoHoverSelected") then
    LUISyncGizmoHoverSelection(LUIGetActiveToolGizmos(), nil)
  end
end

local GIZMO_POST_DRAG_HOVER_COOLDOWN = 0.12

local function LUIGetGizmoHoverClock()
  local osTable = rawget(_G, "os") or os
  return osTable and osTable.clock and osTable.clock()
end

local function LUIBeginGizmoHoverCooldown()
  local now = LUIGetGizmoHoverClock()
  if now then
    rawset(_G, "_GizmoHoverCooldownUntil", now + GIZMO_POST_DRAG_HOVER_COOLDOWN)
  end
end

local function LUIIsGizmoHoverCoolingDown()
  local untilTime = rawget(_G, "_GizmoHoverCooldownUntil")
  if not untilTime then
    return false
  end
  local now = LUIGetGizmoHoverClock()
  if not now or now >= untilTime then
    rawset(_G, "_GizmoHoverCooldownUntil", nil)
    return false
  end
  return true
end

local function LUIWarnGizmoRecovery(message)
  local warning = rawget(_G, "pwarning")
  if warning then
    pcall(warning, message)
  end
end

local function LUIForceMouseRelease(x, y, modifiers)
  rawset(_G, "_RotateSnapMouseCapture", false)
  rawset(_G, "LUIClickWindow", nil)
  rawset(_G, "LUIDropWindow", nil)
  rawset(_G, "LUIDragingButton", nil)
  rawset(_G, "LUIDragingModifiers", nil)
  local timer = rawget(_G, "_LUITimerDownRepeat")
  local cancelTimer = rawget(_G, "LUITimerCancel")
  if timer and cancelTimer then
    pcall(cancelTimer, timer)
    timer.Window = nil
    timer.Func = nil
  end
  local globals = rawget(_G, "LUIGlobals")
  if globals and globals.MouseDrag then
    pcall(function()
      globals.MouseDrag:set(nil)
    end)
  end
  local updateMouseOver = rawget(_G, "LUIUpdateMouseOver")
  if updateMouseOver and type(x) == "number" and type(y) == "number" then
    pcall(updateMouseOver, x, y, true, modifiers)
  end
end

local function LUISetPlugValueSafe(mod, plug, value)
  if not plug then
    return
  end
  if mod and mod.set then
    local ok = pcall(function()
      mod.set(plug, value)
    end)
    if ok then
      return
    end
  end
  if plug.set then
    pcall(function()
      plug:set(value)
    end)
  elseif plug.setraw then
    pcall(function()
      plug:setraw(value)
    end)
  end
end

local function LUIRecoverSelectionState(globals)
  globals = globals or rawget(_G, "LUIGlobals")
  if not globals then
    return
  end
  local document = rawget(_G, "Document")
  local mod = document and document.getmodifier and document:getmodifier()
  local selected = globals.Selected
  local selectionPlugs = selected and selected.getoutputs and selected:getoutputs()
  if selectionPlugs then
    local count = table.maxn and table.maxn(selectionPlugs) or #selectionPlugs
    for i = count, 1, -1 do
      local plug = selectionPlugs[i]
      if mod and mod.disconnect then
        pcall(function()
          mod.disconnect(plug, selected)
        end)
      end
      LUISetPlugValueSafe(mod, plug, false)
    end
  end
  local disconnect = rawget(_G, "disconnectoutputs")
  if disconnect and selected then
    pcall(disconnect, selected)
  end
  if mod and mod.removealldependencies then
    if globals.SelectionStructure then
      pcall(function()
        mod.removealldependencies(globals.SelectionStructure)
      end)
    end
    if globals.SelectionTransform then
      pcall(function()
        mod.removealldependencies(globals.SelectionTransform)
      end)
    end
  end
  LUISetPlugValueSafe(mod, globals.SelectedPaths, {})
end

local function LUIPatchSafeSelectionUnselectAll()
  local globalsVT = rawget(_G, "LUIGlobalsVT")
  if not globalsVT or rawget(_G, "_GizmoSafeUnselectAllPatched") then
    return
  end
  local originalUnselectAll = globalsVT.unselectall
  if not originalUnselectAll then
    return
  end
  rawset(_G, "_GizmoSafeUnselectAllPatched", true)
  globalsVT.unselectall = function(self, ...)
    local ok, result = pcall(originalUnselectAll, self, ...)
    if ok then
      return result
    end
    rawset(_G, "_GizmoLastUnselectAllError", tostring(result))
    LUIWarnGizmoRecovery("Gizmo selection recovery: " .. tostring(result))
    LUIRecoverSelectionState(self)
    LUIForceMouseRelease()
  end
end

local function LUIHandleMouseReleaseError(message, x, y, modifiers)
  rawset(_G, "_GizmoLastMouseReleaseError", tostring(message))
  LUIWarnGizmoRecovery("Gizmo mouse release recovery: " .. tostring(message))
  LUIRecoverSelectionState(rawget(_G, "LUIGlobals"))
  LUIForceMouseRelease(x, y, modifiers)
  rawset(_G, "_GizmoHoverSelected", nil)
  LUIBeginGizmoHoverCooldown()
end

local function LUIRunMouseWithReleaseRecovery(originalMouse, button, state, modifiers, x, y)
  local ok, result = pcall(originalMouse, button, state, modifiers, x, y)
  if ok then
    return result
  end
  local leftButton = rawget(_G, "LUI_LEFT_BUTTON")
  local buttonUp = rawget(_G, "LUI_BUTTON_UP")
  local buttonDoubleClick = rawget(_G, "LUI_BUTTON_DOUBLE_CLICK")
  if button == leftButton and (state == buttonUp or state == buttonDoubleClick) then
    LUIHandleMouseReleaseError(result, x, y, modifiers)
    return
  end
  error(result)
end

local function LUIUpdateGizmoHoverFromMouse(x, y)
  local tool = LUIGetCurrentTool()
  if tool and tool._DraggedGizmo then
    return
  end
  local activeGizmos = LUIGetActiveToolGizmos()
  if rawget(_G, "LUIDragingButton") or LUIIsGizmoHoverCoolingDown() then
    LUISyncGizmoHoverSelection(activeGizmos, nil)
    return
  end
  if not activeGizmos or type(x) ~= "number" or type(y) ~= "number" or not rawget(_G, "LUIRootWindow") or not rawget(_G, "LUIWindowPickByMethod") then
    LUISyncGizmoHoverSelection(activeGizmos, nil)
    return
  end
  local win, lx, ly = LUIWindowPickByMethod(LUIRootWindow, x, y, "onOver")
  if win and win.OverTarget then
    win = win.OverTarget
  end
  if (not win or not win.onGetObjects) and rawget(_G, "LUIOverWindow") then
    win = LUIOverWindow.OverTarget or LUIOverWindow
    if win and rawget(_G, "LUIWindowGetLocalPoint") then
      lx, ly = LUIWindowGetLocalPoint(win, x, y)
    end
  end
  if not win or not win.onGetObjects then
    win, lx, ly = LUIWindowPickByMethod(LUIRootWindow, x, y, "onGetObjects")
  end
  if not win or not win.onGetObjects then
    LUISyncGizmoHoverSelection(activeGizmos, nil)
    return
  end
  local objects = win:onGetObjects(lx, ly, 0, 0, true, false)
  local hoveredGizmo = LUIResolveActiveGizmoFromObjects(objects, activeGizmos)
  LUISyncGizmoHoverSelection(activeGizmos, hoveredGizmo)
end

local function LUIPatchGizmoProximityHit()
  local viewClass = rawget(_G, "LUI3dInteractiveVT")
  if not viewClass or rawget(_G, "_GizmoProximityHitPatched") then
    return
  end
  rawset(_G, "_GizmoProximityHitPatched", true)
  local originalOnGetObjects = viewClass.onGetObjects
  viewClass.onGetObjects = function(self, x, y, w, h, selectTools, forceAllObjects)
    local objects = originalOnGetObjects(self, x, y, w, h, selectTools, forceAllObjects)
    if not selectTools or w ~= 0 or h ~= 0 then
      return objects
    end
    local activeGizmos = LUIGetActiveToolGizmos()
    if not activeGizmos then
      return objects
    end
    if LUIResolveActiveGizmoFromObjects(objects, activeGizmos) then
      return objects
    end
    local gizmo = LUIGetActiveGizmoHit(self, originalOnGetObjects, x, y, forceAllObjects, activeGizmos)
    if gizmo then
      gizmo._Path = nil
      return {gizmo}
    end
    return objects
  end
  local originalOnOver = viewClass.onOver
  viewClass.onOver = function(self, enter, x, y)
    if originalOnOver then
      originalOnOver(self, enter, x, y)
    end
    if enter == "outside" or enter == false or enter == nil then
      LUIClearGizmoHoverSelection()
    end
  end
end

local function LUIPatchGizmoSelectionLifecycle()
  local gizmo3d = rawget(_G, "Gizmo3D")
  if not gizmo3d or rawget(_G, "_GizmoSelectionLifecyclePatched") then
    return
  end
  rawset(_G, "_GizmoSelectionLifecyclePatched", true)
  local originalOnDragEnd = gizmo3d.onDragEnd
  gizmo3d.onDragEnd = function(self, view, x, y)
    local result = originalOnDragEnd and originalOnDragEnd(self, view, x, y)
    LUISetGizmoSelected(self, false)
    if rawget(_G, "_GizmoHoverSelected") == self then
      rawset(_G, "_GizmoHoverSelected", nil)
    end
    LUIBeginGizmoHoverCooldown()
    return result
  end
end

local function LUIShouldUseRotateSnapMouse(button, modifiers)
  if button ~= rawget(_G, "LUI_LEFT_BUTTON") then
    return false
  end
  local shift = rawget(_G, "LUI_MODIFIER_SHIFT")
  if not shift or not LUIHasFlag(modifiers, shift) then
    return false
  end
  local globals = rawget(_G, "LUIGlobals")
  return globals and globals.TransformTool and LUIPlugGetValue(globals.TransformTool) == "rotate"
end

local function LUIGetRotateGizmoUnderCursor(x, y)
  if not rawget(_G, "LUIRootWindow") or not rawget(_G, "LUIWindowPickByMethod") then
    return
  end
  local win, lx, ly = LUIWindowPickByMethod(LUIRootWindow, x, y, "onGetObjects")
  if not win or not win.onGetObjects then
    return
  end
  local objects = win:onGetObjects(lx, ly, 0, 0, true, false)
  local target = objects and objects[1]
  if LUIIsRotateGizmo(target) then
    return target
  end
end

local function LUIPatchRotateSnapMouseRouting()
  local originalMouse = rawget(_G, "LUIOnMouse")
  if not originalMouse or rawget(_G, "_RotateSnapMouseRoutingPatched") then
    return
  end
  rawset(_G, "_RotateSnapMouseRoutingPatched", true)
  rawset(_G, "_RotateSnapMouseOriginal", originalMouse)
  rawset(_G, "_RotateSnapMouseCapture", false)
  rawset(_G, "LUIOnMouse", function(button, state, modifiers, x, y)
    local leftButton = rawget(_G, "LUI_LEFT_BUTTON")
    local buttonDown = rawget(_G, "LUI_BUTTON_DOWN")
    local buttonUp = rawget(_G, "LUI_BUTTON_UP")
    local buttonDoubleClick = rawget(_G, "LUI_BUTTON_DOUBLE_CLICK")
    local result
    if state == buttonDown and LUIShouldUseRotateSnapMouse(button, modifiers) and LUIGetRotateGizmoUnderCursor(x, y) then
      rawset(_G, "_RotateSnapMouseCapture", true)
      result = LUIRunMouseWithReleaseRecovery(originalMouse, button, state, 0, x, y)
    elseif rawget(_G, "_RotateSnapMouseCapture") and button == leftButton and (state == buttonUp or state == buttonDoubleClick) then
      rawset(_G, "_RotateSnapMouseCapture", false)
      result = LUIRunMouseWithReleaseRecovery(originalMouse, button, state, 0, x, y)
    else
      result = LUIRunMouseWithReleaseRecovery(originalMouse, button, state, modifiers, x, y)
    end
    if button == leftButton and (state == buttonUp or state == buttonDoubleClick) then
      LUIClearGizmoHoverSelection()
    end
    return result
  end)
end

local function LUIPatchGizmoHoverMoveRouting()
  -- Avoid viewport selection passes on every mouse move. Click picking covers gizmo selection.
end

LUIPatchRotateSnapMouseRouting()
LUIPatchGizmoHoverMoveRouting()
LUIPatchGizmoSelectionLifecycle()
LUIPatchGizmoProximityHit()
LUIPatchSafeSelectionUnselectAll()

GAPickToolCmd = command.create("Tools|Pick", "button_pick.png", "I")
GAPickToolCmd.IconMenu = "icon_default"
function GAPickToolCmd:Action()
  LUIPlugSetValue(LUIGlobals.TransformTool, "pick")
end
function GAPickToolCmd:isChecked()
  return LUIPlugGetValue(LUIGlobals.TransformTool) == "pick"
end

GASelectToolCmd = command.create("Tools|Select", "button_select.png", LUIShortcutCreate(LUI_KEY_Q))
GASelectToolCmd.IconMenu = "icon_default"
function GASelectToolCmd:Action()
  LUIPlugSetValue(LUIGlobals.TransformTool, "select")
end
function GASelectToolCmd:isChecked()
  return LUIPlugGetValue(LUIGlobals.TransformTool) == "select"
end

GATranslateToolCmd = command.create("Tools|Translate", "button_translate.png", LUIShortcutCreate(LUI_KEY_W))
GATranslateToolCmd.IconMenu = "icon_default"
function GATranslateToolCmd:Action()
  LUIPlugSetValue(LUIGlobals.TransformTool, "move")
end
function GATranslateToolCmd:isChecked()
  return LUIPlugGetValue(LUIGlobals.TransformTool) == "move"
end

GARotateToolCmd = command.create("Tools|Rotate", "button_rotate.png", LUIShortcutCreate(LUI_KEY_E))
GARotateToolCmd.IconMenu = "icon_default"
function GARotateToolCmd:Action()
  LUIPlugSetValue(LUIGlobals.TransformTool, "rotate")
end
function GARotateToolCmd:isChecked()
  return LUIPlugGetValue(LUIGlobals.TransformTool) == "rotate"
end

GAScaleToolCmd = command.create("Tools|Scale", "button_scale.png", LUIShortcutCreate(LUI_KEY_R))
GAScaleToolCmd.IconMenu = "icon_default"
function GAScaleToolCmd:Action()
  LUIPlugSetValue(LUIGlobals.TransformTool, "scale")
end
function GAScaleToolCmd:isChecked()
  return LUIPlugGetValue(LUIGlobals.TransformTool) == "scale"
end

GAPivotCmd = command.create("Tools|Use Pivot", "button_pivot.png", nil)
GAPivotCmd.IconMenu = "icon_default"
function GAPivotCmd:Action()
  local input = LUIGlobals.PivotPointHidden:getinput()
  if input then
    input:set(not input:get())
  end
end
function GAPivotCmd:isChecked()
  return not LUIGlobals.PivotPointHidden:get()
end

GAToolsMenu = {
  GASelectToolCmd,
  GATranslateToolCmd,
  GARotateToolCmd,
  GAScaleToolCmd,
  GAPivotCmd,
  GAPickToolCmd,
  nil,
  nil,
  nil
}

GAToolsCmd = LUIMenuCmdCreate("Tools", "icon_default", LUIShortcutCreate(LUI_KEY_T))
GAToolsCmd.Menu = GAToolsMenu

LUIVTCreate("GATool", "LUITool")

function GAToolCreate()
  LUIPatchRotateSnapMouseRouting()
  LUIPatchGizmoHoverMoveRouting()
  LUIPatchGizmoSelectionLifecycle()
  LUIPatchGizmoProximityHit()
  LUIPatchSafeSelectionUnselectAll()
  local self = LUIToolCreate()
  LUIVTSetClass(self, GAToolVT)
  -- Keep move gizmo indexes stable: plane-highlight links in lui_gizmo_move_rectangle.lua depend on 1=x, 2=y, 3=z.
  self._PrimGizmos[1] = LUIGizmoMoveArrowCreate(self, "x")
  self._PrimGizmos[2] = LUIGizmoMoveArrowCreate(self, "y")
  self._PrimGizmos[3] = LUIGizmoMoveArrowCreate(self, "z")
  self._PrimGizmos[4] = LUIGizmoMoveRectangleCreate(self, "center")
  self._PrimGizmos[5] = LUIGizmoMoveRectangleCreate(self, "xy")
  self._PrimGizmos[6] = LUIGizmoMoveRectangleCreate(self, "yz")
  self._PrimGizmos[7] = LUIGizmoMoveRectangleCreate(self, "xz")
  self._PrimGizmos[12] = LUIGizmoRotateCreate(self, "x")
  self._PrimGizmos[13] = LUIGizmoRotateCreate(self, "y")
  self._PrimGizmos[14] = LUIGizmoRotateCreate(self, "z")
  self._PrimGizmos[15] = LUIGizmoRotateCreate(self, "view")
  -- Keep the stock free-rotate handle for picking, but its source override renders it fully transparent.
  self._PrimGizmos[16] = LUIGizmoMultiRotateCreate(self)
  -- Keep scale gizmo indexes stable: plane-highlight links in lui_gizmo_scale_rectangle.lua depend on 17=x, 18=y, 19=z.
  self._PrimGizmos[17] = LUIGizmoScaleAxisCreate(self, "x")
  self._PrimGizmos[18] = LUIGizmoScaleAxisCreate(self, "y")
  self._PrimGizmos[19] = LUIGizmoScaleAxisCreate(self, "z")
  self._PrimGizmos[20] = LUIGizmoScaleRectangleCreate(self, "center")
  self._PrimGizmos[21] = LUIGizmoScaleRectangleCreate(self, "xy")
  self._PrimGizmos[22] = LUIGizmoScaleRectangleCreate(self, "yz")
  self._PrimGizmos[23] = LUIGizmoScaleRectangleCreate(self, "xz")
  for _, gizmo in pairs(self._PrimGizmos) do
    for _, mesh in pairs(gizmo._Meshes) do
      LUIGizmoMeshes:adddependencies(mesh.Structure)
    end
  end
  return self
end

function GAToolClean(self)
  for _, gizmo in pairs(self._PrimGizmos) do
    local meshes = gizmo._Meshes
    for _, mesh in pairs(meshes) do
      isolatenodes(false, mesh)
    end
    isolatenodes(false, gizmo)
  end
  isolatenodes(false, self)
end
