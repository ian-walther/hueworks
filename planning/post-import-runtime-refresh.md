# Post-Import Runtime Refresh: Hardware Acceptance

Remaining validation requires real bridges and a production-shaped database. The
implementation contract and diagnostics are in
[the runtime refresh guide](../docs/post-import-runtime-refresh.md).

Do not deploy or change household lighting just to complete this checklist while
the operator is away. No database migration is required for this feature.

## Hue Acceptance

- Take the normal pre-deploy database backup and record the deployed revision.
- Import a new light into an existing bridge group while an area scene is active.
- Confirm the new light, existing members, and bridge group report current physical
  brightness and color temperature without restarting the container. A refresh
  reads the bridge; it does not apply the scene to a newly added light by itself.
- Confirm Home Assistant and HueWorks agree on brightness and color temperature.
- Observe at least two circadian ticks and confirm no convergence retries or
  duplicate group dispatches occur when the hardware already matches intent.
- Confirm individual light changes still update member and derived group state.
- Reimport an existing bridge and confirm no desired state, scene, Pico config,
  area placement, or export identity changes merely because runtime refresh ran.

## Other Transports And Recovery

- Verify HA, Caseta, and Z2M imports update live observations without an application
  restart. For Caseta, also verify newly imported Pico buttons receive events.
- Verify Z2M reconnects only the affected client and does not accumulate duplicate
  connections or leave temporary bootstrap clients behind.
- With a bridge temporarily unavailable, verify the import remains applied,
  diagnostics report retries, and observations recover once it is available.
- Verify an off light stays reported off, with its last known levels preserved.
- If rollback is needed, redeploy the prior code revision without reverting the
  database. Imports already applied remain durable configuration; rolling back
  this feature does not undo them.
