# Kraken Motor System

The movement system is the game's primary feature.

The player never micromanages eight arms during normal play. The player supplies intent, direction, speed and target selection. The motor system turns that into coordinated soft-body movement.

## Player contract

The controls should feel closer to a fast third-person action game than to a deliberate physics puzzle.

The player should be able to trust:

"If I point the kraken there and ask it to grab, the body will find a plausible, readable way to do it without making me solve its joints."

Complexity belongs under the controls, not in the controls.

## Control layers

### 1. Player intent

Small vocabulary:

- FLOW — fastest locomotion and momentum preservation
- HUNT — target pursuit, reaching, grabbing and attacks
- GHOST — fast low-profile movement, camouflage and quiet contact

The player does not select arm numbers.

### 2. Motor primitives

Reusable biological / biomechanical operators:

- PROPAGATE — send curvature down an arm
- ELONGATE / SHORTEN — axial reach or pull
- STIFFEN — temporary support / pseudo-joint
- ADHERE / RELEASE — establish and break surface contacts
- TORSION — rotate / wrap the flexible arm
- JET — whole-body impulse from mantle / siphon

Gameplay verbs such as grapple, swing, wall-run, silent takedown and slingshot are chains of these primitives rather than independent locomotion systems.

### 3. Autonomous tentacle layer

Each tentacle continuously receives a temporary role:

- STREAM
- REACH
- GRIP
- WRAP
- PULL
- BRACE
- PROBE
- RECOVER

Roles are dynamic. No arm is permanently the attack arm.

## Flow examples

### Fast surface traversal

REACH -> ADHERE -> PULL -> opposite-arm BRACE -> RELEASE -> next REACH

The next arm begins reaching before the previous arm releases. This overlap is critical: contacts form a rolling support network rather than stop/start animation states.

### Grapple zip

PROPAGATE -> ADHERE -> STIFFEN -> SHORTEN -> RELEASE + optional JET

The motor system preserves incoming velocity and adds the pull vector instead of zeroing player momentum.

### Wrap / swing

REACH -> ADHERE -> TORSION -> WRAP -> tension build -> body orbit -> controlled RELEASE

Wrapping should be automatic once a suitable cylindrical or edge target is acquired.

### Silent takedown

PROBE / target lock -> REACH -> soft GRIP -> WRAP -> PULL

Free arms remain responsible for body support and collision avoidance.

## Anti-frustration rules

These are stronger than strict physical purity.

1. No ordinary arm micromanagement.
2. A valid player intent should almost always produce a useful action.
3. Contact targets use generous attraction / correction volumes.
4. Arms may slide to a nearby valid contact rather than miss by centimeters.
5. Animation never freezes movement input unless a move explicitly requires commitment.
6. Grabs, wraps and attacks should preserve or redirect momentum, not kill it.
7. Tangles are treated as a controller failure, not as player punishment.
8. The system may cheat locally to maintain a believable silhouette and responsive control.

## No-clipping / no-tangle stack

The final system should use several layers rather than relying on raw rigid-body collision alone.

### A. Reach planning

Before committing a reach:

- sweep a capsule from arm base toward target;
- reject impossible lanes;
- reserve a spatial corridor for the selected arm;
- bias neighboring arms away from that corridor.

### B. Arm-arm separation

Adjacent arms receive soft repulsion constraints.

This is not meant to visibly push them apart. It prevents two chains from trying to occupy the same path before penetration happens.

### C. Surface contact projection

A requested grip is projected onto a valid nearby surface point with:

- surface normal;
- curvature estimate;
- available sucker area;
- approach direction.

The arm follows the projected contact, not the exact noisy player reticle.

### D. Wrap solver

For a pole, limb or rail:

1. identify the target axis / local surface;
2. choose a winding direction that minimizes arm crossing;
3. reserve a helical lane;
4. progressively convert distal arm segments from reach to wrap;
5. stop adding windings when enough grip exists.

### E. Tangle recovery

If arm-arm penetration or impossible curvature crosses a threshold:

- lower stiffness;
- release the least important contact;
- temporarily widen its spatial lane;
- re-plan toward the nearest useful configuration.

The player should perceive this as the animal naturally repositioning itself.

### F. Last-resort presentation correction

If the physical solve would create an obviously broken pose, presentation may temporarily diverge from strict simulation through:

- local collision softening;
- contact sliding;
- constrained teleport of a small distal segment;
- render skeleton correction while physics converges.

Believable motion beats dogmatic simulation.

## V1 implementation

KrakenMotor is the first thin layer:

- chooses FLOW / HUNT / GHOST;
- assigns changing arm roles;
- generates role-dependent joint motion;
- gives alternating arms small spatial lane biases to reduce visual self-intersection;
- keeps attack arms and brace arms active at the same time.

This is deliberately not yet the final contact planner. The next implementation milestone is world-aware reach planning with capsule sweeps and automatic surface grips.

## Success criterion

The movement feature is working when a player can perform a chain like:

swim -> underside grapple -> pull -> corner wrap -> swing -> silent grab -> release -> jet back into water

without ever thinking about which arm is doing which sub-action.
