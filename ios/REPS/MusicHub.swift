import Foundation
import AVFoundation
import MediaPlayer
import Combine
import UIKit
import SwiftUI   // remove(atOffsets:) 来自 SwiftUI 对集合的扩展

// MARK: - 可播放条目

/// 本地文件、Apple Music 曲库歌曲、试听片段都走同一个条目模型。
/// source 表示「这首歌本来想怎么放」：
///   .local      —— 沙盒里的文件，AVPlayer 直接放
///   .appleMusic —— 曲库歌曲，优先交给系统播放器放完整版，失败再退回试听
///   .preview    —— 没有完整版可用，只放 30 秒官方试听
struct PlayItem: Identifiable, Equatable {
    enum Source: String {
        case local
        case preview
        case appleMusic
    }

    let id: String
    let title: String
    let artist: String
    let artworkURL: URL?
    let fileURL: URL?          // 本地文件路径，或试听直链
    let externalURL: URL?      // 去 Apple Music 打开这首歌
    let fullDuration: Double   // 完整曲目时长（只作参考，实际以播放器为准）
    let source: Source
    /// 资料库曲目的唯一标识。有它就绝对不会放错歌（点哪首放哪首）。
    var mediaID: MPMediaEntityPersistentID? = nil

    var isPreview: Bool { source == .preview }

    var subtitle: String {
        switch source {
        case .local: return "本地音乐"
        case .preview: return "30 秒试听"
        case .appleMusic: return "Apple Music 完整版"
        }
    }
}

// MARK: - 播放中枢

/// 全局唯一的播放器。两种引擎：
///   .av          —— AVPlayer，放本地文件和试听片段
///   .appleMusic  —— MPMusicPlayerController，放资料库里的完整曲目
/// 对外只暴露一套控制、一套锁屏信息、一套控制中心命令，
/// 上层界面不需要关心当前是哪台引擎在响。
final class MusicHub: NSObject, ObservableObject {
    static let shared = MusicHub()

    enum Engine {
        case none
        case av
        case appleMusic
    }

    enum RepeatMode: String, CaseIterable {
        case off
        case all
        case one

        var next: RepeatMode {
            switch self {
            case .off: return .all
            case .all: return .one
            case .one: return .off
            }
        }
        var symbol: String { self == .one ? "repeat.1" : "repeat" }
        var isOn: Bool { self != .off }
        var label: String {
            switch self {
            case .off: return "不循环"
            case .all: return "列表循环"
            case .one: return "单曲循环"
            }
        }
    }

    @Published private(set) var queue: [PlayItem] = []
    @Published private(set) var index: Int = 0
    @Published private(set) var isPlaying = false
    @Published private(set) var currentTime: Double = 0
    @Published private(set) var duration: Double = 0
    @Published private(set) var errorMessage: String?
    @Published private(set) var engine: Engine = .none


    @Published var repeatMode: RepeatMode = .off {
        didSet {
            if engine == .appleMusic {
                AppleMusicService.shared.setRepeat(mpRepeatMode)
            }
            updateNowPlaying()
        }
    }

    private var player: AVPlayer?
    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?
    private var ticker: Timer?
    /// 拖动进度条刚 seek 完的保护期：这段时间内不采用轮询回来的时间
    private var seekGuardUntil = Date.distantPast
    private let store = Store.shared

    /// 跟系统播放器打交道专用：串行队列，避免并发设队列互相覆盖
    private let mpQueue = DispatchQueue(label: "reps.musicplayer", qos: .userInitiated)
    /// 上次交给系统播放器的曲目序列。相同就不重建队列（setQueue 很贵）
    private var mpQueueSignature: [MPMediaEntityPersistentID] = []
    /// 连点保护：只有最后一次装载生效
    private let tokenLock = NSLock()
    private var _loadToken = 0

    /// 系统播放器队列里的位置 → 我们自己 queue 里的位置。
    /// 完整版队列会跳过那些没匹配上的歌，所以两张下标不是一一对应的。
    private var indexMap: [Int]?

    var current: PlayItem? {
        queue.indices.contains(index) ? queue[index] : nil
    }
    var hasQueue: Bool { !queue.isEmpty }

    /// 当前这首是不是真在放完整版（用于界面标注，避免再说空话）
    var isPlayingFullVersion: Bool {
        engine == .appleMusic
    }

    private override init() {
        super.init()
        configureSession()
        configureRemoteCommands()
    }

    // MARK: - 音频会话与锁屏

    private func configureSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [])
            try session.setActive(true)
        } catch {
            errorMessage = "音频会话启动失败"
        }
    }

    private var mpRepeatMode: MPMusicRepeatMode {
        switch repeatMode {
        case .off: return MPMusicRepeatMode.none
        case .all: return MPMusicRepeatMode.all
        case .one: return MPMusicRepeatMode.one
        }
    }

    /// 取下一个装载令牌（主线程调）
    private func bumpToken() -> Int {
        tokenLock.lock(); defer { tokenLock.unlock() }
        _loadToken &+= 1
        return _loadToken
    }

    /// 后台队列里读「当前最新令牌」，用来判断自己是不是已经被后来的点击取代
    private var currentLoadToken: Int {
        tokenLock.lock(); defer { tokenLock.unlock() }
        return _loadToken
    }

    private func configureRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.addTarget { [weak self] _ in
            self?.resume()
            return .success
        }
        center.pauseCommand.addTarget { [weak self] _ in
            self?.pause()
            return .success
        }
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            self?.toggle()
            return .success
        }
        center.nextTrackCommand.addTarget { [weak self] _ in
            self?.next(userInitiated: true)
            return .success
        }
        center.previousTrackCommand.addTarget { [weak self] _ in
            self?.previous()
            return .success
        }
        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let e = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            self?.seek(to: e.positionTime)
            return .success
        }
    }

    private func updateNowPlaying() {
        // 完整版由系统投送锁屏信息（歌名、封面、时长都是 Apple Music 自己的元数据），
        // 我们再写一遍反而会把锁屏搞乱，所以这里直接让位。
        if engine == .appleMusic { return }

        var info = [String: Any]()
        info[MPMediaItemPropertyTitle] = current?.title ?? "REPS"
        info[MPMediaItemPropertyArtist] = current?.artist.isEmpty == false
            ? current?.artist
            : (current?.subtitle ?? "REPS")
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = currentTime
        info[MPMediaItemPropertyPlaybackDuration] = duration
        info[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? 1.0 : 0.0
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    // MARK: - 对外播放控制

    /// 用一批曲目开始播，从第 i 首起。
    func play(items: [PlayItem], startingAt i: Int) {
        guard !items.isEmpty else { return }
        errorMessage = nil
        queue = items
        load(index: max(0, min(i, items.count - 1)), autoplay: true)
    }

    func playSingle(_ item: PlayItem) {
        play(items: [item], startingAt: 0)
    }

    func toggle() {
        if isPlaying { pause() } else { resume() }
    }

    func resume() {
        if engine == .appleMusic {
            AppleMusicService.shared.player.play()
            isPlaying = true
            return
        }
        if player == nil {
            guard !queue.isEmpty else { return }
            load(index: index, autoplay: true)
            return
        }
        player?.play()
        isPlaying = true
        updateNowPlaying()
    }

    func pause() {
        if engine == .appleMusic {
            AppleMusicService.shared.player.pause()
        } else {
            player?.pause()
        }
        isPlaying = false
        updateNowPlaying()
    }

    func stop() {
        if engine == .appleMusic {
            AppleMusicService.shared.player.stop()
        }
        tearDownAV()
        stopTicker()
        engine = .none
        indexMap = nil
        mpQueueSignature = []
        _ = bumpToken()
        queue = []
        index = 0
        currentTime = 0
        duration = 0
        isPlaying = false
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    func next(userInitiated: Bool = false) {
        guard !queue.isEmpty else { return }

        if engine == .appleMusic {
            let mp = AppleMusicService.shared.player
            if repeatMode == .one {
                seek(to: 0)
                mp.play()
                isPlaying = true
                return
            }
            // 队列里下一首还能完整播，就交给系统 skip，衔接更顺
            if let map = indexMap,
               let p = map.firstIndex(of: index),
               map.indices.contains(p + 1) {
                mp.skipToNextItem()
                index = map[p + 1]
                currentTime = 0
                if let d = mp.nowPlayingItem?.playbackDuration, d > 0 { duration = d }
                isPlaying = true
                return
            }
            let target = (index + 1) % queue.count
            load(index: target, autoplay: true)
            return
        }

        if index + 1 >= queue.count {
            if userInitiated && repeatMode != .one {
                load(index: 0, autoplay: true)   // 手动点下一首就绕回开头
            } else if repeatMode == .one {
                seek(to: 0)
                player?.play()
                isPlaying = true
            } else {
                load(index: 0, autoplay: true)
            }
            return
        }
        load(index: index + 1, autoplay: true)
    }

    func previous() {
        guard !queue.isEmpty else { return }

        if engine == .appleMusic {
            let mp = AppleMusicService.shared.player
            if currentTime > 3 {
                seek(to: 0)
                return
            }
            if let map = indexMap,
               let p = map.firstIndex(of: index),
               p > 0 {
                mp.skipToPreviousItem()
                index = map[p - 1]
                currentTime = 0
                if let d = mp.nowPlayingItem?.playbackDuration, d > 0 { duration = d }
                isPlaying = true
                return
            }
            load(index: (index - 1 + queue.count) % queue.count, autoplay: true)
            return
        }

        if currentTime > 3 {
            seek(to: 0)
            return
        }
        load(index: (index - 1 + queue.count) % queue.count, autoplay: true)
    }

    /// 把当前播放器从一个队列位置跳到另一首（搜索结果、播放列表里点歌用）。
    func jump(to i: Int) {
        guard queue.indices.contains(i) else { return }
        load(index: i, autoplay: true)
    }

    func seek(to seconds: Double) {
        let t = max(0, seconds)
        if engine == .appleMusic {
            let mp = AppleMusicService.shared.player
            mp.currentPlaybackTime = t
            currentTime = t
            // 系统播放器偶尔落后一拍，0.25 秒后没落到位就再补一次；
            // 这段时间内轮询回来的旧时间不要盖掉我们刚设的位置，否则进度条会往回跳。
            seekGuardUntil = Date().addingTimeInterval(0.9)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
                guard let self = self, self.engine == .appleMusic else { return }
                if abs(mp.currentPlaybackTime - t) > 0.8 {
                    mp.currentPlaybackTime = t
                    self.seekGuardUntil = Date().addingTimeInterval(0.6)
                }
            }
        } else {
            player?.seek(to: CMTime(seconds: t, preferredTimescale: 600))
            currentTime = t
        }
        updateNowPlaying()
    }

    func cycleRepeatMode() {
        repeatMode = repeatMode.next
    }

    // MARK: - 内部装载

    private func load(index i: Int, autoplay: Bool) {
        guard queue.indices.contains(i) else { return }
        let item = queue[i]
        index = i
        currentTime = 0

        switch item.source {
        case .local, .preview:
            loadAV(item: item, autoplay: autoplay)
        case .appleMusic:
            if !loadAppleMusic(item: item, autoplay: autoplay) {
                if item.fileURL != nil {
                    errorMessage = "「\(item.title)」不在你的 Apple Music 资料库里，先放 30 秒试听。在 Apple Music 里点「+」加入资料库之后就能听完整版。"
                    loadAV(item: item, autoplay: autoplay)
                } else {
                    errorMessage = "「\(item.title)」既不在资料库、也没有试听片段，放不了。"
                    tearDownAV()
                    stopTicker()
                    engine = .none
                    isPlaying = false
                    duration = item.fullDuration
                }
            }
        }
    }

    /// 完整版：从当前队列里挑出所有能在资料库匹配到的歌，组成系统播放器队列。
    ///
    /// 关键改动：跟系统播放器打交道（stop / setQueue / nowPlayingItem / play）全是
    /// 跨进程调用，setQueue 一次可能几百毫秒。以前整套放在主线程同步跑，
    /// 点一下播放就卡一大下。现在**先在本机把状态全部就位**（界面立刻有反应），
    /// 系统队列交给后台串行队列去做，而且队列没变就不再重建。
    private func loadAppleMusic(item: PlayItem, autoplay: Bool) -> Bool {
        let svc = AppleMusicService.shared
        guard svc.isGranted else { return false }

        var pool: [(local: Int, media: MPMediaItem)] = []
        for (idx, it) in queue.enumerated() where it.source == .appleMusic {
            // 有 persistentID 就直接取那一首，保证和界面上点的是同一首歌
            let m: MPMediaItem?
            if let mid = it.mediaID {
                m = svc.item(for: mid)
            } else {
                m = svc.match(title: it.title, artist: it.artist)
            }
            if let m = m {
                pool.append((idx, m))
            }
        }
        guard let pos = pool.firstIndex(where: { $0.local == index }) else { return false }

        tearDownAV()
        stopTicker()

        let media = pool.map { $0.media }
        let target = media[pos]
        let signature = media.map { $0.persistentID }
        let rebuild = (signature != mpQueueSignature)
        let mode = mpRepeatMode

        // ── 先把界面状态就位，不等系统播放器 ──
        engine = .appleMusic
        indexMap = pool.map { $0.local }
        // MPMediaItem.playbackDuration 是非可选的 TimeInterval
        let fullLength = target.playbackDuration
        duration = fullLength > 0 ? fullLength : item.fullDuration
        currentTime = 0
        isPlaying = autoplay
        startTicker()

        // 封面预热也放后台（ArtworkStore 内部就是异步的），先给当前这首
        let lo = max(0, pos - 1), hi = min(media.count - 1, pos + 2)
        ArtworkStore.shared.prefetch(Array(media[lo...hi]))

        // ── 系统播放器交给后台，串行执行保证顺序 ──
        let token = bumpToken()
        mpQueue.async { [weak self] in
            guard let self = self else { return }
            // 用户连着点了几首时，只让最后一次生效，中间的丢掉
            if self.currentLoadToken != token { return }
            let mp = svc.player
            if rebuild {
                mp.stop()
                mp.setQueue(with: MPMediaItemCollection(items: media))
                mp.repeatMode = mode
            }
            if mp.nowPlayingItem?.persistentID != target.persistentID {
                mp.nowPlayingItem = target
            }
            if autoplay { mp.play() } else { mp.pause() }
            DispatchQueue.main.async {
                self.mpQueueSignature = signature
            }
        }
        return true
    }

    // MARK: - AVPlayer（本地 / 试听）

    private func loadAV(item: PlayItem, autoplay: Bool) {
        // 从完整版切到试听时，先把系统播放器停掉，否则两个声音会叠在一起
        if engine == .appleMusic {
            AppleMusicService.shared.player.stop()
        }
        stopTicker()
        tearDownAV()
        engine = .av
        indexMap = nil

        guard let url = item.fileURL else {
            engine = .none
            isPlaying = false
            duration = 0
            return
        }
        duration = item.isPreview ? 30 : 0

        let assetItem = AVPlayerItem(url: url)
        let p = AVPlayer(playerItem: assetItem)
        p.automaticallyWaitsToMinimizeStalling = true
        player = p

        timeObserver = p.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.1, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            guard let self = self else { return }
            self.currentTime = time.seconds.isFinite ? time.seconds : 0
            if let d = self.player?.currentItem?.duration.seconds, d.isFinite, d > 0 {
                self.duration = d
            }
            self.updateNowPlaying()
        }

        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: assetItem,
            queue: .main
        ) { [weak self] _ in
            guard let self = self else { return }
            if self.repeatMode == .one {
                self.seek(to: 0)
                self.player?.play()
                self.isPlaying = true
            } else {
                self.next()
            }
        }

        if autoplay {
            p.play()
            isPlaying = true
        }
        updateNowPlaying()
    }

    private func tearDownAV() {
        if let obs = timeObserver, let p = player {
            p.removeTimeObserver(obs)
        }
        timeObserver = nil
        if let obs = endObserver {
            NotificationCenter.default.removeObserver(obs)
        }
        endObserver = nil
        player?.pause()
        player = nil
    }

    // MARK: - 外部引擎轮询
    //
    // MPMusicPlayerController 的每个进度/状态属性都是一次跨进程调用。
    // 之前 0.1 秒读四个属性，等于每秒 40 次 XPC 全压在主线程上 ——
    // 这是「点播放卡一下」「滚动发涩」的另一半原因。
    //
    // 现在：0.1 秒只在本地把时间往前推（不外呼），0.5 秒才跟系统对一次账，
    // 偏差小于 0.35 秒就不纠（保住平滑），刚 seek 完的 0.9 秒内完全不信系统时间。

    private var tickCount = 0

    private func startTicker() {
        stopTicker()
        tickCount = 0
        let t = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            self?.tickExternal()
        }
        RunLoop.main.add(t, forMode: .common)
        ticker = t
    }

    private func stopTicker() {
        ticker?.invalidate()
        ticker = nil
    }

    private func tickExternal() {
        guard engine == .appleMusic else { return }

        tickCount += 1

        // ── 每 0.1 秒：本地推进 ──
        if isPlaying, Date() >= seekGuardUntil {
            let next = currentTime + 0.1
            if duration > 0 {
                if next < duration { currentTime = next }
            } else {
                currentTime = next
            }
        }

        // ── 每 0.5 秒：跟系统对一次账 ──
        guard tickCount % 5 == 0 else { return }
        let mp = AppleMusicService.shared.player

        let playing = (mp.playbackState == .playing)
        if playing != isPlaying { isPlaying = playing }

        let cur = mp.currentPlaybackTime
        if cur.isFinite, cur >= 0, Date() >= seekGuardUntil {
            if !isPlaying || abs(cur - currentTime) > 0.35 { currentTime = cur }
        }

        syncTrackIfNeeded(mp)
    }

    /// 系统自己切歌（放完自动下一首、或在系统里换了歌）时同步下标和时长。
    /// 封面由 TrackArt 跟着 mediaID 自己走，这里不用管。
    private func syncTrackIfNeeded(_ mp: MPMusicPlayerController) {
        let p = mp.indexOfNowPlayingItem
        guard let map = indexMap, map.indices.contains(p) else { return }
        let mapped = map[p]
        guard mapped != index else { return }
        index = mapped
        currentTime = 0
        if let it = mp.nowPlayingItem {
            ArtworkStore.shared.prefetch([it])
            let d = it.playbackDuration
            if d > 0 { duration = d }
        }
    }

    // MARK: - 本地音乐

    var localTracks: [Track] { store.playlist }

    /// 把本地歌单转成可播放队列，顺带过滤掉文件已经不在的。
    func localItems() -> [PlayItem] {
        store.playlist.compactMap { t in
            guard let url = t.url, FileManager.default.fileExists(atPath: url.path) else { return nil }
            return PlayItem(id: t.id.uuidString,
                            title: t.title,
                            artist: "",
                            artworkURL: nil,
                            fileURL: url,
                            externalURL: nil,
                            fullDuration: 0,
                            source: .local)
        }
    }

    func playLocal(at i: Int) {
        let items = localItems()
        guard items.indices.contains(i) else { return }
        play(items: items, startingAt: i)
    }

    var musicDirectory: URL? {
        guard let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return nil }
        let music = dir.appendingPathComponent("Music")
        if !FileManager.default.fileExists(atPath: music.path) {
            try? FileManager.default.createDirectory(at: music, withIntermediateDirectories: true)
        }
        return music
    }

    /// 把用户选的文件拷进沙盒，权限永久有效，重开 App 不用重新选。
    @discardableResult
    func importFiles(_ urls: [URL]) -> Int {
        guard let dir = musicDirectory else { return 0 }
        var added = 0
        for url in urls {
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }

            let original = url.lastPathComponent
            var dest = dir.appendingPathComponent(original)
            var counter = 1
            while FileManager.default.fileExists(atPath: dest.path) {
                let base = url.deletingPathExtension().lastPathComponent
                let ext = url.pathExtension
                dest = dir.appendingPathComponent("\(base)-\(counter).\(ext)")
                counter += 1
            }
            do {
                try FileManager.default.copyItem(at: url, to: dest)
                let title = url.deletingPathExtension().lastPathComponent
                var list = store.playlist
                list.append(Track(title: title, filename: dest.lastPathComponent))
                store.playlist = list
                added += 1
            } catch {
                errorMessage = "导入失败：\(original)"
            }
        }
        return added
    }

    func removeTracks(at offsets: IndexSet) {
        var list = store.playlist
        let removing = offsets.compactMap { list.indices.contains($0) ? list[$0] : nil }
        for t in removing {
            if let url = t.url { try? FileManager.default.removeItem(at: url) }
        }
        list.remove(atOffsets: offsets)
        store.playlist = list
        // 队列变了就重排，正在播的本地曲目位置也对得上
        if current?.source == .local {
            let items = localItems()
            if items.isEmpty {
                stop()
            } else {
                queue = items
                index = min(index, items.count - 1)
            }
        }
    }

    static func formatTime(_ s: Double) -> String {
        guard s.isFinite, s >= 0 else { return "0:00" }
        let t = Int(s)
        return String(format: "%d:%02d", t / 60, t % 60)
    }
}
