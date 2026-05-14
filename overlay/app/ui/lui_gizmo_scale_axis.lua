require("opengl")
require("lui_gizmo_scale")
local GIZMO_THEME = require("lui_gizmo_theme")
local GIZMO_PRECISION = require("lui_gizmo_precision")

LUIVTCreate("LUIGizmoScaleAxis", "LUIGizmoScale")

local SCALE_AXIS_COLORS = GIZMO_THEME.axis
local GIZMO_REACH_DEFAULT_SCALE = 1.5
local SCALE_AXIS_LINE_WIDTH = 3
local SCALE_AXIS_LINE_LENGTH = 4
local SCALE_AXIS_HANDLE_SIZE = 0.5

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

local function LUIGetScaleLineScale()
  local plug = LUIGetGizmoReachScalePlug()
  local scale = plug and plug:get() or GIZMO_REACH_DEFAULT_SCALE
  return math.max(GIZMO_REACH_DEFAULT_SCALE, scale or GIZMO_REACH_DEFAULT_SCALE)
end

local function LUIGetScaleAxisLineLength()
  -- Keep scale-gizmo reach separate from ToolSize so +/- only stretches shafts.
  return SCALE_AXIS_LINE_LENGTH * LUIGetScaleLineScale()
end

local function LUIGetScaleAxisViewScale(view, gizmoMatrix)
  return LUIPlugGetValue(LUIGlobals.ToolSize) * _LUI3dComputeScaleFactor(view, gizmoMatrix:gettranslation())
end

local function LUICreateScaleAxisShaftMesh(length)
  local shaft = linemesh()
  shaft.LineWidth = SCALE_AXIS_LINE_WIDTH
  shaft:addpolyline({
    0, 0, 0,
    length, 0, 0
  }, false)
  return {LUIOpenGLMeshCreateFromLine(shaft, 0)}
end

local function LUISafeScaleRatio(currentValue, startValue)
  if not startValue or math.abs(startValue) < 1.0e-4 then
    return 1
  end
  return currentValue / startValue
end

local function LUIGetScaleDisplayMatrix(tool)
  return tool.ToolTransform:get():getmatrix()
end

function LUIGizmoScaleAxisVT:onLDown(x, y, view)
  local gizmoMatrix = self.Transform:get():getmatrix()
  self._InitPos = LUIGetScaleDisplayMatrix(self._Tool):gettranslation()
  self._InitAxis = gizmoMatrix:geti():getnormalized()
  LUIGizmoScaleVT.onLDown(self, x, y, view)
  self._ToWorld:copy(gizmoMatrix)
  self._ToLocal:copy(gizmoMatrix)
  LUIMtxInvert(self._ToLocal)
  GIZMO_PRECISION.beginScalar(self, "scale", 0, rawget(_G, "LUIMouseModifiers"))
end

function LUIGizmoScaleAxisVT:onGetPoint(view, x, y)
  return LUI3d2dToLine(view, x, y, self._InitPos, self._InitAxis)
end

function LUIGizmoScaleAxisVT:onDrag(view, x, y, lx, ly, modifier)
  local current = self:onGetPoint(view, lx, ly)
  if not current then
    return 0, 0
  end
  local rawScale = LUISafeScaleRatio((current - self._Center):dot(self._InitAxis), self._ScaleDistance)
  local adjustedScale = 1 + GIZMO_PRECISION.scalarDelta(self, "scale", rawScale - 1, modifier)
  self._CurrentScale = GIZMO_PRECISION.snapScale(math.max(0.01, adjustedScale), modifier)
  self._ScaleMatrix:copy(self._ToLocal)
  self._LocScaleMatrix:setidentity()
  self._LocScaleMatrix:scale(self._CurrentScale, 1, 1)
  LUIMtxCompose(self._ScaleMatrix, self._LocScaleMatrix)
  LUIMtxCompose(self._ScaleMatrix, self._ToWorld)
  self._ScaleMatrix:settranslation(point3.create(0, 0, 0))
  self._Tool:dotransformmodification(self)
  return 0, 0
end

function LUIGizmoScaleAxisVT:onDragEnd(view, x, y)
  GIZMO_PRECISION.endDrag(self)
  return LUIGizmoScaleVT.onDragEnd(self, view, x, y)
end

function LUIGizmoScaleAxisVT:doModification(object)
  return LUIGizmoScaleVT.doModification(self, object)
end

function LUIGizmoScaleAxisVT:_updateShaftMesh()
  local length = LUIGetScaleAxisLineLength()
  if self._ShaftMeshLength == length then
    return
  end
  local mesh = LUICreateScaleAxisShaftMesh(length)
  self._Meshes[3].Geometry.Mesh:set(mesh)
  self._Meshes[3].GeometryTransparent.Mesh:set(mesh)
  self._ShaftMeshLength = length
end

function LUIGizmoScaleAxisVT:eval(plug)
  if plug == self.Transform then
    local gizmoMatrix = matrix.createidentity()
    local toolMatrix = LUIGetScaleDisplayMatrix(self._Tool)
    local i, j
    if self._Axis == "x" then
      i = toolMatrix:geti():getnormalized()
      j = toolMatrix:getk():cross(i):getnormalized()
    elseif self._Axis == "y" then
      i = toolMatrix:getj():getnormalized()
      j = toolMatrix:geti():cross(i):getnormalized()
    else
      i = toolMatrix:getk():getnormalized()
      j = toolMatrix:getj():cross(i):getnormalized()
    end
    local k = i:cross(j):getnormalized()
    gizmoMatrix:seti(i)
    gizmoMatrix:setj(j)
    gizmoMatrix:setk(k)
    gizmoMatrix:settranslation(toolMatrix:gettranslation())
    return transform.create(gizmoMatrix)
  elseif plug == self.ShaftTransform then
    self:_updateShaftMesh()
    return self.Transform:get()
  elseif plug == self.MeshFlags then
    local hidden = LUIPlugGetValue(LUIGlobals.TransformTool) ~= "scale" or not LUIPlugGetValue(self.PrimitiveSelected)
    return GLdisplay.HideOnXFront + GLdisplay.NoLigthing + GLdisplay.ViewDependent + (hidden and GLdisplay.Hidden or 0)
  end
  return LUIGizmoScaleVT.eval(self, plug)
end

function LUIGizmoScaleAxisVT:getGLprops()
  local hidden = LUIGlobals.TransformTool:get() ~= "scale" or not self.PrimitiveSelected:get()
  return GLdisplay.NodeTypeMisc + GLdisplay.NodeIgnoreFilter + (hidden and GLdisplay.NodeHidden or 0), 0, 1, 1
end

function LUIGizmoScaleAxisCreate(tool, axis)
  local color = SCALE_AXIS_COLORS[axis] or SCALE_AXIS_COLORS.x
  local self = LUIGizmoScaleCreate(tool, {
    LUIGizmoMeshCreate("gizmo_cube", color),
    LUIGizmoMeshCreate("scale_line", color),
    LUIGizmoMeshCreate(nil, color)
  })
  LUIVTSetClass(self, LUIGizmoScaleAxisVT)
  self._Axis = axis
  self.Transform:adddependencies(tool.ToolTransform)
  self.MeshFlags:adddependencies(self.PrimitiveSelected, LUIGlobals.TransformTool)
  Plug(self, "ShaftTransform", Plug.NoSerial, types.transform, LUI_MESH_PLUG_DEFAULT_TRANSFORM)
  local lineScalePlug = LUIGetGizmoReachScalePlug()
  if lineScalePlug then
    self.ShaftTransform:adddependencies(tool.ToolTransform, lineScalePlug)
  else
    self.ShaftTransform:adddependencies(tool.ToolTransform)
  end
  self._Meshes[3].Transform:disconnectall()
  self._Meshes[3].Transform:connect(self.ShaftTransform)
  self._Meshes[1].Geometry.MeshRenderMode:set(GLdisplay.Filled)
  self._Meshes[1].GeometryTransparent.MeshRenderMode:set(GLdisplay.Filled)

  -- Hide the stock line and keep only the custom shaft mesh so width/length stay controllable.
  self._Meshes[2].Geometry.MeshFlags:disconnectall()
  self._Meshes[2].GeometryTransparent.MeshFlags:disconnectall()
  self._Meshes[2].Geometry.MeshFlags:set(GLdisplay.Hidden)
  self._Meshes[2].GeometryTransparent.MeshFlags:set(GLdisplay.Hidden)

  self._Meshes[1].Geometry.MeshScaleFactor:disconnectall()
  self._Meshes[1].GeometryTransparent.MeshScaleFactor:disconnectall()
  self._Meshes[3].Geometry.MeshScaleFactor:disconnectall()
  self._Meshes[3].GeometryTransparent.MeshScaleFactor:disconnectall()

  local mesh = LUICreateScaleAxisShaftMesh(LUIGetScaleAxisLineLength())
  self._Meshes[3].Geometry.Mesh:set(mesh)
  self._Meshes[3].GeometryTransparent.Mesh:set(mesh)
  self._ShaftMeshLength = LUIGetScaleAxisLineLength()

  local function onGetHandleMatrix(geometry, view)
    local gizmo = geometry:getowner()._Gizmo
    local gizmoMatrix = gizmo.Transform:get():getmatrix()
    local viewScale = LUIGetScaleAxisViewScale(view, gizmoMatrix)
    local currentScale = gizmo._CurrentScale or 1
    local handleDistance = LUIGetScaleAxisLineLength() * currentScale * viewScale
    local axisI = gizmoMatrix:geti():getnormalized()
    local axisJ = gizmoMatrix:getj():getnormalized()
    local axisK = gizmoMatrix:getk():getnormalized()
    local newMatrix = matrix.create(gizmoMatrix)
    newMatrix:seti(axisI * (viewScale * SCALE_AXIS_HANDLE_SIZE))
    newMatrix:setj(axisJ * (viewScale * SCALE_AXIS_HANDLE_SIZE))
    newMatrix:setk(axisK * (viewScale * SCALE_AXIS_HANDLE_SIZE))
    newMatrix:settranslation(gizmoMatrix:transform(point3.create(handleDistance, 0, 0)))
    return newMatrix
  end

  local function onGetShaftMatrix(geometry, view)
    local gizmo = geometry:getowner()._Gizmo
    local gizmoMatrix = gizmo.Transform:get():getmatrix()
    local viewScale = LUIGetScaleAxisViewScale(view, gizmoMatrix)
    local currentScale = gizmo._CurrentScale or 1
    local axisI = gizmoMatrix:geti():getnormalized()
    local axisJ = gizmoMatrix:getj():getnormalized()
    local axisK = gizmoMatrix:getk():getnormalized()
    local newMatrix = matrix.create(gizmoMatrix)
    newMatrix:seti(axisI * (viewScale * currentScale))
    newMatrix:setj(axisJ * viewScale)
    newMatrix:setk(axisK * viewScale)
    newMatrix:settranslation(gizmoMatrix:gettranslation())
    return newMatrix
  end

  self._Meshes[1].Geometry.onGetViewDependentMatrix = onGetHandleMatrix
  self._Meshes[1].GeometryTransparent.onGetViewDependentMatrix = onGetHandleMatrix
  self._Meshes[3].Geometry.onGetViewDependentMatrix = onGetShaftMatrix
  self._Meshes[3].GeometryTransparent.onGetViewDependentMatrix = onGetShaftMatrix
  return self
end
