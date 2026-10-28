import SwiftUI
import UniformTypeIdentifiers

// MARK: - 音乐
//
// 参照 Apple Music 的极简结构：大标题 + 常驻搜索栏 + 列表 + 底部迷你播放条，
// 点开是铺满全屏的播放页。搜索直接查 Apple Music 曲库，点歌在 App 内播放，
// 不再把用户甩到别的 App。

struct MusicView: View {
    @ObservedObject private var hub = MusicHub.shared
    @ObservedObject private var store = Store.shared

    @State private var query = ""
    @State private var results: [ITunesTrack] = []
    @State private var isSearching = false
    @State private var message: String?
    @State private var showPicker = false
    @State private var showPlayer = false
    @State private var searchTask: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if query.trimmingCharacters(in: .whitespaces).isEmpty {
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
                Text("Apple Music 曲库 · \(results.count) 首")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.secondary)

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
                VStack(alignment: .leading, spacing: 2) {
                    Text(t.title)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    HStack(spacing: 5) {
                        if !t.hasPreview {
                            Image(systemName: "lock.fill")
                                .font(.system(size: 8))
                        }
                        Text(t.hasPreview ? t.artist : "\(t.artist) · 仅 Apple Music")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
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
                    Label("在 Apple Music 打开完整版", systemImage: "arrow.up.forward.app")
                }
            }
            Button {
                NeteaseService.search("\(t.title) \(t.artist)")
            } label: {
                Label("去网易云搜这首歌", systemImage: "waveform")
            }
        }
    }

    private func playTrack(_ t: ITunesTrack) {
        let playable = results.filter { $0.hasPreview }
        guard let pos = playable.firstIndex(where: { $0.id == t.id }) else {
            message = "「\(t.title)」没有试听片段，用长按菜单去 Apple Music 听完整版。"
            return
        }
        let items: [PlayItem] = playable.compactMap { makeItem($0) }
        guard items.indices.contains(pos) else { return }
        hub.play(items: items, startingAt: pos)
        showPlayer = true
    }

    private func makeItem(_ r: ITunesTrack) -> PlayItem? {
        guard let p = r.preview else { return nil }
        return PlayItem(id: r.id,
                        title: r.title,
                        artist: r.artist,
                        artworkURL: r.artworkLarge,
                        fileURL: p,
                        source: .preview,
                        externalURL: r.storeURL,
                        fullDuration: r.duration)
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
            Text("搜索走的是 Apple Music 曲库，能播的是 30 秒官方试听片段（完整曲目受版权限制只能在 Apple Music 里放）。本地导入的音乐不受此限制，可以整首循环。")
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
    @ObservedObject private var hub = MusicHub.shared
    var onTap: () -> Void

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

struct NowPlayingView: View {
    @ObservedObject private var hub = MusicHub.shared
    @Environment(\.dismiss) private var dismiss
    @State private var dragOffset: CGFloat = 0

    var body: some View {
        ZStack {
            AppBackground()

            VStack(spacing: 0) {
                // 顶部把手 + 收起
                HStack {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.primary)
                            .frame(width: 38, height: 38)
                            .glassInner(cornerRadius: 19)
                    }
                    .buttonStyle(.plain)
                    Spacer()
                    Text("正在播放")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.secondary)
                    Spacer()
                    Menu {
                        Toggle(isOn: $hub.repeatOne) {
                            Label("单曲循环", systemImage: "repeat.1")
                        }
                        if let u = hub.current?.externalURL {
                            Button {
                                UIApplication.shared.open(u)
                            } label: {
                                Label("在 Apple Music 打开完整版", systemImage: "arrow.up.forward.app")
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
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.primary)
                            .frame(width: 38, height: 38)
                            .glassInner(cornerRadius: 19)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)

                Spacer(minLength: 12)

                cover

                Spacer(minLength: 16)

                VStack(spacing: 5) {
                    Text(hub.current?.title ?? "没有正在播放的音乐")
                        .font(.system(size: 22, weight: .bold))
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                    Text(hub.current?.artist.isEmpty == false
                         ? (hub.current?.artist ?? "")
                         : (hub.current?.subtitle ?? ""))
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                .padding(.horizontal, 24)

                Spacer(minLength: 18)

                progress

                controls

                Spacer(minLength: 26)
            }
            .padding(.bottom, 10)
        }
        .offset(y: max(0, dragOffset))
        .gesture(
            DragGesture()
                .onChanged { v in dragOffset = v.translation.height }
                .onEnded { v in
                    if v.translation.height > 120 {
                        dismiss()
                    } else {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                            dragOffset = 0
                        }
                    }
                }
        )
    }

    private var cover: some View {
        Group {
            if let u = hub.current?.artworkURL {
                AsyncImage(url: u) { phase in
                    if case .success(let img) = phase {
                        img.resizable().aspectRatio(contentMode: .fit)
                    } else {
                        AlbumArt(title: hub.current?.title ?? "REPS", size: 300)
                    }
                }
            } else {
                AlbumArt(title: hub.current?.title ?? "REPS", size: 300)
            }
        }
        .frame(maxWidth: 300)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: .black.opacity(0.22), radius: 26, y: 16)
        .padding(.horizontal, 36)
        .scaleEffect(hub.isPlaying ? 1 : 0.94)
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: hub.isPlaying)
    }

    private var progress: some View {
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
            .font(.system(size: 11, weight: .medium))
            .monospacedDigit()
            .foregroundColor(.secondary)
        }
        .padding(.horizontal, 28)
    }

    private var controls: some View {
        HStack(spacing: 46) {
            Button { hub.previous() } label: {
                Image(systemName: "backward.fill").font(.system(size: 26))
            }
            Button { hub.toggle() } label: {
                Image(systemName: hub.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 42))
                    .frame(width: 56, height: 56)
            }
            Button { hub.next(userInitiated: true) } label: {
                Image(systemName: "forward.fill").font(.system(size: 26))
            }
        }
        .foregroundColor(.primary)
        .padding(.top, 18)
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
