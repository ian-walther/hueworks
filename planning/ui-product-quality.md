# UI Product Quality

## Goal
Make HueWorks feel like an intentional, trustworthy product rather than a collection of individually tolerable configuration pages.

HueWorks is moving from a personal side project toward a source-available application that other people can successfully operate. The UI is currently one of the largest barriers to that goal. This work should improve both the user experience and the internal vocabulary available for future UI development.

Source availability does not change the security posture in `planned_architecture.md`. HueWorks remains a private trusted-LAN appliance and must not become publicly network-accessible without a separate system-wide security design.

## Desired Outcome
From a user's perspective:

- Related workflows behave consistently across pages.
- Common actions are easy to discover and require no unnecessary clicks.
- Dense configuration remains understandable without becoming visually noisy.
- Control and configuration surfaces have a clear information hierarchy.
- Empty, loading, editing, selected, disabled, error, and destructive states are intentional.
- Desktop and mobile layouts both feel designed rather than merely functional.
- Keyboard navigation, focus treatment, labels, contrast, and touch targets are reliable.

From a contributor's perspective:

- New UI work is composed from documented tokens, layout primitives, visual primitives, and LiveView components where appropriate.
- Repeated visual or interaction decisions have one clear implementation.
- Existing patterns can be reused when they are good, improved when they are close, and replaced when they preserve accidental limitations.
- Page-specific CSS is reserved for genuinely page-specific composition.

## Product Principles

### Improve Workflows, Not Isolated Pages
The primary unit of work is an end-to-end user workflow. Before changing one surface, inspect every neighboring surface that presents or edits the same concept.

For example, changes to light and group selection should consider scene building, Pico configuration, control, light configuration, and import review rather than solving the interaction independently on one page.

### Behavior Before Styling
Agree on interaction rules, information hierarchy, terminology, and edge cases before choosing the final visual treatment. A polished presentation must not conceal an awkward or inconsistent workflow.

### Rendered Behavior Is The Source Of Truth
Static template review is insufficient. UI decisions should be based on actually performing the workflow in the rendered application with representative data and inspecting its behavior at desktop and mobile widths.

### Existing Patterns Are Candidates, Not Constraints
Preserve patterns that are already effective, but do not formalize current inconsistency merely because it exists. This effort may expand existing reusable classes, migrate more consumers to them, introduce better replacements, and delete obsolete classes after their consumers move.

### Extract From Evidence
Do not design a complete component system in the abstract. Improve a real vertical slice, then promote a pattern when it has proven useful and has a credible second consumer. The system should become more complete as workflows improve.

### Preserve Capability During Convergence
Visual and structural refactors should not silently remove existing behavior. Capability changes require an explicit product decision and should be tested as behavior changes, not smuggled into styling work.

### Choose An Intentional Visual Direction
The finished application should have a recognizable visual language, not a generic administration-dashboard restyle. Typography, color, density, surface hierarchy, icon use, and motion should support the character and practical use of HueWorks.

## Repeatable Collaboration Workflow
Use this loop for each UI improvement:

1. **Observe the real workflow.** The user describes the pain point, then the agent performs the task in the rendered app. Record confusion, extra clicks, inconsistent behavior, poor hierarchy, responsive problems, and missing states before proposing changes.
2. **Inspect neighboring workflows.** Find every other surface using the same concept, terminology, interaction, CSS, or component. Distinguish a local problem from a system-level pattern.
3. **Propose behavior before editing.** Explain the intended interaction, edge cases, affected surfaces, and meaningful tradeoffs. Align with the user before implementation.
4. **Implement one vertical slice.** Complete the workflow rather than landing a disconnected collection of cosmetic edits. Include the relevant populated, empty, loading, editing, disabled, destructive, and error states.
5. **Verify behavior and presentation.** Use LiveView tests for semantics and browser inspection for rendered behavior, responsiveness, focus, accessibility, and visual quality.
6. **Promote successful patterns.** Move repeated styling into shared CSS primitives and repeated markup or behavior into Phoenix components. Update existing consumers when the shared pattern is clearly better.
7. **Retest the originating workflow.** Confirm that extraction did not make the original experience worse or introduce responsive and state regressions.

The user remains the product-judgment layer. The agent should own implementation, browser inspection, responsive checks, and test coverage after interaction behavior is aligned.

## Design-System Layers

### Tokens
Use CSS custom properties for foundational decisions that should evolve coherently:

- Color roles rather than page-specific color values.
- Typography families, sizes, weights, and line heights.
- Spacing scale.
- Border radii and widths.
- Shadows and elevation.
- Control heights and touch targets.
- Content widths and responsive breakpoints.
- Animation durations and easing.

Tokens should describe roles such as surface, muted text, accent, warning, and destructive action. Avoid token names tied to one page or a literal color when the value has semantic meaning.

### Layout Primitives
Provide reusable, domain-neutral layout classes for recurring spatial relationships, such as:

- Page and content containers.
- Vertical stacks.
- Inline clusters and toolbars.
- Responsive grids.
- Split layouts.
- Form and field groups.
- Section spacing.

Layout primitives should control composition without importing card, button, or domain semantics.

### Visual Primitives
Consolidate recurring visual and state treatment for:

- Buttons and icon buttons.
- Cards and surfaces.
- Fields, labels, help text, and validation errors.
- Selectors and segmented choices.
- Pills, badges, and status indicators.
- Notices and flash messages.
- Modals and overlays.
- Expandable sections.
- Empty and loading states.
- Destructive confirmations.

Every interactive primitive should define hover, active, focus-visible, disabled, and loading behavior where applicable.

### Domain Components
Repeated domain markup or behavior belongs in Phoenix components rather than CSS alone. Likely candidates include:

- Recursive light and group trees.
- Entity rows and cards.
- Scene selectors and scene status.
- Light-control surfaces.
- Bridge import and review rows.
- Reusable configuration editors.

Shared CSS should style a stable contract; shared LiveView components should own repeated markup, state presentation, and interaction structure. Do not hide domain behavior inside generic class names.

### Page Composition
Pages should increasingly compose tokens, primitives, and domain components. One-off classes remain acceptable when a page has a genuinely unique layout or interaction, but they should not duplicate an existing shared concept under a new name.

## Page-Level Implementation Plans
This section translates the cross-application principles above into concrete page and workflow designs. A page-level plan should define the information architecture, behavior, meaningful states, reusable vocabulary, verification matrix, and implementation boundaries before visual implementation begins.

Page-level plans do not replace domain planning documents. The page plan owns presentation and interaction; the relevant domain plan remains authoritative for data ownership, safety rules, and backend behavior.

Create a focused page-level plan here before implementing each future vertical slice. The plan should define the workflow, state model, information hierarchy, reusable vocabulary, verification matrix, and explicit non-goals while leaving domain ownership and safety rules in the relevant domain document.

## Ongoing Application Audit
Continue the combined static and rendered audit as each workflow approaches implementation. The Config and bridge-import slice was selected from the initial rendered evidence; completing an exhaustive whole-application audit is not a prerequisite for starting it.

### Static Audit

- Inventory stylesheets, CSS variables, reusable classes, inline styles, JavaScript hooks, and Phoenix components.
- Find repeated declarations and repeated HEEX structures.
- Identify classes whose names or contracts are too page-specific for their actual reuse.
- Identify broad classes whose consumers have incompatible needs.
- Find ad hoc spacing, color, typography, button, form, card, modal, and responsive treatments.
- Map shared browser hooks and make sure visual changes preserve their behavioral contracts.

### Rendered Audit
Exercise the major workflows with representative data:

- Daily control and area drill-down.
- Scene creation, editing, preview, activation, and power policy editing.
- Light and group configuration.
- Pico configuration and button assignment.
- Bridge setup, initial import, and reimport review.
- Application and integration settings.
- HomeKit pairing and maintenance surfaces.

For each workflow, inspect desktop and mobile layouts plus relevant empty, populated, editing, disabled, loading, error, and destructive states. Record repeated interaction patterns and places where visually similar controls behave differently.

### Classification
Classify each discovered pattern as:

- **Keep:** effective and suitable for broader reuse.
- **Improve:** directionally correct but incomplete.
- **Consolidate:** multiple implementations should become one pattern.
- **Replace:** the existing pattern encodes poor interaction or visual decisions.
- **Page-specific:** legitimately unique and not a design-system candidate.

The audit should maintain a workflow inventory, a reusable-pattern inventory, and evidence for future slices and reusable primitives. It should not produce a page-by-page cosmetic punch list detached from user workflows.

## Browser And Data Workflow

- Use the local application for implementation and fast iteration.
- Prefer representative production-shaped data so complex nesting, long names, mixed capabilities, disabled entities, and populated configuration states are exercised.
- Use the in-app browser for repeatable viewport and interaction inspection.
- Use Chrome when an existing authenticated session or real external-system state is specifically necessary.
- Treat production as a final reality check, not the primary design sandbox.
- Capture screenshots when they help compare alternatives or preserve evidence, but do not make screenshot exchange the primary feedback mechanism.

## Verification

Application behavior and visual quality need different evidence:

- LiveView and component tests should protect interaction semantics, persistence, validation, conditional states, and capability boundaries.
- Browser inspection should verify hierarchy, density, responsive behavior, transient states, focus order, keyboard use, touch targets, labels, contrast, and console health.
- Test at representative narrow mobile, tablet, and desktop widths.
- Verify both realistic dense data and minimal or empty data.
- Prefer semantic assertions over CSS-selector details that make refactoring unnecessarily expensive.
- Do not introduce broad pixel-perfect screenshot testing by default. Add targeted visual regression coverage only for stable, high-value layouts where it will provide more signal than maintenance cost.

## Component Gallery
A small internal component-gallery page may become valuable once enough shared primitives exist. It should demonstrate supported variants and interaction states using real application components.

Do not build the gallery as the first task. Add it when maintaining primitives across real consumers becomes harder than maintaining the gallery itself.

## Rollout Strategy

- Improve one vertical slice at a time rather than attempting a single whole-app rewrite.
- Let each slice contribute reusable vocabulary for later slices.
- Migrate nearby consumers when a new shared pattern is clearly applicable and the expanded scope remains reviewable.
- Remove superseded CSS and components once their consumers have migrated; do not accumulate permanent legacy variants.
- Keep this document forward-looking by removing completed audit and implementation items as they land.

## Remaining Cross-Application Decisions
Ongoing rendered audits should provide enough evidence to decide:

- Which proven Config and bridge-review patterns should become reference components for unrelated workflows.
- Which workflow should become the next vertical slice.
- Which additional tokens and layout primitives will eliminate the most duplication.
- When a component gallery becomes worth maintaining.

These decisions should be made from the rendered application and actual workflows, not from the current stylesheet structure alone.

## Non-Goals

- Do not redesign every page in one branch.
- Do not preserve every existing visual pattern for compatibility.
- Do not create a complete abstract design system before improving real workflows.
- Do not replace behavioral tests with screenshots.
- Do not make source availability imply public network exposure.
