-- Centralized gizmo palette so move/scale/rotate share the same axis colors.
local theme = {
  axis = {
    x = {0.9137254902, 0.2196078431, 0.3098039216, 1},
    y = {0.4901960784, 0.7725490196, 0.1254901961, 1},
    z = {0.1921568627, 0.5137254902, 0.9058823529, 1}
  },
  planes = {
    -- Plane colors follow the excluded axis color with reduced alpha.
    xy = {0.1921568627, 0.5137254902, 0.9058823529, 0.7},
    yz = {0.9137254902, 0.2196078431, 0.3098039216, 0.7},
    xz = {0.4901960784, 0.7725490196, 0.1254901961, 0.7}
  },
  center = {0.95, 0.82, 0.18, 1},
  view = {0.95, 0.82, 0.18, 1}
}

rawset(_G, "LUI_GIZMO_THEME", theme)

return theme
