require("lui_color_picker")

LUIVTCreate("LUIColorBox", "LUIControl", "Window")
LUIVTCreate("LUIColorBoxBox", "LUIFrame8")
LUIWindowHookVTIndex(LUIColorBoxVT)

local ColorBoxWidth = 80

local function clampByte(value)
  return math.max(0, math.min(255, math.floor(255 * (value or 0) + 0.5)))
end

local function applyHexClipboard(box)
  local rgb = LUIColorPickerHexToRenderingRGB(LUIClipboardGet())
  if rgb then
    LUIControlSetValue(box:getparent(), rgb, nil, false)
    return true
  end
  return false
end

function LUIColorBoxBoxVT:copy()
  local rgb = LUIControlGetValue(self:getparent())
  LUIClipboardPut(LUICopyObjectIntoBuffer(rgb, types.color))
end

function LUIColorBoxBoxVT:paste()
  if applyHexClipboard(self) then
    return
  end
  local rgb = LUIPasteObjectFromClipboard(LUIPSTypeColor)
  if rgb and type(rgb) == "table" and type(rgb[1]) == "number" and type(rgb[2]) == "number" and type(rgb[3]) == "number" then
    LUIControlSetValue(self:getparent(), rgb, nil, false)
  end
end

function LUIColorBoxBoxVT:onKeyDown(c, modifier)
  if c == LUI_KEY_RETURN and modifier == 0 then
    self:onLDoubleClick()
    return true
  elseif c == LUI_KEY_C and modifier == LUI_MODIFIER_CTRL then
    self:copy()
    return true
  elseif c == LUI_KEY_V and modifier == LUI_MODIFIER_CTRL then
    self:paste()
    return true
  end
end

function LUIColorBoxBoxVT:onLDoubleClick(lx, ly)
  local x, y
  if lx and ly then
    x, y = LUIWindowGetScreenPoint(self, lx, ly)
  end
  local parent = self:getparent()
  local box = LUIColorPickerBoxCreate(self.Attributes, x, y)
  local inputs = parent.Input:getdependencies()
  if inputs then
    if parent.Desc.IsInstanciable then
      local mod = Document:modify()
      local realinputs = {}
      for _, plug in pairs(inputs) do
        table.insert(realinputs, parent.Desc:instanciate(plug))
      end
      inputs = realinputs
      mod.finish()
    end
    for _, plug in pairs(inputs) do
      box.Input:adddependencies(plug)
    end
  end
end

function LUIColorBoxBoxVT:onRDown(x, y)
  local colorBox = self
  local openCmd = command.create("Open")
  function openCmd:Action(window)
    colorBox:onLDoubleClick()
  end
  local copyCmd = command.create("Copy")
  function copyCmd:Action(window)
    colorBox:copy()
  end
  local pasteCmd = command.create("Paste")
  function pasteCmd:Action(window)
    colorBox:paste()
  end
  LUIMenuCreate({
    openCmd,
    copyCmd,
    pasteCmd
  }, self)
end

function LUIColorBoxVT:onUpdateControl2()
  local rgb = LUIControlGetValue(self)
  if type(rgb) == "number" then
    rgb = {rgb, rgb, rgb}
  elseif type(rgb) ~= "table" then
    rgb = {0, 0, 0}
  end
  local grgb = ocio.renderingtopicker(rgb)
  LUIWindowSetColor(self._ColorQuad, LUIRGB(clampByte(grgb[1]), clampByte(grgb[2]), clampByte(grgb[3])))
end

function LUIColorBoxBoxCreate(name, parent, style, attributes)
  local self = LUIFrame8Create(name, parent, style)
  local color = LUIQuadCreate("color", self)
  LUIVTSetClass(self, LUIColorBoxBoxVT)
  LUIWindowSetX(color, 0)
  LUIWindowSetY(color, 0)
  LUIWindowSetW(color, 0, 1)
  LUIWindowSetH(color, 0, 1)
  self.Attributes = attributes
  self.Focusable = true
  self._EnableRDown = true
  color.Layer = 10
  parent._ColorQuad = color
  return self
end

function LUIColorBoxCreate(name, parent, style, attributes)
  local self = LUIWindowCreate(name, parent, style)
  local box = LUIColorBoxBoxCreate("box", self, style, attributes)
  LUIVTSetClass(self, LUIColorBoxVT)

  LUIWindowSetX(box, 0)
  LUIWindowSetW(box, ColorBoxWidth)

  local slider = LUISliderCreate("slider", self, nil, attributes.Desc, attributes)
  slider.Attribute = attributes
  slider:setw(-ColorBoxWidth, 1)
  slider:seth(0, 1)
  slider:setx(ColorBoxWidth)

  ViewPlug(self, "Input", Plug.NoSerial + LUI_PLUG_THROUGH, types.color)
  ViewPlug(self, "ScreenGamma", Plug.NoSerial, types.float({}))

  local preferences = Document:getpreferences()
  if preferences then
    self.ScreenGamma:connect(preferences.ScreenGamma)
  end

  slider.Input:adddependencies(self.Input)
  self.AttrName = attributes.AttrName

  return self
end
