--[[
  The ASCII dancer GUI component: a black canvas backdrop with the dancer's
  frame drawn over it as monospace text, a tempo status line above and the
  current move's caption below. Owns the timer that polls the song and
  advances the dancer; the timer retires itself when its dialog goes away.
]]

local Dancer = require "src.dancer"
local probe = require "src.song_probe"

local M = {}

local TICK_MS = 40
local FONT = "mono"
---Pixels between the backdrop edge and the text.
local PAD = 6
local BACKDROP = { 10, 11, 13 }
local FLOOR = { 58, 66, 62 }
---Text colour levels from dim (between beats) to bright (on the beat).
local LEVELS = {
  { 118, 138, 126 },
  { 148, 170, 156 },
  { 180, 202, 186 },
  { 212, 232, 214 },
  { 240, 255, 236 },
}
local IDLE_LEVEL = 3

---@class DancerComponent
---@field view renoise.Views.View Column to place in a dialog.
---@field dancer Dancer
---@field stats DancerStats
---@field start fun(dialog: renoise.Dialog) Begin animating; `dialog` must be the one showing `view`.
---@field stop fun()
---@field running fun(): boolean
---@field state fun(): table Snapshot for `just eval` inspection.

---The most recently started component (dev inspection only).
---@type DancerComponent?
M.current = nil

---@param vb renoise.ViewBuilder
---@param app table The application module (`src/app.lua`).
---@return DancerComponent
function M.new(vb, app)
  local dancer = Dancer.new(nil, { tick_ms = TICK_MS })
  local art = dancer.art
  local blank_rows = {}
  for r = 1, art.H do
    blank_rows[r] = (" "):rep(art.W)
  end

  local stage_text = vb:text {
    id = "dancer_stage_text",
    font = FONT,
    style = "custom",
    color = LEVELS[IDLE_LEVEL],
    origin = { PAD, PAD },
    text = table.concat(blank_rows, "\n"),
  }
  -- Every frame has the same character grid, so the text never grows after this.
  local stage_w = stage_text.width + 2 * PAD
  local stage_h = stage_text.height + 2 * PAD
  local backdrop = vb:canvas {
    id = "dancer_backdrop",
    mode = "plain",
    size = { stage_w, stage_h },
    render = function(ctx)
      local w, h = ctx.size.width, ctx.size.height
      ctx.fill_color = BACKDROP
      ctx:fill_rect(0, 0, w, h)
      ctx.fill_color = FLOOR
      ctx:fill_rect(PAD, h - PAD - 1, w - 2 * PAD, 1)
    end,
  }
  local status = vb:text { id = "dancer_status", font = FONT, text = "stopped" }
  local caption = vb:text { id = "dancer_caption", font = FONT, style = "strong", text = "idle" }
  local view = vb:column {
    id = "dancer",
    spacing = renoise.ViewBuilder.DEFAULT_CONTROL_SPACING,
    status,
    vb:stack { id = "dancer_stage", backdrop, stage_text },
    caption,
  }

  ---@type renoise.Dialog?
  local dialog = nil
  local probe_state = {}
  local shown_level = IDLE_LEVEL
  local shown_status, shown_caption = "stopped", "idle"
  local self = { view = view, dancer = dancer, stats = dancer.stats }

  ---@type fun()
  local tick

  function self.stop()
    app.reg.remove_timer(tick)
    dialog = nil
    if M.current == self then
      M.current = nil
    end
  end

  local function body()
    local entry = app.dialogs.main
    if not dialog or not dialog.visible or not entry or not rawequal(entry.dialog, dialog) then
      self.stop() -- dialog closed, replaced, or dropped on song change
      return
    end
    local input = probe.read(renoise.song(), probe_state)
    local lines, changed = dancer:update(input)
    if changed then
      stage_text.text = table.concat(lines, "\n")
    end
    local level = IDLE_LEVEL
    if dancer.playing then
      level = 1 + math.floor((1 - dancer.phase) * (#LEVELS - 1) + 0.5)
    end
    if level ~= shown_level then
      stage_text.color = LEVELS[level]
      shown_level = level
    end
    local s = dancer:status()
    if s ~= shown_status then
      status.text = s
      shown_status = s
    end
    local c = dancer:caption()
    if c ~= shown_caption then
      caption.text = c
      shown_caption = c
    end
  end
  local guarded = app.guard(body)

  tick = function()
    -- guard logs the traceback; the pcall keeps a broken tick from raising every 40 ms
    if not pcall(guarded) then
      self.stop()
    end
  end

  ---@param dlg renoise.Dialog
  function self.start(dlg)
    dialog = dlg
    probe_state = {}
    M.current = self
    app.reg.timer(tick, TICK_MS)
  end

  function self.running()
    return dialog ~= nil and renoise.tool():has_timer(tick)
  end

  function self.state()
    local d = dancer
    return {
      running = self.running(),
      playing = d.playing,
      bpm = d.bpm,
      mult = d.mult,
      energy = d.energy,
      family = d.family,
      move = d.move and d.move.name or nil,
      caption = d:caption(),
      status = d:status(),
      dbeat = d.dbeat,
      ticks = d.stats.ticks,
      changes = d.stats.changes,
      accents = d.stats.accents,
      changes_per_second = d.stats.ticks > 0 and d.stats.changes * (1000 / TICK_MS) / d.stats.ticks
        or 0,
    }
  end

  return self --[[@as DancerComponent]]
end

return M
