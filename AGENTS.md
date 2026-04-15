# Project Instructions

1. Planning docs are forward-looking only.
   Do not use planning docs to record completed work or progress updates. Remove completed items from planning docs instead of marking them done, and keep planning docs focused on future work, open decisions, and remaining refactor targets.

2. Keep docs in sync with code changes.
   When code changes complete or materially change a planned item, update the relevant docs in the same change. Remove completed items from forward-looking planning docs at the time the code lands, and update priorities or methodology immediately when the direction changes so future humans and agents inherit the current plan instead of stale intent.

3. Prefer pipes when style is a tossup.
   Do not force the pipe operator into every call site, but when two styles are similarly clear, prefer the pipe operator for readability and flow.
