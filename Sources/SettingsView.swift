import SwiftUI
import SwiftData
import AVFoundation
import ServiceManagement
import HotKey
import os.log

enum SettingsSection: String, CaseIterable {
    case general = "General"
    case vocabulary = "Vocabulary"
    case history = "History"

    var icon: String {
        switch self {
        case .general: return "gearshape.fill"
        case .vocabulary: return "book.fill"
        case .history: return "clock.fill"
        }
    }

    var description: String {
        switch self {
        case .general: return "Configure microphone, hotkeys, and basic preferences"
        case .vocabulary: return "Manage local vocabulary corrections for better accuracy"
        case .history: return "View and manage transcription history settings"
        }
    }
}

// Parakeet-only SettingsView with macOS sidebar pattern
struct SettingsView: View {
    @AppStorage("selectedMicrophone") private var selectedMicrophone = ""
    @AppStorage("globalHotkey") private var globalHotkey = "⌘⇧Space"
    @AppStorage("startAtLogin") private var startAtLogin = true
    @AppStorage("autoBoostMicrophoneVolume") private var autoBoostMicrophoneVolume = false
    @AppStorage("transcriptionHistoryEnabled") private var transcriptionHistoryEnabled = false
    @AppStorage("transcriptionRetentionPeriod") private var transcriptionRetentionPeriodRaw = RetentionPeriod.oneMonth.rawValue

    @State private var selectedSection: SettingsSection = .general
    @State private var availableMicrophones: [AVCaptureDevice] = []
    @State private var isRecordingHotkey = false
    @State private var recordedModifiers: NSEvent.ModifierFlags = []
    @State private var recordedKey: Key?

    var body: some View {
        HSplitView {
            // Sidebar
            sidebar
                .frame(minWidth: 200, maxWidth: 250)

            // Content area
            contentArea
                .frame(minWidth: 450)
        }
        .tint(Color(red: 0.3, green: 0.3, blue: 0.3))
        .onAppear {
            loadAvailableMicrophones()
        }
    }

    // MARK: - Sidebar
    private var sidebar: some View {
        VStack(spacing: 0) {
            // FluidVoice logo section - direct image without VStack
            Group {
                if let logoPath = Bundle.main.path(forResource: "Assets.xcassets/FluidVoiceLogo.imageset/FluidVoiceIcon", ofType: "png"),
                   let logoImage = NSImage(contentsOfFile: logoPath) {
                    Image(nsImage: logoImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: .infinity, maxHeight: 120)
                } else {
                    // Fallback: Use gear icon like header originally had
                    Image(systemName: "gearshape.fill")
                        .frame(width: 24, height: 16)
                        .foregroundColor(.secondary)
                }
            }
            .foregroundColor(.primary)
            .padding(.bottom, 20)

            ForEach(SettingsSection.allCases, id: \.self) { section in
                SidebarRow(
                    section: section,
                    isSelected: selectedSection == section
                ) {
                    selectedSection = section
                }
            }

            Spacer()
        }
        .padding(.vertical, 12)
        .background(Color.clear)
    }

    // MARK: - Content Area
    private var contentArea: some View {
        VStack(spacing: 0) {
            // Header
            contentHeader
                .padding(.horizontal, 32)
                .padding(.top, 40)
                .padding(.bottom, 20)

            // Content
            ScrollView {
                VStack(spacing: 24) {
                    switch selectedSection {
                    case .general:
                        generalContent
                    case .vocabulary:
                        vocabularyContent
                    case .history:
                        historyContent
                    }
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 24)
            }
        }
        .background(Color(NSColor.windowBackgroundColor))
    }

    private var contentHeader: some View {
        VStack(spacing: 12) {
            SettingsCard {
                VStack(spacing: 8) {
                    // Section icon - no background
                    Image(systemName: selectedSection.icon)
                        .font(.system(size: 28, weight: .medium))
                        .foregroundColor(.primary)
                        .frame(height: 36)

                    // Centered title and description like Bartender
                    VStack(spacing: 4) {
                        Text(selectedSection.rawValue)
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(.primary)

                        Text(selectedSection.description)
                            .font(.system(size: 12, weight: .regular))
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
                .padding(.horizontal, 16)
            }
        }
        .padding(.bottom, 12)
    }

    // MARK: - Content Sections
    private var generalContent: some View {
        VStack(spacing: 12) {
            // Audio Settings Group
            SettingsCard {
                VStack(spacing: 0) {
                    SettingsRow("Microphone") {
                        Picker("Input Device", selection: $selectedMicrophone) {
                            Text("System Default").tag("")
                            ForEach(availableMicrophones, id: \.uniqueID) { device in
                                Text(device.localizedName).tag(device.uniqueID)
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(maxWidth: 200)
                    }

                    Divider()
                        .padding(.horizontal, 16)

                    SettingsRow("Auto-boost microphone volume") {
                        Toggle("", isOn: $autoBoostMicrophoneVolume)
                            .toggleStyle(SwitchToggleStyle(tint: Color.gray))
                    }
                }
            }

            // Hotkey Settings Group
            SettingsCard {
                BartenderSettingsRow("Global Hotkey") {
                    HStack {
                        if isRecordingHotkey {
                            HotKeyRecorderView(
                                isRecording: $isRecordingHotkey,
                                recordedModifiers: $recordedModifiers,
                                recordedKey: $recordedKey,
                                onComplete: { newHotkey in
                                    globalHotkey = newHotkey
                                    updateGlobalHotkey(newHotkey)
                                }
                            )
                        } else {
                            Text(globalHotkey)
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.secondary.opacity(0.1))
                                .cornerRadius(4)

                            Button("Change") {
                                isRecordingHotkey = true
                                recordedModifiers = []
                                recordedKey = nil
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }
            }

            // General Settings Group
            SettingsCard {
                BartenderSettingsRow("Start at login") {
                    Toggle("", isOn: $startAtLogin)
                        .toggleStyle(SwitchToggleStyle(tint: Color.gray))
                        .onChange(of: startAtLogin) { oldValue, newValue in
                            updateLoginItem(enabled: newValue)
                        }
                }
            }
        }
    }

    private var vocabularyContent: some View {
        VStack(spacing: 12) {
            // Vocabulary Management
            SettingsCard {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Vocabulary Management")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.primary)
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)

                    Text("Local vocabulary corrections are stored in ~/.config/fluidvoice/vocabulary.jsonc")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 16)

                    HStack {
                        Spacer()
                        Button("Open Vocabulary File") {
                            openVocabularyFile()
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
                }
            }

            // Coming Soon Features
            SettingsCard {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Coming Soon")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.primary)
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("• In-app vocabulary editor")
                        Text("• Import/export vocabulary lists")
                        Text("• Context-aware corrections")
                    }
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
                }
            }
        }
    }

    private var historyContent: some View {
        VStack(spacing: 12) {
            // History Settings
            SettingsCard {
                VStack(spacing: 0) {
                    SettingsRow("Save transcription history") {
                        Toggle("", isOn: $transcriptionHistoryEnabled)
                            .toggleStyle(SwitchToggleStyle(tint: Color.gray))
                    }

                    if transcriptionHistoryEnabled {
                        Divider()
                            .padding(.horizontal, 16)

                        SettingsRow("Keep history for") {
                            Picker("Retention Period", selection: $transcriptionRetentionPeriodRaw) {
                                ForEach(RetentionPeriod.allCases, id: \.self) { period in
                                    Text(period.displayName).tag(period.rawValue)
                                }
                            }
                            .pickerStyle(.menu)
                            .frame(maxWidth: 200)
                        }

                        Divider()
                            .padding(.horizontal, 16)

                        SettingsRow("Manage history") {
                            Button("View History...") {
                                showHistoryWindow()
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Helper Functions
    private func loadAvailableMicrophones() {
        Task {
            let devices = AVCaptureDevice.DiscoverySession(
                deviceTypes: [.microphone],
                mediaType: .audio,
                position: .unspecified
            ).devices

            await MainActor.run {
                self.availableMicrophones = devices
            }
        }
    }

    private func updateGlobalHotkey(_ hotkey: String) {
        // Implementation would update the global hotkey
        // This connects to the existing hotkey system
    }

    private func updateLoginItem(enabled: Bool) {
        // Implementation would update login item
        // This connects to the existing ServiceManagement code
    }

    private func openVocabularyFile() {
        let homeURL = FileManager.default.homeDirectoryForCurrentUser
        let configURL = homeURL.appendingPathComponent(".config/fluidvoice/vocabulary.jsonc")
        NSWorkspace.shared.open(configURL)
    }

    private func showHistoryWindow() {
        // Implementation would show history window
        // This connects to the existing HistoryWindowManager
    }
}

// MARK: - Bartender-style Components
struct BartenderSettingsCard<Content: View>: View {
    let content: Content
    @Environment(\.colorScheme) private var colorScheme

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(
                        colorScheme == .dark
                            ? Color.white.opacity(0.015)  // Dark Mode: sehr subtil heller
                            : Color.black.opacity(0.02)   // Light Mode: sehr subtil dunkler
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color(NSColor.separatorColor).opacity(0.7), lineWidth: 1)
            )
    }
}

struct BartenderSettingsRow<Content: View>: View {
    let title: String
    let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 13))
                .foregroundColor(.primary)

            Spacer()

            content
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}

// MARK: - Supporting Views
struct SidebarRow: View {
    let section: SettingsSection
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: section.icon)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(isSelected ? .white : .secondary)
                    .frame(width: 20)

                Text(section.rawValue)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(isSelected ? .white : .primary)

                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(
                isSelected ? Color(red: 0.3, green: 0.3, blue: 0.3) : Color.clear
            )
            .cornerRadius(6)
            .padding(.horizontal, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}


// MARK: - HotKey Recorder (Simplified version)
struct HotKeyRecorderView: View {
    @Binding var isRecording: Bool
    @Binding var recordedModifiers: NSEvent.ModifierFlags
    @Binding var recordedKey: Key?
    let onComplete: (String) -> Void

    @State private var displayText = "Press keys..."

    var body: some View {
        HStack {
            Text(displayText)
                .foregroundColor(.primary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.black.opacity(0.1))
                .cornerRadius(4)

            Button("Cancel") {
                isRecording = false
            }
            .buttonStyle(.bordered)
        }
    }
}

// MARK: - Sidebar Glass Effect
struct SidebarGlass: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    private var isDark: Bool { colorScheme == .dark }

    func body(content: Content) -> some View {
        content
            // Dark sidebar background with subtle transparency
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(
                        isDark
                            ? Color.black.opacity(0.3)
                            : Color.black.opacity(0.1)
                    )
            )

            // Top highlight for depth
            .overlay(alignment: .top) {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(isDark ? 0.15 : 0.25),
                                .clear
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(height: 6)
                    .blur(radius: 0.5)
            }

            // Subtle border
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(
                        Color.white.opacity(isDark ? 0.08 : 0.12),
                        lineWidth: 0.5
                    )
            )

            // Add material blur effect
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .opacity(0.8)
            )

            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

extension View {
    func sidebarGlass() -> some View {
        modifier(SidebarGlass())
    }
}

#Preview {
    SettingsView()
        .frame(width: 800, height: 600)
}