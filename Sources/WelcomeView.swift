import SwiftUI
import AppKit

struct WelcomeView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            headerSection

            ScrollView {
                VStack(spacing: 24) {
                    welcomeSection
                    featuresList
                    setupSection
                }
                .padding(.vertical, 20)
                .padding(.horizontal, 30)
            }

            Divider()

            actionButtons
                .padding(20)
        }
        .frame(width: 600, height: 650)
        .background(Color(NSColor.windowBackgroundColor))
    }

    private var headerSection: some View {
        VStack(spacing: 8) {
            Image(systemName: "mic.circle.fill")
                .font(.system(size: 64))
                .foregroundColor(.accentColor)
                .symbolRenderingMode(.hierarchical)

            Text("Welcome to FluidVoice")
                .font(.largeTitle)
                .fontWeight(.semibold)

            Text("Privacy-first voice transcription for Apple Silicon")
                .font(.headline)
                .foregroundColor(.secondary)
        }
        .padding(.top, 30)
        .padding(.bottom, 10)
    }

    private var welcomeSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Getting Started")
                .font(.title2)
                .fontWeight(.semibold)

            Text("FluidVoice uses Parakeet for ultra-fast, completely private transcription on Apple Silicon Macs. No data leaves your device.")
                .font(.body)
                .foregroundColor(.secondary)
        }
    }

    private var featuresList: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Features")
                .font(.title2)
                .fontWeight(.semibold)

            VStack(alignment: .leading, spacing: 8) {
                FeatureRow(icon: "lock.shield", text: "100% private - no cloud dependencies")
                FeatureRow(icon: "bolt", text: "Sub-second transcription with Parakeet")
                FeatureRow(icon: "globe", text: "25 languages supported")
                FeatureRow(icon: "keyboard", text: "Global hotkey support")
                FeatureRow(icon: "textformat", text: "Smart vocabulary correction")
            }
        }
    }

    private var setupSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Setup")
                .font(.title2)
                .fontWeight(.semibold)

            Text("FluidVoice will automatically set up Parakeet when you first record. No manual configuration needed.")
                .font(.body)
                .foregroundColor(.secondary)
        }
    }

    private var actionButtons: some View {
        HStack {
            Spacer()

            Button("Get Started") {
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
    }
}

private struct FeatureRow: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(.accentColor)
                .frame(width: 20)

            Text(text)
                .font(.body)
        }
    }
}

#Preview {
    WelcomeView()
}