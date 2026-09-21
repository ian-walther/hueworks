# Post-Import Runtime Refresh

## Boundary And Ownership

`Hueworks.Import.apply_review/4` owns the transaction for both initial import and
manual reimport. After commit it emits `{:bridge_import_applied, bridge_id}` on
the domain-events topic. A failed or rolled-back review emits no refresh event.
Calling this workflow inside another transaction returns
`{:error, :nested_import_transaction}` rather than publishing before that caller
has committed. Lower-level materialization helpers are not runtime entry points.

`Hueworks.Control.ImportRefresh` handles the event independently of the importing
LiveView. Navigating away does not cancel refresh, and an unavailable bridge does
not make a committed import fail. `BridgeRefresh` reloads the bridge from the
database, refreshes its connection indexes, then reads physical observations.

The refresh does not alter desired state, issue lighting control commands,
reactivate scenes, or claim a light has converged without an observation. Group
reports do not become invented individual-light readings. Ordinary `control_state`
notifications update existing UI and export consumers; API readers see the same
state store. A newly imported light's **actual** state may differ from the active
scene until the normal control pipeline applies intent.

## Transport Behavior

- Hue reloads source-ID and group-membership maps in the existing SSE connection,
  then reads individual `/lights` and aggregate `/groups` snapshots.
- Home Assistant acknowledges an in-place websocket index refresh, preserving its
  authentication and subscription state, then reads `/api/states`.
- Caseta reloads zone and Pico indexes, subscribes newly discovered buttons, and
  reads `/zone/status` over a short-lived LEAP connection.
- Z2M replaces only the affected supervised MQTT client, retaining its client ID.
  Replacement waits for Tortoise's old handler subtree to stop so the library
  cannot reuse stale indexes. A task-owned temporary MQTT supervisor handles
  read-only `/get` hydration and is torn down on completion, error, or task exit.

Snapshot requests capture opaque observation versions before I/O. State accepts
their results only if no newer observation has arrived for that entity. The
compare-and-write is serialized in the State server and does not depend on wall
clock precision. Superseded snapshots publish nothing and do not overwrite live
stream updates. Empty/unrecognized payloads do not count as physical observations.

## Scheduling And Recovery

One refresh task runs per bridge; different bridges can refresh concurrently.
Imports arriving during a refresh coalesce into a follow-up pass over the newest
database model. A new import cancels a pending retry and requests a fresh pass.

Tasks have a 30-second deadline. Failures retry with exponential delays from one
second up to 30 seconds, with no change to the applied import status. A task crash
does not crash the coordinator. The coordinator and its task supervisor share a
`one_for_all` subtree so a coordinator restart cannot leave competing orphan tasks.
On startup/restart, enabled bridges whose initial import is complete are refreshed
from the committed database, recovering missed notifications without an outbox or
replaying configuration changes. Normal cold-start state bootstrap may overlap;
the observation-version guard also protects those reads.

Deleted or disabled bridges are skipped. `HUEWORKS_RUNTIME_IO_DISABLED` omits the
automatic worker and prevents ad hoc refresh and hydration from contacting bridges.
Tests disable automatic startup with `:import_refresh_enabled` and explicitly
start supervised workers against controlled transports when needed.

## Diagnostics

From an attached release console:

```elixir
Hueworks.Control.ImportRefresh.status(bridge_id)
```

The status is `nil` before a bridge has been processed, or a map with `state`,
`attempt`, `error`, and `updated_at`. States are `:refreshing`, `:ready`, `:retrying`,
`:skipped`, and `:disabled`. This status is ephemeral, not an import audit record.
`:ready` means the transport refresh completed, not that all hardware matches
desired intent or that unreachable devices supplied readings.

Subscribers to `"bridge_runtime_refresh"` receive
`{:bridge_runtime_refresh, bridge_id, status}`. Retry warnings include the bridge
ID, attempt, bounded error category, and delay, never credentials or response bodies.
An explicit retry can use the same domain event:

```elixir
Hueworks.DomainEvents.bridge_import_applied(bridge_id)
```

## Validation

Regression coverage exercises the public initial-import/reimport boundary,
rollback, identity changes, live group membership, API/state publication, preserved
intent, planner no-op after hydration, all four transports, stale snapshot races,
I/O-disabled mode, coalescing, retry, task timeout, shutdown, and restart recovery.
A loopback MQTT broker exercises real Tortoise connection replacement and event
delivery, including a deliberately slow old handler subtree.

Real-house acceptance remains in the
[hardware checklist](../planning/post-import-runtime-refresh.md). It is not
substituted by mocked snapshots or the loopback broker.
