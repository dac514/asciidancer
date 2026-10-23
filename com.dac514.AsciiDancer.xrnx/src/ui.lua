--[[
  ViewBuilder UI for the main dialog: the ASCII dancer visualizer. Pure
  construction: returns the builder (so the dev bridge can map ids to views),
  the root view and the dancer component, which `App.show_dialog` starts once
  the dialog exists.
]]

local dancer_view = require "src.dancer_view"

local M = {}

---@param app table The application module (`src/app.lua`).
---@return renoise.ViewBuilder vb, renoise.Views.View root, DancerComponent component
function M.build(app)
  local vb = renoise.ViewBuilder()
  local component = dancer_view.new(vb, app)
  local root = vb:column {
    id = "root",
    margin = renoise.ViewBuilder.DEFAULT_DIALOG_MARGIN,
    component.view,
  }
  return vb, root, component
end

return M
