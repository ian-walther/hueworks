# Extended Kelvin Profiles

## Goal
Plan a future rework of extended low-end white-temperature handling without disturbing the current working behavior.

The current calculations are good enough to keep shipping, but future work should make it possible to add a separate, more color-theory-driven implementation that is easier to tune and reason about.

## Core Direction
Future work should treat the current extended-kelvin calculations as a frozen legacy profile and add any new implementation beside it rather than rewriting it in place.

Target shape:

- keep the existing path as `legacy`
- add a separate profile system for alternate extended-kelvin mappings
- allow global selection of a profile first
- consider per-light or per-group override only later if it proves necessary

This keeps the current behavior stable while giving room for more principled experimentation.

## Architectural Boundary
This work should stay below the intent layer.

It belongs with lower-level device-profile and color-mapping semantics, not in scene intent or `DesiredState`.

That means future work should prefer boundaries like:

- scene/circadian/manual intent chooses a logical kelvin target
- lower-level color-mapping code turns that target into control payload chromaticity
- lower-level parsing code maps reported chromaticity back into logical kelvin

## Preserve The Legacy Profile
The current implementation should remain available as a named profile.

Reasons:

- it already works well enough in production
- it preserves the current visual feel around `2000K`
- it provides a safe fallback if newer profiles are not satisfactory
- it gives future experiments a fixed baseline for A/B comparison

The legacy profile should remain the default until a newer profile proves clearly better in real rooms.

## Proposed New Model
### Use CCT Plus Tint, Not Raw XY Knobs
A better future model should be based on:

- correlated color temperature (`CCT`) as the warm/cool axis
- `Duv` as the tint axis relative to the blackbody locus

This is a better fit for the problem than directly exposing XY constants.

Why:

- `CCT` answers how warm the light should be
- `Duv` answers how pink or green the light should feel
- complaints like "too pink around `2600K`" map naturally to the tint axis

### Use Anchors Rather Than Magic Constants
The new profile system should prefer a small set of anchor points over formula coefficients.

Example profile definition shape:

- `2000K -> duv -0.0010`
- `2200K -> duv -0.0008`
- `2400K -> duv -0.0004`
- `2600K -> duv 0.0000`
- `2700K -> duv 0.0000`

The exact values are illustrative. The important idea is:

- tune visually at a few anchor temperatures
- interpolate between anchors
- avoid exposing low-level XY constants first

### Interpolate In A Better Space
If a new profile is implemented, interpolation should happen in a more suitable chromaticity space than plain XY.

Recommended working space:

- `u'v'`

Reason:

- XY interpolation tends to produce awkward visual drift
- `u'v'` is a better space for smooth tint interpolation

Suggested forward path:

1. take logical kelvin
2. resolve interpolated `Duv` for that kelvin
3. compute target chromaticity from `CCT + Duv`
4. convert to `u'v'`
5. interpolate there if needed
6. convert to output `xy`

## Reverse Mapping Strategy
The system also needs to map observed `xy` back into logical kelvin for event parsing and convergence.

A future implementation should avoid trying to derive a complex analytic inverse.

Recommended approach:

- build a lookup table across the extended band
- generate a forward mapping for each step, for example every `5K` or `10K`
- reverse-map by nearest lookup entry in chromaticity space

Why this is a good fit:

- simple to reason about
- stable round trips
- easy to test
- easy to compare across profiles

## Suggested Module Shape
A future implementation should likely live in a separate module instead of extending the current helpers further.

Candidate module shape:

- `/Users/ianwalther/code/hueworks/lib/hueworks/extended_kelvin_profiles.ex`

Possible responsibilities:

- expose available profile names
- resolve the active profile from config
- forward-map logical kelvin to `xy`
- build or cache reverse lookup tables
- reverse-map `xy` to logical kelvin

The current `/Users/ianwalther/code/hueworks/lib/hueworks/kelvin.ex` could then delegate to:

- legacy profile helpers for the current path
- new profile helpers for alternate paths

## Configuration Shape
### Global First
The first configurable version should likely be global-only.

Candidate setting:

- `extended_kelvin_profile`

Possible values:

- `legacy`
- `warm_dim_v1`
- `warm_dim_less_pink`
- `custom`

Global-first benefits:

- low UI complexity
- easy rollback
- easy visual comparison
- easier testing and support

### Custom Profile Later
If a `custom` mode is eventually added, it should expose a small set of anchor temperatures and tint adjustments rather than raw XY constants.

Example future custom inputs:

- `2000K tint`
- `2200K tint`
- `2400K tint`
- `2600K tint`
- `2700K tint`

This would be much easier to understand than:

- `x_start`
- `x_end`
- `y_start`
- `y_end`
- `bias`
- `bulge`

## UI Direction
The first UI should be intentionally small.

Recommended first pass:

- one global dropdown on the config page for extended-kelvin profile
- optional explanatory text about what each profile is optimized for

Avoid in the first pass:

- per-light custom curve editors
- raw XY coefficient fields
- dense scientific controls in the UI

If later needed, a second-pass UI could expose a compact custom profile editor using a few temperature anchors.

## Implementation Phases
### Phase 1
- freeze current behavior as `legacy`
- add a profile abstraction beside the current implementation
- keep `legacy` as the default

### Phase 2
- add one new alternate preset profile
- optimize it for reduced pinkness near `2600K`
- compare visually in real rooms

### Phase 3
- add global config selection for profile choice
- keep rollback to `legacy` trivial

### Phase 4
- consider custom anchors only if preset profiles are not enough

## Testing Expectations
Any future implementation should be tested in three ways:

1. forward mapping
- expected logical kelvin -> expected `xy` trend

2. reverse mapping
- reported `xy` round-trips back to the intended logical kelvin band

3. real-room validation
- compare visible behavior around the most sensitive region, especially `2500K-2700K`

A future profile should not replace `legacy` unless it is visibly better in real rooms, not just numerically different.

## Open Questions
These should be answered before implementation begins:

1. Should alternate profiles be global-only, or should lights/groups be able to opt in separately later?
2. Is one improved preset likely enough, or is a custom-anchor mode expected to matter soon?
3. How fine should the reverse lookup table be to get stable round trips without unnecessary overhead?
4. Should profile selection live only in app settings first, or should it eventually become part of light/group capability tuning?
