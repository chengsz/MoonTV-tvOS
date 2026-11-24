import Foundation

struct VideoSource: Identifiable, Codable, Hashable {
    let key: String
    let name: String
    let api: String?

    var id: String { key }

    enum CodingKeys: String, CodingKey {
        case key, id, name, title, api
    }

    init(key: String, name: String, api: String? = nil) {
        self.key = key
        self.name = name
        self.api = api
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedKey = (try? container.decode(String.self, forKey: .key))
            ?? (try? container.decode(String.self, forKey: .id))
            ?? UUID().uuidString
        let decodedName = (try? container.decode(String.self, forKey: .name))
            ?? (try? container.decode(String.self, forKey: .title))
            ?? decodedKey
        self.key = decodedKey
        self.name = decodedName
        self.api = try? container.decode(String.self, forKey: .api)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(key, forKey: .key)
        try container.encode(name, forKey: .name)
        try container.encodeIfPresent(api, forKey: .api)
    }
}

struct DoubanItem: Identifiable, Hashable {
    let id: String
    let title: String
    let poster: String?
    let rate: String?
    let year: String?
    let type: String
}

struct CategoryFilter: Identifiable, Hashable {
    let id: String
    let label: String
    let type: String
    let tag: String

    static let defaults: [CategoryFilter] = [
        CategoryFilter(id: "movie_hot", label: "Popular Movies", type: "movie", tag: "热门"),
        CategoryFilter(id: "movie_top", label: "Top Rated", type: "movie", tag: "豆瓣高分"),
        CategoryFilter(id: "tv_us", label: "US & UK TV", type: "tv", tag: "美剧"),
        CategoryFilter(id: "tv_kr", label: "K-Drama", type: "tv", tag: "韩剧"),
        CategoryFilter(id: "tv_anime", label: "Anime", type: "tv", tag: "日本动画"),
        CategoryFilter(id: "tv_cn", label: "C-Drama", type: "tv", tag: "国产剧"),
        CategoryFilter(id: "tv_doc", label: "Documentaries", type: "tv", tag: "纪录片"),
        CategoryFilter(id: "tv_variety", label: "Variety", type: "tv", tag: "综艺")
    ]
}

struct MediaItem: Identifiable, Hashable {
    let id: String
    let title: String
    let poster: String?
    let source: String
    let sourceName: String
    let year: String?
    let remarks: String?

    var uniqueKey: String { "\(source)_\(id)" }
}

struct ExternalSubtitleTrack: Identifiable, Hashable {
    let id: String
    let label: String
    let language: String
    let url: String
}

struct MediaDetail: Hashable {
    let id: String
    let title: String
    let poster: String?
    let description: String?
    let year: String?
    let source: String
    let sourceName: String
    let episodes: [EpisodeItem]
    let subtitles: [ExternalSubtitleTrack]
}

struct EpisodeItem: Identifiable, Hashable {
    let index: Int
    let title: String
    let url: String

    var id: String { "\(index)_\(url)" }
}

struct PlayRecord: Identifiable, Hashable {
    let key: String
    let title: String
    let source: String
    let sourceName: String
    let videoId: String
    let cover: String?
    let episodeIndex: Int
    let totalEpisodes: Int
    let playTime: Double
    let totalTime: Double
    let updatedAt: Double

    var id: String { key }

    var progressFraction: Double {
        guard totalTime > 0 else { return 0 }
        return min(max(playTime / totalTime, 0), 1)
    }
}

struct FavoriteItem: Identifiable, Hashable {
    let key: String
    let title: String
    let source: String
    let sourceName: String
    let videoId: String
    let cover: String?
    let year: String?

    var id: String { key }
}

enum MoonTVError: LocalizedError {
    case invalidURL
    case notConfigured
    case unauthorized
    case httpError(Int, String)
    case decodingFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid server address. Use format like 192.168.1.50:3000 or http://raspberrypi.local:3000."
        case .notConfigured:
            return "Server address is not configured."
        case .unauthorized:
            return "Authentication failed. Check your username and password."
        case .httpError(let code, let body):
            return "Server returned HTTP \(code). \(body.prefix(120))"
        case .decodingFailed(let detail):
            return "Could not parse backend response: \(detail)"
        }
    }
}
