# Terraform Trek Architecture

## Layering

- `main.lua`: callback wiring only.
- `app/*`: app shell, scene manager, input routing, service registry.
- `scenes/*`: gameplay/influence/card-library scene contracts.
- `systems/*`: turn, forecast, hazard, coupling, objectives, magnetosphere math APIs.
- `content/*`: data definitions (worlds, hazards, cards, industries, encounters/rewards/relics scaffolding).
- `domain/*`: run state model and domain entities.
- `run/*`: encounter-flow scaffolding for Slay-the-Spire-like expansion.
- `ui/layout/*`: screen layout calculators.
- `ui/components/*`: reusable UI widgets.

## Scene Contract

Every scene should expose:

- `enter(ctx, payload)`
- `exit()`
- `update(dt)`
- `draw()`
- `keypressed(key)`
- `mousepressed(x, y, button)`
- `wheelmoved(dx, dy)`
- `resize(w, h)`

## System Contract

- `TurnResolver.resolve_end_turn(run_state, action, rng)`
- `ForecastSystem.preview(run_state, action)`
- `HazardSystem.apply(hazard, magnetosphere_level, stats)`
- `CouplingSystem.compute(stats, rules, terraforming_state)`
- `ObjectivesSystem.compute(run_state)`

## Refactor Guardrails

- Do not mutate game state inside draw functions.
- Keep hit-testing in scene/input modules.
- Keep business logic in systems/domain modules.
- Prefer content-driven additions over in-scene branching.

## Current Transitional Note

Gameplay behavior currently runs through `app/legacy_runtime.lua` to preserve stability while modules are extracted.
New features should target `content/*` and `systems/*` first; legacy runtime calls should shrink over time.
Scene modules now call explicit scene-specific runtime methods (`*_gameplay`, `*_influence`, `*_card_library`) instead of a single generic event path.
Shared data/constants for terraforming state are now split into `domain/terraforming_defaults.lua` and `domain/terraforming_math.lua`.
