require("opengl")
require("lui_gizmo_move")
local GIZMO_THEME = require("lui_gizmo_theme")
local GIZMO_PRECISION = require("lui_gizmo_precision")

LUIVTCreate("LUIGizmoMoveRectangle", "LUIGizmoMove")

local MOVE_PLANE_COLORS = {
  center = GIZMO_THEME.center,
  xy = GIZMO_THEME.planes.xy,
  yz = GIZMO_THEME.planes.yz,
  xz = GIZMO_THEME.planes.xz
}
local GIZMO_REACH_DEFAULT_SCALE = 1.5
local MOVE_PLANE_OFFSETS = {
  xy = 2.5,
  yz = 2.5,
  xz = 2.5
}
local MOVE_PLANE_SIZE = 0.68
local MOVE_PLANE_THICKNESS = 0.055
local MOVE_PLANE_LINE_WIDTH = 2
local MOVE_PLANE_FILL_DIVISIONS = 20

local MOVE_PLANE_ARROW_LINKS = {
  xy = {"x", "y"},
  yz = {"y", "z"},
  xz = {"x", "z"}
}

local MOVE_ARROW_GIZMO_INDEX = {
  x = 1,
  y = 2,
  z = 3
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

local function LUIGetMoveArrowLineScale()
  local plug = LUIGetGizmoReachScalePlug()
  local scale = plug and plug:get() or GIZMO_REACH_DEFAULT_SCALE
  return math.max(GIZMO_REACH_DEFAULT_SCALE, scale or GIZMO_REACH_DEFAULT_SCALE)
end

local function LUIGetMovePlaneOffset(axisPair)
  -- Plane handles move outward with the same line-scale as arrows, but their size stays fixed.
  local offset = MOVE_PLANE_OFFSETS[axisPair] or MOVE_PLANE_OFFSETS.xz
  return offset * LUIGetMoveArrowLineScale()
end

local function LUIGetMovePlaneBasis(toolMatrix, axisPair)
  -- j is the plane normal; onGetPoint uses it for the two-axis drag plane.
  local i, j, k
  if axisPair == "center" then
    i = toolMatrix:geti():getnormalized()
    j = toolMatrix:getk():cross(i):getnormalized()
    k = i:cross(j):getnormalized()
  elseif axisPair == "yz" then
    i = toolMatrix:getk():getnormalized()
    j = toolMatrix:geti():getnormalized() * -1
    k = toolMatrix:getj():getnormalized()
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

local function LUICreateMovePlaneMesh(axisPair)
  local offset = LUIGetMovePlaneOffset(axisPair)
  local half = MOVE_PLANE_SIZE * 0.5
  local minv = offset - half
  local maxv = offset + half
  -- Bake the offset into the mesh vertices so +/- repositions planes without scaling the handle itself.
  local lines = linemesh()
  lines.LineWidth = MOVE_PLANE_LINE_WIDTH
  lines:addpolyline({
    minv, 0, minv,
    maxv, 0, minv,
    maxv, 0, maxv,
    minv, 0, maxv
  }, true)
  if MOVE_PLANE_FILL_DIVISIONS > 1 then
    local step = (maxv - minv) / MOVE_PLANE_FILL_DIVISIONS
    for idx = 1, MOVE_PLANE_FILL_DIVISIONS - 1 do
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

function LUIGizmoMoveRectangleVT:_updatePlaneMesh()
  if self._AxisPair == "center" then
    return
  end
  local offset = LUIGetMovePlaneOffset(self._AxisPair)
  if self._PlaneMeshOffset == offset then
    return
  end
  local mesh = LUICreateMovePlaneMesh(self._AxisPair)
  self._Meshes[1].Geometry.Mesh:set(mesh)
  self._Meshes[1].GeometryTransparent.Mesh:set(mesh)
  self._PlaneMeshOffset = offset
end

local function LUISetMovePlaneArrowHighlight(self, highlighted)
  local links = MOVE_PLANE_ARROW_LINKS[self._AxisPair]
  if not links then
    return
  end
  local tool = self._Tool
  if not tool or not tool._PrimGizmos then
    return
  end
  for _, axis in ipairs(links) do
    local gizmo = tool._PrimGizmos[MOVE_ARROW_GIZMO_INDEX[axis]]
    if gizmo and gizmo ~= self and gizmo.Selected then
      gizmo.Selected:set(highlighted and true or false)
    end
  end
end

function LUIGizmoMoveRectangleVT:onLDown(x, y, view)
  local gm = self._Tool.SelectionTransform:get()
  self._InitPos = gm:getmatrix():gettranslation()
  if self._AxisPair == "center" then
    self._InitNormal = view:getviewworldmatrixorient():getk()
  else
    self._InitNormal = self.Transform:get():getmatrix():getj():getnormalized()
  end
  LUIGizmoMoveVT.onLDown(self, x, y, view)
  GIZMO_PRECISION.beginVector(self, "move", self._Start, rawget(_G, "LUIMouseModifiers"))
  LUISetMovePlaneArrowHighlight(self, true)
end

function LUIGizmoMoveRectangleVT:onGetPoint(view, x, y)
  return LUI3d2dToPlane(view, x, y, self._InitPos, self._InitNormal)
end

function LUIGizmoMoveRectangleVT:onDrag(view, x, y, lx, ly, modifier)
  local current = GIZMO_PRECISION.snapPoint(self:onGetPoint(view, lx, ly), modifier)
  if not current then
    return 0, 0
  end
  self._SetPosition = nil
  self._Translation = GIZMO_PRECISION.vectorDelta(self, "move", current, modifier)
  self._Tool:dotransformmodification(self)
  return 0, 0
end

function LUIGizmoMoveRectangleVT:onDragEnd(view, x, y)
  GIZMO_PRECISION.endDrag(self)
  LUISetMovePlaneArrowHighlight(self, false)
  return LUIGizmoMoveRectangleVT.Parent.onDragEnd(self, view, x, y)
end

function LUIGizmoMoveRectangleVT:eval(plug)
  if plug == self.Transform then
    self:_updatePlaneMesh()
    local gizmoMatrix = matrix.create(true)
    local toolMatrix = self._Tool.ToolTransform:get():getmatrix()
    local i, j, k = LUIGetMovePlaneBasis(toolMatrix, self._AxisPair)
    gizmoMatrix:seti(i)
    gizmoMatrix:setj(j)
    gizmoMatrix:setk(k)
    gizmoMatrix:settranslation(toolMatrix:gettranslation())
    return transform.create(gizmoMatrix)
  elseif plug == self.MeshFlags then
    local hidden = LUIGlobals.TransformTool:get() ~= "move" or not self.PrimitiveSelected:get()
    if self._AxisPair == "center" then
      return GLdisplay.NoLigthing + (hidden and GLdisplay.Hidden or 0)
    end
    return GLdisplay.SetDoubleSided + GLdisplay.NoLigthing + (hidden and GLdisplay.Hidden or 0)
  elseif plug == self.MeshScaleFactor then
    return LUIGlobals.ToolSize:get()
  end
  return LUIGizmoMoveVT.eval(self, plug)
end

function LUIGizmoMoveRectangleVT:getPickPriority()
  return 2
end

function LUIGizmoMoveRectangleVT:getGLprops()
  return LUIGizmoMoveVT.getGLprops(self)
end

function LUIGizmoMoveRectangleCreate(tool, axisPair)
  axisPair = axisPair or "center"
  local color = MOVE_PLANE_COLORS[axisPair] or MOVE_PLANE_COLORS.center
  local meshName = axisPair == "center" and "gizmo_halfcube" or nil
  local self = LUIGizmoMoveCreate(tool, {
    LUIGizmoMeshCreate(meshName, color)
  })
  setclass(self, LUIGizmoMoveRectangleVT)
  self._AxisPair = axisPair
  local globals = rawget(_G, "LUIGlobals")
  local lineScalePlug = LUIGetGizmoReachScalePlug()
  if lineScalePlug then
    self.Transform:adddependencies(tool.ToolTransform, lineScalePlug)
  else
    self.Transform:adddependencies(tool.ToolTransform)
  end
  self.MeshFlags:adddependencies(self.PrimitiveSelected, globals.TransformTool)
  self._Meshes[1].Color:set(color)
  self._Meshes[1].Geometry.MeshRenderMode:set(GLdisplay.Filled)
  self._Meshes[1].GeometryTransparent.MeshRenderMode:set(GLdisplay.Filled)

  if axisPair == "center" then
    return self
  end

  local mesh = LUICreateMovePlaneMesh(axisPair)
  self._Meshes[1].Geometry.Mesh:set(mesh)
  self._Meshes[1].GeometryTransparent.Mesh:set(mesh)
  self._Meshes[1].Geometry.MeshRenderMode:set(GLdisplay.WireFrame)
  self._Meshes[1].GeometryTransparent.MeshRenderMode:set(GLdisplay.WireFrame)
  self._PlaneMeshOffset = LUIGetMovePlaneOffset(axisPair)
  return self
end
