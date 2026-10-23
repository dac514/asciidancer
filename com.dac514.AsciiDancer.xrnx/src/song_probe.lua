--[[
  Reads what the dancer needs from the live song, once per timer tick:
  transport state plus the number of note-ons on pattern lines reached since
  the previous tick. Never caches the song (it changes on load/new); the caller
  passes `renoise.song()` every time. Safe to call with a nil song.
]]

local M = {}

---Lines skipped between two ticks that are still scanned for note-ons.
local MAX_CATCHUP = 8

---@class ProbeState
---@field seq integer?
---@field line integer?

---@class ProbeResult : DancerInput
---@field playing boolean
---@field bpm number
---@field lpb integer
---@field beats number
---@field hits integer

---Count note-ons on one pattern line across active sequencer tracks.
---May raise if the song is mid-edit; the caller wraps it in pcall.
---@param song renoise.Song
---@param seq integer
---@param line integer
---@return integer
local function count_line(song, seq, line)
  local sequencer = song.sequencer
  if seq < 1 or seq > #sequencer.pattern_sequence then
    return 0
  end
  local pattern = song:pattern(sequencer:pattern(seq))
  if line < 1 or line > pattern.number_of_lines then
    return 0
  end
  local hits = 0
  for t = 1, #song.tracks do
    local track = song:track(t)
    if
      track.type == renoise.Track.TRACK_TYPE_SEQUENCER
      and track.mute_state == renoise.Track.MUTE_STATE_ACTIVE
    then
      local pattern_line = pattern:track(t):line(line)
      if not pattern_line.is_empty then
        for c = 1, track.visible_note_columns do
          if pattern_line:note_column(c).note_value < renoise.PatternLine.NOTE_OFF then
            hits = hits + 1
          end
        end
      end
    end
  end
  return hits
end

---@param song renoise.Song?
---@param state ProbeState Remembers the last (sequence, line) seen; mutated.
---@return ProbeResult
function M.read(song, state)
  if not song then
    state.seq, state.line = nil, nil
    return { playing = false, bpm = 120, lpb = 4, beats = 0, hits = 0 }
  end
  local transport = song.transport
  local playing = transport.playing
  local result = {
    playing = playing,
    bpm = transport.bpm,
    lpb = transport.lpb,
    beats = transport.playback_pos_beats,
    hits = 0,
  }
  if not playing then
    state.seq, state.line = nil, nil
    return result
  end
  local pos = transport.playback_pos
  local seq, line = pos.sequence, pos.line
  if seq ~= state.seq or line ~= state.line then
    local first = line
    if
      seq == state.seq
      and state.line
      and line > state.line
      and line - state.line <= MAX_CATCHUP
    then
      first = state.line + 1
    end
    local ok, hits = pcall(function()
      local total = 0
      for l = first, line do
        total = total + count_line(song, seq, l)
      end
      return total
    end)
    result.hits = ok and hits or 0
    state.seq, state.line = seq, line
  end
  return result
end

return M
