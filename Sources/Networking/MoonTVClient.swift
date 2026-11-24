import Foundation

actor MoonTVClient {
    private var baseURL: URL?
    private let session: URLSession

    init() {
        let config = URLSessionConfiguration.default
        config.httpCookieStorage = .shared
        config.httpShouldSetCookies = true
        config.httpCookieAcceptPolicy = .always
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 30
        self.session = URLSession(configuration: config)
    }

    func configure(baseURL: URL) {
        self.baseURL = baseURL
    }

    func currentBaseURL() -> URL? {
        baseURL
    }

    static func normalizeBaseURL(_ raw: String) -> URL? {
        var trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if !trimmed.lowercased().hasPrefix("http://") && !trimmed.lowercased().hasPrefix("https://") {
            trimmed = "http://\(trimmed)"
        }
        while trimmed.hasSuffix("/") {
            trimmed.removeLast()
        }
        guard let url = URL(string: trimmed), url.host != nil else {
            return nil
        }
        return url
    }

    func proxiedImageURL(for rawURL: String?) -> URL? {
        guard let rawURL, !rawURL.isEmpty else { return nil }
        guard let baseURL else { return URL(string: rawURL) }
        var components = URLComponents(url: baseURL.appendingPathComponent("api/image-proxy"), resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "url", value: rawURL)]
        return components?.url ?? URL(string: rawURL)
    }

    // MARK: - Auth & Health

    func login(username: String, password: String) async throws {
        let url = try endpointURL("api/login")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        var payload: [String: String] = ["password": password]
        if !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            payload["username"] = username.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { return }
        if http.statusCode == 401 || http.statusCode == 403 {
            throw MoonTVError.unauthorized
        }
        guard (200...299).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw MoonTVError.httpError(http.statusCode, body)
        }
    }

    func verifyServerConfig() async throws {
        let url = try endpointURL("api/server-config")
        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse else { return }
        if http.statusCode == 401 || http.statusCode == 403 {
            throw MoonTVError.unauthorized
        }
        guard (200...299).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw MoonTVError.httpError(http.statusCode, body)
        }
    }

    // MARK: - Douban & Categories

    func fetchDouban(type: String, tag: String, pageSize: Int = 20, pageStart: Int = 0) async throws -> [DoubanItem] {
        let data = try await get(
            path: "api/douban",
            queryItems: [
                URLQueryItem(name: "type", value: type),
                URLQueryItem(name: "tag", value: tag),
                URLQueryItem(name: "pageSize", value: String(pageSize)),
                URLQueryItem(name: "pageStart", value: String(pageStart))
            ]
        )

        guard let raw = try? JSONSerialization.jsonObject(with: data) else { return [] }
        let list: [[String: Any]]
        if let arr = raw as? [[String: Any]] {
            list = arr
        } else if let dict = raw as? [String: Any] {
            list = (dict["list"] as? [[String: Any]])
                ?? (dict["subjects"] as? [[String: Any]])
                ?? (dict["data"] as? [[String: Any]])
                ?? []
        } else {
            return []
        }

        return list.enumerated().compactMap { idx, item in
            guard let title = stringValue(item, keys: ["title", "name"]) else { return nil }
            let id = stringValue(item, keys: ["id"]) ?? "\(type)_\(idx)_\(title)"
            return DoubanItem(
                id: id,
                title: title,
                poster: stringValue(item, keys: ["poster", "cover", "pic"]),
                rate: stringValue(item, keys: ["rate", "rating", "score"]),
                year: stringValue(item, keys: ["year"]),
                type: type
            )
        }
    }

    func fetchCategories() async throws -> [CategoryFilter] {
        let data = try await get(path: "api/categories")
        guard let raw = try? JSONSerialization.jsonObject(with: data) else { return [] }
        let list: [[String: Any]]
        if let arr = raw as? [[String: Any]] {
            list = arr
        } else if let dict = raw as? [String: Any] {
            list = (dict["categories"] as? [[String: Any]])
                ?? (dict["custom_category"] as? [[String: Any]])
                ?? (dict["data"] as? [[String: Any]])
                ?? []
        } else {
            return []
        }

        let parsed: [CategoryFilter] = list.enumerated().compactMap { idx, item in
            guard let name = stringValue(item, keys: ["name", "title", "label"]) else { return nil }
            let type = stringValue(item, keys: ["type"]) ?? "movie"
            let tag = stringValue(item, keys: ["query", "tag", "name"]) ?? name
            return CategoryFilter(id: "cat_\(idx)_\(name)", label: name, type: type, tag: tag)
        }
        return parsed.isEmpty ? CategoryFilter.defaults : parsed
    }

    // MARK: - Sources & Search

    func fetchResources() async throws -> [VideoSource] {
        let data = try await get(path: "api/search/resources")
        if let direct = try? JSONDecoder().decode([VideoSource].self, from: data) {
            return direct
        }
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let list = json["resources"] ?? json["data"] ?? json["sites"],
               let listData = try? JSONSerialization.data(withJSONObject: list),
               let decoded = try? JSONDecoder().decode([VideoSource].self, from: listData) {
                return decoded
            }
        }
        return []
    }

    func searchAll(query: String, resources: [VideoSource]) async throws -> [MediaItem] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        if resources.isEmpty {
            let data = try await get(path: "api/search", queryItems: [URLQueryItem(name: "q", value: trimmed)])
            return parseMediaItems(from: data, fallbackSource: "default", fallbackSourceName: "MoonTV")
        }

        return await withTaskGroup(of: [MediaItem].self) { group in
            for source in resources {
                group.addTask {
                    let items = (try? await self.searchSingleSource(query: trimmed, source: source)) ?? []
                    return items
                }
            }
            var combined: [MediaItem] = []
            for await batch in group {
                combined.append(contentsOf: batch)
            }
            return combined
        }
    }

    private func searchSingleSource(query: String, source: VideoSource) async throws -> [MediaItem] {
        let data = try await get(
            path: "api/search/one",
            queryItems: [
                URLQueryItem(name: "q", value: query),
                URLQueryItem(name: "resource", value: source.key)
            ]
        )
        return parseMediaItems(from: data, fallbackSource: source.key, fallbackSourceName: source.name)
    }

    // MARK: - Detail

    func fetchDetail(source: String, id: String, fallbackTitle: String, fallbackSourceName: String) async throws -> MediaDetail {
        let data = try await get(
            path: "api/detail",
            queryItems: [
                URLQueryItem(name: "source", value: source),
                URLQueryItem(name: "id", value: id)
            ]
        )
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw MoonTVError.decodingFailed("Expected JSON object from /api/detail")
        }

        let obj = (root["videoInfo"] as? [String: Any])
            ?? (root["data"] as? [String: Any])
            ?? root

        let title = stringValue(obj, keys: ["title", "vod_name", "name"]) ?? fallbackTitle
        let poster = stringValue(obj, keys: ["poster", "cover", "pic", "vod_pic"])
        let desc = stringValue(obj, keys: ["desc", "description", "vod_content", "overview"])
        let year = stringValue(obj, keys: ["year", "vod_year"])
        let resolvedSourceName = stringValue(obj, keys: ["source_name", "sourceName"]) ?? fallbackSourceName

        let rawEpisodes = (obj["episodes"] as? [Any]) ?? (root["episodes"] as? [Any]) ?? []
        var episodes: [EpisodeItem] = []
        for (idx, item) in rawEpisodes.enumerated() {
            if let urlStr = item as? String, !urlStr.isEmpty {
                episodes.append(EpisodeItem(index: idx, title: "Episode \(idx + 1)", url: urlStr))
            } else if let dict = item as? [String: Any],
                      let urlStr = stringValue(dict, keys: ["playUrl", "url", "link"]),
                      !urlStr.isEmpty {
                let epTitle = stringValue(dict, keys: ["title", "name"]) ?? "Episode \(idx + 1)"
                episodes.append(EpisodeItem(index: idx, title: epTitle, url: urlStr))
            }
        }

        let rawSubs = (obj["subtitles"] as? [[String: Any]])
            ?? (root["subtitles"] as? [[String: Any]])
            ?? (obj["subs"] as? [[String: Any]])
            ?? []
        let subtitles: [ExternalSubtitleTrack] = rawSubs.enumerated().compactMap { idx, dict in
            guard let urlStr = stringValue(dict, keys: ["url", "src", "link"]), !urlStr.isEmpty else {
                return nil
            }
            let label = stringValue(dict, keys: ["label", "name", "title"]) ?? "Track \(idx + 1)"
            let lang = stringValue(dict, keys: ["lang", "language", "srclang"]) ?? "auto"
            return ExternalSubtitleTrack(id: "backend_\(idx)", label: label, language: lang, url: urlStr)
        }

        return MediaDetail(
            id: id,
            title: title,
            poster: poster,
            description: desc,
            year: year,
            source: source,
            sourceName: resolvedSourceName,
            episodes: episodes,
            subtitles: subtitles
        )
    }

    // MARK: - Play Records & Favorites

    func fetchPlayRecords() async throws -> [PlayRecord] {
        let data = try await get(path: "api/playrecords")
        guard let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return []
        }

        var results: [PlayRecord] = []
        for (key, value) in dict {
            guard let item = value as? [String: Any] else { continue }
            let parts = key.split(separator: "+", maxSplits: 1).map(String.init)
            let source = parts.first ?? (stringValue(item, keys: ["source"]) ?? "")
            let videoId = parts.count > 1 ? parts[1] : (stringValue(item, keys: ["id", "video_id"]) ?? key)
            let title = stringValue(item, keys: ["title"]) ?? "Untitled"
            let sourceName = stringValue(item, keys: ["source_name", "sourceName"]) ?? source
            let cover = stringValue(item, keys: ["cover", "poster"])
            let epIndex = intValue(item, keys: ["index", "episodeIndex"]) ?? 1
            let totalEps = intValue(item, keys: ["total_episodes", "totalEpisodes"]) ?? 1
            let playTime = doubleValue(item, keys: ["play_time", "playTime"]) ?? 0
            let totalTime = doubleValue(item, keys: ["total_time", "totalTime"]) ?? 0
            let saveTime = doubleValue(item, keys: ["save_time", "saveTime"]) ?? 0

            results.append(PlayRecord(
                key: key,
                title: title,
                source: source,
                sourceName: sourceName,
                videoId: videoId,
                cover: cover,
                episodeIndex: max(0, epIndex - 1),
                totalEpisodes: totalEps,
                playTime: playTime,
                totalTime: totalTime,
                updatedAt: saveTime
            ))
        }

        return results.sorted { $0.updatedAt > $1.updatedAt }
    }

    func savePlayRecord(
        source: String,
        sourceName: String,
        videoId: String,
        title: String,
        cover: String?,
        episodeIndex: Int,
        totalEpisodes: Int,
        playTime: Double,
        totalTime: Double
    ) async {
        guard let url = try? endpointURL("api/playrecords") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let key = "\(source)+\(videoId)"
        let record: [String: Any] = [
            "title": title,
            "source_name": sourceName,
            "cover": cover ?? "",
            "index": episodeIndex + 1,
            "total_episodes": totalEpisodes,
            "play_time": Int(playTime),
            "total_time": Int(totalTime),
            "save_time": Int(Date().timeIntervalSince1970 * 1000)
        ]
        let body: [String: Any] = ["key": key, "record": record]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        _ = try? await session.data(for: request)
    }

    func fetchFavorites() async throws -> [FavoriteItem] {
        let data = try await get(path: "api/favorites")
        guard let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return []
        }

        var results: [FavoriteItem] = []
        for (key, value) in dict {
            guard let item = value as? [String: Any] else { continue }
            let parts = key.split(separator: "+", maxSplits: 1).map(String.init)
            let source = parts.first ?? ""
            let videoId = parts.count > 1 ? parts[1] : key
            results.append(FavoriteItem(
                key: key,
                title: stringValue(item, keys: ["title"]) ?? "Untitled",
                source: source,
                sourceName: stringValue(item, keys: ["source_name", "sourceName"]) ?? source,
                videoId: videoId,
                cover: stringValue(item, keys: ["cover", "poster"]),
                year: stringValue(item, keys: ["year"])
            ))
        }
        return results
    }

    func setFavorite(
        source: String,
        sourceName: String,
        videoId: String,
        title: String,
        cover: String?,
        year: String?,
        add: Bool
    ) async {
        let key = "\(source)+\(videoId)"
        if add {
            guard let url = try? endpointURL("api/favorites") else { return }
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            let favorite: [String: Any] = [
                "title": title,
                "source_name": sourceName,
                "cover": cover ?? "",
                "year": year ?? "",
                "save_time": Int(Date().timeIntervalSince1970 * 1000)
            ]
            request.httpBody = try? JSONSerialization.data(withJSONObject: ["key": key, "favorite": favorite])
            _ = try? await session.data(for: request)
        } else {
            guard let url = try? endpointURL("api/favorites", queryItems: [URLQueryItem(name: "key", value: key)]) else { return }
            var request = URLRequest(url: url)
            request.httpMethod = "DELETE"
            _ = try? await session.data(for: request)
        }
    }

    // MARK: - Helpers

    private func endpointURL(_ path: String, queryItems: [URLQueryItem] = []) throws -> URL {
        guard let baseURL else { throw MoonTVError.notConfigured }
        var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)
        if !queryItems.isEmpty {
            components?.queryItems = queryItems
        }
        guard let url = components?.url else { throw MoonTVError.invalidURL }
        return url
    }

    private func get(path: String, queryItems: [URLQueryItem] = []) async throws -> Data {
        let url = try endpointURL(path, queryItems: queryItems)
        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse else { return data }
        if http.statusCode == 401 || http.statusCode == 403 {
            throw MoonTVError.unauthorized
        }
        guard (200...299).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw MoonTVError.httpError(http.statusCode, body)
        }
        return data
    }

    private func parseMediaItems(from data: Data, fallbackSource: String, fallbackSourceName: String) -> [MediaItem] {
        guard let raw = try? JSONSerialization.jsonObject(with: data) else { return [] }
        let list: [[String: Any]]
        if let arr = raw as? [[String: Any]] {
            list = arr
        } else if let dict = raw as? [String: Any] {
            list = (dict["results"] as? [[String: Any]])
                ?? (dict["data"] as? [[String: Any]])
                ?? (dict["list"] as? [[String: Any]])
                ?? []
        } else {
            return []
        }

        return list.compactMap { item in
            guard let id = stringValue(item, keys: ["id", "vod_id"]),
                  let title = stringValue(item, keys: ["title", "vod_name", "name"]) else {
                return nil
            }
            return MediaItem(
                id: id,
                title: title,
                poster: stringValue(item, keys: ["poster", "cover", "pic", "vod_pic"]),
                source: stringValue(item, keys: ["source"]) ?? fallbackSource,
                sourceName: stringValue(item, keys: ["source_name", "sourceName"]) ?? fallbackSourceName,
                year: stringValue(item, keys: ["year", "vod_year"]),
                remarks: stringValue(item, keys: ["remarks", "vod_remarks"])
            )
        }
    }

    private func stringValue(_ dict: [String: Any], keys: [String]) -> String? {
        for key in keys {
            if let str = dict[key] as? String, !str.isEmpty { return str }
            if let num = dict[key] as? NSNumber { return num.stringValue }
        }
        return nil
    }

    private func intValue(_ dict: [String: Any], keys: [String]) -> Int? {
        for key in keys {
            if let val = dict[key] as? Int { return val }
            if let num = dict[key] as? NSNumber { return num.intValue }
            if let str = dict[key] as? String, let parsed = Int(str) { return parsed }
        }
        return nil
    }

    private func doubleValue(_ dict: [String: Any], keys: [String]) -> Double? {
        for key in keys {
            if let val = dict[key] as? Double { return val }
            if let num = dict[key] as? NSNumber { return num.doubleValue }
            if let str = dict[key] as? String, let parsed = Double(str) { return parsed }
        }
        return nil
    }
}
