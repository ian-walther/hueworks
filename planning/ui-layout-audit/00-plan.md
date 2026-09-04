# UI Layout Audit — Ledger

Visual pass over prod (`http://hueworks.home/`, desktop width only) on 2026-09-03, made read-only through the browser. Every route in `router.ex` was screenshotted except the bridge reimport/import review pages (opening them refreshes the bridge's last-checked timestamp). No narrow-viewport pass was possible (Chrome ignored resizes); the built CSS has breakpoints at 900/820/720/520px only.

Branch: `ui-layout-polish`. Work is iterated in the working tree, not split per finding. Status column is the source of truth if context is lost; resume from the first `open` row.

Status values: `open`, `done`, `wontfix` (with reason).

## A. Bugs (visibly broken)

| ID | Where | Finding | Status |
|----|-------|---------|--------|
| A1 | Integrations → HomeKit card | "Apple Home Setup Code" label is overlapped ~8px by the code chip. The `<code>` carries `hw-field-input`, which brings input margins. `integrations_config_live.html.heex` | done |
| A2 | `/setup/areas` | Breadcrumb/header/progress panel stretch to 238/325/370px tall. `.hw-setup-area-page` is a grid inside the `min-height:100vh` shell, so rows stretch. Fix: `align-content:start`. `app.css` ~906 | done |
| A3 | External scenes | "Enable this mapping" checkbox and text sit at opposite card edges: the `<label class="hw-row">` is flex + space-between. `external_scene_config_live.html.heex` | done |
| A4 | `/config/light-states/new/manual` | Brightness/Temperature value readouts render as bare "%" / "K" until the slider moves. Edit page shows numbers. | done |
| A5 | Pico detail | Area `<select>` is 243px wide and truncates "Basement (Auto-Detected)". `pico_config_live.html.heex` | done |
| A6 | Pico detail | "Control groups" fieldset renders a bare legend over an empty checkbox list when no groups exist, leaving a floating label and gap before "Assign By Press". | done |
| A7 | Circadian editor charts | "2000K" y-axis label draws over the "00:00" x-axis label at the bottom-left of the Temperature Curve. | done |

## B. Spacing and alignment

| ID | Where | Finding | Status |
|----|-------|---------|--------|
| B1 | Control + Areas area cards | Header stack (title, status pill, counts, All On/Off or Edit/Delete, "Primary behavior" eyebrow) has zero gaps: buttons end at the exact px the eyebrow starts; the empty-state box ends at the exact px "Direct adjustment"/"Configuration" starts. Needs a real header/body separation. | done |
| B2 | Control + Areas | Area title is 16px/400 while light row names are 16px/700 — hierarchy inverted. | done |
| B3 | Control + Areas | Active scene row gets an accent bar + inset so its name starts ~14px right of the other scene names. | done |
| B4 | Control + Areas | "Direct adjustment"/"Configuration" section is indented with a left rule; sibling "Primary behavior" is not. | done |
| B5 | Control + Areas | "Scenes" heading and "New scene" button don't share a baseline; the button floats between eyebrow and heading. | done |
| B6 | Scene editor | Each light row puts name + power-policy select on line 1 and the round × alone on line 2, doubling row height. `scene_builder_component.ex` | done |
| B7 | Scene editor | "Light state" select starts at x=457, "Add light" select at x=452 — label column isn't fixed width. | done |
| B8 | General | Country input top is 18px above ZIP input top (the "Two-letter code" help pushes it); Look Up button sits 6px lower than the ZIP input. `.hw-postal-code-form` uses `align-items:end`. `app.css` ~1160 | done |
| B9 | Input + button rows (Reveal Token, Copy on Pico, Look Up) | Button is a few px taller and bottom-aligned each time; needs one shared rule that matches control heights. | done |
| B10 | Integrations (all cards), light-state edit ("Used by N scenes"), Pico ("Area Scope") | Intro paragraph runs straight into the first field label with zero margin. | done |
| B11 | Config overview | System panel is flush against the bottom of the Light States / Integrations cards. | done |
| B12 | Pico list + Discovered Buttons | "buttons: N" / "area: X" / "binding: …" shift per row (flex, not grid columns); every row has ~30px dead space under the content. | done |
| B13 | Lights | Slider tracks end at different x positions (label + value to the right varies in width); values not right-aligned. | done |
| B14 | Lights | "Show linked" wraps to its own line under the right column's filter row while "Show disabled" stays inline. | done |
| B15 | Circadian editor → Solar Timing | Labels sit at three heights on one row (Sunrise Time / Sunrise Window group label / Min-Max sub-labels); sunset pair splits across rows while sunrise fits on one; "Brightness mode" label wraps and drops its select below its neighbours. | done |

## C. Consistency nits

| ID | Where | Finding | Status |
|----|-------|---------|--------|
| C1 | App-wide | Button casing mixed: sentence case on Control/Areas ("New scene"), Title Case in Config ("Check for Changes", "Save And Exit"). Decision: sentence case everywhere. | done |
| C2 | Areas → Configuration | "Area details" row has no description and no action — reads as an empty row. | done |
| C3 | Areas | "Manage" / "View" are tiny text links where comparable actions elsewhere are pill buttons. | done |
| C4 | Lights | Numeric badge on light cards ("1", "31") is unexplained; group cards say "group" in the same spot. | done |
| C5 | Control / scene editor | "+ Foyer (7 lights)" group rows start with a bare plus sign. | done |
| C6 | Bridges → Home Assistant card | "Switch to Browser Authorization" makes the three-button row wrap early. | done |

## Root cause worth knowing

Most of section B on the Control and Areas cards came from one thing: the templates use `hw-area-*` class names (`hw-area-card-header`, `hw-area-ledger-body`, `hw-control-area-grid`, …) while `app.css` still defined them as `hw-room-*`. The rules were renamed to `hw-area-*`; that alone restored the card header rule, the Fraunces title, and the two-column scenes/details body. Dead `.hw-room-item*` rules were deleted at the same time.

## Decisions taken while implementing

- Control height unified: `--hw-control-height` is 2.55rem; inputs, selects and `.hw-button` all use it, so input+button rows line up without per-page fixes (B8, B9).
- Button labels are sentence case app-wide; proper nouns (Pico, HomeKit, MQTT, Home Assistant) keep their capitals. Page titles/breadcrumbs stay Title Case. "Save Home Assistant" became "Save MQTT export"; "Switch to Browser Authorization" became "Use browser authorization" (C1, C6).
- Group expand toggles use a CSS chevron (`.hw-group-toggle::before`) instead of "+"/"-" text (C5).
- Lights page source-id pill reads "ID <n>" and is hidden when the source id equals the display name (z2m) (C4).
- New manual light state seeds brightness 100 / 3000K / hue 0 / saturation 100 so the readouts and sliders agree before the first drag (A4).
- Circadian charts: y labels are right-anchored to the plot edge; the first/last x tick anchor start/end (A7). Solar Timing is two explicit rows (sunrise, sunset) and Min/Max mini-labels sit inline before their inputs (B15).
- Pico list rows and Discovered Buttons use `.hw-pico-row` (title+meta | actions grid); the "Control groups" fieldset is hidden when there are no control groups (B12, A6).

## Verification

Dev server (`mix phx.server`, port 4000, `hueworks_dev.db`) checked in the in-app browser: Control, Areas, Lights, Config overview, General, Integrations, new manual light state, Bridges, Setup areas all confirmed visually. Not visually confirmed in dev (no Caseta bridge / no saved circadian state in the dev DB): Pico pages, scene-editor member rows, circadian editor — verified by DOM measurement / CSS reasoning only; re-check on prod after deploy. `mix test` passes.
