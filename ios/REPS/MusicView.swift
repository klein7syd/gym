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
    @State private var results: [ITunesTrack] = []
    @State private var isSearching = false
    @State private var message: String?
    @State private var showPicker = false
    @State private var showPlayer = false
    @State private var searchTask: Task<Void, Never>?
    /// 搜到的曲目里，能在 Apple Music 资料库匹配到（= 可听完整版）的 id
    @State private var fullIDs: Set<String> = []

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
                        prompt: Text(tab == .apple ? "搜索 Apple Music" : "搜索本地音乐"))
            .onSubmit(of: .search) {
                if tab == .apple { runSearch() }
            }
            .onChange(of: query) { newValue in
                if newValue.trimmingCharacters(in: .whitespaces).isEmpty {
                    results = []
                    message = nil
                    isSearching = false
                    fullIDs = []
                }
            }
            .onChange(of: am.librarySongCount) { _ in
                refreshFullFlags()
            }
            .onChange(of: tab) { _ in
                message = nil
                if tab == .local {
                    results = []
                    fullIDs = []
                }
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

        if query.trimmingCharacters(in: .whitespaces).isEmpty {
            appleMusicCard
            searchHint
        } else {
            searchSection
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
            Text("搜 Apple Music 曲库")
                .font(.system(size: 15, weight: .semibold))
            Text("输入歌名、歌手或专辑。资料库里的歌整首播放，其余给 30 秒官方试听。")
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
                Text("Apple Music 完整播放")
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
                 : "开启后，你 Apple Music 资料库里的歌可以在这儿整首播放，不再是 30 秒试听。")
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
                            if ok { refreshFullFlags() }
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


    // MARK: - 搜索

    private func runSearch() {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        searchTask?.cancel()
        isSearching = true
        message = nil
        results = []
        searchTask = Task {
            do {
                let list = try await ITunesAPI.search(q)
                if Task.isCancelled { return }
                await MainActor.run {
                    results = list
                    isSearching = false
                    refreshFullFlags()
                    if list.isEmpty { message = "没搜到「\(q)」，换个关键词试试。" }
                }
            } catch {
                if Task.isCancelled { return }
                await MainActor.run {
                    isSearching = false
                    message = "网络不通，搜不到曲库。检查一下网络再试。"
                }
            }
        }
    }

    private var searchSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            if isSearching {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("正在搜 Apple Music")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 30)
                .frame(maxWidth: .infinity)
            }

            if let msg = message {
                Text(msg)
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    .padding(.vertical, 20)
                    .frame(maxWidth: .infinity, alignment: .center)
            }

            if !results.isEmpty {
                HStack(spacing: 6) {
                    Text("Apple Music 曲库 · \(results.count) 首")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.secondary)
                    if !fullIDs.isEmpty {
                        Text("其中 \(fullIDs.count) 首可听完整版")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.green)
                    }
                    Spacer()
                }

                VStack(spacing: 0) {
                    ForEach(Array(results.enumerated()), id: \.element.id) { i, t in
                        trackRow(t, index: i)
                        if i != results.count - 1 {
                            Divider().padding(.leading, 66)
                        }
                    }
                }
                .padding(.vertical, 4)
                .glass()
            }
        }
    }

    private func trackRow(_ t: ITunesTrack, index: Int) -> some View {
        Button {
            playTrack(t)
        } label: {
            HStack(spacing: 12) {
                artwork(url: t.artworkSmall, size: 50, seed: t.title)
                VStack(alignment: .leading, spacing: 3) {
                    Text(t.title)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    HStack(spacing: 6) {
                        Text(t.artist)
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                        sourceBadge(t)
                    }
                }
                Spacer(minLength: 4)
                Text(MusicHub.formatTime(t.duration))
                    .font(.system(size: 11, design: .rounded))
                    .monospacedDigit()
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            if let u = t.storeURL {
                Button {
                    UIApplication.shared.open(u)
                } label: {
                    Label(fullIDs.contains(t.id) ? "在 Apple Music 打开" : "去 Apple Music 加入资料库",
                          systemImage: "arrow.up.forward.app")
                }
            }
            Button {
                NeteaseService.search("\(t.title) \(t.artist)")
            } label: {
                Label("去网易云搜这首歌", systemImage: "waveform")
            }
        }
    }

    /// 三种状态一眼看清：能放完整版 / 只能试听 / 啥都放不了。
    @ViewBuilder
    private func sourceBadge(_ t: ITunesTrack) -> some View {
        if fullIDs.contains(t.id) {
            Text("完整")
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(.green)
                .padding(.horizontal, 5)
                .padding(.vertical, 1.5)
                .background(Capsule().fill(Color.green.opacity(0.15)))
        } else if t.hasPreview {
            Text("试听")
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(.secondary)
                .padding(.horizontal, 5)
                .padding(.vertical, 1.5)
                .background(Capsule().fill(Color.primary.opacity(0.07)))
        } else {
            Text("不可播")
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(.orange)
                .padding(.horizontal, 5)
                .padding(.vertical, 1.5)
                .background(Capsule().fill(Color.orange.opacity(0.14)))
        }
    }

    private func playTrack(_ t: ITunesTrack) {
        // 优先组「完整版」队列：这一批里所有能在资料库匹配上的歌一起排队，
        // 这样上一首/下一首切过去的也是完整版，不会突然掉回试听。
        let fullItems = results.compactMap { makeItem($0, preferFull: true) }
            .filter { $0.source == .appleMusic }
        if let pos = fullItems.firstIndex(where: { $0.id == t.id }) {
            hub.play(items: fullItems, startingAt: pos)
            showPlayer = true
            return
        }

        let playable = results.compactMap { makeItem($0, preferFull: false) }
        if let pos = playable.firstIndex(where: { $0.id == t.id }) {
            hub.play(items: playable, startingAt: pos)
            showPlayer = true
            return
        }

        message = "「\(t.title)」没有试听片段。在 Apple Music 里把它加入资料库，再回来就能听完整版。"
    }

    private func makeItem(_ r: ITunesTrack, preferFull: Bool) -> PlayItem? {
        let full = preferFull && fullIDs.contains(r.id)
        guard full || r.preview != nil else { return nil }
        return PlayItem(id: r.id,
                        title: r.title,
                        artist: r.artist,
                        artworkURL: r.artworkLarge,
                        fileURL: r.preview,
                        externalURL: r.storeURL,
                        fullDuration: r.duration,
                        source: full ? .appleMusic : .preview)
    }

    /// 搜完（或资料库索引就绪）后，把「能完整播」的结果算一次，避免每行都跑正则匹配。
    private func refreshFullFlags() {
        guard am.isGranted else {
            fullIDs = []
            return
        }
        var s = Set<String>()
        for r in results where am.isPlayableInFull(title: r.title, artist: r.artist) {
            s.insert(r.id)
        }
        fullIDs = s
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
                    artwork(url: hub.current?.artworkURL, size: 76, seed: hub.current?.title ?? "REPS")
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
                SlimBar(progress: cardProgressRatio,
                        onScrub: { v in cardScrub = v * max(1, hub.duration) },
                        onCommit: { v in
                            hub.seek(to: v * max(1, hub.duration))
                            cardScrub = nil
                        },
                        trackHeight: 4)
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


    // MARK: - 封面

    private func artwork(url: URL?, size: CGFloat, seed: String) -> some View {
        Group {
            if let url = url {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let img):
                        img.resizable().aspectRatio(contentMode: .fill)
                    default:
                        AlbumArt(title: seed, size: size)
                    }
                }
            } else {
                AlbumArt(title: seed, size: size)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.08, style: .continuous))
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
        Group {
            if let u = hub.current?.artworkURL {
                AsyncImage(url: u) { phase in
                    if case .success(let img) = phase {
                        img.resizable().aspectRatio(contentMode: .fill)
                    } else {
                        AlbumArt(title: hub.current?.title ?? "", size: 40)
                    }
                }
            } else {
                AlbumArt(title: hub.current?.title ?? "", size: 40)
            }
        }
        .frame(width: 40, height: 40)
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
    }
}

// MARK: - 全屏播放页
//
// 照 Apple Music 的播放页抄的版式：
//   ─ 抓手 ─
//   ⌄                          ⋯
//   [          封面          ]
//   歌名（粗，左对齐）
//   艺人（灰，左对齐）
//   ──── 进度条 ────
//   0:12                    -3:20
//   ☰    ⏮    ▶    ⏭    🔁
//   🔊 ───── 音量 ───── 🔊
//   [ 训练状态 ]            ← 顶掉 Apple Music 底部的歌词/待播/AirPlay

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
            let inset: CGFloat = 20
            // 除封面以外的固定高度合计
            let fixed: CGFloat = 372
            let side = max(150, min(geo.size.width - inset * 2, geo.size.height - fixed, 336))

            VStack(spacing: 0) {
                grabber

                header

                Spacer(minLength: 4)

                cover(side: side)

                Spacer().frame(height: 22)

                titleBlock

                Spacer().frame(height: 16)

                progress

                Spacer().frame(height: 14)

                controls

                Spacer().frame(height: 14)

                volume

                Spacer(minLength: 10)

                trainingBar
                    .padding(.horizontal, 16)
            }
            .padding(.bottom, 6)
        }
        .background { AppBackground() }
        .offset(y: max(0, dragOffset))
        .sheet(isPresented: $showQueue) {
            QueueSheet()
        }
    }

    // MARK: 抓手

    private var grabber: some View {
        Capsule()
            .fill(Color.secondary.opacity(0.35))
            .frame(width: 34, height: 5)
            .padding(.top, 6)
    }

    // MARK: 顶部

    private var header: some View {
        HStack(spacing: 0) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(.primary)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

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
                Image(systemName: "ellipsis")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(.primary)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
        }
        .padding(.horizontal, 10)
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
        Group {
            if let img = hub.nowArtwork {
                Image(uiImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else if let u = hub.current?.artworkURL {
                AsyncImage(url: u) { phase in
                    if case .success(let img) = phase {
                        img.resizable().aspectRatio(contentMode: .fill)
                    } else {
                        AlbumArt(title: hub.current?.title ?? "REPS", size: side)
                    }
                }
            } else {
                AlbumArt(title: hub.current?.title ?? "REPS", size: side)
            }
        }
        .frame(width: side, height: side)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .shadow(color: .black.opacity(0.20), radius: 20, y: 12)
        .scaleEffect(hub.isPlaying ? 1 : 0.94)
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: hub.isPlaying)
    }

    // MARK: 歌名（Apple Music 是左对齐，贴着封面左边）

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(hub.current?.title ?? "没有正在播放的音乐")
                .font(.system(size: 22, weight: .bold))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(subtitleText)
                .font(.system(size: 18))
                .foregroundColor(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 22)
    }

    private var subtitleText: String {
        guard let c = hub.current else { return "" }
        let artist = c.artist.isEmpty ? c.subtitle : c.artist
        return hub.isPlayingFullVersion ? artist + " · 完整版" : artist
    }

    // MARK: 进度

    private var progress: some View {
        VStack(spacing: 6) {
            SlimBar(progress: progressRatio,
                    onScrub: { v in scrub = v * max(1, hub.duration) },
                    onCommit: { v in
                        hub.seek(to: v * max(1, hub.duration))
                        scrub = nil
                    },
                    trackHeight: 5)

            HStack(spacing: 0) {
                Text(MusicHub.formatTime(elapsed))
                Spacer(minLength: 8)
                Text("-" + MusicHub.formatTime(max(0, hub.duration - elapsed)))
            }
            .font(.system(size: 11, weight: .medium))
            .monospacedDigit()
            .foregroundColor(.secondary)
        }
        .padding(.horizontal, 22)
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
    // Apple Music 是「随机 / 上一首 / 播放 / 下一首 / 循环」五个图标，
    // 这里把「随机」换成「播放列表」，其余位置、大小照抄（无圆形底，纯图标）。

    private var controls: some View {
        HStack(spacing: 0) {
            Button {
                showQueue = true
            } label: {
                Image(systemName: "list.bullet")
                    .font(.system(size: 20, weight: .regular))
                    .foregroundColor(.primary)
                    .frame(width: 48, height: 48)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Spacer(minLength: 0)

            Button {
                hub.previous()
            } label: {
                Image(systemName: "backward.fill")
                    .font(.system(size: 26))
                    .foregroundColor(.primary)
                    .frame(width: 56, height: 56)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button {
                hub.toggle()
            } label: {
                Image(systemName: hub.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 42))
                    .foregroundColor(.primary)
                    .frame(width: 76, height: 56)
                    .contentShape(Rectangle())
            }
            .buttonStyle(ScaleButtonStyle(scale: 0.92))

            Button {
                hub.next(userInitiated: true)
            } label: {
                Image(systemName: "forward.fill")
                    .font(.system(size: 26))
                    .foregroundColor(.primary)
                    .frame(width: 56, height: 56)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Spacer(minLength: 0)

            Button {
                hub.cycleRepeatMode()
            } label: {
                Image(systemName: hub.repeatMode.symbol)
                    .font(.system(size: 20, weight: .regular))
                    .foregroundColor(hub.repeatMode.isOn ? .accentColor : .primary)
                    .frame(width: 48, height: 48)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 18)
    }

    // MARK: 系统音量

    private var volume: some View {
        HStack(spacing: 10) {
            Image(systemName: "speaker.fill")
                .font(.system(size: 9))
                .foregroundColor(.secondary)
            VolumeBar()
            Image(systemName: "speaker.wave.3.fill")
                .font(.system(size: 9))
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 26)
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
                                Group {
                                    if let u = item.artworkURL {
                                        AsyncImage(url: u) { phase in
                                            if case .success(let img) = phase {
                                                img.resizable().aspectRatio(contentMode: .fill)
                                            } else {
                                                AlbumArt(title: item.title, size: 40)
                                            }
                                        }
                                    } else {
                                        AlbumArt(title: item.title, size: 40)
                                    }
                                }
                                .frame(width: 40, height: 40)
                                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))

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

// MARK: - 细条进度/音量控件
//
// 和 Apple Music 一样：静态时只有一条 4pt 的线，按住拖动时把手才浮出来。
// 命中区域仍是 18pt 高，手指不用瞄得很准。

struct SlimBar: View {
    var progress: Double
    var onScrub: (Double) -> Void = { _ in }
    var onCommit: (Double) -> Void = { _ in }
    var trackHeight: CGFloat = 4
    var enabled: Bool = true

    @State private var dragging = false
    @State private var local: Double = 0

    var body: some View {
        GeometryReader { geo in
            let w = max(1, geo.size.width)
            let p = CGFloat(min(max(dragging ? local : progress, 0), 1))

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.primary.opacity(0.14))
                    .frame(height: trackHeight)

                Capsule()
                    .fill(Color.primary.opacity(0.78))
                    .frame(width: max(0, w * p), height: trackHeight)

                if dragging {
                    Circle()
                        .fill(Color.primary)
                        .frame(width: 12, height: 12)
                        .offset(x: min(w * p, w - 6) - 6)
                        .transition(.opacity)
                }
            }
            .frame(width: w, height: 18)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { v in
                        guard enabled else { return }
                        dragging = true
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
        .frame(height: 18)
        .opacity(enabled ? 1 : 0.4)
    }
}

// MARK: - 系统音量条

struct VolumeBar: View {
    @State private var level: Double = SystemVolume.shared.level
    @State private var dragging = false
    @State private var local: Double = 0

    private let ticker = Timer.publish(every: 0.25, on: .main, in: .common).autoconnect()

    var body: some View {
        SlimBar(progress: dragging ? local : level,
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
                trackHeight: 4)
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
