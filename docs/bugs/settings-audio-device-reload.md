# Settings Audio Device Reload Bug

**Date**: 2025-09-06  
**Component**: SettingsView, AudioDeviceManager  
**Severity**: Medium  
**Status**: ✅ **RESOLVED**  

## Problem

When opening the Settings sheet, audio devices are not automatically reloaded. This means that if a user connects/disconnects audio devices while the app is running, they won't see the updated device list in Settings without manually restarting the app.

## Expected Behavior

- Opening Settings sheet should automatically refresh the available audio devices
- Users should see newly connected devices immediately
- Disconnected devices should be removed from the list

## Current Behavior

- Audio devices are only loaded once at app startup
- Settings sheet shows stale device list
- Users must restart app to see device changes

## Technical Details

- Need to trigger device enumeration when Settings sheet opens
- Should integrate with existing AudioDeviceManager
- Consider using `.onAppear` or similar SwiftUI lifecycle method

## ✅ Solution Implemented

**Changes Made:**

1. **AudioDeviceManager.swift:47-56** - Added `getAllAvailableDevices()` method that:
   - Creates new AVCaptureDevice.DiscoverySession to get fresh device list
   - Logs device count for debugging
   - Returns updated device array

2. **SettingsView.swift:738** - Modified `loadAvailableMicrophones()` to:
   - Use centralized AudioDeviceManager.shared.getAllAvailableDevices()
   - Gets called automatically on each Settings sheet open via existing onAppear

**Behavior After Fix:**
- ✅ Opening Settings sheet automatically refreshes audio device list
- ✅ Newly connected devices appear immediately
- ✅ Disconnected devices are removed from picker
- ✅ No app restart required for device changes

**Files Modified:**
- `Sources/SettingsView.swift:738` - Updated loadAvailableMicrophones() method
- `Sources/AudioDeviceManager.swift:47-56` - Added getAllAvailableDevices() method