import SwiftUI

// MARK: - Settings Card Components
/// Modern settings card component with subtle background and border styling
/// Features theme-aware appearance for both light and dark modes
struct SettingsCard<Content: View>: View {
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
                            ? Color.white.opacity(0.015)  // Much more subtle in dark mode
                            : Color.black.opacity(0.02)   // Much more subtle in light mode
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(
                        colorScheme == .dark
                            ? Color.white.opacity(0.1)
                            : Color.black.opacity(0.1),
                        lineWidth: 0.5
                    )
            )
    }
}

/// Row component for use within SettingsCard
/// Provides consistent spacing and typography for settings rows
struct SettingsRow<Content: View>: View {
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

// MARK: - Preview
#Preview {
    VStack(spacing: 16) {
        SettingsCard {
            VStack(spacing: 0) {
                SettingsRow("Sample Setting") {
                    Toggle("", isOn: .constant(true))
                        .toggleStyle(.switch)
                }

                Divider()
                    .padding(.horizontal, 16)

                SettingsRow("Another Setting") {
                    Picker("Option", selection: .constant("Option 1")) {
                        Text("Option 1").tag("Option 1")
                        Text("Option 2").tag("Option 2")
                    }
                    .pickerStyle(.menu)
                }
            }
        }

        SettingsCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("Welcome Card")
                    .font(.headline)
                    .padding(.horizontal, 16)
                    .padding(.top, 12)

                Text("This is an example of how SettingsCard can be used for welcome screens or other content.")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
            }
        }
    }
    .padding()
    .frame(width: 400)
}