# Audit Chunk 2: State Ingestion

Scope: `lib/hueworks/subscription/**` (parsers, mappers, readiness) and `lib/hueworks_app/subscription/**` (per-bridge connection processes, `GenericEventStream`).
Status: audit complete; **no open findings** (IDs SI-1 through SI-8 were all implemented and removed per the forward-facing rule).

Overall assessment: the supervision design is good — `GenericEventStream` monitors each per-bridge connection, restarts with delay, and defers startup until the bridges table exists, so individual stream crashes are self-healing. All four streams share the reference behaviors (deferred non-blocking connect, staleness-triggered index refresh, desired-state-aware group fan-out), and LEAP transport plumbing is consolidated in `Hueworks.Control.CasetaLeap`. Perf note preserved from SI-3: Caseta still opens a fresh TLS handshake per command — if Caseta responsiveness ever becomes a product complaint, a persistent LEAP connection process belongs behind `CasetaLeap`; don't build it speculatively.

## Test-Gap Notes (cross-reference for planning/test-coverage-audit.md)

- Coverage here is genuinely good: every stream has a connection-level suite (staleness refresh, deferred connect, crash isolation), plus Hue parser/mapper suites and a `CasetaLeap` suite. Explicitly leave the parser suite alone.
- Two small gaps remain (Hue `maybe_refresh_indexes` direct case; `GenericEventStream` restart/readiness test) — tracked as CC-5 in `07-cross-cutting.md`.

## Parked

The Readiness boot-ordering question is consolidated as CC-6 in `07-cross-cutting.md`.
