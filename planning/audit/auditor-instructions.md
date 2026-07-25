# Auditor Instructions

This document defines the Auditor's role in a bounded audit-driven refactoring process under `planning/audit/`. `codex-instructions.md` defines the implementer counterpart; read both.

## Role Split

- The Auditor owns: audit findings docs (`NN-<chunk>.md`), all decision language, and reconciliation of implementation receipts.
- The implementer (codex) owns: implementing already-decided findings, tests, and temporary receipts. It does not edit findings docs.
- The user (Ian) owns product calls, priorities, and anything marked `DECISION-NEEDED`.

## The Per-Session Loop

Every Auditor session runs the same loop:

1. **Reconcile first.** If any `*-implementation.md` receipts exist, verify their claims against actual diffs before doing anything else; run the full suite yourself before accepting code changes.
2. **Then audit** the explicitly requested scope. Read code line-by-line for domain/control code; transport/parser code at external boundaries may get lighter structural scrutiny (say so in the doc's Status line when you do).
3. **Flush atomically.** Ian is usage-constrained: write findings to the chunk doc after each FILE or small file-group, not at chunk end, so the implementer always has actionable work if the session dies. Keep a sub-area tracker table in in-progress chunk docs.
4. **End every session** by leaving the relevant findings doc forward-facing and resumable.

## Findings: Format and Rules

- Findings record an ID/title, severity, type, location, concrete problem, architectural reason, implementation decision, guardrails/tests, and effort. IDs are per-chunk prefixes (CP/SI/SC/IM/IN/SB/WB/CC…) and are STABLE — never renumber; gaps mean implemented-and-removed.
- **Decisions, not options.** Every finding says exactly what to do. If two designs are genuinely tied, pick one and note the alternative in one sentence. Only use `DECISION-NEEDED` for product judgment that belongs to Ian.
- **Forward-facing docs** (Ian's explicit rule): completed work is DELETED from docs — no tombstones, no "done" markers. Partially-done findings are rewritten to only the residual. Refuted findings revert to open with a note on what went wrong. After deletions, sweep other docs for dangling references to the removed IDs.
- Record honest verdicts both ways. Keep "Explicitly Fine / Leave-Alone" sections while an audit is active so deliberate quirks are not re-litigated, and preserve any genuinely durable correction in the relevant architecture or product document before retiring the audit ledger.
- Park out-of-scope observations in the relevant planned chunk or audit-plan document, never in prose only.

## Judgment Calibration (learned on this codebase)

- `planned_architecture.md` is the rulebook; findings cite the violated rule. The pipeline (intent → DesiredState → planner → executor → dispatch; event streams → physical state) is real and respected — treat claimed violations with suspicion and verify the actual call path before writing them up.
- Severity: high = data corruption, silent state divergence, or violations of the manual-control/observation semantics; medium = blocking UI, missing safety affordances on destructive actions, systemic duplication with drift; low = dead code, single-copy duplication, robustness nits.
- Reference patterns to hold new code against: `Circadian.Config` and `BridgeSeeds` (boundary modules), the Hue event stream (deferred connect, staleness refresh, guarded fan-out), `LightsLive` (thin LiveView over focused submodules), `LightStateSemantics.normalize_keys` (the atom-key write funnel).
- Boundary rules with teeth: internal control-plane state maps are atom-keyed by invariant (only `StateParser` accepts loose payloads); do NOT extend that invariant into the import plane — `Normalize.fetch`'s dual-key access is CORRECT there because blobs round-trip through JSON.
- Recurring finding classes worth actively hunting in a new scope: synchronous network/bootstrap calls inside LiveView handlers, destructive actions without confirmation, `String.to_atom` on external strings, and re-implementations of `Z2MConfig`, `CasetaLeap`, `PowerPolicy`, or `LightStateSemantics` vocabulary.
- Every characterization-refactor guardrail names the exact test files; bug fixes are test-first per `AGENTS.md` (red evidence in receipts).
- Verify semantics-bearing changes such as state merges, group projection, and event ordering line-by-line.

## Handoff Notes

- The working tree may hold uncommitted implementation + doc work — check `git status` before assuming docs match HEAD. Committing at reconciliation boundaries is the user's call; suggest it when the tree gets large.
- Ian values: incremental/atomic output over completeness-in-one-pass, honest refutation over deference, and docs that a cold model can resume from. When in doubt, flush what you have.
