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
| Villager stealth test | `game/scenes/test/VillagerStealthTest.tscn` (headless, below) |

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

```bash
godot --headless --path . res://game/scenes/test/VillagerStealthTest.tscn
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
| Turn the sun (azimuth) | **Dial** (default): drag the sun knob left / right inside the ring. **Slider**: drag horizontally in the bottom strip | Q / E (both modes) |
| Raise / lower the sun (elevation) | **Dial**: up = HIGH (short shadows), down = LOW. **Slider**: drag vertically in the strip | R / F (both modes) |
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

- **Dial ("joystick" mode, position control).** A thin golden ring (264 px) with ticks,
  HIGH above and LOW below, and a dashed inner circle. The bright sun knob always sits at
  the sun's **current** angle: knob X = azimuth (ring's left edge = the level's minimum,
  right edge = maximum), knob Y = elevation (top = HIGH). The angle rectangle maps onto
  the disc with an elliptical square↔disc mapping, so every point inside the ring is a
  valid angle. Touching or dragging anywhere in the ring sets that angle as the target;
  the sun turns toward it at the rig's 180°/s and smoothing, and a dim marker shows where
  the finger is aiming meanwhile. Releasing keeps the target (no spring-back), and the
  knob starts at the level's start angle. If the guard refuses an angle, the sun and knob
  stop at the last safe angle, the ring flashes red, and the dim marker lingers
  (`blocked_marker_time`, 0.8 s) on the refused angle. `left_handed` mirrors the dial to
  the bottom-left.
- **Slider (relative position control).** Drag in the bottom strip: horizontal = azimuth,
  vertical = elevation, sensitivity 1.5×. It also always shows the current angle: the sun
  icon sits at the current azimuth along the fixed arc and rises above it for a high sun
  (a dim ring marks the target while the sun catches up), consistent with the dial.

While the sun is moving, by either control or the keys, Dracula stops at the next cell
and stands still.

**Free sun (default) / exposure guard.** By default (`ShadowRunFeature.sun_guard_enabled` off) the sun turns freely: if it lights Dracula, the exposure meter in the top bar fills and he burns when it is full (about 1.2 s in full sun), so swing it and move him back into shade in time. With `sun_guard_enabled` on, the old guard applies: the sun cannot be turned to an angle that would put Dracula's
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

## Dracula (model, animation, visibility)

- **Model:** `player/Dracula/dracula.glb` (1.95 m, 26 bones, cloak motion baked into the
  clips). `player/DraculaVisual.tscn` is an inherited scene of it, rotated 180° on Y (the
  model faces +Z, the game's forward is −Z) and placed under `Dracula/Visual`.
- **Clips:** only `Idle`, `Walk` and `Run` are imported, all looping (Linear). The `.glb`'s
  Import Script, `player/Dracula/dracula_import.gd`, keeps just those three, because
  Godot's per-animation import options have no skip switch.
- **AnimationTree:** `Locomotion` (BlendSpace1D on real ground speed: Idle 0, Walk 1.44,
  Run 4.24 m/s, the speeds the clips were authored for, measured from the planted foot)
  → `Speed` (TimeScale = speed ÷ blended clip speed above the Walk point, so the feet don't
  slide; Run plays at 1.9× at 8 m/s) → output. `DraculaVisual.gd` smooths the speed with
  `locomotion_blend_time` (0.2 s), so stopping eases into Idle. Turning in place, sun
  adjustments and standing still all read 0 m/s, which is Idle. Hops keep Run playing.
- **Turning** (`DraculaController`, group *Turning*): he faces a point `facing_lookahead`
  (0.8 m) ahead on his path, lightly smoothed (`facing_smoothing` 14/s), turning at up to
  `turn_speed_degrees` (720°/s) with no lean or tilt. If the path direction is more than
  `turn_in_place_angle` (100°) from his facing, he stops and turns first, then sets off
  once within `turn_in_place_release` (20°).
- **Colours:** each of the 13 surfaces uses a duplicate of its `.glb` material in
  `game/assets/materials/dracula/` (same albedo, roughness and metallic; the eyes and ruby
  have their emission boosted to 2.6 and 2.0). Effects are added only via `next_pass`:
  surface → `dracula_rim.tres` (fresnel rim + burn glow) → `dracula_outline.tres`
  (screen-space inverted hull). There's no `material_override` and no `material_overlay`.
- **Readable in shade without lightening shade:** his mesh is on render layer 2
  ("Character"). `CharacterLight` (in `DraculaVisual.tscn`) is a shadowless
  DirectionalLight with **cull mask = Character only**, pointing from the camera side.
  A capture with this light on vs off differs only inside Dracula's own silhouette
  (a 109 × 112 px box at 1080 width); every ground and shadow pixel is identical. In
  sunlight he gets the normal sun light plus the burn effects.

## Failure

Two ways to lose: **sunlight** (below) and **caught** by a villager (see *Village:
villagers and hiding*). Both end in Game Over (`GameBus.game_over("sunlight" / "caught")`;
the panel reads "BURNED TO ASH" / "CAUGHT!").

Exposure (the sun meter in the top bar) is driven by `ShadowSensor`: three foot-level points on
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

| 4 · Village Watch (`levels/Level04.tscn`) | **Stealth + a sun you can't steer.** The sun runs by itself on a loop (hold 8 s, sweep 3 s). Before each sweep, get Dracula onto shade that lasts through it, or into a hiding spot. **A:** wait out the first sweep by the start. **B:** run up the street and slip past the red villager (haystack to hide in) to the crates. **C:** hide in the barrels while the sun swings past, then slip by the blue lantern-bearer to the crypt. A six-line tutorial plays at the start. | Auto sun: keys (−45°, 25°) → (−15°, 20.4°) → (60°, 18°) → (−17.5°, 18°), loop; first hold +16 s |

Levels 1–3 use the full default ranges (azimuth −80…80°, elevation 15…65°).

`level/LevelValidatorRunner.tscn` (driven by `level_solver.tres`, plus `patrol_check.tres` on
levels with villagers) proves each level is
**solvable**, **needs at least one sun adjustment**, and is **not trivial**: no single sun
sweep from the start spot connects straight to the goal. It searches the sun on both axes
(21 azimuth × 6 elevation samples). Its search moves the sun only while
Dracula stands on a pivot cell that stays shaded, with a margin, at both sample angles and
halfway between, mirroring the in-game guard. The end-to-end test then replays those
plans in the real game.

## Auto sun (levels whose sun runs by itself)

`ShadowLevel` → **Auto sun** group: `auto_sun` on, `auto_sun_keys` (azimuth, elevation
pairs), `auto_sun_hold_time`, `auto_sun_move_time`, `auto_sun_first_hold_bonus`. The sun
holds at each key, sweeps (smoothstep) to the next, and loops after the last key
(`ShadowLevel.auto_sun_state(t)` is the schedule; `ShadowRunFeature` steers the `SunRig`
along it while PLAYING). The player can't move the sun: both sun controls show
`ui/mfw/SunLock.tscn` (chains and a padlock over the control, still showing the sun's
position) with a countdown ("Sun moves in N" / "The sun is moving…"), and the guard is
off. Dracula can still be moved during a sweep (taps, drags and hiding use the shade as it
updates, about 10 times a second). Dracula burns if the
sweep lights him (exposure meter), so park him on shade that lasts or in a hiding spot.

Validation: `LevelSolver.solve_schedule()` (used automatically for auto-sun levels) walks
the loop: in each hold Dracula may run (`run_speed` 8 m/s) anywhere in his shade within the
hold time, and must end it on a cell whose footprint stays shaded at every sampled angle of
the next sweep (or on a hiding spot's Entry), up to `max_cycles` loops. The patrol check then
runs on that route.

**Tutorial:** `ShadowLevel` → **Tutorial** group: `tutorial_steps` (lines) and
`tutorial_step_time`. They play one after another in the hint banner at level start
(instead of `hint`).

## Village: villagers and hiding

**Hiding spots** (`props/village/hide/*.tscn`: barrels, haystack, covered cart, crate stack;
script `props/village/HideSpot.gd`):

- **Tap** a hiding spot (its `HideZone`, physics layer 5 `hide_spot`), or **end a drag** on
  it: Dracula takes the normal shade path to its `Entry` (a dashed ring on the ground) and
  hides. With no shaded route he shakes his head. He tucks into the prop (shrinks, then
  disappears) and a closed-eye icon shows above the spot.
- **Hidden** = invisible to villagers **and** safe from the sun: the sensor is shielded and
  the sun guard is off, so the sun can be swung freely while he hides (a hiding spot is a
  free pivot).
- **Tap anywhere else** (or start a drag) to leave and go there. He only leaves when the
  cell he hides on (or a neighbour) is shaded and the target is reachable; otherwise he stays
  hidden and shakes his head.
- `max_hide_time` per spot (0 = unlimited): the icon's ring empties, then he is pushed out
  at the Entry.

**Villagers** (`villager/Villager.tscn`, inherited from `assets/models/Villager/villager.glb`;
script `villager/VillagerController.gd`):

- **Patrol:** walks the points of its `patrol_path` (a `Path3D` in the level) at
  `walk_speed`, waits `wait_time` at each point playing LookAround, turning smoothly
  (`turn_speed_degrees`). `patrol_mode` LOOP or PING_PONG. The patrol is a fixed timeline,
  so the validator can simulate it exactly.
- **Vision:** a cone (`vision_range` 6 m, `vision_angle` 70°) drawn on the ground, plus a
  line-of-sight ray from the eye to Dracula's chest that walls and props (`obstacle` and
  `shadow_caster` layers) block. While chasing or searching the cone widens
  (`alert_angle_multiplier`). The drawn cone is not clipped by walls (only detection is).
- **Detection meter** (eye icon above the head, filling white → amber → red, with a "?" /
  "!" label): fills while he is seen, `sun_multiplier` (2×) in sunlight and
  `shade_multiplier` (0.5×) in shade (`time_to_spot` 1.2 s at 1×: 0.6 s in sun, 2.4 s in
  shade); fills **instantly** within `lantern_spot_radius` (1.8 m) of the lantern; drains at
  `drain_rate` out of view.
- **States:** Patrol → Suspicious (meter rising: stops, faces him, LookAround) → Alert
  (meter full: Alert clip) → Chase (Run, ground A* that ignores sunlight,
  `ShadeGrid.find_ground_path`) → Attack within `attack_range` (Attack clip; the hit at
  `attack_hit_time` fails the run with reason `"caught"`). If he hides or breaks line of
  sight first: Search the last seen spot (`search_time`), then Return and resume the patrol
  where it left off.
- **Look:** `tunic_color`, `vest_color`, `cap_color`, `trousers_color` are per-instance
  shader parameters (`villager_cloth.gdshader`), shown live in the editor (`@tool`). A warm
  `OmniLight3D` rides the `Lantern` bone (`lantern_range`, `lantern_energy`). The mesh is on
  render layer 2 (Character) so it reads in shade.

**Wiring:** `ShadowRunFeature` finds every `VillagerController` and `HideSpot` under the
level at setup, calls `villager.setup(dracula, grid, sensor, bus)`, and keeps villagers
active while the level is PLAYING. `GameBus` gained `villager_alerted(villager)` and
`dracula_hidden_changed(hidden)` for audio / haptics hooks.

### How to place a villager and its patrol

1. Under the level's **Villagers** node, add a **Path3D** (e.g. `GuardPatrol`) and click its
   points on the ground with the curve tool. Each point is a stop; keep the legs off walls
   and props.
2. Instance `villager/Villager.tscn` under **Villagers**, put it on the first point, and set
   **patrol_path** to the Path3D. Pick `patrol_mode`, `wait_time`, `walk_speed`, and
   `start_time_offset` to de-sync villagers.
3. Recolour with the **Clothing** colours; tune **Vision**, **Detection**, **Chase** and
   **Lantern** on the instance.
4. Add hiding spots from `props/village/hide/` near each watched stretch; keep each
   **Entry** marker on open ground reachable in shade.
5. Run `LevelValidatorRunner.tscn`: it lists every chokepoint on the solution route, the
   villager's longest gap there, and the nearest hiding spot.

### Village props

`props/village/`: `cottage_small` / `cottage_large` (half-timbered, casters), `stone_well`
(caster), `lamp_post` (warm light, solid only), `fence_section` (solid only), `cobble_road`
(visual; world-space cobble shader, scale it to resize), `barrel.tscn` (a primitive
barrel, 0.96 m; the imported `wooden_barrel.glb` is not used). Every prop is primitives + `.tres`
materials (`assets/materials/village/`). Casters carry `ShadowCaster` shapes that match their
shadow-casting meshes; small details (timber frames, windows, doors) and props without
gameplay shade (lamp posts, fences, barrels) don't cast shadows, so drawn shadows always
equal the shade grid.

**Dusk lighting** is a per-level override of the shared shell: the level sets
`Game/WorldEnvironment.environment = assets/environments/dusk_village.tres` (warm horizon,
blue-violet ambient, light depth fog) and a warmer, dimmer `Game/SunRig` sun colour/energy.

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

1. **Top bar, 10%:** pause, level label, exposure meter (`ui/mfw/ExposureMeter.gd`: a sun that fills red plus a bar; `ShadowRunHUD.show_exposure_meter`). Exposure also drives the burn vignette.
2. **Play view:** taps and drags happen here; nothing covers it except transient labels
   and, in dial mode, the dial. Dial mode: 90%, down to the bottom edge (camera
   `distance` 4.0 m). Slider mode: 75%, ending above the strip (camera 5.5 m). Either way
   Dracula sits in the lower-middle of the visible play view, above the controls.
3. **Dial mode:** `SunJoystick` (290 × 356 px including the HIGH/LOW labels), 24 px in
   from the bottom-right corner of the safe area. **Slider mode:** the `SunControl`
   strip, bottom 15% of the safe area.

Everything interactive sits inside `SafeArea` (`ui/common/SafeAreaMargin.tscn`): the
system insets (notch, gesture bar), converted to canvas px and updated on every size
change, **plus** minimum padding (16 top, 32 bottom, 24 sides), so nothing is ever flush
with the screen edge, even on phones that report zero insets. The 3D level stays
full-screen behind it.

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
| `Game/HUDLayer/…/SunJoystick` (`ui/mfw/SunJoystick.tscn`, the dial) | key speeds 180 °/s, `blocked_marker_time` 0.8 s, `left_handed`, `corner_margin` 24, `grab_slop` 28, shake; ring look on `Body/Ring` (`DialRing`: `ring_color`, `ring_width`, `tick_length`, `inner_fraction`, `inner_dashes`, `backdrop_color`); knob / marker / red rim in their StyleBoxes |
| `Game/HUDLayer/…/SunControl` (slider strip) | strip height via its `size_flags_stretch_ratio` (15), `drag_sensitivity` (1.5), key speeds (180 °/s), `elevation_drag_span`, `elevation_travel`, `sun_radius`, arc shape, blocked shake and colour |
| `Game/HUDLayer/ShadowRunHUD` | `play_view_ratio_joystick` 90 / `play_view_ratio_slider` 75, `show_debug_button` (off; debug builds only), `min_safe_margin` |
| `Game/Dracula` (`player/Dracula.tscn`) | `walk_speed` 5, `run_speed` 8, `run_threshold` 2 m, `acceleration` 45 m/s², `hop_time` 0.3 s, `hop_height`; Turning: `turn_speed_degrees` 720, `turn_in_place_angle` 100°, `turn_in_place_release` 20°, `facing_lookahead` 0.8 m, `facing_smoothing` 14/s; burn and death timings, cue angles |
| `Game/Dracula/Visual/DraculaVisual` (`player/DraculaVisual.tscn`, inherited from `Dracula/dracula.glb`) | `walk_clip_speed` 1.44, `run_clip_speed` 4.24, `locomotion_blend_time` 0.2 s, `min_time_scale` 0.5; graph in `AnimationTree`; `CharacterLight`: `light_energy` 1.3, `light_color` (0.84, 0.86, 1), `light_specular` 0.25 |
| `game/assets/materials/dracula/` | `dracula_rim.tres`: `rim_color` (pale violet), `rim_strength` 0.6, `rim_width` 0.28, burn `burn_color` / `burn_power`. `dracula_outline.tres`: `outline_color` (pale violet), `outline_width` 1.6 px. Per-surface colours and emission in `dracula_<part>.tres` |
| `Game/HUDLayer/ShadowRunHUD/SafeArea` (`ui/common/SafeAreaMargin.tscn`) | `min_top` 16, `min_bottom` 32, `min_left` / `min_right` 24, `simulate_insets_top/bottom/left/right` (0; debug only) |
| `Game/ShadowSensor` | `burn_rate` (100/1.2 per s), `heal_rate`, `ray_length` |
| `Game/ShadowRunFeature` | Touch: `drag_start_distance` 25 px, `drag_start_time` 0.15 s, `drag_repath_rate` 12/s, `drag_hop_hold_time` 0.2 s, `edge_penalty` 2. Sun control: `default_sun_mode` (Joystick), `camera_distance_joystick` 3.6, `camera_distance_slider` 5.5. `title_time`, F6 fallback |
| `Game/RunCamera` | `height`, `distance`, `pitch_degrees`, `fov`, `forward_smoothing`, death cam |
| `Game/MoveMarker` (`fx/MoveMarker.tscn`) | Ring size, `tap_ok` / `tap_fail` materials, `pulse_time`, `start_scale`, drag `follow_rate` |
| `level/level_solver.tres` | `angle_step` (2.5°), `check_midpoints` (off), `goal_radius`, `max_adjustments` (8); auto sun: `run_speed` (8), `max_cycles` (3) |
| `LevelNN` root (`ShadowLevel`), auto sun / tutorial | `auto_sun`, `auto_sun_keys`, `auto_sun_hold_time`, `auto_sun_move_time`, `auto_sun_first_hold_bonus`; `tutorial_steps`, `tutorial_step_time` |
| `ui/mfw/SunLock.tscn` | chain / lock / dim colours, `link_length`, `link_width`, `link_thickness`, `chain_extent`, `lock_size`, `round_backdrop`, countdown texts |
| `level/patrol_check.tres` | `time_step` (0.1 s), `dracula_speed` (8), `margin_time` (0.5 s), `max_hide_distance` (8 m) |
| `Villagers/<Villager>` (`villager/Villager.tscn`) | Clothing colours; Patrol `patrol_path`, `patrol_mode`, `walk_speed` 1.5, `wait_time` 2, `start_time_offset`, `turn_speed_degrees` 300; Vision `vision_range` 6, `vision_angle` 70, `alert_angle_multiplier` 1.8, `target_height` 1.1; Detection `time_to_spot` 1.2, `sun_multiplier` 2, `shade_multiplier` 0.5, `lantern_spot_radius` 1.8, `drain_rate` 0.4, `suspicious_threshold` 0.05; Chase `run_speed` 3.8, `attack_range` 1.2, `attack_hit_time` 0.45, `search_time` 3, `repath_interval` 0.25; Lantern `lantern_range` 3.5, `lantern_energy` 1.4; Animation `walk_clip_speed` 1.4, `run_clip_speed` 3.6, `blend_time` 0.2; cone colours |
| `props/village/hide/*` (`HideSpot`) | `max_hide_time` (0 = unlimited), `icon_fade_time` |
| `Game/Dracula` | Hiding: `hide_time` 0.25, `hide_tuck` 0.6, `hide_scale` 0.2; Caught: `caught_recoil_degrees`, `caught_recoil_time`, `caught_vanish_time`, `caught_linger_time` |
| `Game/ShadowRunFeature` | Stealth: `caught_focus_time` 1.5 s; Sun control: `sun_guard_enabled` (off = free sun, burn by the exposure meter) |
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

- **Village: 60 FPS on a phone is not measured.** The level has about 420 mesh instances
  (mostly small timber-frame boxes; frustum culling keeps roughly a third on screen), 5 lamp
  lights and 2 lantern lights (no omni shadows), fog, and up to two villager sight rays per
  frame. Desktop runs at 100 FPS. If a phone struggles, drop timber details first.
- **The patrol check is "gaps + hiding spots", not a time-expanded search.** It proves every
  watched chokepoint on the solver's route has an unwatched window long enough to run through
  and a hiding spot within `max_hide_distance`; it does not plan the exact waits. It counts
  any sighting as instant (the real meter needs time), so it is conservative.
- **Drawn vision cones aren't clipped by walls** (that would need runtime meshes); detection is.
- **The end-to-end test freezes the villagers** while replaying the solver's plan (hide steps
  still go through real taps); villager behaviour is covered by `VillagerStealthTest`.
- **Three Level 1 turning/drag checks in the end-to-end test also fail on the commit before
  the village work** ("not back to Idle after arriving" and two drag-release checks).

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
- **Placeholder audio.** The burn flinch is a whole-body tilt (the model has no flinch clip).
- **A faint moiré pattern shows on sunlit ground at the extreme high-sun angle** (around
  65°). It's not ordinary shadow acne: raising the bias didn't remove it. Mid angles
  render clean. Still to investigate.
- **The sun guard is only explicitly tested on azimuth.** It moves both axes together and
  the playthrough's elevation moves pass through it, but there is no dedicated
  elevation-blocking test.
- **Template docs:** `docs/OPTIMIZATION_GUIDE.md` (referenced by `# PDF §x` comments) is
  missing from this repo.
