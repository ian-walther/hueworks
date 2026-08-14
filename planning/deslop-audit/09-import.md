# Chunk 9 — Import Plane

Status: CLOSED. IP1-IP2 implemented and reconciled. No open findings. (`Normalize.resolution_of/1` and `Normalize.entity_source_id/1` are now the single owners of those rules.)

## Explicitly Fine / Leave-Alone

- **`Normalize.fetch` dual-key access throughout the plane** — the boundary rule; JSON round-trip makes it correct.
- **`ReimportApply.apply_lights`/`apply_groups` parallel reduces** — parallel but *not* identical (canonical-id tracking, duplicate-target semantics differ per entity kind); a parameterized merge would trade visible duplication for invisible conditionals. The nested cond→case→case encodes real resolution states (real vs hidden-duplicate vs stale) with `Repo.rollback` exits — a `with`-flattening does not survive the rollback branches cleanly.
- **`disable_*!`/`delete_*!` light/group twins** — differ in cascade sets (lights also clear `SceneComponentLight`); left as-is deliberately.
- **`|> Kernel.||([])` in pipelines** (47 sites across lib) — accepted pipeline idiom here; consistent with the DM5 refutation (style-only, out of scope). Do not re-flag.
- **`validate_resolution_targets!` external-id staleness checks** — load-bearing safety against stale plans; keep exactly as-is.
- **`base_normalized` writing both `external_spaces` and `areas`** — schema-version compatibility aliasing, deliberate.
