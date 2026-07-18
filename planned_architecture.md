# Planned Architecture

This document is a set of guiding principles for future agents and maintainers. It is not a backlog and should not be used to track completed work.

When this document and a planning backlog disagree, treat this document as the higher-level architectural rulebook and update the backlog to match.

## Product Direction

- HueWorks is the primary control core for lighting logic and optimization.
- External ecosystems such as Home Assistant and HomeKit are optional integration layers.
- Integrations should enter HueWorks through normal control paths rather than bypassing HueWorks scene, desired-state, planner, or executor semantics.
- For users who operate from Home Assistant or HomeKit, the integrated experience should preserve HueWorks' advantages: optimization, predictability, and explainability.

## Core Control Model

### Desired State Is Intent

Desired state represents what HueWorks wants to be true.

Rules:
- Higher-level features should compile down into desired-state transactions.
- Do not introduce a second long-lived target-state plane.
- Do not let UI, Home Assistant, HomeKit, Pico, or scene code dispatch hardware actions directly when an existing desired-state path can represent the intent.
- Manual-control exceptions should be explicit scene semantics, not hidden alternate state ownership.

### Physical State Is Observation

Physical state represents what bridges report right now.

Rules:
- Treat observed state as delayed, incomplete, and sometimes stale.
- Use observed state for comparison, convergence, UI display, and debugging.
- Do not let observed state silently rewrite scene intent or become a second source of truth.
- When observations conflict with desired state, prefer explicit convergence or deactivation policy over implicit mutation.

### Planner Owns Optimization

The planner turns desired-vs-physical diffs and area topology into bridge actions.

Rules:
- Keep group-vs-light optimization below the desired-state boundary.
- Keep bridge partitioning and capability-aware action selection below the desired-state boundary.
- Do not push Zigbee, Hue, Caseta, Home Assistant, or HomeKit transport quirks into scene or UI code.
- Favor pure planner inputs where practical: snapshot + desired diff + options -> actions.

### Executor Owns Dispatch And Convergence

The executor runs planned actions and handles downstream timing.

Rules:
- Keep queueing, retries, convergence checks, and partial-failure behavior in the executor/control layer.
- Upstream callers may choose intent and enqueue policy, but should not own bridge dispatch sequencing.
- Cross-bridge timing and no-popcorning behavior belongs here, not in scene builders or LiveViews.
- Runtime traces should survive crossing queue/executor boundaries.
- Commit each desired-state transaction atomically. Planned actions must carry the desired-state revisions of the snapshot that produced them.
- Never dispatch an action whose covered desired-state revisions are stale. Replan its covered lights from current desired and physical state so group optimization cannot strand an unchanged member or overwrite a newer intent.
- Track expected bridge settlement only as executor-local, per-light dispatch metadata. It must expire or be superseded, never become persisted desired state or a second target-state model.
- Base convergence eligibility on the effective duration actually encoded by the dispatch boundary, not only the caller's requested transition. Recovery must preserve its original operation policy and avoid groups that include lights owned by newer settlements.

## Agent Rules

### Preserve The Pipeline

Future changes should reinforce this flow:

1. upstream input decides intent
2. intent is committed to `DesiredState`
3. planner computes actions from desired state, physical state, and topology
4. executor dispatches actions and checks convergence
5. bridge event streams update physical state

If a feature feels hard to fit into this pipeline, pause and document the tension before creating a parallel path.

### Normalize At Boundaries

Rules:
- Accept loose maps at external boundaries: HTTP params, MQTT payloads, bridge payloads, JSON columns, and imported blobs.
- Convert bounded internal concepts into structs, embedded schemas, or typed domain helpers as early as practical.
- Do not spread mixed atom/string key handling through downstream domain code.
- If multiple modules parse the same vocabulary, extract a boundary module before adding more branches.

### Context APIs Own Persistence Invariants

Rules:
- Treat UI validation and filtered selectors as affordances, not enforcement.
- Enforce topology and persistence invariants in the owning context path so every caller receives the same validation.
- Route specialized update functions through the same validated mutation path instead of maintaining parallel rule copies.
- Commit multi-row topology changes in one database transaction, then run external integration effects only after a successful commit.

### Areas Own Lighting Coordination

HueWorks Areas are authored lighting coordination boundaries. An Area may represent one physical room, several rooms in an open floor plan, or a larger zone whose lights and scenes should behave together.

Rules:
- Keep Areas flat unless recursive composition is separately designed; do not infer hierarchy from names or source topology.
- Treat source-reported rooms, zones, Floors, and Areas as `ExternalSpace` evidence rather than HueWorks ownership.
- Persist user-reviewed `ExternalSpaceMapping` records separately from source facts. Many external spaces may map to one Area, while one external space maps to at most one Area.
- Use mappings only as placement defaults for newly imported entities. A source rename, hierarchy change, mapping edit, import, or reimport must not silently move existing lights or groups.
- Keep bridge group membership as bridge-owned topology even when it diverges from HueWorks Area placement.

### Persist Published Identity

Externally published identity is durable data, not a formatting function.

Rules:
- Generate an external identity once, store the final published value, and reuse it for the life of the record.
- Renames, terminology changes, source-space remaps, and display-name changes must not regenerate published identity.
- Existing identity strings may retain historical vocabulary as opaque data; do not preserve deprecated routes, APIs, topics, or domain models merely because an old identity contains that vocabulary.
- Missing or duplicate persisted identities are integrity errors. Do not silently repair them during ordinary reads or exports.

### Keep Onboarding State-Derived

Guided setup is an orchestration surface over normal HueWorks configuration, not a second configuration model.

Rules:
- Derive setup progress from committed Areas, bridges, imports, scenes, and integration state wherever possible.
- Persist only the selected setup path and explicit completion or dismissal state.
- Home Assistant-assisted setup may use HA inventory to propose native sources and spatial mappings, but HueWorks remains the owner of Areas, placement, scenes, desired state, and control behavior.
- Inventory Home Assistant before native setup when helpful, but materialize native entities before selected HA-only entities so duplicate linking retains its supported direction.
- Keep direct setup fully supported and allow either path to leave for normal configuration without losing completed work.

### Fan Out Integration Effects After Commit

Rules:
- When one committed domain change has multiple optional integration consumers, publish a domain event instead of making the domain mutation depend directly on every integration.
- Broadcast only after persistence succeeds. Subscriber failure must not turn a committed domain mutation into an apparent rollback.
- Keep subscribers independently restartable and safe to refresh from current domain state.
- Synchronous integration effects are acceptable when ordering is part of the domain contract; keep those exceptions explicit and tested.

### Preserve The Runtime And Domain File Split

Rules:
- Keep supervised runtime processes and infrastructure under `lib/hueworks_app`; keep domain/application APIs and pure transformations under `lib/hueworks`.
- Runtime modules may retain the `Hueworks.*` namespace when they implement domain runtime behavior. Reserve `HueworksApp.*` for infrastructure such as the runtime cache.
- Do not move a module based on namespace alone; placement follows whether it owns supervised runtime state or domain behavior.

### Keep Semantics Above Hardware, Hardware Below Semantics

Rules:
- Scene policy, manual power retention, circadian target selection, and presence-input behavior are semantic concerns.
- Bridge command encoding, retry timing, grouped dispatch, convergence, and device capability quirks are hardware/control concerns.
- Refactors should make this boundary clearer, not simply move complexity around.

### Preserve Manual Control Semantics

Rules:
- While a scene is active, manual `power` changes are allowed, but manual brightness and temperature changes are blocked.
- While a scene is active, manual `on` restores the light to the current scene-component state.
- While a scene is active, manual `off` stays sticky within that active scene.
- Scene changes and scene deactivation clear old manual power retention.
- When no scene is active, manual `on` uses the centralized fallback baseline, and manual brightness/temperature changes are allowed.
- UI controls, Pico controls, Home Assistant, HomeKit, and future manual entry points should share the same semantic path even when their target-selection UX differs.

### Treat Groups As Optimization Projections

Rules:
- Groups are optimization units for command planning and dispatch.
- Member lights are the source of truth for observation.
- Group UI state should be a projection from member-light state unless a bridge-reported group state is explicitly being shown as bridge metadata.
- Do not let group records become a second independent light-state model.

### Keep Device Profiles Below Product Semantics

Rules:
- Source/device-specific behavior belongs behind a profile or lower-level control boundary.
- Device profiles may project logical intent into controllable intent, encode bridge commands, decode raw events, and decide practical desired-vs-observed equivalence.
- Hue floor clamping, brightness tolerance, non-temperature light behavior, low-end Z2M warm-white behavior, and Z2M crossover interpretation should not leak upward into scene or UI code.

### Debug At The Control Boundary

Rules:
- Control tracing should be generic, environment-gated, and planner/executor-centric.
- For mixed-bridge reliability bugs, first capture the desired-state diff, planner output, dispatch timing, observed updates, and convergence retries before adding new upstream control concepts.
- Apply lineage or revision tracking is acceptable if it improves causality and convergence decisions, but it must not become a second target-state model.

### Keep The Deployment Boundary Private

HueWorks is a trusted-LAN appliance, not a public web service. Network reachability is deliberately the authorization boundary.

Rules:
- Do not expose HueWorks to the public Internet under any circumstances. Do not port-forward it, publish it through a public tunnel, or place it on a network reachable by untrusted clients.
- Application authentication is intentionally absent. Every client that can reach the web endpoint is trusted to inspect configuration, control devices, upload credentials, and perform confirmed destructive operations.
- Plain HTTP is supported inside the isolated trusted LAN. `PHX_SCHEME=https` describes a private TLS-terminating reverse proxy when one is used; it does not make HueWorks' listener serve TLS.
- CSRF protection, secure browser headers, and WebSocket origin checks remain required defense in depth, but they are not authentication or substitutes for network isolation.
- Any future remote or public-access use case requires a new, system-wide security design before exposure, including authentication, authorization, TLS, session/cookie policy, secret handling, and abuse controls. Do not evolve into that posture incrementally while the private-appliance assumptions remain active.

### Planning Docs Are Forward-Looking

Rules:
- Use `planning/` docs and `hueworks_todo.md` for future work, open decisions, and remaining risks.
- Remove completed items instead of marking them done.
- Keep progress narratives out of planning docs.
- Keep this file stable as an architecture rulebook rather than an implementation checklist.

### Test The Right Boundary

Rules:
- Prefer changing internals beneath stable public surfaces where that keeps the existing suite valuable.
- If a test breaks for an expected architectural reason, first ask whether the assertion belongs higher, lower, or on a different public surface.
- Prefer narrow, evidence-backed structural changes over broad speculative layers.
- Production behavior should continue informing architecture decisions because the app controls real areas, not just fixtures.

## Relationship To Other Docs

- `/Users/ianwalther/code/hueworks/planning/audit/` contains the completed audit's durable scope conclusions and leave-alone decisions.
- `/Users/ianwalther/code/hueworks/planning/import-resync.md` contains the reimport ownership, safety, and future-extension rules.
- `/Users/ianwalther/code/hueworks/hueworks_todo.md` contains prioritized future work.

If those docs drift from these principles, update the more specific doc first unless the principle itself is intentionally changing.
