# Shadow Run — Prototype

A portrait 2.5D gothic **shadow-hopping puzzle game**. Dracula can only walk where it is
shaded. The player moves the sun to reshape the shadows, then taps a shaded spot to send
him there. Each level is solved by chaining shadows from the Start to the crypt Goal.

**Core loop:** adjust the sun → a connected shadow path appears → tap a shadow → Dracula
walks it → repeat until he reaches the goal.

Build stage: `PROTOTYPE` (local only: no network, ads or analytics). Template
architecture is unchanged: `ServiceRegistry` is the only autoload, `GameService` is the
composition root, and services are injected.

## How to run

| What | How |
|---|---|
| Full game | **Play** (F5): `Boot.tscn` → Home → **Play** → `levels/Level01.tscn` |
| One level | Open `game/scenes/gameplay/shadow_run/levels/LevelNN.tscn` and press **F6** (see *Editor F6 fallback*) |
| Level validator | F6 on `level/LevelValidatorRunner.tscn`, or headless (below) |
| Shade self-check | F6 on `shadow/ShadowSensorSelfCheck.tscn`, or headless (below) |
| End-to-end test | `game/scenes/test/ShadowRunSoakTest.tscn` (headless, below) |

```bash
godot --headless --path . res://game/scenes/gameplay/shadow_run/level/LevelValidatorRunner.tscn
```

```bash
godot --headless --path . res://game/scenes/gameplay/shadow_run/level/LevelValidatorRunner.tscn -- --verbose=3 --az=-30,0 --rows=1
```

Layout experiments (debug only, never saved): `--only=3` runs one level;
`--range=az_min,az_max,el_min,el_max`, `--start=az,el`, `--set=Props/pillar_6:x:z;…`
and `--hide=Props/name;…` try variations without editing the scene.

```bash
godot --headless --path . res://game/scenes/gameplay/shadow_run/shadow/ShadowSensorSelfCheck.tscn
```

```bash
godot --headless --path . res://game/scenes/test/ShadowRunSoakTest.tscn
```

Each tool exits with code 0 on success.

- `--verbose=N` prints level N's walkable map at the level's minimum, start and maximum
  sun angles (plus any `--az=` angles). Symbols: `o` shaded and walkable, `.` sunlit,
  `#` solid, `S` start, `G` goal.
- **The end-to-end test plays every level for real.** It replays the solver's plan through
  the same `move_to` that taps use, moves the sun under the exposure guard, presses Next,
  then does death → Retry loops and checks node counts. It writes level progress to your
  local save (`user://saves/`).

### Editor F6 fallback

`ShadowRunFeature.editor_f6_fallback` (on by default) handles a level launched directly
with nothing injected. It boots `GameService` itself and runs the same injection pass.
It is guarded by `OS.has_feature("editor")`, waits two frames (so it never fires in the
normal flow), and is the only place in gameplay code that touches `ServiceRegistry` or
`/root`.

## Controls

| Action | Touch | Desktop |
|---|---|---|
| Move Dracula | **Tap** a spot, or **press and drag** to lead him | Click / click-drag |
| Turn the sun (azimuth) | **Joystick** (default): push the sun knob left / right. **Slider**: drag horizontally in the bottom strip | Q / E (both modes) |
| Raise / lower the sun (elevation) | **Joystick**: push up = higher sun, short shadows. **Slider**: drag vertically in the strip | R / F (both modes) |
| Switch sun control | Pause → **Sun control: Joystick / Slider** (saved) | Same |
| Pause | ‖ button (top-left) | Esc or P |
| Debug overlay | Optional "dbg" button (off by default) | F3 (debug builds only) |

**Tap or drag to move.** A press in the play view becomes a **drag** once it moves more
than `drag_start_distance` (25 px on the 1080-wide canvas) or is held longer than
`drag_start_time` (0.15 s); otherwise it is a **tap**. Click = tap and click-drag = drag
on desktop. Only the first finger in the play view leads Dracula. Touches that start on
the active sun control (joystick or strip) always belong to the sun.

**Drag to move.** While the finger is down, Dracula runs after the cell under it,
re-pathing up to `drag_repath_rate` (12) times a second, and only when that cell
changes. Walking paths during a drag never hop. When the finger is over sunlight, a wall
or a shadow he can't walk to, he heads for the closest cell of his own shadow and waits
there. That cell is chosen with `edge_penalty` (2 cells per lit neighbour), so he stands
a step inside the shadow rather than on its sunny edge. To hop a small gap
(≤ `max_hop_distance`), hold the finger over the far shade for `drag_hop_hold_time`
(0.2 s). The same yellow ring as a tap (`fx/MoveMarker.tscn`) glides under the cell he
is heading to (never under a sunlit finger) and, on release, plays the tap's pulse and
fade on his final stop. On release:
over reachable shade, that cell (nudged off the edge) is his final stop; otherwise he
finishes at the last valid cell and shakes his head. Starting a sun drag stops him at
the next cell; he resumes following when the sun is released and the finger is still
down. There is no camera pan, so nothing else competes with one-finger drags.
Re-path cost (snap search + walking A*) is about 2 ms for a 24 m path on desktop.

**Tap results.**

- **Reachable** (a shaded cell connected to Dracula's shadow region, hops included): he
  runs the A* path at 8 m/s (walks at 5 m/s if it's 2 m or shorter). He accelerates at
  45 m/s² and brakes into the last cell, turns quickly to face his heading, and hops gaps
  in 0.3 s. A soft ring pulses at the target.
- **Unreachable:** a red ring pulses at the tap and Dracula shakes his head. He never
  walks through sunlight.
- **Tapping while he's moving** re-routes from where he is.
- **During a sun drag** taps are ignored. A tap made while the shade is still updating is
  held and answered within a few frames.

**Sun: two controls, one interface.** `SunJoystick` (bottom-right, default) and the
`SunControl` slider strip both implement `SunInput` and only move the SunRig's target, so
ranges (per level), the 180°/s cap, smoothing, the guard and shade-grid syncing are
identical. Exactly one is shown; the Pause panel switch swaps them instantly and saves
`sun_control_mode` (see *Saved setting*).

- **Joystick (rate control).** Knob deflection sets the turning *speed*:
  `speed = max_speed × ((d − deadzone) / (1 − deadzone))^response_exponent`, with
  `max_speed` 180°/s, `deadzone` 0.1, `response_exponent` 2.2 (a 30% push turns about
  5°/s for fine work, full push 180°/s). X = azimuth, up = higher sun. Releasing springs
  the knob back and the sun stops where it is (the target never leads the sun by more
  than `max_lead_degrees`, 6°). The base is 260 px; `left_handed` mirrors it bottom-left.
- **Slider (position control).** Relative drag in the bottom strip: horizontal = azimuth,
  vertical = elevation, sensitivity 1.5×; the guide arc stays fixed and the sun icon
  rises above it for a high sun.

While the sun is moving, by either control or the keys, Dracula stops at the next cell
and stands still.

**Exposure guard.** The sun cannot be turned to an angle that would put Dracula's
footprint in sunlight. It stops at the last safe angle, the active control flashes red
(joystick rim / strip edge) and Dracula flinches (at most every 0.4 s while a held
joystick keeps pushing). Moving the sun alone can never burn him.

**Goal connection.** No outline is drawn on shadow edges during gameplay. When the shadow
region Dracula stands in reaches the goal, a soft glow ring lights up at the crypt door.
The region itself is only visualised by the F3 debug overlay.

**Touch arbitration.** Touches that start on the active sun control belong to the sun
until they lift. They are consumed before the play view sees them, so a sun move is never
a tap and two fingers work at once (one on the sun, one leading Dracula). A hidden control
ignores all input, keys included.

**Saved setting.** `ShadowRunFeature` reads `sun_control_mode` (`"joystick"` /
`"slider"`) from the injected `SaveManager` at level start (`get_value`, default
`default_sun_mode` = joystick), and the Pause switch writes it with `set_value` +
`save_game()`, so it carries across levels and restarts.

## Failure

Exposure (no on-screen bar) is a safety net driven by `ShadowSensor`: three foot-level points on
Dracula ray-cast toward the sun. It rises whenever he is exposed, for example mid-hop, and
recovers in shade. At 100 the burn → ash-and-bats death plays, then Game Over
(Retry / Home). All burn feedback is kept: smoke and embers, the emissive rim, the screen
vignette, the sizzle sound and haptics.

## Shade grid: gameplay truth

`level/ShadeGrid.gd` sits on a node in every level. It covers the walkable floor (x from 0
to `size.x`, z from 0 to `−size.y`) with `cell_size` cells (0.4 m; 30 × 125 cells for a
12 × 50 m level).

- **Solid:** a cell is solid if a foot-to-head box (0.15–1.9 m) overlaps the `obstacle` or
  `shadow_caster` layers. Walls, buildings, the wagon and statues are solid; overhead
  canopies are not. This is computed once at load.
- **Shaded:** a cell is shaded if a ray from its ground point (0.15 m up) toward the sun
  hits the `shadow_caster` layer. This is the same test as `ShadowSensor` and the same
  caster shapes that cast the visible shadows, so rendered shadow = walkable cell = no
  burning.
- **Walkable** = shaded and not solid.
- **Pathfinding:** A* with 8-way moves and no corner-cutting past sunlight or walls.
- **Hops:** a straight jump of up to `max_hop_distance` (1.0 m; 0 disables) across
  non-solid sunlit cells to another walkable cell. It costs extra (`hop_penalty`), so
  walking is preferred, and it causes a small exposure spike. Hops count for
  reachability and the goal connection.

**Updating shade (mobile budget).** At load the grid ray-tests every cell at
`mask_samples` × `mask_elevation_samples` sun angles across the level's ranges. Cells that never change are frozen;
only "variable" cells, dilated by one cell, are re-cast afterwards.

- **While the sun moves:** passes are throttled to `max_updates_per_second` (10) and
  time-sliced at `rays_per_frame` (300 rays, about 0.6 ms on desktop and roughly 3 ms on
  a mid-range phone).
- **When the sun settles:** a full pass runs at `settle_rays_per_frame` (1,200), finishing
  in about 3 frames.
- **Setup** takes about 90 ms on desktop for a 3,750-cell level.

**Measured cost.** A ray costs about 2 µs from GDScript on desktop. In these levels about
85–90% of cells are variable, because long building shadows sweep most of the street.

## Level structure

Each level is a scene, `levels/LevelNN.tscn`, with this hierarchy:

```
LevelNN (ShadowLevel)            level_number, level_title, next_level, hint,
                                 sun_start_azimuth/elevation, azimuth_min/max, elevation_min/max
├─ Ground (StaticBody3D)         flat ochre floor (ground_ochre.tres) + dark outer ground
├─ ShadeGrid                     grid origin = its position; size, cell_size, max_hop_distance…
├─ Start (Marker3D)              Dracula's spawn (must be shaded at the start angle)
├─ Goal (CryptDoor.tscn)         LevelGoal Area3D; crypt behind it is a caster + solid
├─ Props/…                       instanced caster/obstacle scenes (buildings, statue, wagon…)
└─ Game (ShadowRun.tscn)         shared gameplay shell; Game/ShadowRunFeature.level = ".."
```

`ShadowRun.tscn` is the shared shell, holding the feature, environment, `SunRig`, Dracula,
sensor, camera, backdrop, tap marker, debug overlay and HUD. Each level
instances it, so every level runs directly through `SceneManager.go_to(path)`. On the
Level Complete panel:

- **Next** loads `next_level`. After the last level it reads "Finish" and returns Home.
- **Retry** reloads the level.
- **Home** returns to the Home scene.

**Completion** calls `SaveManager.complete_level(level_number, 3, 100)` then `save_game()`.
It emits `GameBus.level_completed` and calls `GameManager.game_over("level_complete")`.
Home's Play opens Level01 and shows "Levels cleared: N".

### The three prototype levels

| Level | Idea | Sun |
|---|---|---|
| 1 · The Gargoyle (start el 40°) | **Teaching.** The left row shades the start. Walk to the gargoyle, stand in its shadow, swing the sun right, and the right row's shadow leads to the crypt. | Start −40°; one sweep to the right while sheltered by the statue |
| 2 · Two Alleys (start el 38°) | **Branching.** A chapel splits the street. Left route: switch the sun early, in the spire's shadow in front of the chapel, and use the chapel's shadow down the left alley. Right route: use the chapel's shadow down the right alley at the start angle, then switch late at the gargoyle by the exit. | Start −35°; one switch, early or late |
| 3 · The Narrow Gate (start el 32°) | **Timing.** A 2.4 m gate between castle walls. With the sun nearly ahead, the **covered wagon's** shadow fills the gap, so the wagon is both what blocks the path and what lets you through. Past it, swing further left so the wagon throws shade beside itself, slip around it, and reach the crypt in the left buildings' shadow. | Start +30°; two adjustments |

All levels use the full default ranges (azimuth −80…80°, elevation 15…65°).

`level/LevelValidatorRunner.tscn` (driven by `level_solver.tres`) proves each level is
**solvable**, **needs at least one sun adjustment**, and is **not trivial**: no single sun
sweep from the start spot connects straight to the goal. It searches the sun on both axes
(21 azimuth × 6 elevation samples). Its search moves the sun only while
Dracula stands on a pivot cell that stays shaded, with a margin, at both sample angles and
halfway between, mirroring the in-game guard. The end-to-end test then replays those
plans in the real game.

## How to build a level in the editor

1. Duplicate `levels/Level01.tscn` (or make a new scene with the hierarchy above). On the
   root, set `level_number`, `level_title`, `hint`, `next_level`, `sun_start_azimuth`,
   `sun_start_elevation`, and the ranges `azimuth_min` / `azimuth_max` /
   `elevation_min` / `elevation_max` (narrow them if a puzzle needs it). Point the previous level's
   `next_level` at it.
2. Keep **ShadeGrid** covering the walkable floor. The levels use a 12 × 50 m street from
   x −6 to +6, starting at z +1.5.
3. Drag props from `props/casters/` (buildings, walls, `statue`, `chapel_block`,
   `covered_wagon`, `tree`, `pillar`, …) and `props/obstacles/` under **Props**, then move
   them with the gizmo. Anything that casts a visible shadow must have a matching
   `ShadowCaster` collision shape on layer 4 (`shadow_caster`); all existing props do.
   Anything standing on the ground (0.15–1.9 m) becomes solid automatically.
4. Place **Start** in shade at the start angle, and **Goal** (`props/goal/CryptDoor.tscn`)
   where the player should end up. The crypt sits 2.4 m behind the goal point.
5. Make sure the instanced **Game** node's `ShadowRunFeature.level` points at the root
   (`../..`).
6. Add the scene to `LevelValidatorRunner.tscn` → `level_scenes` and run it. Use
   `--verbose=N --az=… --rows=1` maps to see where shadows connect, then iterate until it
   passes (solvable, needs the sun, not trivial). Add `--el=<deg>` to dump at another
   elevation.

**Puzzle tips.** Shadows stretch toward +Z (back toward the start) by
`height × cot(elevation) × cos(azimuth)` and sideways by
`−height × cot(elevation) × sin(azimuth)`. A tall block next to the path is a natural
pivot, because the cells right behind it stay shaded through most sun angles.

## Visual style

Golden sun against dark shadow is the dominant read:

- **Lighting:** all scenery uses **toon diffuse with specular off**. The ground is golden
  ochre in sun; ambient light is low and dark brown-purple, so shadows read near-black.
- **Shadow edges:** the sun's shadows are crisp (`shadow_blur` 0, mobile hard filtering,
  bias 0.08 / normal bias 2 against acne).
- **Atmosphere:** the sky is a flat warm gradient, with no glow and no fog. Buildings,
  walls, the statue, chapel and crypt are dark, simple silhouettes.
- **Accent:** one blood-red accent, used sparingly (the crypt lantern and Dracula's eyes
  and cape lining).
- **Materials** are `.tres` files under `game/assets/materials/`.

**Camera** (`camera/CameraRig.tscn`):

- 55° pitch, 14 m high, 5.5 m behind.
- `keep_aspect = Keep Width` with a 46° horizontal FOV, so the whole 12 m level width is
  always visible.
- X is centred on the level (`center_x` from `ShadowLevel.center_x()`); Z follows Dracula
  smoothly (`forward_smoothing` 4), keeping him in the lower-middle of the play view.

Captures were checked at 9:16 (540×960), 9:20 (432×960) and 3:4 (720×960). At 3:4 the full
width is visible but less depth ahead.

**Layout** (portrait 1080×1920, `canvas_items` / `expand`, locked portrait, safe-area padding):

1. **Top bar, 10%:** pause, level label (no exposure bar; exposure only drives the burn vignette).
2. **Play view:** taps and drags happen here; nothing covers it except transient labels
   and, in joystick mode, the joystick. Joystick mode: 90%, down to the bottom edge
   (camera `distance` 3.6 m). Slider mode: 75%, ending above the strip (camera 5.5 m).
   Either way Dracula sits in the lower-middle of the visible play view.
3. **Joystick mode:** 260 px `SunJoystick` floating 48 px in from the bottom-right safe
   corner. **Slider mode:** the `SunControl` strip, bottom 15%.

## Debug overlay (F3, off by default)

`debug/ShadowDebugOverlay.tscn` draws:

- every grid cell: green walkable, orange sunlit, grey solid, blue reachable from Dracula;
- the current path (white line) and the sensor's foot rays (green shaded, red lit);
- text: sun angle and target, grid size and variable-cell count, exposure, fps and node count.

Rendered shadows and green/blue cells must coincide; captures confirmed they do.

## Tunables

| Where | What |
|---|---|
| `LevelNN` root (`ShadowLevel`) | `sun_start_azimuth`, `sun_start_elevation`, `azimuth_min` / `azimuth_max` (−80/80), `elevation_min` / `elevation_max` (15/65), `hint`, `next_level` |
| `LevelNN/ShadeGrid` | `size`, `cell_size`, `sample_height`, `max_hop_distance`, `hop_penalty`, `solid_probe_heights`, `mask_samples`, `mask_elevation_samples`, `rays_per_frame`, `settle_rays_per_frame`, `max_updates_per_second` |
| `Game/SunRig` (`sun/SunRig.tscn`) | `max_azimuth_speed` / `max_elevation_speed` (180 °/s), `smoothing` (22), `min_follow_speed` (60), `settle_threshold`, `guard_search_steps`, sun colour and energy; light shadow settings |
| `Game/HUDLayer/…/SunJoystick` (`ui/mfw/SunJoystick.tscn`) | `max_speed` 180 °/s, `deadzone` 0.1, `response_exponent` 2.2, `knob_travel` 92 px, `max_lead_degrees` 6, `return_time`, key speeds 180 °/s, `left_handed`, `corner_margin` 48, `grab_slop` 24; size 260 px (`custom_minimum_size` + offsets); look in the StyleBoxes |
| `Game/HUDLayer/…/SunControl` (slider strip) | strip height via its `size_flags_stretch_ratio` (15), `drag_sensitivity` (1.5), key speeds (180 °/s), `elevation_drag_span`, `elevation_travel`, `sun_radius`, arc shape, blocked shake and colour |
| `Game/HUDLayer/ShadowRunHUD` | `play_view_ratio_joystick` 90 / `play_view_ratio_slider` 75, `show_debug_button` (off; debug builds only), `min_safe_margin` |
| `Game/Dracula` (`player/Dracula.tscn`) | `walk_speed` 5, `run_speed` 8, `run_threshold` 2 m, `acceleration` 45 m/s², `hop_time` 0.3 s, `hop_height`; Turning: `turn_speed_degrees` 720, `turn_in_place_angle` 100°, `turn_in_place_release` 20°, `facing_lookahead` 0.8 m, `facing_smoothing` 14/s; burn and death timings, cue angles |
| `Game/Dracula/Visual/DraculaVisual` (`player/DraculaVisual.tscn`, inherited from `Dracula/dracula.glb`) | `walk_clip_speed` 1.44, `run_clip_speed` 4.24, `locomotion_blend_time` 0.2 s, `min_time_scale` 0.5; graph in `AnimationTree`; rim look in `dracula_rim.tres` |
| `Game/ShadowSensor` | `burn_rate` (100/1.2 per s), `heal_rate`, `ray_length` |
| `Game/ShadowRunFeature` | Touch: `drag_start_distance` 25 px, `drag_start_time` 0.15 s, `drag_repath_rate` 12/s, `drag_hop_hold_time` 0.2 s, `edge_penalty` 2. Sun control: `default_sun_mode` (Joystick), `camera_distance_joystick` 3.6, `camera_distance_slider` 5.5. `title_time`, F6 fallback |
| `Game/RunCamera` | `height`, `distance`, `pitch_degrees`, `fov`, `forward_smoothing`, death cam |
| `Game/MoveMarker` (`fx/MoveMarker.tscn`) | Ring size, `tap_ok` / `tap_fail` materials, `pulse_time`, `start_scale`, drag `follow_rate` |
| `level/level_solver.tres` | `angle_step` (2.5°), `check_midpoints` (off), `goal_radius`, `max_adjustments` (8) |
| `LevelValidatorRunner.tscn` | `min_window_degrees` (8°); per level: `ShadowLevel.min_sun_adjustments` |

## Verification done

- **Level validator (two axes, wide ranges):** all 3 levels are solvable, need the sun,
  and are not trivial. A negative test with a goal next to the start confirmed the
  triviality check fires.
- **End-to-end test** (headless, real game through `SceneManager`): PASS.
  - **Level 1 checks:** pause/resume; a real tap via `handle_tap`; an unreachable tap
    doesn't move him; the exposure guard stops a sun drag at −11.3° with 0 exposure.
  - **Playthrough:** all three levels completed by replaying the solver's two-axis plans
    at the faster movement speeds (peak exposure 12–30 from hops); Level Complete → Next →
    … → Finish → Home; progression saved.
  - **Stability:** 5 death → Retry loops with a flat node count (271) and no leaked
    `GameBus` connections.
- **ShadowSensorSelfCheck:** passes.
- **Rendered captures** (mobile renderer): crisp golden/dark contrast, the overlay agrees
  with the rendered shadows, framing at 9:16, 9:20 and 3:4.

## Known issues / not done

- **60 FPS on a mid-range Android device has not been measured** (no device available).
  The shade budget is about 3 ms per frame while dragging (estimated from desktop ray cost
  × 5) plus a ~3-frame settle pass, and load is about 0.5 s per level on a phone. Profile on
  hardware, and lower `rays_per_frame` or `max_updates_per_second` if needed.
- **The optional camera pan (drag the play view to look ahead) is not implemented.** It
  would conflict with tap-to-move, so it was left out (the brief allowed it to be off).
- **The guard protects the footprint, not the whole body.** Shade is decided at foot level
  (the ground-shadow rule). A low wall can shade his feet while his head is in the sun;
  that counts as safe.
- **The solver samples the sun every ~4.3°** and checks halfway points. A hand-dragged sun
  can still be stopped by the guard in a slightly different place than the solver assumed,
  which is harmless (the player just picks a better pivot).
- **Large casters can hide part of the level** from the high camera (for example Level 3's
  gate walls) until Dracula gets closer.
- **Dracula is still the capsule placeholder** (the detailed character was reverted), so
  there are no limbs or cloak physics. His run "animation" is a bob tied to distance
  travelled, which scales with speed. Placeholder audio.
- **A faint moiré pattern shows on sunlit ground at the extreme high-sun angle** (around
  65°). It's not ordinary shadow acne: raising the bias didn't remove it. Mid angles
  render clean. Still to investigate.
- **The sun guard is only explicitly tested on azimuth.** It moves both axes together and
  the playthrough's elevation moves pass through it, but there is no dedicated
  elevation-blocking test.
- **Template docs:** `docs/OPTIMIZATION_GUIDE.md` (referenced by `# PDF §x` comments) is
  missing from this repo.
