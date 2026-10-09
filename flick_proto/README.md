# LOCALHOST flick_proto — engine-less stick-gesture trick recognition (JOO-193)

First runnable proof of the crown-jewel feel layer for the open-skate program:
right-stick gestures -> recognized tricks, in plain C++17. No engine, no
third-party material.

## Clean-room statement

All code in this directory is original. The trick vocabulary uses common
skateboarding terminology (ollie, kickflip, heelflip, shove-it, etc.) —
publicly observable physical behavior and standard sport language. No game's
assets, code, symbols, or product names are referenced or derived. Mechanics
and input schemes are functional design.

## Build & run

    make            # compiles: g++ -std=c++17 -O2 -Wall -Wextra
    ./flick_battery # runs the scripted battery, prints pass matrix, exit 0 at >=90%

## Input model

A stream of right-stick samples `{t, x, y}` at ~60 Hz, `x/y` in [-1,1].

### Coordinate convention (documented, tunable in one place)

Camera behind the rider, rider traveling "up-screen":

- `+y` = nose direction (travel), `-y` = tail.
- REGULAR stance: toe side = screen-left (`-x`), heel side = screen-right (+x).
- GOOFY mirrors the x mapping. A release toward the toe side reads as a
  kickflip; toward the heel side reads as a heelflip; a tail sweep toward the
  heel side (+x, ccw sweep) reads as a BACKSIDE spin.
- The mapping lives in `toeSign`-style helpers in `flick_recognizer.cpp` and is
  a single flip if a playtest says the sides feel inverted.

### Phases

    idle -> load -> flick -> recover (+ optional hold)

- **load**: stick reaches 0.55 magnitude and holds >= 36 ms (the crouch).
- **flick**: a fast motion (>= 6 stick-units/s) starting within 150 ms of the
  completed load. One burst ends when speed falls back under threshold
  (foot parked) or the stick collapses below ~0.15.
- **recover**: stick returns toward neutral. A new pop is only allowed after
  the stick has passed through neutral since the last pop — this is what
  chains tricks and what keeps a pop-into-lean (manual) from firing twice.
- **hold**: after a pop, a lean held >= 250 ms within +-75 deg of tail/nose
  resolves the last ollie-family trick into `manual (hold)` /
  `nose manual (hold)`.

### Features -> decision tree

Each flick burst extracts: reversal angle (load vs release), signed sweep arc
(ccw positive, accumulated only over consecutive in-band samples), release
direction, peak speed, peak magnitude. Classification order:

1. arc >= 240 deg  -> 360-family: release tilted up >= 0.15 => `360 flip`;
   otherwise `360 shove-it fs/bs` (fs/bs from sweep sign + stance).
2. release tilted (|x| >= 0.22) and up-ish (y >= 0.12) -> `kickflip` / `heelflip`
   by stance-relative side.
3. arc in 55..240 -> `pop shove-it fs/bs`.
4. clean reversal (>= 140 deg, straight release) -> `ollie` (tail load) or
   `nollie` (nose load).
5. else -> `unknown flick` (counted as a miss by the battery).

Riding context decorates names: `fakie ollie`, late pops inside the previous
trick's airborne window become `late <trick>`.

### Honest limits of v0 (next actions)

- Thresholds were derived from the scripted generator's kinematics (deliberate
  and documented in `Tunables`), not from human input. **Next step (P2):
  record real controller streams (SDL2 dump) and re-fit thresholds.**
- Switch-riding naming is acknowledged but not yet battery-tested.
- Offline whole-stream processing; an incremental wrapper can reuse the same
  state machine (the loop state carries over sample-to-sample).
- Confidence is a weighted feature score per family (see `classify`), not a
  probability model.

## Files

- `flick_recognizer.hpp` — input/context types, tunables, outputs.
- `flick_recognizer.cpp` — phase machine + classification.
- `battery.cpp` — scripted gesture battery, harness, pass matrix.
- `Makefile` — build rules.

This directory lives outside the Godot project's active scene tree on purpose:
it is the engine-less feel lab for the open-skate program (JOO-192), not
LOCALHOST gameplay code yet.