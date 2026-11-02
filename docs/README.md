# Shadow Run

> Dracula must cross a sunlit village by bending shadows and hiding from lantern-carrying villagers.

![Shadow Run Gameplay](media/gameplay.gif)

## Gameplay
- **Move Through Shade:** Tap or drag in the play area to guide Dracula along safe, shaded ground.
- **Reshape Shadows:** Turn the sun using the bottom-right dial joystick (or bottom slider) to shift cast shadows and forge new paths.
- **Sunlight Burns:** Stepping into direct sunlight rapidly fills Dracula's exposure meter. Extended exposure turns him to ash.
- **Stealth & Villagers:** Villagers patrol with lanterns and vision cones. If they spot Dracula, they detect, chase, and attack.
- **Hide Spots:** Conceal Dracula inside barrels, haystacks, covered carts, and crate stacks to escape villager sightlines.
- **Reach the Crypt Door:** Traverse each stage to reach the crypt door and escape.

## Features
- **5 Handcrafted Levels:** Progression from city alleys to the village edge and watchtower (`Level01` through `Level05`).
- **Level Select & Saved Progress:** Progress unlocks new levels and saves locally.
- **Cinematic Level Intro:** Camera smoothly showcases the Goal before easing into gameplay framing on Dracula.
- **Safe-Area Portrait UI:** Designed for portrait mobile gameplay (1080×1920) with notched-display safe area handling.
- **Two Sun-Control Modes:** Choose between dial joystick or arc slider from the Pause panel.
- **Mobile-Optimised 60 FPS:** Time-budgeted shade raycasts, 2-cascade split shadow maps, and physics interpolation.

## Controls

### Mobile
- **One-Finger Tap / Drag:** Move Dracula through shade.
- **Joystick / Slider:** Rotate sun azimuth (angle) and elevation (height).
- **Android Back Button:** Opens exit confirmation popup.

### Desktop Testing
- **Left Mouse Button (Click / Drag):** Move Dracula.
- **Q / E:** Rotate sun azimuth left / right.
- **R / F:** Adjust sun elevation up / down.
- **F3:** Toggle debug overlay.
*(Note: A / D / Arrow keys are not used).*

## Tech
- **Engine:** Godot 4.7 (Mobile renderer)
- **Language:** GDScript
- **Shade Grid:** `AStarGrid2D` coupled with direct 3D physics raycasts for real-time walkable shadow geometry.
- **Models & Visuals:** Custom `.glb` character, villager, and village models with custom shaders for vision cones, detection meters, and cobblestones.

## Project Structure

| Directory | Contents |
|---|---|
| `game/scenes/gameplay/shadow_run/levels/` | Puzzle level scenes (`Level01.tscn` to `Level05.tscn`) and level catalog |
| `game/scenes/gameplay/shadow_run/player/` | Dracula controller, animation blend tree, and particle FX |
| `game/scenes/gameplay/shadow_run/villager/` | Villager patrol AI, detection meter, lantern, and vision cone |
| `game/scenes/gameplay/shadow_run/props/` | Village hide spots (barrels, haystacks, carts, crates) and casters |
| `game/scenes/ui/mfw/` | Portrait HUD, sun joystick & slider, pause, level select, and exit popups |
| `game/assets/` | 3D models (`.glb`), materials, custom shaders, and audio assets |

## How to Run & Build
1. Open the project in **Godot 4.7+**.
2. Press **Play** (or `F5`). The game starts from `game/scenes/boot/Boot.tscn`.
3. **Android Export:** Portrait preset (`1080×1920`) configured in `export_presets.cfg`.

## Roadmap
- Additional village and castle levels
- Advanced patrol types (watchdogs, lantern patrols)
- Special abilities (bat dash, distraction cues)

## Credits
Built with Godot 4.7.
