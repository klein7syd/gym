import Foundation
import AVFoundation
import MediaPlayer
import Combine
import UIKit

/// 本地音频播放器。
/// 相比网页版的三个实质提升：
///  1. 歌单持久化 —— 文件拷进 App 沙盒，重开不用重选
///  2. 锁屏 / 控制中心可切歌（MPRemoteCommandCenter）
///  3. 真后台播放 —— AVAudioSession.playback + UIBackgroundModes audio
final class AudioPlayer: NSObject, ObservableObject {
    static let shared = AudioPlayer()

    @Published private(set) var isPlaying = false
    @Published private(set) var currentIndex: Int = 0
    @Published private(set) var currentTime: Double = 0
    @Published private(set) var duration: Double = 0
    @Published private(set) var errorMessage: String?

    private var player: AVPlayer?
    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?
    private let store = Store.shared

    var tracks: [Track] { store.playlist }
    var currentTrack: Track? {
        guard tracks.indices.contains(currentIndex) else { return nil }
        return tracks[currentIndex]
    }

    private override init() {
        super.init()
        currentIndex = max(0, min(store.lastTrackIndex, max(0, store.playlist.count - 1)))
        configureSession()
        configureRemoteCommands()
    }

    // MARK: - 音频会话与锁屏控制

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
            self?.play()
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
            self?.next()
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
        info[MPMediaItemPropertyTitle] = currentTrack?.title ?? "REPS"
        info[MPMediaItemPropertyArtist] = "本地音乐"
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = currentTime
        info[MPMediaItemPropertyPlaybackDuration] = duration
        info[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? 1.0 : 0.0
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    // MARK: - 播放控制

    func toggle() {
        isPlaying ? pause() : play()
    }

    func play() {
        if player == nil {
            guard !tracks.isEmpty else { return }
            load(index: currentIndex, autoplay: false)
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

    func next() {
        guard !tracks.isEmpty else { return }
        load(index: (currentIndex + 1) % tracks.count, autoplay: true)
    }

    func previous() {
        guard !tracks.isEmpty else { return }
        if currentTime > 3 {
            seek(to: 0)
            return
        }
        load(index: (currentIndex - 1 + tracks.count) % tracks.count, autoplay: true)
    }

    func select(index: Int) {
        load(index: index, autoplay: true)
    }

    func seek(to seconds: Double) {
        let t = CMTime(seconds: max(0, seconds), preferredTimescale: 600)
        player?.seek(to: t)
        currentTime = max(0, seconds)
        updateNowPlaying()
    }

    private func load(index: Int, autoplay: Bool) {
        guard tracks.indices.contains(index) else { return }
        guard let url = tracks[index].url, FileManager.default.fileExists(atPath: url.path) else {
            errorMessage = "文件不存在：\(tracks[index].title)"
            return
        }
        tearDownPlayer()
        currentIndex = index
        store.lastTrackIndex = index
        let item = AVPlayerItem(url: url)
        let p = AVPlayer(playerItem: item)
        player = p
        currentTime = 0
        duration = 0

        timeObserver = p.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.5, preferredTimescale: 600),
                                                 queue: .main) { [weak self] time in
            guard let self = self else { return }
            self.currentTime = time.seconds.isFinite ? time.seconds : 0
            if let d = self.player?.currentItem?.duration.seconds, d.isFinite {
                self.duration = d
            }
            self.updateNowPlaying()
        }

        endObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime,
                                                             object: item, queue: .main) { [weak self] _ in
            guard let self = self, !self.tracks.isEmpty else { return }
            let nextIndex = (self.currentIndex + 1) % self.tracks.count
            self.load(index: nextIndex, autoplay: true)
        }

        if autoplay {
            p.play()
            isPlaying = true
        }
        updateNowPlaying()
    }

    private func tearDownPlayer() {
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

    // MARK: - 文件导入

    var musicDirectory: URL? {
        guard let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return nil }
        let music = dir.appendingPathComponent("Music")
        if !FileManager.default.fileExists(atPath: music.path) {
            try? FileManager.default.createDirectory(at: music, withIntermediateDirectories: true)
        }
        return music
    }

    /// 把用户选的文件拷进沙盒。这样权限永久有效，重开 App 不用重新授权。
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
        let removing = offsets.map { list[$0] }
        tearDownPlayer()
        for t in removing {
            if let url = t.url { try? FileManager.default.removeItem(at: url) }
        }
        list.remove(atOffsets: offsets)
        store.playlist = list
        currentIndex = max(0, min(currentIndex, max(0, list.count - 1)))
        currentTime = 0
        duration = 0
        updateNowPlaying()
    }

    static func formatTime(_ s: Double) -> String {
        guard s.isFinite, s >= 0 else { return "0:00" }
        let t = Int(s)
        return String(format: "%d:%02d", t / 60, t % 60)
    }
}
