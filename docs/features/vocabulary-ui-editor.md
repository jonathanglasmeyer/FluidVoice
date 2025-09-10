# Vocabulary UI Editor

## Overview
A graphical user interface for managing FluidVoice's vocabulary replacement configuration, replacing the current manual JSON editing workflow with an intuitive UI.

## Current State
Currently, vocabulary replacements are managed through manual editing of `~/.config/fluidvoice/vocabulary.jsonc`:
- Users must understand JSON syntax
- No validation of input format
- No search/filtering capabilities
- Risk of syntax errors breaking the configuration
- No visual feedback on applied rules

## Proposed Feature

### Core Functionality
1. **Vocabulary Management Interface**
   - Add new vocabulary entries with canonical form and misrecognitions
   - Edit existing entries inline
   - Delete unwanted entries
   - Drag-and-drop reordering within categories

2. **Smart Input Features**
   - Auto-suggest common misrecognitions based on canonical term
   - Case mode selection (upper/mixed/exact) with preview
   - Real-time validation of entries
   - Duplicate detection and warnings

3. **Organization & Search**
   - Category-based grouping (Technical Acronyms, Platforms, Languages, etc.)
   - Search/filter vocabulary entries
   - Bulk operations (delete multiple, change case modes)
   - Import/export capabilities

### UI Design Concepts

#### Main Interface
```
┌─ Vocabulary Editor ──────────────────────────────────────┐
│ [+ Add Entry] [Import] [Export] [Test Mode]    [Search▼] │
├──────────────────────────────────────────────────────────┤
│ ▼ TECHNICAL ACRONYMS (12 entries)                       │
│   API          → ["a p i", "api", "a.p.i"]      [UPPER] │
│   CLI          → ["c l i", "cli", "c.l.i"]      [UPPER] │
│   ...                                                    │
│                                                          │
│ ▼ PLATFORMS & SERVICES (8 entries)                      │
│   GitHub       → ["git hub", "github", "git-hub"] [MIXED]│
│   Claude Code  → ["cloud code", "clod code"]     [MIXED] │
│   ...                                                    │
└──────────────────────────────────────────────────────────┘
```

#### Add/Edit Entry Dialog
```
┌─ Edit Vocabulary Entry ──────────────────────────────────┐
│ Canonical Form: [DVS                           ]         │
│ Case Mode:      (•) UPPER  ( ) Mixed  ( ) Exact         │
│ Preview:        DVS                                      │
│                                                          │
│ Misrecognitions:                                         │
│ • [d vs                    ] [×]                         │
│ • [d v s                   ] [×]                         │
│ • [D VS                    ] [×]                         │
│ • [D V S                   ] [×]                         │
│   [+ Add misrecognition]                                 │
│                                                          │
│ Category: [Technical Acronyms        ▼]                 │
│                                                          │
│                              [Cancel] [Save]            │
└──────────────────────────────────────────────────────────┘
```

### Technical Implementation

#### UI Framework
- **SwiftUI** for native macOS interface
- **Settings-style** window (similar to System Preferences)
- **Dock integration** or menu bar access

#### Data Management
- **Live editing** of vocabulary.jsonc
- **Atomic saves** to prevent corruption
- **Backup creation** before modifications
- **Real-time validation** with error highlighting

#### Integration Points
- **Settings window** as new tab/section
- **Menu item** in main app menu: "Vocabulary Editor..."
- **Keyboard shortcut** for quick access
- **Context menu** integration for adding terms from transcriptions

### User Workflows

#### Adding New Terms
1. User clicks "Add Entry" or uses keyboard shortcut
2. Dialog opens with smart defaults based on clipboard/selection
3. User enters canonical form, system suggests case mode
4. User adds common misrecognitions (with suggestions)
5. System validates and saves to vocabulary.jsonc

#### Bulk Management
1. User selects multiple entries via checkboxes
2. Bulk operations: delete, change category, export subset
3. Confirmation dialog for destructive operations
4. Progress indicator for large operations

#### Testing Mode
1. Toggle "Test Mode" to simulate transcription
2. Type or paste text with known vocabulary issues
3. Real-time preview showing applied corrections
4. Identify gaps in current vocabulary coverage

### Benefits
- **Lower barrier to entry** for vocabulary customization
- **Reduced errors** through input validation
- **Better organization** with categorization and search
- **Faster iteration** on vocabulary improvements
- **Visual feedback** on correction rules

### Implementation Priority
- **Phase 1**: Basic CRUD operations with simple list interface
- **Phase 2**: Advanced features (categories, search, bulk operations)
- **Phase 3**: Smart suggestions and testing mode
- **Phase 4**: Import/export and integration features

### Success Metrics
- Reduced time to add new vocabulary entries
- Fewer JSON syntax errors in vocabulary.jsonc
- Increased user customization of vocabulary
- Positive user feedback on ease of use

## Related Files
- `~/.config/fluidvoice/vocabulary.jsonc` - Configuration file
- Potential new files:
  - `Sources/VocabularyEditor/` - UI implementation
  - `Sources/VocabularyManager.swift` - Data management
  - `Sources/VocabularyValidation.swift` - Input validation

## Notes
This feature would significantly improve the user experience for vocabulary customization, making FluidVoice more accessible to non-technical users while providing power users with advanced management capabilities.