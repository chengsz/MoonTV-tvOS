import Foundation

struct OpenSubtitleResult: Identifiable, Hashable {
    let id: String
    let fileId: Int
    let fileName: String
    let language: String
    let releaseName: String
    let downloadCount: Int
    let hearingImpaired: Bool
}

enum OpenSubtitlesError: LocalizedError {
    case missingAPIKey
    case httpError(Int, String)
    case downloadLinkMissing

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "Add your free OpenSubtitles.com API key in the Settings tab first."
        case .httpError(let code, let detail):
            return "OpenSubtitles returned HTTP \(code). \(detail.prefix(120))"
        case .downloadLinkMissing:
            return "OpenSubtitles did not return a download link (daily limit may be reached)."
        }
    }
}

actor OpenSubtitlesClient {
    private var apiKey: String = ""
    private var username: String = ""
    private var password: String = ""
    private var bearerToken: String?

    private let baseURL = URL(string: "https://api.opensubtitles.com/api/v1")!
    private let userAgent = "MoonTV-tvOS v1.2"
    private let session: URLSession

    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        self.session = URLSession(configuration: config)
    }

    func configure(apiKey: String, username: String, password: String) {
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedUser = username.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedKey != self.apiKey || trimmedUser != self.username || password != self.password {
            self.bearerToken = nil
        }
        self.apiKey = trimmedKey
        self.username = trimmedUser
        self.password = password
    }

    func search(query: String, language: String) async throws -> [OpenSubtitleResult] {
        guard !apiKey.isEmpty else { throw OpenSubtitlesError.missingAPIKey }

        var components = URLComponents(url: baseURL.appendingPathComponent("subtitles"), resolvingAgainstBaseURL: false)
        var items = [URLQueryItem(name: "query", value: query)]
        if !language.isEmpty && language != "all" {
            items.append(URLQueryItem(name: "languages", value: language))
        }
        components?.queryItems = items
        guard let url = components?.url else { return [] }

        var request = URLRequest(url: url)
        applyHeaders(&request)

        let (data, response) = try await session.data(for: request)
        try validate(response, data: data)

        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rows = root["data"] as? [[String: Any]] else {
            return []
        }

        return rows.compactMap { row in
            guard let attrs = row["attributes"] as? [String: Any],
                  let files = attrs["files"] as? [[String: Any]],
                  let firstFile = files.first,
                  let fileId = firstFile["file_id"] as? Int else {
                return nil
            }
            let id = (row["id"] as? String) ?? "\(fileId)"
            let fileName = (firstFile["file_name"] as? String) ?? "Subtitle #\(fileId)"
            let lang = (attrs["language"] as? String) ?? "unknown"
            let release = (attrs["release"] as? String) ?? fileName
            let downloads = (attrs["download_count"] as? Int) ?? 0
            let hi = (attrs["hearing_impaired"] as? Bool) ?? false

            return OpenSubtitleResult(
                id: id,
                fileId: fileId,
                fileName: fileName,
                language: lang,
                releaseName: release,
                downloadCount: downloads,
                hearingImpaired: hi
            )
        }
    }

    func downloadSubtitleText(fileId: Int) async throws -> String {
        guard !apiKey.isEmpty else { throw OpenSubtitlesError.missingAPIKey }

        if bearerToken == nil && !username.isEmpty && !password.isEmpty {
            try? await login()
        }

        let url = baseURL.appendingPathComponent("download")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        applyHeaders(&request)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let bearerToken {
            request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: ["file_id": fileId])

        let (data, response) = try await session.data(for: request)
        try validate(response, data: data)

        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let link = root["link"] as? String,
              let downloadURL = URL(string: link) else {
            throw OpenSubtitlesError.downloadLinkMissing
        }

        let (subData, subResponse) = try await session.data(from: downloadURL)
        try validate(subResponse, data: subData)
        return String(data: subData, encoding: .utf8)
            ?? String(data: subData, encoding: .isoLatin1)
            ?? ""
    }

    func downloadRawURL(_ urlString: String) async throws -> String {
        guard let url = URL(string: urlString) else { return "" }
        let (data, response) = try await session.data(from: url)
        try validate(response, data: data)
        return String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .isoLatin1)
            ?? ""
    }

    private func login() async throws {
        let url = baseURL.appendingPathComponent("login")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        applyHeaders(&request)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "username": username,
            "password": password
        ])

        let (data, response) = try await session.data(for: request)
        try validate(response, data: data)
        if let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let token = root["token"] as? String {
            self.bearerToken = token
        }
    }

    private func applyHeaders(_ request: inout URLRequest) {
        request.setValue(apiKey, forHTTPHeaderField: "Api-Key")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
    }

    private func validate(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard (200...299).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw OpenSubtitlesError.httpError(http.statusCode, body)
        }
    }
}
