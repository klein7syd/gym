import Foundation
import AVFoundation
import MediaPlayer
import Combine
import UIKit

// MARK: - 可播放条目

/// 本地文件和 Apple Music 试听都走同一个 AVPlayer，
/// 所以「搜到 → 点开 → 播放页」是完整的，不会中途把用户甩出 App。
struct PlayItem: Identifiable, Equatable {
    enum Source: String {
        case local
        case preview
    }

    let id: String
    let title: String
    let artist: String
    let artworkURL: URL?
    let fileURL: URL
    let source: Source
    let externalURL: URL?      // 去 Apple Music / 网易云打开这首歌
    let fullDuration: Double   // 完整曲目时长（试听只有 30 秒）

    var isPreview: Bool { source == .preview }

    var subtitle: String {
        isPreview ? "Apple Music 试听" : "本地音乐"
    }
}

// MARK: - 播放中枢

/// 全局唯一的播放器。本地音乐和 Apple Music 试听共用一套播放控制、
/// 一套锁屏信息、一套控制中心命令，避免两个播放器互相抢声音。
final class MusicHub: NSObject, ObservableObject {
    static let shared = MusicHub()

    @Published private(set) var queue: [PlayItem] = []
    @Published private(set) var index: Int = 0
    @Published private(set) var isPlaying = false
    @Published private(set) var currentTime: Double = 0
    @Published private(set) var duration: Double = 0
    @Published private(set) var errorMessage: String?
    @Published var repeatOne = false

    private var player: AVPlayer?
    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?
    private let store = Store.shared

    var current: PlayItem? {
        queue.indices.contains(index) ? queue[index] : nil
    }
    var hasQueue: Bool { !queue.isEmpty }

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
        player?.pause()
        isPlaying = false
        updateNowPlaying()
    }

    func stop() {
        tearDown()
        queue = []
        index = 0
        currentTime = 0
        duration = 0
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    func next(userInitiated: Bool = false) {
        guard !queue.isEmpty else { return }
        if index + 1 >= queue.count {
            if userInitiated && !repeatOne {
                load(index: 0, autoplay: true)   // 手动点下一首就绕回开头
            } else if repeatOne {
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
        if currentTime > 3 {
            seek(to: 0)
            return
        }
        load(index: (index - 1 + queue.count) % queue.count, autoplay: true)
    }

    /// 把当前播放器从一个队列位置跳到另一首（搜索结果里点歌用）。
    func jump(to i: Int) {
        guard queue.indices.contains(i) else { return }
        load(index: i, autoplay: true)
    }

    func seek(to seconds: Double) {
        let t = CMTime(seconds: max(0, seconds), preferredTimescale: 600)
        player?.seek(to: t)
        currentTime = max(0, seconds)
        updateNowPlaying()
    }

    // MARK: - 内部装载

    private func load(index i: Int, autoplay: Bool) {
        guard queue.indices.contains(i) else { return }
        let item = queue[i]
        tearDownPlayerOnly()
        index = i
        currentTime = 0
        duration = item.isPreview ? 30 : 0

        let assetItem = AVPlayerItem(url: item.fileURL)
        let p = AVPlayer(playerItem: assetItem)
        p.automaticallyWaitsToMinimizeStalling = true
        player = p

        timeObserver = p.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.4, preferredTimescale: 600),
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
            if self.repeatOne {
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

    private func tearDownPlayerOnly() {
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
        isPlaying = false
    }

    private func tearDown() {
        tearDownPlayerOnly()
        currentTime = 0
        duration = 0
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
                            source: .local,
                            externalURL: nil,
                            fullDuration: 0)
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
