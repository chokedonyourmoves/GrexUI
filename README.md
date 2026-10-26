# GrexUI

A modular ESP, Chams, and silent-aim suite built on **Rayfield Gen 2**, designed as an educational reference for how these systems fit together in Lua.

> **Educational use only.** This project is intended for private servers, Studio testing, or your own game. Using it on live Roblox servers violates the Terms of Service and harms other players. But who cares tho? Who genuinely care with this diclaimer?? See [Disclaimer](#disclaimer).

---

## Table of Contents

- [Features](#features)
- [Installation](#installation)
- [Usage](#usage)
- [Feature Reference](#feature-reference)
- [Profiles](#profiles)
- [Architecture](#architecture)
- [Detection Resistance](#detection-resistance)
- [Limitations](#limitations)
- [Disclaimer](#disclaimer)

---

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

Kewl GUI is a single Lua file. There is no build step.

### Option 1 — Load from URL

Paste this one line into your executor while Roblox is running:

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/chokedonyourmoves/GrexUI/refs/heads/main/GrexUI.lua"))()
