--[[
  Tests for the pure dancer modules. Run with plain LuaJIT, no Renoise needed:

    luajit tests/dancer_test.lua            run all checks
    luajit tests/dancer_test.lua --show M   print every keyframe of move M (or "idle")
    luajit tests/dancer_test.lua --list     list move names
]]

local here = debug.getinfo(1, "S").source:match "^@(.*)[/\\]" or "."
package.path = here .. "/../com.dac514.AsciiDancer.xrnx/?.lua;" .. package.path

local Art = require "src.dancer_art"
local Dancer = require "src.dancer"

local checks, failures = 0, 0

---@param cond any
---@param msg string
local function check(cond, msg)
  checks = checks + 1
  if not cond then
    failures = failures + 1
    print("FAIL: " .. msg)
  end
end

---@param lines string[]
---@param W integer
---@param H integer
---@param where string
local function check_frame(lines, W, H, where)
  check(#lines == H, ("%s: %d rows, want %d"):format(where, #lines, H))
  for i, line in ipairs(lines) do
    if #line ~= W then
      check(false, ("%s row %d: %d chars, want %d"):format(where, i, #line, W))
      return
    end
  end
end

---Feed a dancer a simulated playback and return visible changes per second.
---@param bpm number
---@param seconds number
---@param hits_fn fun(tick: integer): integer
---@return number changes_per_second, Dancer dancer
local function simulate(bpm, seconds, hits_fn)
  local tick_ms = 40
  local d = Dancer.new(nil, { tick_ms = tick_ms, min_frame_ms = 80 })
  local ticks = math.floor(seconds * 1000 / tick_ms)
  local beats = 0
  local changes = 0
  for t = 1, ticks do
    beats = beats + bpm / 60 * tick_ms / 1000
    local lines, changed = d:update { playing = true, bpm = bpm, beats = beats, hits = hits_fn(t) }
    check_frame(lines, d.art.W, d.art.H, ("simulate %g BPM tick %d"):format(bpm, t))
    if changed then
      changes = changes + 1
    end
  end
  return changes / seconds, d
end

-- --show / --list -----------------------------------------------------------

local function show_move(name)
  local compiled = Art.compile(Art)
  local function print_lines(lines, title)
    print(("--- %s"):format(title))
    for _, line in ipairs(lines) do
      print("|" .. line .. "|")
    end
  end
  if name == "idle" then
    local p = compiled.idle
    print_lines(Dancer.compose(compiled, p.head, p.arms, p.legs, 0, 0, 0), "idle")
    return
  end
  for _, move in ipairs(compiled.moves) do
    if move.name == name then
      for i, key in ipairs(move.keys) do
        local p = key.pose
        local legs, dy = p.legs, p.dy
        if dy > 0 then
          legs = compiled.legs[legs].squash or legs
        end
        print_lines(
          Dancer.compose(compiled, p.head, p.arms, legs, dy, p.dx or 0, p.head_dx),
          ("%s key %d at %g"):format(name, i, key.at)
        )
      end
      return
    end
  end
  for _, accent in ipairs(compiled.accents) do
    if accent.name == name then
      local p = accent.pose
      local idle = compiled.idle
      print_lines(
        Dancer.compose(
          compiled,
          p.head or idle.head,
          p.arms or idle.arms,
          p.legs or idle.legs,
          p.dy or 0,
          0,
          p.head_dx or 0
        ),
        "accent " .. name
      )
      return
    end
  end
  print("unknown move: " .. name)
  os.exit(2)
end

if arg[1] == "--show" and arg[2] then
  show_move(arg[2])
  os.exit(0)
elseif arg[1] == "--list" then
  for _, move in ipairs(Art.moves) do
    print(move.name)
  end
  for _, accent in ipairs(Art.accents) do
    print(accent.name .. " (accent)")
  end
  os.exit(0)
end

-- (a) art validates and every combination composes to W x H -----------------

do
  local ok, err = Art.validate(Art)
  check(ok, "art validates: " .. tostring(err))
  local art = Art.compile(Art)
  local W, H = art.W, art.H
  check(W == 21 and H == 11, ("stage is %dx%d, want 21x11"):format(W, H))
  local combos = 0
  for h = 1, #art.heads do
    for a = 1, #art.arms do
      for l = 1, #art.legs do
        for dy = -1, 1 do
          for dx = -art.SWAY_MAX, art.SWAY_MAX do
            for hdx = -1, 1 do
              local ok2, lines = pcall(Dancer.compose, art, h, a, l, dy, dx, hdx)
              local where = ("compose h%d a%d l%d dy%d dx%d hdx%d"):format(h, a, l, dy, dx, hdx)
              check(ok2, where .. ": " .. tostring(lines))
              if ok2 then
                check_frame(lines, W, H, where)
              end
              combos = combos + 1
            end
          end
        end
      end
    end
  end
  check(combos > 0, "composed some combinations")
end

-- (b) tempo folding with hysteresis -----------------------------------------

do
  local f = Dancer.fold_bpm
  check(f(40) == 2, "40 BPM doubles")
  check(f(32) == 4, "32 BPM quadruples")
  check(f(120) == 1, "120 BPM unchanged")
  check(f(159) == 1, "159 BPM unchanged")
  check(f(160) == 0.5, "160 BPM halves")
  check(f(300) == 0.5, "300 BPM halves")
  check(f(999) == 0.125, "999 BPM to one eighth")
  check(f(150, 0.5) == 0.5, "300 -> 150 keeps half-time (hysteresis)")
  check(f(150, 1) == 1, "120 -> 150 keeps full-time (hysteresis)")
  check(f(143, 0.5) == 1, "half-time at 143 unfolds")
  check(f(176, 1) == 0.5, "full-time at 176 folds")
  for bpm = 32, 999 do
    local m = f(bpm)
    local d = bpm * m
    if d < 80 or d >= 160 then
      check(false, ("fold %d BPM -> %g outside [80,160)"):format(bpm, d))
    end
  end
  check(Dancer.tempo_label(1) == "", "label for x1 is empty")
  check(Dancer.tempo_label(0.5) == "half-time", "label for half-time")
  check(Dancer.tempo_label(2) == "double-time", "label for double-time")
end

-- (c) frame-change rate stays clamped at any tempo --------------------------

do
  math.randomseed(7)
  for _, bpm in ipairs { 40, 120, 300, 999 } do
    local rate, d = simulate(bpm, 30, function()
      return math.random(0, 10) == 0 and math.random(1, 6) or 0
    end)
    check(rate <= 12.5 + 1e-9, ("%g BPM: %.2f frame changes/s, max 12.5"):format(bpm, rate))
    check(rate >= 2, ("%g BPM: %.2f frame changes/s, expected some motion"):format(bpm, rate))
    check(d:status():find "BPM" ~= nil, "status mentions BPM while playing")
  end
end

-- (d) stopped: one idle frame, then nothing changes -------------------------

do
  local d = Dancer.new()
  local first, changed = d:update { playing = false }
  check(changed, "first idle frame counts as a change")
  check_frame(first, d.art.W, d.art.H, "idle")
  for _ = 1, 100 do
    local lines, c = d:update { playing = false }
    check(not c and lines == first, "idle frame never changes while stopped")
  end
  check(d:status() == "stopped", "status is 'stopped'")
  check(d:caption() == "idle", "caption is 'idle'")
  -- play, then stop again: back to the very same idle table
  local beats = 0
  for _ = 1, 50 do
    beats = beats + 0.08
    d:update { playing = true, bpm = 120, beats = beats, hits = 2 }
  end
  local again = d:update { playing = false }
  check(again == first, "stopping returns the cached idle frame")
end

-- (e) determinism -----------------------------------------------------------

do
  local a, b = Dancer.new(), Dancer.new()
  local beats = 0
  local same = true
  for t = 1, 600 do
    beats = beats + 0.08
    local hits = t % 7 == 0 and 4 or 0
    local la = a:update { playing = true, bpm = 128, beats = beats, hits = hits }
    local lb = b:update { playing = true, bpm = 128, beats = beats, hits = hits }
    if table.concat(la, "\n") ~= table.concat(lb, "\n") then
      same = false
    end
  end
  check(same, "two dancers fed the same input produce identical frames")
end

-- (f) backwards position jump (pattern loop) --------------------------------

do
  local d = Dancer.new()
  local beats = 0
  for _ = 1, 200 do
    beats = beats + 0.08
    d:update { playing = true, bpm = 120, beats = beats, hits = 0 }
  end
  local ok = pcall(function()
    for _ = 1, 200 do
      beats = beats - 0.08
      d:update { playing = true, bpm = 120, beats = beats, hits = 0 }
    end
    for _ = 1, 50 do
      d:update { playing = true, bpm = 120, beats = 0, hits = 0 }
    end
  end)
  check(ok, "backwards jumps do not error")
  check(d.move ~= nil, "a move is active after a jump")
end

-- (g) energy and accents react to hits --------------------------------------

do
  local d = Dancer.new()
  local beats = 0
  local saw_accent = false
  for t = 1, 300 do
    beats = beats + 0.08
    d:update { playing = true, bpm = 120, beats = beats, hits = t % 5 == 0 and 5 or 0 }
    if d.active and d.active ~= d.move then
      saw_accent = true
    end
  end
  check(d.energy > 0.4, ("energy rises with dense hits (%.2f)"):format(d.energy))
  check(saw_accent, "dense hits trigger an accent")
  check(d.stats.accents > 0, "accent counter increments")
end

if failures > 0 then
  print(("%d of %d checks failed"):format(failures, checks))
  os.exit(1)
end
print(("ok %d checks"):format(checks))
