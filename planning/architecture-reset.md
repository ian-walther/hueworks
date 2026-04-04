# Architecture Reset

## Goal
Use future refactors to move HueWorks back toward a stricter control pipeline:

1. upstream inputs decide target state
2. target state is committed into `DesiredState`
3. planner/executor own hardware-facing behavior
4. observed physical state is compared against desired state for convergence

All future architecture work in this area should reinforce that pipeline rather than adding new parallel control paths.

## Non-Negotiable Rules
### `DesiredState` Is The Only Mutable Control Target
Future work should not introduce:

- a second runtime target plane
- a manual-control shadow target model
- long-lived runtime overlays that bypass desired-state commits

If higher-level features need extra semantics, they should compile down into desired-state transactions.

### Upstream Code Decides Semantics, Not Hardware Behavior
Upstream layers may decide:

- scene intent
- circadian intent
- manual-control eligibility
- no-scene manual baseline behavior
- active-scene manual power retention

Upstream layers should not own:

- retry loops
- bridge partitioning
- convergence timing
- partial-success recovery
- dispatch sequencing

### Planner/Executor Own Hardware Decisions
Future lower-level work should continue pushing hardware-facing concerns into planner/executor:

- group-vs-light optimization
- bridge partitioning
- dispatch ordering
- retries
- convergence checks
- mixed-bridge recovery
- apply lineage / causality if added later

### Physical State Is Observation
Observed state should stay an observation layer.

It should answer:

- what the devices appear to be doing
- whether that matches desired state
- whether convergence has happened

It should not automatically rewrite scene/manual intent or become a second control source.

## Semantics To Preserve
These behaviors should remain true while refactoring internals.

### Active Scene Manual Rules
While a scene is active:

- manual `power` changes are allowed
- manual `brightness` changes are blocked
- manual `kelvin` / temperature changes are blocked
- manual `on` should restore the light to the current scene-component state
- manual `off` should stay sticky within the same active scene
- scene change or scene deactivation clears old manual power retention

### No-Scene Manual Rules
When no scene is active:

- manual `on` should use the centralized fallback baseline
- manual brightness and temperature changes are allowed

### Manual Entry Points Stay Equivalent
Different manual inputs should keep sharing the same upstream path:

- UI manual controls
- Pico-triggered controls
- future external manual triggers

They may differ in target selection and ergonomics, but not in downstream control semantics.

### Groups Stay Optimization Units
Future work should preserve this model:

- groups are optimization units for commands
- member lights are the source of truth for observation
- group UI is a projection from member lights

## Main Workstreams
### 1. Keep Shrinking Upstream Operational Behavior
Continue removing lower-level operational behavior from upstream modules where the behavior is really hardware-facing.

Main targets:

- `/Users/ianwalther/code/hueworks/lib/hueworks/scenes.ex`
- `/Users/ianwalther/code/hueworks/lib/hueworks/lights/manual_control.ex`
- `/Users/ianwalther/code/hueworks/lib/hueworks/active_scenes.ex`

Future work should prefer:

- upstream code computing desired-state transactions
- shared lower apply paths handling planning and execution

### 2. Keep Scene Semantics Explicit Above Planner/Executor
Do not over-correct by pushing scene semantics downward.

These belong above planner/executor:

- scene materialization
- active-scene recomputation for a subset of lights
- manual power retention within an active scene
- no-scene manual baseline semantics

Likely continuing API shape:

- `Scenes.apply_scene/2`
- `Scenes.recompute_active_scene_lights/3`
- `Scenes.recompute_active_circadian_lights/3`

Future cleanup here should make those APIs clearer, not erase the scene boundary.

### 3. Strengthen Lower-Level Convergence
Continue improving convergence where it belongs: below the desired-state commit.

Future work should focus on:

- better bounded retries
- better mixed-bridge recovery
- clearer stale-subset recovery
- stronger convergence criteria
- explicit apply lineage if needed

This is the primary place to investigate any remaining “manual control is slightly less reliable than scene activation” issues.

### 4. Move Debugging And Tracing Downward
Tracing should be:

- universal
- env-gated
- planner/executor-centric

Future work should keep reducing caller-driven tracing seams and prefer:

- generic planner traces
- generic executor dispatch traces
- generic convergence/recovery traces

The goal is to debug real control issues without requiring upstream layers to customize the lower pipeline.

### 5. Separate Planner Logic From Data Loading
The planner still mixes computation with room/topology loading.

Future work should continue toward:

- one layer loads room/topology/snapshot data
- planner becomes more purely:
  - snapshot + desired diff -> actions

That is mainly an architecture/testability cleanup, but it also makes debugging easier.

### 6. Build A Device-Profile Boundary
Continue the lower-level circadian cleanup by pushing source/device-specific semantics into a clearer profile boundary.

Future profile responsibilities should include:

- projecting logical intent into controllable intent
- encoding bridge/device commands
- decoding raw events into canonical observation
- practical equivalence between desired and observed state

That is the best long-term place for:

- Hue floor clamping
- brightness tolerance
- non-temperature light handling
- low-end Z2M warm-white behavior
- Z2M crossover interpretation in the `2600-2700K` band

### 7. Keep UI Out Of Semantic Correction
Future UI work should continue pushing semantic interpretation downward.

UI should mostly:

- render current state
- collect user intent
- dispatch actions

UI should not keep accumulating:

- semantic correction
- device-specific workarounds
- scene-lifecycle policy

## Technical Focus Areas
### Planner / Executor Debugging
For any remaining mixed-bridge reliability bug, the first debugging pass should capture:

1. the committed desired-state diff
2. the planner output
3. dispatch start/end per action
4. first observed updates per affected light
5. convergence retries and their timing
6. whether the wrong subset was retried, or retried too early, or not retried at all

This should be done as close to planner/executor as possible.

### Apply Lineage
Apply revisions or similar lineage tracking are still a good future direction if needed.

If implemented, they should be used for:

- causality between dispatch and observation
- bounded convergence decisions
- clearer recovery logic

They should not become a second target model.

### Lower-Level Complexity Hotspots
The biggest remaining complexity multipliers worth simplifying over time are:

- low-end extended kelvin support below `2700K`
- default-off scene lights that can later be manually turned on
- mixed-bridge convergence timing
- canonical observation of Z2M warm-white crossover behavior

## Testing And Rollout Rules
### Preserve Existing Public APIs Where Reasonable
Prefer changing internals beneath stable surfaces such as:

- `/Users/ianwalther/code/hueworks/lib/hueworks/scenes.ex`
- `/Users/ianwalther/code/hueworks/lib/hueworks/lights/manual_control.ex`

This keeps the existing suite valuable while architecture shifts.

### Reconsider Test Level When Needed
If a test breaks for an expected architectural reason, first ask whether the assertion belongs:

- higher
- lower
- or on a different public surface

Do not preserve old behavior just to satisfy the old boundary.

### Prefer Narrow, Evidence-Backed Changes
Future work should keep favoring:

- small structural simplifications
- lower-level convergence improvements
- targeted removals of stale concepts

over large speculative new layers.

### Validate In Production-Like Reality
Mixed-bridge manual behavior still needs real-world validation.

Unit and integration tests matter, but the app controls real rooms now, so production behavior should keep informing architecture decisions.

## Near-Term Tasks
1. Continue separating planner computation from room/topology loading.
2. Keep lowering generic tracing into planner/executor.
3. Investigate remaining mixed-bridge manual-control misses through planner/executor traces before adding any new upstream control concepts.
4. Continue building a clearer device-profile boundary for Hue and Z2M semantics.

## Open Questions
1. How far should planner separation from room/topology loading go before the cleanup stops paying for itself?
2. How much explicit apply-lineage state are we willing to carry if it materially improves mixed-bridge convergence debugging?
3. Is the current exact low-end Z2M warm-white behavior worth its ongoing maintenance cost, or should it be narrowed if the profile boundary still feels too expensive?
