# Auditor Instructions

This document defines the Auditor's role in the audit-driven refactoring process under `planning/audit/`. The role was held by Claude (Fable) through chunks 1–6b; any capable model (e.g. GPT Sol) can assume it from here. `codex-instructions.md` defines the implementer counterpart — read both.

## Role Split

- The Auditor owns: audit findings docs (`NN-<chunk>.md`), the ledger/session log in `00-plan.md`, all decision language, and reconciliation of implementation receipts.
- The implementer (codex) owns: implementing already-decided findings, tests, and temporary receipts. It does not edit findings docs.
- The user (Ian) owns product calls, priorities, and anything marked `DECISION-NEEDED`.

## The Per-Session Loop

Every Auditor session runs the same loop:

1. **Reconcile first.** If any `*-implementation.md` receipts exist, run the Implementation Reconciliation Protocol in `00-plan.md` before doing anything else. Non-negotiable parts: verify claims against actual `git diff`s (receipts have been stale once — SI-3 landed unlisted with a wrong test count); run the FULL suite yourself; if 1–2 tests fail, rerun before suspecting the change (known intermittent SQLite "Database busy" flake, see `07-cross-cutting.md`).
2. **Then audit** the next chunk per the ledger. Read code line-by-line for domain/control code; transport/parser code at external boundaries may get lighter structural scrutiny (say so in the doc's Status line when you do).
3. **Flush atomically.** Ian is usage-constrained: write findings to the chunk doc after each FILE or small file-group, not at chunk end, so the implementer always has actionable work if the session dies. Keep a sub-area tracker table in in-progress chunk docs.
4. **End every session** by updating the ledger + one session-log row in `00-plan.md`.

## Findings: Format and Rules

- Use the finding format in `00-plan.md`. IDs are per-chunk prefixes (CP/SI/SC/IM/IN/SB/WB/CC…) and are STABLE — never renumber; gaps mean implemented-and-removed.
- **Decisions, not options.** Every finding says exactly what to do. If two designs are genuinely tied, pick one and note the alternative in one sentence. Only use `DECISION-NEEDED` for product judgment that belongs to Ian.
- **Forward-facing docs** (Ian's explicit rule): completed work is DELETED from docs — no tombstones, no "done" markers. Partially-done findings are rewritten to only the residual. Refuted findings revert to open with a note on what went wrong. After deletions, sweep other docs for dangling references to the removed IDs.
- Record honest verdicts both ways: keep "Explicitly Fine / Leave-Alone" sections so future passes don't re-litigate deliberate quirks, and record refutations permanently (see the IM-2 display_name correction in `04-import.md` — the implementer was right and the audit was wrong; that is a healthy outcome, credit it).
- Park out-of-scope observations in the target chunk's doc (or `07-cross-cutting.md`), never in prose only.

## Judgment Calibration (learned on this codebase)

- `planned_architecture.md` is the rulebook; findings cite the violated rule. The pipeline (intent → DesiredState → planner → executor → dispatch; event streams → physical state) is real and respected — treat claimed violations with suspicion and verify the actual call path before writing them up.
- Severity: high = data corruption, silent state divergence, or violations of the manual-control/observation semantics; medium = blocking UI, missing safety affordances on destructive actions, systemic duplication with drift; low = dead code, single-copy duplication, robustness nits.
- Reference patterns to hold new code against: `Circadian.Config` and `BridgeSeeds` (boundary modules), the Hue event stream (deferred connect, staleness refresh, guarded fan-out), `LightsLive` (thin LiveView over focused submodules), `LightStateSemantics.normalize_keys` (the atom-key write funnel).
- Boundary rules with teeth: internal control-plane state maps are atom-keyed by invariant (only `StateParser` accepts loose payloads); do NOT extend that invariant into the import plane — `Normalize.fetch`'s dual-key access is CORRECT there because blobs round-trip through JSON.
- Recurring finding classes worth actively hunting in remaining chunks: synchronous network/bootstrap calls inside LiveView handlers (WB-1/WB-12 class), destructive actions without confirmation (WB-10/WB-15 class), `String.to_atom` on external strings (IM-3/WB-14 class — reuse `Import.Source.normalize/1`), re-implementations of `Z2MConfig`/`CasetaLeap`/`PowerPolicy`/`LightStateSemantics` vocabulary.
- Every characterization-refactor guardrail names the exact test files; bug fixes are test-first per `AGENTS.md` (red evidence in receipts).
- Codex's track record across 9 passes: consistently faithful, occasionally better than spec (pure helpers, request-id guards); its one real deviation was CORRECT (IM-2 refutation). Trust it with M-effort extractions; verify semantics-bearing changes (state merges, group projection, event ordering) line-by-line.

## Audit Status (as of 2026-07-11)

The whole-code audit, architectural distillation, and audit-directed implementation backlog are complete. No findings remain open. Future Auditor work requires a new user request, an implementation receipt, or concrete evidence that invalidates the distillation; do not start another broad audit by default.

## Handoff Notes

- The working tree may hold uncommitted implementation + doc work — check `git status` before assuming docs match HEAD. Committing at reconciliation boundaries is the user's call; suggest it when the tree gets large.
- `codex-instructions.md` says receipts are reconciled by "Fable" — read that as "the Auditor."
- Ian values: incremental/atomic output over completeness-in-one-pass, honest refutation over deference, and docs that a cold model can resume from. When in doubt, flush what you have.
