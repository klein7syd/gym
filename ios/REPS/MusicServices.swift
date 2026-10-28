import Foundation
import UIKit

// MARK: - Apple Music 曲库搜索
//
// 用 Apple 官方的 iTunes Search 接口：不需要 entitlement、不需要登录，
// 返回结果里带 30 秒试听直链（previewUrl）和高清封面。
// 这样「搜索 → 点开 → 在 App 里播放」是一条完整链路，
// 不会出现点了之后被甩到别的 App、回来什么都没有的情况。

struct ITunesTrack: Identifiable, Equatable {
    let id: String
    let title: String
    let artist: String
    let album: String
    let artworkSmall: URL?
    let artworkLarge: URL?
    let preview: URL?
    let duration: Double
    let storeURL: URL?

    var hasPreview: Bool { preview != nil }
}

enum ITunesAPI {
    /// 中国大陆区优先，搜不到再落到美国区。
    static func search(_ term: String, limit: Int = 30) async throws -> [ITunesTrack] {
        let q = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return [] }

        var out = try await request(term: q, country: "cn", limit: limit)
        if out.isEmpty {
            out = try await request(term: q, country: "us", limit: limit)
        }
        return out
    }

    private static func request(term: String, country: String, limit: Int) async throws -> [ITunesTrack] {
        var comps = URLComponents(string: "https://itunes.apple.com/search")!
        comps.queryItems = [
            URLQueryItem(name: "term", value: term),
            URLQueryItem(name: "media", value: "music"),
            URLQueryItem(name: "entity", value: "song"),
            URLQueryItem(name: "limit", value: "\(limit)"),
            URLQueryItem(name: "country", value: country),
            URLQueryItem(name: "lang", value: country == "cn" ? "zh_cn" : "en_us")
        ]
        guard let url = comps.url else { return [] }

        var req = URLRequest(url: url)
        req.timeoutInterval = 15
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else { return [] }

        let payload = try JSONDecoder().decode(SearchResponse.self, from: data)
        return payload.results.compactMap { r in
            guard let title = r.trackName, !title.isEmpty else { return nil }
            let small = r.artworkUrl100.flatMap { URL(string: $0) }
            let large = r.artworkUrl100
                .map { $0.replacingOccurrences(of: "100x100", with: "600x600") }
                .flatMap { URL(string: $0) }
            return ITunesTrack(
                id: String(r.trackId ?? 0),
                title: title,
                artist: r.artistName ?? "",
                album: r.collectionName ?? "",
                artworkSmall: small,
                artworkLarge: large,
                preview: r.previewUrl.flatMap { URL(string: $0) },
                duration: Double(r.trackTimeMillis ?? 0) / 1000.0,
                storeURL: r.trackViewUrl.flatMap { URL(string: $0) }
            )
        }
    }

    private struct SearchResponse: Decodable {
        let results: [RawTrack]
    }

    private struct RawTrack: Decodable {
        let trackId: Int?
        let trackName: String?
        let artistName: String?
        let collectionName: String?
        let artworkUrl100: String?
        let previewUrl: String?
        let trackTimeMillis: Int?
        let trackViewUrl: String?
    }
}

// MARK: - 网易云音乐
//
// 网易云没有对外开放的第三方播放接口，能做到的只有把关键词交给官方 App。
// 所以这里只提供「去网易云搜这首歌」的入口，播放交给官方客户端。

enum NeteaseService {
    static func openApp() {
        if let url = URL(string: "orpheus://"), UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url)
            return
        }
        openWeb()
    }

    static func search(_ term: String) {
        let q = term.trimmingCharacters(in: .whitespacesAndNewlines)
        let encoded = q.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        if !q.isEmpty, let app = URL(string: "orpheus://search?keyword=\(encoded)"),
           UIApplication.shared.canOpenURL(app) {
            UIApplication.shared.open(app)
            return
        }
        if let app = URL(string: "orpheus://"), UIApplication.shared.canOpenURL(app) {
            UIApplication.shared.open(app)
            return
        }
        let web = q.isEmpty
            ? "https://music.163.com/"
            : "https://music.163.com/#/search/m/?s=\(encoded)"
        if let url = URL(string: web) { UIApplication.shared.open(url) }
    }

    static func openWeb() {
        if let url = URL(string: "https://music.163.com/") { UIApplication.shared.open(url) }
    }
}
