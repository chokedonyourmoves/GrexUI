## Features

- **ESP** — boxes, healthbars, names, distance, team check, max distance
- **Chams** — full-body highlight with configurable fill + outline colors
- **Tracers** — look tracers and player tracers with independent colors
- **Silent Aim** — raycast rewriting with smoothing, prediction, hitbox expansion
- **Camera Aim** — visible camera-lock mode for a "legit" feel
- **Triggerbot** — auto-fire within a pixel FOV with cooldown
- **Target Priority** — crosshair, distance, lowest health, or threat
- **Profiles** — one-click Legit / Semi / Rage presets
- **Keybinds** — bind aimlock and triggerbot without opening the UI
- **Fullbright** — with original-lighting restore
- **Stealth layer** — rate-limited raycast rewrites, angular jitter, ease-out aim
- **Performance mode** — halves ESP drawing writes at no visible cost
- **Robust teardown** — restores metatable, lighting, highlights, and connections

---

## Installation

Grex UI is a single Lua file. There is no build step.

### Option 1 — Load from URL

Paste this one line into your executor while Roblox is running:

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/chokedonyourmoves/GrexUI/refs/heads/main/GrexUI.lua"))()
```

Your script file should begin with its own Rayfield loadstring call:

```lua
local Rayfield = loadstring(game:HttpGet("https://sirius.menu/gen2"))()
```

### Option 2 — Paste directly

Paste the entire `GrexUI.lua` contents into the executor and click Execute.

### Executor requirements

| Function | Used for | Required |
|---|---|---|
| `loadstring` / `game:HttpGet` | Loading Rayfield + this script | ✅ |
| `getrawmetatable` / `setreadonly` / `newcclosure` | Silent-aim raycast hook | ✅ |
| `Drawing.new` | ESP boxes, tracers, FOV circles | ✅ |
| `mouse1click` or `VirtualUser` or `keypress` | Triggerbot firing | ⚠️ At least one |

If your executor lacks any of the required functions, the script will error at the relevant section. Drawing features will silently no-op without `Drawing`.

---

## Usage

1. Execute the script — the Rayfield window opens.
2. Use the sidebar to switch between **Combat**, **Visuals**, **World**, and **Config**.
3. Toggle features, adjust sliders, pick colors. Every change auto-saves.
4. Press `RightControl` (default) to hide/show the UI.
5. Open **Config → Unload Script** to fully restore the game state.

### Quick start

- **Just want ESP?** → Visuals → *Enable ESP Boxes*
- **Want to see through walls?** → Visuals → *Enable Chams*
- **Want aim assist?** → Combat → *Enable Aimlock* (try the **Legit** profile first)
- **Want a clean slate?** → Config → *Apply: Legit* or *Unload Script*

---

## Feature Reference

### ⚔️ Combat

#### Aim

| Feature | Type | Description |
|---|---|---|
| Enable Aimlock | Toggle | Master switch for aim assistance |
| Aimlock Keybind | Keybind | Toggle aimlock without opening the UI |
| Aim Mode | Dropdown | `Silent` rewrites raycasts; `Camera` lerps your view |
| Aim Smoothness | Slider (0–1) | 0 = instant snap, 1 = slowest turn |
| Target Priority | Dropdown | `Crosshair` / `Distance` / `LowestHealth` / `Threat` |
| Target Part | Dropdown | `Head` / `HumanoidRootPart` / `UpperTorso` / `LowerTorso` / `Random` |
| FOV Size | Slider (10–600 px) | Radius of the aim selection cone |
| Show FOV | Toggle | Draws the aim FOV circle |
| FOV Circle Color | Color | Live color of the aim circle |

#### Trigger

| Feature | Type | Description |
|---|---|---|
| Triggerbot | Toggle | Auto-fires when a target enters the trigger FOV |
| Triggerbot Keybind | Keybind | Toggle triggerbot without the UI |
| Triggerbot FOV | Slider (1–60 px) | Pixel radius for auto-fire |

#### Filters

| Feature | Type | Description |
|---|---|---|
| Wall Check | Toggle | Raycast line-of-sight before aiming or firing |
| Ignore Passive | Toggle | Skips AFK / near-zero-velocity players |
| Ignore Friends | Toggle | Skips Roblox friends (cached on join) |
| Prediction | Toggle | Leads the target based on ping + velocity |
| Prediction Amount | Slider (0–5) | Multiplier on the prediction lead |
| Hitbox Size | Slider (0–5) | Random point inside a sphere around the target part |

### 👁️ Visuals

#### ESP

| Feature | Type | Description |
|---|---|---|
| Enable ESP Boxes | Toggle | Master ESP switch |
| ESP Box Color | Color | Replaces health-derived box color |
| Healthbar | Toggle | Vertical bar on the left of the box (health-colored) |
| Player Nicknames | Toggle | Username above the box |
| Distance | Toggle | Meter readout below the box |
| Team Check | Toggle | Hides teammates (also gates chams) |
| Max Distance | Slider (100–5000) | Beyond this, ESP hides |
| Text Size | Slider (8–24) | Name/distance font size |

#### Chams

| Feature | Type | Description |
|---|---|---|
| Enable Chams | Toggle | Highlight instance on every player |
| Chams Fill Color | Color | Live-updates all highlights |
| Chams Outline Color | Color | Live-updates all highlights |

#### Tracers

| Feature | Type | Description |
|---|---|---|
| Look Tracers | Toggle | Line from crosshair (center) to player |
| Look Tracer Color | Color | Live color |
| Player Tracers | Toggle | Line from bottom-of-screen to player |
| Player Tracer Color | Color | Live color |

### ☀️ World

| Feature | Type | Description |
|---|---|---|
| Fullbright | Toggle | Forces max brightness, no fog; restores on off |
| Reset Lighting | Button | Manually restores snapped lighting values |

### ⚙️ Config

#### Profiles

| Feature | Description |
|---|---|
| Apply: Legit | Camera mode, high smoothing, low rewrite cap, no triggerbot |
| Apply: Semi | Silent aim, mid smoothing, triggerbot, stealth on |
| Apply: Rage | Instant snap, large FOV, triggerbot, stealth off |

#### Performance

| Feature | Description |
|---|---|
| Performance Mode | Processes ESP drawings every other frame (halves property writes) |

#### Detection Resistance

| Feature | Description |
|---|---|
| Stealth Mode | Ease-out aim, angular jitter, slower behavior profile |
| Aim Jitter | Sub-degree noise added to every predicted point |
| Max Raycast Rewrites / sec | Caps how many raycasts the silent-aim hook can rewrite per second |

#### Utility

| Feature | Description |
|---|---|
| Unload Script | Restores metatable, removes drawings/highlights, disconnects everything, destroys Rayfield |

### Always-on behavior

These run regardless of toggles:

| Behavior | Purpose |
|---|---|
| Friend cache | `IsFriendsWith` resolved once on join (it yields) |
| Character removal cleanup | Hides drawings immediately on death |
| pcall guards | Update loop + teardown are individually protected |
| Shared raycast | One wall-check raycast feeds both aimlock and triggerbot |
| Chams team check | Respects Team Check per frame |
| Auto-save | Every setting change persists to `GrexUI/KewlConfig` |

### Feature totals

| Category | Count |
|---|---|
| Aim | 9 |
| Trigger | 3 |
| Filters | 6 |
| ESP | 8 |
| Chams | 3 |
| Tracers | 4 |
| World | 2 |
| Config | 12 |
| **Total user-facing** | **47** |

---

## Profiles

Profiles are one-click bundles of ~10 settings. They write to `Settings` and silently sync the UI handles so the panel always reflects the current state.

| Setting | Legit | Semi | Rage |
|---|---|---|---|
| Aim Mode | Camera | Silent | Silent |
| Aim Smoothness | 0.75 | 0.35 | 0 |
| Aim FOV | 40 | 90 | 300 |
| Triggerbot | Off | On (0.12s) | On (0.05s) |
| ESP Boxes | Off | On | On |
| Chams | Off | On | On |
| Tracers | Off | Off | On |
| Stealth Mode | On | On | Off |
| Aim Jitter | 0.02 | 0.01 | 0 |
| Max Rewrites/sec | 10 | 20 | 60 |

Use these as starting points, not absolutes — tweak the sliders after applying.

---

## Architecture

### Data flow

```
RenderStepped
    └── SafeUpdate (pcall wrapper)
            └── UpdateAll
                    ├── Chams team check        (every player, every frame)
                    ├── ESP rendering           (every other frame in Performance Mode)
                    ├── Target selection        (every frame)
                    ├── Triggerbot              (every frame)
                    ├── FOV circle layout       (every frame)
                    └── Camera lock (if Camera) (every frame)

workspace.Raycast (hooked)
    └── Silent aim (if Aim Mode = Silent)
            ├── Rate limiter check
            ├── GetPredictedPos (prediction + jitter + hitbox)
            ├── Smoothing (linear or ease-out)
            └── Rewrite direction
```

### Core state

| Table | Purpose |
|---|---|
| `Settings` | Every toggle, slider, color, and mode value |
| `EspObjects` | Per-player drawing handles (box, tracers, text, healthbar) |
| `ChamsObjects` | Per-player Highlight instances |
| `FriendsCache` | `UserId → boolean` resolved on join |
| `Handles` | UI element references for profile syncing |
| `Connections` | Every RBXScriptConnection for clean teardown |

### Lifecycle

- **Join:** `CreateEsp` + `SetupChams` + async `RefreshFriendStatus`
- **Death:** `CharacterRemoving` hides drawings; chams auto-reapply on `CharacterAdded`
- **Leave:** `RemoveEsp` + destroy highlight + clear friend cache
- **Unload:** restore metatable → remove drawings → destroy highlights → restore lighting → destroy Rayfield → disconnect connections

---

## Detection Resistance

> **Read this before enabling Stealth Mode.** No Lua-level change bypasses Hyperion (Byfron). Stealth Mode reduces *behavioral anomalies* that server-side heuristics look for. It does not stop injection detection.

### What Stealth Mode changes

| Layer | Behavior |
|---|---|
| **Rate limiter** | Caps raycast rewrites at `MaxRewritesPerSecond` (default 30). Rewriting every raycast is one of the loudest signatures. |
| **Aim jitter** | Adds sub-degree noise to every predicted point. No two shots are pixel-identical. |
| **Ease-out smoothing** | `alpha²` instead of `alpha` — fast initial correction, slow settle. Looks less robotic than linear lerp. |
| **Profile discipline** | The Legit preset uses Camera mode + high smoothing + low rewrite cap; Rage turns stealth off deliberately. |

### What it does not do

- **Bypass Hyperion.** Injection-level detection happens before Lua runs.
- **Bypass server-side aim analysis.** A server that logs every shot's angle delta will still see a signal; jitter only makes it noisier.
- **Bypass replay review.** Human reviewers will still spot impossible reaction times. The Legit profile mitigates this by disabling triggerbot and using Camera mode.
- **Make Rage safe.** Rage is deliberately loud. It exists as a contrast so you can see what stealth changes.

### Practical guidance

- For any game with an active anti-cheat, use **Legit** and leave Stealth Mode on.
- For Studio or your own game, use **Rage** to see full behavior.
- **Semi** is a middle ground — silent aim is still detectable, but the smoothing + jitter + rate cap make it significantly harder to flag than a raw rewrite.

---

## Limitations

- **Single-account, single-executor.** No multi-account support.
- **Drawing API required.** Chams and Fullbright work without it; ESP and FOV circles do not.
- **Triggerbot depends on executor.** Uses `mouse1click`, then `VirtualUser`, then `keypress` — whichever your executor supports.
- **Camera aim is single-player-per-frame.** The closest target by priority wins; multi-target locking is not implemented.
- **No movement exploits.** Fly, noclip, speed, and anti-aim are out of scope by design (different category, higher detection surface).
- **No auto-farm / quest bots.** Game-specific and outside the educational goal.
- **Profiles are additive.** Applying a profile does not reset settings it does not list — use `Unload Script` for a clean reset.
- **Hyperion is unaddressed.** See [Detection Resistance](#detection-resistance).

---

## Disclaimer

This project is provided **strictly for educational purposes**:

- Studying how ESP, chams, aim assistance, and prediction are implemented in Lua
- Learning UI architecture with Rayfield Gen 2
- Testing in **Roblox Studio** or **your own game**
- **Not** for use on live Roblox servers, competitive games, or any environment where other players are affected

Using this code on live servers:

- **Violates the Roblox Terms of Service** and will result in account termination
- **Harms other players** by degrading their experience
- **Undermines the platform** you are a guest on

The author assumes **no responsibility** for any consequences of misuse — bans, account loss, or otherwise. By running this code, you accept full responsibility for where and how you run it.

If you want to learn from this project responsibly, do it in a **private Studio place** with a **second test account** that you own.

---
