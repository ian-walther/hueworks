# HueWorks TODO & Development Roadmap

## Project Status: Phase 0 - Foundation & Vertical Slice

**Current State:** Import pipeline is functional with tests. Need to complete UI wizard, add test coverage, and implement core control functionality before moving to advanced features.

**Architecture Health:** ✅ Solid foundation, proper domain modeling, good test patterns established  
**Test Coverage:** ⚠️ ~25% (Target: 80%+)  
**Core Value Prop:** ❌ Group batching not yet implemented

---

## Critical Path: Foundation Completion

### 1. Test Coverage to 80%+ (HIGH PRIORITY) — [planning/test-coverage.md](planning/test-coverage.md)
**Status:** ~25% coverage, need comprehensive testing before building more features

- See [planning/test-coverage.md](planning/test-coverage.md) for detailed test tasks.

### 2. Implement Core Control Functionality (HIGH PRIORITY) — [planning/control-batching.md](planning/control-batching.md)
**Status:** Control layer exists but clients are stubs returning `:ok`

- See [planning/control-batching.md](planning/control-batching.md) for detailed tasks.

### 3. Bridge Configuration Wizard UI (CURRENT FOCUS) — [planning/import-review-ui.md](planning/import-review-ui.md)
**Status:** Import pipeline works via CLI, needs user-friendly UI

- See [planning/import-review-ui.md](planning/import-review-ui.md) for detailed tasks.

### 4. Database Performance & Integrity (MEDIUM PRIORITY) — [planning/db-integrity.md](planning/db-integrity.md)
**Status:** Schema is functional but missing critical indices

- See [planning/db-integrity.md](planning/db-integrity.md) for detailed tasks.

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

### Import & Sync Improvements — [planning/import-resync.md](planning/import-resync.md)

- See [planning/import-resync.md](planning/import-resync.md) for detailed tasks.

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
