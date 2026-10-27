# Shadow Run — Prototype

A 2.5D gothic endless runner built on the Godot Game Template. Dracula runs forward
automatically down a 3-lane road. He survives only in shade, and the player controls
where the shade falls by moving the sun. Build stage: `PROTOTYPE` (local only: no
network, ads or analytics).

## How to run

| What | How |
|---|---|
| Full game | Press **Play** (F5). Flow: `Boot.tscn` → Home → **Play** → `ShadowRun.tscn` |
| Gameplay scene only | Open `game/scenes/gameplay/shadow_run/ShadowRun.tscn` and press **F6** (see *Editor F6 fallback*) |
| Shade self-check | F6 on `shadow/ShadowSensorSelfCheck.tscn`, or headless (below) |
| Segment validator | F6 on `track/SegmentValidatorRunner.tscn`, or headless (below) |
| Retry soak test | F6 on `game/scenes/test/ShadowRunSoakTest.tscn` (windowed, so the two-touch check runs) |

```bash
godot --headless --path . res://game/scenes/gameplay/shadow_run/shadow/ShadowSensorSelfCheck.tscn
```

```bash
godot --headless --path . res://game/scenes/gameplay/shadow_run/track/SegmentValidatorRunner.tscn -- --verbose=seg_arcade
```

```bash
godot --path . res://game/scenes/test/ShadowRunSoakTest.tscn
```

Each tool exits with code 0 on success. `--verbose=<segment_id>` (or `*`) prints a shade
map for every sun angle, one character per meter per lane: `#` shaded, `+` partly lit,
`.` lit, `X` obstacle.

> The soak test plays 10 real runs, so it writes runs and best distance into your local
> save (`user://saves/`).

### Editor F6 fallback

`ShadowRunFeature.editor_f6_fallback` (on by default) handles the case where the scene was
launched directly and nothing injected it. It then creates `GameService` itself and runs
the same `inject_services()` pass that `SceneManager` would. The fallback:

- is guarded by `OS.has_feature("editor")`, so it never runs in exported builds;
- waits two frames, so it never fires in the normal Boot → Home → Play flow;
- is the only place in gameplay code that touches `ServiceRegistry` or `/root`.

## Controls

| Action | Touch | Desktop |
|---|---|---|
| Change lane | Swipe left/right in the **play view** (≥ ~60 px at 1080 width). A long drag can switch two lanes. | A/D or ←/→ |
| Sun azimuth (left ↔ right) | Drag horizontally in the **bottom sun strip** (relative drag, 1.3× sensitivity: touching never jumps the sun) | Q / E (or mouse drag in the strip) |
| Sun elevation (high ↔ low) | Drag vertically in the strip | R / F |
| Pause | ‖ button (top-left) | Esc or P |
| Debug overlay | Faint "dbg" button (bottom-left of the play view) | F3 |

**Touch arbitration.** A touch that starts inside the sun strip belongs to the sun until it
lifts: `SunControl._input()` consumes it. Every other touch reaches
`DraculaController._unhandled_input()` as a swipe candidate. Two fingers at once work
(the soak test checks this in a real window). Lane input registers in the same frame as
the event, and one extra move is buffered while a slide (0.12 s) is in progress.

## Portrait layout

| Setting | Value |
|---|---|
| Viewport | 1080 × 1920; desktop window override 540 × 960 |
| Orientation | `display/window/handheld/orientation = portrait` (locked) |
| Stretch | `canvas_items`, aspect `expand` (works from 9:16 to 9:21 phones and 3:4 tablets) |
| Safe area | `ShadowRunHUD` pads its `SafeArea` container with `DisplayServer.get_display_safe_area()` on mobile |
| Export presets | `export_presets.cfg` is git-ignored and does not exist yet. When you create the Android/iOS presets, keep the orientation portrait-only; the project setting above is what they inherit. |

Screen from top to bottom (`VBoxContainer` stretch ratios in `ShadowRunHUD.tscn`):

1. **Top bar, 10%:** pause, distance, exposure meter.
2. **Play view, 68%:** the 3D road. Only transient labels appear here (countdown, hints, the faint debug button).
3. **Sun strip, 22%:** a wide, shallow arc. The sun icon is about 150 px across.

**Camera** (`camera/CameraRig.tscn`): `keep_aspect = Keep Width`, so `fov` (50°) is the
horizontal angle and all 3 lanes plus the roadside shadows fill the width; taller screens
simply see further ahead. Defaults are height 11 m, distance 9 m and pitch 38°, which puts
Dracula at about 63% of screen height (the lower third of the play view). Rendered
captures confirmed all 3 lanes, Dracula and the shade ahead at 9:16 (540×960),
9:20 (432×960) and 3:4 (720×960).

## Lane configuration

`track/lane_config.tres` (`LaneConfig`) is the single source of truth for the lanes:

| Field | Value |
|---|---|
| `lane_count` | 3 (indexes 0, 1, 2) |
| `lane_width` | 2.5 m, so lane centers are x = −2.5, 0, +2.5 |
| `start_lane` | 1 (middle) |

Lane x is computed as `(i − (lane_count − 1) / 2) × lane_width`. These read it:

- `Dracula.tscn` (`lanes`): lane positions, start lane and edge clamping. A swipe or key
  past the road edge is ignored: no slide, no sound, no haptic. One extra move is still
  buffered during a slide.
- `TrackSpawner` (`lanes`, `road_material`): pushes `lane_count` and `lane_width` into the
  road shader's dashed dividers at prewarm.
- `segment_validator.tres` (`lanes`): which lanes are sampled.
- `ShadowDebugOverlay` (`lanes`): lane-center marker lines; Dracula's lane is yellow.

No script contains lane positions or a lane count. The **road mesh and the lane-spanning
props are authored geometry**, so changing the lane count also means re-authoring them.
Current 3-lane geometry:

- Road 8.5 m wide (edge ±4.25); curbs at ±4.4; sidewalks 4.55–8.05.
- Roadside props sit at |x| ≥ 4.75: facades ±6.25, castle walls ±5.45, towers ±7.25,
  trees ±6.75, ruin walls ±5.65, pillars ±5.05.
- Stone arch: piers ±5.35, deck 11.9 m.
- Banner gantry: posts ±5.25, beam 10.9 m.
- Arcade canopy: posts ±5.25; the roof is 4.4 m wide over the middle lane only.
- Gatehouse: towers ±7.75, deck 11.5 m.

**Overhead casters fade.** The gate roof, arch decks, canopies, gantry beams and banners sit
between the high camera and Dracula. Each of these parts is two meshes:

- a visual mesh that fades out within 16 m of the camera (`visibility_range_begin`);
- a twin with `cast_shadow = Shadows Only` that always casts.

So the shadow on the road never disappears and Dracula is never hidden.

## Scene list (everything is an editable `.tscn`)

All gameplay paths are under `game/scenes/gameplay/shadow_run/`.

| Scene | What it is |
|---|---|
| `ShadowRun.tscn` | Gameplay root: `ShadowRunFeature`, WorldEnvironment, SunRig, TrackSpawner, Dracula, ShadowSensor, RunCamera, Backdrop, DebugOverlay, HUD layer |
| `player/Dracula.tscn` | CharacterBody3D with body, head, cape, hitbox, 3 shade sample markers, BurnFX, DeathFX |
| `player/BurnFX.tscn` | Smoke and ember particles plus the flare light (scaled with exposure) |
| `player/DeathFX.tscn` | One-shot ash and bat bursts |
| `sun/SunRig.tscn` | DirectionalLight3D and sun angle state |
| `camera/CameraRig.tscn` | Portrait chase camera (all framing values exported) |
| `track/TrackSegment.tscn` | Base road segment (30 m, 3 lanes, `Casters` / `Obstacles` / `OptionalObstacles`) |
| `track/segments/seg_*.tscn` | 10 authored segments, inherited from `TrackSegment.tscn` |
| `props/casters/*.tscn` | building_facade, building_facade_short, castle_wall, castle_wall_long, castle_tower, watch_tower, pillar, tree, stone_arch, arcade_vault, banner_gantry, hanging_banner, covered_wagon (dual-purpose), ruin_wall, gatehouse |
| `props/obstacles/*.tscn` | crate, spike_trap, fallen_pillar |
| `Backdrop.tscn` | Distant hills and castle silhouettes (no shadows, no collision) |
| `debug/ShadowDebugOverlay.tscn` | Ray lines and info panel; hidden by default |
| `shadow/ShadowSensorSelfCheck.tscn` | Self-check rig: caster box, obstacle box, sun, probe, sensor |
| `track/SegmentValidatorRunner.tscn` | Validator tool scene |
| `game/scenes/ui/mfw/ShadowRunHUD.tscn` | Portrait HUD |
| `game/scenes/ui/mfw/SunControl.tscn` | Sun strip |
| `game/scenes/ui/mfw/GameOverPanel.tscn`, `PausePanel.tscn` | Panels pushed through `UIManager.push_packed()` |
| `game/scenes/test/ShadowRunSoakTest.tscn` | Retry, leak and two-touch soak test |

Saved resources:

- `track/run_difficulty.tres`: speed, segment difficulty, obstacle density and sun-delta curves, plus the onboarding sequence.
- `track/segment_validator.tres`: validator settings.
- `game/assets/materials/*.tres`: every material, including Dracula's, the FX, the burn rim, debug rays and backdrop.
- `game/assets/shaders/*.gdshader`: burn rim, burn vignette, cobble road.
- `game/assets/audio/sfx/*.wav`: placeholder SFX, synthesized and original.

**Nothing visual is assembled in code.** Scripts only animate or configure nodes that
already exist in scenes. The remaining `new()` calls are physics query parameters, an RNG,
validator data structs, and the `GameService` composition-root bootstrap in the F6
fallback and the soak harness. The only runtime geometry is the debug overlay's per-frame
ray lines.

## Script map

| Script | Role |
|---|---|
| `ShadowRunFeature.gd` (GameFeature) | Run lifecycle: injection → prewarm → countdown → `GameManager.start()` → per-frame loop → death → save → Game Over / Retry / Home; pause; GameBus relays |
| `player/DraculaController.gd` (extends `PlayerController3D`) | Auto-run, lanes and input buffer, swipe detection, burn feedback, both death animations |
| `game/scripts/controllers/PlayerController3D.gd` | 3D twin of the template's 2D `PlayerController`, with the same injection contract |
| `sun/SunRig.gd` | Azimuth/elevation clamps, speed-capped smoothing (135°/s), no-tail settle, light orientation, sky/ambient tint |
| `shadow/ShadowSensor.gd` | Gameplay shade truth (raycasts) and the exposure meter |
| `track/TrackSegment.gd`, `SegmentSafeWindow.gd` | Segment metadata and pooling helpers |
| `track/TrackSpawner.gd` | Prewarmed pool, recycling, difficulty-driven selection |
| `track/RunDifficulty.gd` | Difficulty resource (curves) |
| `track/SegmentValidator.gd` (Resource) | Fairness and "sun matters" proof per segment |
| `camera/RunCameraController.gd` | Follow (lane lag), shake, death dolly |
| `ui/mfw/ShadowRunHUD.gd`, `SunControl.gd`, `ExposureMeter.gd`, `GameOverPanel.gd`, `PausePanel.gd` | UI (all `UIController` except the meter) |
| `powerups/PowerUp.gd` | Empty interface stub (out of scope) |

**GameBus signals added:**

- `sun_exposure_changed(value)`
- `lane_changed(lane)`
- `distance_changed(meters)`
- `powerup_collected(id)` (reserved; nothing emits it)

**Deaths** emit the existing parameterless `player_died` (through `PlayerController3D.die()`),
then `GameManager.game_over(cause)` with `cause` = `"sunlight"` or `"obstacle"`. The
template's `player_died` has no argument, so the cause travels on `game_over`.

**Saving.** The `stats` repository holds the run count (`matches_played`), plus
`custom.best_distance` and `custom.total_distance`, followed by an explicit `save_game()`.
Home shows the best distance and run count.

## How shade detection works

Shade is never read from the shadow map. Every physics frame, `ShadowSensor` casts one ray
from each of Dracula's three markers (feet 0.2 m, torso 1.0 m, head 1.65 m) toward the sun.

- The direction is `SunRig.direction_from_angles(az, el)`, which is the light's −forward vector.
- Rays are 60 m long and only hit the `shadow_caster` physics layer (layer 4).
- A blocked ray means that point is shaded: `exposure_fraction = lit / 3`.

The exposure meter (0–100):

- rises at `burn_rate × fraction`, with `burn_rate = 100/1.2`, so full sun kills in ~1.2 s;
- heals at `heal_rate` (32/s) in full shade;
- fires `burned_out` at 100.

`exposure_changed` is only emitted on changes of at least 1 point.

**Rendering and gameplay agree** because every visible shadow-casting mesh has an identical
collision shape on layer 4. Small decorative parts (windows, iron bands, wheels, spikes)
have `cast_shadow` off, so they cast nothing in either system. Physics layers:

- `ground` (1)
- `player` (2)
- `obstacle` (3)
- `shadow_caster` (4)

Caster collision only blocks light. Physical blocking comes from a separate
`ObstacleBody` on layer 3, which the covered wagon, crate and fallen pillar have.

**Verify it with F3.** Green rays are shaded and red rays are lit. In a visible shadow,
all three should be green.

## Authoring a new segment in the editor

1. **Scene → New Inherited Scene…** from `track/TrackSegment.tscn`. The road runs from
   z = 0 to z = −30 (run direction −Z). Lane centers are x = −2.5, 0, +2.5 (lanes 0, 1, 2).
   Roadside props go at |x| ≥ 4.75. A fallen pillar spans two lanes when centered at
   x = ±1.25.
2. Drag caster scenes from `props/casters/` under **Casters**. Drag obstacles under
   **Obstacles** (always present) or **OptionalObstacles** (enabled by density).
   Move them with the gizmo.
3. On the root node, fill in the exports:
   - `segment_id`, `difficulty` (0–1), `onboarding`, `weight`, `requires_sun_move`;
   - at least one `safe_windows` entry (New `SegmentSafeWindow`): lane, start/end meters,
     and azimuth/elevation range.
4. Save as `track/segments/seg_<name>.tscn`, then add it to **TrackSpawner →
   segment_scenes** in `ShadowRun.tscn`. Pools are prewarmed at load, `copies_per_scene` = 2.
5. Run `SegmentValidatorRunner.tscn`. A segment fails if it:
   - is **unsolvable**: no lane+sun path survives (optional obstacles on);
   - is **sun_irrelevant**: a path survives the worst sun angle everywhere;
   - is **sun_optional**: every fixed sun angle solves it;
   - has `requires_sun_move` set while a fixed angle solves it;
   - declares a safe window that isn't really shaded;
   - is **lane_always_safe**: one lane, ridden straight through, survives the worst sun
     angle. With only 3 lanes this is the easiest way for the sun to become irrelevant;
   - is **all_lanes_blocked**: every lane is physically blocked at the same distance, with
     all optional obstacles on. This is what guarantees the spawner can never close the road.

   It also **warns** (`lane_mostly_shaded`) when a lane is shaded at every sun angle for
   more than 40% of its length.

   Use `--verbose=<id>` shade maps to place safe windows.

**New casters.** Pair each shadow-casting mesh with an identical `CollisionShape3D` under a
`ShadowCaster` StaticBody3D (layer 4, mask 0). For overhead parts, also follow the fade
pattern: a visual mesh with `cast_shadow = Off` and `visibility_range_begin = 16`, plus a
`Shadows Only` twin.

## Tunables

| Where | What |
|---|---|
| `lane_config.tres` | `lane_count` (3), `lane_width` (2.5 m), `start_lane` (1) |
| `run_difficulty.tres` | `speed_min` 9 / `speed_max` 17 m/s and `speed_curve` over `ramp_duration_s` (360 s); `max_difficulty_curve`, `difficulty_window`; `obstacle_density_curve`; `sun_delta_curve`; onboarding duration (30 s) and sequence |
| `ShadowSensor` (in `ShadowRun.tscn`) | `burn_rate`, `heal_rate`, `ray_length`, `emit_step` |
| `SunRig` (select **SunRig** in `ShadowRun.tscn`, or open `sun/SunRig.tscn`; Motion group) | Azimuth −70…70, elevation 18…60, `max_azimuth_speed` / `max_elevation_speed` 135 °/s, `smoothing` 13 /s (≈ 0.08 s lag), `min_follow_speed` 40 °/s, `settle_threshold` 0.25°, start angles (−45°/36° so onboarding starts in shade), colors |
| `Dracula` | Lane positions, slide time, swipe threshold (fraction of width), burn and death animation timings, bob/lean |
| `CameraRig` | `height`, `distance`, `pitch_degrees`, `fov`, `lateral_follow`, death cam |
| `SunControl` (select **HUDLayer/ShadowRunHUD/…/SunControl**, or open `ui/mfw/SunControl.tscn`) | `drag_sensitivity` 1.3, `key_azimuth_speed` / `key_elevation_speed` 135 °/s, `sun_radius` (≥ 70), arc sag, high/low rows |
| `ShadowRunFeature` | Countdown, onboarding `hint_times` / `hint_texts`, F6 fallback |
| `segment_validator.tres` | Sample grid, entry exposure (25), lane dwell (0.3 s), window tolerance, `max_azimuth_speed` / `max_elevation_speed` (keep equal to SunRig: 135 °/s) |

## Mobile renderer and shadow settings

| Setting | Value |
|---|---|
| Renderer | `rendering_method = mobile` on desktop and mobile; project features "Mobile". This replaces the template's GL Compatibility default, as the brief requires. |
| Sun light | 2 cascades (`PARALLEL_2_SPLITS`), split 0.25, `max_distance` 100 m, no blend splits, bias 0.04 / normal bias 1.2, pancake 30 |
| Shadow atlas (mobile) | Directional size 2048 and hard filtering (the engine's mobile defaults); positional atlas 1024 |
| Particles | CPUParticles3D only (cheap, no GPU particle compile) |
| Environment | Ambient from color (no sky ambient cost), reflections disabled, light fog, mild glow |

The 60 FPS target on a mid-range Android device has **not been measured**: there was no
device in this session. Profile on hardware before tuning further.

## Verification done

- **ShadowSensorSelfCheck:** 11/11 pass (lit/shaded at known angles, obstacle layer never shades, burn-out in ~1.2 s, recovery).
- **SegmentValidator (3 lanes):** all 10 segments pass. Fixed-angle solutions range from 9/75 to 34/75, so every segment needs the sun in a particular region. No lane is safe at every angle, and no distance has every lane blocked. A negative test (burn disabled) confirms `lane_always_safe` fires.
- **Soak test (windowed):** 10 Retries with flat node count (1806 each time), one `GameBus` connection, 10 saved runs and pause/resume. It also covers two-touch arbitration (sun strip drag + play-view swipe = sun moved and exactly one lane change) and lane edges (bursts of presses past both edges end exactly on lanes 0 and 2).
- **Rendered captures** at 9:16, 9:20 and 3:4 (framing, HUD inside bounds, shade contrast).

## 3-lane re-authoring notes

The switch from 4 to 3 lanes kept every segment's purpose:

| Segment | What changed |
|---|---|
| `seg_gate_start` | Safe window is now lane 0 only |
| `seg_left_row` / `seg_right_row` | Lane 0 / lane 2 (was lane 3) |
| `seg_sun_swing` | Lane 0, then lane 2 |
| `seg_arcade` | Canopy narrowed to cover only the middle lane (shade puzzle in lane 1); optional crates moved to the outer lanes |
| `seg_banners` | Gantries hang banners over lanes {0, 2}, then {1}, then {0, 2}; the optional spike trap is in lane 2 |
| `seg_wagon` | Wagons in the outer lanes (0, then 2) throw shade into the middle lane with the sun left, then right. This is still the wagon decision |
| `seg_courtyard_gap` | Keep shadow window moved to lane 1 |
| `seg_ruins_slalom` | Fallen pillars span lanes 0–1, then 1–2, so one lane always stays open |
| `seg_towers_narrow` | Unchanged except for roadside x |

Every roadside prop moved 0.75 m inward to the narrower road. Obstacle density in
`run_difficulty.tres` was lowered (peak 0.6, was 0.9; 0.12 at 15% of the ramp, was 0.2).

## Known issues / limits

- **Onboarding segments warn `all_shaded`** (one angle shades over 90% of the road). This is intentional wide shade for the first 30 s, and it is a warning, not a failure.
- **Validator approximations:**
  - assumes 25 exposure on entry;
  - uses the expected speed for the segment's difficulty;
  - moves elevation one grid step every other tick;
  - does not model shadows cast across segment boundaries (these can only add shade).
- **Particle intensity.** `CPUParticles3D` has no `amount_ratio`, so burn intensity scales particle color alpha and speed instead.
- **Sizzle sound.** `AudioManager` has no looping SFX handle, so the sizzle is retriggered as short bursts while burning.
- **Desktop window size.** A window taller than your monitor gets clamped by the OS. Test tall aspects at a size that fits, e.g. 432×960 for 9:20.
- **Headless runs** cannot test touch positions (0×0 window), so the soak test skips that check unless it is windowed.
- **Generated, then hand-editable.** Props, segments and panels were generated once by throwaway scripts and are now plain scenes. Edit them in the editor; nothing regenerates them.
- **Placeholder art and audio.**
- **Template docs.** `docs/OPTIMIZATION_GUIDE.md` (referenced by the template README and by `# PDF §x` comments) and the phase guide are missing from this repo. New code keeps the `# PDF §4 / §5 / §6` convention, based on how existing comments use it.
