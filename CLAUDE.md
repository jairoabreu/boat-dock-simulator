# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a **marine propulsion control system simulator** built for Marine Telematics. It consists of self-contained HTML files (no build step, no dependencies, open directly in a browser) that simulate a twin-screw leisure boat with optional bow and stern thrusters.

## Files

| File | Purpose |
|------|---------|
| `propulsion_scene.html` | **Main active file.** Full physics simulator: boat moves near an L-shaped pier, dual view modes (normal + ego-centric), all propulsion logic. |
| `propulsion_validator.html` | Static visualizer: boat SVG + joystick + thrust readouts. No physics/movement — use for validating control logic in isolation. |
| `propulsion_scene_ego.html` | Legacy ego-only version, kept as backup. Superseded by `propulsion_scene.html`. |
| `iate_top_view.svg` | Original boat top-view icon (300×420 viewBox). Not actively edited. |

## Architecture of `propulsion_scene.html`

The file is a single ~1250-line HTML/CSS/JS file. Logic flows in this order:

### 1. Joystick Input → `state` object
- 3-axis joystick: inner circle (r < 81px) = XY drag (`surge`/`sway`), outer ring = rotation drag (`yaw`)
- Both zones spring back to zero on release
- `state = { surge, sway, yaw }` — all values in [-1, 1]

### 2. `calcThrust()` — Zone-based propulsion rules
Converts joystick state into motor commands `thrust = { port, stbd, bow, stern }`:
- **Yaw ring active** (`|yaw| > 0.015`): differential motor mode — port and stbd run opposite
- **Zone 1** (`|surge| ≥ 2×|sway|`): both motors equal (straight ahead/astern)
- **Zone 2** (`|sway| ≥ 2×|surge|`): thrusters only, motors off
- **Zone 3** (diagonal): single motor (port for starboard sway, stbd for port sway)
- Bow/stern thruster buttons (`bowBtn`, `sternBtn`) layer on top of joystick-derived commands
- `hasBow`/`hasStern` flags gate thruster commands

### 3. `updatePhysics()` — Forces in body frame → world frame
Key physics constants (tune via sliders):
```
ACCEL=0.11, ANG_ACCEL=0.0022, THR_SWAY=0.010, BOW_TORQUE=0.0010,
STERN_TORQUE=0.0010, PROP_WALK=0.022, DRAG=0.94, ANG_DRAG=0.88
```
Force pipeline each frame:
1. `netSurge` → forward/backward push along `fwdX/fwdY`
2. `netYaw` → rotation, scaled by `fwdFactor` (0.40 forward = larger turning circle, 1.80 reverse = tighter)
3. `netSway_thr` + `netYaw_thr` → thruster lateral force + independent torque per end
4. `netSway_propwalk` → prop walk / paddle-wheel effect (`(-port + stbd) × PROP_WALK`); BB avante drifts left, BE avante drifts right, both equal = cancels
5. Drag applied to all velocities
6. Boundary + pier collision (L-shaped: vertical dock x=6–70 y=80–376; finger x=70–246 y=6–48)

Body↔world transform: `fwdX=sin(h)`, `fwdY=-cos(h)`, `sidX=cos(h)`, `sidY=sin(h)`

### 4. View Modes (toggled by `#btn-mode`)
- **Normal mode**: boat div moves via `style.left/top/transform:rotate()`; `worldG` SVG group has no transform
- **Ego-centric mode**: boat div fixed at screen center `(SCENE_CX-48, SCENE_CY-89.5)`; `worldG` gets `translate(cx,cy) rotate(-deg) translate(-bx,-by)`; compass needle counter-rotates to show true north; wake points converted via `worldToScreen()`

### 5. Individual Gain Sliders
Each physics function has an independent gain variable and slider:
- `gainSurge` / `gain-surge` — main motors forward/reverse
- `gainYaw` / `gain-yaw` — differential turning
- `gainBow` / `gain-bow` — bow thruster
- `gainStern` / `gain-stern` — stern thruster
- `gainPropWalk` / `gain-propwalk` — prop walk / motor torque effect

`setupGainSlider(sliderId, valId, setFn)` wires each slider to its variable and updates the `--pct` CSS custom property for the visual fill.

## Key Conventions

- **Port = BB (Bombordo)**, **Starboard = BE (Boreste)** — never "Estibordo" or "EB"
- Contra-rotating props: port runs CCW forward (`invertCW=true`), starboard CW forward
- All UI text in **pt-BR**
- Color theme: dark navy background (`#09131f`), muted blue accents, green active state
- Thruster buttons are **momentary** (active on mousedown/touchstart, clear on mouseup/leave/touchend)
- Config toggles (`hasBow`/`hasStern`) in the "Equipamentos instalados" card disable the corresponding thruster rows visually and zero out their commands

## Running / Editing

No build tool or server needed — open any `.html` file directly in a browser. For live editing, a simple local server (e.g. `python3 -m http.server`) allows reloading without file:// restrictions.

When editing `propulsion_scene.html`, the most sensitive sections are:
- Lines ~860–895: `calcThrust()` — propulsion zone logic
- Lines ~926–996: `updatePhysics()` — all force calculations
- Lines ~1000–1043: view mode toggle and world/boat transforms
- Lines ~660–695: gain slider HTML inside `.gain-wrap` div
