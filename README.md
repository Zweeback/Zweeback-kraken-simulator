# Kraken Simulator

A physics-driven creature sandbox centered on a controllable kraken / octopus-like body interacting with ships, harbors and destructible environments.

## Product thesis

The tentacles are the game. Movement, grabbing, pulling, bracing, tearing, throwing and emergent physics should be fun before adding progression, lore or a large world.

## First vertical slice

- One kraken
- Eight independently simulated tentacles with constrained player assistance
- One harbor arena
- One ship
- Grab / pull / brace / break / throw loop
- Physics-based score and destruction feedback
- Stable camera and readable controls
- Deterministic reset / replay for testing

## Architecture

- `core/tentacle`
- `core/locomotion`
- `core/grabbing`
- `core/damage`
- `core/ai`
- `modes/sandbox`
- later: `modes/evolution`, `modes/pirate`

## Technical direction

Godot 4.7.1, desktop-first, Forward+ unless profiling proves otherwise. Keep physics authority separate from presentation and aggressively budget joint counts, collision shapes and destructible objects.
