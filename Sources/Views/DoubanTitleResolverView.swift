import SwiftUI

/// Bridges Douban catalog items to playable Apple CMS V10 streams on your Raspberry Pi.
struct DoubanTitleResolverView: View {
    @EnvironmentObject private var appState: AppState
    let item: DoubanItem

    @State private var matches: [MediaItem] = []
    @State private var isSearching = true
    @State private var errorMessage: String?

    private let columns = [
        GridItem(.adaptive(minimum: 240, maximum: 280), spacing: 36)
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(item.title)
                        .font(.largeTitle.bold())
                    Text("Select a video source on your MoonTV server to start playing")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                if isSearching {
                    HStack(spacing: 16) {
                        ProgressView()
                        Text("Searching \(max(1, appState.resources.count)) source(s) for \(item.title)...")
                            .foregroundStyle(.secondary)
                    }
                } else if let errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                } else if matches.isEmpty {
                    Text("No playable streams found for \(item.title) across your configured sources.")
                        .foregroundStyle(.secondary)
                } else {
                    LazyVGrid(columns: columns, spacing: 40) {
                        ForEach(matches, id: \.uniqueKey) { match in
                            NavigationLink {
                                DetailView(
                                    source: match.source,
                                    sourceName: match.sourceName,
                                    videoId: match.id,
                                    initialTitle: match.title
                                )
                            } label: {
                                PosterCardView(
                                    title: match.title,
                                    subtitle: [match.sourceName, match.year, match.remarks]
                                        .compactMap { $0 }
                                        .filter { !$0.isEmpty }
                                        .joined(separator: " • "),
                                    rawPosterURL: match.poster ?? item.poster,
                                    ratingBadge: item.rate,
                                    progress: nil
                                )
                            }
                            .buttonStyle(.card)
                        }
                    }
                }
            }
            .padding(56)
        }
        .task {
            await findMatches()
        }
    }

    private func findMatches() async {
        isSearching = true
        errorMessage = nil
        defer { isSearching = false }

        do {
            matches = try await appState.client.searchAll(query: item.title, resources: appState.resources)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
