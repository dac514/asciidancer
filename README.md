# ASCII Dancer

A tiny dancer for [Renoise](https://www.renoise.com). Press play and a little
ASCII buddy gets down to your track. Press stop and it stands there, patiently,
like it has nowhere better to be.

```
       .-----.
      ( o   o )
       '--v--'
       .-|=|-.
       | |=| |
       o |=| o
        .' '.
       /     \
      _|     |_
```

**YouTube:** [demo video](https://youtu.be/DR_vuVzrXCU?si=mJkDQ02PSyiZ40UI) ·
[short video](https://youtube.com/shorts/jV4Z7nRmsAs?si=SVgzwA76PNIR0Jqj)

## Download

Grab the latest `com.dac514.AsciiDancer.xrnx` from the
[Releases page](https://github.com/dac514/asciidancer/releases) and drag it
onto Renoise. Then open **Tools → ASCII Dancer...** (or bind
*Global → Tools → Show ASCII Dancer* to a key) and hit play.

## What it does, exactly

- **Dances to the song, not the clock.** Every frame is picked from the
  playback position, so loops, jumps and tempo changes all land on the beat.
- **Reads the room.** Moves are chosen bar by bar from where you are in the
  song and how busy the pattern is. Sparse intro? A gentle groove. Wall of
  notes? Arms up. A dense line triggers a jump.
- **Squashes on the beat** and brightens with it, then eases back off. Organic,
  not twitchy.
- **Survives your BPM.** At 300 BPM it dances in half-time. At 40 it doubles
  up. There is hysteresis so it never flip-flops, and a hard cap on how fast
  frames may change, so it stays readable at any tempo. The status line tells
  you which mode you're in.
- **Never reflows.** Every frame is exactly the same size, so the window never
  twitches, resizes or scrolls.
- **Moves:** groove, sway, shuffle, twist, disco point, raise the roof, spin,
  plus two accents (jump!, hands up). The caption names whatever it's doing.

No audio analysis is involved. Renoise doesn't expose audio levels to tools,
so the dancer listens to the transport and the pattern data instead, which
turns out to be plenty.

## Hacking on it

The dancer is plain Lua inside `com.dac514.AsciiDancer.xrnx/`:

```
src/dancer_art.lua    the character: parts, poses, moves, accents (ASCII in long strings)
src/dancer.lua        the brain: tempo folding, choreography, frame compositor, rate clamp
src/song_probe.lua    what it reads from the song each tick
src/dancer_view.lua   the dialog component and its timer
tests/dancer_test.lua runs under plain luajit, no Renoise needed
```

Want to draw your own moves? Edit `dancer_art.lua`, then
`just test` checks that every frame still fits the stage and
`luajit tests/dancer_test.lua --show groove` prints a move so you can eyeball it.

The dev tooling (`just check`, `just reload`, `just views`, `just screenshot`,
and the dev bridge that lets a coding assistant poke at the running tool) comes
from [ReSlop](https://github.com/dac514/reslop), the starter kit this project
was built with. `CLAUDE.md` has the full briefing if you want to work on it
with [Claude Code](https://claude.com/claude-code), and `just doctor` tells
you what to install (just, StyLua, lua-language-server, Python 3).

## Credits and license

MIT. Built with [ReSlop](https://github.com/dac514/reslop). Bundles the
MIT-licensed [renoise/definitions](https://github.com/renoise/definitions) and
guide pages from [renoise/xrnx](https://github.com/renoise/xrnx); see the
`UPSTREAM.md` files for the exact commits.
