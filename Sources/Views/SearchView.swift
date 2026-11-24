import SwiftUI

struct SearchView: View {
    @EnvironmentObject private var appState: AppState
    @State private var query = ""
    @State private var results: [MediaItem] = []
    @State private var isSearching = false
    @State private var errorMessage: String?

    private let columns = [
        GridItem(.adaptive(minimum: 240, maximum: 280), spacing: 36)
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 32) {
                    HStack(spacing: 20) {
                        TextField("Search movies, shows, anime...", text: $query)
                            .onSubmit {
                                Task { await runSearch() }
                            }
                            .frame(maxWidth: 720)

                        Button("Search") {
                            Task { await runSearch() }
                        }
                        .disabled(isSearching || query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }

                    if isSearching {
                        HStack(spacing: 16) {
                            ProgressView()
                            Text("Searching across \(max(1, appState.resources.count)) source(s)...")
                                .foregroundStyle(.secondary)
                        }
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    }

                    LazyVGrid(columns: columns, spacing: 40) {
                        ForEach(results, id: \.uniqueKey) { item in
                            NavigationLink {
                                DetailView(
                                    source: item.source,
                                    sourceName: item.sourceName,
                                    videoId: item.id,
                                    initialTitle: item.title
                                )
                            } label: {
                                PosterCardView(
                                    title: item.title,
                                    subtitle: [item.sourceName, item.year, item.remarks]
                                        .compactMap { $0 }
                                        .filter { !$0.isEmpty }
                                        .joined(separator: " • "),
                                    rawPosterURL: item.poster,
                                    ratingBadge: nil,
                                    progress: nil
                                )
                            }
                            .buttonStyle(.card)
                        }
                    }
                }
                .padding(56)
            }
        }
    }

    private func runSearch() async {
        isSearching = true
        errorMessage = nil
        defer { isSearching = false }

        do {
            results = try await appState.client.searchAll(query: query, resources: appState.resources)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
