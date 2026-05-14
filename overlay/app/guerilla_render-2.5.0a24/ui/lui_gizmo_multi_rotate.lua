require("opengl")
require("lui_gizmo_3d")
local GIZMO_PRECISION = require("lui_gizmo_precision")

LUIVTCreate("LUIGizmoMultiRotate", "Gizmo3D")

local MULTI_ROTATE_PICK_COLOR = {
  0,
  0,
  0,
  0
}
local MULTI_ROTATE_VISIBLE_COLOR = {
  0.25,
  1.0,
  0.25,
  0.9
}
local MULTI_ROTATE_VISIBLE_SCALE = 0.74
local GIZMO_REACH_DEFAULT_SCALE = 1.5
local ROTATE_SNAP_ANGLE = math.rad(15)
local ROTATE_COARSE_SNAP_ANGLE = math.rad(45)
local ROTATE_MODIFIER_SHIFT = rawget(_G, "LUI_MODIFIER_SHIFT") or 8
local ROTATE_MODIFIER_CTRL = rawget(_G, "LUI_MODIFIER_CTRL") or 16

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

local function LUIGetRotateCenterScale()
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

function LUIGizmoMultiRotateVT:onLDown(x, y, view)
  LUIGizmoMultiRotateVT.Parent.onLDown(self, x, y, view)
  local gizmoMatrix = self.Transform:get():getmatrix()
  self._StartCenter = gizmoMatrix:gettranslation()
  self._StartRadius = _LUI3dComputeScaleFactor(view, self._StartCenter) * LUIPlugGetValue(self.MeshScaleFactor) * 5
  local psphere = LUI3d2dToSphere(view, x, y, self._StartCenter, self._StartRadius)
  self._StartV = psphere and (psphere - self._StartCenter):getnormalized() or point3.create(0)
  GIZMO_PRECISION.beginScalar(self, "rotate", 0, rawget(_G, "LUIMouseModifiers"))
end

function LUIGizmoMultiRotateVT:onDrag(view, x, y, lx, ly, modifier)
  local psphere = LUI3d2dToSphere(view, lx, ly, self._StartCenter, self._StartRadius)
  local newV = psphere and (psphere - self._StartCenter):getnormalized() or point3.create(0)
  self._Axis = self._StartV:cross(newV)
  local mag = self._Axis:getlength()
  if mag < 0.001 then
    self._Axis = point3.create(0, 0, 1)
    self._Angle = 0
  else
    self._Axis = self._Axis / mag
    local k = self._Axis:cross(self._StartV)
    local dx, dy = newV:dot(k), newV:dot(self._StartV)
    modifier = modifier or rawget(_G, "LUIMouseModifiers") or rawget(_G, "LUIDragingModifiers") or 0
    self._Angle = GIZMO_PRECISION.scalarDelta(self, "rotate", -math.atan2(dx, dy), modifier)
    self._Angle = LUISnapRotateAngle(self._Angle, modifier)
  end
  self._Tool:dotransformmodification(self)
  return 0, 0
end

function LUIGizmoMultiRotateVT:onDragEnd(view, x, y)
  GIZMO_PRECISION.endDrag(self)
  return LUIGizmoMultiRotateVT.Parent.onDragEnd(self, view, x, y)
end

function LUIGizmoMultiRotateVT:doModification(object)
  if object.gettransform then
    local state = self._Tool:getnodestate(object)
    local trans = object:gettransform()
    if trans.setmatrix and state and state.WorldMtx then
      local pivotPos = LUIGlobals.PivotPointHidden:get() and state.WorldMtx:gettranslation() or LUIGlobals.PivotPointTransform:get():getmatrix():gettranslation()
      local pivot = matrix.createidentity()
      pivot:pivot(self._Axis, self._Angle, pivotPos)
      local mtx = state.WorldMtx:compose(pivot):compose(state.InvParentWorldMtx)
      trans:setmatrix(mtx)
    end
  end
end

function LUIGizmoMultiRotateVT:eval(plug)
  if plug == self.Transform then
    local gizmoMatrix = matrix.createidentity()
    local toolMatrix = self._Tool.ToolTransform:get():getmatrix()
    gizmoMatrix:settranslation(toolMatrix:gettranslation())
    return transform.create(gizmoMatrix)
  elseif plug == self.MeshFlags then
    local hidden = LUIPlugGetValue(LUIGlobals.TransformTool) ~= "rotate" or not LUIPlugGetValue(self.PrimitiveSelected)
    return GLdisplay.NoLigthing + (hidden and GLdisplay.Hidden or 0)
  elseif plug == self.MeshScaleFactor then
    return LUIPlugGetValue(LUIGlobals.ToolSize) * 0.9 * LUIGetRotateCenterScale()
  elseif plug == self.VisibleMeshScaleFactor then
    return LUIPlugGetValue(self.MeshScaleFactor) * MULTI_ROTATE_VISIBLE_SCALE
  end
  return LUIGizmoMultiRotateVT.Parent.eval(self, plug)
end

function LUIGizmoMultiRotateVT:getGLprops()
  local hidden = LUIGlobals.TransformTool:get() ~= "rotate" or not self.PrimitiveSelected:get()
  return GLdisplay.NodeConstantScale + GLdisplay.NodeTypeMisc + GLdisplay.NodeIgnoreFilter + (hidden and GLdisplay.Hidden or 0), 0, 1, LUIGlobals.ToolSize:get() * 0.9
end

function LUIGizmoMultiRotateCreate(tool)
  local self = LUIGizmo3DCreate(tool, {
    -- Keep the stock multi-rotate mesh invisible for reliable center picking.
    LUIGizmoMeshCreate("gizmo_multi_rotate", MULTI_ROTATE_PICK_COLOR),
    -- Secondary visible hint mesh kept hidden; free-rotate uses the invisible stock pick volume above.
    LUIGizmoMeshCreate("material_sphere", MULTI_ROTATE_VISIBLE_COLOR)
  })
  LUIVTSetClass(self, LUIGizmoMultiRotateVT)
  self._Color = MULTI_ROTATE_VISIBLE_COLOR
  LUIPlugAddDependencies(self.Transform, tool.ToolTransform)
  LUIPlugAddDependencies(self.MeshFlags, self.PrimitiveSelected, LUIGlobals.TransformTool)
  Plug(self, "VisibleMeshScaleFactor", Plug.NoSerial, LUIPSTypeFloat, 1)
  local lineScalePlug = LUIGetGizmoReachScalePlug()
  if lineScalePlug then
    self.MeshScaleFactor:adddependencies(lineScalePlug)
  end
  if LUIGlobals.TransformTool then
    self.VisibleMeshScaleFactor:adddependencies(LUIGlobals.TransformTool)
  end
  self.VisibleMeshScaleFactor:adddependencies(self.MeshScaleFactor)
  -- Both meshes stay hidden; center free-rotate is injected by a custom viewport hit test in ga_tool.lua.
  LUIPlugSetValue(self._Meshes[1].Geometry.MeshRenderMode, GLdisplay.Filled)
  LUIPlugSetValue(self._Meshes[1].GeometryTransparent.MeshRenderMode, GLdisplay.Filled)
  LUIPlugSetValue(self._Meshes[2].Geometry.MeshRenderMode, GLdisplay.Filled)
  LUIPlugSetValue(self._Meshes[2].GeometryTransparent.MeshRenderMode, GLdisplay.Filled)
  self._Meshes[1].Geometry.MeshFlags:disconnectall()
  self._Meshes[1].Geometry.MeshFlags:set(GLdisplay.Hidden)
  self._Meshes[1].GeometryTransparent.MeshFlags:disconnectall()
  self._Meshes[1].GeometryTransparent.MeshFlags:set(GLdisplay.Hidden)
  self._Meshes[2].Geometry.MeshFlags:disconnectall()
  self._Meshes[2].Geometry.MeshFlags:set(GLdisplay.Hidden)
  self._Meshes[2].GeometryTransparent.MeshFlags:disconnectall()
  self._Meshes[2].GeometryTransparent.MeshFlags:set(GLdisplay.Hidden)
  self._Meshes[2].Geometry.MeshScaleFactor:disconnectall()
  self._Meshes[2].GeometryTransparent.MeshScaleFactor:disconnectall()
  self._Meshes[2].Geometry.MeshScaleFactor:connect(self.VisibleMeshScaleFactor)
  self._Meshes[2].GeometryTransparent.MeshScaleFactor:connect(self.VisibleMeshScaleFactor)
  return self
end

function LUIGizmoMultiRotateVT:isactive(object)
  local trans = object.gettransform and object:gettransform()
  return trans and trans.setmatrix
end

LUIGizmoMultiRotateVT.onLSDown = LUIGizmoMultiRotateVT.onLDown
LUIGizmoMultiRotateVT.onLSDrag = LUIGizmoMultiRotateVT.onDrag
LUIGizmoMultiRotateVT.onLSDragEnd = LUIGizmoMultiRotateVT.onDragEnd
LUIGizmoMultiRotateVT.onLCSDown = LUIGizmoMultiRotateVT.onLDown
LUIGizmoMultiRotateVT.onLCSDrag = LUIGizmoMultiRotateVT.onDrag
LUIGizmoMultiRotateVT.onLCSDragEnd = LUIGizmoMultiRotateVT.onDragEnd
