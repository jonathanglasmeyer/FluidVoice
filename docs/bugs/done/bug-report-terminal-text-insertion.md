# Bug Report: FluidVoice Unicode-Typing Triggers Select All (Cmd+A) in Claude Code Terminal

**Date:** 2025-01-06  
**Reporter:** User  
**Severity:** High  
**Component:** FluidVoice Unicode-Typing System / Claude Code Terminal Interface  

## Problem Description

When FluidVoice's Unicode-Typing system pastes transcribed text into Claude Code's terminal interface, it triggers a "Select All" behavior identical to pressing Cmd+A. This causes the entire page/screen content to be selected instead of inserting the transcribed text at the cursor position. The issue occurs consistently regardless of cursor position or field state (empty or containing text).

## Expected Behavior

- Text should be inserted at the current cursor position
- No text selection should occur
- Normal text editing behavior should apply

## Actual Behavior

- Entire page/screen content gets selected (identical to Cmd+A behavior)
- Transcribed text is not inserted at the intended cursor position
- Any existing content in the terminal gets selected and would be overwritten
- Issue occurs consistently with FluidVoice Unicode-Typing system
- Behavior suggests unintended Cmd+A keyboard shortcut is being triggered

## Reproduction Steps

1. Start FluidVoice with Unicode-Typing enabled
2. Open Claude Code terminal interface
3. Position cursor anywhere in a text field (empty or with existing content)
4. Use FluidVoice hotkey (⌘⇧Space) to transcribe speech
5. Observe in logs: `✅ Unicode-Typing paste successful`
6. Observe in terminal: Entire page content gets selected (Cmd+A behavior)
7. Transcribed text is not inserted at cursor position

## Evidence from Logs

```
2025-09-06 17:15:47.723 I  FluidVoice[98385:2670e4] [com.fluidvoice.app:App] 📊 PERF (parakeet-tts): Audio=3.4s, Words=12, Time=0.10s, RTF=0.03, ms/word=8, WPS=121.5
2025-09-06 17:15:47.723 I  FluidVoice[98385:260bd0] [com.fluidvoice.app:App] ✅ Transcription completed: Kannst du das mal versuchen, ein bisschen zu analy...
2025-09-06 17:15:47.723 I  FluidVoice[98385:260bd0] [com.fluidvoice.app:App] 🧪 DEBUG: Full transcription is [Kannst du das mal versuchen, ein bisschen zu analysieren und zu verstehen?]
2025-09-06 17:15:47.723 I  FluidVoice[98385:260bd0] [com.fluidvoice.app:App] 🔄 Auto-pasting transcribed text...
2025-09-06 17:15:47.724 I  FluidVoice[98385:260bd0] [com.fluidvoice.app:App] ✅ Unicode-Typing paste successful
2025-09-06 17:15:47.724 I  FluidVoice[98385:260bd0] [com.fluidvoice.app:App] ✅ Transcription completed successfully
```

FluidVoice reports successful Unicode-Typing paste, but Claude Code terminal exhibits Select All behavior.

## Environment

- **Platform:** macOS
- **FluidVoice:** Unicode-Typing system enabled
- **Target Application:** Claude Code built-in terminal
- **Paste Method:** Unicode-Typing (CGEvent-based text insertion)

## Root Cause Analysis

**Suspected Issue:** FluidVoice's Unicode-Typing system is inadvertently sending a Cmd+A (Select All) keyboard event before or during text insertion. This could be due to:

1. **Key Modifier Conflict**: Unicode-Typing CGEvent sequence incorrectly setting Command key modifier
2. **Timing Issue**: Race condition between key events causing Command key to be held during 'A' character insertion
3. **Claude Code Terminal Sensitivity**: Terminal interface interpreting Unicode-Typing events as keyboard shortcuts
4. **CGEvent Key Code Mapping**: Wrong key codes being sent that Claude Code interprets as Cmd+A

## Impact

- **High Severity**: Makes FluidVoice unusable with Claude Code terminal
- **User Experience**: All transcribed text triggers Select All, risking data loss
- **Workflow Disruption**: Forces manual typing instead of voice transcription
- **Productivity Loss**: Core FluidVoice functionality broken in primary development tool

## Workaround

- Disable Unicode-Typing in FluidVoice settings (if possible)
- Use standard Clipboard mode instead of Unicode-Typing for Claude Code
- Manually paste transcribed text from clipboard after transcription

## Priority

**High** - This makes FluidVoice's core functionality unusable with Claude Code, a primary development tool. The Select All behavior could cause data loss if users accidentally overwrite existing terminal content.

## Technical Investigation Needed

1. **Unicode-Typing Code Review**: Examine `Sources/PasteManager.swift` CGEvent generation
2. **Key Event Logging**: Add debug logging for all CGEvent key codes and modifiers
3. **Claude Code Compatibility**: Test with other terminal applications (iTerm2, Terminal.app)
4. **CGEvent Timing**: Investigate event timing and key modifier state management
5. **Alternative Paste Methods**: Consider fallback to standard clipboard paste for problematic applications

## Additional Notes

The fact that FluidVoice reports "✅ Unicode-Typing paste successful" while Claude Code exhibits Select All behavior suggests the issue is in the CGEvent key sequence generation, not the paste mechanism itself. The Unicode-Typing system may be inadvertently generating the Cmd+A key combination during text insertion.