# 🌸 Survive the Apocalypse Script — Anime / RPG Fantasy Edition

<div align="center">

![GitHub Stars](https://img.shields.io/github/stars/TheHilichurl/Survive-the-Apocalypse-Script?style=for-the-badge&color=ec4899)
![GitHub Forks](https://img.shields.io/github/forks/TheHilichurl/Survive-the-Apocalypse-Script?style=for-the-badge&color=fbbf24)
![Game](https://img.shields.io/badge/Roblox-Survive%20the%20Apocalypse-a855f7?style=for-the-badge&logo=roblox)
![Version](https://img.shields.io/badge/Version-v14.0%20Modular-38bdf8?style=for-the-badge)

**The ultimate, fully modular and beautifully styled script for Roblox *Survive the Apocalypse*.**  
*Engineered directly from decompiled game mechanics with a custom Anime/RPG Fantasy neon aesthetic.*

</div>

---

## ⚡ Quick Start (Execute via Executor)

Run the following one-line command in any modern Roblox executor (Synapse, Wave, KRNL, Fluxus, Delta, Codex, Hydrogen, etc.):

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/TheHilichurl/Survive-the-Apocalypse-Script/main/main.lua"))()
```

---

## 🌟 Key Highlights & Aesthetics

- 🌸 **Anime / RPG Fantasy Theme**: Neon Sakura Pink (`#EC4899`), Star Amber Gold (`#FBBF24`), and Deep Arcane Twilight Velvet (`#160924`).
- ✨ **Glow & Drop Shadow System**: Glowing neon borders, outer drop shadow aura, smooth gradients, and interactive animations.
- 🐾 **Custom Floating Toggle**: Sleek on-screen toggle button featuring the custom Hilichurl badge with drag and minimize support.
- 📐 **Dynamic Scaling & Corner Resize Grip**: Draggable `//` grip at the bottom-right corner to freely resize the hub with full font and layout responsiveness.
- 💾 **Automatic Cloud & Local Save**: Automatically saves and loads player configuration via `STA_<username>.json`.

---

## 📂 Modular Architecture

```
survive the apocalypse/
├── main.lua                # Master entry point & dynamic GitHub/local loader
├── README.md               # Documentation & usage guide
├── core/
│   ├── env.lua             # Services, compatibility helpers, Remotes & Anti-Cheat guard
│   ├── config.lua          # Config table, persistence (save/load) & auto-save manager
│   └── utils.lua           # Character helpers, safe step-teleports, item classification
├── modules/
│   ├── combat.lua          # Kill Aura, Break Aura, Virtual Bullet Raycast, Silent Aim, Gun mods
│   ├── abilities.lua       # Psychic, Outlaw, Hacker, Necromancer, Alchemist, Operator, etc.
│   ├── looting.lua         # Auto loot, guided physics item flight to Base, smart hunger
│   ├── structures.lua      # Base repair aura, auto upgrade structures, remote workbench crafting
│   ├── movement.lua        # Fog revealer, speed boost, noclip, velocity fly, POI teleports
│   └── visuals.lua         # Color-only highlight ESP (30-cap limit friendly), fullbright, no fog
├── ui/
│   └── uilib.lua           # Portable Anime / RPG Fantasy UI Library Engine
└── interface.lua           # UI window construction & 7 feature-packed tabs
```

---

## 🎮 Features Overview

### 1. Dashboard & Telemetry
- **Live Game Telemetry**: Day number, phase (Day/Night/Blood Moon/Blizzard), mobs left, countdown timer.
- **Base Status**: Generator level, fuel %, Scrap, Batteries, Hearts.
- **Player Stats**: Class, Class Level, Perk, Gems, Zombie Skulls.
- **Knightmare Anti-Cheat Ping Guard**: Auto-responds to ping telemetry events to prevent detection.
- **Anti-AFK**: Bypasses the 20-minute idle kick.

### 2. Combat & Weapons
- **Melee Kill Aura**: Multiple target priorities (Nearest, Lowest HP, Highest HP, Specials First).
- **Bloater Safety Guard**: Prevents melee swings on Bloaters to avoid death explosion damage.
- **Special Melee Attacks**: Auto-triggers Power Hammer, Scorchblade, and Bloodthirster specials.
- **Break Aura**: Breaks Barrels, Scrap Piles, and Crashed Cars automatically.
- **360° Silent Aim & Auto Shoot**: Works off-screen with virtual bullet raycast verification and real-time HP checks.
- **Gun Modifications**: No Recoil, No Camera Shake, 100% Accuracy (No Spread), Rapid Fire, Fast Reload (4x), Automatic Fire, Instant Charge, and Max Penetration.

### 3. Class Abilities & Perks
- **Universal X & C Auto-Abilities**: Auto activates equipped skills off cooldown.
- **Psychic**: Auto binds backpack guns to Remote Arsenal and auto fires.
- **Outlaw**: Auto Quickdraw 6x instant headshot burst.
- **Hacker**: Infiltrate zombie virus propagation & System Override detonation.
- **Necromancer**: Auto summon undead allies & instant recall.
- **Alchemist**: Auto brew potions & instant thrown potion detonation.
- **Operator**: Combat drone targeting mode management.
- **Commander & Vanguard**: Auto Airstrike, Charge, and Counter shockwaves.

### 4. Looting, Smart Hunger & Item Flight
- **Direct-to-Backpack Looting**: Never forces equipped weapons out of your hand.
- **Touch & Guided Flight to Base**: Smooth physics flight for nearby and map-wide items to Base, Generator, or Shredder.
- **Smart Hunger**: Automatically eats food when hunger < 70%; stores into backpack sack when >= 70%.
- **Auto Heal**: Auto consumes bandages, medkits, or recovery compounds when low HP.
- **Auto Crate Opener & Objective Interactor**: Opens loot crates, interacts with power plants, radio towers, and survivors.

### 5. Base, Structures & Crafting
- **Repair Aura**: Repairs walls, gates, turrets, and generator using Repair Hammer.
- **Auto Upgrade Structures**: Upgrades fences, gates, and watchtowers with Upgrade Hammer.
- **Remote Workbench Crafting**: Access Levels 1–4 crafting menus from anywhere on the map.
- **Remote Ammo Crate**: Auto crafts Pistol, Medium, Long, or Shells ammo when reserve is low.
- **Remote Merchant Shop**: Browse and auto buy items using Zombie Skulls.

### 6. Visuals & Clean ESP
- **Master Color-Only Highlight ESP**: Zero text clutter; renders clean glowing outlines.
- **Roblox 31-Highlight Cap Friendly**: Nearest distance priority sorting prevents invisible ESP bugs.
- **Target Categories**: Zombies, Bloaters (Lime), Screamers (Magenta), Bosses (Orange), Dropped Items (Category-colored), Crates (Gold), Teammates (Cyan), Generator (Green).
- **World & Environment**: Fullbright, No Fog, Remove Screen Overlays (Poison, Radiation, Low HP), Cutscene Skipper, and FPS Boost.

### 7. Movement, Teleport & AFK Farm
- **Physics Boosts**: WalkSpeed, Infinite Hunger Sprint, Bunny Hop, Infinite Jump, Noclip, Velocity Fly.
- **Map Fog Revealer**: 1-Click full city map reveal via `FogTouched`.
- **POI Teleports**: Base Generator, Workbench, Power Plants, Radio Tower, Military Base, Nuclear Bunker, Downed Teammates.
- **Full AFK Gem Farm**: Automates survival, repairs, looting, returning to base at night, and voting play again on game over.

---

<div align="center">
Made with 💖 by <b>TheHilichurl</b>
</div>
