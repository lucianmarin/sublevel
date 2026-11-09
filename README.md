# Sublevel — Technical & Design Specification (Godot 4)

> **Concept:** A hyper-kinetic, textureless 3D arena shooter where **Mirror's Edge** architectural color-blocking meets the movement physics of **Quake III Arena** and the dual-mode weaponry & dodge mechanics of **Unreal Tournament '99**.
> **The Pun ("Sublevel"):** Rather than traditional RPG "leveling up" via stat bloat, progression happens by descending through stark, brutalist underground architectural strata (*Sublevels*) and mastering spatial elevation, momentum, and verticality within each arena.

---

## 1. Core Pillars

1. **Pure Chromatic Readability (Mirror's Edge):** Zero photo-textures. Surfaces are defined by smooth roughness values, stark white architectural concrete, radiosity color bleeding (GI), ambient occlusion, and saturated functional color coding.
2. **Momentum Mastery (Quake 3):** Uncapped horizontal air-acceleration, strafe-jumping, bunny-hopping, rocket-jumping, and slick wall-skimming.
3. **Tactical Reactivity (UT99):** Double-tap directional dodge-jumps, wall-dodges, and high-skill alt-fire weapon combos (e.g., Shock Core + Beam detonation).
4. **Vertical Descent & Elevation ("Sublevel"):** Arenas are stacked vertically. Knockback, jump pads, and destructible floor grates drop or launch combatants between sub-strata mid-fight.

---

## 2. Visual & Rendering Architecture (Godot 4 Forward+)

### 2.1 Textureless Material Pipeline
All world geometry uses a unified **Master Architectural Shader** (`res://shaders/arch_surface.gdshader`) instead of bitmap textures.
- **Albedo:** Driven by material presets or vertex colors (`COLOR.rgb`).
- **Surface Micro-detail:** Procedural world-space triplanar Simplex/Worley noise at sub-perceptual amplitude (`0.015` normal strength) to catch specular highlights without looking "textured."
- **Edge Highlighting:** Screen-space normal/depth edge beveling or baked vertex-color curvature so brutalist geometry reads crisply at any distance.

### 2.2 Color Semantic Language ("Sublevel Vision")
Every color in the arena has gameplay meaning:
| Swatch | Hex | Gameplay Meaning |
| :--- | :--- | :--- |
| **Stark White / Warm Gray** | `#F4F5F7` | Neutral static geometry, floors, walls |
| **Signal Red** | `#FF2A19` | Kinetic flow: Jump pads, wall-dodge panels, launch ramps |
| **Cobalt Blue** | `#0057FF` | Vertical transitions: Drop shafts, teleporters, gravity lifts |
| **Amber Gold** | `#FFB800` | High-tier pickups: Mega-health, Armor shards, Powerups |
| **Acid Magenta / Cyan** | `#FF007A` / `#00F0FF` | Enemy team silhouettes (unshaded fresnel rim + high-contrast albedo) |

### 2.3 Lighting & WorldEnvironment Setup
- **Renderer:** Godot 4 `Forward+` targeting **240+ FPS**.
- **Global Illumination:**
  - **Static Arena Geometry:** `LightmapGI` with high-bounce indirect multipliers (`2.0+`) so colored accent walls bleed saturated bounce light onto adjacent white corridors (classic *Mirror's Edge* Beast lightmapper look).
  - **Dynamic Objects/Projectiles:** `VoxelGI` or `ReflectionProbe` grid for real-time emissive flashes from plasma/shock projectiles onto white walls.
- **Post-Processing (`WorldEnvironment`):**
  - **Tonemapper:** `AgX` or `ACES` with high contrast and bright exposure.
  - **SSAO & SSIL:** Enabled for crisp contact shadows and real-time color bleeding in corners.
  - **Glow / Bloom:** Soft bicubic bloom tuned specifically for emissive projectiles, jump pads, and sunlit sky shafts.

---

## 3. Movement Physics Architecture (`SublevelCharacterBody3D`)

Built on a custom state-driven `CharacterBody3D` bypassing standard damped platformer physics in favor of **id Tech 3 (`PM_Accelerate`) + UT99 Dodge** math.

### 3.1 Core Kinematic Constants
```gdscript
# res://scripts/player/movement_config.gd
class_name MovementConfig extends Resource

@export_group("Ground Movement")
@export var max_ground_speed: float = 10.5      # m/s (~320 ups equivalent)
@export var ground_accel: float = 12.0
@export var friction: float = 6.0
@export var stop_speed: float = 3.2

@export_group("Air / Quake 3 Physics")
@export var max_air_wish_speed: float = 1.25    # Low wish-speed cap enables Q3 strafe-jumping
@export var air_accel: float = 2.5
@export var cpm_air_control: float = 150.0      # Optional CPMA W-only air turning
@export var gravity: float = 24.0
@export var jump_impulse: float = 8.8           # Auto-hop on hold

@export_group("UT99 Dodge & Wall Tech")
@export var dodge_impulse_horizontal: float = 13.5
@export var dodge_impulse_vertical: float = 5.2
@export var dodge_cooldown: float = 0.35
@export var wall_dodge_max_count: int = 2
@export var slide_friction_multiplier: float = 0.15
```

### 3.2 Physics Tick Pipeline (`_physics_process(delta)`)
1. **Input Sampling:** Capture wish direction (`wish_dir`), queued jump buffer (`0.1s` window), and double-tap/dedicated dodge key vector.
2. **Ground Check & Queue Jump:** If `is_on_floor()` and jump is held/buffered, immediately apply vertical impulse and skip ground friction on that frame (preserving 100% horizontal momentum).
3. **Ground vs. Air Acceleration:**
   ```gdscript
   func accelerate(wish_dir: Vector3, wish_speed: float, accel: float, delta: float) -> void:
       var current_speed := velocity.dot(wish_dir)
       var add_speed := wish_speed - current_speed
       if add_speed <= 0.0:
           return
       var accel_speed := minf(accel * delta * wish_speed, add_speed)
       velocity += wish_dir * accel_speed
   ```
4. **UT99 Dodge & Wall-Dodge:**
   - **Ground Dodge:** Instant horizontal burst (`dodge_impulse_horizontal`) + low vertical hop (`dodge_impulse_vertical`).
   - **Wall Dodge:** While airborne near a wall (`ShapeCast3D` ring check), pressing Dodge + directional input away from the wall normal redirects velocity and grants a burst across the gap.
5. **Sublevel Slam / Slide:** Holding crouch mid-air increases downward gravity (`2.2x`) to dive into lower sublevels; landing on a ramp or holding crouch above base speed converts vertical velocity into a low-friction slide.
6. **Stair Stepping & Ramp Sliding:** Custom `move_and_collide` step-up solver (up to `0.45m` steps) so stairs never kill bunny-hop speed, and upward ramps convert horizontal speed into vertical launches ("trimping").

---

## 4. Weapon & Arsenal System (UT99 Dual-Mode + Q3 Trinity)

Weapons are modular `Resource` + `Node3D` rigs using hitscan (`PhysicsDirectSpaceState3D.intersect_ray`) and deterministic projectiles. Every weapon features **Primary Fire**, **Alt-Fire**, and a **Cross-Mode / Movement Synergy**.

| Weapon | Color Accent | Primary Fire | Alt-Fire | Synergy / Combo |
| :--- | :--- | :--- | :--- | :--- |
| **1. Kinetic Gauntlet / Impulse** | Signal Red | High-knockback melee dash | Focused air-blast cone | Blast floors for zero-self-damage vertical hops or knock enemies off sublevels |
| **2. Prism Rifle** *(Shock Rifle)* | Electric Cyan | Instant hitscan beam (45 dmg) | Slow-moving unstable Plasma Orb (55 dmg) | **Shock Combo:** Shoot the Alt-Fire Orb with the Primary Beam for a massive 160-dmg sphere explosion |
| **3. Shard Cannon** *(Flak Cannon)* | Amber Orange | 9-pellet ricocheting geometric shrapnel spread | Arcing fragmentation grenade | Pellets bounce once off white walls with glowing orange trails |
| **4. Vector Launcher** *(Rocket)* | Crimson | Fast linear rocket (100 dmg, high splash) | Hold to load up to 3 rockets (spiral or spread) | Core rocket-jumping tool; reduced self-damage (`0.4x`) |
| **5. Sub-Rail** *(Railgun / Sniper)* | Cobalt Violet | Piercing 90-dmg slug with persistent volumetric beam | Zoom + vertical penetrator (pierces thin sublevel floors) | Rewards high-velocity mid-air flick shots |

---

## 5. "Sublevel" Arena & Progression Mechanics

The name **Sublevel** drives both the spatial design and match rules:
1. **Stratified Arenas (`B1` -> `B2` -> `B3`):**
   - **B1 (Atrium / Skylight):** Bright natural white light, long sightlines (Rail/Prism territory), high exposure.
   - **B2 (Concourse):** Tight red/orange kinetic corridors, wall-dodge shafts, Flak & Rocket brawls.
   - **B3 (The Sump / Core):** High-risk, saturated cobalt/amber lighting where powerups (`Quad Overdrive`, `Sub-Shield`) spawn over lethal abysses.
2. **Dynamic Breaches:** Certain glass skylights and concrete floor plates shatter when hit by Shock Combos or Rockets, creating new vertical drop-downs mid-match.
3. **Momentum HUD & Style Meter:** Instead of XP bars, a sleek diegetic speedometer (u/s) and **Sublevel Flow Multiplier** track airtime, multi-level kills (killing an enemy on a different vertical stratum), and Shock Combos.

---

## 6. Project Directory Structure

```text
sublevel/
├── project.godot
├── addons/
│   └── func_godot/                  # TrenchBroom .map importer for rapid brutalist blockouts
├── assets/
│   ├── audio/                       # Crisp reverb-heavy footsteps, synth weapon reports, announcer
│   └── meshes/                      # Low-poly bevelled weapon & pickup primitives
├── scenes/
│   ├── main.tscn
│   ├── player/
│   │   ├── player.tscn              # CharacterBody3D + CameraRig + WeaponViewport
│   │   └── hud.tscn                 # Minimalist high-contrast crosshairs + speedometer
│   ├── weapons/                     # Individual weapon scenes & projectile VFX
│   └── arenas/
│       ├── sl_atrium.tscn           # Multi-stratum arena 01
│       └── interactables/           # JumpPad, Teleporter, ShatterFloor, PickupSpawner
├── scripts/
│   ├── autoload/
│   │   ├── game_manager.gd          # Match state, frag limits, sublevel breach events
│   │   ├── audio_bus_controller.gd  # Dynamic reverb based on B1/B2/B3 depth
│   │   └── network_manager.gd       # ENet/MultiplayerSynchronizer tick-rollback foundation
│   ├── player/
│   │   ├── sublevel_player.gd       # Main controller
│   │   ├── movement_solver.gd       # Pure math Q3/UT99 acceleration, dodge, & trimping
│   │   └── camera_fx.gd             # Strafe roll tilt, FOV speed scaling, landing punch
│   └── weapons/
│       ├── weapon_controller.gd
│       ├── weapon_resource.gd
│       └── shock_combo_orb.gd       # Area3D + Hurtbox that detects hitscan beam intersection
└── shaders/
    ├── arch_surface.gdshader        # Textureless triplanar micro-normal + vertex color shader
    ├── player_silhouette.gdshader   # High-visibility team color + rim light
    └── shock_sphere.gdshader        # Volumetric inverted-hull sphere distortion for combos
```

---

## 7. Node Hierarchy: `player.tscn`

```text
SublevelPlayer (CharacterBody3D)
├── CollisionHull (CollisionShape3D - Capsule 0.8m x 1.8m)
├── StairStepperCast (ShapeCast3D)
├── WallDodgeDetector (ShapeCast3D - Cylinder)
├── HeadPivot (Node3D)
│   └── CameraRecoilPivot (Node3D)
│       ├── WorldCamera (Camera3D - FOV 105, culls Viewmodel layer)
│       └── SubViewportContainer (Viewmodel Layer - prevents weapon clipping into walls)
│           └── SubViewport
│               └── ViewmodelCamera (Camera3D - FOV 75)
│                   └── WeaponMount (Node3D)
├── HitboxRig (Node3D - Area3D capsules for head/torso/legs)
├── MovementAudio (Node3D - 3D spatial wind loop, slide scrape, dodge whoosh)
└── HUD (CanvasLayer)
```

---

## 8. Implementation Roadmap (Milestones)

1. **M1 — The White Room (Movement & Feel):**
   - Implement `movement_solver.gd` with Q3 strafe-jumping, auto-hop, and UT99 ground/wall dodges.
   - Build a test gym with ramps, gaps, jump pads, and a live horizontal speedometer.
2. **M2 — Chromatic Radiosity (Visual Prototype):**
   - Author `arch_surface.gdshader` and bake a 3-stratum vertical test map (`B1`–`B3`) with `LightmapGI` and *Mirror's Edge* color bleeding.
3. **M3 — The Arsenal (Combat Loop):**
   - Implement the **Prism Rifle** (with working Shock Combo), **Vector Launcher** (with rocket jumping), and **Shard Cannon**.
4. **M4 — Arena Bot & Multiplayer Slice:**
   - Implement navmesh + jump-link bots capable of using jump pads and tracking airborne targets, plus 60Hz `ENetMultiplayerPeer` state sync.

---

## 9. Native macOS Build (Swift 6 + Metal)

This repository implements the complete **Sublevel** specification natively for macOS using **Swift 6**, **Metal / MetalKit**, and **AVAudioEngine** procedural audio synthesis.

### Build & Run
```bash
# Build Sublevel.app bundle + AppIcon.icns
make app

# Build and launch Sublevel.app
make run

# Run the movement, weapon combo, breach, and simulation unit test suite
make test
```

### Controls
| Input | Action |
| :--- | :--- |
| **Click Window** | Capture mouse cursor for 3D arena look |
| **W / A / S / D** | Ground movement & airborne strafe-jumping |
| **Double-Tap W / A / S / D ( or Q / E )** | UT99 Ground Dodge or Airborne Wall-Dodge (up to 2x off walls) |
| **Space (Hold)** | Jump / Auto-Hop (skips ground friction on landing frame) |
| **C / Left Ctrl / Shift** | Crouch-Slide (on landing above 11 m/s) or **Sublevel Slam** (2.2x gravity dive in mid-air) |
| **Left Click** | Primary Fire |
| **Right Click** | Alt-Fire (Shock Orb, Arcing Grenade, 3-Rocket Charge, Rail Zoom) |
| **1 – 5 / Scroll** | Switch Weapon (Gauntlet, Prism Rifle, Shard Cannon, Vector Launcher, Sub-Rail) |
| **R** | Reset Arena & Breaches |
| **M** | Mute / Unmute Procedural Synth Audio |
| **ESC** | Release Mouse Capture |

