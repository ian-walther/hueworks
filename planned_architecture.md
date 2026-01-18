# Planned Architecture

This document captures the planned architecture direction before full automation work begins. The goal is to separate intent, physical state, and execution so the system can compute optimal plans (for example, minimizing Zigbee traffic).

## Core Concepts

### Intent (Desired State)
- What the system wants to be true.
- Example: a scene sets a group to 30 percent at 3000K.
- Expressed in Hueworks domain terms, not tied to Hue/HA/Caseta APIs.

### Observed State (Physical State)
- What bridges report right now.
- Derived from Hue SSE, HA WebSocket events, Caseta LEAP updates.
- May be delayed or incomplete.

### Planner / Diff Engine
- Computes a plan from desired vs observed state and topology.
- Outputs the smallest list of actions to reach desired state.
- Where Zigbee optimizations live (group-first commands, minimizing fan-out).

### Execution / Control
- Takes a plan and runs it against the correct bridge driver.
- Deterministic and minimal logic.

### Feedback Loop
- Observed updates reconcile intent vs reality.
- Lets the UI converge even when devices are slow or offline.

## Proposed Modules

### Hueworks.Control.State
- Stores desired and observed state in ETS/GenServer.
- UI writes desired state here.

### Hueworks.Plan
- Pure functions for planning.
- API shape:
  - plan(desired, observed, topology) -> list of actions

### Hueworks.Control.*
- Bridge-specific command execution (Hue, HA, Caseta).
- Takes actions from Hueworks.Plan.

### Hueworks.Domain
- Schemas and topology helpers.
- Group memberships and canonical mappings.

## Execution Flow

1. UI updates desired state.
2. Planner computes minimal actions.
3. Control executes actions per bridge.
4. Observed state updates reconcile with desired state.

## Notes

- Planning can start simple: compare desired vs observed and issue direct actions.
- Group optimizations can be layered in later.
- Keep the planner pure to make it testable.
