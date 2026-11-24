import AVFoundation
import Foundation

/// Intercepts HLS (.m3u8) playlists via a custom URL scheme, strips spliced ad segments
/// (such as short #EXT-X-DISCONTINUITY blocks and ad-domain chunks like MoonTVPlus),
/// and resolves segment URLs to absolute HTTP(S) paths so AVPlayer fetches video directly.
final class HLSAdBlockLoader: NSObject, AVAssetResourceLoaderDelegate {
    static let customHTTPScheme = "moontv-http"
    static let customHTTPSScheme = "moontv-https"

    private let session: URLSession
    private let adKeywords = ["adjump", "/ad/", "/ads/", "advert", "commercial", "doubleclick", "googlesyndication"]

    override init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        self.session = URLSession(configuration: config)
        super.init()
    }

    static func rewriteURLForAdBlock(_ url: URL) -> URL {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url
        }
        let lowerPath = url.path.lowercased()
        let isPlaylist = lowerPath.contains(".m3u8") || lowerPath.contains("m3u8")
        guard isPlaylist else { return url }

        if components.scheme?.lowercased() == "https" {
            components.scheme = customHTTPSScheme
        } else if components.scheme?.lowercased() == "http" {
            components.scheme = customHTTPScheme
        }
        return components.url ?? url
    }

    private static func restoreOriginalURL(_ url: URL) -> URL? {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }
        if components.scheme == customHTTPSScheme {
            components.scheme = "https"
        } else if components.scheme == customHTTPScheme {
            components.scheme = "http"
        }
        return components.url
    }

    func resourceLoader(
        _ resourceLoader: AVAssetResourceLoader,
        shouldWaitForLoadingOfRequestedResource loadingRequest: AVAssetResourceLoadingRequest
    ) -> Bool {
        guard let requestURL = loadingRequest.request.url,
              let originalURL = Self.restoreOriginalURL(requestURL) else {
            return false
        }

        Task {
            do {
                let (data, response) = try await session.data(from: originalURL)
                let finalURL = response.url ?? originalURL
                guard let text = String(data: data, encoding: .utf8) else {
                    loadingRequest.finishLoading(with: NSError(domain: "HLSAdBlock", code: -1))
                    return
                }

                let cleanedText = processPlaylist(text, baseURL: finalURL)
                let cleanedData = Data(cleanedText.utf8)

                if let infoRequest = loadingRequest.contentInformationRequest {
                    infoRequest.contentType = "public.m3u-playlist"
                    infoRequest.isByteRangeAccessSupported = false
                    infoRequest.contentLength = Int64(cleanedData.count)
                }
                loadingRequest.dataRequest?.respond(with: cleanedData)
                loadingRequest.finishLoading()
            } catch {
                loadingRequest.finishLoading(with: error)
            }
        }
        return true
    }

    private func processPlaylist(_ content: String, baseURL: URL) -> String {
        let lines = content.components(separatedBy: .newlines)

        if content.contains("#EXT-X-STREAM-INF") {
            return lines.map { line -> String in
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return "" }
                if trimmed.hasPrefix("#") {
                    return resolveQuotedURIs(in: trimmed, baseURL: baseURL, wrapPlaylist: true)
                }
                if let resolved = URL(string: trimmed, relativeTo: baseURL)?.absoluteURL {
                    return Self.rewriteURLForAdBlock(resolved).absoluteString
                }
                return trimmed
            }.joined(separator: "\n")
        }

        var headerLines: [String] = []
        var footerLines: [String] = []
        var blocks: [[SegmentEntry]] = [[]]
        var pendingTags: [String] = []
        var seenFirstSegment = false

        for rawLine in lines {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }

            if line == "#EXT-X-ENDLIST" {
                footerLines.append(line)
                continue
            }

            if line == "#EXT-X-DISCONTINUITY" {
                if !blocks[blocks.count - 1].isEmpty {
                    blocks.append([])
                }
                continue
            }

            if line.hasPrefix("#") {
                let resolvedTag = resolveQuotedURIs(in: line, baseURL: baseURL, wrapPlaylist: false)
                if !seenFirstSegment && !line.hasPrefix("#EXTINF") && !line.hasPrefix("#EXT-X-BYTERANGE") && !line.hasPrefix("#EXT-X-KEY") {
                    headerLines.append(resolvedTag)
                } else {
                    pendingTags.append(resolvedTag)
                }
            } else {
                seenFirstSegment = true
                let resolvedURL = URL(string: line, relativeTo: baseURL)?.absoluteURL.absoluteString ?? line
                let duration = extractDuration(from: pendingTags)
                let entry = SegmentEntry(tags: pendingTags, uri: resolvedURL, duration: duration)
                blocks[blocks.count - 1].append(entry)
                pendingTags = []
            }
        }

        let nonEmptyBlocks = blocks.filter { !$0.isEmpty }
        guard !nonEmptyBlocks.isEmpty else { return content }

        let dominantSignature = findDominantPathSignature(in: nonEmptyBlocks)

        var output: [String] = headerLines
        var keptBlockCount = 0

        for (blockIdx, block) in nonEmptyBlocks.enumerated() {
            let totalDuration = block.reduce(0.0) { $0 + $1.duration }
            let hasAdKeyword = block.contains { entry in
                let lower = entry.uri.lowercased()
                return adKeywords.contains { lower.contains($0) }
            }

            let blockSignature = block.first.map { pathSignature(for: $0.uri) }
            let isMismatchedShortSplice = nonEmptyBlocks.count > 1
                && blockIdx > 0
                && blockSignature != dominantSignature
                && totalDuration < 45.0

            let isIsolatedTinyDiscontinuity = nonEmptyBlocks.count > 2
                && blockIdx > 0
                && block.count <= 8
                && totalDuration < 35.0
                && blockSignature != dominantSignature

            if hasAdKeyword || isMismatchedShortSplice || isIsolatedTinyDiscontinuity {
                continue
            }

            if keptBlockCount > 0 {
                output.append("#EXT-X-DISCONTINUITY")
            }
            for entry in block {
                output.append(contentsOf: entry.tags)
                output.append(entry.uri)
            }
            keptBlockCount += 1
        }

        output.append(contentsOf: footerLines)
        return output.joined(separator: "\n")
    }

    private func extractDuration(from tags: [String]) -> Double {
        for tag in tags where tag.hasPrefix("#EXTINF:") {
            let payload = tag.dropFirst("#EXTINF:".count)
            let numStr = payload.split(separator: ",").first.map(String.init) ?? ""
            if let val = Double(numStr) { return val }
        }
        return 0
    }

    private func pathSignature(for uri: String) -> String {
        guard let url = URL(string: uri) else { return "" }
        let host = url.host ?? ""
        let parent = url.deletingLastPathComponent().path
        return "\(host)\(parent)"
    }

    private func findDominantPathSignature(in blocks: [[SegmentEntry]]) -> String {
        var counts: [String: Int] = [:]
        for block in blocks {
            for entry in block {
                let sig = pathSignature(for: entry.uri)
                counts[sig, default: 0] += 1
            }
        }
        return counts.max(by: { $0.value < $1.value })?.key ?? ""
    }

    private func resolveQuotedURIs(in tagLine: String, baseURL: URL, wrapPlaylist: Bool) -> String {
        guard let range = tagLine.range(of: "URI=\"") else { return tagLine }
        let afterPrefix = tagLine[range.upperBound...]
        guard let endQuote = afterPrefix.firstIndex(of: "\"") else { return tagLine }
        let rawURI = String(afterPrefix[..<endQuote])
        guard let resolved = URL(string: rawURI, relativeTo: baseURL)?.absoluteURL else { return tagLine }
        let replacement = wrapPlaylist ? Self.rewriteURLForAdBlock(resolved).absoluteString : resolved.absoluteString
        return tagLine.replacingCharacters(in: range.upperBound..<endQuote, with: replacement)
    }

    private struct SegmentEntry {
        let tags: [String]
        let uri: String
        let duration: Double
    }
}
