require("opengl")
require("lui_gizmo_3d")
local GIZMO_THEME = require("lui_gizmo_theme")
local GIZMO_PRECISION = require("lui_gizmo_precision")

LUIVTCreate("LUIGizmoRotate", "Gizmo3D")

local ROTATE_RING_COLORS = {
  x = GIZMO_THEME.axis.x,
  y = GIZMO_THEME.axis.y,
  z = GIZMO_THEME.axis.z,
  view = GIZMO_THEME.view
}

local ROTATE_RING_RADIUS = 5
local ROTATE_VIEW_RING_RADIUS = 5.8
local ROTATE_RING_LINE_WIDTH = 3
local ROTATE_RING_SEGMENTS = 96
local GIZMO_REACH_DEFAULT_SCALE = 1.5
local ROTATE_SNAP_ANGLE = math.rad(15)
local ROTATE_COARSE_SNAP_ANGLE = math.rad(45)
local ROTATE_MODIFIER_SHIFT = rawget(_G, "LUI_MODIFIER_SHIFT") or 8
local ROTATE_MODIFIER_CTRL = rawget(_G, "LUI_MODIFIER_CTRL") or 16

-- Keep the stock global for ga_ui_meshes.lua startup compatibility.
LUIGizmoRotateRadius = ROTATE_RING_RADIUS

local function LUICreateRotateRingMesh(radius)
  local ring = linemesh()
  ring.LineWidth = ROTATE_RING_LINE_WIDTH
  local points = {}
  for idx = 0, ROTATE_RING_SEGMENTS - 1 do
    local angle = (idx / ROTATE_RING_SEGMENTS) * math.pi * 2
    points[#points + 1] = 0
    points[#points + 1] = math.cos(angle) * radius
    points[#points + 1] = math.sin(angle) * radius
  end
  ring:addpolyline(points, true)
  return {LUIOpenGLMeshCreateFromLine(ring, 0)}
end

local function LUICreateRotateViewRingMesh(radius)
  local ring = linemesh()
  ring.LineWidth = ROTATE_RING_LINE_WIDTH
  local points = {}
  for idx = 0, ROTATE_RING_SEGMENTS - 1 do
    local angle = (idx / ROTATE_RING_SEGMENTS) * math.pi * 2
    points[#points + 1] = math.cos(angle) * radius
    points[#points + 1] = math.sin(angle) * radius
    points[#points + 1] = 0
  end
  ring:addpolyline(points, true)
  return {LUIOpenGLMeshCreateFromLine(ring, 0)}
end

local function LUIHasRotateModifier(modifier, flag)
  return modifier and modifier % (flag * 2) >= flag
end

local function LUIGetGizmoReachScalePlug()
  local globals = rawget(_G, "LUIGlobals")
  if not globals then
    return
  end
  if not globals.GizmoReachScale then
    Plug(globals, "GizmoReachScale", Plug.NoSerial, LUIPSTypeFloat, GIZMO_REACH_DEFAULT_SCALE)
  end
  return globals.GizmoReachScale
end

local function LUIGetRotateRingScale()
  local plug = LUIGetGizmoReachScalePlug()
  local scale = plug and plug:get() or GIZMO_REACH_DEFAULT_SCALE
  scale = math.max(GIZMO_REACH_DEFAULT_SCALE, scale or GIZMO_REACH_DEFAULT_SCALE)
  return scale / GIZMO_REACH_DEFAULT_SCALE
end

local function LUIGetRotateSnapAngle()
  local getter = GIZMO_PRECISION.getRotateSnapAngle
  return getter and getter() or ROTATE_SNAP_ANGLE
end

local function LUIGetRotateCoarseSnapAngle()
  local getter = GIZMO_PRECISION.getRotateCoarseSnapAngle
  return getter and getter() or ROTATE_COARSE_SNAP_ANGLE
end

local function LUISnapRotateAngle(angle, modifier)
  local step = nil
  if LUIHasRotateModifier(modifier, ROTATE_MODIFIER_SHIFT) and LUIHasRotateModifier(modifier, ROTATE_MODIFIER_CTRL) then
    step = LUIGetRotateCoarseSnapAngle()
  elseif LUIHasRotateModifier(modifier, ROTATE_MODIFIER_SHIFT) then
    step = LUIGetRotateSnapAngle()
  end
  if not step then
    return angle
  end
  return math.floor(angle / step + 0.5) * step
end

local function LUIGetRotateDisplayToolMatrix(tool)
  local globals = rawget(_G, "LUIGlobals")
  local toolMatrix = tool.ToolTransform:get():getmatrix()
  if globals and globals.TransformTool:get() == "rotate" and globals.TransformMode:get() == "local" and tool._DraggedGizmo then
    -- ToolTransform intentionally freezes orientation from InitTransform during a drag.
    -- For local rotate, that makes the ring display lag until drag-end.
    -- Use the live SelectionTransform orientation while keeping the same pivot translation rules.
    local selectionTransform = tool.SelectionTransform:get()
    local selectionMatrix = selectionTransform and selectionTransform:getmatrix()
    if selectionMatrix then
      local displayMatrix = matrix.create(selectionMatrix)
      if toolMatrix then
        displayMatrix:settranslation(toolMatrix:gettranslation())
      end
      return displayMatrix
    end
  end
  return toolMatrix
end

function LUIGizmoRotateVT:onLDown(x, y, view)
  LUIGizmoRotateVT.Parent.onLDown(self, x, y, view)
  local gizmoMatrix = self.Transform:get():getmatrix()
  self._StartP = gizmoMatrix:gettranslation()
  if self._Axis == "view" then
    self._StartN = view:getviewworldmatrixorient():getk():getnormalized()
  else
    self._StartN = gizmoMatrix:geti():getnormalized()
  end
  self._StartI = (LUI3d2dToPlane(view, x, y, self._StartP, self._StartN) - self._StartP):getnormalized()
  self._StartJ = self._StartI:cross(self._StartN)
  GIZMO_PRECISION.beginScalar(self, "rotate", 0, rawget(_G, "LUIMouseModifiers"))
end

function LUIGizmoRotateVT:onDrag(view, x, y, lx, ly, modifier)
  local dir = (LUI3d2dToPlane(view, lx, ly, self._StartP, self._StartN) - self._StartP):getnormalized()
  local dx, dy = dir:dot(self._StartI), dir:dot(self._StartJ)
  modifier = modifier or rawget(_G, "LUIMouseModifiers") or rawget(_G, "LUIDragingModifiers") or 0
  self._Angle = GIZMO_PRECISION.scalarDelta(self, "rotate", math.atan2(dy, dx), modifier)
  self._Angle = LUISnapRotateAngle(self._Angle, modifier)
  self._Tool:dotransformmodification(self)
  return 0, 0
end

function LUIGizmoRotateVT:onDragEnd(view, x, y)
  GIZMO_PRECISION.endDrag(self)
  return LUIGizmoRotateVT.Parent.onDragEnd(self, view, x, y)
end

function LUIGizmoRotateVT:getPickPriority()
  return 1
end

function LUIGizmoRotateVT:doModification(object)
  if object.gettransform then
    local state = self._Tool:getnodestate(object)
    local trans = object:gettransform()
    if LUIGlobals.TransformMode:get() == "local" and self._Axis ~= "view" and trans.setaxisrotation then
      trans:setaxisrotation(self._Axis, state.Axis[self._Axis] + self._Angle)
    elseif trans.setmatrix and state and state.WorldMtx then
      local pivotPos = LUIGlobals.PivotPointHidden:get() and state.WorldMtx:gettranslation() or LUIGlobals.PivotPointTransform:get():getmatrix():gettranslation()
      local pivot = matrix.createidentity()
      pivot:pivot(self._StartN, self._Angle, pivotPos)
      local mtx = state.WorldMtx:compose(pivot):compose(state.InvParentWorldMtx)
      trans:setmatrix(mtx)
    end
  end
end

function LUIGizmoRotateVT:eval(plug)
  if plug == self.Transform then
    local gizmoMatrix = matrix.createidentity()
    local toolMatrix = LUIGetRotateDisplayToolMatrix(self._Tool)
    local p = toolMatrix:gettranslation()
    local i, j
    if self._Axis == "view" then
      -- The view ring uses NodeLookAt, so keep a clean identity basis and draw its circle in local XY.
      i = point3.create(1, 0, 0)
      j = point3.create(0, 1, 0)
    elseif self._Axis == "y" then
      i = toolMatrix:getj():getnormalized()
      j = toolMatrix:getk():getnormalized()
    elseif self._Axis == "z" then
      i = toolMatrix:getk():getnormalized()
      j = toolMatrix:geti():getnormalized()
    else
      i = toolMatrix:geti():getnormalized()
      j = toolMatrix:getj():getnormalized()
    end
    local k = i:cross(j)
    gizmoMatrix:seti(i)
    gizmoMatrix:setj(j)
    gizmoMatrix:setk(k)
    gizmoMatrix:settranslation(p)
    return transform.create(gizmoMatrix)
  elseif plug == self.MeshFlags then
    local hidden = LUIGlobals.TransformTool:get() ~= "rotate" or not self.PrimitiveSelected:get()
    return (self._Axis ~= "view" and GLdisplay.HideOnXSide or 0) + GLdisplay.NoLigthing + (hidden and GLdisplay.Hidden or 0)
  elseif plug == self.MeshScaleFactor then
    return LUIGlobals.ToolSize:get() * LUIGetRotateRingScale()
  end
  return LUIGizmoRotateVT.Parent.eval(self, plug)
end

function LUIGizmoRotateVT:getGLprops()
  local hidden = LUIGlobals.TransformTool:get() ~= "rotate" or not self.PrimitiveSelected:get()
  local flags = GLdisplay.NodeConstantScale + GLdisplay.NodeTypeMisc + GLdisplay.NodeIgnoreFilter + (self._Axis == "view" and GLdisplay.NodeLookAt or GLdisplay.NodeLookAtX) + (hidden and GLdisplay.Hidden or 0)
  return flags, 0, 1, LUIGlobals.ToolSize:get() * LUIGetRotateRingScale()
end

function LUIGizmoRotateCreate(tool, axis)
  local color = ROTATE_RING_COLORS[axis] or ROTATE_RING_COLORS.x
  local self = LUIGizmo3DCreate(tool, {
    LUIGizmoMeshCreate(nil, color)
  })
  LUIVTSetClass(self, LUIGizmoRotateVT)
  local lineScalePlug = LUIGetGizmoReachScalePlug()
  if lineScalePlug then
    LUIPlugAddDependencies(self.Transform, tool.ToolTransform, lineScalePlug)
    self.MeshScaleFactor:adddependencies(lineScalePlug)
  else
    LUIPlugAddDependencies(self.Transform, tool.ToolTransform)
  end
  LUIPlugAddDependencies(self.MeshFlags, self.PrimitiveSelected, LUIGlobals.TransformTool)
  self._Axis = axis

  local radius = axis == "view" and ROTATE_VIEW_RING_RADIUS or ROTATE_RING_RADIUS
  local mesh = axis == "view" and LUICreateRotateViewRingMesh(radius) or LUICreateRotateRingMesh(radius)
  self._Meshes[1].Geometry.Mesh:set(mesh)
  self._Meshes[1].GeometryTransparent.Mesh:set(mesh)
  self._Meshes[1].Geometry.MeshRenderMode:set(GLdisplay.WireFrame)
  self._Meshes[1].GeometryTransparent.MeshRenderMode:set(GLdisplay.WireFrame)
  return self
end

function LUIGizmoRotateVT:isactive(object)
  local trans = object.gettransform and object:gettransform()
  return trans and trans.setmatrix
end

-- Shift/Ctrl+Shift dragging must stay on the rotate gizmo instead of falling back to the viewport
-- selection gesture. The mouse dispatcher looks for LS/LCS-specific handlers on mouse-down.
LUIGizmoRotateVT.onLSDown = LUIGizmoRotateVT.onLDown
LUIGizmoRotateVT.onLSDrag = LUIGizmoRotateVT.onDrag
LUIGizmoRotateVT.onLSDragEnd = LUIGizmoRotateVT.onDragEnd
LUIGizmoRotateVT.onLCSDown = LUIGizmoRotateVT.onLDown
LUIGizmoRotateVT.onLCSDrag = LUIGizmoRotateVT.onDrag
LUIGizmoRotateVT.onLCSDragEnd = LUIGizmoRotateVT.onDragEnd
