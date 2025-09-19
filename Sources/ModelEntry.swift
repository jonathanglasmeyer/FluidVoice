import SwiftUI

protocol ModelEntry {
    var title: String { get }
    var subtitle: String { get }
    var sizeText: String? { get }
    var statusText: String? { get }
    var statusColor: Color? { get }
    var isDownloaded: Bool { get }
    var isDownloading: Bool { get }
    var isSelected: Bool { get }
    var badgeText: String? { get }
    var onSelect: () -> Void { get }
    var onDownload: () -> Void { get }
    var onDelete: () -> Void { get }
}

// LocalWhisperEntry removed - Parakeet-only architecture

struct MLXEntry: ModelEntry {
    let model: MLXModel
    let isDownloaded: Bool
    let isDownloading: Bool
    let statusText: String?
    let sizeText: String?
    let isSelected: Bool
    let badgeText: String?
    let onSelect: () -> Void
    let onDownload: () -> Void
    let onDelete: () -> Void

    var title: String { model.displayName }
    var subtitle: String { model.description }
    var statusColor: Color? {
        if let t = statusText, t.localizedCaseInsensitiveContains("error") || t.localizedCaseInsensitiveContains("please") {
            return .red
        }
        return isDownloading ? .blue : nil
    }
}

