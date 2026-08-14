# Chunk 6 — Web (main LiveViews)

Status: CLOSED. WM1-WM4 implemented and reconciled. No open findings.

## Explicitly Fine / Leave-Alone

- **`SceneBuilderComponent` vs `SceneBuilderComponent.Component`** — not duplicates: LiveComponent vs domain struct. The naming is unfortunate but renaming is churn without complexity reduction.
- **`ControlLive` size (788)** — organized into clause families + function components; nothing dead found.
- **Both `/control` and `/lights` routes exist** — product decision territory (see `planning/ui-product-quality.md`), not code slop.
- **`lights_live/` submodule split** — cited reference pattern for thin LiveViews; untouched.
