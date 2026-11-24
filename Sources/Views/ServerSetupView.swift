import SwiftUI

struct ServerSetupView: View {
    @EnvironmentObject private var appState: AppState
    let isInitialSetup: Bool

    @State private var addressInput: String = ""
    @State private var usernameInput: String = ""
    @State private var passwordInput: String = ""
    @State private var isTesting = false
    @State private var statusMessage: String?
    @State private var isError = false

    private let languages = [
        ("en", "English"),
        ("zh-cn", "Chinese (Simplified)"),
        ("zh-tw", "Chinese (Traditional)"),
        ("es", "Spanish"),
        ("ja", "Japanese"),
        ("ko", "Korean"),
        ("all", "All Languages")
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 36) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(isInitialSetup ? "Connect to MoonTV" : "Server & Playback Settings")
                        .font(.largeTitle.bold())
                    Text("Point to your Raspberry Pi IP and port (e.g. 192.168.1.50:3000 or http://raspberrypi.local:3000).")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 18) {
                    Text("MoonTV / LunaTV / MoonTVPlus Backend")
                        .font(.title3.bold())

                    TextField("Server IP:Port (e.g. 192.168.1.50:3000)", text: $addressInput)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()

                    TextField("Username (optional for password-only)", text: $usernameInput)
                        .autocorrectionDisabled()

                    SecureField("Password", text: $passwordInput)
                }
                .frame(maxWidth: 800)

                HStack(spacing: 24) {
                    Button {
                        Task { await testAndSave() }
                    } label: {
                        HStack(spacing: 12) {
                            if isTesting {
                                ProgressView()
                            }
                            Text(isTesting ? "Connecting..." : "Test & Connect")
                        }
                        .padding(.horizontal, 20)
                    }
                    .disabled(isTesting || addressInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    if !isInitialSetup {
                        Button(role: .destructive) {
                            appState.disconnect()
                        } label: {
                            Text("Disconnect")
                        }
                    }
                }

                if let statusMessage {
                    Text(statusMessage)
                        .font(.callout)
                        .foregroundStyle(isError ? .red : .green)
                }

                VStack(alignment: .leading, spacing: 18) {
                    Text("HLS Ad-Blocker")
                        .font(.title3.bold())

                    Toggle("Strip spliced HLS ad segments (#EXT-X-DISCONTINUITY)", isOn: $appState.adBlockEnabled)
                        .frame(maxWidth: 800)
                }

                VStack(alignment: .leading, spacing: 18) {
                    Text("OpenSubtitles.com Search (VLC / Infuse Style)")
                        .font(.title3.bold())
                    Text("Create a free API consumer key at opensubtitles.com/en/consumers to search and load subtitles inside the player.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    TextField("OpenSubtitles API Key", text: $appState.openSubtitlesAPIKey)
                        .autocorrectionDisabled()

                    TextField("OpenSubtitles Username (optional, raises daily limit)", text: $appState.openSubtitlesUsername)
                        .autocorrectionDisabled()

                    SecureField("OpenSubtitles Password (optional)", text: $appState.openSubtitlesPassword)

                    Picker("Default Subtitle Language", selection: $appState.preferredSubtitleLanguage) {
                        ForEach(languages, id: \.0) { code, name in
                            Text(name).tag(code)
                        }
                    }
                }
                .frame(maxWidth: 800)
            }
            .padding(60)
        }
        .onAppear {
            addressInput = appState.serverAddress.isEmpty ? "http://192.168.1.100:3000" : appState.serverAddress
            usernameInput = appState.username
            passwordInput = appState.password
        }
    }

    private func testAndSave() async {
        isTesting = true
        statusMessage = nil
        isError = false
        defer { isTesting = false }

        do {
            try await appState.connectAndLogin(
                address: addressInput,
                username: usernameInput,
                password: passwordInput
            )
            statusMessage = "Connected to \(appState.serverAddress)"
            isError = false
        } catch {
            statusMessage = error.localizedDescription
            isError = true
        }
    }
}
