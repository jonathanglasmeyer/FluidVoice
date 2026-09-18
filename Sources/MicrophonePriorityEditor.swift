import SwiftUI
import AVFoundation

/// Ordered microphone list for Settings: the first connected entry records, built-in mic is the fallback
struct MicrophonePriorityEditor: View {
    @State private var entries: [MicrophoneEntry] = MicrophonePriority.load()
    @State private var connectedDevices: [AVCaptureDevice] = []
    @State private var usableUIDs: Set<String> = []

    private let deviceManager = AudioDeviceManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SettingsRow("Microphone priority", infoText: "The first connected microphone in this list is used for recording. If none is connected, the built-in microphone is used.") {
                addMenu
            }

            if entries.isEmpty {
                Text("No microphones added - using the system default input")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 16)
            } else {
                VStack(spacing: 2) {
                    ForEach(Array(entries.enumerated()), id: \.element.uid) { index, entry in
                        row(for: entry, rank: index + 1)
                    }
                }
                .padding(.horizontal, 12)
            }
        }
        .padding(.bottom, 12)
        .onAppear(perform: refreshDevices)
        .onReceive(NotificationCenter.default.publisher(for: AVCaptureDevice.wasConnectedNotification)) { _ in refreshDevices() }
        .onReceive(NotificationCenter.default.publisher(for: AVCaptureDevice.wasDisconnectedNotification)) { _ in refreshDevices() }
        .onChange(of: entries) { _, newEntries in
            MicrophonePriority.save(newEntries)
            refreshAvailability()
        }
    }

    private var activeUID: String? {
        MicrophonePriority.firstAvailable(in: entries) { usableUIDs.contains($0) }?.uid
    }

    private var addableDevices: [AVCaptureDevice] {
        connectedDevices.filter { device in
            !entries.contains(where: { $0.uid == device.uniqueID })
                && !AudioDeviceManager.isVirtualDevice(name: device.localizedName)
        }
    }

    private var addMenu: some View {
        Menu("Add") {
            ForEach(addableDevices, id: \.uniqueID) { device in
                Button(device.localizedName) {
                    MicrophonePriority.add(&entries, MicrophoneEntry(uid: device.uniqueID, name: device.localizedName))
                }
            }
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .disabled(addableDevices.isEmpty)
    }

    private func row(for entry: MicrophoneEntry, rank: Int) -> some View {
        let isConnected = usableUIDs.contains(entry.uid)
        return HStack(spacing: 8) {
            Text("\(rank).")
                .font(.system(size: 12).monospacedDigit())
                .foregroundColor(.secondary)
                .frame(width: 18, alignment: .trailing)
            Circle()
                .fill(isConnected ? Color.green : Color.secondary.opacity(0.4))
                .frame(width: 7, height: 7)
                .help(isConnected ? "Connected" : "Not connected")
            Text(entry.name)
                .font(.system(size: 13))
                .foregroundColor(isConnected ? .primary : .secondary)
                .lineLimit(1)
            if entry.uid == activeUID {
                Text("in use")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .overlay(Capsule().stroke(Color.secondary.opacity(0.5), lineWidth: 0.5))
            }
            Spacer()
            iconButton("chevron.up", help: "Move up", disabled: rank == 1) {
                MicrophonePriority.move(&entries, uid: entry.uid, by: -1)
            }
            iconButton("chevron.down", help: "Move down", disabled: rank == entries.count) {
                MicrophonePriority.move(&entries, uid: entry.uid, by: 1)
            }
            iconButton("xmark", help: "Remove") {
                entries.removeAll { $0.uid == entry.uid }
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 4)
    }

    private func iconButton(_ systemName: String, help: String, disabled: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 11, weight: .medium))
                .frame(width: 18, height: 18)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundColor(.secondary)
        .disabled(disabled)
        .opacity(disabled ? 0.3 : 1)
        .help(help)
    }

    private func refreshDevices() {
        connectedDevices = deviceManager.getAllAvailableDevices()
        refreshAvailability()

        // Refresh stored names (migrated entries only carry their UID)
        var updated = entries
        for device in connectedDevices {
            if let index = updated.firstIndex(where: { $0.uid == device.uniqueID }) {
                updated[index].name = device.localizedName
            }
        }
        if updated != entries {
            entries = updated
        }
    }

    private func refreshAvailability() {
        usableUIDs = Set(entries.map(\.uid).filter { deviceManager.usableDeviceID(forUID: $0) != nil })
    }
}
