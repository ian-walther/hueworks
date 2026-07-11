# Audit Chunk 10: Kelvin Round-Trip Parity

Scope: Kelvin/device-profile conversion math, extended-range crossover and inverse behavior, outbound control encoding, simulated device reports, and inbound Z2M parsing.
Status: complete. The real HA and Z2M control encoders now round-trip through simulated authoritative reports over default and custom extended profiles. Both direct-Kelvin and mired report shapes are checked within one mired step.

## Sub-Area Tracker

| Area | Status |
|------|--------|
| Map control and report conversion entry points | complete |
| Define device-profile boundary/crossover sample matrix | complete |
| Add deterministic round-trip/property-style coverage | complete |
| Investigate and fix any red cases | complete |

## Required Evidence

For every supported profile and representative points on both sides of each crossover, encode a requested color temperature through the real control path, transform it into the report shape the device emits, parse it through the real ingestion boundary, and assert the recovered logical value is idempotent within an explicit tolerance. Boundary-adjacent, reported-floor, maximum-range, and inverse-extended-XY cases must be named in failures.

## Current Invariant

`test/hueworks/kelvin_round_trip_test.exs` samples the extended minimum, interior low band, both sides of the crossover, normal-white interior, and maximum for two profiles. Low-band commands simulate an authoritative XY report with a stale reported-floor temperature; normal-white commands simulate both supported temperature report shapes.

An explicit `color_temp` mode is the disambiguator at a reported-floor crossover: it denotes a normal-white temperature that must map from reported to actual range. A floor value without that authoritative mode may still be a fallback emitted after an extended-XY command and retains the established floor mapping. Z2M's direct logical low-temperature exception remains outside the reported-floor band.

No `KR-*` findings remain open.
