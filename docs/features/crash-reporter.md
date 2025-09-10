# Crash Reporter Feature

## Overview
Privacy-safe crash reporter that automatically collects crash information locally without sending data anywhere.

## Implementation Plan

### Option A: Automatic Collection (Privacy-Safe)

**Components:**
- Mini crash reporter (PLCrashReporter or KSCrash in offline mode)
- Local storage: `~/Library/Application Support/FluidVoice/Crashes/`
- Menu/tray button "Show Crash Logs" → opens Finder to crash directory
- Manual sharing via Slack/Email by colleagues

**Advantages:**
- No system search required
- No Console.app dependency
- Full privacy control
- Easy sharing workflow

## Technical Details

### Storage Location
```
~/Library/Application Support/FluidVoice/Crashes/
├── crash_2025-01-15_14-30-22.crash
├── crash_2025-01-15_15-45-10.crash
└── README.txt (explains what these files are)
```

### Integration Points
- App delegate crash handling
- Menu bar item addition
- Finder integration for log access

## Privacy Considerations
- All data stays local
- No automatic transmission
- User controls when/how to share
- Clear documentation about what's collected

## User Experience
1. App crashes → crash report saved locally
2. User notices issue → clicks "Show Crash Logs" in menu
3. Finder opens to crash directory
4. User can share relevant .crash files with team

## Status
- [ ] Research crash reporting libraries
- [ ] Implement local crash collection
- [ ] Add menu integration
- [ ] Test functionality