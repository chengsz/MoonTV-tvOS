import SwiftUI

struct SubtitlePickerView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    let initialQuery: String
    let backendTracks: [ExternalSubtitleTrack]
    @Binding var activeCues: [SubtitleCue]
    @Binding var activeLabel: String?
    @Binding var subtitleOffset: Double

    @State private var searchQuery: String = ""
    @State private var selectedLanguage: String = "en"
    @State private var searchResults: [OpenSubtitleResult] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    private let languages = [
        ("en", "English"),
        ("zh-cn", "Chinese (SC)"),
        ("zh-tw", "Chinese (TC)"),
        ("es", "Spanish"),
        ("ja", "Japanese"),
        ("ko", "Korean"),
        ("all", "All")
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    HStack {
                        Text("Subtitles")
                            .font(.largeTitle.bold())
                        Spacer()
                        if activeLabel != nil {
                            Button(role: .destructive) {
                                activeCues = []
                                activeLabel = nil
                                dismiss()
                            } label: {
                                Text("Turn Off Subtitles")
                            }
                        }
                    }

                    if let activeLabel {
                        HStack(spacing: 24) {
                            Text("Active: \(activeLabel)")
                                .font(.callout)
                                .foregroundStyle(.green)

                            Spacer()

                            Text(String(format: "Timing Offset: %+.1fs", subtitleOffset))
                                .font(.callout)

                            Button("-0.5s") { subtitleOffset -= 0.5 }
                            Button("Reset") { subtitleOffset = 0 }
                            Button("+0.5s") { subtitleOffset += 0.5 }
                        }
                    }

                    if !backendTracks.isEmpty {
                        VStack(alignment: .leading, spacing: 14) {
                            Text("From MoonTVPlus")
                                .font(.title3.bold())

                            ForEach(backendTracks) { track in
                                Button {
                                    Task { await loadBackendTrack(track) }
                                } label: {
                                    HStack {
                                        Text(track.label)
                                        Spacer()
                                        Text(track.language.uppercased())
                                            .foregroundStyle(.secondary)
                                    }
                                    .padding(.vertical, 6)
                                }
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 16) {
                        Text("Search OpenSubtitles.com")
                            .font(.title3.bold())

                        HStack(spacing: 16) {
                            TextField("Movie or episode title", text: $searchQuery)
                                .onSubmit { Task { await searchOpenSubtitles() } }
                                .frame(maxWidth: 640)

                            Picker("Lang", selection: $selectedLanguage) {
                                ForEach(languages, id: \.0) { code, name in
                                    Text(name).tag(code)
                                }
                            }
                            .frame(maxWidth: 260)

                            Button("Search") {
                                Task { await searchOpenSubtitles() }
                            }
                            .disabled(isLoading || searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }

                        if isLoading {
                            ProgressView("Fetching subtitles...")
                        }

                        if let errorMessage {
                            Text(errorMessage)
                                .foregroundStyle(.red)
                        }

                        ForEach(searchResults) { item in
                            Button {
                                Task { await downloadAndApply(item) }
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(item.releaseName)
                                            .lineLimit(1)
                                        Text("\(item.language.uppercased()) • \(item.downloadCount) downloads\(item.hearingImpaired ? " • HI" : "")")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Image(systemName: "arrow.down.circle")
                                }
                                .padding(.vertical, 6)
                            }
                        }
                    }
                }
                .padding(56)
            }
        }
        .onAppear {
            searchQuery = initialQuery
            selectedLanguage = appState.preferredSubtitleLanguage
        }
    }

    private func loadBackendTrack(_ track: ExternalSubtitleTrack) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let text = try await appState.openSubtitles.downloadRawURL(track.url)
            let cues = SubtitleParser.parse(text)
            activeCues = cues
            activeLabel = track.label
            subtitleOffset = 0
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func searchOpenSubtitles() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            searchResults = try await appState.openSubtitles.search(
                query: searchQuery,
                language: selectedLanguage
            )
            if searchResults.isEmpty {
                errorMessage = "No subtitles found for \(searchQuery)."
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func downloadAndApply(_ item: OpenSubtitleResult) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let text = try await appState.openSubtitles.downloadSubtitleText(fileId: item.fileId)
            let cues = SubtitleParser.parse(text)
            activeCues = cues
            activeLabel = "\(item.language.uppercased()) - \(item.releaseName)"
            subtitleOffset = 0
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
