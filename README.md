# Blessing of Ra (Plus/4)

**Blessing of Ra** - a two-player pyramid escape for the Commodore
Plus/4 (ACME + VICE), the port of the
[C64 original](https://git.teletypegames.org/games/blessingofra):
same rules, same screens, same eight levels.

The legend: when the great pyramid rose, a worker was sealed in its
peak. He prayed to Ra until the sun god took pity - now Ra bends the
pyramid's labyrinth walls to lead him out.

**Player 1** (joystick 2, or `w a s d`) is the worker, running the
corridors toward the green exit portal. **Player 2** (joystick 1, or
`i j k l`) is Ra: a bracket cursor rides the corners of the walls -
fire (or `return`) spins the four wall pieces around the cursor by
90 degrees, reshaping the maze in real time. A spin is denied while
anyone is standing in one of the four slots (the border blips red);
the spun pieces flash white.

Eight levels, each maze one cell bigger than the last: a square that
starts at 4x4 cells and grows to 11x11 - the tallest square lattice
the screen fits - always centered on screen. One more enemy joins
each level (up to four): the cyan **scarabs** roam the corridors,
and the light-red **scorpions** also spit a venom sting whenever
they line up with the worker - the purple drop flies down the
corridor until a wall swallows it.

The options screen adds three optional twists:

- **worker gun** - player 1 shoots a bullet with fire/`space`; a hit
  enemy respawns on a random cell after a pause.
- **spin cooldown** - each spin starts a recharge; further spins are
  denied until the bar on the status row drains (pixel by pixel) and
  the readout flips back from *wait* to *ready* (the cursor also
  turns red while recharging).
- **relic order** - numbered relics lie scattered over the corridors
  and the worker has to gather them *in order*, 1 first, then 2, and
  so on, before the portal will take him. Until the last one is his
  the exit stays sealed (a dull grey, and bumping into it blips the
  border red); the relic he is after next pulses white, and the
  status row counts them off next to the portal glyph. Every level
  adds one more: two on level 1 up to nine on level 8.

Screens: TTG intro -> pyramid title card (the pyramid, the trapped
worker and the pulsing sun of Ra) -> main menu (play / options /
story / credits) -> game -> next level, and after the last one the
escape screen (back to the menu); game over lets fire retry the same
level with a fresh maze, `m` backs out to the menu.

## What changed for the Plus/4

The TED is a different beast from the VIC-II + SID, so the graphics
and sound layers were rebuilt while the game logic stayed as it was:

- **No hardware sprites.** Every actor (worker, cursor, bullet,
  sting, enemies) is a software sprite: each frame its 8x8 shape is
  shifted to its pixel offset through precomputed shift tables,
  or-ed over the maze glyphs it covers and stamped into one of 32
  dynamic chars (`$60`-`$7f`), painted in the actor's colour. The
  covered cells are put back at the top of the next frame, before
  the game logic reads the maze off the screen - the screen stays
  the wall data structure exactly as on the C64. The cursor covers
  its cell instead of blending, so the brackets stay readable over
  the posts.
- **Colours** are TED colour bytes (`luminance << 4 | hue`), colour
  RAM sits at `$0800` below the screen at `$0c00`. The gold wash and
  the fade to black use real luminance ramps (the fade walks every
  cell one luminance step down per pass).
- **Charset**: the ROM's 128-char uppercase set is copied to `$5000`,
  the custom tiles (wall, post, portal, bar) go on unused graphic
  codes; codes `$80`-`$ff` stay the TED's hardware inverses, so the
  `$a0` solid block still builds the big letters.
- **Status band**: the C64's busy-wait raster band is a TED raster
  interrupt now (the KERNAL is banked out and `$fffe` points at our
  handler), so the whole frame - bottom border, blank, top border -
  is free for the update; the frame syncs on the last text row and
  the actors are redrawn while the beam is off the maze.
- **Sound**: the SID driver became a TED voice-2 driver: square or
  noise, a 10-bit pitch slide per frame and a software volume decay
  standing in for the envelope.
- **Input**: keyboard columns on `$fd30`, rows and joysticks latched
  on `$ff08` (the matrix positions of `wasd`, `ijkl`, `m`, space and
  return match the C64's); joystick 2 is the worker, joystick 1 is Ra.

## Build & run

```
make deps       # macOS: brew install acme vice
make build      # -> blessingofra_plus4.prg
make run        # build + launch in xplus4
```

Loading the `.prg` on a real or emulated Plus/4:

```
LOAD"*",8,1
RUN
```

Test builds can boot straight into one state:

```
acme -DAUTOPLAY=1 -f cbm -o blessingofra_plus4.prg main.asm
# also: AUTOOPTIONS, AUTOSTORY, AUTOPYRAMID, AUTOCREDITS,
# AUTOWIN, AUTOLOSE; add -DFORCEOPTS=1 to start with all
# three options turned on, -DAUTOLEVEL=8 to start on level 8,
# -DRASTERDBG=1 to paint the update's raster time white on
# the border
```

Headless smoke test with VICE (runs a few emulated seconds, then
writes a screenshot):

```sh
xplus4 +sound -warp -limitcycles 13000000 -exitscreenshot shot.png \
  -autostartprgmode 1 blessingofra_plus4.prg
```

## Files

- `main.asm` - entry point, BASIC stub (`SYS 4109`), per-frame state
  machine, the border, the status band raster interrupt
- `defs.asm` - TED registers, constants, palette, zero page, macros
- `intro.asm` - TTG boot logo with the gold color wash
- `pyramid.asm` - title card: the pyramid, the worker, the sun of Ra
- `menu.asm` - main menu card over a dark maze backdrop
- `options.asm` - the optional extras and their toggle screen
- `story.asm` - the legend of the worker and Ra + the controls
- `credits.asm` - the crew
- `play.asm` - maze geometry + generation (recursive backtracker,
  animated) + the game and its eight growing levels
- `win.asm` / `over.asm` - end screens
- `common.asm` - shared routines: printing, big block font, the
  title wash, keyboard/joystick input, RNG
- `sound.asm` - single-voice SFX driver on TED voice 2
- `gfx.asm` - RAM charset with the custom tiles, the software
  sprite engine, the portal animation and the fade-to-black
  transition

## Memory map

```
$1001 .. $100c   BASIC stub (10 SYS 4109)
$100d .. ~$3d00  machine code + texts + variables + maze buffers
$0c00 .. $0fe7   screen RAM (also the maze's wall data)
$0800 .. $0be7   colour RAM
$5000 .. $53ff   RAM charset (128 chars; $5300+ = the dynamic chars)
$5400 .. $61ff   shift tables for the software sprites (built at start)
$fffe            IRQ vector (RAM banked in over the KERNAL)
```

## Pipeline

`.woodpecker.yaml` is a one-line marker (`platform: plus4`); the
pipeline itself is served by the update server. See
[plus4-build](https://git.teletypegames.org/build/plus4-build) for
the toolchain and the platform page on the wiki:
https://wiki.teletypegames.org/development/plus4
