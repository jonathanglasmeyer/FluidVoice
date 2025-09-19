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
        case .vocabulary: return "textformat"
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
                .frame(minWidth: 400)
        }
        .onAppear {
            loadAvailableMicrophones()
        }
    }

    // MARK: - Sidebar
    private var sidebar: some View {
        VStack(spacing: 0) {
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
                .padding(.horizontal, 40)
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
                .padding(.horizontal, 40)
                .padding(.bottom, 40)
            }
        }
        .background(Color(NSColor.windowBackgroundColor))
    }

    private var contentHeader: some View {
        VStack(spacing: 20) {
            // Icon in rounded square like Bartender
            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(NSColor.controlAccentColor))
                    .frame(width: 64, height: 64)

                Image(systemName: selectedSection.icon)
                    .font(.system(size: 28, weight: .medium))
                    .foregroundColor(.white)
            }

            VStack(spacing: 8) {
                Text(selectedSection.rawValue)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundColor(.primary)

                Text(selectedSection.description)
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
        }
        .padding(.top, 12)
    }

    // MARK: - Content Sections
    private var generalContent: some View {
        VStack(spacing: 20) {
            // Audio Settings Group
            BartenderSettingsCard {
                VStack(spacing: 0) {
                    BartenderSettingsRow("Microphone") {
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
                        .padding(.horizontal, 20)

                    BartenderSettingsRow("Auto-boost microphone volume") {
                        Toggle("", isOn: $autoBoostMicrophoneVolume)
                            .toggleStyle(.switch)
                    }
                }
            }

            // Hotkey Settings Group
            BartenderSettingsCard {
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
            BartenderSettingsCard {
                BartenderSettingsRow("Start at login") {
                    Toggle("", isOn: $startAtLogin)
                        .toggleStyle(.switch)
                        .onChange(of: startAtLogin) { oldValue, newValue in
                            updateLoginItem(enabled: newValue)
                        }
                }
            }
        }
    }

    private var vocabularyContent: some View {
        VStack(spacing: 20) {
            // Vocabulary Management
            BartenderSettingsCard {
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
            BartenderSettingsCard {
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
        VStack(spacing: 20) {
            // History Settings
            BartenderSettingsCard {
                VStack(spacing: 0) {
                    BartenderSettingsRow("Save transcription history") {
                        Toggle("", isOn: $transcriptionHistoryEnabled)
                            .toggleStyle(.switch)
                    }

                    if transcriptionHistoryEnabled {
                        Divider()
                            .padding(.horizontal, 16)

                        BartenderSettingsRow("Keep history for") {
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

                        BartenderSettingsRow("Manage history") {
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

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(NSColor.controlBackgroundColor).opacity(0.7))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color(NSColor.separatorColor).opacity(0.3), lineWidth: 1)
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
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
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
                isSelected ? Color.accentColor : Color.clear
            )
            .cornerRadius(6)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 8)
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
                .foregroundColor(.blue)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.blue.opacity(0.1))
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