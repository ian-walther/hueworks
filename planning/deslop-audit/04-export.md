# Chunk 4 — Home Assistant Export

Status: CLOSED. EX1-EX6 implemented and reconciled. No open findings. (`Export.Runtime` was deleted; its helpers live in `Export.Config`.)

## Explicitly Fine / Leave-Alone

- **`Publisher` publish/unpublish pair fan-out** — each pair writes different topic/payload sets; the repetition is the MQTT discovery protocol, not slop.
- **`Sync` facade** — the single entry surface for lifecycle dispatch; its one-line delegations earn their keep as the seam between lifecycle messages and per-domain sync modules (the `apply/3` indirection that once sat above it was removed by EX2).
- **`Messages.*` payload builders** — verbose by protocol necessity; `fetch_state_value` re-normalization is cheap boundary paranoia on values that cross into MQTT JSON.
- **`Handler`, `Connection` error handling, `TokenProvider` rescue** — real IO boundaries with injectable test seams that tests use.
- **`export.ex` struct-or-id double heads** (`refresh_light(%Light{id: id})` + `refresh_light(id)`) — genuine caller convenience, both forms used.
