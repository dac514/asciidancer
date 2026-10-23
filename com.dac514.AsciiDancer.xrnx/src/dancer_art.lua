--[[
  ASCII Dancer artwork: body parts, poses, dance moves and accents, plus the
  compiler that turns the hand-drawn long strings into row arrays.

  Pure Lua: nothing here touches `renoise.*` or Renoise's stdlib additions, so
  `luajit tests/dancer_test.lua` can load it unchanged.

  Coordinates: the figure box is FIGURE_W (17) columns by STAGE_H (11) rows.
  Every part is drawn directly in those coordinates (leading spaces position
  it) and `row` is the first figure row the art occupies. Spaces are
  transparent when a part is stamped onto the frame, so arms may pass beside
  the head. Standing layout: row 1 headroom (jump), row 2 hands (arms up),
  rows 3-5 head, rows 6-8 arms + torso (6 = shoulders), rows 9-11 legs.

  Art rows carry no trailing spaces (editors strip them); `compile` pads.
]]

local M = {}

M.FIGURE_W = 17
M.STAGE_H = 11
---Columns of padding on each side of the figure box, used for sway/side-steps.
M.SWAY_MAX = 2
M.STAGE_W = M.FIGURE_W + 2 * M.SWAY_MAX

---@class DancerPartSource
---@field row integer First figure row the art occupies (1-based).
---@field art string Rows separated by "\n", drawn in figure coordinates.
---@field squash string? Legs only: variant drawn when the figure squashes (dy = 1).

---@class DancerPose
---@field head string?
---@field arms string?
---@field legs string?
---@field dy integer? -1 = jump (figure up one row), 1 = squash (head + arms down one row).
---@field dx integer? Explicit horizontal shift in columns; nil lets the engine sway.
---@field head_dx integer? Head tilt in columns (-1, 0, 1).

---@class DancerKey
---@field at number Offset in dance beats within the move's loop; ascending, first is 0.
---@field pose DancerPose

---@class DancerMove
---@field name string
---@field caption string
---@field beats integer Loop length in dance beats.
---@field energy string|string[] Energy families this move belongs to: "low", "mid", "high".
---@field keys DancerKey[]

---@class DancerAccent
---@field name string
---@field caption string
---@field pose DancerPose Partial pose overlaid on the current move's pose.

---@type table<string, table<string, DancerPartSource>>
M.parts = {
  head = {
    front = {
      row = 3,
      art = [==[
     .-----.
    ( o   o )
     '--v--']==],
    },
    happy = {
      row = 3,
      art = [==[
     .-----.
    ( ^   ^ )
     '--u--']==],
    },
    wink = {
      row = 3,
      art = [==[
     .-----.
    ( -   o )
     '--v--']==],
    },
    side_l = {
      row = 3,
      art = [==[
      .---.
     (o    )
      '---']==],
    },
    side_r = {
      row = 3,
      art = [==[
      .---.
     (    o)
      '---']==],
    },
    back = {
      row = 3,
      art = [==[
     .-----.
    (  ~~~  )
     '-----']==],
    },
  },
  arms = {
    rest = {
      row = 6,
      art = [==[
     .-|=|-.
     | |=| |
     o |=| o]==],
    },
    out = {
      row = 6,
      art = [==[
 o---.-|=|-.---o
       |=|
       |=|]==],
    },
    hips = {
      row = 6,
      art = [==[
     .-|=|-.
    (  |=|  )
     '-|=|-']==],
    },
    swing_l = {
      row = 6,
      art = [==[
     .-|=|-.
    /  |=| |
   o   |=| o]==],
    },
    swing_r = {
      row = 6,
      art = [==[
     .-|=|-.
     | |=|  \
     o |=|   o]==],
    },
    up = {
      row = 2,
      art = [==[
  o           o
  |           |
  |           |
   \         /
    '--|=|--'
       |=|
       |=|]==],
    },
    up_l = {
      row = 2,
      art = [==[
  o
  |
  |
   \
    '--|=|-.
       |=| |
       |=| o]==],
    },
    up_r = {
      row = 2,
      art = [==[
              o
              |
              |
             /
     .-|=|--'
     | |=|
     o |=|]==],
    },
    point_r = {
      row = 2,
      art = [==[
                o
               /
              /
             /
     .-|=|--'
     | |=|
     o |=|]==],
    },
    point_l = {
      row = 2,
      art = [==[
o
 \
  \
   \
    '--|=|-.
       |=| |
       |=| o]==],
    },
  },
  legs = {
    stand = {
      row = 9,
      squash = "crouch",
      art = [==[
      .' '.
     /     \
    _|     |_]==],
    },
    wide = {
      row = 9,
      squash = "crouch",
      art = [==[
     .'   '.
    /       \
   _|       |_]==],
    },
    crouch = {
      row = 10,
      art = [==[
    _/     \_
   |_|     |_|]==],
    },
    tuck = {
      row = 9,
      art = [==[
      .' '.
     (_) (_)]==],
    },
    step_l = {
      row = 9,
      art = [==[
      .' '.
    _/    |
   |_|    |_]==],
    },
    step_r = {
      row = 9,
      art = [==[
      .' '.
      |    \_
     _|    |_|]==],
    },
    twist_l = {
      row = 9,
      art = [==[
      .' '.
      /    /
    _/   _/]==],
    },
    twist_r = {
      row = 9,
      art = [==[
      .' '.
      \    \
       \_   \_]==],
    },
  },
}

---@type DancerPose
M.idle = { head = "front", arms = "rest", legs = "stand" }

---@type DancerMove[]
M.moves = {
  {
    name = "groove",
    caption = "groove",
    beats = 2,
    energy = "low",
    keys = {
      { at = 0, pose = { head = "front", arms = "swing_l", legs = "stand", dy = 1 } },
      { at = 0.4, pose = { head = "front", arms = "swing_l", legs = "stand" } },
      { at = 1, pose = { head = "front", arms = "swing_r", legs = "stand", dy = 1 } },
      { at = 1.4, pose = { head = "front", arms = "swing_r", legs = "stand" } },
    },
  },
  {
    name = "sway",
    caption = "sway",
    beats = 2,
    energy = "low",
    keys = {
      { at = 0, pose = { head = "front", arms = "swing_l", legs = "wide", dx = -1, head_dx = -1 } },
      { at = 0.5, pose = { head = "front", arms = "rest", legs = "wide", dx = 0 } },
      { at = 1, pose = { head = "front", arms = "swing_r", legs = "wide", dx = 1, head_dx = 1 } },
      { at = 1.5, pose = { head = "front", arms = "rest", legs = "wide", dx = 0 } },
    },
  },
  {
    name = "shuffle",
    caption = "shuffle",
    beats = 2,
    energy = "mid",
    keys = {
      { at = 0, pose = { head = "front", arms = "swing_r", legs = "step_l", dx = -1 } },
      { at = 0.5, pose = { head = "front", arms = "rest", legs = "stand", dx = 0 } },
      { at = 1, pose = { head = "front", arms = "swing_l", legs = "step_r", dx = 1 } },
      { at = 1.5, pose = { head = "front", arms = "rest", legs = "stand", dx = 0 } },
    },
  },
  {
    name = "twist",
    caption = "twist",
    beats = 2,
    energy = { "mid", "high" },
    keys = {
      { at = 0, pose = { head = "front", arms = "hips", legs = "twist_l", head_dx = -1 } },
      { at = 0.5, pose = { head = "front", arms = "hips", legs = "stand" } },
      { at = 1, pose = { head = "front", arms = "hips", legs = "twist_r", head_dx = 1 } },
      { at = 1.5, pose = { head = "front", arms = "hips", legs = "stand" } },
    },
  },
  {
    name = "point",
    caption = "disco point",
    beats = 2,
    energy = { "mid", "high" },
    keys = {
      { at = 0, pose = { head = "wink", arms = "point_r", legs = "wide" } },
      { at = 0.75, pose = { head = "front", arms = "rest", legs = "wide" } },
      { at = 1, pose = { head = "wink", arms = "point_l", legs = "wide" } },
      { at = 1.75, pose = { head = "front", arms = "rest", legs = "wide" } },
    },
  },
  {
    name = "roof",
    caption = "raise the roof",
    beats = 2,
    energy = "high",
    keys = {
      { at = 0, pose = { head = "happy", arms = "up_l", legs = "wide" } },
      { at = 0.5, pose = { head = "happy", arms = "up", legs = "wide" } },
      { at = 1, pose = { head = "happy", arms = "up_r", legs = "wide" } },
      { at = 1.5, pose = { head = "happy", arms = "up", legs = "wide" } },
    },
  },
  {
    name = "spin",
    caption = "spin",
    beats = 2,
    energy = "high",
    keys = {
      { at = 0, pose = { head = "front", arms = "out", legs = "stand", dx = 0 } },
      { at = 0.5, pose = { head = "side_r", arms = "out", legs = "stand", dx = 1 } },
      { at = 1, pose = { head = "back", arms = "rest", legs = "stand", dx = 0 } },
      { at = 1.5, pose = { head = "side_l", arms = "rest", legs = "stand", dx = -1 } },
    },
  },
}

---@type DancerAccent[]
M.accents = {
  {
    name = "jump",
    caption = "jump!",
    pose = { head = "happy", arms = "up", legs = "tuck", dy = -1, head_dx = 0 },
  },
  {
    name = "hands_up",
    caption = "hands up",
    pose = { head = "happy", arms = "up", head_dx = 0 },
  },
}

-- Compiler -------------------------------------------------------------------

---@class CompiledPart
---@field row integer
---@field rows string[]
---@field squash integer? Legs only: index of the squash variant.

---@class CompiledPose
---@field head integer
---@field arms integer
---@field legs integer
---@field dy integer
---@field dx integer?
---@field head_dx integer

---@class CompiledKey
---@field at number
---@field pose CompiledPose

---@class CompiledMove
---@field name string
---@field caption string
---@field beats integer
---@field bars integer Whole dance bars the loop spans (at least 1).
---@field keys CompiledKey[]

---@class CompiledAccent
---@field name string
---@field caption string
---@field pose table Partial pose with integer part indexes.

---@class CompiledArt
---@field W integer Stage width in characters.
---@field H integer Stage height in rows.
---@field FIGURE_W integer
---@field SWAY_MAX integer
---@field heads CompiledPart[]
---@field arms CompiledPart[]
---@field legs CompiledPart[]
---@field idle CompiledPose
---@field moves CompiledMove[]
---@field pools table<string, CompiledMove[]>
---@field accents CompiledAccent[]

---Split a part's art into rows and check they fit the figure box.
---@param kind string
---@param name string
---@param src DancerPartSource
---@param height integer
---@return string[] rows
local function split_rows(kind, name, src, height)
  local rows = {}
  for line in (src.art .. "\n"):gmatch "(.-)\n" do
    rows[#rows + 1] = line
  end
  if #rows == 0 then
    error(("%s.%s: empty art"):format(kind, name))
  end
  for i, line in ipairs(rows) do
    if #line > M.FIGURE_W then
      error(("%s.%s row %d is %d wide, max %d"):format(kind, name, i, #line, M.FIGURE_W))
    end
    if line:find "\t" then
      error(("%s.%s row %d contains a tab"):format(kind, name, i))
    end
  end
  if src.row < 1 or src.row + #rows - 1 > height then
    error(("%s.%s does not fit rows 1..%d"):format(kind, name, height))
  end
  return rows
end

---@param kind string
---@param sources table<string, DancerPartSource>
---@param height integer
---@return CompiledPart[] parts, table<string, integer> index
local function compile_parts(kind, sources, height)
  local names = {}
  for name in pairs(sources) do
    names[#names + 1] = name
  end
  table.sort(names)
  local parts, index = {}, {}
  for i, name in ipairs(names) do
    local src = sources[name]
    parts[i] = { row = src.row, rows = split_rows(kind, name, src, height) }
    index[name] = i
  end
  for i, name in ipairs(names) do
    local squash = sources[name].squash
    if squash then
      if not index[squash] then
        error(("%s.%s: unknown squash variant %q"):format(kind, name, squash))
      end
      parts[i].squash = index[squash]
    end
  end
  return parts, index
end

---@param art table The art module table (or a test double with the same shape).
---@return CompiledArt
function M.compile(art)
  local height = art.STAGE_H or M.STAGE_H
  local figure_w = art.FIGURE_W or M.FIGURE_W
  local sway = art.SWAY_MAX or M.SWAY_MAX
  local heads, head_index = compile_parts("head", art.parts.head, height)
  local arms, arms_index = compile_parts("arms", art.parts.arms, height)
  local legs, legs_index = compile_parts("legs", art.parts.legs, height)

  ---@param where string
  ---@param pose DancerPose
  ---@param partial boolean
  ---@return table
  local function compile_pose(where, pose, partial)
    local out = {}
    local function resolve(field, index)
      local name = pose[field]
      if name == nil then
        if not partial then
          error(("%s: pose is missing %s"):format(where, field))
        end
        return nil
      end
      local i = index[name]
      if not i then
        error(("%s: unknown %s %q"):format(where, field, tostring(name)))
      end
      return i
    end
    out.head = resolve("head", head_index)
    out.arms = resolve("arms", arms_index)
    out.legs = resolve("legs", legs_index)
    for _, field in ipairs { "dy", "head_dx" } do
      local v = pose[field]
      if v ~= nil and (v < -1 or v > 1 or v ~= math.floor(v)) then
        error(("%s: %s must be -1, 0 or 1"):format(where, field))
      end
      out[field] = v or (partial and nil or 0)
    end
    if pose.dx ~= nil and (pose.dx < -sway or pose.dx > sway) then
      error(("%s: dx must be within +-%d"):format(where, sway))
    end
    out.dx = pose.dx
    return out
  end

  local bar_beats = 4
  local moves, pools = {}, { low = {}, mid = {}, high = {} }
  for _, src in ipairs(art.moves) do
    if type(src.beats) ~= "number" or src.beats <= 0 then
      error(("move %s: beats must be positive"):format(src.name))
    end
    local keys = {}
    for i, key in ipairs(src.keys) do
      if type(key.at) ~= "number" or key.at < 0 or key.at >= src.beats then
        error(("move %s key %d: at must be within [0, beats)"):format(src.name, i))
      end
      keys[i] = {
        at = key.at,
        pose = compile_pose(("move %s key %d"):format(src.name, i), key.pose, false),
      }
    end
    table.sort(keys, function(a, b)
      return a.at < b.at
    end)
    if #keys == 0 or keys[1].at ~= 0 then
      error(("move %s: first key must be at 0"):format(src.name))
    end
    local move = {
      name = src.name,
      caption = src.caption or src.name,
      beats = src.beats,
      bars = math.max(1, math.ceil(src.beats / bar_beats)),
      keys = keys,
    }
    moves[#moves + 1] = move
    local families = type(src.energy) == "table" and src.energy or { src.energy }
    for _, family in ipairs(families) do
      if not pools[family] then
        error(("move %s: unknown energy family %q"):format(src.name, tostring(family)))
      end
      table.insert(pools[family], move)
    end
  end
  if #moves == 0 then
    error "no moves defined"
  end
  for family, pool in pairs(pools) do
    if #pool == 0 then
      pools[family] = moves -- fall back to everything rather than dancing nothing
    end
  end

  local accents = {}
  for i, src in ipairs(art.accents or {}) do
    accents[i] = {
      name = src.name,
      caption = src.caption or src.name,
      pose = compile_pose(("accent %s"):format(src.name), src.pose, true),
    }
  end

  return {
    W = figure_w + 2 * sway,
    H = height,
    FIGURE_W = figure_w,
    SWAY_MAX = sway,
    heads = heads,
    arms = arms,
    legs = legs,
    idle = compile_pose("idle", art.idle, false),
    moves = moves,
    pools = pools,
    accents = accents,
  }
end

---@param art table
---@return boolean ok
---@return string? err
function M.validate(art)
  local ok, err = pcall(M.compile, art)
  if ok then
    return true, nil
  end
  return false, tostring(err)
end

return M
