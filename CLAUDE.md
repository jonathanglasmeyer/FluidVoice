# FluidVoice — Developer & AI Guidelines

## Debug & Logging

**Workflow:** 
1. `./build-dev.sh && FluidVoice-dev.app/Contents/MacOS/FluidVoice` (background: `run_in_background: true`)
2. `/usr/bin/log stream --predicate 'subsystem == "com.fluidvoice.app"' --info` 
3. `pkill -f FluidVoice`

**Kritisch:** 
- Nie `.build-dev/debug/FluidVoice` verwenden (Bundle-Struktur!)
- Immer `/usr/bin/log` (nicht `log`) mit `--info` Flag
- Debug Audio: `defaults write com.fluidvoice.app enableDebugAudioMode -bool true`
- **🚨 CRITICAL: ALWAYS use `.infoDev()` not `.info()` for ALL logging!** 
  - ✅ `logger.infoDev("message")` → visible in logs
  - ❌ `logger.info("message")` → shows as `<private>` 
  - Examples: Logger.app.infoDev(), Logger.audioInspector.infoDev()
  - **RULE: If AI adds ANY logger.info() it MUST be logger.infoDev()**
- Privacy Logs: Device names show as `<private>` - use `sudo log stream` for real names
- **🚨 AI niemals BashOutput für Logs:** User copy/pastet relevante Logs - spart Context Window  
- **🚨 BashOutput HARD LIMIT:** Max 10-20 lines output - niemals full log dumps (Context Bloat!)

## AI Testing Grenzen

**AI macht:** Code, Build, Logs, Umgebung vorbereiten, Implementation prüfen  
**User macht:** Hotkeys, UI, Audio/Speech, Permissions, End-to-End Testing

**AI darf NICHT:** User-Interaktionen simulieren, UI testen, Mikrofon/Speech validieren

## TCC Permissions & Attribution

**macOS Attribution Chain:** TCC prüft "responsible process" für Permissions  
**Problem:** Terminal → FluidVoice = Terminal braucht auch die Permission  
**Lösung A:** Aus Finder starten (Doppelklick FluidVoice-dev.app)  
**Lösung B:** Terminal Mikrofonerlaubnis geben (System Settings → Privacy → Microphone)

**Dev Workflow:** Wenn du über Terminal startest, muss dein Terminal (Ghostty/iTerm/etc.) auch Mikrofon-Permission haben, sonst `AVAuthorizationStatus: .denied`

## Permission Reset 

**NIE:** `tccutil reset Accessibility` (zerstört alle Apps!)  
**OK:** `tccutil reset Accessibility com.fluidvoice.app` (nur FluidVoice)  
**Grund:** Broad resets zerstören alle User-Permissions!

## Build & Signing

**Dev:** `./build-dev.sh` oder `fv-build`  
**Release:** `CODE_SIGN_IDENTITY="EFC93994F7FFF5A8EC85E5CD41174673C1EDCD25" ./build.sh`  
**Bundle ID:** com.fluidvoice.app  
**Nie:** `swift build` verwenden

**🚨 CRITICAL BUILD RULE:** `./build-dev.sh` cleans FluidVoice-dev.app BEFORE building  
**Grund:** Prevents running stale builds when recent build failed (lines 46-49), ensures fresh binary  
**AI Must:** Always use `./build-dev.sh` (never manual swift build), cleanup happens upfront

## Dependencies

**Core:** SwiftUI+AppKit, AVFoundation, Alamofire, WhisperKit, HotKey, KeychainAccess  
**Pipeline:** AVFoundation → WhisperKit/APIs → Clipboard  
**Local AI:** WhisperKit (CoreML), Parakeet (MLX/Python subprocess)  
**Async:** Swift Concurrency preferred über Combine  
**Regel:** Existing Dependencies verwenden, keine neuen einführen

## Code Rules

**Swift:** 5.7+, macOS 14+, kein `!`, `guard let`, value types first  
**Memory:** `[weak self]`, UI auf main actor, functions ≤40 lines  
**Concurrency:** `async`/`await` preferred, actors for shared state, cleanup in `deinit`  
**Style:** Existing patterns folgen, self-documenting code

## Testing

**Framework:** XCTest für alle Logic  
**Coverage:** `swift test --parallel --enable-code-coverage`  
**Mocks:** External dependencies isolieren  
**Tests:** Edge cases, error paths, concurrency

## Feature & Bug Documentation

**Features:** Always check `docs/features/README.md` for current status  
**Completed:** Listed in `docs/features/done/` directory  
**Bugs:** Document in `docs/bugs/` (if exists) or search codebase for TODO/FIXME  
**AI Rule:** Never guess features/bugs - always read documentation first

## Status Reports

**When:** End of major sessions, before context window fills, complex blockers  
**Location:** `docs/reports/YYYY-MM-DD-session-NN-[title].md`  
**Format:** Date, Session title, Main accomplishment, Current issue, File changes, Next priorities  
**Focus:** Write for zero-context AI - include system state, dependencies, debug workflow

## Audio Files

**Location:** `FileManager.default.temporaryDirectory` (system temp)  
**Pattern:** `recording_[timestamp].m4a` (Sources/AudioRecorder.swift:78)  
**Example Path:** `/var/folders/bk/_pv4zm0s3mjc4wmcgv3vw5y00000gp/T/`  
**Find Command:** `find /var/folders -name "recording_*.m4a" -type f 2>/dev/null`  
**Access:** App has "Show Audio File" button for transcription errors (Sources/ContentView.swift:830)

## Quick Commands

- `fv-build` - Fast development build
- `fv-test` - Run tests 
- `fv-clean` - Clean build artifacts
- `source .build-config` - Load build environment

## Vocabulary Mapping Requests

**Einfaches Format:** Schreib einfach `falsch -> richtig` und AI fügt es zur vocabulary.jsonc hinzu.

**Examples:**
- `cloud code -> Claude Code` 
- `ClaudeMD -> CLAUDE.md`
- `i o s -> iOS`

**AI Action:** Automatisch zur `~/.config/fluidvoice/vocabulary.jsonc` hinzufügen mit passender Case-Mode und Kategorie.