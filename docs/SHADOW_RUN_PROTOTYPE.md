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
| Move Dracula | **Tap** a spot in the play view | Left-click |
| Turn the sun (azimuth) | **Drag horizontally** in the bottom sun strip | Q / E (or mouse-drag in the strip) |
| Raise / lower the sun (elevation) | **Drag vertically** in the strip (up = short shadows, down = long) | R / F |
| Pause | ‖ button (top-left) | Esc or P |
| Debug overlay | Optional "dbg" button (off by default) | F3 (debug builds only) |

**Tap to move.** A tap is a press that moves less than `tap_slop` (30 px) within
`tap_max_time` (0.45 s).

- **Reachable** (a shaded cell connected to Dracula's shadow region, hops included): he
  runs the A* path at 8 m/s (walks at 5 m/s if it's 2 m or shorter). He accelerates at
  45 m/s² and brakes into the last cell, turns quickly to face his heading, and hops gaps
  in 0.3 s. A soft ring pulses at the target.
- **Unreachable:** a red ring pulses at the tap and Dracula shakes his head. He never
  walks through sunlight.
- **Tapping while he's moving** re-routes from where he is.
- **During a sun drag** taps are ignored. A tap made while the shade is still updating is
  held and answered within a few frames.

**Sun.** Relative drag: touching never jumps the sun. Horizontal drag sets azimuth;
vertical drag sets elevation, shown by the sun's height in the strip (the guide arc
stays fixed; the sun sits above it when high and below it when low). Drag sensitivity is 1.5× and the sun follows the finger at up to 180°/s. While the
sun is being dragged, Dracula stops at the next cell and stands still.

**Exposure guard.** The sun cannot be turned to an angle that would put Dracula's
footprint in sunlight. It stops at the last safe angle, the strip shakes with a red edge,
and Dracula flinches. Dragging the sun alone can never burn him.

**Goal connection.** No outline is drawn on shadow edges during gameplay. When the shadow
region Dracula stands in reaches the goal, a soft glow ring lights up at the crypt door.
The region itself is only visualised by the F3 debug overlay.

**Touch arbitration.** Touches that start in the sun strip belong to the sun until they
lift. They are consumed before the play view sees them, so a sun drag is never a tap and
two fingers work at once.

## Failure

The exposure meter is a safety net driven by `ShadowSensor`: three foot-level points on
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

1. **Top bar, 10%:** pause, level label, exposure meter.
2. **Play view, 75%:** taps happen here; nothing covers it except transient labels.
3. **Sun strip, 15%.**

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
| `Game/HUDLayer/…/SunControl` | strip height via `size_flags_stretch_ratio` on `ShadowRunHUD.tscn` (15, play view 75), `drag_sensitivity` (1.5), `key_azimuth_speed` / `key_elevation_speed` (180 °/s), `elevation_drag_span`, `elevation_travel`, `sun_radius`, arc shape, blocked shake and colour |
| `Game/HUDLayer/ShadowRunHUD` | `show_debug_button` (off; debug builds only), `min_safe_margin` |
| `Game/Dracula` (`player/Dracula.tscn`) | `walk_speed` 5, `run_speed` 8, `run_threshold` 2 m, `acceleration` 45 m/s², `hop_time` 0.3 s, `hop_height`, `turn_speed` 22 rad/s, `bob_cycles_per_meter` (bob scales with speed), burn and death timings, cue angles |
| `Game/ShadowSensor` | `burn_rate` (100/1.2 per s), `heal_rate`, `ray_length` |
| `Game/ShadowRunFeature` | `tap_slop`, `tap_max_time`, `title_time`, F6 fallback |
| `Game/RunCamera` | `height`, `distance`, `pitch_degrees`, `fov`, `forward_smoothing`, death cam |
| `Game/TapMarker` | Colours, pulse time |
| `level/level_solver.tres` | `azimuth_samples` (21), `elevation_samples` (6), `goal_radius` |

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
