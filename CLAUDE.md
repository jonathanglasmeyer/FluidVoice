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

## AI Testing Grenzen

**AI macht:** Code, Build, Logs, Umgebung vorbereiten, Implementation prüfen  
**User macht:** Hotkeys, UI, Audio/Speech, Permissions, End-to-End Testing

**AI darf NICHT:** User-Interaktionen simulieren, UI testen, Mikrofon/Speech validieren

## Permission Reset 

**NIE:** `tccutil reset Accessibility` (zerstört alle Apps!)  
**OK:** `tccutil reset Accessibility com.fluidvoice.app` (nur FluidVoice)  
**Grund:** Broad resets zerstören alle User-Permissions!

## Build & Signing

**Dev:** `./build-dev.sh` oder `fv-build`  
**Release:** `CODE_SIGN_IDENTITY="EFC93994F7FFF5A8EC85E5CD41174673C1EDCD25" ./build.sh`  
**Bundle ID:** com.fluidvoice.app  
**Nie:** `swift build` verwenden

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

## Status Reports

**When:** End of major sessions, before context window fills, complex blockers  
**Location:** `docs/reports/YYYY-MM-DD-session-NN-[title].md`  
**Format:** Date, Session title, Main accomplishment, Current issue, File changes, Next priorities  
**Focus:** Write for zero-context AI - include system state, dependencies, debug workflow

## Quick Commands

- `fv-build` - Fast development build
- `fv-test` - Run tests 
- `fv-clean` - Clean build artifacts
- `source .build-config` - Load build environment