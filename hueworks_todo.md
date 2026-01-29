# HueWorks TODO & Development Roadmap

## Project Status: Phase 0 - Foundation & Vertical Slice

**Current State:** Import pipeline is functional with tests. Need to complete UI wizard, add test coverage, and implement core control functionality before moving to advanced features.

**Architecture Health:** ✅ Solid foundation, proper domain modeling, good test patterns established  
**Test Coverage:** ⚠️ ~25% (Target: 80%+)  
**Core Value Prop:** ❌ Group batching not yet implemented

---

## Critical Path: Foundation Completion

### 1. Test Coverage to 80%+ (HIGH PRIORITY)
**Status:** ~25% coverage, need comprehensive testing before building more features

- [ ] **Schema validation unit tests**
  - [ ] Light changeset validations (self-referential canonical_light, kelvin ranges)
  - [ ] Group changeset validations
  - [ ] Bridge changeset validations
  - [ ] Room changeset validations
  - [ ] Scene and SceneComponent changesets
  - [ ] All unique constraints tested
  - [ ] All Ecto relationship validations tested

- [ ] **Context module tests** (currently missing entirely)
  - [ ] `Hueworks.Lights` - list, get, update operations
  - [ ] `Hueworks.Groups` - group management
  - [ ] `Hueworks.Rooms` - room operations
  - [ ] `Hueworks.Scenes` - scene CRUD
  - [ ] Error cases and edge conditions

- [ ] **Control layer integration tests** (critical for core value prop)
  - [ ] Group command batching by bridge
  - [ ] Parallel execution across bridges
  - [ ] Partial failure handling
  - [ ] Bridge offline scenarios
  - [ ] Command timing verification (measure popcorning prevention)

- [ ] **Import pipeline edge cases**
  - [ ] Malformed JSON handling
  - [ ] Bridge timeout scenarios
  - [ ] Duplicate entity handling
  - [ ] Missing required fields
  - [ ] Re-import/resync behavior

### 2. Implement Core Control Functionality (HIGH PRIORITY)
**Status:** Control layer exists but clients are stubs returning `:ok`

- [ ] **Error handling infrastructure**
  - [ ] Define error types (`:bridge_offline`, `:network_error`, `:invalid_state`, etc.)
  - [ ] Consistent error return pattern across control modules
  - [ ] Error logging and telemetry hooks
  - [ ] User-friendly error messages

- [ ] **Hue control implementation**
  - [ ] Replace `HueClient` stubs with actual HTTP calls
  - [ ] Rate limiting awareness
  - [ ] Retry logic with exponential backoff
  - [ ] Group command optimization (single API call per group)
  - [ ] Integration tests with mock HTTP

- [ ] **Caseta control implementation**
  - [ ] Replace `CasetaClient` stubs with LEAP protocol
  - [ ] Connection management
  - [ ] Command queuing for reliability
  - [ ] Integration tests with mock SSL socket

- [ ] **Group command batching** (CORE VALUE PROPOSITION)
  - [ ] Detect lights on same bridge within group
  - [ ] Batch commands into single bridge API call
  - [ ] Parallel execution across different bridges
  - [ ] Timing coordination to prevent visible delay
  - [ ] Performance testing with 50+ lights
  - [ ] Document batching strategy in code

- [ ] **State synchronization foundation**
  - [ ] Poll bridge state on interval
  - [ ] Update database with physical state
  - [ ] Publish state changes via PubSub for LiveView
  - [ ] Handle bridge offline gracefully
  - [ ] Separate desired state from actual state (future enhancement)

### 3. Bridge Configuration Wizard UI (CURRENT FOCUS)
**Status:** Import pipeline works via CLI, needs user-friendly UI

- [ ] **Bridge addition wizard**
  - [ ] Step 1: Bridge type selection (Hue, Caseta, HA)
  - [ ] Step 2: Credential entry form
  - [ ] Step 3: Connection test with feedback
  - [ ] Step 4: Review import plan before execution
  - [ ] Step 5: Import execution with progress indicator
  - [ ] Step 6: Results review (success/warnings/errors)

- [ ] **Import review workflow**
  - [ ] Display normalized entities before materialization
  - [ ] Show room assignments with confidence indicators
  - [ ] Allow override/manual assignment
  - [ ] Highlight duplicates/conflicts
  - [ ] Accept/decline individual entities

- [ ] **Bridge management UI**
  - [ ] List all configured bridges with status
  - [ ] Edit bridge credentials
  - [ ] Re-test connection
  - [ ] Trigger re-import/resync
  - [ ] Delete bridge with cascade warning

### 4. Database Performance & Integrity (MEDIUM PRIORITY)
**Status:** Schema is functional but missing critical indices

- [ ] **Add database indices**
  - [ ] `CREATE INDEX lights_canonical_light_id ON lights(canonical_light_id)`
  - [ ] `CREATE INDEX lights_room_id ON lights(room_id)`
  - [ ] `CREATE INDEX lights_bridge_id ON lights(bridge_id)`
  - [ ] `CREATE INDEX groups_bridge_id_source_id ON groups(bridge_id, source_id)`
  - [ ] `CREATE INDEX group_lights_group_id ON group_lights(group_id)`
  - [ ] `CREATE INDEX group_lights_light_id ON group_lights(light_id)`
  - [ ] Document index strategy in migration comments

- [ ] **Schema refinement**
  - [ ] Review metadata usage - promote frequently-queried fields to columns
  - [ ] Centralize `source` enum definition (currently scattered)
  - [ ] Add database-level foreign key constraints
  - [ ] Consider cascade delete vs soft delete strategy

---

## Near-Term Features (After Foundation)

### Room Assignment Intelligence
**Status:** Room schema exists, derivation logic partially implemented

- [ ] **Room derivation algorithm**
  - [ ] Extract room matching logic into `Hueworks.Import.RoomDerivation` module
  - [ ] Implement confidence scoring for room matches
  - [ ] Handle HA room data when available
  - [ ] Cross-bridge room matching (same physical room, different bridges)
  - [ ] Write comprehensive tests for derivation logic

- [ ] **Room assignment UI**
  - [ ] Display suggested room assignments with confidence
  - [ ] Manual override interface
  - [ ] Bulk assignment operations
  - [ ] Unassigned lights view
  - [ ] Room creation/editing

- [ ] **Make HA integration optional**
  - [ ] System works without HA connection
  - [ ] HA data enhances room detection when available
  - [ ] Clear separation between native and HA-derived data

### Scene Definition & Activation
**Status:** Schema exists, no activation logic

- [ ] **Scene management UI**
  - [ ] Create/edit/delete scenes
  - [ ] Scene component definition (lights, states, transitions)
  - [ ] Scene organization within rooms
  - [ ] Scene preview/testing
  - [ ] Import scenes from bridges

- [ ] **Scene activation runtime**
  - [ ] Translate scene to light commands
  - [ ] Use group batching for coordinated activation
  - [ ] Transition timing coordination
  - [ ] Handle partial failures gracefully
  - [ ] Activation via UI controls
  - [ ] Activation logging/history

### Circadian/Adaptive Lighting
**Status:** Not started

- [ ] **Kelvin adjustment algorithm**
  - [ ] Sunrise/sunset calculation for location
  - [ ] Smooth CT curve throughout day
  - [ ] Per-room adaptive preferences
  - [ ] Manual override handling (disable adaptive when user adjusts)
  - [ ] Respect scene activations

- [ ] **Implementation**
  - [ ] Background process for time-based adjustments
  - [ ] Gradual transitions (not sudden jumps)
  - [ ] UI for adaptive lighting configuration
  - [ ] Enable/disable per room or per light

---

## Mid-Term Enhancements

### Import & Sync Improvements

- [ ] **Re-import/Resync functionality**
  - [ ] Detect newly added lights on bridges
  - [ ] Detect removed lights
  - [ ] Preserve user customizations (display_name, room_id, enabled)
  - [ ] Upsert strategy with conflict resolution
  - [ ] Track import history for audit trail

- [ ] **Bridge credential management**
  - [ ] Update IP address without re-import
  - [ ] Rotate API keys/tokens
  - [ ] Re-test connection after changes
  - [ ] Credential validation before save

- [ ] **Import idempotency**
  - [ ] Define clear upsert rules
  - [ ] Handle duplicate detection correctly
  - [ ] Preserve user edits vs bridge updates
  - [ ] Document import behavior

### Pico Button Integration

- [ ] **Button event runtime**
  - [ ] Move working LEAP subscription code into supervised GenServer
  - [ ] Handle button events (press, release, multi-tap)
  - [ ] Reliable reconnection on disconnect

- [ ] **Button configuration**
  - [ ] Database schema for button → action mappings
  - [ ] UI for configuring button bindings
  - [ ] Support scene activation from buttons
  - [ ] Support multi-button sequences

- [ ] **Alternative: HA bridge approach**
  - [ ] Document Pico → HA automation → HueWorks scene pattern
  - [ ] Provide example HA automation configs

---

## Long-Term Features & Quality

### Security Improvements

- [ ] **Credential protection**
  - [ ] Encrypt credentials at rest (use Cloak or similar)
  - [ ] File permissions on SQLite DB (chmod 600)
  - [ ] Secure backup strategy (don't leak credentials)
  - [ ] Move Lutron cert/key files to secure location
  - [ ] Consider OS keychain integration
  - [ ] Audit credential handling in logs

### Code Quality & Maintenance

- [ ] **Code cleanup**
  - [ ] Remove or document stub implementations in control layer
  - [ ] Clean up unused `Subscription` modules
  - [ ] Remove connection test exploration code
  - [ ] Document architectural decisions (ADRs)

- [ ] **Refactoring**
  - [ ] Extract Kelvin presentation logic from domain logic
  - [ ] Consider consolidating Mix tasks into hierarchical structure
  - [ ] Break large LiveView modules into components (when they emerge)
  - [ ] Centralize source enum definition

- [ ] **Testing improvements**
  - [ ] Add property-based tests with StreamData
  - [ ] Performance testing with 100+ lights
  - [ ] Load testing for concurrent control operations
  - [ ] Integration tests with real hardware (optional)

### Schema Evolution & Data Management

- [ ] **Migration strategy**
  - [ ] Define rollback procedures
  - [ ] Plan for removing fields (not just adding)
  - [ ] Schema versioning for import/export
  - [ ] Database migration testing process

- [ ] **Backup and restore**
  - [ ] Automated backup procedures
  - [ ] Restore validation
  - [ ] Backup encryption
  - [ ] Point-in-time recovery

### State Management & Resilience

- [ ] **Advanced state handling**
  - [ ] Separate desired state from physical state
  - [ ] Conflict resolution (UI change vs physical change)
  - [ ] State synchronization strategy
  - [ ] Optimistic updates with rollback

- [ ] **Error resilience**
  - [ ] Comprehensive error handling for all bridge interactions
  - [ ] Circuit breaker for failing bridges
  - [ ] Graceful degradation when bridges offline
  - [ ] Recovery from network failures

### UI/UX Polish

- [ ] **Performance**
  - [ ] Pagination/virtual scrolling for large light lists
  - [ ] Optimize LiveView updates
  - [ ] Loading states and skeletons
  - [ ] Optimistic UI updates

- [ ] **Usability**
  - [ ] Mobile-responsive design
  - [ ] Keyboard shortcuts for power users
  - [ ] Accessibility (ARIA labels, keyboard nav)
  - [ ] Dark mode support

- [ ] **Advanced features**
  - [ ] Bulk operations (multi-select lights)
  - [ ] Search and filter
  - [ ] Saved filter views
  - [ ] Custom dashboards

### Advanced Control Features

- [ ] **Automation & Intelligence**
  - [ ] Presence detection integration
  - [ ] Motion sensor support
  - [ ] Time-based automation rules
  - [ ] Vacation/away modes

- [ ] **Monitoring & Analytics**
  - [ ] Energy usage tracking
  - [ ] Light bulb lifetime tracking
  - [ ] Usage statistics per room
  - [ ] Firmware update notifications

- [ ] **Multi-home & Deployment**
  - [ ] Support multiple locations
  - [ ] Remote access strategy
  - [ ] User authentication
  - [ ] Multi-user support with permissions

---

## Research & Future Exploration

- [ ] **Additional bridge types**
  - [ ] Zigbee2MQTT integration (direct coordinator control)
  - [ ] Lutron RA2 Select support
  - [ ] Lutron RadioRA 3 support
  - [ ] LIFX, Nanoleaf, other platforms

- [ ] **Integration & API**
  - [ ] WebSocket API for external integrations
  - [ ] REST API for programmatic control
  - [ ] Home Assistant integration (bi-directional)
  - [ ] Voice assistant integration research

- [ ] **Client applications**
  - [ ] Mobile app considerations (React Native?)
  - [ ] Apple Watch complication
  - [ ] Desktop menubar app

---

## Critical Reminders

### Development Philosophy
- **Test-First:** Write tests before implementing features (already doing well!)
- **Vertical Slices:** Build complete end-to-end features, don't leave half-finished work
- **Close the Loop:** Finish import pipeline + wizard + control before adding advanced features
- **Type Specs:** Add @spec to all public functions (not consistently done yet)

### Quality Gates
- **80% test coverage minimum** - Enforce in CI
- **All tests passing** - No broken tests in main branch  
- **Credo clean** - No warnings before committing
- **Migration tested** - Test both up and down migrations

### Current Anti-Patterns to Avoid
- ❌ Adding features before testing existing code
- ❌ Using metadata map as dumping ground for structured data
- ❌ Stub implementations without clear TODO markers
- ❌ Building UI before backend logic is tested
- ❌ Skipping error handling "for now"

### Success Metrics for Phase 0 Completion
- [ ] Import wizard working end-to-end (add bridge, import, review, commit)
- [ ] Can control a group of 10+ lights without popcorning (measured!)
- [ ] 80%+ test coverage with meaningful tests
- [ ] All bridges can be added/tested/removed via UI
- [ ] State synchronization keeps UI in sync with physical lights
- [ ] Documentation for setup and deployment

---

## Notes & Decisions

**Why test coverage first?**  
Current code is well-structured but untested. Building more features on untested foundation creates technical debt. Writing tests now validates assumptions and catches bugs before they compound.

**Why focus on control before scenes/automation?**  
The core value proposition is "no popcorning." If group batching doesn't work perfectly, scenes and automation built on top will be disappointing. Prove the foundation first.

**Why wizard UI before advanced features?**  
CLI workflow is fine for development but blocks real-world testing and validation. A working wizard enables dogfooding the system with actual hardware in your home.

**Priority sequencing rationale:**
1. Tests catch bugs early, enable confident refactoring
2. Control proves core value prop and enables validation
3. Wizard enables real-world usage and feedback
4. Database indices prevent performance issues at scale
5. Everything else builds on this foundation

---

**Last Updated:** January 2025  
**Current Sprint Focus:** Test coverage + Bridge wizard UI  
**Next Sprint:** Core control implementation + group batching
