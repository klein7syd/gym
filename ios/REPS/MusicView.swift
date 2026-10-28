import SwiftUI
import MediaPlayer
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

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if query.trimmingCharacters(in: .whitespaces).isEmpty {
                        appleMusicCard
                        if hub.current != nil { nowPlayingCard }
                        localSection
                        tipCard
                    } else {
                        searchSection
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 120)
            }
            .background { AppBackground() }
            .scrollDismissesKeyboard(.interactively)
            .searchable(text: $query,
                        placement: .navigationBarDrawer(displayMode: .always),
                        prompt: "搜索 Apple Music")
            .onSubmit(of: .search) { runSearch() }
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

            VStack(spacing: 2) {
                Slider(value: Binding(get: { hub.currentTime },
                                      set: { hub.seek(to: $0) }),
                       in: 0...max(1, hub.duration))
                    .tint(.primary)
                HStack {
                    Text(MusicHub.formatTime(hub.currentTime))
                    Spacer()
                    Text(MusicHub.formatTime(hub.duration))
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

    private var localSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("本地音乐")
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
                Button {
                    showPicker = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .semibold))
                }
                .buttonStyle(.plain)
            }

            if hub.localTracks.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "music.note.list")
                        .font(.system(size: 26, weight: .light))
                        .foregroundColor(.secondary)
                    Text("还没有本地音乐")
                        .font(.system(size: 14, weight: .medium))
                    Text("从「文件」里导入 mp3 / m4a / wav，存进沙盒后永久有效")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                    Button {
                        showPicker = true
                    } label: {
                        Text("导入音乐")
                    }
                    .buttonStyle(GlassButtonStyle())
                    .padding(.top, 2)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
                .padding(.horizontal, 14)
                .glass()
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(hub.localTracks.enumerated()), id: \.element.id) { i, t in
                        let playing = hub.current?.source == .local
                            && hub.current?.title == t.title
                        Button {
                            hub.playLocal(at: i)
                            showPlayer = true
                        } label: {
                            HStack(spacing: 12) {
                                AlbumArt(title: t.title, size: 46)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(t.title)
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
                                hub.removeTracks(at: IndexSet(integer: i))
                            } label: {
                                Label("移除", systemImage: "trash")
                            }
                        }
                        if i != hub.localTracks.count - 1 {
                            Divider().padding(.leading, 70)
                        }
                    }
                }
                .padding(.vertical, 4)
                .glass()
            }

            if let err = hub.errorMessage {
                Text(err)
                    .font(.system(size: 11))
                    .foregroundColor(.red)
            }
        }
    }

    private var tipCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("关于曲库")
                .font(.system(size: 12, weight: .semibold))
            Text("搜索走 Apple Music 曲库。歌只要在你 Apple Music 的「资料库」里，这里就能整首完整播放；不在资料库的先给你 30 秒官方试听。想听某首完整版，在 Apple Music 里点歌名旁的「+」加进资料库，回到这里下拉刷新即可。")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .glass(cornerRadius: 20, shadow: false)
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
// 布局比上一版整体上移、收紧：封面从 300pt 降到最多 244pt，段间距压到 8-12pt，
// 中间区域可滚动，保证小屏（SE）也不会把控件挤出屏幕。
// 从上到下：收起 + 菜单 / 封面 / 歌名 / 进度 / 播放控制（含循环方式、播放列表）
// / 系统音量条 / 底部固定的训练状态（与训练页共用同一个 RestTimer）。

struct NowPlayingView: View {
    @ObservedObject var hub = MusicHub.shared
    @ObservedObject var store = Store.shared
    @ObservedObject var rest = RestTimer.shared
    @Environment(\.dismiss) private var dismiss
    @State private var dragOffset: CGFloat = 0
    @State private var showQueue = false

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width - 104, 244)

            ZStack {
                AppBackground()

                VStack(spacing: 0) {
                    header

                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 11) {
                            cover(side: side)
                            titleBlock
                            progress
                            controls
                            volume
                        }
                        .padding(.top, 6)
                        .padding(.bottom, 4)
                    }

                    trainingBar
                        .padding(.horizontal, 16)
                        .padding(.top, 6)
                }
                .padding(.bottom, 6)
            }
        }
        .offset(y: max(0, dragOffset))
        .sheet(isPresented: $showQueue) {
            QueueSheet()
        }
    }

    // MARK: 顶部

    private var header: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.primary)
                    .frame(width: 34, height: 34)
                    .glassInner(cornerRadius: 17)
            }
            .buttonStyle(.plain)

            Spacer()

            VStack(spacing: 1) {
                Text(sourceLabel)
                    .font(.system(size: 9, weight: .bold))
                    .tracking(0.6)
                    .foregroundColor(hub.isPlayingFullVersion ? .green : .secondary)
                Text("正在播放")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)
            }

            Spacer()

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
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.primary)
                    .frame(width: 34, height: 34)
                    .glassInner(cornerRadius: 17)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
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

    private var sourceLabel: String {
        if hub.isPlayingFullVersion { return "APPLE MUSIC 完整版" }
        if let c = hub.current { return c.subtitle }
        return "REPS"
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
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Color.white.opacity(0.18), lineWidth: 0.8)
        )
        .shadow(color: .black.opacity(0.22), radius: 22, y: 12)
        .scaleEffect(hub.isPlaying ? 1 : 0.95)
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: hub.isPlaying)
    }

    // MARK: 歌名

    private var titleBlock: some View {
        VStack(spacing: 2) {
            Text(hub.current?.title ?? "没有正在播放的音乐")
                .font(.system(size: 18, weight: .bold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(subtitleText)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 26)
    }

    private var subtitleText: String {
        guard let c = hub.current else { return "" }
        return c.artist.isEmpty ? c.subtitle : c.artist
    }

    // MARK: 进度

    private var progress: some View {
        VStack(spacing: 0) {
            Slider(value: Binding(get: { hub.currentTime },
                                  set: { hub.seek(to: $0) }),
                   in: 0...max(1, hub.duration))
                .tint(.primary)
            HStack {
                Text(MusicHub.formatTime(hub.currentTime))
                Spacer()
                Text(MusicHub.formatTime(hub.duration))
            }
            .font(.system(size: 10, weight: .medium))
            .monospacedDigit()
            .foregroundColor(.secondary)
            .padding(.horizontal, 4)
        }
        .padding(.horizontal, 24)
        .padding(.top, -4)
    }

    // MARK: 播放控制（循环方式 / 上一首 / 播放 / 下一首 / 播放列表）

    private var controls: some View {
        HStack(spacing: 0) {
            Button {
                hub.cycleRepeatMode()
            } label: {
                Image(systemName: hub.repeatMode.symbol)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(hub.repeatMode.isOn ? .accentColor : .secondary)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Spacer(minLength: 0)

            Button {
                hub.previous()
            } label: {
                Image(systemName: "backward.fill")
                    .font(.system(size: 21))
                    .foregroundColor(.primary)
                    .frame(width: 50, height: 50)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button {
                hub.toggle()
            } label: {
                ZStack {
                    Circle().fill(.ultraThinMaterial)
                    Circle().strokeBorder(Color.white.opacity(0.32), lineWidth: 0.8)
                    Image(systemName: hub.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 28))
                        .foregroundColor(.primary)
                }
                .frame(width: 62, height: 62)
                .shadow(color: .black.opacity(0.12), radius: 10, y: 5)
            }
            .buttonStyle(ScaleButtonStyle(scale: 0.94))
            .padding(.horizontal, 6)

            Button {
                hub.next(userInitiated: true)
            } label: {
                Image(systemName: "forward.fill")
                    .font(.system(size: 21))
                    .foregroundColor(.primary)
                    .frame(width: 50, height: 50)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Spacer(minLength: 0)

            Button {
                showQueue = true
            } label: {
                Image(systemName: "list.bullet")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.secondary)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
    }

    // MARK: 系统音量

    private var volume: some View {
        HStack(spacing: 9) {
            Image(systemName: "speaker.fill")
                .font(.system(size: 9))
                .foregroundColor(.secondary)
            SystemVolumeSlider()
                .frame(height: 26)
            Image(systemName: "speaker.wave.3.fill")
                .font(.system(size: 9))
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 30)
        .padding(.top, 2)
    }

    // MARK: 底部训练状态
    //
    // 计时用的就是训练页那个 RestTimer：同一个剩余秒数、同一个进度环、同一套 +30/跳过。

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

// MARK: - 系统音量条
//
// iOS 不允许直接改 AVAudioSession.outputVolume，唯一合法且有效的方式是
// 把系统的 MPVolumeView 塞进界面。它控制的是设备真实音量，跟侧边键完全同步。

struct SystemVolumeSlider: UIViewRepresentable {
    func makeUIView(context: Context) -> MPVolumeView {
        let v = MPVolumeView()
        v.showsRouteButton = false
        v.backgroundColor = .clear
        v.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return v
    }

    func updateUIView(_ uiView: MPVolumeView, context: Context) {
        // MPVolumeView 内部的 UISlider 是懒创建的，等一拍再上色
        DispatchQueue.main.async {
            for sub in uiView.subviews {
                if let s = sub as? UISlider {
                    s.minimumTrackTintColor = UIColor.label
                    s.maximumTrackTintColor = UIColor.tertiaryLabel.withAlphaComponent(0.35)
                    s.thumbTintColor = UIColor.label
                }
            }
        }
    }
}


// MARK: - 抽象封面

/// 本地文件没有内嵌封面时，用歌名生成固定渐变封面，避免整页空白。
struct AlbumArt: View {
    let title: String
    var size: CGFloat

    var body: some View {
        let colors = Self.palette(for: title)
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.08, style: .continuous)
                .fill(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing))
            RoundedRectangle(cornerRadius: size * 0.08, style: .continuous)
                .fill(LinearGradient(colors: [Color.white.opacity(0.26), Color.clear],
                                     startPoint: .topLeading, endPoint: .center))
            Image(systemName: "music.note")
                .font(.system(size: size * 0.2, weight: .light))
                .foregroundColor(.white.opacity(0.92))
        }
        .frame(width: size, height: size)
        .overlay(
            RoundedRectangle(cornerRadius: size * 0.08, style: .continuous)
                .strokeBorder(Color.white.opacity(0.16), lineWidth: 1)
        )
    }

    static func palette(for title: String) -> [Color] {
        let palettes: [[Color]] = [
            [Color(red: 0.30, green: 0.42, blue: 0.98), Color(red: 0.62, green: 0.34, blue: 0.96)],
            [Color(red: 0.98, green: 0.44, blue: 0.38), Color(red: 0.96, green: 0.68, blue: 0.31)],
            [Color(red: 0.16, green: 0.78, blue: 0.62), Color(red: 0.14, green: 0.52, blue: 0.88)],
            [Color(red: 0.86, green: 0.36, blue: 0.62), Color(red: 0.52, green: 0.32, blue: 0.94)],
            [Color(red: 0.22, green: 0.68, blue: 0.88), Color(red: 0.36, green: 0.40, blue: 0.96)]
        ]
        let seed = title.unicodeScalars.reduce(0) { $0 &+ Int($1.value) }
        return palettes[abs(seed) % palettes.count]
    }
}
