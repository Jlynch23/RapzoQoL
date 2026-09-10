# Rapzo QoL

Rapzo QoL is a single modular quality-of-life addon for World of Warcraft Retail.

## One addon, internal modules

World of Warcraft now sees only one addon folder:

`RapzoQoL/`

Internal modules:
- Core — SavedVariables, scanning and bag ordering.
- Tooltip — item metadata and account-wide counts.
- Search — global inventory search.
- Collections — collection detection.
- Vendor — expanded merchant view and filters.
- AFK — fullscreen AFK screen.
- HUD — cursor ring, square minimap and minimalist Player/Target/Focus visuals.
- QoL — "current expansion only" filter preset for the Auction House and customer Crafting Orders searches.
- ReflectHerald — announces the spell you bounced back with Spell Reflection.
- CooldownPulse — Midnight-safe "cooldown ready" alert (icon + name), learns real cooldown lengths.
- CombatText — fonts, scale, gravity and duration of Blizzard's combat text (off by default).
- Config — runtime module controls, including toggles for every module.

## Installation

Copy or junction only `RapzoQoL` into:

`World of Warcraft/_retail_/Interface/AddOns/`

The legacy `RapzoBags_*` folders are no longer separate addons.

## Commands

- `/rapzo`
- `/rapzo config`
- `/rapzo modules`
- `/rapzo afk preview`
- `/rapzo hud status`
- `/rapzo hud style 1` — current compact unit-frame style.
- `/rapzo hud style 2` — clean icon-free layout, auras on top and cast bar below.
- `/rapzo hud preview` — toggles the in-game fake/demo unit-frame preview.
- `/rapzo hud preview on|off`
- `/rapzo expfilter on|off` — "current expansion only" preset in AH/Crafting Orders searches.
- `/rapzo reflect [status|on|off|party|test|stats]` — Spell Reflection announcer (short alias: `/rh`).
- `/rapzo pulse [status|on|off|scan|test|list|ignore|enable|min|size|move]` — cooldown-ready alert.
- `/rapzo damage [status|on|off|font|scale|gravity|duration|restore]` — combat text customization.

Legacy aliases `/rbags` and `/rapzobags` remain available, and `/rqol` is a short alias for `/rapzo`. The addon also registers `/rl` as a quick `/reload` shortcut (another addon registering `/rl` may take precedence depending on load order).

## Offline HUD preview

Open this file directly in a browser:

`preview/index.html`

It is a self-contained interactive preview that does not require World of Warcraft. It can switch between Style 1 and Style 2, change preview scale and simulate a mob/player target.

The offline preview is for geometry and visual iteration. Protected Blizzard behavior and real aura/cast rendering are validated with the in-game `/rapzo hud preview` mode.

## HUD frame styles

**Style 1** is the existing working Rapzo QoL unit-frame design and is intentionally preserved.

**Style 2** is selectable, uses an invisible outer container (no panel, no top line, no exterior border), and adds:
- class-correct colors from Blizzard's `RAID_CLASS_COLORS`;
- helpful player auras in a WoW 12.1 AuraContainer above the player frame;
- Target/Focus native aura containers re-anchored above the usable frame area;
- a Rapzo QoL cast bar below the frame using Midnight-safe duration handling when available;
- player-only secondary class resources between the main power bar and castbar:
  - Rogue: Combo Points;
  - Feral Druid: Combo Points;
  - Warlock: Soul Shards, including partial shard fill;
  - Paladin: Holy Power;
  - Windwalker Monk: Chi;
  - Arcane Mage: Arcane Charges;
  - Evoker: Essence;
  - Death Knight: six Runes with recharge progress.

Classes/specs without a discrete secondary resource keep the compact Style 2 spacing with no empty resource row.

## Compatibility

The addon intentionally keeps the existing `RapzoBagsDB` SavedVariables name so current data and preferences survive the migration.

## Development

Current development line: **3.0.0-alpha5** for WoW Retail 12.1.0.

Repository workflow rules are documented in `AGENTS.md`. Code changes should be performed directly in the repository when write access is available; users normally only need to sync and test.
