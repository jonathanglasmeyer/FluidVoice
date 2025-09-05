# FluidVoice User Stories

Collection of user stories driving FluidVoice feature development.

## Epic: Hotkey Improvements

### Story: Fn Key Support
**ID**: US-001  
**Priority**: High  
**Status**: Planned

**As a** productivity user  
**I want** to use the Fn key as my recording hotkey  
**So that** I can trigger recordings with a single, easily accessible key

**Acceptance Criteria:**
- Fn key can be selected as global hotkey in Settings
- Fn key press starts/stops recording based on current mode
- Works when FluidVoice is not the active application
- Clear permission setup flow for Input Monitoring

**Notes:**
- Competitive parity with Whisper Flow
- Single-key operation preferred by many users
- Requires macOS Input Monitoring permission

---

## Epic: User Experience

### Story: Simplified Setup
**ID**: US-002  
**Priority**: Medium  
**Status**: Backlog

**As a** new user  
**I want** a streamlined first-run experience  
**So that** I can start transcribing quickly without complex setup

**Current Issues:**
- Complex "Quiet Setup" dialog with nested boxes
- Too many configuration options on first run
- Over-engineered setup flow

**Acceptance Criteria:**
- One-screen welcome with essential settings only
- Optional advanced setup for power users
- Default settings work for majority use cases

---

## Epic: Accessibility

### Story: Single-Key Operation
**ID**: US-003  
**Priority**: High  
**Status**: Related to US-001

**As a** user with mobility constraints  
**I want** to trigger recordings without key combinations  
**So that** I can use the app with minimal finger movement

**Acceptance Criteria:**
- Single Fn key press triggers recording
- No modifier key combinations required
- Clear visual feedback when recording active

---

## Epic: Competitive Features

### Story: Feature Parity
**ID**: US-004  
**Priority**: High  
**Status**: In Progress

**As a** user evaluating transcription apps  
**I want** FluidVoice to have the same core features as alternatives  
**So that** I don't have to compromise on functionality

**Gap Analysis:**
- ❌ Fn key hotkey (Whisper Flow has this)
- ✅ Multiple transcription services
- ✅ Local processing options
- ✅ History management
- ❓ Export options (need to verify vs competitors)

---

## Future User Stories

### Story: Touch Bar Integration
**ID**: US-005  
**Priority**: Low  
**Status**: Future

**As a** MacBook Pro user with Touch Bar  
**I want** Touch Bar controls for recording  
**So that** I have quick access without hotkeys

### Story: Multi-Language Support
**ID**: US-006  
**Priority**: Medium  
**Status**: Future  

**As an** international user  
**I want** FluidVoice UI in my language  
**So that** I can use the app comfortably

### Story: Team Collaboration
**ID**: US-007  
**Priority**: Low  
**Status**: Future

**As a** team member  
**I want** to share transcriptions with colleagues  
**So that** we can collaborate on meeting notes

---

## User Feedback Integration

### Recent Feedback
- "mh ok also `Fn` kann sie schon mal nich als hotkey?" - Priority: High → US-001
- UI feedback: "kleine dev-macht-ui aspekte" - Priority: Medium → US-002

### Feedback Sources
- Direct user testing
- GitHub issues (if public)
- User support requests
- Competitive analysis

---

**Next Review**: Weekly during development sprints  
**Last Updated**: 2025-09-04  
**Owner**: Development Team