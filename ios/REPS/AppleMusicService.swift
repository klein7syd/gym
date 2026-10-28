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
    /// 资料库全量索引，搜索就遍历它
    private var entries: [Entry] = []
    private var byID: [MPMediaEntityPersistentID: MPMediaItem] = [:]
    /// 专辑索引：id → 整张专辑（含全部曲目）
    private var albumByKey: [String: Album] = [:]
    /// 单曲 → 所属专辑 id
    private var albumKeyByItem: [MPMediaEntityPersistentID: String] = [:]
    /// 专辑列表，保持资料库里的自然顺序
    private var albumOrder: [String] = []
    private let work = DispatchQueue(label: "reps.applemusic.index", qos: .userInitiated)

    /// 一条可搜索记录。文本都做过规范化，另外带上拼音 / 首字母，
    /// 这样中文歌名也能用拼音搜（`qt` → 晴天，`zhoujielun` → 周杰伦）。
    struct Entry {
        let item: MPMediaItem
        let title: String
        let artist: String
        let album: String
        let titleTokens: [String]
        let artistTokens: [String]
        let titlePinyin: String
        let titleInitials: String
        let artistPinyin: String
        let artistInitials: String
    }

    /// 一张专辑：一条记录带整张的曲目，专辑页就是靠它把没搜到的歌也补全。
    struct Album: Identifiable, Hashable {
        let id: String
        let title: String
        let artist: String
        let year: Int
        /// 合辑 / 群星碟：排序时往后放，别把别人的精选集排在本人录音室专辑前面
        let isCompilation: Bool
        let sampleID: MPMediaEntityPersistentID
        let items: [MPMediaItem]

        var displayArtist: String { artist.isEmpty ? "未知艺人" : artist }
        var subtitle: String {
            var parts: [String] = []
            if !artist.isEmpty { parts.append(artist) }
            if year > 0 { parts.append("\(year) 年") }
            return parts.joined(separator: " · ")
        }

        static func == (l: Album, r: Album) -> Bool { l.id == r.id }
        func hash(into h: inout Hasher) { h.combine(id) }
    }

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
    // 全量读一次资料库（几千首），每条记录预先算好：
    //   规范化歌名/艺人/专辑、切好的词、拼音全拼、拼音首字母。
    // 之后搜索就是纯内存遍历 + 打分，不联网、不出资料库范围。
    // 全部在后台队列做，主线程不卡。

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
            var list: [Entry] = []
            exact.reserveCapacity(songs.count)
            list.reserveCapacity(songs.count)

            for it in songs {
                let rawTitle = it.title ?? ""
                guard !rawTitle.isEmpty else { continue }
                let t = Self.normalize(rawTitle)
                guard !t.isEmpty else { continue }
                let rawArtist = it.artist ?? ""
                let a = Self.normalize(rawArtist)
                exact["\(t)|\(a)"] = it
                titles[t, default: []].append(it)
                ids[it.persistentID] = it

                let tp = Self.pinyin(rawTitle)
                let ap = Self.pinyin(rawArtist)
                list.append(Entry(item: it,
                                  title: t,
                                  artist: a,
                                  album: Self.normalize(it.albumTitle ?? ""),
                                  titleTokens: Self.tokens(rawTitle),
                                  artistTokens: Self.tokens(rawArtist),
                                  titlePinyin: tp.full,
                                  titleInitials: tp.initials,
                                  artistPinyin: ap.full,
                                  artistInitials: ap.initials))
            }

            let total = songs.count
            let albums = Self.makeAlbums(songs)
            DispatchQueue.main.async {
                self.byKey = exact
                self.byTitle = titles
                self.byID = ids
                self.entries = list
                self.albumByKey = albums.byKey
                self.albumKeyByItem = albums.keyByItem
                self.albumOrder = albums.order
                self.librarySongCount = total
                self.isIndexing = false
                self.indexBuilt = true
            }
        }
    }

    // MARK: - 专辑索引
    //
    // 搜索结果按专辑排版，点进一张专辑要能列出**整张**的曲目（不只是命中的那几首），
    // 所以这里在后台把「专辑 → 全部曲目」也建一份。
    // 专辑 id 用「专辑名|专辑艺人」，没有专辑名的归到「未知专辑」。

    private static func albumKey(title: String, artist: String) -> String {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { return "\u{2205}" }
        let a = (artist.isEmpty ? "" : artist).trimmingCharacters(in: .whitespacesAndNewlines)
        return "\(t)|\(a)"
    }

    private static func makeAlbums(_ songs: [MPMediaItem])
        -> (byKey: [String: Album], keyByItem: [MPMediaEntityPersistentID: String], order: [String]) {
        var buckets: [String: [MPMediaItem]] = [:]
        var info: [String: (title: String, artist: String, year: Int, comp: Bool)] = [:]
        var keys: [MPMediaEntityPersistentID: String] = [:]
        var order: [String] = []

        for m in songs {
            let title = (m.albumTitle ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let artist = (m.albumArtist ?? m.artist ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let key = albumKey(title: title, artist: artist)
            if buckets[key] == nil {
                order.append(key)
                buckets[key] = []
                var year = 0
                if let d = m.releaseDate {
                    year = Calendar.current.component(.year, from: d)
                }
                info[key] = (title.isEmpty ? "未知专辑" : title, artist, year, false)
            }
            buckets[key]?.append(m)
            if m.isCompilation {
                if let cur = info[key] { info[key] = (cur.title, cur.artist, cur.year, true) }
            }
            keys[m.persistentID] = key
        }

        var albums: [String: Album] = [:]
        for key in order {
            guard let list = buckets[key], let meta = info[key] else { continue }
            let sorted = list.sorted {
                if $0.discNumber != $1.discNumber { return $0.discNumber < $1.discNumber }
                if $0.albumTrackNumber > 0 && $1.albumTrackNumber > 0 &&
                   $0.albumTrackNumber != $1.albumTrackNumber {
                    return $0.albumTrackNumber < $1.albumTrackNumber
                }
                return ($0.title ?? "") < ($1.title ?? "")
            }
            albums[key] = Album(id: key,
                                title: meta.title,
                                artist: meta.artist,
                                year: meta.year,
                                isCompilation: meta.comp,
                                sampleID: sorted.first?.persistentID ?? 0,
                                items: sorted)
        }
        return (albums, keys, order)
    }

    func album(forKey key: String) -> Album? { albumByKey[key] }

    func album(containing item: MPMediaItem) -> Album? {
        guard let key = albumKeyByItem[item.persistentID] else { return nil }
        return albumByKey[key]
    }

    /// 把一批搜索结果按专辑归并，顺序按「第一次出现的先后」，
    /// 这样相关性高的专辑自然排在前面。
    func albums(from hits: [MPMediaItem], matching rawQuery: String = "") -> [Album] {
        var seen = Set<String>()
        var out: [Album] = []
        for m in hits {
            guard let key = albumKeyByItem[m.persistentID],
                  let a = albumByKey[key] else { continue }
            if seen.insert(key).inserted { out.append(a) }
        }
        guard !out.isEmpty else { return out }

        // 排序权重（越小越靠前）：
        //   本人专辑 > 合辑/群星碟 > 只在里面 feats 一句的别人专辑；
        //   再按「曲目多少」区分正式录音室专辑和单曲/EP；最后新的靠前一点。
        // 分数相同就保持搜索结果的相关度顺序，不把高相关的专辑挤下去。
        let q = Self.normalize(rawQuery)
        let various = Self.normalize("Various Artists")

        var scored: [(score: Int, order: Int, album: Album)] = []
        for (i, a) in out.enumerated() {
            let artist = Self.normalize(a.artist)
            var score = 0

            if !q.isEmpty, !artist.isEmpty,
               artist.contains(q) || q.contains(artist) {
                score -= 1000                       // 搜的就是这个艺人 → 他的专辑优先
            }
            if a.isCompilation || artist == various {
                score += 400                        // 合辑往后放
            }
            let n = a.items.count
            if n >= 5 { score -= 60 }                // 正式专辑（曲目多）优先于单曲/EP
            if n >= 10 { score -= 40 }
            if n <= 2 { score += 40 }
            if a.year > 0 {
                score -= min(30, max(0, a.year - 2000) / 2)   // 同年份里新专往前一点
            }
            scored.append((score, i, a))
        }
        scored.sort { $0.score != $1.score ? $0.score < $1.score : $0.order < $1.order }
        return scored.map { $0.album }
    }

    /// 按 persistentID 精确取曲目：这就是「点哪首放哪首」的保证，
    /// 不再靠歌名+艺人去猜，避免放成同名翻唱或别的版本。
    func item(for id: MPMediaEntityPersistentID) -> MPMediaItem? {
        byID[id]
    }

    // MARK: - 搜索
    //
    // 之前那版的问题是「只要包含就收」：搜「晴天」，专辑名里带「晴天」的、
    // 艺人名里带「晴」的全被塞进结果，看起来就是一堆无关的歌。
    //
    // 现在按分数来：
    //   ① 多关键词是 AND —— 输入「周杰伦 稻香」必须两个词都命中才算
    //   ② 每个词分别打分，歌名完全等于 100、歌名里某个词等于 92、歌名前缀 88…
    //      艺人 62 起、专辑 30 起（专辑最容易出噪音，权重压到最低）
    //   ③ 有强命中时设一个相关性下限，把纯靠专辑名擦边命中的结果直接丢掉
    //   ④ 支持拼音：`qt` / `qingtian` 都能搜到「晴天」
    // limit <= 0 表示不截断：资料库里匹配多少就给多少（外面是 LazyVStack，不卡）。
    func search(_ raw: String, limit: Int = 0) -> [MPMediaItem] {
        guard access == .granted, indexBuilt else { return [] }

        let tokens = Self.tokens(raw)
        guard !tokens.isEmpty else { return [] }
        let joined = tokens.joined()
        let isLatin = joined.allSatisfy { $0.isASCII }

        var scored: [(score: Int, order: Int, len: Int, item: MPMediaItem)] = []
        scored.reserveCapacity(64)

        for (i, e) in entries.enumerated() {
            var total = 0
            var matchedAll = true
            for tok in tokens {
                let s = Self.score(token: tok, entry: e, latin: isLatin)
                if s == 0 { matchedAll = false; break }
                total += s
            }
            guard matchedAll else { continue }

            // 多词查询时，整串连在一起出现在歌名里再加一笔
            if tokens.count > 1, e.title.contains(joined) { total += 30 }
            scored.append((total, i, e.title.count, e.item))
        }
        guard !scored.isEmpty else { return [] }

        // 相关性下限：有明确歌名/艺人命中时，纯专辑擦边的结果不展示
        let best = scored.map { $0.score }.max() ?? 0
        let floor = best >= 70 ? max(34, best / 3) : 0

        var out = scored.filter { $0.score >= floor }
        out.sort {
            if $0.score != $1.score { return $0.score > $1.score }
            // 同分时短标题优先（越短越接近完整匹配）
            if $0.len != $1.len { return $0.len < $1.len }
            return $0.order < $1.order
        }
        let mapped = out.map { $0.item }
        return limit > 0 ? Array(mapped.prefix(limit)) : mapped
    }

    private static func score(token: String, entry: Entry, latin: Bool) -> Int {
        let t = entry.title, a = entry.artist, al = entry.album

        // —— 歌名 ——
        if t == token { return 100 }
        if entry.titleTokens.contains(token) { return 92 }
        if t.hasPrefix(token) { return 88 }
        if entry.titleTokens.contains(where: { $0.hasPrefix(token) }) { return 80 }
        if t.contains(token) { return 74 }

        // —— 艺人 ——
        if a == token { return 64 }
        if entry.artistTokens.contains(token) { return 60 }
        if a.hasPrefix(token) { return 56 }
        if a.contains(token) { return 48 }

        // —— 拼音（只对纯字母输入有意义）——
        if latin {
            if entry.titlePinyin == token { return 86 }
            if entry.titleInitials == token { return 82 }
            if entry.titlePinyin.hasPrefix(token) { return 78 }
            if entry.titleInitials.hasPrefix(token) { return 70 }
            if entry.titlePinyin.contains(token) { return 66 }
            if entry.artistPinyin == token { return 58 }
            if entry.artistInitials == token { return 54 }
            if entry.artistPinyin.hasPrefix(token) { return 50 }
        }

        // —— 专辑（权重最低，只作兜底）——
        if al == token { return 32 }
        if al.contains(token) { return 26 }
        return 0
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

    /// 分词：先按空白和各种分隔符切开，每段再规范化。查询和索引都走这套，
    /// 这样「周杰伦 稻香」是两个词（分别命中艺人和歌名），而不是一个拼在一起的长串。
    static func tokens(_ s: String) -> [String] {
        let seps = CharacterSet(charactersIn: " \t\n-–—_·•/\\|,，、;；:：&+()（）[]【】\"'“”‘’")
        return s.components(separatedBy: seps)
            .map { normalize($0) }
            .filter { !$0.isEmpty }
    }

    /// 汉字转拼音：全拼（无声调）+ 首字母。
    static func pinyin(_ s: String) -> (full: String, initials: String) {
        guard !s.isEmpty else { return ("", "") }
        let latin = s.applyingTransform(.toLatin, reverse: false)?
            .applyingTransform(.stripDiacritics, reverse: false) ?? s
        let full = latin.lowercased()
            .replacingOccurrences(of: "[^0-9a-z]+", with: "", options: .regularExpression)
        let initials = latin
            .components(separatedBy: CharacterSet(charactersIn: " \t-–—_·•/\\|,，、;；:：&+()（）[]【】\"'“”‘’"))
            .compactMap { $0.first }
            .map { String($0).lowercased() }
            .joined()
            .replacingOccurrences(of: "[^0-9a-z]+", with: "", options: .regularExpression)
        return (full, initials)
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
