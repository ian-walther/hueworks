# HueWorks TODO

Forward-looking backlog only. Completed work has been removed.

This file should stay short. If a future idea is not likely to be acted on soon, leave it out until it becomes real planning work.

## Now

### Reimport Review UX
Reference: `planning/import-resync.md`

- [ ] Replace the remaining new-entity checkboxes with explicit `Do Not Import` / `Import` controls and show current HueWorks versus bridge values where a decision is required.
- [ ] Show collapsed, inspectable bridge-owned auto-refresh details plus summary counts for unchanged, auto-refreshed, and membership-warning items without presenting them as decisions.

### Transition Hardware Validation

- [ ] Smoke-test a multi-minute scene activation on both Hue and Zigbee2MQTT, verifying that neither convergence nor circadian adaptation interrupts the fade.

### HomeKit Control Quality
Reference: `planning/homekit-control-quality.md`

- [ ] Improve HomeKit behavior beyond reliable on/off control.
- [ ] Define the expected user experience for brightness/color control when no HueWorks scene is active.
