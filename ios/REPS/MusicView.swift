import SwiftUI
import MediaPlayer
import AVFoundation
import UniformTypeIdentifiers

// MARK: - 音乐
//
// 参照 Apple Music 的极简结构：大标题 + 常驻搜索栏 + 列表 + 底部迷你播放条，
// 点开是铺满全屏的播放页。搜索直接查 Apple Music 曲库，点歌在 App 内播放，
// 不再把用户甩到别的 App。

struct MusicView: View {
    @ObservedObject var hub = MusicHub.shared
    @ObservedObject var store = Store.shared
    @ObservedObject var am = AppleMusicService.shared

    @State private var query = ""
    /// 资料库搜索结果（全部可直接完整播放，不再有 30 秒试听）
    @State private var libraryHits: [MPMediaItem] = []
    @State private var didSearch = false
    @State private var showPicker = false
    @State private var showPlayer = false

    /// 音乐页的两个界面：Apple Music 曲库 / 本地音乐
    enum SourceTab: String, CaseIterable, Identifiable {
        case apple = "Apple Music"
        case local = "本地"
        var id: String { rawValue }
    }

    @State private var tab: SourceTab = .apple
    /// 卡片进度条拖动中的临时秒数
    @State private var cardScrub: Double?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Picker("来源", selection: $tab) {
                        ForEach(SourceTab.allCases) { t in
                            Text(t.rawValue).tag(t)
                        }
                    }
                    .pickerStyle(.segmented)

                    switch tab {
                    case .apple:
                        applePane
                    case .local:
                        localPane
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 6)
                .padding(.bottom, 130)
            }
            .background { AppBackground() }
            .scrollDismissesKeyboard(.interactively)
            .searchable(text: $query,
                        placement: .navigationBarDrawer(displayMode: .always),
                        prompt: Text(tab == .apple ? "搜索我的资料库" : "搜索本地音乐"))
            .onChange(of: query) { _ in
                runLibrarySearch()
            }
            .onChange(of: am.librarySongCount) { _ in
                runLibrarySearch()
            }
            .onChange(of: tab) { _ in
                if tab == .apple { runLibrarySearch() }
            }
            .navigationTitle("音乐")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button {
                            showPicker = true
                        } label: {
                            Label("导入本地音乐", systemImage: "square.and.arrow.down")
                        }
                        Button {
                            am.buildIndexIfNeeded(force: true)
                        } label: {
                            Label("刷新 Apple Music 资料库", systemImage: "arrow.clockwise")
                        }
                        Button {
                            NeteaseService.openApp()
                        } label: {
                            Label("打开网易云音乐", systemImage: "waveform")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.system(size: 17))
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if hub.current != nil, !showPlayer {
                    MiniPlayerBar { showPlayer = true }
                }
            }
            .sheet(isPresented: $showPicker) {
                DocumentPicker(contentTypes: [.audio], allowsMultiple: true) { urls in
                    let n = hub.importFiles(urls)
                    if n > 0, hub.localTracks.count == n {
                        hub.playLocal(at: 0)
                    }
                }
            }
            .fullScreenCover(isPresented: $showPlayer) {
                NowPlayingView()
            }
        }
    }

    // MARK: - 两个界面

    @ViewBuilder
    private var applePane: some View {
        if hub.current != nil, hub.current?.source != .local {
            nowPlayingCard
        }

        appleMusicCard

        if query.trimmingCharacters(in: .whitespaces).isEmpty {
            searchHint
        } else {
            libraryResults
        }
    }

    @ViewBuilder
    private var localPane: some View {
        if hub.current != nil, hub.current?.source == .local {
            nowPlayingCard
        }
        localSection
        if let err = hub.errorMessage {
            Text(err)
                .font(.system(size: 11))
                .foregroundColor(.red)
        }
    }

    private var searchHint: some View {
        VStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 24, weight: .light))
                .foregroundColor(.secondary)
            Text("搜我的资料库")
                .font(.system(size: 15, weight: .semibold))
            Text("只搜你 Apple Music 资料库里的歌，搜到的都能整首完整播放。想加歌就去 Apple Music 里点「+」。")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 26)
        .padding(.horizontal, 18)
    }

    // MARK: - Apple Music 完整播放授权

    private var appleMusicCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "music.note.tv")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(.accentColor)
                Text("Apple Music 资料库")
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                if am.isGranted {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 10))
                        Text("已连接")
                            .font(.system(size: 10, weight: .medium))
                    }
                    .foregroundColor(.green)
                }
            }

            Text(am.isGranted
                 ? am.statusHint
                 : "开启后直接读你 Apple Music 资料库，会员能听的歌在这里整首放，不会有 30 秒限制。")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if !am.isGranted {
                Button {
                    if am.access == .denied {
                        if let u = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(u)
                        }
                    } else {
                        am.requestAccess({ ok in
                            if ok { runLibrarySearch() }
                        })
                    }
                } label: {
                    Text(am.access == .denied ? "去设置里允许" : "授权 Apple Music")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 34)
                        .background(Capsule().fill(Color.accentColor.opacity(0.14)))
                        .foregroundColor(.accentColor)
                }
                .buttonStyle(ScaleButtonStyle())
            } else if am.isIndexing {
                HStack(spacing: 6) {
                    ProgressView().scaleEffect(0.7)
                    Text("正在读取资料库")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .glass(cornerRadius: 20, shadow: false)
    }


    // MARK: - 资料库搜索
    //
    // 只搜自己的 Apple Music 资料库：不联网、不搜曲库以外的任何东西。
    // 排序和相关性门限都在 AppleMusicService.search 里做（多词 AND、按分数、
    // 支持拼音），这里只负责调用 + 顺手预热前几行的封面。

    private func runLibrarySearch() {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard tab == .apple, am.isGranted, !q.isEmpty else {
            libraryHits = []
            didSearch = false
            return
        }
        didSearch = true
        libraryHits = am.search(q)
        // 前几行的封面先排进后台，滚动时不至于一片灰
        ArtworkStore.shared.prefetch(libraryHits, side: 160, limit: 12)
    }

    @ViewBuilder
    private var libraryResults: some View {
        if am.isIndexing {
            HStack(spacing: 8) {
                ProgressView().scaleEffect(0.7)
                Text("正在读取资料库…")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                Spacer()
            }
            .padding(.vertical, 16)
        } else if libraryHits.isEmpty {
            if didSearch {
                Text("资料库里没有「\(query)」")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
            }
        } else {
            HStack(spacing: 6) {
                Text("我的资料库 · \(libraryHits.count) 首")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.secondary)
                Text("全部可完整播放")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.green)
                Spacer()
            }

            LazyVStack(spacing: 0) {
                ForEach(Array(libraryHits.enumerated()), id: \.element.persistentID) { i, m in
                    libraryRow(m, index: i)
                    if i != libraryHits.count - 1 {
                        Divider().padding(.leading, 66)
                    }
                }
            }
            .padding(.vertical, 4)
            .glass()
        }
    }

    private func libraryRow(_ m: MPMediaItem, index: Int) -> some View {
        let playing = hub.current?.mediaID == m.persistentID
        return Button {
            playLibrary(at: index)
        } label: {
            HStack(spacing: 12) {
                TrackArt(title: m.title ?? "未知曲目",
                         mediaID: m.persistentID,
                         size: 50)
                VStack(alignment: .leading, spacing: 2) {
                    Text(m.title ?? "未知曲目")
                        .font(.system(size: 15, weight: playing ? .semibold : .regular))
                        .foregroundColor(playing ? .accentColor : .primary)
                        .lineLimit(1)
                    Text(librarySubtitle(m))
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                if playing && hub.isPlaying {
                    Image(systemName: "waveform")
                        .font(.system(size: 13))
                        .foregroundColor(.accentColor)
                } else {
                    Text(MusicHub.formatTime(m.playbackDuration))
                        .font(.system(size: 11))
                        .monospacedDigit()
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func librarySubtitle(_ m: MPMediaItem) -> String {
        let artist = m.artist ?? ""
        let album = m.albumTitle ?? ""
        if artist.isEmpty { return album }
        return album.isEmpty ? artist : "\(artist) · \(album)"
    }

    /// 点哪首放哪首：队列就是当前看到的这串结果，每首带着 persistentID，不会串歌。
    private func playLibrary(at index: Int) {
        let items: [PlayItem] = libraryHits.map { m in
            PlayItem(id: String(m.persistentID),
                     title: m.title ?? "未知曲目",
                     artist: m.artist ?? "",
                     artworkURL: nil,
                     fileURL: nil,
                     externalURL: m.assetURL,
                     fullDuration: m.playbackDuration,
                     source: .appleMusic,
                     mediaID: m.persistentID)
        }
        guard items.indices.contains(index) else { return }
        hub.play(items: items, startingAt: index)
        showPlayer = true
    }

    // MARK: - 正在播放卡片

    private var cardProgressRatio: Double {
        let d = max(1, hub.duration)
        if let s = cardScrub { return min(max(s / d, 0), 1) }
        return min(max(hub.currentTime / d, 0), 1)
    }

    private var nowPlayingCard: some View {
        VStack(spacing: 14) {
            Button {
                showPlayer = true
            } label: {
                HStack(spacing: 14) {
                    TrackArt(title: hub.current?.title ?? "REPS",
                             mediaID: hub.current?.mediaID,
                             size: 76)
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 5) {
                            Text("正在播放")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(.secondary)
                            Text(hub.isPlayingFullVersion ? "完整版" : (hub.current?.subtitle ?? ""))
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(hub.isPlayingFullVersion ? .green : .secondary)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(
                                    Capsule().fill(
                                        (hub.isPlayingFullVersion ? Color.green : Color.primary).opacity(0.12)
                                    )
                                )
                        }
                        Text(hub.current?.title ?? "")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(.primary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                        Text(hub.current?.artist.isEmpty == false
                             ? (hub.current?.artist ?? "")
                             : (hub.current?.subtitle ?? ""))
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.up")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            VStack(spacing: 5) {
                GlassBar(progress: cardProgressRatio,
                         onScrub: { v in cardScrub = v * max(1, hub.duration) },
                         onCommit: { v in
                             hub.seek(to: v * max(1, hub.duration))
                             cardScrub = nil
                         },
                         trackHeight: 6)
                HStack {
                    Text(MusicHub.formatTime(cardScrub ?? hub.currentTime))
                    Spacer()
                    Text("-" + MusicHub.formatTime(max(0, hub.duration - (cardScrub ?? hub.currentTime))))
                }
                .font(.system(size: 10, weight: .medium))
                .monospacedDigit()
                .foregroundColor(.secondary)
            }

            HStack(spacing: 44) {
                Button { hub.previous() } label: {
                    Image(systemName: "backward.fill").font(.system(size: 21))
                }
                Button { hub.toggle() } label: {
                    Image(systemName: hub.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 30))
                        .frame(width: 40, height: 40)
                }
                Button { hub.next(userInitiated: true) } label: {
                    Image(systemName: "forward.fill").font(.system(size: 21))
                }
            }
            .foregroundColor(.primary)
        }
        .padding(16)
        .glass()
    }

    // MARK: - 本地音乐

    /// 有搜索词时按标题过滤，保留原序号，删除/播放下标才不会错。
    private var filteredLocal: [(offset: Int, element: Track)] {
        let all = Array(hub.localTracks.enumerated())
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return all }
        return all.filter { $0.element.title.localizedCaseInsensitiveContains(q) }
    }

    @ViewBuilder
    private var localSection: some View {
        Button {
            showPicker = true
        } label: {
            HStack(spacing: 11) {
                Image(systemName: "square.and.arrow.down")
                    .font(.system(size: 16, weight: .semibold))
                VStack(alignment: .leading, spacing: 1) {
                    Text("导入本地音乐")
                        .font(.system(size: 14, weight: .semibold))
                    Text("mp3 / m4a / wav，存进沙盒后永久有效")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
                Spacer(minLength: 4)
                Image(systemName: "plus")
                    .font(.system(size: 13, weight: .semibold))
            }
            .foregroundColor(.accentColor)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.accentColor.opacity(0.10))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(ScaleButtonStyle())

        if hub.localTracks.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "music.note.list")
                    .font(.system(size: 24, weight: .light))
                    .foregroundColor(.secondary)
                Text("还没有本地音乐")
                    .font(.system(size: 14, weight: .medium))
                Text("从「文件」里选歌导入，整首播放、不联网也能听")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
        } else if filteredLocal.isEmpty {
            Text("本地没有匹配「\(query)」的歌")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
        } else {
            HStack {
                Text("本地音乐 · \(hub.localTracks.count) 首")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.secondary)
                Spacer()
            }

            VStack(spacing: 0) {
                ForEach(filteredLocal, id: \.element.id) { item in
                    localRow(index: item.offset, track: item.element)
                    if item.element.id != filteredLocal.last?.element.id {
                        Divider().padding(.leading, 70)
                    }
                }
            }
            .padding(.vertical, 4)
            .glass()
        }

        localTip
    }

    private func localRow(index: Int, track: Track) -> some View {
        let playing = hub.current?.source == .local && hub.current?.title == track.title
        return Button {
            hub.playLocal(at: index)
            showPlayer = true
        } label: {
            HStack(spacing: 12) {
                AlbumArt(title: track.title, size: 46)
                VStack(alignment: .leading, spacing: 2) {
                    Text(track.title)
                        .font(.system(size: 15, weight: playing ? .semibold : .regular))
                        .foregroundColor(playing ? .accentColor : .primary)
                        .lineLimit(1)
                    Text("本地音乐")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                Spacer(minLength: 4)
                if playing && hub.isPlaying {
                    Image(systemName: "waveform")
                        .font(.system(size: 13))
                        .foregroundColor(.accentColor)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(role: .destructive) {
                hub.removeTracks(at: IndexSet(integer: index))
            } label: {
                Label("移除", systemImage: "trash")
            }
        }
    }

    private var localTip: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("本地音乐会存在 App 沙盒里")
                .font(.system(size: 11, weight: .semibold))
            Text("文件放在 Documents/Music。删 App 就一起没了，重签安装时别先卸载。")
                .font(.system(size: 10))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(13)
        .glass(cornerRadius: 18, shadow: false)
    }


}

// MARK: - 底部迷你播放条

struct MiniPlayerBar: View {
    @ObservedObject var hub = MusicHub.shared
    var onTap: () -> Void

    init(onTap: @escaping () -> Void) {
        self.onTap = onTap
    }

    var body: some View {
        HStack(spacing: 11) {
            Button(action: onTap) {
                HStack(spacing: 11) {
                    artwork
                    VStack(alignment: .leading, spacing: 1) {
                        Text(hub.current?.title ?? "")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.primary)
                            .lineLimit(1)
                        Text(hub.current?.artist.isEmpty == false
                             ? (hub.current?.artist ?? "")
                             : (hub.current?.subtitle ?? ""))
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 4)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button { hub.toggle() } label: {
                Image(systemName: hub.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 18))
                    .foregroundColor(.primary)
                    .frame(width: 36, height: 36)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button { hub.next(userInitiated: true) } label: {
                Image(systemName: "forward.fill")
                    .font(.system(size: 15))
                    .foregroundColor(.primary)
                    .frame(width: 30, height: 36)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .glass(cornerRadius: 22)
        .padding(.horizontal, 14)
        .padding(.bottom, 4)
    }

    private var artwork: some View {
        TrackArt(title: hub.current?.title ?? "",
                 mediaID: hub.current?.mediaID,
                 size: 40)
    }
}

// MARK: - 全屏播放页
//
// 版式按 Apple Music 的播放页排（iOS 17/18 那一版）：
//
//            ── 抓手 ──
//   ⌄          正在播放           ⋯
//        [      封面      ]
//   歌名（20 粗，左对齐）
//   艺人（20 常规，灰，左对齐）
//   ══════ 进度条 ══════
//   0:12                  -3:20
//   ☰     ⏮     ▶     ⏭     🔁
//   🔈 ══════ 音量 ══════ 🔊
//   [ Apple Music 底部那排歌词/待播/AirPlay 换成训练状态 ]
//
// 进度条、音量条都是「白灰玻璃条」：8pt 厚，浅灰轨道 + 白色（深色模式）
// 或深灰（浅色模式）已播放段，边缘 0.5pt 高光描边，没有圆点把手。

struct NowPlayingView: View {
    @ObservedObject var hub = MusicHub.shared
    @ObservedObject var store = Store.shared
    @ObservedObject var rest = RestTimer.shared
    @Environment(\.dismiss) private var dismiss
    @State private var dragOffset: CGFloat = 0
    @State private var showQueue = false
    /// 拖动进度条时的临时秒数（nil = 没在拖，跟随播放器）
    @State private var scrub: Double?

    var body: some View {
        GeometryReader { geo in
            // 除封面以外的固定高度合计
            let fixed: CGFloat = 372
            let side = max(140, min(geo.size.width - 32, geo.size.height - fixed, 352))

            VStack(spacing: 0) {
                grabber

                header

                Spacer(minLength: 8)

                cover(side: side)

                Spacer().frame(height: 22)

                titleBlock

                Spacer().frame(height: 20)

                progress

                Spacer().frame(height: 10)

                controls

                Spacer().frame(height: 8)

                volume

                Spacer(minLength: 10)

                trainingBar
                    .padding(.horizontal, 16)
                    .padding(.bottom, 4)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .background { playerBackground }
        .offset(y: max(0, dragOffset))
        .sheet(isPresented: $showQueue) {
            QueueSheet()
        }
    }

    /// 纯色底，不再有渐变 / 柔光色斑（和全局一致）。
    private var playerBackground: some View {
        Color(UIColor.systemBackground).ignoresSafeArea()
    }

    // MARK: 抓手

    private var grabber: some View {
        Capsule()
            .fill(Color.secondary.opacity(0.30))
            .frame(width: 36, height: 5)
            .padding(.top, 6)
            .padding(.bottom, 2)
    }

    // MARK: 顶部：左收起 · 中「正在播放」· 右更多

    private var header: some View {
        HStack(spacing: 0) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.primary)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Spacer(minLength: 0)

            Text("正在播放")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.secondary)
                .textCase(.uppercase)
                .tracking(0.6)

            Spacer(minLength: 0)

            Menu {
                Button {
                    hub.cycleRepeatMode()
                } label: {
                    Label(hub.repeatMode.label, systemImage: hub.repeatMode.symbol)
                }
                Button {
                    showQueue = true
                } label: {
                    Label("播放列表", systemImage: "list.bullet")
                }
                if let u = hub.current?.externalURL {
                    Button {
                        UIApplication.shared.open(u)
                    } label: {
                        Label("在 Apple Music 打开", systemImage: "arrow.up.forward.app")
                    }
                }
                if let c = hub.current {
                    Button {
                        NeteaseService.search("\(c.title) \(c.artist)")
                    } label: {
                        Label("去网易云搜这首歌", systemImage: "waveform")
                    }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 19, weight: .regular))
                    .foregroundColor(.primary)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
        }
        .padding(.horizontal, 8)
        .contentShape(Rectangle())
        .gesture(
            DragGesture()
                .onChanged { v in
                    if v.translation.height > 0 { dragOffset = v.translation.height }
                }
                .onEnded { v in
                    if v.translation.height > 110 {
                        dismiss()
                    } else {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                            dragOffset = 0
                        }
                    }
                }
        )
    }

    // MARK: 封面

    private func cover(side: CGFloat) -> some View {
        TrackArt(title: hub.current?.title ?? "REPS",
                 mediaID: hub.current?.mediaID,
                 size: side,
                 corner: 8)
            .shadow(color: .black.opacity(0.28), radius: 22, y: 14)
            .scaleEffect(hub.isPlaying ? 1 : 0.95)
            .animation(.spring(response: 0.42, dampingFraction: 0.82), value: hub.isPlaying)
    }

    // MARK: 歌名 / 艺人（Apple Music 都是左对齐，贴封面左边）

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(hub.current?.title ?? "没有正在播放的音乐")
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)

            Text(subtitleText)
                .font(.system(size: 20, weight: .regular))
                .foregroundColor(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
    }

    private var subtitleText: String {
        guard let c = hub.current else { return "" }
        return c.artist.isEmpty ? (c.subtitle) : c.artist
    }

    // MARK: 进度

    private var progress: some View {
        VStack(spacing: 5) {
            GlassBar(progress: progressRatio,
                     onScrub: { v in scrub = v * max(1, hub.duration) },
                     onCommit: { v in
                         hub.seek(to: v * max(1, hub.duration))
                         scrub = nil
                     },
                     trackHeight: 8)

            HStack(spacing: 0) {
                Text(MusicHub.formatTime(elapsed))
                Spacer(minLength: 8)
                Text("-" + MusicHub.formatTime(max(0, hub.duration - elapsed)))
            }
            .font(.system(size: 11, weight: .medium))
            .monospacedDigit()
            .foregroundColor(.secondary)
        }
        .padding(.horizontal, 20)
    }

    private var progressRatio: Double {
        let d = max(1, hub.duration)
        if let s = scrub { return min(max(s / d, 0), 1) }
        return min(max(hub.currentTime / d, 0), 1)
    }

    private var elapsed: Double {
        scrub ?? hub.currentTime
    }

    // MARK: 播放控制
    //
    // Apple Music 是「随机 / 上一首 / 播放 / 下一首 / 循环」，
    // 这里第一个换成「播放列表」（用户要的），位置和尺寸保持一致：纯图标、无圆底。

    private var controls: some View {
        HStack(spacing: 0) {
            Button {
                showQueue = true
            } label: {
                Image(systemName: "list.bullet")
                    .font(.system(size: 19, weight: .regular))
                    .foregroundColor(.primary)
                    .frame(width: 46, height: 46)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Spacer(minLength: 0)

            Button {
                hub.previous()
            } label: {
                Image(systemName: "backward.fill")
                    .font(.system(size: 27))
                    .foregroundColor(.primary)
                    .frame(width: 54, height: 54)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button {
                hub.toggle()
            } label: {
                Image(systemName: hub.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 42))
                    .foregroundColor(.primary)
                    .frame(width: 76, height: 54)
                    .contentShape(Rectangle())
            }
            .buttonStyle(ScaleButtonStyle(scale: 0.9))

            Button {
                hub.next(userInitiated: true)
            } label: {
                Image(systemName: "forward.fill")
                    .font(.system(size: 27))
                    .foregroundColor(.primary)
                    .frame(width: 54, height: 54)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Spacer(minLength: 0)

            Button {
                hub.cycleRepeatMode()
            } label: {
                Image(systemName: hub.repeatMode.symbol)
                    .font(.system(size: 19, weight: .regular))
                    .foregroundColor(hub.repeatMode.isOn ? .accentColor : .primary)
                    .frame(width: 46, height: 46)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 22)
    }

    // MARK: 系统音量

    private var volume: some View {
        HStack(spacing: 9) {
            Image(systemName: "speaker.fill")
                .font(.system(size: 10))
                .foregroundColor(.secondary)
            VolumeBar(trackHeight: 8)
            Image(systemName: "speaker.wave.3.fill")
                .font(.system(size: 10))
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 22)
    }

    // MARK: 底部训练状态（顶掉 Apple Music 的歌词 / 待播 / AirPlay）

    private var trainingBar: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Image(systemName: "figure.strengthtraining.traditional")
                        .font(.system(size: 9, weight: .semibold))
                    if store.current != nil {
                        Text("正在训练")
                            .font(.system(size: 10, weight: .semibold))
                        Text("· 第 \(setCount) 组")
                            .font(.system(size: 10))
                    } else {
                        Text("还没开始训练")
                            .font(.system(size: 10, weight: .semibold))
                    }
                }
                .foregroundColor(.secondary)

                Text(store.current != nil ? store.currentExercise.name : "去训练页记第一组")
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)

                Text(trainingDetail)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            if rest.isRunning {
                MiniRestRing(progress: rest.progress, text: rest.remainingText, size: 48)
                VStack(spacing: 5) {
                    Button {
                        rest.add(seconds: 30)
                    } label: {
                        Text("+30")
                            .font(.system(size: 10, weight: .semibold))
                            .frame(width: 40, height: 20)
                            .background(Capsule().fill(Color.primary.opacity(0.07)))
                            .foregroundColor(.primary)
                    }
                    .buttonStyle(ScaleButtonStyle())

                    Button {
                        rest.skip()
                    } label: {
                        Text("跳过")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.secondary)
                            .frame(width: 40, height: 20)
                    }
                    .buttonStyle(ScaleButtonStyle())
                }
            } else {
                Button {
                    rest.start(seconds: store.restSeconds)
                } label: {
                    VStack(spacing: 1) {
                        Image(systemName: "timer")
                            .font(.system(size: 14, weight: .medium))
                        Text("\(store.restSeconds)s")
                            .font(.system(size: 9, weight: .medium))
                    }
                    .foregroundColor(.accentColor)
                    .frame(width: 58, height: 44)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color.accentColor.opacity(0.13))
                    )
                }
                .buttonStyle(ScaleButtonStyle())
                .disabled(store.current == nil)
                .opacity(store.current == nil ? 0.35 : 1)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .glass(cornerRadius: 22)
    }

    private var setCount: Int {
        store.currentExercise.sets.count
    }

    private var trainingDetail: String {
        guard store.current != nil else {
            return "组数、重量、休息计时都同步显示在这里"
        }
        if let s = store.currentExercise.sets.last {
            return "上一组 \(fmtWeight(s.w)) kg × \(s.r) · 共 \(setCount) 组"
        }
        return "这个动作还没记录，调好重量再点「完成一组」"
    }

    private func fmtWeight(_ w: Double) -> String {
        w.truncatingRemainder(dividingBy: 1) == 0
            ? String(format: "%.0f", w)
            : String(format: "%.1f", w)
    }
}

// MARK: - 播放列表

struct QueueSheet: View {
    @ObservedObject var hub = MusicHub.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(Array(hub.queue.enumerated()), id: \.element.id) { i, item in
                        Button {
                            hub.jump(to: i)
                        } label: {
                            HStack(spacing: 10) {
                                TrackArt(title: item.title,
                                         mediaID: item.mediaID,
                                         size: 40)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.title)
                                        .font(.system(size: 14, weight: i == hub.index ? .semibold : .regular))
                                        .foregroundColor(i == hub.index ? .accentColor : .primary)
                                        .lineLimit(1)
                                    Text(item.subtitle)
                                        .font(.system(size: 11))
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                }
                                Spacer(minLength: 4)
                                if i == hub.index {
                                    Image(systemName: hub.isPlaying ? "waveform" : "pause.fill")
                                        .font(.system(size: 12))
                                        .foregroundColor(.accentColor)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    Text("\(hub.queue.count) 首 · \(hub.repeatMode.label)")
                }
            }
            .navigationTitle("播放列表")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }
}

// MARK: - 玻璃进度条 / 音量条
//
// 照 Apple Music 的观感做：8pt 厚的胶囊条，浅灰半透明轨道 +
// 已播放段是白色（深色模式）/ 近黑（浅色模式），0.5pt 高光描边 + 轻微外发光，
// 看起来像一根磨过的玻璃条，而不是系统 Slider 那种塑料件。
// 没有圆点把手（按住任意位置拖，命中区 26pt），拖动时按下位置跟手。

struct GlassBar: View {
    var progress: Double
    var onScrub: (Double) -> Void = { _ in }
    var onCommit: (Double) -> Void = { _ in }
    var trackHeight: CGFloat = 8
    var enabled: Bool = true

    @Environment(\.colorScheme) private var scheme
    @State private var dragging = false
    @State private var local: Double = 0

    var body: some View {
        GeometryReader { geo in
            let w = max(1, geo.size.width)
            let p = CGFloat(min(max(dragging ? local : progress, 0), 1))

            ZStack(alignment: .leading) {
                // 轨道：玻璃槽
                Capsule(style: .continuous)
                    .fill(Color.primary.opacity(scheme == .dark ? 0.16 : 0.12))
                    .overlay(
                        Capsule(style: .continuous)
                            .strokeBorder(Color.white.opacity(scheme == .dark ? 0.10 : 0.45),
                                          lineWidth: 0.5)
                    )
                    .frame(height: trackHeight)

                // 已播放段：白 / 深灰玻璃
                Capsule(style: .continuous)
                    .fill(fillColor)
                    .overlay(
                        Capsule(style: .continuous)
                            .strokeBorder(Color.white.opacity(scheme == .dark ? 0.55 : 0.30),
                                          lineWidth: 0.5)
                    )
                    .frame(height: trackHeight)
                    .mask(alignment: .leading) {
                        Rectangle().frame(width: w * p)
                    }
                    .shadow(color: fillColor.opacity(0.35), radius: 4, y: 0)
            }
            .frame(width: w, height: max(trackHeight, 26))
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { v in
                        guard enabled else { return }
                        if !dragging {
                            dragging = true
                            UISelectionFeedbackGenerator().selectionChanged()
                        }
                        let t = min(max(v.location.x / w, 0), 1)
                        local = t
                        onScrub(t)
                    }
                    .onEnded { v in
                        guard enabled else { return }
                        let t = min(max(v.location.x / w, 0), 1)
                        local = t
                        dragging = false
                        onCommit(t)
                    }
            )
        }
        .frame(height: max(trackHeight, 26))
        .opacity(enabled ? 1 : 0.4)
    }

    private var fillColor: Color {
        scheme == .dark
            ? Color.white.opacity(0.92)
            : Color(white: 0.12).opacity(0.86)
    }
}

// MARK: - 系统音量条

struct VolumeBar: View {
    var trackHeight: CGFloat = 8

    @State private var level: Double = SystemVolume.shared.level
    @State private var dragging = false
    @State private var local: Double = 0

    private let ticker = Timer.publish(every: 0.25, on: .main, in: .common).autoconnect()

    var body: some View {
        GlassBar(progress: dragging ? local : level,
                 onScrub: { v in
                     dragging = true
                     local = v
                     SystemVolume.shared.set(v)
                 },
                 onCommit: { v in
                     local = v
                     level = v
                     dragging = false
                     SystemVolume.shared.set(v)
                 },
                 trackHeight: trackHeight)
            .onReceive(ticker) { _ in
                guard !dragging else { return }
                let v = SystemVolume.shared.level
                if abs(v - level) > 0.005 { level = v }
            }
            .onAppear { level = SystemVolume.shared.level }
    }
}

/// 系统音量读写。
///
/// iOS 不开放改音量的 API，只能借 MPVolumeView 内部那个 UISlider：
/// 把它挂到一个看不见的容器里，读它的 value / 给它 setValue，
/// 就能做到和侧边键完全同步的真实音量控制。
final class SystemVolume {
    static let shared = SystemVolume()

    private let host = MPVolumeView(frame: CGRect(x: -4, y: -4, width: 1, height: 1))

    private var slider: UISlider? {
        host.subviews.compactMap { $0 as? UISlider }.first
    }

    private init() {
        host.showsRouteButton = false
        host.alpha = 0.01
        host.isUserInteractionEnabled = false
    }

    /// MPVolumeView 的 UISlider 是懒创建的，先进窗口再取一次。
    private func install() {
        if host.superview == nil {
            guard let scene = UIApplication.shared.connectedScenes
                    .compactMap({ $0 as? UIWindowScene })
                    .first(where: { $0.activationState == .foregroundActive })
                    ?? UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first,
                  let window = scene.windows.first(where: { $0.isKeyWindow }) ?? scene.windows.first
            else { return }
            window.addSubview(host)
            host.setNeedsLayout()
            host.layoutIfNeeded()
        }
        if slider == nil {
            host.setNeedsLayout()
            host.layoutIfNeeded()
        }
    }

    var level: Double {
        install()
        if let s = slider { return Double(s.value) }
        return Double(AVAudioSession.sharedInstance().outputVolume)
    }

    func set(_ v: Double) {
        install()
        let target = Float(min(max(v, 0), 1))
        if let s = slider {
            s.setValue(target, animated: false)
        }
    }
}


// MARK: - 抽象封面

/// 本地文件没有内嵌封面时，用歌名挑一个纯色占位（不用渐变）。
struct AlbumArt: View {
    let title: String
    var size: CGFloat

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.08, style: .continuous)
                .fill(Self.baseColor(for: title))
            Image(systemName: "music.note")
                .font(.system(size: size * 0.2, weight: .light))
                .foregroundColor(.white.opacity(0.92))
        }
        .frame(width: size, height: size)
    }

    static func baseColor(for title: String) -> Color {
        let colors: [Color] = [
            Color(red: 0.32, green: 0.42, blue: 0.92),
            Color(red: 0.92, green: 0.44, blue: 0.38),
            Color(red: 0.16, green: 0.66, blue: 0.56),
            Color(red: 0.80, green: 0.36, blue: 0.58),
            Color(red: 0.24, green: 0.60, blue: 0.82)
        ]
        let seed = title.unicodeScalars.reduce(0) { $0 &+ Int($1.value) }
        return colors[abs(seed) % colors.count]
    }
}
