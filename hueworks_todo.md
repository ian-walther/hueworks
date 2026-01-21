# HueWorks TODO & Future Considerations

## Current Focus (In Progress)

### Import Pipeline Refactor
- [ ] Build modular, testable import pipeline
  - [ ] Raw JSON fetch (in-memory for UI, exportable for CLI)
  - [ ] Extract lights from vendor JSON
  - [ ] Extract groups from vendor JSON
  - [ ] Persist to database
- [ ] Write unit tests using JSON fixtures from real bridges
- [ ] Mix tasks for each pipeline step (fetch, extract, persist)
- [ ] UI workflow that pipes data in-memory through steps

### Bridge Configuration UI
- [ ] Wizard-style UX for adding bridges
  - [ ] Step 1: Enter credentials
  - [ ] Step 2: Test connection
  - [ ] Step 3: Import entities
  - [ ] Step 4: Review results
- [ ] Per-bridge import status display
- [ ] Allow partial import success (some bridges succeed, others fail)

### Room Assignment
- [ ] Import room list from HA (when available)
- [ ] Link HA entities to native Hue/Caseta entities for room propagation
- [ ] Derivation logic that works regardless of import order
- [ ] UI to review/accept/decline room suggestions
- [ ] Support manual room assignment for all lights
- [ ] Make HA integration optional (not mandatory)

## Near-Term (Next Up)

### Scene Definition & Management
- [ ] UI for creating/editing scenes
- [ ] Scene component definition (which lights, what states)
- [ ] Scene organization within rooms
- [ ] Scene testing/preview functionality

### Scene Activation
- [ ] Translate scene definitions into coordinated light commands
- [ ] Batch command execution to prevent popcorning
- [ ] Handle partial failures gracefully
- [ ] Scene activation via UI controls

### Circadian/Adaptive Lighting
- [ ] Algorithm for CT adjustment over time
- [ ] Sunrise/sunset calculation
- [ ] Per-room/per-scene adaptive lighting preferences
- [ ] Manual override handling

## Mid-Term (Future Enhancements)

### Import & Sync Improvements
- [ ] **Re-import/Resync functionality**
  - [ ] Pull in newly added lights from bridges
  - [ ] Detect removed lights
  - [ ] Preserve user customizations (display names, room assignments, enabled state)
  - [ ] Upsert strategy with conflict resolution
- [ ] **Bridge credential updates**
  - [ ] Allow changing bridge IP address
  - [ ] Allow updating credentials
  - [ ] Re-test connection after changes
- [ ] **Import idempotency**
  - [ ] Define upsert strategy (what gets preserved vs updated)
  - [ ] Handle duplicate detection correctly
  - [ ] User edit preservation (display_name, room_id, enabled)

### Pico Button Integration
- [ ] Move working LEAP button subscription code into supervised GenServer
- [ ] Button event handling runtime
- [ ] Database schema for button → action bindings
- [ ] UI for configuring button bindings
- [ ] Alternative: HA scene bridge (Pico → HA automation → HueWorks scene)

### State Management
- [ ] Separate desired state from physical state
- [ ] State synchronization strategy
- [ ] Handle bridge offline scenarios
- [ ] Keep UI in sync with reality
- [ ] Polling vs event subscription for state updates

### Group Control Enhancement
- [ ] Implement robust group command batching
- [ ] Optimize command timing to eliminate popcorning
- [ ] Group control testing with real hardware
- [ ] Performance measurement and optimization

## Long-Term (Nice to Have)

### Security Improvements
- [ ] **Credential storage security**
  - [ ] Evaluate encryption at rest for credentials
  - [ ] File permissions on SQLite DB (chmod 600)
  - [ ] Secure backup strategy (don't leak credentials)
  - [ ] Better storage for Lutron cert/key files (currently in project folder, gitignored)
  - [ ] Consider secure credential vault or OS keychain integration

### Schema Evolution
- [ ] Strategy for adding new fields to existing tables
- [ ] Backfill approach (re-import vs migration vs manual)
- [ ] Versioning for import/export formats
- [ ] Database migration testing

### Error Handling & Resilience
- [ ] Comprehensive error handling for all bridge interactions
- [ ] Retry logic with exponential backoff
- [ ] User-friendly error messages
- [ ] Logging and debugging infrastructure
- [ ] Recovery from bridge disconnections

### Testing & Quality
- [ ] Expand test coverage to 80%+
- [ ] Integration test strategy (without hitting real bridges)
- [ ] Performance testing with large light counts (100+)
- [ ] Edge case coverage (network failures, malformed responses)

### UI/UX Polish
- [ ] Refactor large LiveView files into smaller components
- [ ] Pagination/virtual scrolling for large light lists
- [ ] Mobile-responsive design
- [ ] Loading states and optimistic updates
- [ ] Keyboard shortcuts for power users

### Advanced Features
- [ ] Presence detection integration
- [ ] Motion sensor support
- [ ] Time-based automation rules
- [ ] Vacation/away modes
- [ ] Energy usage tracking
- [ ] Light bulb lifetime tracking
- [ ] Firmware update notifications

## Technical Debt & Maintenance

- [ ] Add database indices on commonly-queried fields
- [ ] Extract validation logic from large changesets
- [ ] Document architectural decisions
- [ ] API documentation for public modules
- [ ] Deployment guide
- [ ] Backup and restore procedures
- [ ] Performance profiling and optimization

## Research & Exploration

- [ ] Zigbee2MQTT integration (for direct coordinator control)
- [ ] Support for additional bridge types (RA2 Select, RadioRA 3)
- [ ] WebSocket API for external integrations
- [ ] Mobile app considerations
- [ ] Multi-home support (multiple locations)

---

## Notes

- **Priority**: Focus on current work before moving to near-term items
- **Philosophy**: Build testable, modular pieces that can be composed
- **Sequencing**: Each phase builds on the previous - don't skip ahead
- **Testing**: Write tests as you build new features, not after
- **User Experience**: Make assumptions transparent, allow opt-out where appropriate
