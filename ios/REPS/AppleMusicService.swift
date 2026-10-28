import Foundation
import MediaPlayer
import Combine

// MARK: - Apple Music 完整播放
//
// 约束与取舍（重要）：
// Apple 的 MusicKit 需要 `com.apple.developer.musickit` entitlement 才能播放曲库任意歌曲，
// 而这个 entitlement 只有付费开发者账号在 Developer Portal 里勾选后才拿得到。
// 用 Sideloadly / AltStore 自签装的包一定没有它，所以「用 MusicKit 直接放完整版」这条路
// 在自签环境下是死的 —— 这就是上一版只剩 30 秒试听的根本原因。
//
// 但 iOS 还有一条一直对外开放的路：MediaPlayer 框架。
// 只要用户已订阅 Apple Music、并打开了「同步资料库」，资料库里的歌就能交给
// MPMusicPlayerController 完整播放（走的是 Apple Music 的正式播放通道，不是试听片段）。
// 它只需要 NSAppleMusicUsageDescription + 用户授权，不需要任何 entitlement，
// 自签安装同样有效。
//
// 所以这里的做法是：搜索只搜「自己的资料库」，播放交给 MediaPlayer。
// 这样搜到的每一首都一定能整首放（会员身份直接生效），也不存在「搜出一堆不搭边的歌」，
// 更不会出现「点 A 放成 B」——曲目用 persistentID 精确寻址，不再靠歌名猜。

final class AppleMusicService: ObservableObject {
    static let shared = AppleMusicService()

    enum Access: Equatable {
        case unknown     // 还没问过用户
        case denied      // 拒绝 / 被家长控制限制
        case granted     // 已授权，可读资料库
    }

    @Published private(set) var access: Access = .unknown
    @Published private(set) var isIndexing = false
    @Published private(set) var librarySongCount = 0

    private var indexBuilt = false
    private var byKey: [String: MPMediaItem] = [:]
    private var byTitle: [String: [MPMediaItem]] = [:]
    /// 资料库全量，和 searchKeys 同序，供本地搜索用
    private var items: [MPMediaItem] = []
    private var searchKeys: [(title: String, artist: String, album: String)] = []
    private var byID: [MPMediaEntityPersistentID: MPMediaItem] = [:]
    private let work = DispatchQueue(label: "reps.applemusic.index", qos: .userInitiated)

    /// 系统播放器。applicationMusicPlayer 是 App 内播放，不接管「音乐」App 的播放状态。
    var player: MPMusicPlayerController { MPMusicPlayerController.applicationMusicPlayer }

    var isGranted: Bool { access == .granted }

    private init() {
        refreshStatus()

        // 资料库变动（在别的设备加了歌、Apple Music 里点了 +）时重建索引
        NotificationCenter.default.addObserver(
            forName: Notification.Name(rawValue: "MPMediaLibraryDidChangeNotification"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.buildIndexIfNeeded(force: true)
        }
        MPMediaLibrary.default().beginGeneratingLibraryChangeNotifications()
    }

    // MARK: - 授权

    func refreshStatus() {
        switch MPMediaLibrary.authorizationStatus() {
        case .authorized:
            access = .granted
        case .denied, .restricted:
            access = .denied
        case .notDetermined:
            access = .unknown
        @unknown default:
            access = .unknown
        }
        if access == .granted { buildIndexIfNeeded() }
    }

    /// 弹系统授权框；已授权时直接回调成功。
    func requestAccess(_ done: ((Bool) -> Void)? = nil) {
        if access == .granted {
            buildIndexIfNeeded()
            done?(true)
            return
        }
        MPMediaLibrary.requestAuthorization { status in
            DispatchQueue.main.async {
                self.access = (status == .authorized) ? .granted : .denied
                if self.access == .granted {
                    self.buildIndexIfNeeded()
                    done?(true)
                } else {
                    done?(false)
                }
            }
        }
    }

    // MARK: - 资料库索引
    //
    // 全量读一次资料库（几千首也就几十万字符的规范化），建两张表：
    // 「歌名|艺人」精确表 + 「歌名」倒排表。之后匹配就是纯字典查找。
    // 建索引放后台队列，不卡主线程。

    func buildIndexIfNeeded(force: Bool = false) {
        guard access == .granted else { return }
        if isIndexing { return }
        if indexBuilt && !force { return }

        isIndexing = true
        work.async { [weak self] in
            guard let self = self else { return }
            let songs = MPMediaQuery.songs().items ?? []
            var exact: [String: MPMediaItem] = [:]
            var titles: [String: [MPMediaItem]] = [:]
            var ids: [MPMediaEntityPersistentID: MPMediaItem] = [:]
            var keys: [(title: String, artist: String, album: String)] = []
            exact.reserveCapacity(songs.count)
            keys.reserveCapacity(songs.count)

            for it in songs {
                let rawTitle = it.title ?? ""
                guard !rawTitle.isEmpty else { continue }
                let t = Self.normalize(rawTitle)
                guard !t.isEmpty else { continue }
                let a = Self.normalize(it.artist ?? "")
                exact["\(t)|\(a)"] = it
                titles[t, default: []].append(it)
                ids[it.persistentID] = it
                keys.append((t, a, Self.normalize(it.albumTitle ?? "")))
            }

            let total = songs.count
            DispatchQueue.main.async {
                self.byKey = exact
                self.byTitle = titles
                self.byID = ids
                self.items = songs
                self.searchKeys = keys
                self.librarySongCount = total
                self.isIndexing = false
                self.indexBuilt = true
            }
        }
    }

    /// 按 persistentID 精确取曲目：这就是「点哪首放哪首」的保证，
    /// 不再靠歌名+艺人去猜，避免放成同名翻唱或别的版本。
    func item(for id: MPMediaEntityPersistentID) -> MPMediaItem? {
        byID[id]
    }

    /// 资料库内搜索。全部在本地索引里做，不联网，也不会搜出资料库外的歌。
    /// 排序：歌名前缀 → 歌名包含 → 艺人包含 → 专辑包含。
    func search(_ raw: String, limit: Int = 40) -> [MPMediaItem] {
        guard access == .granted, indexBuilt else { return [] }
        let q = Self.normalize(raw)
        guard !q.isEmpty else { return [] }

        var hits: [(rank: Int, order: Int, item: MPMediaItem)] = []
        for (i, k) in searchKeys.enumerated() {
            var rank = -1
            if k.title.hasPrefix(q) {
                rank = 0
            } else if k.title.contains(q) {
                rank = 1
            } else if k.artist.contains(q) {
                rank = 2
            } else if k.album.contains(q) {
                rank = 3
            }
            guard rank >= 0 else { continue }
            hits.append((rank, i, items[i]))
        }
        hits.sort { $0.rank != $1.rank ? $0.rank < $1.rank : $0.order < $1.order }
        return hits.prefix(limit).map { $0.item }
    }

    /// 按「歌名 + 艺人」在资料库里兜底匹配（只在 PlayItem 没带 persistentID 时用）。
    func match(title: String, artist: String) -> MPMediaItem? {
        guard access == .granted, indexBuilt else { return nil }
        let t = Self.normalize(title)
        guard !t.isEmpty else { return nil }
        let a = Self.normalize(artist)

        if let hit = byKey["\(t)|\(a)"] { return hit }
        if let list = byTitle[t], !list.isEmpty {
            if list.count == 1 { return list[0] }
            if !a.isEmpty {
                for it in list {
                    let ia = Self.normalize(it.artist ?? "")
                    if !ia.isEmpty && (ia.contains(a) || a.contains(ia)) { return it }
                }
            }
            return list.first
        }
        return nil
    }

    func isPlayableInFull(title: String, artist: String) -> Bool {
        match(title: title, artist: artist) != nil
    }

    /// 统一规范化：小写、去括号里的版本说明、去 feat. 后缀、去标点空格。
    /// 目的是让「稻香 (Live)」「稻香 - Live」都能对到资料库里的「稻香」。
    static func normalize(_ s: String) -> String {
        var t = s.lowercased()
        t = t.replacingOccurrences(of: "\\([^)]*\\)", with: "", options: .regularExpression)
        t = t.replacingOccurrences(of: "（[^）]*）", with: "", options: .regularExpression)
        t = t.replacingOccurrences(of: "\\[[^\\]]*\\]", with: "", options: .regularExpression)
        t = t.replacingOccurrences(of: "(feat\\.?|ft\\.?|featuring)\\s.*$", with: "", options: .regularExpression)
        t = t.replacingOccurrences(of: "[^0-9a-z\\p{Han}]+", with: "", options: .regularExpression)
        return t
    }

    // MARK: - 播放控制

    /// 用资料库里的曲目组队列播放。items 顺序就是队列顺序。
    @discardableResult
    func play(_ items: [MPMediaItem], startingAt i: Int, repeatMode: MPMusicRepeatMode) -> Bool {
        guard !items.isEmpty, items.indices.contains(i) else { return false }
        let mp = player
        mp.stop()
        mp.setQueue(with: MPMediaItemCollection(items: items))
        mp.nowPlayingItem = items[i]
        mp.repeatMode = repeatMode
        mp.play()
        return true
    }

    func setRepeat(_ mode: MPMusicRepeatMode) {
        player.repeatMode = mode
    }

    /// 账号没订阅 / 资料库为空时，用来解释「为什么只能试听」。
    var statusHint: String {
        switch access {
        case .unknown: return "还没授权读取 Apple Music 资料库"
        case .denied: return "资料库权限被拒绝，去系统设置里打开"
        case .granted:
            if isIndexing { return "正在读取资料库…" }
            if librarySongCount == 0 { return "资料库是空的，先把歌加进 Apple Music 资料库" }
            return "资料库 \(librarySongCount) 首可完整播放"
        }
    }
}
