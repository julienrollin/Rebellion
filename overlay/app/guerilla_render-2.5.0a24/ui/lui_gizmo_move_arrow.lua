require("opengl")
require("lui_gizmo_move")
local GIZMO_THEME = require("lui_gizmo_theme")
local GIZMO_PRECISION = require("lui_gizmo_precision")

LUIVTCreate("LUIGizmoMoveArrow", "LUIGizmoMove")

local MOVE_ARROW_COLORS = GIZMO_THEME.axis
local GIZMO_REACH_DEFAULT_SCALE = 1.5
-- User-tunable shaft thickness for the move gizmo.
local MOVE_ARROW_LINE_WIDTH = 3
local MOVE_ARROW_LINE_LENGTH = 3.6
local MOVE_ARROW_CONE_LENGTH_SCALE = 0.8
-- Extra gap added after the end of the shaft line.
local MOVE_ARROW_CONE_OFFSET = 0
local _MOVE_ARROW_CONE_BASE_X

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

local function LUIGetMoveArrowLineLength()
  -- Move gizmo length is driven by its own scale plug so +/- only stretches shafts.
  return MOVE_ARROW_LINE_LENGTH * LUIGetMoveArrowLineScale()
end

local function LUIGetMoveArrowViewScale(view, gizmoMatrix)
  return LUIPlugGetValue(LUIGlobals.ToolSize) * _LUI3dComputeScaleFactor(view, gizmoMatrix:gettranslation())
end

local function LUICreateMoveArrowShaftMesh(length)
  local shaft = linemesh()
  shaft.LineWidth = MOVE_ARROW_LINE_WIDTH
  shaft:addpolyline({
    0, 0, 0,
    length, 0, 0
  }, false)
  return {LUIOpenGLMeshCreateFromLine(shaft, 0)}
end

local function LUIGetMoveArrowConeBaseX()
  if _MOVE_ARROW_CONE_BASE_X ~= nil then
    return _MOVE_ARROW_CONE_BASE_X
  end
  local _, laabb = GAMeshBankGetMesh(GAMeshBank, "gizmo_cone")
  if not laabb then
    _MOVE_ARROW_CONE_BASE_X = 0
    return _MOVE_ARROW_CONE_BASE_X
  end
  local min = laabb:getmin()
  -- The stock cone mesh is authored offset from the origin; keep its local base anchored.
  _MOVE_ARROW_CONE_BASE_X = min[1] or 0
  return _MOVE_ARROW_CONE_BASE_X
end

function LUIGizmoMoveArrowVT:onLDown(x, y, view)
  local selectionTransform = self._Tool.SelectionTransform:get()
  self._InitPos = selectionTransform:getmatrix():gettranslation()
  self._InitAxis = self.Transform:get():getmatrix():geti():getnormalized()
  LUIGizmoMoveVT.onLDown(self, x, y, view)
  GIZMO_PRECISION.beginVector(self, "move", self._Start, rawget(_G, "LUIMouseModifiers"))
end

function LUIGizmoMoveArrowVT:onGetPoint(view, x, y)
  return LUI3d2dToLine(view, x, y, self._InitPos, self._InitAxis)
end

function LUIGizmoMoveArrowVT:onDrag(view, x, y, lx, ly, modifier)
  local current = GIZMO_PRECISION.snapPoint(self:onGetPoint(view, lx, ly), modifier)
  if not current then
    return 0, 0
  end
  self._SetPosition = nil
  self._Translation = GIZMO_PRECISION.vectorDelta(self, "move", current, modifier)
  self._Tool:dotransformmodification(self)
  return 0, 0
end

function LUIGizmoMoveArrowVT:onDragEnd(view, x, y)
  GIZMO_PRECISION.endDrag(self)
  return LUIGizmoMoveVT.onDragEnd(self, view, x, y)
end

function LUIGizmoMoveArrowVT:_updateShaftMesh()
  local length = LUIGetMoveArrowLineLength()
  if self._ShaftMeshLength == length then
    return
  end
  local mesh = LUICreateMoveArrowShaftMesh(length)
  self._Meshes[3].Geometry.Mesh:set(mesh)
  self._Meshes[3].GeometryTransparent.Mesh:set(mesh)
  self._ShaftMeshLength = length
end

function LUIGizmoMoveArrowVT:eval(plug)
  if plug == self.Transform then
    local gizmoMatrix = matrix.create(true)
    local toolMatrix = self._Tool.ToolTransform:get():getmatrix()
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
  elseif plug == self.ConeTransform then
    local baseMatrix = self.Transform:get():getmatrix()
    local coneMatrix = matrix.create(baseMatrix)
    local extraLength = LUIGetMoveArrowLineLength() - MOVE_ARROW_LINE_LENGTH + MOVE_ARROW_CONE_OFFSET
    if extraLength ~= 0 then
      coneMatrix:settranslation(baseMatrix:transform(point3.create(extraLength, 0, 0)))
    end
    return transform.create(coneMatrix)
  elseif plug == self.ShaftTransform then
    self:_updateShaftMesh()
    return self.Transform:get()
  elseif plug == self.MeshFlags then
    local hidden = LUIGlobals.TransformTool:get() ~= "move" or not self.PrimitiveSelected:get()
    return GLdisplay.HideOnXFront + GLdisplay.NoLigthing + GLdisplay.ViewDependent + (hidden and GLdisplay.Hidden or 0)
  elseif plug == self.MeshScaleFactor then
    return LUIGlobals.ToolSize:get()
  end
  return LUIGizmoMoveVT.eval(self, plug)
end

function LUIGizmoMoveArrowVT:getGLprops()
  local hidden = LUIGlobals.TransformTool:get() ~= "move" or not self.PrimitiveSelected:get()
  return GLdisplay.NodeTypeMisc + GLdisplay.NodeIgnoreFilter + (hidden and GLdisplay.NodeHidden or 0), 0, 1, 1
end

function LUIGizmoMoveArrowCreate(tool, axis)
  local color = MOVE_ARROW_COLORS[axis] or MOVE_ARROW_COLORS.x
  local self = LUIGizmoMoveCreate(tool, {
    LUIGizmoMeshCreate("gizmo_cone", color),
    LUIGizmoMeshCreate("move_lines", color),
    LUIGizmoMeshCreate(nil, color)
  })
  self._Axis = axis
  setclass(self, LUIGizmoMoveArrowVT)
  self.Transform:adddependencies(tool.ToolTransform)
  self.MeshFlags:adddependencies(self.PrimitiveSelected, rawget(_G, "LUIGlobals").TransformTool)
  Plug(self, "ConeTransform", Plug.NoSerial, types.transform, LUI_MESH_PLUG_DEFAULT_TRANSFORM)
  Plug(self, "ShaftTransform", Plug.NoSerial, types.transform, LUI_MESH_PLUG_DEFAULT_TRANSFORM)
  local lineScalePlug = LUIGetGizmoReachScalePlug()
  if lineScalePlug then
    self.ConeTransform:adddependencies(tool.ToolTransform, lineScalePlug)
    self.ShaftTransform:adddependencies(tool.ToolTransform, lineScalePlug)
  else
    self.ConeTransform:adddependencies(tool.ToolTransform)
    self.ShaftTransform:adddependencies(tool.ToolTransform)
  end
  self._Meshes[1].Transform:disconnectall()
  self._Meshes[1].Transform:connect(self.ConeTransform)
  self._Meshes[3].Transform:disconnectall()
  self._Meshes[3].Transform:connect(self.ShaftTransform)
  self._Meshes[1].Geometry.MeshRenderMode:set(GLdisplay.Filled)
  self._Meshes[1].GeometryTransparent.MeshRenderMode:set(GLdisplay.Filled)
  self._Meshes[2].Geometry.MeshFlags:disconnectall()
  self._Meshes[2].GeometryTransparent.MeshFlags:disconnectall()
  -- Hide the stock thin line and keep only the custom shaft mesh so width/length are controllable.
  self._Meshes[2].Geometry.MeshFlags:set(GLdisplay.Hidden)
  self._Meshes[2].GeometryTransparent.MeshFlags:set(GLdisplay.Hidden)
  self._Meshes[1].Geometry.MeshScaleFactor:disconnectall()
  self._Meshes[1].GeometryTransparent.MeshScaleFactor:disconnectall()
  self._Meshes[3].Geometry.MeshScaleFactor:disconnectall()
  self._Meshes[3].GeometryTransparent.MeshScaleFactor:disconnectall()

  local mesh = LUICreateMoveArrowShaftMesh(LUIGetMoveArrowLineLength())
  self._Meshes[3].Geometry.Mesh:set(mesh)
  self._Meshes[3].GeometryTransparent.Mesh:set(mesh)
  self._ShaftMeshLength = LUIGetMoveArrowLineLength()

  local function onGetConeMatrix(geometry, view)
    local gizmo = geometry:getowner()._Gizmo
    local gizmoMatrix = gizmo.Transform:get():getmatrix()
    local scale = LUIGetMoveArrowViewScale(view, gizmoMatrix)
    local newMatrix = matrix.create(gizmoMatrix)
    local axisI = gizmoMatrix:geti():getnormalized()
    local axisJ = gizmoMatrix:getj():getnormalized()
    local axisK = gizmoMatrix:getk():getnormalized()
    local coneBaseX = LUIGetMoveArrowConeBaseX()
    local extraLength = LUIGetMoveArrowLineLength() - MOVE_ARROW_LINE_LENGTH + MOVE_ARROW_CONE_OFFSET
    local baseAnchorCompensation = scale * coneBaseX * (1 - MOVE_ARROW_CONE_LENGTH_SCALE)
    local coneOffset = scale * extraLength + baseAnchorCompensation
    -- Build the non-uniform scale explicitly in local gizmo axes; LUIMtxSetScaleBefore caused Y/Z drift here.
    newMatrix:seti(axisI * (scale * MOVE_ARROW_CONE_LENGTH_SCALE))
    newMatrix:setj(axisJ * scale)
    newMatrix:setk(axisK * scale)
    newMatrix:settranslation(gizmoMatrix:gettranslation())
    if coneOffset ~= 0 then
      newMatrix:settranslation(gizmoMatrix:transform(point3.create(coneOffset, 0, 0)))
    end
    return newMatrix
  end

  local function onGetShaftMatrix(geometry, view)
    local gizmo = geometry:getowner()._Gizmo
    local gizmoMatrix = gizmo.Transform:get():getmatrix()
    local scale = LUIGetMoveArrowViewScale(view, gizmoMatrix)
    local newMatrix = matrix.create(gizmoMatrix)
    LUIMtxSetScaleBefore(newMatrix, scale, scale, scale)
    return newMatrix
  end

  self._Meshes[1].Geometry.onGetViewDependentMatrix = onGetConeMatrix
  self._Meshes[1].GeometryTransparent.onGetViewDependentMatrix = onGetConeMatrix
  self._Meshes[3].Geometry.onGetViewDependentMatrix = onGetShaftMatrix
  self._Meshes[3].GeometryTransparent.onGetViewDependentMatrix = onGetShaftMatrix
  return self
end
