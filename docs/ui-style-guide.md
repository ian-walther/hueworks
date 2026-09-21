# UI Style Guide

Use this vocabulary when extending the existing UI. Product and workflow principles live in [UI Product Quality](../planning/ui-product-quality.md); `assets/css/app.css` is the implementation source of truth.

## Shared Vocabulary

- **Surfaces:** `.hw-panel` for a page section, `.hw-card` for an opaque item, and `.hw-tile` for an inset row or sub-card. Add `.hw-tile-quiet` or `.hw-tile-dashed` where appropriate.
- **Tones:** `.hw-tone-success`, `.hw-tone-warning`, `.hw-tone-danger`, and `.hw-tone-accent` share semantic colors with the corresponding status-badge and callout variants.
- **Headers:** `.hw-panel-header` and `.hw-section-header` place the heading on the left and actions on the right.
- **Rows:** `.hw-data-row` with `.hw-data-row-main`, `.hw-data-row-actions`, and optionally `.hw-data-row-active`. Combine with `.hw-tile` for a bordered row.
- **Stats:** `.hw-stat-strip` contains `.hw-stat-tile` items with a `strong` value and a `span` label.
- **Forms:** `.hw-form`, `.hw-form-grid`, `.hw-field-group`, `.hw-inline-fields`, and `.hw-form-actions` own form composition. Use `.hw-field-input` and `.hw-field-select` for controls, with existing variants where needed.
- **Disclosures:** `.hw-disclosure` provides the tile and chevron summary with `.hw-disclosure-body`; `.hw-detail-disclosure` is the lighter list treatment.
- **Bars:** `.hw-action-bar` is the sticky action surface; `.hw-callout` is the contextual message surface, with `.hw-callout-block` where a following gap is needed.
- **Buttons:** compose `.hw-button` with the primary, secondary, quiet, small, on, or off variants. `.hw-delete-button` is the destructive control. Use sentence case for action labels and preserve proper nouns.

## Form Rhythm

Vertical rhythm belongs to the form, not individual controls. `.hw-form` and modal forms give adjacent children a small gap and use the larger field gap when a new field or block starts. Controls carry no margins of their own; do not add one-off label spacing classes.

Keep a field's parts together:

- Whatever directly follows `.hw-field-label` is its control, including a value row, dropzone, inline fields, or toggle, and retains the small gap.
- A hidden checkbox input between the label and visible control must not break that relationship.
- `.hw-field-help` and `.hw-muted` retain the small gap under the content they explain.
- Grids own their internal gaps; do not stack form margins onto their children.

## Tokens And Build

Use the shared semantic color, spacing, type, radius, elevation, translucent-surface, and control-size tokens in `app.css`. Keep light/dark mode values in the theme layer rather than scattering colors through templates or page modules. Use warm/on and cool/off treatments consistently for physical power state.

CSS is built with esbuild, not Tailwind. The stylesheet includes its own reset and is organized from layout, text, surfaces, and controls through shared composition and page-specific modules. Keep each page module's responsive rules beside it.

## Verification

Inspect the rendered workflow with representative data at desktop and narrow widths, in both light and dark modes. Include long labels, errors, empty states, disclosures, and wrapping action rows rather than checking only the happy path.

`test/hueworks_web/css_classes_test.exs` checks the shared class vocabulary, and `test/hueworks_web/theme_css_test.exs` protects theme and layout conventions. These checks complement, not replace, browser inspection. Run the full suite after application or styling changes under `AGENTS.md`.
