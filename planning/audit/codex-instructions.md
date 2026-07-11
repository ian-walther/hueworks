# Codex Implementation Instructions

This document defines Codex's role in the audit-driven refactoring process under `planning/audit/`.
It is forward-looking process documentation, not a progress log.

## Role Split

- The Auditor owns the audit findings docs (`NN-<chunk>.md`) and decision language.
- Codex owns implementation of already-decided findings, tests, and temporary implementation receipts.
- The user owns product calls, priority calls, and any decision marked `DECISION-NEEDED`.
- Codex should not edit Auditor-owned findings docs during a normal audit-driven loop unless explicitly asked. Instead, document implementation evidence in a temporary receipt and let the Auditor reconcile.

## Cold Start Checklist

When asked to resume implementation, do this first:

1. Read `AGENTS.md`.
2. Read `planned_architecture.md`.
3. Read the relevant chunk findings docs under `planning/audit/`.
4. Check `git status --short --branch`.
5. Identify uncommitted changes that may belong to the user, the Auditor, or a prior Codex pass. Do not overwrite or revert them unless explicitly asked.
6. If any `*-implementation.md` receipts already exist, read them before starting new implementation work.

## Picking Work

Prefer findings that are already fully decided and locally testable.

Good Codex targets:

- Small or medium bug-risk findings with clear guardrails.
- Refactors with explicit target shape and existing characterization tests.
- Clusters that the audit explicitly says should land together.
- Residual cleanup where the product behavior is unchanged and the audit decision is unambiguous.

Avoid or pause on:

- `DECISION-NEEDED` findings.
- Findings where code reality contradicts the audit decision.
- Broad refactors whose dependency order is unclear.
- Anything that would require choosing product behavior not already specified.
- Anything that risks live production data or deployment state unless the user explicitly asks for deployment work.

## Implementation Rules

- Implement the audit decision; do not re-audit or redesign it by default.
- Keep scope tight. Do not opportunistically sweep nearby issues unless the audit explicitly groups them.
- Preserve the architecture pipeline from `planned_architecture.md`: upstream intent -> `DesiredState` -> planner -> executor -> bridge dispatch -> event-stream observation.
- Normalize at boundaries rather than spreading atom/string or transport-specific tolerance deeper into domain code.
- Prefer pure shared helpers when extracting duplicated semantics. Avoid making low-level semantic helpers call GenServers or the Repo unless the existing architecture clearly requires it.
- Treat explicit opt-in behavior differently from dangerous defaults. Safer defaults can change while explicit escape hatches may remain if tests or the audit require them.
- Preserve public behavior unless the finding explicitly calls for behavior change.
- Never use worktree isolation for subagents or implementation work.

## Test Discipline

- For bug fixes and regressions, first add or identify a failing test and confirm it fails.
- For refactors, add characterization tests first when the audit guardrails call for them or when behavior is not already covered.
- After the fix/refactor, rerun the focused test or focused suite that proved the change.
- Run `mix test` before declaring code-change work complete.
- For docs-only changes, do not run tests unless the user explicitly asks or the doc contains executable examples that should be verified.
- If a full-suite failure appears unrelated, investigate enough to distinguish pre-existing flake from introduced failure before closing out.

## Temporary Implementation Receipts

After implementing any audit finding, create or update a short-lived receipt next to the source findings doc:

`planning/audit/NN-<chunk>-implementation.md`

Use this shape:

```md
# <Chunk Name> Implementation Notes

Temporary reconciliation note for `planning/audit/NN-<chunk>.md`.
Delete this file after the audit doc has been updated to remove or revise the completed items below.

## Implemented

- <Finding ID>: <short outcome>.
  - What changed.
  - Tests added or updated.
  - Red/green evidence for bug fixes, when applicable.
  - Focused verification command.

## Not Implemented

- Findings intentionally left open.
- Scope boundaries or deferred follow-ups.

## Auditor Notes

- What the Auditor should verify.
- Any nuance where implementation differs slightly from the original audit wording.
```

Receipts are disposable evidence, not durable planning docs. Once Fable verifies the code and updates the findings docs, the receipt should be deleted.

## Reconciliation Expectations

The Auditor should verify receipts against actual diffs and tests before deleting completed findings. Codex should make that cheap by:

- Listing exact finding IDs.
- Naming exact files and functions when useful.
- Recording focused commands that passed.
- Calling out partial implementations clearly.
- Avoiding vague claims like "cleaned up state code" without concrete evidence.

## Stop Conditions

Pause and ask the user before continuing if:

- The audit finding is contradicted by current code.
- The intended behavior is ambiguous.
- The smallest correct fix requires a product decision.
- A migration, deployment, server change, or production-data action becomes necessary.
- Implementation would require rewriting Fable-owned audit docs instead of adding a receipt.
- Tests reveal a larger architectural problem than the finding described.

## Final Response Checklist

When finishing an implementation pass, report:

- Which finding IDs were implemented.
- Which temporary receipt files were created.
- Which tests were run, including `mix test`.
- Any warnings, residual risks, or findings intentionally left open.

Do not claim Auditor-owned findings are complete; say they are ready for the Auditor to reconcile.
