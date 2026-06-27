# Transition Smoothness

## User Experience Problem
Some light transitions can feel rough in normal daily use.

Observed pain points:
- Scene changes can feel too abrupt.
- Circadian adaptation can sometimes be visually noticeable.
- Abrupt catch-up behavior is especially jarring when lights appear not to adapt smoothly and then change suddenly.

## Current Product Concern
HueWorks currently treats transition timing as a shared behavior across different user intents:
- manual control
- scene changes
- circadian adaptation

Those contexts may not want the same feel. A transition that is acceptable for direct manual control may be too abrupt for a scene change, while a transition that works for scene activation may still be noticeable during subtle circadian adaptation.

## Desired Outcome
Transition behavior should feel intentional for the context.

From the user's perspective:
- Scene changes should feel smooth rather than abrupt.
- Circadian adaptation should usually fade into the background.
- Manual control should remain responsive and predictable.
- The app should avoid jarring delayed catch-up changes during normal adaptation periods.

## Non-Goals For This Planning Note
- Do not choose a data model yet.
- Do not choose a transition-time formula yet.
- Do not assume one global setting can satisfy every context.
- Do not start with bridge-specific implementation details.

## Open Questions
- Should scene changes, manual control, and circadian adaptation have separate transition behavior?
- Should transition feel be configurable globally, per room, per scene, or per behavior type?
- Should circadian adaptation optimize for being imperceptible even if convergence takes longer?
- Should scene changes prioritize room-wide coordination over raw speed?
