# Assisted-User Functionality Plan

## Goal
Make HueWorks feel reliable, powerful, and understandable for an enthusiast end user who did not personally build the system, while preserving advanced capabilities for technical operators.

## Vision Refinement
- HueWorks is the core control brain for lighting behavior and optimization.
- Home Assistant is an optional integration layer, not a hard dependency for core value.
- If Home Assistant is used, the combined HA + HueWorks experience must be at least as good as HA-only for daily control workflows, and better in key areas (optimization, predictability, explainability).

## User Archetype
- Lighting nerd who wants cool behavior from existing hardware.
- Limited technical comfort with networking, credentials, and low-level integration details.
- System is initially installed/configured by a more technical person.

## Locked Decisions
- Home Assistant integration is optional, not required for core value.
- HueWorks owns control logic and optimization decisions, independent from HA internals.
- Setup/onboarding automation is not the primary investment area right now.
- Highest priority is day-to-day functionality quality (predictability, control, confidence).
- Advanced capabilities remain available, but day-to-day usage should not require technical concepts.

## Scope
- Improve runtime behavior and UX clarity for normal operation:
  - applying scenes
  - manual changes
  - active-scene behavior
  - predictable circadian behavior
- Reduce confusing outcomes caused by integration/control ownership conflicts.
- Add simple, user-facing observability for “what changed and why.”
- Prioritize features that improve practical use of existing installed lights.

## Out of Scope (Near Term)
- Fully self-serve onboarding for non-technical users.
- Fully automated hardware/network discovery flows.
- “No-installer-needed” deployment flows.

## Highest-Impact Work Order

### 1) Predictability and Conflict Guardrails
- Define explicit room-level control ownership modes (for example: HueWorks-primary, external-primary, cooperative).
- Add clear policy for outside changes while a scene is active (for example: auto-deactivate with user-visible reason).
- Prevent silent “integration fights” by surfacing conflict warnings in UI and status views.

### 2) Active Scene Clarity
- Show active/inactive scene state prominently on room views.
- Include deactivation reason (manual change, external change, explicit deactivate, error path).
- Keep behavior consistent across manual and circadian scenes.

### 3) Runtime Confidence UX
- Add a simple “Now Controlling” status card per room:
  - current active scene
  - current mode (manual/circadian)
  - last control source (HueWorks/HA/HomeKit/etc.)
  - last apply result
- Add plain-language status/errors so users can self-diagnose common issues.

### 4) Scene Usability for Real Homes
- Improve scene editing toward outcome-based controls (less data-model terminology).
- Keep per-light default power semantics but present them in user language.
- Add scene-level transition-time support (already requested) with sane defaults.

### 5) Integration as Convenience Layer (Not Core Dependency)
- Keep HA reverse integration optional and additive for advanced users.
- Keep HomeKit bridge optional and additive for Apple-home workflows.
- Ensure core HueWorks value is strong without any external automation platform.

## Acceptance Criteria
- A non-technical enthusiast can run daily lighting behavior without needing to understand internal pipeline details.
- Manual or external changes do not produce surprising oscillation; behavior is explainable in UI.
- Scene and circadian behavior is consistent, observable, and trusted in normal household use.
- Optional integrations improve convenience without becoming mandatory for core usage.

## Testing Strategy
- Expand integration tests around:
  - active scene deactivation reasoning
  - external-change handling policies
  - manual override behavior under active scenes
- Add UI-level tests for status clarity and conflict messaging.
- Add a short in-home validation checklist for behavior that is perceptual (transition feel, room coherence).

## Open Questions
- Which control-ownership modes should be exposed first to maximize clarity with minimal complexity?
- Should conflict warnings be passive (status only) or active (blocking/rate-limiting applies) in v1?
- How much “advanced mode” detail should be hidden by default vs visible to all users?
