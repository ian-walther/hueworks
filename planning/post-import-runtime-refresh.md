# Post-Import Runtime Refresh

## Problem
Applying an initial import or reimport commits new lights, groups, and group membership to the database, but the running control plane may still reflect the pre-import entity set.

Two runtime caches are affected:
- `Hueworks.Control.State` may have no physical observation for a new entity, or may retain an observation captured before the import was fully applied.
- Bridge event-stream connections cache source-ID indexes and group membership maps when they start. Those maps are not explicitly refreshed after import materialization.

The Hue event stream can eventually notice an unknown individual-light event and rebuild its indexes. That is not a sufficient synchronization contract. A Hue group command may produce a current `grouped_light` event without producing an individual event that forces every newly imported member into the connection's cache.

## User-Visible Failure
A newly imported light can show a different brightness or color temperature from the other members of its group even when:
- HueWorks desired state is identical for every member.
- The bridge reports the group at the intended state.
- The physical lights are actually synchronized.

The stale member observation is not only cosmetic. Convergence can compare the current group intent against stale member observations, conclude that the group has not settled, and repeatedly dispatch an already-satisfied group command. Circadian recomputation can therefore create unnecessary bridge traffic on every tick.

## Desired Contract
After an import or reimport transaction commits successfully, the affected bridge must reconcile its runtime state with the newly committed database model.

The post-commit refresh must:
- Load physical observations for newly imported or identity-refreshed entities.
- Rebuild source-ID indexes used by the affected bridge event-stream connection.
- Rebuild cached group-to-light membership used by event handling.
- Publish normal physical-state updates so connected LiveViews and exports receive current observations.
- Leave desired state unchanged.
- Avoid sending control commands merely to populate physical state.
- Preserve the rule that aggregate group observations do not fabricate individual member observations.

Runtime refresh belongs outside the database transaction. A committed import must not be rolled back because a bridge is temporarily unavailable after commit.

## Architectural Direction
Use an explicit post-commit runtime reconciliation boundary rather than having import materialization directly manipulate supervised processes.

The implementation should preserve the runtime/domain split:
- Import and materialization code commits the durable model and emits or returns enough information to identify affected bridges and entity topology.
- Supervised runtime infrastructure performs the physical-state bootstrap and event-stream cache refresh.
- Refresh failures are observable and retryable without changing the applied import status.

Prefer a bridge-scoped refresh. A full application-wide state bootstrap is an acceptable fallback, but it should not become the only available synchronization primitive if a targeted design is straightforward.

The event-stream refresh needs an explicit API or message. Waiting for an unknown future event is not synchronization. Restarting the affected connection is acceptable if it is the cleanest way to rebuild all of its indexes, provided the restart is supervised and does not create duplicate connections.

## Guardrails
- Do not copy a `grouped_light` observation into individual member state.
- Do not optimistically mark imported lights converged without a bridge observation.
- Do not issue scene or light commands as part of runtime hydration.
- Do not put runtime process calls inside the import database transaction.
- Do not make a successful import appear failed solely because post-commit hydration is delayed.
- Do not require an application restart after import or reimport.
- Do not weaken convergence checks to hide stale observations.

## Test Plan
Reproduce the bug with failing tests before implementing the fix.

Required coverage:
- Apply an initial Hue import while the Hue event stream is already running, then verify a newly imported light receives a current physical observation without restarting the application.
- Apply a reimport that adds lights to an existing Hue group, then verify the event-stream source indexes and group membership maps include the new rows.
- Start with stale observations for newly imported group members while the physical bridge already matches desired state, run post-commit reconciliation, and verify the next planner pass emits no control action.
- Verify a current `grouped_light` event alone does not overwrite individual member observations.
- Verify a later individual-light event is mapped correctly after runtime reconciliation.
- Verify LiveView/API readers receive the refreshed physical values through the normal control-state publication path.
- Verify a bridge refresh failure leaves the database import applied and produces observable retry/error evidence.
- Verify runtime-I/O-disabled tests do not perform bridge network calls.
- Cover initial import and manual reimport through their public workflow boundaries rather than relying only on private function signatures.

## Operational Acceptance
Validate the completed behavior against a production-shaped database and real Hue hardware:
- Import a new light into an existing bridge group while an area scene is active.
- Confirm the new light, existing members, and bridge group report the same physical state in HueWorks without restarting the container.
- Confirm Home Assistant and HueWorks agree on brightness and color temperature.
- Observe at least two circadian ticks and confirm no convergence retries or duplicate group dispatches occur when the hardware already matches intent.
- Confirm normal individual light changes continue to update both member and derived group state afterward.
