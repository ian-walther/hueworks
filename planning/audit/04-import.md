# Audit Chunk 4: Import & Persistence

Scope: `lib/hueworks/import/**`, `lib/hueworks/bridges.ex`, `lib/hueworks/bridge_seeds.ex`. Import-owned schemas were read as encountered.
Status: audit complete; **no open findings** (IDs IM-1 through IM-8 were all implemented and removed per the forward-facing rule; the IM-2 display_name divergence sub-claim was refuted during implementation — see correction below).

Overall assessment: the reimport backend implements the reimport product contract (now `planning/import-resync.md`, rewritten as the review-UI plan) with real care — field ownership respected on refresh, staleness validation enforced for destructive resolutions, rollback on duplicate-classification drift, post-commit-only integration effects — and `ReimportApply` now has a 12-case characterization suite covering the full contract matrix. Shared construction lives in `Import.EntityAttrs`/`Import.Areas`/`Import.IdentifierIndex`/`Import.Source`; fetch transports consume `CasetaLeap`/`Z2MConfig`.

## Audit Correction (recorded so it isn't re-found)

The original IM-2 finding claimed initial import and reimport diverged on `display_name` (initial leaving it unset so bridge renames flow through). **That was wrong**: `Light`/`Group` changesets force `display_name` to default to `name` at insert (`put_default_display_name` + `validate_required`), a migration backfills blanks, and import-resync.md documents the contract — `name` is the bridge-owned cache, `display_name` is the HueWorks-owned label, set once at insert and never touched by refresh. Both import paths already agreed. The implementer correctly refused the audit-directed change and added characterization for the real contract instead.

## Leave-Alone Notes (checked, intentional)

- `BridgeSeeds` — clean boundary module (explicit shape validation, whitelisted types, good errors). Reference example alongside `Circadian.Config`.
- `Bridges` — delete paths clean up references in the right order and defer export removals to post-commit.
- The four `normalize/*` modules — complexity is real upstream mess; loose `Normalize.fetch` dual-key access is correct HERE (blobs round-trip through JSON). Do not extend the control plane's atom-key invariant into the import plane.
- `Fetch.Common.invalid_credential?/1` stays — Hue and HA import fetchers still use it.

## Parked

Formerly-parked items (warnings pass, dual-key sweep, exports/ fixtures, bridge_host metadata) are consolidated as CC-2/CC-3/CC-4 in `07-cross-cutting.md`.
