# CSS Refactor — Notes

Follows the layout polish ledger in `00-plan.md`. Four commits on `ui-layout-polish`, each independently diffable:

| Commit | What |
|---|---|
| CSS guard test and class hygiene | `test/hueworks_web/css_classes_test.exs` fails when app.css and the templates disagree about which `hw-*` classes exist. Fixed a second room→area rename miss on the bridge review page and defined the button-quiet / button-secondary / dropzone / guided-empty-state styles templates already used. |
| Tokenize spacing, type, radius, elevation, surfaces | Real scales in the theme block; every component literal snapped to a token. 8 spacing steps, 10 type sizes, radius sm/md/lg/xl/pill/control, 6 shadows, 4 translucent surface levels (`--hw-glass-1..4`), `--hw-line`, `--hw-text-soft`, font-family tokens. |
| Consolidate the stylesheet onto shared primitives | Component section rewritten in a documented order (layout → text → surfaces → controls → composition → page modules, each module with its own breakpoints). |
| Drop Tailwind; build CSS with esbuild | Tailwind was preflight-only. Own reset lives at the top of the component section. |

## Vocabulary to reuse

- **Surfaces**: `.hw-panel` (page section), `.hw-card` (opaque item), `.hw-tile` (translucent inset row/sub-card; add `.hw-tile-quiet` or `.hw-tile-dashed`).
- **Tones**: `.hw-tone-success|warning|danger|accent` tint any surface, badge, stat tile, or callout the same way. `.hw-status-badge-*` and `.hw-callout-*` use the same names.
- **Headers**: `.hw-panel-header` / `.hw-section-header` (eyebrow + h2/h3 on the left, actions on the right; h2 gets the display face).
- **Rows**: `.hw-data-row` (+ `.hw-data-row-main`, `.hw-data-row-actions`, `.hw-data-row-active`); combine with `.hw-tile` for a bordered row.
- **Stats**: `.hw-stat-strip` of `.hw-stat-tile` (`strong` value + `span` label).
- **Forms**: `.hw-form` (stacked), `.hw-form-grid` (two columns), `.hw-field-group`, `.hw-inline-fields`, `.hw-form-actions`. Only `.hw-field-input` / `.hw-field-select` exist for controls. Vertical rhythm belongs to the form, not its children: `.hw-form > * + *` gives siblings the small gap, and anything that starts a new field (label, toggle, grid, callout, actions row, heading) or follows a block gets the field gap. Controls carry no margins of their own, so never add spacing classes to labels.
- **Disclosures**: `.hw-disclosure` (tile with chevron summary, `.hw-disclosure-body`), `.hw-detail-disclosure` (hairline list style on Areas).
- **Bars**: `.hw-action-bar` (sticky bottom), `.hw-callout` (+ `.hw-callout-block` for margin below).
- **Buttons**: `.hw-button` with `-primary`, `-secondary`, `-quiet`, `-small`, `-on`, `-off`, `.hw-delete-button`.

Page-frame paddings (shell, content frame) and a few negative margins are the only literal lengths left; everything else references a token.

## Verification harness

Regression checking was done with headless Chrome over the DevTools protocol (no dependencies beyond Node ≥ 22 and Chrome):

- `capture.mjs <stage> [width]` — visits every dev route (plus any static fixture pages) and writes a computed-style + geometry snapshot per route.
- `diff.mjs <a> <b> [width] --tol=px` — reports style differences and size / parent-relative position changes between two stages.
- `shot.mjs <stage> [width] [routes…]` — full-page PNGs.
- A skipped-by-default ExUnit module (`SNAP_OUT=dir mix test test/hueworks_web/snapshot_dump_test.exs`) renders pages the dev database cannot show (bridge import review, bridge change review, Pico detail, setup with HA inventory) from test fixtures into static HTML for the tools above.

These lived in the session scratchpad and the dump module is git-excluded; check them into `tooling/css-snapshot/` if you want to keep using them.
