local PRECISION = {}

local MODIFIER_CTRL = rawget(_G, "LUI_MODIFIER_CTRL") or 16
local MODIFIER_SHIFT = rawget(_G, "LUI_MODIFIER_SHIFT") or 8
local DEFAULT_MOVE_SNAP_STEP = 0.25
local DEFAULT_SCALE_SNAP_STEP = 0.1
local DEFAULT_ROTATE_SNAP_DEGREES = 15
local DEFAULT_ROTATE_COARSE_SNAP_DEGREES = 45

local PRECISION_FACTORS = {
  move = 0.1,
  rotate = 0.25,
  scale = 0.1
}

local function hasModifier(modifier, flag)
  return modifier ~= nil and modifier % (flag * 2) >= flag
end

local function getFloatPlug(name, defaultValue)
  local globals = rawget(_G, "LUIGlobals")
  if not globals then
    return
  end
  if not globals[name] then
    Plug(globals, name, Plug.NoSerial, LUIPSTypeFloat, defaultValue)
  end
  return globals[name]
end

local function quantize(value, step)
  if not step or step <= 0 then
    return value
  end
  return math.floor(value / step + 0.5) * step
end

local function currentModifiers(modifier)
  if modifier ~= nil then
    return modifier
  end
  local mouse = rawget(_G, "LUIMouseModifiers")
  if mouse ~= nil then
    return mouse
  end
  local dragging = rawget(_G, "LUIDragingModifiers")
  if dragging ~= nil then
    return dragging
  end
end

function PRECISION.isCtrlDown(modifier)
  local modifiers = currentModifiers(modifier)
  if modifiers ~= nil then
    return hasModifier(modifiers, MODIFIER_CTRL)
  end
  return rawget(_G, "LUIGizmoPrecisionCtrlDown") and true or false
end

function PRECISION.isShiftDown(modifier)
  local modifiers = currentModifiers(modifier)
  if modifiers ~= nil then
    return hasModifier(modifiers, MODIFIER_SHIFT)
  end
  return false
end

function PRECISION.isGridSnapDown()
  return rawget(_G, "LUIGizmoGridSnapDown") and true or false
end

function PRECISION.isSurfaceSnapDown()
  return rawget(_G, "LUIGizmoSurfaceSnapDown") and true or false
end

function PRECISION.getMoveSnapStep()
  local plug = getFloatPlug("GizmoMoveSnapStep", DEFAULT_MOVE_SNAP_STEP)
  local value = plug and plug:get() or DEFAULT_MOVE_SNAP_STEP
  return math.max(1.0e-4, value or DEFAULT_MOVE_SNAP_STEP)
end

function PRECISION.getScaleSnapStep()
  local plug = getFloatPlug("GizmoScaleSnapStep", DEFAULT_SCALE_SNAP_STEP)
  local value = plug and plug:get() or DEFAULT_SCALE_SNAP_STEP
  return math.max(1.0e-4, value or DEFAULT_SCALE_SNAP_STEP)
end

function PRECISION.getRotateSnapAngle()
  local plug = getFloatPlug("GizmoRotateSnapDegrees", DEFAULT_ROTATE_SNAP_DEGREES)
  local value = plug and plug:get() or DEFAULT_ROTATE_SNAP_DEGREES
  return math.rad(math.max(0.1, value or DEFAULT_ROTATE_SNAP_DEGREES))
end

function PRECISION.getRotateCoarseSnapAngle()
  local plug = getFloatPlug("GizmoRotateCoarseSnapDegrees", DEFAULT_ROTATE_COARSE_SNAP_DEGREES)
  local value = plug and plug:get() or DEFAULT_ROTATE_COARSE_SNAP_DEGREES
  return math.rad(math.max(0.1, value or DEFAULT_ROTATE_COARSE_SNAP_DEGREES))
end

function PRECISION.factor(kind, modifier)
  if PRECISION.isCtrlDown(modifier) then
    -- Keep existing Shift and Ctrl+Shift rotate snapping semantics intact.
    if kind == "rotate" and PRECISION.isShiftDown(modifier) then
      return 1
    end
    return PRECISION_FACTORS[kind] or 1
  end
  return 1
end

function PRECISION.beginScalar(self, kind, rawValue, modifier)
  self._PrecisionKind = kind
  self._PrecisionScalarStart = rawValue or 0
  self._PrecisionScalarAccum = 0
  self._PrecisionFactor = PRECISION.factor(kind, modifier)
end

function PRECISION.scalarDelta(self, kind, rawValue, modifier)
  if self._PrecisionKind ~= kind or self._PrecisionScalarStart == nil then
    PRECISION.beginScalar(self, kind, rawValue or 0, modifier)
  end
  local current = rawValue or 0
  local nextFactor = PRECISION.factor(kind, modifier)
  if math.abs((self._PrecisionFactor or 1) - nextFactor) > 1.0e-6 then
    self._PrecisionScalarAccum = (self._PrecisionScalarAccum or 0) + (current - self._PrecisionScalarStart) * (self._PrecisionFactor or 1)
    self._PrecisionScalarStart = current
    self._PrecisionFactor = nextFactor
  end
  return (self._PrecisionScalarAccum or 0) + (current - self._PrecisionScalarStart) * (self._PrecisionFactor or 1)
end

function PRECISION.beginVector(self, kind, startPoint, modifier)
  self._PrecisionKind = kind
  self._PrecisionVectorStart = startPoint
  self._PrecisionVectorAccum = point3.create(0, 0, 0)
  self._PrecisionFactor = PRECISION.factor(kind, modifier)
end

function PRECISION.vectorDelta(self, kind, currentPoint, modifier)
  if not currentPoint then
    return point3.create(0, 0, 0)
  end
  if self._PrecisionKind ~= kind or self._PrecisionVectorStart == nil then
    PRECISION.beginVector(self, kind, currentPoint, modifier)
  end
  local nextFactor = PRECISION.factor(kind, modifier)
  if math.abs((self._PrecisionFactor or 1) - nextFactor) > 1.0e-6 then
    self._PrecisionVectorAccum = (self._PrecisionVectorAccum or point3.create(0, 0, 0)) + (currentPoint - self._PrecisionVectorStart) * (self._PrecisionFactor or 1)
    self._PrecisionVectorStart = currentPoint
    self._PrecisionFactor = nextFactor
  end
  return (self._PrecisionVectorAccum or point3.create(0, 0, 0)) + (currentPoint - self._PrecisionVectorStart) * (self._PrecisionFactor or 1)
end

function PRECISION.endDrag(self)
  self._PrecisionKind = nil
  self._PrecisionScalarStart = nil
  self._PrecisionScalarAccum = nil
  self._PrecisionVectorStart = nil
  self._PrecisionVectorAccum = nil
  self._PrecisionFactor = nil
end

function PRECISION.snapPoint(point, modifier)
  if not point then
    return point
  end
  local snapped = point
  local globals = rawget(_G, "LUIGlobals")
  local raySnap = globals and globals.RaySnap and LUIPlugGetValue(globals.RaySnap)
  local snap = rawget(_G, "getsnapposition")
  if snap and (PRECISION.isSurfaceSnapDown(modifier) or raySnap) then
    local candidate = snap(point)
    if candidate then
      snapped = candidate
    end
  end
  if PRECISION.isGridSnapDown(modifier) then
    local step = PRECISION.getMoveSnapStep()
    snapped = point3.create(
      quantize(snapped[1], step),
      quantize(snapped[2], step),
      quantize(snapped[3], step)
    )
  end
  return snapped
end

function PRECISION.snapScale(scaleValue)
  if not scaleValue or not PRECISION.isGridSnapDown() then
    return scaleValue
  end
  local step = PRECISION.getScaleSnapStep()
  return math.max(0.01, 1 + quantize(scaleValue - 1, step))
end

return PRECISION
