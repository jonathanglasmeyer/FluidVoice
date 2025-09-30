import Foundation
import AppKit
import HotKey

class HotKeyManager {
    private var hotKey: HotKey?
    private var modifierKeyMonitor: Any?
    private var localModifierKeyMonitor: Any?
    private let onHotKeyPressed: () -> Void

    // Modifier key dual-mode state (tap vs hold)
    private enum ModifierKeyState {
        case idle
        case tapPending      // Just pressed, timer running to detect tap vs hold
        case holdRecording   // Timer expired, in push-to-talk mode
        case toggleRecording // Quick tap detected, recording until next tap
    }

    private var modifierKeyState: ModifierKeyState = .idle
    private var modifierKeyTimer: Timer?
    private var currentKeyCode: UInt16?
    private var currentModifierFlag: NSEvent.ModifierFlags?

    // Modifier key mapping (name -> keyCode + flag)
    private let modifierKeyMap: [String: (keyCode: UInt16, flag: NSEvent.ModifierFlags)] = [
        "Fn": (63, .function),
        "Right Option": (61, .option),
        "Left Option": (58, .option),
        "Right Command": (54, .command),
        "Left Command": (55, .command),
        "Right Shift": (60, .shift),
        "Left Shift": (56, .shift),
        "Right Control": (62, .control),
        "Left Control": (59, .control)
    ]
    
    init(onHotKeyPressed: @escaping () -> Void) {
        self.onHotKeyPressed = onHotKeyPressed
        setupObservers()
        setupInitialHotKey()
    }
    
    private func setupObservers() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(updateHotKey),
            name: .updateGlobalHotkey,
            object: nil
        )
    }
    
    private func setupInitialHotKey() {
        let savedHotkey = UserDefaults.standard.string(forKey: "globalHotkey") ?? "Right Option"
        setupHotKeyFromString(savedHotkey)
    }
    
    @objc private func updateHotKey(_ notification: Notification) {
        if let newHotkeyString = notification.object as? String {
            setupHotKeyFromString(newHotkeyString)
        }
    }
    
    private func setupHotKeyFromString(_ hotkeyString: String) {
        // Clear existing hotkey
        clearHotkey()

        // Check if it's a single modifier key
        if let (keyCode, flag) = modifierKeyMap[hotkeyString] {
            setupModifierKeyMonitor(keyCode: keyCode, flag: flag)
            Logger.app.infoDev("Hotkey configured: \(hotkeyString)")
        } else {
            // Parse the hotkey string and set up new hotkey
            let (key, modifiers) = parseHotkeyString(hotkeyString)

            if let key = key {
                hotKey = HotKey(key: key, modifiers: modifiers)
                hotKey?.keyDownHandler = { [weak self] in
                    self?.onHotKeyPressed()
                }
                Logger.app.infoDev("Hotkey configured: \(hotkeyString)")
            } else {
                Logger.app.infoDev("Failed to parse hotkey: \(hotkeyString)")
            }
        }
    }
    
    private func clearHotkey() {
        hotKey = nil
        if let monitor = modifierKeyMonitor {
            NSEvent.removeMonitor(monitor)
            modifierKeyMonitor = nil
        }
        if let monitor = localModifierKeyMonitor {
            NSEvent.removeMonitor(monitor)
            localModifierKeyMonitor = nil
        }
        modifierKeyTimer?.invalidate()
        modifierKeyTimer = nil
        modifierKeyState = .idle
        currentKeyCode = nil
        currentModifierFlag = nil
    }

    private func setupModifierKeyMonitor(keyCode: UInt16, flag: NSEvent.ModifierFlags) {
        currentKeyCode = keyCode
        currentModifierFlag = flag

        // Global monitor: catches events from other apps
        modifierKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.flagsChanged]) { [weak self] event in
            if event.keyCode == keyCode {
                self?.handleModifierKeyEvent(event, flag: flag)
            }
        }

        // Local monitor: catches events from FluidVoice itself (e.g., Welcome window)
        localModifierKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged]) { [weak self] event in
            if event.keyCode == keyCode {
                self?.handleModifierKeyEvent(event, flag: flag)
            }
            return event
        }
    }

    private func handleModifierKeyEvent(_ event: NSEvent, flag: NSEvent.ModifierFlags) {
        let keyPressed = event.modifierFlags.contains(flag)

        // Dispatch to main queue for thread safety
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            if keyPressed && self.modifierKeyState == .idle {
                // Key pressed - start recording and timer to detect tap vs hold
                self.modifierKeyState = .tapPending
                self.startTapTimer()
                self.onHotKeyPressed()
                Logger.app.infoDev("Modifier key pressed - recording started, detecting tap vs hold")

            } else if keyPressed && self.modifierKeyState == .toggleRecording {
                // Another tap while in toggle mode - stop recording
                self.modifierKeyState = .idle
                self.cancelTapTimer()
                self.onHotKeyPressed()
                Logger.app.infoDev("Modifier key tapped again - stopping toggle recording")

            } else if !keyPressed && self.modifierKeyState == .tapPending {
                // Key released - check if timer is still running to determine tap vs hold
                if self.modifierKeyTimer != nil {
                    // Timer still running = QUICK TAP
                    self.cancelTapTimer()
                    self.modifierKeyState = .toggleRecording
                    // Don't call onHotKeyPressed() - keep recording running for toggle mode
                    Logger.app.infoDev("Modifier key quick tap detected - entering toggle recording mode")
                } else {
                    // Timer already expired = it was actually a HOLD
                    self.modifierKeyState = .idle
                    self.onHotKeyPressed()
                    Logger.app.infoDev("Modifier key hold released - stopping recording")
                }

            } else if !keyPressed && self.modifierKeyState == .holdRecording {
                // Released during confirmed hold mode = PUSH-TO-TALK stop
                self.modifierKeyState = .idle
                self.onHotKeyPressed()
                Logger.app.infoDev("Modifier key hold released - stopping recording")
            }
        }
    }
    
    private func startTapTimer() {
        Logger.app.infoDev("🔄 Attempting to start modifier key tap timer...")

        // Create timer and add to RunLoop explicitly
        modifierKeyTimer = Timer(timeInterval: 0.2, repeats: false) { [weak self] _ in
            self?.handleTapTimerExpired()
        }

        if let timer = modifierKeyTimer {
            RunLoop.main.add(timer, forMode: .common)
            Logger.app.infoDev("✅ Modifier key tap timer started (0.2s threshold - explicit RunLoop)")
        } else {
            Logger.app.infoDev("❌ Failed to create modifier key tap timer!")
        }
    }

    private func cancelTapTimer() {
        // Called from main thread already - cancel directly
        modifierKeyTimer?.invalidate()
        modifierKeyTimer = nil
        Logger.app.infoDev("Modifier key tap timer cancelled")
    }

    private func handleTapTimerExpired() {
        // Timer expired - transition to hold recording mode
        modifierKeyTimer = nil
        modifierKeyState = .holdRecording
        Logger.app.infoDev("Modifier key timer expired - confirmed HOLD recording mode")
    }
    
    private func parseHotkeyString(_ hotkeyString: String) -> (Key?, NSEvent.ModifierFlags) {
        var modifiers: NSEvent.ModifierFlags = []
        var keyString = hotkeyString
        
        // Parse modifiers
        if keyString.contains("⌘") {
            modifiers.insert(.command)
            keyString = keyString.replacingOccurrences(of: "⌘", with: "")
        }
        if keyString.contains("⇧") {
            modifiers.insert(.shift)
            keyString = keyString.replacingOccurrences(of: "⇧", with: "")
        }
        if keyString.contains("⌥") {
            modifiers.insert(.option)
            keyString = keyString.replacingOccurrences(of: "⌥", with: "")
        }
        if keyString.contains("⌃") {
            modifiers.insert(.control)
            keyString = keyString.replacingOccurrences(of: "⌃", with: "")
        }
        
        // Parse key
        let key = stringToKey(keyString)
        
        return (key, modifiers)
    }
    
    private func stringToKey(_ keyString: String) -> Key? {
        switch keyString.uppercased() {
        // Function keys
        case "F1": return .f1
        case "F2": return .f2
        case "F3": return .f3
        case "F4": return .f4
        case "F5": return .f5
        case "F6": return .f6
        case "F7": return .f7
        case "F8": return .f8
        case "F9": return .f9
        case "F10": return .f10
        case "F11": return .f11
        case "F12": return .f12
        case "F13": return .f13
        case "F14": return .f14
        case "F15": return .f15
        case "F16": return .f16
        case "F17": return .f17
        case "F18": return .f18
        case "F19": return .f19
        case "F20": return .f20
        case "A": return .a
        case "S": return .s
        case "D": return .d
        case "F": return .f
        case "H": return .h
        case "G": return .g
        case "Z": return .z
        case "X": return .x
        case "C": return .c
        case "V": return .v
        case "B": return .b
        case "Q": return .q
        case "W": return .w
        case "E": return .e
        case "R": return .r
        case "Y": return .y
        case "T": return .t
        case "1": return .one
        case "2": return .two
        case "3": return .three
        case "4": return .four
        case "6": return .six
        case "5": return .five
        case "=": return .equal
        case "9": return .nine
        case "7": return .seven
        case "-": return .minus
        case "8": return .eight
        case "0": return .zero
        case "]": return .rightBracket
        case "O": return .o
        case "U": return .u
        case "[": return .leftBracket
        case "I": return .i
        case "P": return .p
        case "⏎": return .return
        case "L": return .l
        case "J": return .j
        case "'": return .quote
        case "K": return .k
        case ";": return .semicolon
        case "\\": return .backslash
        case ",": return .comma
        case "/": return .slash
        case "N": return .n
        case "M": return .m
        case ".": return .period
        case "⇥": return .tab
        case "SPACE": return .space
        case "`": return .grave
        case "⌫": return .delete
        case "⎋": return .escape
        case "↑": return .upArrow
        case "↓": return .downArrow
        case "←": return .leftArrow
        case "→": return .rightArrow
        default: return nil
        }
    }
    
    deinit {
        clearHotkey()
        NotificationCenter.default.removeObserver(self)
    }
}
