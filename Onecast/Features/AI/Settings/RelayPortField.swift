import SwiftUI

/// The port omp's browser relay listens on, shown wherever that relay can be switched on. One
/// relay serves this Mac, so this is the same field in Settings and in every assistant, not a copy
/// each of them owns: what a reader sets here is what every armed route dials.
struct RelayPortField: View {
    @Environment(AISettingsStore.self) private var settings
    @State private var draft = ""
    @FocusState private var focused: Bool

    var body: some View {
        // `Text` would group the digits ("9,224") through its localized interpolation; a port is text.
        TextField("Port", text: $draft, prompt: Text(String(BrowserRelayClient.defaultPort)))
            .textFieldStyle(.roundedBorder)
            .labelsHidden()
            .multilineTextAlignment(.trailing)
            .frame(width: 90)
            .focused($focused)
            .onSubmit(commit)
            // The pane's `releasesFocusOnOutsideClick` resigns; this catches it landing.
            .onChange(of: focused) { _, now in
                if !now { commit() }
            }
            .onAppear { draft = stored }
            .onChange(of: settings.browserRelayPort) { _, _ in
                if !focused { draft = stored }
            }
            .accessibilityLabel("Browser relay port")
    }

    /// Never a stored value the client would refuse to dial, so the field cannot show one.
    private var stored: String {
        guard let port = settings.browserRelayPort, BrowserRelayClient.isValidPort(port) else {
            return ""
        }
        return String(port)
    }

    /// One commit path — ↵ or focus landing elsewhere. Blank is the relay's own default.
    private func commit() {
        let trimmed = draft.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            settings.browserRelayPort = nil
        } else if let port = Int(trimmed), BrowserRelayClient.isValidPort(port) {
            settings.browserRelayPort = port
        }
        draft = stored
    }
}
