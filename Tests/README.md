# FluidVoice Test Suite

XCTest suite for the FluidVoice app (Parakeet via FluidAudio → FastVocabularyCorrector → paste).

## Running

```bash
# All tests (always xcrun: a swiftly toolchain in PATH breaks with -target-arch-variant)
xcrun swift test --build-path .build-dev

# One suite / one test
xcrun swift test --build-path .build-dev --filter AudioRecorderTests
xcrun swift test --build-path .build-dev --filter AudioRecorderTests/testStartRecordingUpdatesState

# Memory errors (use-after-free etc.); separate build path, takes a full rebuild
xcrun swift test --build-path /tmp/fluidvoice-asan --sanitize=address --filter AudioRecorderTests
```

`just test` runs the suite with `--parallel`.

## Layout

| File | Covers |
|---|---|
| `AccessibilityPermissionManagerTests` | Accessibility check, permission request and alert flows (alerts answered by `AlertRecorder`) |
| `AppStatusTests` | Status enum and status view model |
| `AudioRecorderTests` | Recording state, audio level, file URLs, deinit cleanup; uses the real HAL input device |
| `DataManagerTests`, `DataManagerIntegrationTests` | SwiftData persistence of transcription records, retention |
| `FastVocabularyCorrectorTests`, `FastVocabularyCorrector_TDD_Tests` | Vocabulary correction (aliases, casing, punctuation) |
| `FillerSoundProcessorTests` | Filler word removal (German/English) |
| `HotKeyManagerTests` | Global hotkey registration |
| `ParakeetServiceTests` | Parakeet transcription service |
| `PasteManagerTests` | SmartPaste permission handling and result notifications |
| `PermissionManagerTests` | Microphone/accessibility permission state machine |
| `SettingsViewTests` | Settings UserDefaults keys, microphone discovery, `RetentionPeriod` |
| `ShowAudioFileButtonTest` | "Show Audio File" error-alert button, only for transcription errors |
| `TranscriptionHistoryIntegrationTests`, `TranscriptionHistoryViewTests`, `TranscriptionRecordTests` | History storage, search, view |
| `TranscriptionTypesTests` | Provider/model enums |
| `UtilityTests` | File, encoding and timer helpers |
| `WindowControllerTests` | Window management |

## Rules

- **No modals under XCTest.** A `runModal()` blocks the whole run. Guard UI with `NSClassFromString("XCTestCase") != nil` (see `PermissionManager`, `PasteManager`) or inject the presenter (see `AccessibilityPermissionManager.init(presentAlert:)`).
- **One `measure` block per test.** A second call throws; in `async` tests that aborts the process.
- **Drain the main queue before observing notifications.** Results posted via `DispatchQueue.main.async` otherwise leak into the next test (see `PasteManagerTests.setUp`).
- **`isRecording` updates asynchronously.** `AudioRecorder.startRecording()` sets it via `main.async`; wait on `$isRecording` instead of reading it right away.
- **Never capture `self` in escaping closures from `deinit`.** They run after deallocation.
- Clean up every UserDefaults key a test writes in `tearDown`.
