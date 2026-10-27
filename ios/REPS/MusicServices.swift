import Foundation
import Combine
import UIKit

#if canImport(MusicKit)
import MusicKit
#endif

/// Apple Music 接入结果（不直接暴露 MusicKit 类型，UI 层不依赖具体框架）
struct AppleMusicResult: Identifiable, Equatable {
    let id: String
    let title: String
    let artist: String
    let artworkURL: URL?
    let url: URL?
}

enum MusicLinkState: Equatable {
    case unknown          // 尚未授权
    case authorized       // 已授权，可搜曲库
    case denied           // 被拒绝
    case unavailable      // 系统不支持
}

/// Apple Music 接入。
///
/// 真正的 MusicKit 播放需要 `com.apple.developer.musickit` entitlement，
/// 免费 Apple ID 签名拿不到。所以策略是：
///   能授权 → 搜 Apple Music 曲库，点结果唤起 Apple Music 播放
///   不能授权 → 自动降级为跳转搜索页，体验不断
final class AppleMusicService: ObservableObject {
    static let shared = AppleMusicService()

    @Published private(set) var state: MusicLinkState = .unknown
    @Published private(set) var results: [AppleMusicResult] = []
    @Published private(set) var isSearching = false
    @Published var message: String?

    private init() {
        refreshState()
    }

    func refreshState() {
        #if canImport(MusicKit)
        let s = MusicAuthorization.currentStatus
        let mapped: MusicLinkState
        switch s {
        case .authorized: mapped = .authorized
        case .denied, .restricted: mapped = .denied
        default: mapped = .unknown
        }
        DispatchQueue.main.async { self.state = mapped }
        #else
        DispatchQueue.main.async { self.state = .unavailable }
        #endif
    }

    func requestAuthorization() {
        #if canImport(MusicKit)
        Task {
            let status = await MusicAuthorization.request()
            let mapped: MusicLinkState
            switch status {
            case .authorized: mapped = .authorized
            case .denied, .restricted: mapped = .denied
            default: mapped = .unknown
            }
            await MainActor.run { self.state = mapped }
        }
        #else
        state = .unavailable
        #endif
    }

    func search(_ term: String) {
        let q = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }

        #if canImport(MusicKit)
        guard state == .authorized else {
            message = "未授权 Apple Music，已改为跳转搜索"
            openAppleMusicSearch(q)
            return
        }
        isSearching = true
        Task {
            do {
                var request = MusicCatalogSearchRequest(term: q, types: [Song.self])
                request.limit = 20
                let response = try await request.response()
                let mapped: [AppleMusicResult] = response.songs.map { song in
                    AppleMusicResult(id: song.id.rawValue,
                                     title: song.title,
                                     artist: song.artistName,
                                     artworkURL: song.artwork?.url(width: 200, height: 200),
                                     url: song.url)
                }
                await MainActor.run {
                    self.results = mapped
                    self.isSearching = false
                    if mapped.isEmpty { self.message = "Apple Music 里没搜到「\(q)」" }
                }
            } catch {
                await MainActor.run {
                    self.isSearching = false
                    self.message = "搜索失败，已改为跳转 Apple Music"
                    self.openAppleMusicSearch(q)
                }
            }
        }
        #else
        openAppleMusicSearch(q)
        #endif
    }

    // MARK: - 跳转

    func openAppleMusicSearch(_ term: String? = nil) {
        var url: URL?
        if let term = term,
           let encoded = term.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
            url = URL(string: "https://music.apple.com/cn/search?term=\(encoded)")
        }
        if url == nil { url = URL(string: "music://") }
        guard let target = url else { return }
        DispatchQueue.main.async {
            UIApplication.shared.open(target)
        }
    }

    func openResult(_ r: AppleMusicResult) {
        if let url = r.url {
            UIApplication.shared.open(url)
        } else {
            openAppleMusicSearch("\(r.title) \(r.artist)")
        }
    }
}

// MARK: - 网易云音乐

/// 网易云没有对外开放的第三方播放 API，只能通过 URL Scheme 唤起官方 App 或走网页。
/// 这里做的是「把关键词带过去」，播放交给官方客户端。
enum NeteaseService {
    @discardableResult
    static func openApp() -> Bool {
        guard let url = URL(string: "orpheus://") else { return false }
        if UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url)
            return true
        }
        if let web = URL(string: "https://music.163.com/") {
            UIApplication.shared.open(web)
            return true
        }
        return false
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
