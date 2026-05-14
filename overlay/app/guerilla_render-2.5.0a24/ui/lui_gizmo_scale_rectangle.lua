require("opengl")
require("lui_gizmo_scale")
local GIZMO_THEME = require("lui_gizmo_theme")
local GIZMO_PRECISION = require("lui_gizmo_precision")

LUIVTCreate("LUIGizmoScaleRectangle", "LUIGizmoScale")

local SCALE_PLANE_COLORS = {
  center = GIZMO_THEME.center,
  xy = GIZMO_THEME.planes.xy,
  yz = GIZMO_THEME.planes.yz,
  xz = GIZMO_THEME.planes.xz
}
local GIZMO_REACH_DEFAULT_SCALE = 1.5
local SCALE_PLANE_OFFSETS = {
  xy = 2.5,
  yz = 2.5,
  xz = 2.5
}
local SCALE_PLANE_SIZE = 0.68
local SCALE_PLANE_LINE_WIDTH = 2
local SCALE_PLANE_FILL_DIVISIONS = 20

local SCALE_PLANE_AXIS_LINKS = {
  xy = {"x", "y"},
  yz = {"y", "z"},
  xz = {"x", "z"}
}

local SCALE_AXIS_GIZMO_INDEX = {
  x = 17,
  y = 18,
  z = 19
}

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

local function LUIGetScalePlaneOffset(axisPair)
  -- Plane handles move outward with the same line-scale as the axis cubes, but their size stays fixed.
  local offset = SCALE_PLANE_OFFSETS[axisPair] or SCALE_PLANE_OFFSETS.xz
  return offset * LUIGetScaleLineScale()
end

local function LUIGetScalePlaneBasis(toolMatrix, axisPair)
  -- j is the plane normal; scaling uses local x/z so they must match the two intended axes.
  local i, j, k
  if axisPair == "center" then
    i = toolMatrix:geti():getnormalized()
    j = toolMatrix:getk():cross(i):getnormalized()
    k = i:cross(j):getnormalized()
  elseif axisPair == "yz" then
    i = toolMatrix:getj():getnormalized()
    j = toolMatrix:geti():getnormalized() * -1
    k = toolMatrix:getk():getnormalized()
  elseif axisPair == "xz" then
    i = toolMatrix:geti():getnormalized()
    j = toolMatrix:getj():getnormalized()
    k = toolMatrix:getk():getnormalized()
  else
    i = toolMatrix:geti():getnormalized()
    j = toolMatrix:getk():getnormalized() * -1
    k = toolMatrix:getj():getnormalized()
  end
  return i, j, k
end

local function LUICreateScalePlaneMesh(axisPair)
  local offset = LUIGetScalePlaneOffset(axisPair)
  local half = SCALE_PLANE_SIZE * 0.5
  local minv = offset - half
  local maxv = offset + half
  -- Bake the offset into the mesh vertices so +/- repositions the handle without scaling the square itself.
  local lines = linemesh()
  lines.LineWidth = SCALE_PLANE_LINE_WIDTH
  lines:addpolyline({
    minv, 0, minv,
    maxv, 0, minv,
    maxv, 0, maxv,
    minv, 0, maxv
  }, true)
  if SCALE_PLANE_FILL_DIVISIONS > 1 then
    local step = (maxv - minv) / SCALE_PLANE_FILL_DIVISIONS
    for idx = 1, SCALE_PLANE_FILL_DIVISIONS - 1 do
      local pos = minv + step * idx
      lines:addpolyline({
        pos, 0, minv,
        pos, 0, maxv
      }, false)
      lines:addpolyline({
        minv, 0, pos,
        maxv, 0, pos
      }, false)
    end
  end
  return {LUIOpenGLMeshCreateFromLine(lines, 0)}
end

local function LUISetScalePlaneAxisHighlight(self, highlighted)
  local links = SCALE_PLANE_AXIS_LINKS[self._AxisPair]
  if not links then
    return
  end
  local tool = self._Tool
  if not tool or not tool._PrimGizmos then
    return
  end
  for _, axis in ipairs(links) do
    local gizmo = tool._PrimGizmos[SCALE_AXIS_GIZMO_INDEX[axis]]
    if gizmo and gizmo ~= self and gizmo.Selected then
      gizmo.Selected:set(highlighted and true or false)
    end
  end
end

local function LUISafeScaleRatio(currentValue, startValue)
  if math.abs(startValue) < 1.0e-4 then
    return 1
  end
  return currentValue / startValue
end

local function LUIGetUniformPlaneScale(currentLocal, startLocal)
  -- Plane scale should stay locked on both active axes; use one shared factor along the handle diagonal.
  local startProjection = startLocal[1] + startLocal[3]
  if math.abs(startProjection) < 1.0e-4 then
    return 1
  end
  local currentProjection = currentLocal[1] + currentLocal[3]
  return math.max(0.01, currentProjection / startProjection)
end

local function LUIGetScaleDisplayMatrix(tool)
  return tool.ToolTransform:get():getmatrix()
end

function LUIGizmoScaleRectangleVT:_updatePlaneMesh()
  if self._AxisPair == "center" then
    return
  end
  local offset = LUIGetScalePlaneOffset(self._AxisPair)
  if self._PlaneMeshOffset == offset then
    return
  end
  local mesh = LUICreateScalePlaneMesh(self._AxisPair)
  self._Meshes[1].Geometry.Mesh:set(mesh)
  self._Meshes[1].GeometryTransparent.Mesh:set(mesh)
  self._PlaneMeshOffset = offset
end

function LUIGizmoScaleRectangleVT:onLDown(x, y, view)
  self._InitPos = LUIGetScaleDisplayMatrix(self._Tool):gettranslation()
  if self._AxisPair == "center" then
    self._InitAxis = view:getviewworldmatrixorient():getk()
    LUIGizmoScaleVT.onLDown(self, x, y, view)
    local gizmoMatrix = self.Transform:get():getmatrix()
    self._ToWorld:copy(gizmoMatrix)
    self._ToLocal:copy(gizmoMatrix)
    LUIMtxInvert(self._ToLocal)
    GIZMO_PRECISION.beginScalar(self, "scale", 0, rawget(_G, "LUIMouseModifiers"))
    return
  end

  local gizmoMatrix = self.Transform:get():getmatrix()
  self._InitNormal = gizmoMatrix:getj():getnormalized()
  self._ToWorld:copy(gizmoMatrix)
  self._ToLocal:copy(gizmoMatrix)
  LUIMtxInvert(self._ToLocal)
  LUIGizmoScaleVT.Parent.onLDown(self, x, y, view)
  local start = self:onGetPoint(view, x, y)
  self._StartLocal = start and self._ToLocal:transform(start) or point3.create(1, 0, 1)
  GIZMO_PRECISION.beginScalar(self, "scale", 0, rawget(_G, "LUIMouseModifiers"))
  LUISetScalePlaneAxisHighlight(self, true)
end

function LUIGizmoScaleRectangleVT:onGetPoint(view, x, y)
  if self._AxisPair == "center" then
    return LUI3d2dToPlane(view, x, y, self._InitPos, self._InitAxis)
  end
  return LUI3d2dToPlane(view, x, y, self._InitPos, self._InitNormal)
end

function LUIGizmoScaleRectangleVT:onDrag(view, x, y, lx, ly, modifier)
  if self._AxisPair == "center" then
    local k = math.pow(10, GIZMO_PRECISION.scalarDelta(self, "scale", x / LUI3dInteractiveZoomSpeed, modifier))
    k = GIZMO_PRECISION.snapScale(k, modifier)
    self._ScaleMatrix:copy(self._ToLocal)
    self._LocScaleMatrix:setidentity()
    self._LocScaleMatrix:scale(k, k, k)
    LUIMtxCompose(self._ScaleMatrix, self._LocScaleMatrix)
    LUIMtxCompose(self._ScaleMatrix, self._ToWorld)
    self._ScaleMatrix:settranslation(point3.create(0, 0, 0))
    self._Tool:dotransformmodification(self)
    return 0, 0
  end

  local current = self:onGetPoint(view, lx, ly)
  if not current then
    return 0, 0
  end

  local localCurrent = self._ToLocal:transform(current)
  local rawScale = LUIGetUniformPlaneScale(localCurrent, self._StartLocal)
  local lockedScale = math.max(0.01, 1 + GIZMO_PRECISION.scalarDelta(self, "scale", rawScale - 1, modifier))
  local snappedScale = GIZMO_PRECISION.snapScale(lockedScale, modifier)
  self._ScaleMatrix:copy(self._ToLocal)
  self._LocScaleMatrix:setidentity()
  self._LocScaleMatrix:scale(snappedScale, 1, snappedScale)
  LUIMtxCompose(self._ScaleMatrix, self._LocScaleMatrix)
  LUIMtxCompose(self._ScaleMatrix, self._ToWorld)
  self._ScaleMatrix:settranslation(point3.create(0, 0, 0))
  self._Tool:dotransformmodification(self)
  return 0, 0
end

function LUIGizmoScaleRectangleVT:onDragEnd(view, x, y)
  GIZMO_PRECISION.endDrag(self)
  LUISetScalePlaneAxisHighlight(self, false)
  return LUIGizmoScaleVT.onDragEnd(self, view, x, y)
end

function LUIGizmoScaleRectangleVT:doModification(object)
  return LUIGizmoScaleVT.doModification(self, object)
end

function LUIGizmoScaleRectangleVT:getPickPriority()
  return 2
end

function LUIGizmoScaleRectangleVT:eval(plug)
  if plug == self.Transform then
    self:_updatePlaneMesh()
    local gizmoMatrix = matrix.create(true)
    local toolMatrix = LUIGetScaleDisplayMatrix(self._Tool)
    local i, j, k = LUIGetScalePlaneBasis(toolMatrix, self._AxisPair)
    gizmoMatrix:seti(i)
    gizmoMatrix:setj(j)
    gizmoMatrix:setk(k)
    gizmoMatrix:settranslation(toolMatrix:gettranslation())
    return transform.create(gizmoMatrix)
  elseif plug == self.MeshFlags then
    local hidden = LUIPlugGetValue(LUIGlobals.TransformTool) ~= "scale" or not LUIPlugGetValue(self.PrimitiveSelected)
    if self._AxisPair == "center" then
      return GLdisplay.NoLigthing + (hidden and GLdisplay.Hidden or 0)
    end
    return GLdisplay.SetDoubleSided + GLdisplay.NoLigthing + (hidden and GLdisplay.Hidden or 0)
  elseif plug == self.MeshScaleFactor then
    return LUIPlugGetValue(LUIGlobals.ToolSize)
  end
  return LUIGizmoScaleVT.eval(self, plug)
end

function LUIGizmoScaleRectangleVT:getGLprops()
  local hidden = LUIGlobals.TransformTool:get() ~= "scale" or not self.PrimitiveSelected:get()
  return GLdisplay.NodeConstantScale + (hidden and GLdisplay.NodeHidden or 0) + GLdisplay.NodeTypeMisc + GLdisplay.NodeIgnoreFilter, 0, 1, LUIGlobals.ToolSize:get()
end

function LUIGizmoScaleRectangleCreate(tool, axisPair)
  axisPair = axisPair or "center"
  local color = SCALE_PLANE_COLORS[axisPair] or SCALE_PLANE_COLORS.center
  local meshName = axisPair == "center" and "gizmo_halfcube" or nil
  local self = LUIGizmoScaleCreate(tool, {
    LUIGizmoMeshCreate(meshName, color)
  })
  LUIVTSetClass(self, LUIGizmoScaleRectangleVT)
  self._AxisPair = axisPair
  local lineScalePlug = LUIGetGizmoReachScalePlug()
  if lineScalePlug then
    LUIPlugAddDependencies(self.Transform, tool.ToolTransform, lineScalePlug)
  else
    LUIPlugAddDependencies(self.Transform, tool.ToolTransform)
  end
  LUIPlugAddDependencies(self.MeshFlags, self.PrimitiveSelected, LUIGlobals.TransformTool)
  self._Meshes[1].Color:set(color)
  self._Meshes[1].Geometry.MeshRenderMode:set(GLdisplay.Filled)
  self._Meshes[1].GeometryTransparent.MeshRenderMode:set(GLdisplay.Filled)

  if axisPair == "center" then
    return self
  end

  local mesh = LUICreateScalePlaneMesh(axisPair)
  self._Meshes[1].Geometry.Mesh:set(mesh)
  self._Meshes[1].GeometryTransparent.Mesh:set(mesh)
  self._Meshes[1].Geometry.MeshRenderMode:set(GLdisplay.WireFrame)
  self._Meshes[1].GeometryTransparent.MeshRenderMode:set(GLdisplay.WireFrame)
  self._PlaneMeshOffset = LUIGetScalePlaneOffset(axisPair)
  return self
end
