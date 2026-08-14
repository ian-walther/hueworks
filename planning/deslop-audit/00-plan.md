# De-slop Audit — Plan & Ledger

A complexity-reduction audit, distinct from the correctness/architecture audits (`planning/audit/`, retired) and the release audit (`planning/release-audit/`, closed). The question this audit asks of every function is: **does this code earn its complexity?** The codebase was built by multiple agents over time; agent-generated code accretes characteristic fat even when correct.

Process rules (roles, per-session loop, forward-facing docs, decisions-not-options, stable IDs) are inherited from `planning/audit/auditor-instructions.md`. Differences specific to this audit are below.

## What counts as slop (finding types)

- **DEF — defensive theater.** Error handling for paths that cannot occur: `case`/`with` clauses matching error shapes no callee returns, rescue around pure code, defaults for always-present values. In Elixir the idiomatic alternative is usually to let it crash. *Every DEF finding must include call-site/callee analysis proving the path unreachable — an aesthetic objection is not a finding.*
- **GEN — speculative generality.** Options never passed, parameters with only one call-site value, behaviours with one impl and no test double, "extensible" dispatch nothing extends.
- **IND — indirection without payoff.** Single-caller private helpers shorter than the context they cost, delegate-only modules, pipeline stages that are identity functions.
- **IDIOM — pattern-matching cosplay.** Multi-clause heads used as decoration rather than dispatch; deep destructuring that forces mental reassembly; `with` for a single fallible op; clause proliferation where one function with a conditional reads better.
- **DUP — agent accretion.** Near-identical branches/functions added side-by-side instead of generalizing; dead remnants of abandoned approaches that still compile.
- **DOC — comment noise.** Doc comments restating signatures, narrating implementation, or justifying changes to a long-gone reviewer.
- **TEST — test slop.** Overbuilt setup helpers, tests asserting unreachable error paths, redundant near-duplicate cases, assertions on incidental structure.

The default fix is **deletion or inlining**. The risk profile is inverted from a correctness audit: the danger is over-deleting a clause that is actually load-bearing for an input source the auditor didn't trace. Hence the proof burden on DEF, and: when a defensive clause guards a true external boundary (network payloads, JSON blobs, MQTT), it is *not* slop — cite the boundary rule from `auditor-instructions.md` (atom-key invariant, `StateParser`/`Normalize.fetch` exceptions) before flagging anything near it.

## Explicitly out of scope

- Correctness bugs found in passing → park in the chunk doc's "Parked (not slop)" section; do not write DEF/IND findings for them.
- Style-only rewrites with no complexity reduction (renames, formatting).
- The `planning/` docs themselves.

## Severity

- **high** — slop that actively misleads: dead code a reader would assume live, defensive clauses that mask real failures (swallow-and-default), duplication already drifted.
- **med** — meaningful reading/maintenance cost: overbuilt functions, unreachable-path handling, delegate layers.
- **low** — local noise: single-caller helpers, comment noise, minor idiom cosplay.

## Chunks

Each chunk covers its lib area **and the tests that exercise it**; TS findings live in the same chunk doc as the code they test. Order chosen so the import plane (uncommitted WIP in working tree) is audited last.

| # | Doc | Scope | Prefix | Status |
|---|-----|-------|--------|--------|
| 1 | `01-control.md` | `lib/hueworks/control/**`, `lib/hueworks_app/control/**` + tests | CT | COMPLETE (implemented + reconciled) |
| 2 | `02-subscription.md` | `lib/hueworks/subscription/**`, `lib/hueworks_app/subscription/**`, `lib/hueworks_app/z2m/**`, `lib/hueworks/mqtt/**` + tests | SU | COMPLETE (implemented + reconciled) |
| 3 | `03-domain.md` | `lib/hueworks/{scenes,lights,groups,picos,circadian,homekit,schemas,app_settings,onboarding}/**`, `api.ex`, top-level `lib/hueworks/*.ex` + tests | DM | CLOSED |
| 4 | `04-export.md` | `lib/hueworks/home_assistant/**`, `lib/hueworks_app/home_assistant/**` + tests | EX | CLOSED |
| 5 | `05-onboarding.md` | `lib/hueworks/bridge_onboarding/**`, `lib/hueworks_app/bridge_onboarding/**`, `lib/hueworks/connection_test/**` + tests | OB | CLOSED (no findings) |
| 6 | `06-web-main.md` | `lib/hueworks_web/live/**` except `config/` + tests | WM | CLOSED |
| 7 | `07-web-config.md` | `lib/hueworks_web/live/config/**` + tests | WC | CLOSED (no chunk-exclusive findings) |
| 8 | `08-web-misc.md` | `lib/hueworks_web/{components,controllers,plugs,api}/**`, remaining `lib/hueworks_web/*.ex`, `lib/mix/tasks/**`, `lib/hueworks_app/{cache,location}/**` + tests | WX | CLOSED (no findings) |
| 9 | `09-import.md` | `lib/hueworks/import/**` + tests | IP | CLOSED |
| 10 | `10-test-infra.md` | Shared test support (`test/support/**`, cross-cutting helpers) | TI | CLOSED (no findings) |

**AUDIT COMPLETE — zero open findings.** All ten chunks audited; all 54 findings (CT1-22, SU1-9, DM1-17, EX1-6, WM1-4, IP1-2) implemented or refuted, reconciled against diffs with the full suite green. The ledger is ready to retire at Ian's discretion; the chunk docs' Leave-Alone sections hold the durable judgments (boundary rules, accepted refutations, deliberately-parallel code) worth preserving if the ledger is ever pruned. New shared vocabulary added during the audit: `Util.{existing_atom,to_float,blank_to_nil,put_unless_nil,changeset_errors}/`, `AppSettings.FieldParser`, `Control.BridgeCredentialsCache`, `Normalize.{resolution_of,entity_source_id}`.

## Judgment calibration for this audit

- A multi-clause head is fine when clauses dispatch on genuinely different shapes from a boundary; it's IDIOM slop when all clauses are internal callers that could pass a normalized shape.
- `{:ok, _}/{:error, _}` tuple returns are fine at fallible boundaries; wrapping infallible pure functions in ok-tuples so callers can `with` them is IDIOM slop.
- Single-caller private functions are fine when they name a genuine concept; IND slop when the name restates the code ("`build_result`", "`maybe_update`" wrappers).
- Test helpers that hide the arrange step of every test behind indirection are TEST slop even when DRY — prefer visible setup over clever fixtures, per existing test style.
