# Pico Support

## Goal
Allow Caseta Pico remotes to act as first-class external inputs for HueWorks so they can trigger the same kinds of actions users can already perform directly in the HueWorks UI.

This is not just a convenience feature. It is part of the core value of HueWorks:

- controlling lights across multiple bridges together
- replacing multiple fragmented hardware control surfaces with fewer, more trustworthy ones
- making physical control feel as reliable as scene activation already does

## Product Framing
Pico support should be designed as part of the same broad workflow as Home Assistant scene activation:

- these are external inputs
- they should enter the same core scene/control pipeline as direct UI interaction
- they should not invent a parallel control model unless there is a strong reason to do so

The guiding principle should be:

> A Pico button press should feel like a physical shortcut for actions users could already trigger from HueWorks.

That means the implementation should prefer reusing the existing HueWorks action paths rather than creating one-off dispatch behavior for remotes.

## Current Status
Pico support is now implemented and working end-to-end for the V1 light-control path.

Implemented pieces:

- separate Pico sync exists
- Pico config is reachable from the Caseta bridge card on `/config`
- discovered Picos and buttons are persisted
- button actions can be learned by physical button press
- Pico-local room-scoped control groups work
- the top-level Pico page supports `Detect Pico` and can jump into a Pico config page by physical button press
- button presses drive the normal HueWorks light-control path
- room override works and persists across later Pico syncs

At this point, Pico support is technically usable in real rooms.

The remaining issues are no longer about “can a Pico control HueWorks at all?” They are about:

- UI polish
- setup ergonomics
- convergence reliability under rapid mixed-bridge interaction

## Locked Decisions
- Pico configuration should have a dedicated entry point from the Caseta bridge card on `/config`.
- Pico support should be treated as bridge-specific configuration, not as part of the general light/group import UI.
- Pico discovery/import should be a separate operator action from the normal Caseta light/group import.
- Runtime Pico actions should map onto existing HueWorks actions wherever possible.
- This work should be considered alongside Home Assistant scene inputs, because both represent external triggers for the same internal behaviors.
- V1 focuses on direct light-control actions, not scene activation.
- Pico mappings are scoped to a room.
- Group/light selection in Pico config should only include entities from that Pico's room.
- Pico config defines room-scoped local control groups inside the Pico config itself.
- Each button mapping targets either one local control group or the union of all configured control groups.
- Button assignment is learned by physical button press during config rather than inferred from model-specific button ordering.
- Hold/release gesture handling is out of scope for V1.
- Favorite-style toggle semantics are generic: if any targeted light is on, turn the targeted set off; otherwise turn it on.
- Toggle evaluation must prefer `DesiredState` over raw physical `State`.

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

## Implemented In V1
### Discovery and Persistence
- Separate Pico sync from normal Caseta entity import.
- Persist Pico devices and discovered buttons.
- Preserve manual room overrides across later syncs.

### Config UI
- Add a bridge-level Pico configuration entry point on `/config`.
- Split Pico config into:
  - a Pico list page
  - a dedicated Pico detail/edit page
- Support `Detect Pico` from the list page to jump directly into a known Pico’s config page.
- Support room-scoped control-group editing using the same group-as-shorthand mental model as scene components.
- Support assign-by-press button learning.

### Runtime
- Replace the old Pico stub logging path with real Caseta button event ingestion.
- Subscribe to per-button Caseta LEAP event URLs.
- Resolve discovered button ids to stored Pico button bindings.
- Map Pico button presses into existing HueWorks manual light-control actions.

## Runtime Model That Actually Worked
### Learned Buttons + Local Control Groups
The workable model is:

1. discover Pico devices and their buttons
2. let the user define local room-scoped control groups
3. let the user choose an action and target
4. press the physical Pico button to bind that action to the discovered button

This removes the most brittle part of the original idea:

- no model-specific hardcoded assumptions about physical layout
- no need to derive `top`, `favorite`, or `lower middle` from raw button numbers
- no back-and-forth calibration for different Pico model variants

### Control Groups
Each Pico config defines a set of room-scoped local control groups.

These are not HueWorks global groups. They are Pico-local target sets.

Each control group has:

- a user-visible name
- a set of selected room groups
- a set of selected room lights
- an expanded effective light id set

As with scene components:

- selecting a HueWorks group is shorthand
- the group expands to child lights
- planner/executor remain responsible for optimizing downstream hardware calls

### Button Bindings
Each button binding defines:

- target:
  - one local control group
  - or `All Control Groups`
- action:
  - `On`
  - `Off`
  - `Toggle`

For `Toggle`, semantics are:

- if any targeted light is on, turn the targeted set off
- otherwise turn the targeted set on

### Why This Is Better
This direction gives us:

- far less model-specific logic
- fewer hidden assumptions
- easier debugging
- easier future support for more Pico variants
- a setup flow that mirrors what the user is actually trying to do

It also fits the product intent better:

> "I want this physical button to do this HueWorks action."

instead of:

> "I hope the app guessed what Lutron means by this button number."

## Important Lessons From Real Use
### 1. Toggle Must Prefer Desired State
This was confirmed by real Pico use, not just theory.

If toggle decisions read raw physical state only, then quick successive button presses can make the wrong choice because the physical state has not caught up yet.

The correct rule is:

- if desired state exists for a targeted light, use that first
- fall back to physical state only when desired state is absent

This makes Pico behavior align with the rest of the control model and lets quick button sequences override in-flight transitions instead of being trapped by stale observed state.

### 2. Manual Control Still Converges Less Reliably Than Scenes
Even after improving toggle semantics and adding retries, real Pico use showed:

- scene activation is effectively near-100% reliable
- Pico/manual power control is improved but still slightly less reliable, especially across mixed bridges

That strongly suggests a remaining structural gap:

- scenes behave like durable target ownership
- manual/Pico control still behaves more like a one-shot command path with retries

### 3. Mixed-Bridge Rapid Interaction Exposes the Weakness
The most important real-world Pico use case is exactly where HueWorks is supposed to shine:

- one button press controlling Hue and Z2M lights together
- replacing multiple separate control surfaces with one trustworthy one

That means the remaining misses are not edge-case nice-to-haves. They are hitting one of the core product promises.

### 4. Boot-Time Subscription Is a Real Operational Gotcha
Caseta Pico button subscriptions currently load from persisted Pico button rows when the Caseta event stream starts.

That means:

- Pico sync/config done after the event stream is already running may not take effect immediately
- a restart currently refreshes those button subscriptions

This is acceptable for now, but it should not remain the long-term model.

## What Has Been Tried Already
### Reliability Improvements Already Landed
The current implementation already includes these improvements:

- desired-state-first toggle decisions
- reconcile-aware manual planning (`intent_diff + reconcile_diff`)
- bounded delayed follow-up reconcile passes for manual power actions
- retries that re-read the latest desired state rather than replaying stale button intent
- shared internal control/apply extraction so scenes and manual control diverge less internally

This has made Pico/manual control meaningfully better.

But the current conclusion is:

- this is the best it has been so far
- it is still not quite at scene-setting reliability

## The Next Deeper Fix
### Core Thesis
The remaining gap is probably not best solved with more ad hoc retries.

The better direction is:

- make manual/Pico control behave more like a transient scene
- not like a lightweight manual command path

In other words, a Pico/manual press should create short-lived target ownership that remains active until convergence, rather than issuing one command and hoping retries are enough.

### Why This Matches The Evidence
Scene activation succeeds more reliably because it already acts like:

- declare target state
- keep reconciling toward it
- treat stale physical state as lagging convergence, not as the primary truth source

Manual/Pico control still only approximates that behavior.

That is likely why scenes feel essentially perfect while Pico/manual control still has a small miss rate.

### Proposed Architecture Direction
Introduce a transient manual-intent layer.

Conceptually:

1. Pico/manual press creates a short-lived manual target for a room or target set
2. that manual target owns the affected lights for a bounded window
3. the system keeps reconciling physical state toward that target until:
   - convergence is reached
   - a newer manual target replaces it
   - a bounded timeout/attempt count is hit

This would be much closer to scene-setting semantics.

### Desired Properties Of That Model
- new button presses supersede older ones cleanly
- mixed-bridge targets are treated as one logical action, not just multiple best-effort commands
- convergence is explicit and bounded
- retry behavior is not ad hoc per button type
- the current public APIs can stay stable while the internals change underneath

### Safe Implementation Strategy
This should not be a one-shot rewrite.

The right rollout shape is:

1. keep public surfaces unchanged:
   - `/Users/ianwalther/code/hueworks/lib/hueworks/scenes.ex`
   - `/Users/ianwalther/code/hueworks/lib/hueworks/lights/manual_control.ex`
2. keep using the existing test suite as the primary guardrail
3. introduce transient manual intent underneath those surfaces
4. reuse the shared control/apply/convergence internals as much as possible
5. phase behavior changes carefully and test in prod with real Picos and real bridge combinations

### Why This Complexity Is Justified
Normally, adding a transient intent layer would look like complexity creep.

In this case, it appears justified because:

- Pico/manual control is not a convenience feature anymore
- it is part of the core real-world lighting workflow
- it is expected to behave like a physical switch across bridges
- scenes already prove that HueWorks can reach that reliability level with a stronger target/convergence model

So the goal is not “make Pico support clever.”

The goal is:

- give manual physical control the same reliability characteristics that scenes already have

## Remaining Follow-Up
### Product / UI
- Improve the Pico config UI so it feels as polished and legible as the scene builder.
- Reduce LiveView form awkwardness and make the binding editor more obvious to use.
- Improve visual hierarchy around:
  - room override
  - control groups
  - button bindings
  - waiting-for-press state
- Add clearer success/error feedback during binding and save operations.

### Runtime / Architecture
- Refresh Caseta button subscriptions when Pico sync/config changes, instead of relying on restart.
- Investigate whether the transient manual-intent architecture should replace the current manual retry model.
- Add richer timing/logging around Pico/manual convergence only if needed to validate the next architecture pass.

### Later, Not Now
- Scene-trigger support from Picos.
- Hold/release gesture handling.
- Optional presets layered on top of learned-button assignment.
- More tailored 2-button and 4-button setup flows.

## What No Longer Belongs At The Center Of The Plan
The following ideas were useful stepping stones, but should no longer be the primary direction:

- hardcoded 5-button physical slot assumptions
- preset-first configuration as the main setup path
- trying to infer `favorite`, `top`, or `bottom` semantics from raw button numbering
- treating manual/Pico control as a permanently lightweight path compared to scenes

Those ideas may still inform optional future conveniences, but they should not define the core implementation anymore.
