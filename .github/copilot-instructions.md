# Kraken Simulator coding-agent instructions

Prioritize the product thesis: **the tentacles are the game**.

- Work in bounded vertical slices.
- Keep physics authority separate from presentation.
- Prefer high-level player intent plus assisted tentacle coordination over per-joint micromanagement.
- Preserve deterministic reset/replay hooks for testing.
- Budget joints, collision shapes, and destructible bodies aggressively.
- Do not expand into progression, lore, economy, or a large world before locomotion/grab/pull/brace/release is fun and testable.
- Avoid external art dependencies for core mechanics.
- Never claim biologically realistic soft-body simulation unless the implementation and tests actually support that statement.
- Make changes on a feature branch and open a PR; do not write directly to main.
