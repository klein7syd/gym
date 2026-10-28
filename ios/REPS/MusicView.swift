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
    @ObservedObject var player = PlayerPresenter.shared

    @State private var query = ""
    /// 资料库搜索结果（全部可直接完整播放，不再有 30 秒试听）
    @State private var libraryHits: [MPMediaItem] = []
    /// 命中的专辑（按专辑排版用，带整张曲目）
    @State private var albumHits: [AppleMusicService.Album] = []
    @State private var didSearch = false
    @State private var showPicker = false

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
                if hub.current != nil, !player.isOpen {
                    MiniPlayerBar { player.open() }
                }
            }
            .navigationDestination(for: String.self) { key in
                AlbumDetailView(albumKey: key)
            }
            .sheet(isPresented: $showPicker) {
                DocumentPicker(contentTypes: [.audio], allowsMultiple: true) { urls in
                    let n = hub.importFiles(urls)
                    if n > 0, hub.localTracks.count == n {
                        hub.playLocal(at: 0)
                    }
                }
            }
        }
    }

    // MARK: - 两个界面

    @ViewBuilder
    private var applePane: some View {
        // 搜索页不放播放器卡片、不放「已连接」卡片 —— 底下已经有迷你播放条了。
        // 只有还没授权时才留一行极简提示，否则搜不出任何东西。
        if !am.isGranted { authRow }

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
            Text("搜歌名、艺人、专辑，也可以打拼音首字母。想加歌就去 Apple Music 里点「+」。")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 26)
        .padding(.horizontal, 18)
    }

    // MARK: - 未授权时的一行提示

    @ViewBuilder
    private var authRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "music.note.tv")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.accentColor)
            Text(am.access == .denied ? "资料库权限被关闭，搜不到歌" : "需要读取你的 Apple Music 资料库")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .lineLimit(1)
            Spacer(minLength: 4)
            Button {
                if am.access == .denied {
                    if let u = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(u)
                    }
                } else {
                    am.requestAccess { ok in
                        if ok { runLibrarySearch() }
                    }
                }
            } label: {
                Text(am.access == .denied ? "去设置" : "授权")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.accentColor)
                    .padding(.horizontal, 12)
                    .frame(height: 30)
                    .background(Capsule().fill(Color.accentColor.opacity(0.13)))
            }
            .buttonStyle(ScaleButtonStyle())
        }
        .padding(.horizontal, 4)
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
            albumHits = []
            didSearch = false
            return
        }
        didSearch = true
        libraryHits = am.search(q)
        albumHits = am.albums(from: libraryHits, matching: q)
        // 前几行的封面先排进后台，滚动时不至于一片灰
        ArtworkStore.shared.prefetch(libraryHits, side: 160, limit: 12)
    }

    // MARK: - 搜索结果（专辑网格 + 歌曲）
    //
    // 照 Apple Music 的版式：先「专辑」两列网格（封面 / 专辑名 / 艺人·年份），
    // 点进一张专辑能看到**整张**曲目（不再只有命中的那几首），下面是「歌曲」直接开播。
    // 队列仍是整串结果，persistentID 精确寻址，点哪首就是哪首。

    private var tileSide: CGFloat {
        let w = UIScreen.main.bounds.width - 40      // 页面左右各 20
        return max(120, floor((w - 12) / 2))         // 两列，列间距 12
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
            if !albumHits.isEmpty {
                sectionHeader("专辑", trailing: "\(albumHits.count) 张")

                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12),
                                    GridItem(.flexible(), spacing: 12)],
                          alignment: .leading,
                          spacing: 18) {
                    ForEach(albumHits) { a in
                        albumTile(a)
                    }
                }
                .padding(.bottom, 6)
            }

            sectionHeader("歌曲", trailing: "\(libraryHits.count) 首")

            LazyVStack(spacing: 0) {
                ForEach(libraryHits.indices, id: \.self) { i in
                    libraryRow(libraryHits[i], index: i)
                    if i != libraryHits.count - 1 {
                        Divider().padding(.leading, 66)
                    }
                }
            }
            .padding(.vertical, 4)
            .glass()
        }
    }

    private func sectionHeader(_ title: String, trailing: String) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.system(size: 17, weight: .bold))
            Spacer(minLength: 4)
            Text(trailing)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 4)
        .padding(.top, 4)
    }

    /// 专辑格子：封面 + 标题 + 艺人·年份（点进去是整张专辑）
    private func albumTile(_ a: AppleMusicService.Album) -> some View {
        NavigationLink(value: a.id) {
            VStack(alignment: .leading, spacing: 8) {
                TrackArt(title: a.title, mediaID: a.sampleID, size: tileSide, corner: 6)
                    .shadow(color: .black.opacity(0.10), radius: 8, y: 4)

                Text(a.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.primary)
                    .lineLimit(1)

                Text(a.subtitle)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .padding(.top, 2)
            }
            .frame(width: tileSide, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// 歌曲行：封面 + 歌名 + 艺人·专辑 + 时长
    private func libraryRow(_ m: MPMediaItem, index: Int) -> some View {
        let playing = hub.current?.mediaID == m.persistentID
        return Button {
            playLibrary(at: index)
        } label: {
            HStack(spacing: 12) {
                TrackArt(title: m.title ?? "未知曲目",
                         mediaID: m.persistentID,
                         size: 50)
                VStack(alignment: .leading, spacing: 4) {
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
            .padding(.vertical, 11)
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

    /// 点哪首放哪首：队列就是当前这串结果，每首带着 persistentID，不会串歌。
    private func playLibrary(at index: Int) {
        let items = MusicHub.items(from: libraryHits)
        guard items.indices.contains(index) else { return }
        hub.play(items: items, startingAt: index)
        player.open()
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
                player.open()
            } label: {
                HStack(spacing: 14) {
                    TrackArt(title: hub.current?.title ?? "REPS",
                             mediaID: hub.current?.mediaID,
                             size: 76)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("正在播放")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.secondary)
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
            VStack(spacing: 6) {
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
        // 按 id 比较：本地曲目进队列时 PlayItem.id = Track.id.uuidString（MusicHub.localItems），
        // 所以能精确对上；以前按歌名比，同名歌会一起高亮。
        let playing = hub.current?.source == .local && hub.current?.id == track.id.uuidString
        return Button {
            hub.playLocal(at: index)
            player.open()
        } label: {
            HStack(spacing: 12) {
                AlbumArt(title: track.title, size: 46)
                VStack(alignment: .leading, spacing: 4) {
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
            .padding(.vertical, 11)
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

// MARK: - 专辑详情
//
// 从搜索结果的专辑格子点进来。这里列的是**整张**专辑的曲目（不只是搜索命中的那几首），
// 版式照 Apple Music：居中大封面、专辑名、艺人·年份、两个胶囊按钮、带音轨号的曲目表。

struct AlbumDetailView: View {
    let albumKey: String

    @ObservedObject var hub = MusicHub.shared
    @ObservedObject var am = AppleMusicService.shared
    @ObservedObject var player = PlayerPresenter.shared

    private var album: AppleMusicService.Album? { am.album(forKey: albumKey) }

    private var coverSide: CGFloat {
        min(UIScreen.main.bounds.width * 0.52, 200)
    }

    var body: some View {
        ScrollView {
            if let a = album {
                VStack(spacing: 0) {
                    header(a)
                    actions(a)
                    trackList(a)
                }
                .padding(.bottom, 120)
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "music.note.list")
                        .font(.system(size: 22, weight: .light))
                        .foregroundColor(.secondary)
                    Text("这张专辑还没读出来")
                        .font(.system(size: 13, weight: .semibold))
                    Text("回上一页，用右上角菜单刷新一次资料库再进来。")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 60)
            }
        }
        .background { AppBackground() }
        .navigationTitle(album?.title ?? "专辑")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            if hub.current != nil, !player.isOpen {
                MiniPlayerBar { player.open() }
            }
        }
    }

    // MARK: 头部

    private func header(_ a: AppleMusicService.Album) -> some View {
        VStack(spacing: 16) {
            TrackArt(title: a.title, mediaID: a.sampleID, size: coverSide, corner: 8)
                .shadow(color: .black.opacity(0.16), radius: 18, y: 10)

            VStack(spacing: 6) {
                // Apple Music 的顺序：大字是**专辑名**，小字才是「艺人 · 年份」
                Text(a.title)
                    .font(.system(size: 21, weight: .bold))
                    .lineSpacing(3)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)

                Text([a.displayArtist, a.year > 0 ? "\(a.year) 年" : ""]
                        .filter { !$0.isEmpty }
                        .joined(separator: " · "))
                    .font(.system(size: 13))
                    .lineSpacing(2)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)

                Text("\(a.items.count) 首")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 24)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 16)
    }

    private func actions(_ a: AppleMusicService.Album) -> some View {
        HStack(spacing: 12) {
            Button {
                play(a, shuffled: false)
            } label: {
                Label("播放", systemImage: "play.fill")
            }
            .buttonStyle(GlassButtonStyle())

            Button {
                play(a, shuffled: true)
            } label: {
                Label("随机播放", systemImage: "shuffle")
            }
            .buttonStyle(GlassButtonStyle())
        }
        .padding(.horizontal, 20)
        .padding(.top, 22)
        .padding(.bottom, 18)
    }

    // MARK: 曲目

    private func trackList(_ a: AppleMusicService.Album) -> some View {
        VStack(spacing: 0) {
            ForEach(a.items.indices, id: \.self) { i in
                trackRow(a.items[i], position: i + 1, album: a, index: i)
                if i != a.items.count - 1 {
                    Divider().padding(.leading, 56)
                }
            }
        }
        .padding(.vertical, 6)
        .glass()
        .padding(.horizontal, 20)
    }

    private func trackRow(_ m: MPMediaItem,
                          position: Int,
                          album a: AppleMusicService.Album,
                          index: Int) -> some View {
        let playing = hub.current?.mediaID == m.persistentID
        let no = m.albumTrackNumber > 0 ? m.albumTrackNumber : position
        return Button {
            play(a, shuffled: false, startAt: index)
        } label: {
            HStack(spacing: 10) {
                Text("\(no)")
                    .font(.system(size: 12, design: .rounded))
                    .monospacedDigit()
                    .foregroundColor(playing ? .accentColor : .secondary)
                    .frame(width: 22, alignment: .trailing)

                Text(m.title ?? "未知曲目")
                    .font(.system(size: 15, weight: playing ? .semibold : .regular))
                    .lineSpacing(3)
                    .foregroundColor(playing ? .accentColor : .primary)
                    .lineLimit(2)

                Spacer(minLength: 6)

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
            .padding(.leading, 12)
            .padding(.trailing, 14)
            .padding(.vertical, 13)
            .frame(minHeight: 52)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: 播放

    private func play(_ a: AppleMusicService.Album, shuffled: Bool, startAt: Int = 0) {
        var media = a.items
        var start = startAt
        if shuffled {
            media.shuffle()
            start = 0
        }
        let items = MusicHub.items(from: media)
        guard items.indices.contains(start) else { return }
        hub.play(items: items, startingAt: start)
        player.open()
    }
}

// MARK: - 全屏播放页
//
// 版式跟 Apple Music 对齐（左边距统一 24，所有元素共用一条中轴）：
//
//            ── 抓手 ──
//   ⌄          正在播放           ⋯
//        [      封面      ]      屏宽 76%，上限 322
//   歌名（22 粗，左对齐）
//   艺人（17，灰，左对齐）
//   ══════ 进度条 8pt ══════
//   0:12                  -3:20
//   ☰     ⏮     ▶     ⏭     🔁
//   🔈 ═════ 音量 ═════ 🔊
//   [ 训练状态卡 ]  ← 点开是训练面板
//
// 背景是灰色液态玻璃，整页固定深色，所以进度 / 音量条是白色。

struct NowPlayingView: View {
    @ObservedObject var hub = MusicHub.shared
    @ObservedObject var store = Store.shared
    @ObservedObject var rest = RestTimer.shared
    @ObservedObject var player = PlayerPresenter.shared

    @State private var dragOffset: CGFloat = 0
    /// 这一轮下拉有没有已经通知过「开始关闭」（只在第一次 onChanged 里发一次）
    @State private var dismissing = false
    @State private var showQueue = false
    @State private var showTraining = false
    /// 拖动进度条时的临时秒数（nil = 没在拖，跟随播放器）
    @State private var scrub: Double?

    /// 全页统一左右留白：封面、标题、进度条、按钮、音量都对齐到这条线
    private let inset: CGFloat = 24

    var body: some View {
        GeometryReader { geo in
            let safe = SafeArea.insets
            // 除封面以外的固定高度（抓手 + 头部 + 标题 + 进度 + 控制 + 音量 + 训练卡）
            //
            // 4.9.2 由 448 加到 462，构成：标题区两行间距 +3（2→5）、
            // 训练卡文字间距 +4（4→6，两处间隙各 +2）、训练卡上下内边距 +4（12→14）、
            // 右侧三个小按钮间距 +2（8→9）、再留 1pt 余量。
            // 小屏预算（side = min(宽×0.82, 高 - 上下安全区 - 462, 340)）：
            //   iPhone SE3 375×667（安全区 20/0）→ 185pt，未触及 130 下限；
            //   iPhone 13 mini 375×812（50/34）→ 266pt；iPhone 16（59/34）→ 297pt。
            // 也就是说小屏上封面会变小一点，但不会被挤出屏幕（Spacer 还能再压）。
            let fixed: CGFloat = 462
            // 铺满整屏之后高度富余，封面按屏宽 82% 走，上限 340
            let side = max(130, min(geo.size.width * 0.82,
                                    geo.size.height - safe.top - safe.bottom - fixed,
                                    340))
            // 标题 / 进度 / 控制 / 音量都对齐到封面的左右边线（Apple Music 就是这个对齐）
            let pad = max(inset, (geo.size.width - side) / 2)

            VStack(spacing: 0) {
                grabber

                header

                Spacer(minLength: 10)

                cover(side: side)

                Spacer(minLength: 18)
                    .frame(height: 24)

                titleBlock(pad: pad)

                Spacer(minLength: 16)
                    .frame(height: 20)

                progressRow(pad: pad)

                Spacer(minLength: 12)
                    .frame(height: 18)

                controls(pad: pad)

                Spacer(minLength: 12)
                    .frame(height: 18)

                volume(pad: pad)

                Spacer(minLength: 10)

                trainingBar
                    .padding(.horizontal, 16)
            }
            // 忽略安全区再自己让回来：这样背景和圆角裁剪都覆盖到状态栏 / 底部横条，
            // 不会在上下各留一条黑边
            .padding(.top, safe.top)
            .padding(.bottom, max(safe.bottom, 10))
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .ignoresSafeArea()
        .background { playerBackground }
        // 顺序必须是「背景 → CardClip → offset」：
        // 遮罩要盖在卡片本身上，再让整张卡片往下位移，圆角才会跟着走；
        // 反过来（先 offset 再 mask）遮罩会留在原地，拖动时圆角跑到屏幕角落去。
        .modifier(CardClip(active: dragOffset > 0.5, radius: min(34, dragOffset / 5)))
        .offset(y: max(0, dragOffset))
        .environment(\.colorScheme, .dark)
        .sheet(isPresented: $showQueue) {
            QueueSheet()
        }
        .sheet(isPresented: $showTraining) {
            TrainingSheet()
        }
    }

    // MARK: 背景

    /// 灰色液态玻璃：灰底 + 半透明材质 + 中性柔光 + 薄白釉面。
    /// 只有灰度没有色相，所以不会发蓝发紫。
    private var playerBackground: some View {
        ZStack {
            Color(white: 0.13)

            Rectangle().fill(.ultraThinMaterial)

            Circle()
                .fill(Color.white.opacity(0.10))
                .frame(width: 420, height: 420)
                .blur(radius: 130)
                .offset(x: -110, y: -260)

            Circle()
                .fill(Color.white.opacity(0.05))
                .frame(width: 460, height: 460)
                .blur(radius: 150)
                .offset(x: 130, y: 300)

            Color.white.opacity(0.03)
        }
        .environment(\.colorScheme, .dark)
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    // MARK: 抓手

    private var grabber: some View {
        Capsule()
            .fill(Color.secondary.opacity(0.30))
            .frame(width: 36, height: 5)
            .padding(.top, 6)
            .padding(.bottom, 4)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .gesture(dismissDrag)
    }

    // MARK: 顶部

    private var header: some View {
        HStack(spacing: 0) {
            Button {
                player.close()
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
                Button {
                    showTraining = true
                } label: {
                    Label("打开训练面板", systemImage: "figure.strengthtraining.traditional")
                }
                if let u = hub.current?.externalURL {
                    Button {
                        UIApplication.shared.open(u)
                    } label: {
                        Label("在 Apple Music 打开", systemImage: "arrow.up.forward.app")
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
        .gesture(dismissDrag)
    }

    /// 往下拖收回：底下的菜单一直可见（并被一起带着放大 / 变亮），所以不会出现黑边；
    /// 拖过阈值就关，没拖够就弹回原位。
    private var dismissDrag: some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { v in
                let h = max(0, v.translation.height)
                dragOffset = h
                // 0…1：拉到 260pt 就算到底，下层同步动
                player.pull = min(1, h / 260)
                // 刚拖起来（位移还只有 8pt 左右、底下几乎没露出）就把窗口切回浅色。
                // 这一步不能等到松手：拖到一半时底下那整页已经露出来了，
                // 那时再从深变浅，就是肉眼看到的「下拉闪一下」。
                if h > 0 && !dismissing {
                    dismissing = true
                    player.beginDismiss()
                }
            }
            .onEnded { v in
                dismissing = false
                let far = v.translation.height > 110 || v.predictedEndTranslation.height > 260
                if far {
                    player.close()
                } else {
                    withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
                        dragOffset = 0
                        player.pull = 0
                    }
                    // 弹回原位后再把窗口切回深色（0.36s 后，弹回动画 0.34s）
                    player.cancelDismiss()
                }
            }
    }

    // MARK: 封面

    private func cover(side: CGFloat) -> some View {
        TrackArt(title: hub.current?.title ?? "REPS",
                 mediaID: hub.current?.mediaID,
                 size: side,
                 corner: 8)
            .shadow(color: .black.opacity(0.30), radius: 24, y: 16)
            .animation(.easeOut(duration: 0.25), value: side)
            .gesture(dismissDrag)
    }

    // MARK: 歌名 / 艺人

    private func titleBlock(pad: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(hub.current?.title ?? "没有正在播放的音乐")
                .font(.system(size: 24, weight: .semibold))
                .lineSpacing(2)
                .foregroundColor(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)

            Text(subtitleText)
                .font(.system(size: 18, weight: .regular))
                .lineSpacing(2)
                .foregroundColor(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, pad)
        .contentShape(Rectangle())
        .gesture(dismissDrag)
    }

    private var subtitleText: String {
        guard let c = hub.current else { return "" }
        return c.artist.isEmpty ? c.subtitle : c.artist
    }

    // MARK: 进度

    private func progressRow(pad: CGFloat) -> some View {
        VStack(spacing: 6) {
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
            .font(.system(size: 12, weight: .medium))
            .monospacedDigit()
            .foregroundColor(.secondary)
        }
        .padding(.horizontal, pad)
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
    // Apple Music 是「随机 / 上一首 / 播放 / 下一首 / 循环」，第一个位置这里换成播放列表。

    private func controls(pad: CGFloat) -> some View {
        HStack(spacing: 0) {
            Button {
                showQueue = true
            } label: {
                Image(systemName: "list.bullet")
                    .font(.system(size: 21, weight: .regular))
                    .foregroundColor(.primary)
                    .frame(width: 50, height: 50)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Spacer(minLength: 0)

            Button {
                hub.previous()
            } label: {
                Image(systemName: "backward.fill")
                    .font(.system(size: 30))
                    .foregroundColor(.primary)
                    .frame(width: 58, height: 58)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button {
                hub.toggle()
            } label: {
                Image(systemName: hub.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 48))
                    .foregroundColor(.primary)
                    .frame(width: 84, height: 58)
                    .contentShape(Rectangle())
            }
            .buttonStyle(ScaleButtonStyle(scale: 0.9))

            Button {
                hub.next(userInitiated: true)
            } label: {
                Image(systemName: "forward.fill")
                    .font(.system(size: 30))
                    .foregroundColor(.primary)
                    .frame(width: 58, height: 58)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Spacer(minLength: 0)

            Button {
                hub.cycleRepeatMode()
            } label: {
                Image(systemName: hub.repeatMode.symbol)
                    .font(.system(size: 21, weight: .regular))
                    .foregroundColor(hub.repeatMode.isOn ? .accentColor : .primary)
                    .frame(width: 50, height: 50)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        // 图标本身有 46pt 命中框，往里收一点，视觉上才和封面边线齐
        .padding(.horizontal, max(0, pad - 8))
    }

    // MARK: 系统音量

    private func volume(pad: CGFloat) -> some View {
        HStack(spacing: 9) {
            Image(systemName: "speaker.fill")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
            VolumeBar(trackHeight: 8)
            Image(systemName: "speaker.wave.3.fill")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, pad)
    }

    // MARK: 底部训练状态（顶掉 Apple Music 的歌词 / 待播 / AirPlay）

    private var trainingBar: some View {
        HStack(alignment: .center, spacing: 10) {
            if rest.isRunning {
                MiniRestRing(progress: rest.progress, text: rest.remainingText, size: 62)
            }

            Button {
                showTraining = true
            } label: {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 5) {
                        Image(systemName: "figure.strengthtraining.traditional")
                            .font(.system(size: 11, weight: .semibold))
                        Text(store.current != nil ? "正在训练 · 第 \(setCount) 组" : "还没开始训练")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundColor(.secondary)

                    Text(store.current != nil ? store.currentExercise.name : "打开训练面板")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(.primary)
                        .lineLimit(1)

                    Text(trainingDetail)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            VStack(spacing: 9) {
                if rest.isRunning {
                    smallButton("+30") { rest.add(seconds: 30) }
                } else {
                    smallButton("\(store.restSeconds)s") { rest.start(seconds: store.restSeconds) }
                }
                smallButton("完成", tint: .accentColor) { completeSet() }
                smallButton("跳过") { rest.skip() }
            }
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 14)
        .glass(cornerRadius: 24)
    }

    private func smallButton(_ title: String,
                             tint: Color = .primary,
                             action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(tint)
                .frame(width: 64, height: 31)
                .background(Capsule().fill(tint.opacity(0.14)))
                .contentShape(Capsule())
        }
        .buttonStyle(ScaleButtonStyle(scale: 0.92))
    }

    private var setCount: Int {
        store.current == nil ? 0 : store.currentExercise.sets.count
    }

    private var trainingDetail: String {
        guard store.current != nil else {
            return "点这里记组、调重量，和训练页同步"
        }
        if let s = store.currentExercise.sets.last {
            return "上一组 \(fmtWeight(s.w)) kg × \(s.r) · 共 \(setCount) 组"
        }
        return "这个动作还没记录，调好重量再点「完成」"
    }

    private func completeSet() {
        guard store.current != nil else {
            showTraining = true
            return
        }
        _ = store.ensureSession()
        store.logSet(weight: store.lastWeight, reps: store.lastReps)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        rest.start(seconds: store.restSeconds)
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
                        row(index: i, item: item)
                    }
                    // 任何一行都能直接拖：不用先点「排序」
                    .onMove { source, dest in
                        hub.reorder(from: source, to: dest)
                    }
                } header: {
                    Text("\(hub.queue.count) 首 · \(hub.repeatMode.label)")
                } footer: {
                    Text("按住任意一行上下拖动即可调整顺序，松手即时生效；点一下就是跳到那首。")
                }
            }
            // 常驻排序状态：右侧把手一直在，滑动就能改顺序
            .environment(\.editMode, .constant(.active))
            .navigationTitle("播放列表")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("关闭") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
    }

    private func row(index i: Int, item: PlayItem) -> some View {
        let content = HStack(spacing: 10) {
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
        // 排序状态常开，用 tap 手势而不是 Button —— Button 在编辑态的行里容易被行本身吃掉
        return content
            .contentShape(Rectangle())
            .onTapGesture { hub.jump(to: i) }
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
                    .fill(Color.primary.opacity(scheme == .dark ? 0.22 : 0.12))
                    .overlay(
                        Capsule(style: .continuous)
                            .strokeBorder(Color.white.opacity(scheme == .dark ? 0.12 : 0.45),
                                          lineWidth: 0.5)
                    )
                    .frame(height: trackHeight)

                // 已播放段：白 / 深灰玻璃
                Capsule(style: .continuous)
                    .fill(fillColor)
                    .overlay(
                        Capsule(style: .continuous)
                            .strokeBorder(Color.white.opacity(scheme == .dark ? 0.65 : 0.30),
                                          lineWidth: 0.5)
                    )
                    .frame(height: trackHeight)
                    .mask(alignment: .leading) {
                        Rectangle().frame(width: w * p)
                    }
                    .shadow(color: fillColor.opacity(scheme == .dark ? 0.45 : 0.35), radius: 4, y: 0)
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
            ? Color.white.opacity(0.97)
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
