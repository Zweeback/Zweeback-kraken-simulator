# Visual Direction — 3D Creature Game

## North star

Kraken Simulator should read immediately as a **playable 3D underwater creature game**, not as a simulation dashboard.

The player should feel that they are *inside the water controlling a physical creature*. The simulation remains underneath, but the presentation is game-first.

## Camera

- Third-person chase camera, slightly above and behind the creature.
- Strong depth cues: foreground tentacles, mid-ground props, distant silhouettes.
- Camera glides rather than snapping.
- The kraken fills a meaningful portion of the frame.
- Mouse look / controller-look should orbit around the creature.

## Creature

- Plastic-surreal / toy-like silhouette rather than anatomical realism.
- Rounded, highly readable body mass.
- Eight clearly legible tentacles.
- Tentacles should overlap in depth and continuously move, even while idle.
- Materials should feel tactile: glossy-to-satin, not flat-shaded debug geometry.
- The player must visually understand which mass belongs to the creature at a glance.

## Underwater world

- Dark-but-readable blue/teal volume.
- Fog establishes depth instead of hiding everything.
- Directional light from above with brighter shallow water and darker depth.
- Seafloor and large props anchor scale.
- Later harbor content should use oversized, chunky silhouettes: piers, ship hulls, containers, buoys, chains.

## HUD

HUD is an overlay, not the visual identity.

Show only useful state:
- depth
- speed / boost
- interaction prompt
- destruction / score feedback

Avoid large panels, engineering readouts or a screen dominated by widgets during ordinary play.

## Gameplay read

The desired first impression is:

> "I am controlling this creature in a 3D underwater space and I want to swim into that ship and grab it."

Not:

> "I am operating a physics simulator."

## MVP visual acceptance criteria

1. Launching the project opens directly into a 3D underwater scene.
2. The player sees the kraken from a third-person camera.
3. The kraken can move in six degrees enough to feel like swimming.
4. Eight tentacles are visible and continuously animated.
5. Lighting + fog produce obvious near/far depth.
6. The scene has large environmental objects for scale.
7. HUD occupies little screen area.
8. No editor/debug visualization is required to understand what is happening.

## Art pass after mechanics

Replace primitive meshes in this order:

1. Kraken body + tentacle mesh
2. Tentacle skin/material
3. Seafloor rocks / debris
4. Harbor props
5. Ship
6. particles / bubbles / caustics
7. destruction VFX

The physics architecture should remain separated from presentation so these replacements do not rewrite gameplay code.
