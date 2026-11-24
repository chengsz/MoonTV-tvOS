import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 44) {
                    HStack {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("MoonTV")
                                .font(.largeTitle.bold())
                            Text(appState.serverAddress)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button {
                            Task { await appState.refreshDashboard() }
                        } label: {
                            Label("Refresh", systemImage: "arrow.clockwise")
                        }
                    }

                    if let featured = appState.doubanMovies.first ?? appState.doubanShows.first {
                        HeroBannerView(item: featured)
                    }

                    if !appState.playRecords.isEmpty {
                        VStack(alignment: .leading, spacing: 20) {
                            Text("Continue Watching")
                                .font(.title2.bold())

                            ScrollView(.horizontal) {
                                LazyHStack(spacing: 36) {
                                    ForEach(appState.playRecords) { record in
                                        NavigationLink {
                                            DetailView(
                                                source: record.source,
                                                sourceName: record.sourceName,
                                                videoId: record.videoId,
                                                initialTitle: record.title,
                                                resumeEpisodeIndex: record.episodeIndex,
                                                resumeTime: record.playTime
                                            )
                                        } label: {
                                            PosterCardView(
                                                title: record.title,
                                                subtitle: "Ep \(record.episodeIndex + 1) • \(record.sourceName)",
                                                rawPosterURL: record.cover,
                                                ratingBadge: nil,
                                                progress: record.progressFraction
                                            )
                                        }
                                        .buttonStyle(.card)
                                    }
                                }
                                .padding(.vertical, 20)
                            }
                        }
                    }

                    if !appState.doubanMovies.isEmpty {
                        VStack(alignment: .leading, spacing: 20) {
                            Text("Douban Trending Movies")
                                .font(.title2.bold())

                            ScrollView(.horizontal) {
                                LazyHStack(spacing: 36) {
                                    ForEach(appState.doubanMovies) { item in
                                        NavigationLink {
                                            DoubanTitleResolverView(item: item)
                                        } label: {
                                            PosterCardView(
                                                title: item.title,
                                                subtitle: item.year ?? "Movie",
                                                rawPosterURL: item.poster,
                                                ratingBadge: item.rate,
                                                progress: nil
                                            )
                                        }
                                        .buttonStyle(.card)
                                    }
                                }
                                .padding(.vertical, 20)
                            }
                        }
                    }

                    if !appState.doubanShows.isEmpty {
                        VStack(alignment: .leading, spacing: 20) {
                            Text("Douban Trending TV Shows")
                                .font(.title2.bold())

                            ScrollView(.horizontal) {
                                LazyHStack(spacing: 36) {
                                    ForEach(appState.doubanShows) { item in
                                        NavigationLink {
                                            DoubanTitleResolverView(item: item)
                                        } label: {
                                            PosterCardView(
                                                title: item.title,
                                                subtitle: item.year ?? "TV Series",
                                                rawPosterURL: item.poster,
                                                ratingBadge: item.rate,
                                                progress: nil
                                            )
                                        }
                                        .buttonStyle(.card)
                                    }
                                }
                                .padding(.vertical, 20)
                            }
                        }
                    }

                    if !appState.favorites.isEmpty {
                        VStack(alignment: .leading, spacing: 20) {
                            Text("Favorites")
                                .font(.title2.bold())

                            ScrollView(.horizontal) {
                                LazyHStack(spacing: 36) {
                                    ForEach(appState.favorites) { fav in
                                        NavigationLink {
                                            DetailView(
                                                source: fav.source,
                                                sourceName: fav.sourceName,
                                                videoId: fav.videoId,
                                                initialTitle: fav.title
                                            )
                                        } label: {
                                            PosterCardView(
                                                title: fav.title,
                                                subtitle: fav.sourceName,
                                                rawPosterURL: fav.cover,
                                                ratingBadge: nil,
                                                progress: nil
                                            )
                                        }
                                        .buttonStyle(.card)
                                    }
                                }
                                .padding(.vertical, 20)
                            }
                        }
                    }
                }
                .padding(56)
            }
        }
    }
}

struct HeroBannerView: View {
    @EnvironmentObject private var appState: AppState
    let item: DoubanItem
    @State private var resolvedURL: URL?

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            AsyncImage(url: resolvedURL) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                default:
                    Rectangle()
                        .fill(Color.white.opacity(0.08))
                }
            }
            .frame(height: 360)
            .clipped()
            .overlay {
                LinearGradient(
                    colors: [Color.black.opacity(0.85), Color.black.opacity(0.25), Color.clear],
                    startPoint: .bottomLeading,
                    endPoint: .topTrailing
                )
            }

            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    if let rate = item.rate, !rate.isEmpty {
                        Text("Douban \(rate)")
                            .font(.caption.bold())
                            .padding(.horizontal, 12)
                            .padding(.vertical, 5)
                            .background(Color.green.opacity(0.85))
                            .clipShape(Capsule())
                    }
                    if let year = item.year, !year.isEmpty {
                        Text(year)
                            .font(.caption.bold())
                            .padding(.horizontal, 12)
                            .padding(.vertical, 5)
                            .background(Color.white.opacity(0.2))
                            .clipShape(Capsule())
                    }
                }

                Text(item.title)
                    .font(.largeTitle.bold())
                    .lineLimit(1)

                NavigationLink {
                    DoubanTitleResolverView(item: item)
                } label: {
                    Label("Find Streams & Play", systemImage: "play.fill")
                        .padding(.horizontal, 24)
                }
            }
            .padding(36)
        }
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .task(id: item.poster) {
            resolvedURL = await appState.client.proxiedImageURL(for: item.poster)
        }
    }
}

struct PosterCardView: View {
    @EnvironmentObject private var appState: AppState
    let title: String
    let subtitle: String
    let rawPosterURL: String?
    let ratingBadge: String?
    let progress: Double?

    @State private var resolvedURL: URL?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack {
                AsyncImage(url: resolvedURL) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    default:
                        Rectangle()
                            .fill(Color.white.opacity(0.08))
                            .overlay {
                                Image(systemName: "film")
                                    .font(.title)
                                    .foregroundStyle(.secondary)
                            }
                    }
                }
                .frame(width: 240, height: 340)
                .clipped()

                VStack {
                    HStack {
                        Spacer()
                        if let ratingBadge, !ratingBadge.isEmpty {
                            Text(ratingBadge)
                                .font(.caption2.bold())
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.black.opacity(0.75))
                                .foregroundStyle(.yellow)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                                .padding(10)
                        }
                    }
                    Spacer()
                    if let progress, progress > 0 {
                        ProgressView(value: progress)
                            .tint(.blue)
                            .padding(.horizontal, 8)
                            .padding(.bottom, 8)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 10)
        }
        .frame(width: 240)
        .task(id: rawPosterURL) {
            resolvedURL = await appState.client.proxiedImageURL(for: rawPosterURL)
        }
    }
}
