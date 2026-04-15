# Project Instructions

1. Planning docs are forward-looking only.
   Do not use planning docs to record completed work or progress updates. Remove completed items from planning docs instead of marking them done, and keep planning docs focused on future work, open decisions, and remaining refactor targets.

2. Keep docs in sync with code changes.
   When code changes complete or materially change a planned item, update the relevant docs in the same change. Remove completed items from forward-looking planning docs at the time the code lands, and update priorities or methodology immediately when the direction changes so future humans and agents inherit the current plan instead of stale intent.

3. Prefer pipes when style is a tossup.
   Do not force the pipe operator into every call site, but when two styles are similarly clear, prefer the pipe operator for readability and flow.

4. Run the full test suite before finishing any task.
   Always run `mix test` before declaring work complete. Fix any failures introduced by the change before closing out.

5. Do not use worktree isolation when spawning agents.
   Always edit files directly in the working tree. Do not pass `isolation: "worktree"` when using the Agent tool.
