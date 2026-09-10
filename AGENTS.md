# Rapzo QoL — Project Rules

> Documento historico. Las reglas vigentes (rama unica `main`, flujo de trabajo, arquitectura)
> estan en `CLAUDE.md`, que manda sobre este archivo cuando difieren (por ejemplo la regla 7 sobre
> `feature/afk-screen-alpha5`, que ya no aplica).

> Before changing Rapzo QoL, read `CODEX_HANDOFF.md` for the current architecture, feature inventory, HUD state, recent commits, testing checklist, and continuity notes.

## Code ownership and execution

1. When the user requests a code change for Rapzo QoL, the assistant must make the change directly in the GitHub repository whenever GitHub write access is available.
2. Do not ask the user to copy, paste, replace, or manually edit Lua/TOC/HTML code when the assistant can perform the repository write itself.
3. The user's normal responsibility is only to sync the repository on each PC (for example, `git pull`) and test behavior in World of Warcraft.
4. If GitHub write access is unavailable or a repository write fails permanently, explain that limitation before asking the user to make a manual code change.
5. Preserve known-working behavior. New experimental HUD/frame designs must be added as selectable styles or isolated modules instead of deleting the current working style unless the user explicitly asks to replace it.
6. Visual HUD work should provide two preview paths whenever practical:
   - an offline HTML preview under `preview/`;
   - an in-game Rapzo QoL preview mode using fake/demo frames.
7. Development work for the current alpha line belongs on `feature/afk-screen-alpha5` until the user explicitly decides to merge/promote it.
8. Before reporting a repository change as complete, verify the target branch and resulting commit.

## Current installation model

World of Warcraft sees one addon folder only:

`RapzoQoL`

Each development PC should junction that single folder from its local repository into Retail `Interface/AddOns`.
