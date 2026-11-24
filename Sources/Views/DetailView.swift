import SwiftUI

struct DetailView: View {
    @EnvironmentObject private var appState: AppState
    let source: String
    let sourceName: String
    let videoId: String
    let initialTitle: String
    var resumeEpisodeIndex: Int = 0
    var resumeTime: Double = 0

    @State private var currentSource: String = ""
    @State private var currentSourceName: String = ""
    @State private var currentVideoId: String = ""

    @State private var detail: MediaDetail?
    @State private var posterURL: URL?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var activePlayback: PlaybackTarget?
    @State private var showSourceSwitcher = false
    @State private var alternativeSources: [MediaItem] = []

    private let episodeColumns = [
        GridItem(.adaptive(minimum: 200, maximum: 260), spacing: 20)
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 36) {
                HStack(alignment: .top, spacing: 40) {
                    AsyncImage(url: posterURL) { phase in
                        switch phase {
                        case .success(let image):
                            image.resizable().scaledToFill()
                        default:
                            Rectangle()
                                .fill(Color.white.opacity(0.08))
                                .overlay { Image(systemName: "film").font(.largeTitle).foregroundStyle(.secondary) }
                        }
                    }
                    .frame(width: 240, height: 340)
                    .clipShape(RoundedRectangle(cornerRadius: 18))

                    VStack(alignment: .leading, spacing: 18) {
                        Text(detail?.title ?? initialTitle)
                            .font(.largeTitle.bold())

                        HStack(spacing: 14) {
                            Text(detail?.sourceName ?? currentSourceName)
                                .font(.callout)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 5)
                                .background(Color.white.opacity(0.12))
                                .clipShape(Capsule())

                            if let year = detail?.year, !year.isEmpty {
                                Text(year)
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                            }
                            if let count = detail?.episodes.count, count > 0 {
                                Text("\(count) Episodes")
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        if let description = detail?.description, !description.isEmpty {
                            Text(description)
                                .font(.body)
                                .foregroundStyle(.secondary)
                                .lineLimit(4)
                        }

                        if let detail {
                            HStack(spacing: 20) {
                                if let first = detail.episodes[safe: resumeEpisodeIndex] ?? detail.episodes.first {
                                    Button {
                                        activePlayback = PlaybackTarget(
                                            detail: detail,
                                            episodeIndex: first.index,
                                            startTime: first.index == resumeEpisodeIndex ? resumeTime : 0
                                        )
                                    } label: {
                                        Label(
                                            resumeTime > 10 ? "Resume \(first.title)" : "Play \(first.title)",
                                            systemImage: "play.fill"
                                        )
                                        .padding(.horizontal, 20)
                                    }
                                }

                                let fav = appState.isFavorited(source: detail.source, videoId: detail.id)
                                Button {
                                    Task {
                                        await appState.toggleFavorite(
                                            source: detail.source,
                                            sourceName: detail.sourceName,
                                            videoId: detail.id,
                                            title: detail.title,
                                            cover: detail.poster,
                                            year: detail.year
                                        )
                                    }
                                } label: {
                                    Label(fav ? "Favorited" : "Favorite", systemImage: fav ? "heart.fill" : "heart")
                                }

                                Button {
                                    showSourceSwitcher = true
                                    Task { await loadAlternativeSources(title: detail.title) }
                                } label: {
                                    Label("Switch Source", systemImage: "arrow.triangle.2.circlepath")
                                }
                            }
                        }
                    }
                }

                if isLoading {
                    ProgressView("Loading episodes...")
                } else if let errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                } else if let detail {
                    VStack(alignment: .leading, spacing: 18) {
                        Text("Episodes (\(detail.episodes.count))")
                            .font(.title2.bold())

                        LazyVGrid(columns: episodeColumns, spacing: 20) {
                            ForEach(detail.episodes) { episode in
                                Button {
                                    activePlayback = PlaybackTarget(
                                        detail: detail,
                                        episodeIndex: episode.index,
                                        startTime: episode.index == resumeEpisodeIndex ? resumeTime : 0
                                    )
                                } label: {
                                    HStack(spacing: 8) {
                                        if episode.index < resumeEpisodeIndex {
                                            Image(systemName: "checkmark.circle.fill")
                                                .foregroundStyle(.green)
                                        }
                                        Text(episode.title)
                                            .lineLimit(1)
                                    }
                                    .frame(maxWidth: .infinity)
                                }
                            }
                        }
                    }
                }
            }
            .padding(56)
        }
        .task {
            if currentSource.isEmpty {
                currentSource = source
                currentSourceName = sourceName
                currentVideoId = videoId
            }
            await loadDetail()
        }
        .fullScreenCover(item: $activePlayback) { target in
            PlayerScreen(target: target)
                .environmentObject(appState)
        }
        .sheet(isPresented: $showSourceSwitcher) {
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        Text("Switch Video Source")
                            .font(.largeTitle.bold())
                        if alternativeSources.isEmpty {
                            ProgressView("Searching alternative sources...")
                        } else {
                            ForEach(alternativeSources, id: \.uniqueKey) { alt in
                                Button {
                                    currentSource = alt.source
                                    currentSourceName = alt.sourceName
                                    currentVideoId = alt.id
                                    showSourceSwitcher = false
                                    Task { await loadDetail() }
                                } label: {
                                    HStack {
                                        Text(alt.sourceName)
                                        Spacer()
                                        Text(alt.remarks ?? alt.title)
                                            .foregroundStyle(.secondary)
                                    }
                                    .padding(.vertical, 6)
                                }
                            }
                        }
                    }
                    .padding(56)
                }
            }
        }
    }

    private func loadDetail() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let loaded = try await appState.client.fetchDetail(
                source: currentSource,
                id: currentVideoId,
                fallbackTitle: initialTitle,
                fallbackSourceName: currentSourceName
            )
            detail = loaded
            posterURL = await appState.client.proxiedImageURL(for: loaded.poster)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func loadAlternativeSources(title: String) async {
        alternativeSources = (try? await appState.client.searchAll(query: title, resources: appState.resources)) ?? []
    }
}

struct PlaybackTarget: Identifiable {
    let id = UUID()
    let detail: MediaDetail
    let episodeIndex: Int
    let startTime: Double
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
