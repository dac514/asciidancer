# ASCII Dancer

A Renoise tool built from the [ReSlop](https://github.com/dac514/reslop) starter kit.

## What it does

Adds **Tools > ASCII Dancer...** to the main menu (and a bindable shortcut under
*Global > Tools > Show ASCII Dancer*). The dialog is a small stage with an
ASCII-art dancer:

- While the song is stopped the dancer rests in an idle pose.
- While it plays, the dancer follows the song: moves are chosen per bar from
  the song position and how busy the pattern is (note-ons per beat), the body
  squashes on each beat, dense lines trigger accents (jumps, hands up), and the
  text brightens with every beat.
- Extreme tempos are folded into a danceable range: above ~160 BPM the dancer
  steps in half-time (quarter-time, ... for faster), below 80 BPM in
  double-time, with hysteresis so it does not flicker between modes. The
  status line shows the song BPM and the mode; the caption names the move.
- Every frame has the same character width and height, so the window never
  resizes or reflows.

## Install

Drag `com.dac514.AsciiDancer.xrnx` onto Renoise, or copy this folder into the
`Scripts/Tools` folder of your Renoise preferences directory.
