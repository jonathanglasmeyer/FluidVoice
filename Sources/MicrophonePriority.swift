import Foundation

/// A microphone the user put into their priority list. `uid` is the CoreAudio device UID,
/// which equals `AVCaptureDevice.uniqueID`. `name` is kept so disconnected devices stay readable.
struct MicrophoneEntry: Codable, Equatable, Identifiable {
    let uid: String
    var name: String

    var id: String { uid }
}

/// Ordered microphone preference: the first available entry is used for recording.
enum MicrophonePriority {
    static let storageKey = "microphonePriority"
    /// Pre-priority-list setting holding a single selected device UID
    static let legacySelectionKey = "selectedMicrophone"

    static func load(from defaults: UserDefaults = .standard) -> [MicrophoneEntry] {
        if let data = defaults.data(forKey: storageKey),
           let entries = try? JSONDecoder().decode([MicrophoneEntry].self, from: data) {
            return entries
        }

        // One-time migration from the single-selection setting
        let legacyUID = defaults.string(forKey: legacySelectionKey) ?? ""
        let migrated = legacyUID.isEmpty ? [] : [MicrophoneEntry(uid: legacyUID, name: legacyUID)]
        save(migrated, to: defaults)
        return migrated
    }

    static func save(_ entries: [MicrophoneEntry], to defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        defaults.set(data, forKey: storageKey)
    }

    static func firstAvailable(in entries: [MicrophoneEntry], isAvailable: (String) -> Bool) -> MicrophoneEntry? {
        return entries.first { isAvailable($0.uid) }
    }

    static func move(_ entries: inout [MicrophoneEntry], uid: String, by offset: Int) {
        guard let index = entries.firstIndex(where: { $0.uid == uid }) else { return }
        let target = index + offset
        guard entries.indices.contains(target) else { return }
        entries.swapAt(index, target)
    }

    static func add(_ entries: inout [MicrophoneEntry], _ entry: MicrophoneEntry) {
        guard !entries.contains(where: { $0.uid == entry.uid }) else { return }
        entries.append(entry)
    }
}
