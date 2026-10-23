--[[
  ASCII Dancer engine: turns transport state (playing, BPM, beat position,
  note hits) into a stage frame of fixed width and height.

  Pure Lua: no `renoise.*`, no Renoise stdlib additions, so it runs under plain
  `luajit` for the tests. Time is counted in `update` calls (ticks), never in
  wall-clock time, which keeps accents and the frame-rate clamp independent of
  seeks and pattern loops.
]]

local Art = require "src.dancer_art"

---@class DancerInput
---@field playing boolean
---@field bpm number?
---@field beats number? Song position in beats (transport.playback_pos_beats).
---@field hits integer? Note-ons seen on newly reached pattern lines since the last tick.

---@class DancerOpts
---@field tick_ms integer? Timer interval the view uses (default 40).
---@field min_frame_ms integer? Shortest time a frame stays visible (default 80).
---@field bar_beats integer? Dance beats per bar (default 4).

---@class DancerStats
---@field ticks integer
---@field changes integer
---@field accents integer

---@class Dancer
---@field art CompiledArt
---@field t integer Tick counter.
---@field stats DancerStats
---@field playing boolean
---@field bpm number
---@field mult number Tempo multiplier: dance beats = song beats * mult.
---@field energy number 0..1, EMA of note-ons per dance beat.
---@field move CompiledMove?
---@field active table? Move or accent currently shown (has `caption`).
---@field family string
---@field dbeat number
---@field phase number 0..1 within the current dance beat.
---@field lines string[] Last emitted frame.
---@field bar_beats integer
---@field min_ticks integer Ticks a frame stays visible at least.
---@field hits_in_beat integer
---@field beat_i integer?
---@field bar integer?
---@field move_started_bar integer
---@field accent CompiledAccent?
---@field accent_until integer
---@field accent_cooldown_until integer
---@field frame_id integer?
---@field frame_changed_at number
---@field cache table<integer, string[]>
local Dancer = {}
Dancer.__index = Dancer

-- Dance tempo band: exactly one power-of-two multiplier lands bpm * mult in [LO, HI).
local LO, HI = 80, 160
-- Keep the current multiplier while bpm * mult stays inside this wider band (hysteresis).
local HYST_LO, HYST_HI = 72, 176
local MULT_MIN, MULT_MAX = 1 / 16, 8

local ACCENT_MIN_HITS = 3 -- note-ons on one line that count as a hit
local ACCENT_TICKS = 6 -- accent pose length (240 ms at 40 ms ticks)
local ACCENT_COOLDOWN_TICKS = 15
local HITS_FULL = 6 -- note-ons per dance beat that count as full energy
local ENERGY_LOW, ENERGY_HIGH = 0.2, 0.55
local HOLD_BARS = 2 -- bars a move is kept before re-picking
local SWAY_PERIOD = 8 -- dance beats per sway cycle
local SONG_BAR_BEATS = 4 -- song beats per bar for the deterministic seed

---Fold a song tempo into the readable dance band by halving or doubling.
---@param bpm number
---@param prev number? Multiplier currently in use, kept while within the hysteresis band.
---@return number mult
function Dancer.fold_bpm(bpm, prev)
  if prev then
    local d = bpm * prev
    if d >= HYST_LO and d < HYST_HI then
      return prev
    end
  end
  local mult, d = 1, bpm
  while d < LO and mult < MULT_MAX do
    mult, d = mult * 2, d * 2
  end
  while d >= HI and mult > MULT_MIN do
    mult, d = mult / 2, d / 2
  end
  return mult
end

---@param mult number
---@return string
function Dancer.tempo_label(mult)
  if mult == 1 then
    return ""
  elseif mult == 0.5 then
    return "half-time"
  elseif mult == 0.25 then
    return "quarter-time"
  elseif mult == 2 then
    return "double-time"
  elseif mult == 4 then
    return "x4"
  end
  return ("x%g"):format(mult)
end

---Deterministic scramble of a non-negative integer (exact in doubles for realistic n).
---@param n number
---@return number
local function hash(n)
  return (n * 2654435761) % 4294967296
end

---@param x number
---@return number
local function round(x)
  return math.floor(x + 0.5)
end

---@param energy number
---@return string
local function family_for(energy)
  if energy < ENERGY_LOW then
    return "low"
  elseif energy < ENERGY_HIGH then
    return "mid"
  end
  return "high"
end

---@param pool CompiledMove[]
---@param h number
---@param prev CompiledMove?
---@return CompiledMove
local function pick(pool, h, prev)
  local n = #pool
  local i = (h % n) + 1
  if n > 1 and pool[i] == prev then
    i = (i % n) + 1
  end
  return pool[i]
end

---Compose one stage frame. Parts are stamped legs, arms, head; spaces are transparent.
---@param art CompiledArt
---@param head integer
---@param arms integer
---@param legs integer
---@param dy integer -1 jump, 0, 1 squash (legs index must already be the squash variant)
---@param dx integer
---@param head_dx integer
---@return string[] lines
function Dancer.compose(art, head, arms, legs, dy, dx, head_dx)
  local H, FW = art.H, art.FIGURE_W
  local grid = {}
  for r = 1, H do
    local row = {}
    for c = 1, FW do
      row[c] = " "
    end
    grid[r] = row
  end
  local function stamp(part, drow, dcol)
    for i, s in ipairs(part.rows) do
      local r = part.row + i - 1 + drow
      for c = 1, #s do
        local ch = s:sub(c, c)
        if ch ~= " " then
          local cc = c + dcol
          if r < 1 or r > H or cc < 1 or cc > FW then
            error(("part out of bounds at row %d col %d"):format(r, cc))
          end
          grid[r][cc] = ch
        end
      end
    end
  end
  stamp(art.legs[legs], dy < 0 and dy or 0, 0)
  stamp(art.arms[arms], dy, 0)
  stamp(art.heads[head], dy, head_dx)
  local left = (" "):rep(art.SWAY_MAX + dx)
  local right = (" "):rep(art.SWAY_MAX - dx)
  local lines = {}
  for r = 1, H do
    lines[r] = left .. table.concat(grid[r]) .. right
  end
  return lines
end

---@param art table? Art module (defaults to `src.dancer_art`); compiled here.
---@param opts DancerOpts?
---@return Dancer
function Dancer.new(art, opts)
  opts = opts or {}
  local compiled = Art.compile(art or Art)
  local tick_ms = opts.tick_ms or 40
  local self = setmetatable({
    art = compiled,
    bar_beats = opts.bar_beats or 4,
    min_ticks = math.max(1, math.ceil((opts.min_frame_ms or 80) / tick_ms)),
    t = 0,
    stats = { ticks = 0, changes = 0, accents = 0 },
    playing = false,
    bpm = 120,
    mult = 1,
    energy = 0,
    hits_in_beat = 0,
    beat_i = nil,
    bar = nil,
    move = nil,
    move_started_bar = 0,
    family = "low",
    accent = nil,
    accent_until = -1,
    accent_cooldown_until = 0,
    active = nil,
    dbeat = 0,
    phase = 0,
    frame_id = nil,
    frame_changed_at = 0,
    lines = nil,
    cache = {},
  }, Dancer)
  return self
end

---@param head integer
---@param arms integer
---@param legs integer
---@param dy integer
---@param dx integer
---@param head_dx integer
---@return string[] lines
---@return boolean changed
function Dancer:emit(head, arms, legs, dy, dx, head_dx)
  local art = self.art
  if dy > 0 then
    local squash = art.legs[legs].squash
    if squash then
      legs = squash
    else
      dy = 0
    end
  end
  local id = (
    (((head * #art.arms + arms) * #art.legs + legs) * 3 + dy + 1) * (2 * art.SWAY_MAX + 1)
    + dx
    + art.SWAY_MAX
  )
      * 3
    + head_dx
    + 1
  if id == self.frame_id then
    return self.lines, false
  end
  if self.frame_id and self.t - self.frame_changed_at < self.min_ticks then
    return self.lines, false -- clamp: hold the current frame a little longer
  end
  local lines = self.cache[id]
  if not lines then
    lines = Dancer.compose(art, head, arms, legs, dy, dx, head_dx)
    self.cache[id] = lines
  end
  self.frame_id = id
  self.frame_changed_at = self.t
  self.lines = lines
  self.stats.changes = self.stats.changes + 1
  return lines, true
end

---Advance one tick.
---@param input DancerInput
---@return string[] lines Exactly `art.H` strings of `art.W` characters; the same table while unchanged.
---@return boolean changed
function Dancer:update(input)
  self.t = self.t + 1
  self.stats.ticks = self.stats.ticks + 1
  local art = self.art

  if not input.playing then
    if self.playing then
      self.playing = false
      self.energy = 0
      self.hits_in_beat = 0
      self.accent = nil
      self.accent_until = -1
      self.active = nil
      self.frame_changed_at = -math.huge -- show the idle pose at once, clamp or not
    end
    local idle = art.idle
    return self:emit(idle.head, idle.arms, idle.legs, 0, 0, 0)
  end

  if not self.playing then
    self.playing = true
    self.energy = 0.3
    self.hits_in_beat = 0
    self.beat_i = nil
    self.bar = nil
    self.move = nil
    self.accent = nil
    self.accent_until = -1
    self.accent_cooldown_until = 0
  end

  local bpm = input.bpm or 120
  self.bpm = bpm
  self.mult = Dancer.fold_bpm(bpm, self.mult)
  local beats = input.beats or 0
  local dbeat = beats * self.mult
  local dbi = math.floor(dbeat)
  local phase = dbeat - dbi
  self.dbeat, self.phase = dbeat, phase

  local hits = input.hits or 0
  if hits > 0 then
    self.hits_in_beat = self.hits_in_beat + hits
    if
      hits >= ACCENT_MIN_HITS
      and self.t >= self.accent_cooldown_until
      and self.energy >= ENERGY_LOW
      and #art.accents > 0
    then
      self.accent = art.accents[1 + hash(dbi) % #art.accents]
      self.accent_until = self.t + ACCENT_TICKS
      self.accent_cooldown_until = self.t + ACCENT_COOLDOWN_TICKS
      self.stats.accents = self.stats.accents + 1
    end
  end
  if dbi ~= self.beat_i then
    self.energy = 0.65 * self.energy + 0.35 * math.min(self.hits_in_beat / HITS_FULL, 1)
    self.hits_in_beat = 0
    self.beat_i = dbi
  end

  local bar = math.floor(dbeat / self.bar_beats)
  if bar ~= self.bar then
    self.bar = bar
    local move = self.move
    if
      not move
      or bar < self.move_started_bar
      or (bar - self.move_started_bar) % math.max(move.bars, HOLD_BARS) == 0
    then
      self.family = family_for(self.energy)
      self.move = pick(art.pools[self.family], hash(math.floor(beats / SONG_BAR_BEATS)), move)
      self.move_started_bar = bar
    end
  end

  local move = self.move --[[@as CompiledMove]] -- picked above on the first playing tick
  local loop_pos = dbeat - math.floor(dbeat / move.beats) * move.beats
  local key = move.keys[1]
  for i = 2, #move.keys do
    if move.keys[i].at <= loop_pos then
      key = move.keys[i]
    else
      break
    end
  end
  local pose = key.pose
  local accent = self.t < self.accent_until and self.accent or nil
  local over = accent and accent.pose or nil
  self.active = accent or move

  local head = over and over.head or pose.head
  local arms = over and over.arms or pose.arms
  local legs = over and over.legs or pose.legs
  local dy = over and over.dy or pose.dy
  local head_dx = over and over.head_dx or pose.head_dx
  local dx = pose.dx
  if dy == 0 and self.energy >= ENERGY_LOW then
    dy = round((1 - phase) ^ 2) -- squash right on the beat, eased release
  end
  if dx == nil then
    dx = round(art.SWAY_MAX * math.sin(2 * math.pi * dbeat / SWAY_PERIOD))
  end
  return self:emit(head, arms, legs, dy, dx, head_dx)
end

---@return string
function Dancer:status()
  if not self.playing then
    return "stopped"
  end
  local s = ("%d BPM"):format(math.floor(self.bpm + 0.5))
  local label = Dancer.tempo_label(self.mult)
  if label ~= "" then
    s = s .. "  " .. label
  end
  return s
end

---@return string
function Dancer:caption()
  if not self.playing then
    return "idle"
  end
  return self.active and self.active.caption or ""
end

return Dancer
