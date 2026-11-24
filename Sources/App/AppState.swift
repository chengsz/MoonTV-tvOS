import Foundation
import SwiftUI

@MainActor
final class AppState: ObservableObject {
    @Published var serverAddress: String {
        didSet { UserDefaults.standard.set(serverAddress, forKey: Keys.serverAddress) }
    }
    @Published var username: String {
        didSet { UserDefaults.standard.set(username, forKey: Keys.username) }
    }
    @Published var password: String {
        didSet { UserDefaults.standard.set(password, forKey: Keys.password) }
    }
    @Published var isConfigured: Bool {
        didSet { UserDefaults.standard.set(isConfigured, forKey: Keys.isConfigured) }
    }

    // Player & Subtitle Preferences
    @Published var adBlockEnabled: Bool {
        didSet { UserDefaults.standard.set(adBlockEnabled, forKey: Keys.adBlockEnabled) }
    }
    @Published var openSubtitlesAPIKey: String {
        didSet {
            UserDefaults.standard.set(openSubtitlesAPIKey, forKey: Keys.openSubtitlesAPIKey)
            Task { await openSubtitles.configure(apiKey: openSubtitlesAPIKey, username: openSubtitlesUsername, password: openSubtitlesPassword) }
        }
    }
    @Published var openSubtitlesUsername: String {
        didSet {
            UserDefaults.standard.set(openSubtitlesUsername, forKey: Keys.openSubtitlesUsername)
            Task { await openSubtitles.configure(apiKey: openSubtitlesAPIKey, username: openSubtitlesUsername, password: openSubtitlesPassword) }
        }
    }
    @Published var openSubtitlesPassword: String {
        didSet {
            UserDefaults.standard.set(openSubtitlesPassword, forKey: Keys.openSubtitlesPassword)
            Task { await openSubtitles.configure(apiKey: openSubtitlesAPIKey, username: openSubtitlesUsername, password: openSubtitlesPassword) }
        }
    }
    @Published var preferredSubtitleLanguage: String {
        didSet { UserDefaults.standard.set(preferredSubtitleLanguage, forKey: Keys.preferredSubtitleLanguage) }
    }

    @Published var resources: [VideoSource] = []
    @Published var playRecords: [PlayRecord] = []
    @Published var favorites: [FavoriteItem] = []
    @Published var doubanMovies: [DoubanItem] = []
    @Published var doubanShows: [DoubanItem] = []
    @Published var categories: [CategoryFilter] = CategoryFilter.defaults
    @Published var lastError: String?

    let client = MoonTVClient()
    let openSubtitles = OpenSubtitlesClient()

    private enum Keys {
        static let serverAddress = "moontv.serverAddress"
        static let username = "moontv.username"
        static let password = "moontv.password"
        static let isConfigured = "moontv.isConfigured"
        static let adBlockEnabled = "moontv.adBlockEnabled"
        static let openSubtitlesAPIKey = "moontv.osApiKey"
        static let openSubtitlesUsername = "moontv.osUsername"
        static let openSubtitlesPassword = "moontv.osPassword"
        static let preferredSubtitleLanguage = "moontv.subLang"
    }

    init() {
        let savedAddress = UserDefaults.standard.string(forKey: Keys.serverAddress) ?? ""
        let savedUsername = UserDefaults.standard.string(forKey: Keys.username) ?? ""
        let savedPassword = UserDefaults.standard.string(forKey: Keys.password) ?? ""
        let savedConfigured = UserDefaults.standard.bool(forKey: Keys.isConfigured)
        let savedAdBlock = UserDefaults.standard.object(forKey: Keys.adBlockEnabled) as? Bool ?? true
        let savedOSKey = UserDefaults.standard.string(forKey: Keys.openSubtitlesAPIKey) ?? ""
        let savedOSUser = UserDefaults.standard.string(forKey: Keys.openSubtitlesUsername) ?? ""
        let savedOSPass = UserDefaults.standard.string(forKey: Keys.openSubtitlesPassword) ?? ""
        let savedLang = UserDefaults.standard.string(forKey: Keys.preferredSubtitleLanguage) ?? "en"

        self.serverAddress = savedAddress
        self.username = savedUsername
        self.password = savedPassword
        self.isConfigured = savedConfigured && !savedAddress.isEmpty
        self.adBlockEnabled = savedAdBlock
        self.openSubtitlesAPIKey = savedOSKey
        self.openSubtitlesUsername = savedOSUser
        self.openSubtitlesPassword = savedOSPass
        self.preferredSubtitleLanguage = savedLang

        if let normalized = MoonTVClient.normalizeBaseURL(savedAddress) {
            Task {
                await client.configure(baseURL: normalized)
            }
        }
        Task {
            await openSubtitles.configure(apiKey: savedOSKey, username: savedOSUser, password: savedOSPass)
        }
    }

    func connectAndLogin(address: String, username: String, password: String) async throws {
        guard let normalizedURL = MoonTVClient.normalizeBaseURL(address) else {
            throw MoonTVError.invalidURL
        }

        await client.configure(baseURL: normalizedURL)

        if !password.isEmpty || !username.isEmpty {
            try await client.login(username: username, password: password)
        }

        try await client.verifyServerConfig()

        self.serverAddress = normalizedURL.absoluteString
        self.username = username
        self.password = password
        self.isConfigured = true
        self.lastError = nil

        await refreshDashboard()
    }

    func refreshDashboard() async {
        async let fetchedResources = client.fetchResources()
        async let fetchedRecords = client.fetchPlayRecords()
        async let fetchedFavorites = client.fetchFavorites()
        async let fetchedMovies = client.fetchDouban(type: "movie", tag: "热门", pageSize: 16, pageStart: 0)
        async let fetchedShows = client.fetchDouban(type: "tv", tag: "热门", pageSize: 16, pageStart: 0)
        async let fetchedCategories = client.fetchCategories()

        self.resources = (try? await fetchedResources) ?? []
        self.playRecords = (try? await fetchedRecords) ?? []
        self.favorites = (try? await fetchedFavorites) ?? []
        self.doubanMovies = (try? await fetchedMovies) ?? []
        self.doubanShows = (try? await fetchedShows) ?? []

        let backendCats = (try? await fetchedCategories) ?? []
        if !backendCats.isEmpty {
            self.categories = backendCats
        }
        self.lastError = nil
    }

    func isFavorited(source: String, videoId: String) -> Bool {
        let key = "\(source)+\(videoId)"
        return favorites.contains { $0.key == key }
    }

    func toggleFavorite(
        source: String,
        sourceName: String,
        videoId: String,
        title: String,
        cover: String?,
        year: String?
    ) async {
        let currentlyFav = isFavorited(source: source, videoId: videoId)
        await client.setFavorite(
            source: source,
            sourceName: sourceName,
            videoId: videoId,
            title: title,
            cover: cover,
            year: year,
            add: !currentlyFav
        )
        self.favorites = (try? await client.fetchFavorites()) ?? self.favorites
    }

    func disconnect() {
        isConfigured = false
        resources = []
        playRecords = []
        favorites = []
        doubanMovies = []
        doubanShows = []
    }
}
