# Pico Support

## Goal
Allow Caseta Pico remotes to act as first-class external inputs for HueWorks so they can trigger the same kinds of actions users can already perform directly in the HueWorks UI.

This should close one of the last major gaps preventing HueWorks from being the full-time main-floor lighting workflow.

## Product Framing
Pico support should be designed as part of the same broad workflow as Home Assistant scene activation:

- these are external inputs
- they should enter the same core scene/control pipeline as direct UI interaction
- they should not invent a parallel control model unless there is a strong reason to do so

The guiding principle should be:

> A Pico button press should feel like a physical shortcut for actions users could already trigger from HueWorks.

That means the implementation should prefer reusing the existing HueWorks action paths rather than creating one-off dispatch behavior for remotes.

## Current Status
The Pico runtime is now working end-to-end for the V1 light-control path:

- separate Pico sync exists
- Pico config is reachable from the Caseta bridge card on `/config`
- discovered Picos and buttons are persisted
- button actions can be learned by physical button press
- Pico-local room-scoped control groups work
- button presses drive the normal HueWorks light-control path

At this point the runtime behavior is in good shape. The remaining work is mostly UI polish and ergonomics rather than core execution correctness.

One especially important implementation detail that fell out during testing:

- toggle decisions must prefer `DesiredState` over raw physical `State`

That turned out to be critical for rapid button sequences and in-progress transitions. Without it, a follow-up Pico press could make the wrong decision because the physical state had not caught up yet. With desired-state-first toggle evaluation, newer button presses can correctly supersede in-flight transitions.

So the current mental model should be:

- Pico button presses express new intent immediately
- desired state is the freshest control truth for toggle evaluation
- physical state is still important, but should be treated as convergence/confirmation rather than the sole source of truth during rapid interaction

## Locked Decisions
- Pico configuration should have a dedicated entry point from the Caseta bridge card on `/config`.
- Pico support should be treated as bridge-specific configuration, not as part of the general light/group import UI.
- Pico discovery/import should be a separate operator action from the normal Caseta light/group import.
- Runtime Pico actions should map onto existing HueWorks actions wherever possible.
- This work should be considered alongside Home Assistant scene inputs, because both represent external triggers for the same internal behaviors.
- V1 should focus on direct light-control actions first, not scene activation.
- Pico target selection should behave like the scene component UI: selecting a group is shorthand for selecting its child lights, and planner/executor should be responsible for optimizing the actual hardware calls.
- Hold/release gesture handling is out of scope for V1; simple press handling is enough for the first implementation.
- Pico mappings should be scoped to a room.
- Group/light selection in Pico config should only include entities from that Pico's room.
- Pico config should define room-scoped local control groups inside the Pico config itself.
- Each button mapping should target either one local control group or the union of all configured control groups.
- Button assignment should be learned by physical button press during config rather than inferred from model-specific button ordering.
- V1 should support any Pico model whose discovered button count can be imported, but only simple press actions are required.
- Favorite-style toggle semantics should be generic: if any targeted light is on, turn the targeted set off; otherwise turn it on.
- Toggle evaluation should prefer desired state over physical state so rapid sequences and in-progress transitions behave predictably.

## What Already Exists
There is already useful Pico/button data in the Caseta fetch layer.

The current Caseta fetcher reads:

- `/device`
- `/button`
- `/virtualbutton`

and already derives Pico-related button records in:

- `/Users/ianwalther/code/hueworks/lib/hueworks/import/fetch/caseta.ex`

The fetched `pico_buttons` data already includes:

- `button_id`
- `button_number`
- `parent_device_id`
- `device_name`
- `area_id`

That means the system already has enough fetch-time information to answer:

- which Pico/device this button belongs to
- which button number it is on that Pico

In other words, the identity model we need is already present in raw fetch data:

- `parent_device_id` identifies the Pico/device
- `button_number` identifies the button on that Pico
- `button_id` identifies the runtime button resource

What does not exist yet is persistence or normalization for this data in the import pipeline.

Today:

- Pico/button data is fetched
- but the Caseta normalizer only turns lights/groups/rooms into canonical imported entities
- and runtime Pico events are still only stub-logged

So Pico support is not starting from zero. The discovery and event subscription pieces already exist in rough form.

## Implemented In V1
- Replaced the old Caseta Pico stub logging path with real event ingestion.
- Added persistence for Pico devices and discovered buttons.
- Added separate Pico sync/config entry points from the Caseta bridge on `/config`.
- Added room-scoped Pico-local control groups.
- Added learned button binding by physical press.
- Mapped Pico button presses into existing HueWorks manual light-control actions.
- Added tests for Pico event ingestion, binding resolution, learning flow, and runtime dispatch.

## Remaining V1 Polish
- Improve the Pico config UI so it feels as polished and legible as the scene builder.
- Reduce LiveView form awkwardness and make the binding editor more obvious to use.
- Improve visual hierarchy around:
  - room override
  - control groups
  - button bindings
  - "waiting for press" state
- Add clearer success/error feedback during binding and save operations.

## Out Of Scope (Initial Version)
- Arbitrary scripting/macros beyond what the HueWorks UI already supports.
- Cross-system Pico sync with Home Assistant or other controllers.
- Rich multi-step automations triggered by one Pico event.
- Per-button custom rate curves or advanced dimming choreography unless needed for parity.

## Config UI Surface
Add a dedicated Pico configuration action to the Caseta bridge card on `/config`.

This should likely open a dedicated Pico configuration view or modal where operators can:

- see discovered Pico devices
- identify them by name or source id
- review current button mappings
- assign or change mappings
- disable or clear mappings
- validate that incoming button events are being seen

The important product decision here is that Pico configuration should be easy to reach from the same place users already manage bridge-level setup.

It should not feel like a hidden expert-only path.

Room scoping should be explicit in this UI:

- each Pico should belong to a room context
- target pickers should only show groups/lights from that room
- the configuration experience should feel like setting up a room-local control surface, not a whole-house global automation

## Runtime Behavior Model
The safest model is to treat Pico button actions as requests for HueWorks-native actions.

Examples:

- toggle room occupancy
- turn a group on or off
- raise or lower brightness through the same manual-control path used by the UI

For V1 specifically, the emphasis should stay on direct light-control actions rather than scene activation. Scene-trigger behavior can come later once the basic Pico mapping workflow is proven out.

For V1, button handling should be based on simple press events only. Hold/release differentiation can be deferred to a later version if manual dimming or richer gesture support becomes important.

The more Pico behavior can reuse existing HueWorks action boundaries, the fewer special cases we will create.

That suggests a structure like:

- Pico event arrives
- event resolves to a configured HueWorks action
- that action calls the same context/runtime entry point used by UI interactions

Examples of target entry points could include:

- `Scenes.activate_scene/1`
- room-level occupancy/action handlers
- light/group manual control paths

The key architectural preference is:

- translate Pico input into a HueWorks action
- do not translate Pico input directly into low-level bridge commands unless absolutely necessary

One subtle but important runtime rule now confirmed by real testing:

- `toggle` should not be decided from raw physical state alone

Instead:

- if desired state exists for a targeted light, use that first
- fall back to physical state only when desired state is absent

This keeps Pico behavior aligned with the rest of the control model and lets quick successive button presses override in-flight transitions instead of being trapped by stale observed state.

## Revised Direction: Learned Buttons + Local Control Groups
After trying to infer physical button meaning from Caseta/Lutron button numbering, the cleaner direction is to stop making the app guess.

This is no longer just a design preference; it is the direction that actually proved workable in implementation.

The better model is:

1. discover Pico devices and their buttons
2. let the user define local room-scoped control groups
3. let the user choose an action and target
4. press the physical Pico button to bind that action to the discovered button

This removes the most brittle part of the design:

- no model-specific hardcoded assumptions about physical layout
- no need to derive "top", "favorite", or "lower middle" from raw button numbers
- no back-and-forth calibration for different Pico model variants

### Discovered Hardware
The hardware layer should stay very simple:

- Pico device
- discovered button ids
- button count
- raw button numbers for debugging/reference

That is enough to know how many buttons exist without pretending the app already knows which one the user intends to use for each semantic action.

### Local Control Groups
Each Pico config should define a set of room-scoped local control groups.

These are not HueWorks global groups. They are Pico-local target sets.

Each control group should have:

- a user-visible name
- a set of selected room groups
- a set of selected room lights
- an expanded effective light id set

As with scene components:

- selecting a HueWorks group is shorthand
- the group expands to child lights
- planner/executor remain responsible for optimizing downstream hardware calls

Examples:

- `Overhead`
- `Lamps`
- `Accent`

### Button Bindings
Each button binding should define:

- target:
  - one local control group
  - or `All Control Groups`
- action:
  - `On`
  - `Off`
  - `Toggle`

For `Toggle`, semantics should be:

- if any targeted light is on, turn the targeted set off
- otherwise turn the targeted set on

### Learned Assignment Flow
The ideal V1 flow is:

1. select Pico
2. set room scope
3. define one or more local control groups
4. choose target + action in the UI
5. click `Assign by Press`
6. press the physical Pico button
7. bind that discovered button id to the chosen action

This makes configuration hardware-truth-based rather than inference-based.

It also means the same UI can work for:

- 2-button Picos
- 4-button Picos
- 5-button Picos

without needing different physical-layout tables for each model in V1.

### Why This Is Better
This revised direction gives us:

- far less model-specific logic
- fewer hidden assumptions
- easier debugging
- easier future support for more Pico variants
- a setup flow that mirrors what the user is actually trying to do

It also fits the product intent better:

> "I want this physical button to do this HueWorks action."

instead of:

> "I hope the app guessed what Lutron means by this button number."

### Implications For Runtime
Runtime stays simple:

- button press arrives with discovered button id
- Pico button lookup resolves to stored action binding
- action binding resolves to local control group or union
- local control group resolves to light ids
- HueWorks manual control path handles the actual action

This keeps the external input path aligned with the rest of HueWorks.

In practice, one extra rule turned out to matter:

- toggle evaluation must use effective current intent, not only observed state

That is what allows quick button sequences to feel correct even while lights are still transitioning.

### What To Keep From The Earlier Work
The following pieces are still good and should remain:

- separate Pico sync from normal Caseta entity import
- bridge-level `/config` entry point
- room scoping
- group-as-shorthand target selection
- direct runtime use of existing HueWorks light-control entry points
- press-only V1
- desired-state-first toggle behavior

### What To Replace
The following earlier ideas should be de-emphasized or removed:

- hardcoded 5-button physical slot assumptions
- preset-first configuration as the primary setup path
- trying to infer favorite/top/bottom semantics from raw imported button order

Presets can still exist later as optional shortcuts, but they should be layered on top of learned button assignment rather than replacing it.

## Future Follow-Up
The current runtime is technically solid enough to use, but the UI still needs a real polish pass.

The highest-value next steps are:

- make the Pico config page visually closer to the scene builder
- improve affordances for creating/editing control groups
- make button binding state clearer at a glance
- improve "assign by press" feedback and completion signaling
- add optional shortcuts/presets on top of the learned-button model, not instead of it
- add 2-button and 4-button tailored flows later
- add scene-trigger support later once light-control UX is settled

## For `2_button`
- `on_off_single_target`
- `brighten_dim_active_scene`
- `toggle_pair`
- `custom`

These names are implementation-facing placeholders, not final UI copy.

The important design point is:

- presets should be hardware-profile-specific
- not every preset should appear for every Pico model
- the 5-button preset path should be the first polished experience, since that is the actual near-term house usage

## Semantic Target Slots
Internally, presets will likely be easier to model if they first define semantic target slots, then generate concrete button mappings.

For example:

- `primary_target`
- `secondary_target`
- `all_target`

Then the preset can say:

- top button -> `primary_target` on
- bottom button -> `primary_target` off
- upper middle -> `secondary_target` on
- lower middle -> `secondary_target` off
- favorite -> `all_target` toggle

This is cleaner than hardcoding every preset directly as raw button/action rows.

It also makes future presets easier to add and easier to explain in the UI.

For the preferred 5-button room-control preset, `all_target` should be derived automatically as:

- union(`primary_target`, `secondary_target`)

instead of being configured as a separate unrelated target.

## Mapping Model
A first version can stay intentionally simple.

Possible shape:

### `pico_devices`
- `id`
- `bridge_id`
- `source_id`
- `name`
- `display_name`
- `metadata`
- timestamps

### `pico_button_mappings`
- `id`
- `pico_device_id`
- `button` or `button_number`
- `press_type` or gesture (`press`, `hold`, `release` if needed)
- `action_type`
- `action_config`
- `enabled`
- timestamps

The exact schema can stay flexible, but the important part is that mappings should resolve to HueWorks-native actions, not arbitrary transport behavior.

## Action Types To Consider
Initial action types that seem most aligned with current HueWorks behavior:

- turn room/group/light on
- turn room/group/light off
- toggle occupancy
- brighten / dim active room scene
- maybe cycle scenes in a room later

I would strongly prefer starting with a narrow, high-confidence set that maps cleanly onto existing runtime paths.

A simpler first version is probably better than over-designing a huge action surface.

## Discovery And Refresh
Pico support likely needs a device discovery or refresh path, but this should still be kept conceptually separate from normal light/group import.

This is not just a product preference; it also fits the current code shape well.

Reasons a separate Pico import/sync process makes sense:

- Pico/button data already comes from a distinct Caseta fetch path
- it does not fit naturally into the shared light/group/room normalization model
- it will need Pico-specific persistence and mapping UI anyway
- runtime button handling will depend on persisted button identity data, especially `button_id -> parent_device_id + button_number`

A reasonable operator flow would be:

1. Configure Caseta bridge.
2. Open Pico config from the Caseta bridge card.
3. Refresh or discover Pico devices.
4. Select a Pico and assign mappings to buttons.
5. Test a button press and confirm that HueWorks performs the expected action.

This keeps bridge setup, Pico discovery, and runtime mapping close together in the UI.

An additional operator-friendly setup flow worth supporting:

1. Open the Pico configuration page/list.
2. Press a button on the Pico you want to configure.
3. HueWorks detects the incoming button event.
4. If that Pico is already known, automatically open or redirect to its config view.

This "detect with button press" flow seems very feasible given the current runtime event model, because button events already identify the button resource.

## Target Selection UX
The target-selection UX should feel familiar to the existing scene editor.

Preferred model:

- user can add a group as shorthand
- user can also add individual lights directly
- HueWorks expands that selection to the child lights underneath
- the stored runtime mapping ultimately targets lights
- planner/executor remains responsible for deciding whether group-level or light-level hardware actions are optimal

This is important because it preserves a single source of truth for hardware optimization:

- the UI expresses user intent
- the planner/executor decides how to issue efficient bridge calls

That is preferable to baking permanent group-dispatch assumptions directly into Pico mappings.

The selection experience should intentionally mirror scene component editing as much as possible:

- same mental model
- same room-local filtering
- same idea that groups are convenience shorthands for sets of lights

## Relationship To Home Assistant Scene Inputs
These two efforts should be designed with a shared mental model:

- Home Assistant scenes are external software triggers.
- Picos are external hardware triggers.
- both should ultimately invoke the same internal HueWorks actions users can trigger from the app.

This matters because it gives us a more coherent architecture:

- external input adapters
- mapping/configuration layer
- shared HueWorks action entry points

rather than:

- one special flow for HA scenes
- another unrelated special flow for Picos
- direct bridge dispatch scattered in multiple places

## Runtime Identity Resolution
The current Caseta runtime button event stream appears to provide the button resource identity itself, for example via a button href like:

- `/button/1`

That means the likely runtime resolution flow is:

1. Caseta LEAP button event arrives.
2. Extract `button_id` from the event href.
3. Resolve persisted button record by `button_id`.
4. From that record, recover:
   - Pico/device (`parent_device_id`)
   - button number (`button_number`)
   - configured HueWorks action mapping
5. Execute the mapped HueWorks-native action.

That same identity resolution also makes a "detect with button press" setup flow realistic:

- button event arrives
- resolve `button_id`
- recover parent Pico/device
- open the associated Pico configuration UI

This is another reason the import/sync step matters:

- runtime events are likely keyed by button resource id
- the user-facing config UI will likely want to show Pico/device names and button numbers
- so we need persisted imported records to bridge those two worlds cleanly

## Testing Plan
- Unit:
  - Pico event normalization/parsing
  - mapping resolution rules
  - invalid/unmapped button behavior
- Integration:
  - Pico event -> mapped HueWorks action
  - disabled mapping -> no-op
  - repeated button events behave predictably
- UI:
  - Caseta bridge card Pico config entry point
  - mapping create/update/remove
  - discovered device list and status

## Phased Execution Plan
1. Define Pico data model and mapping shape.
2. Add Caseta bridge-card config entry point in `/config`.
3. Add Pico discovery/listing/config UI.
4. Replace stub Pico event logging with real mapping resolution.
5. Route mapped actions into existing HueWorks runtime entry points.
6. Add integration and UI regression coverage.

## Open Questions
- What is the smallest initial action surface that still makes Pico support feel useful day one?
- For room scoping, should Pico room assignment come directly from imported Caseta area metadata, or should users be able to override it later?
- Should the detect-with-button-press flow redirect immediately, or first highlight/select the Pico in a list?
- How much runtime feedback about Pico presses should be exposed in the UI/logs?

## Bottom Line
Pico support should not be treated as a one-off remote-control exception.

It should be treated as another external-input path into HueWorks-native actions.

That keeps the user experience coherent:

- clicking in the HueWorks UI
- triggering a mapped Home Assistant scene
- pressing a Pico button

should all feel like different front doors into the same control system.
