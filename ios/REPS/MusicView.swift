import SwiftUI
import UniformTypeIdentifiers

// MARK: - 音乐页（Apple Music 风格：大封面、细线条、留白优先）

struct MusicView: View {
    @ObservedObject var player = AudioPlayer.shared
    @ObservedObject var store = Store.shared
    @ObservedObject var apple = AppleMusicService.shared

    enum Source: String, CaseIterable, Identifiable {
        case local = "本地"
        case apple = "Apple Music"
        case netease = "网易云"
        var id: String { rawValue }
    }

    @State private var source: Source = .local
    @State private var showPicker = false
    @State private var appleQuery = ""
    @State private var neteaseQuery = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                    sourcePicker
                        .padding(.top, 4)

                    if source == .local {
                        localPanel
                    } else if source == .apple {
                        applePanel
                    } else {
                        neteasePanel
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 120)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Color.clear)
            .navigationTitle("音乐")
            .toolbar {
                if source == .local {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button {
                            showPicker = true
                        } label: {
                            Image(systemName: "plus")
                                .font(.system(size: 16, weight: .semibold))
                        }
                    }
                }
                KeyboardDoneBar()
            }
            .sheet(isPresented: $showPicker) {
                DocumentPicker(contentTypes: [.audio], allowsMultiple: true) { urls in
                    let n = player.importFiles(urls)
                    if n > 0 && player.tracks.count == n {
                        player.select(index: 0)
                    }
                }
            }
        }
    }

    // MARK: - 来源切换

    private var sourcePicker: some View {
        HStack(spacing: 4) {
            ForEach(Source.allCases) { s in
                Button {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
                        source = s
                    }
                    UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                } label: {
                    Text(s.rawValue)
                        .font(.system(size: 13, weight: source == s ? .semibold : .medium))
                        .foregroundColor(source == s ? .primary : .secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background {
                            if source == s {
                                Capsule(style: .continuous)
                                    .fill(.ultraThinMaterial)
                                    .overlay(Capsule(style: .continuous)
                                        .strokeBorder(Color.white.opacity(0.45), lineWidth: 0.7))
                                    .shadow(color: .black.opacity(0.08), radius: 6, y: 2)
                            }
                        }
                }
                .buttonStyle(ScaleButtonStyle())
            }
        }
        .padding(4)
        .glassInner(cornerRadius: 24)
    }

    // MARK: - 本地面板

    private var localPanel: some View {
        VStack(spacing: 24) {
            AlbumArt(title: player.currentTrack?.title ?? "REPS", size: 266)
                .padding(.top, 6)

            VStack(spacing: 6) {
                Text(player.currentTrack?.title ?? "还没有音乐")
                    .font(.system(size: 21, weight: .bold))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                Text(player.tracks.isEmpty
                     ? "点右上角导入手机里的音频"
                     : "本地音乐 · 第 \(player.currentIndex + 1) / \(player.tracks.count) 首")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
            }

            VStack(spacing: 2) {
                Slider(value: Binding(get: { player.currentTime },
                                      set: { player.seek(to: $0) }),
                       in: 0...max(1, player.duration))
                    .tint(.primary)
                    .disabled(player.currentTrack == nil)
                HStack {
                    Text(AudioPlayer.formatTime(player.currentTime))
                    Spacer()
                    Text(AudioPlayer.formatTime(player.duration))
                }
                .font(.system(size: 11, weight: .medium))
                .monospacedDigit()
                .foregroundColor(.secondary)
            }

            HStack(spacing: 52) {
                Button { player.previous() } label: {
                    Image(systemName: "backward.fill").font(.system(size: 25))
                }
                Button { player.toggle() } label: {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 38))
                        .frame(width: 54, height: 54)
                }
                Button { player.next() } label: {
                    Image(systemName: "forward.fill").font(.system(size: 25))
                }
            }
            .foregroundColor(.primary)
            .disabled(player.tracks.isEmpty)

            playlistCard
        }
    }

    private var playlistCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("待播列表")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.secondary)
                Spacer()
                Text("\(player.tracks.count) 首")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 6)

            if player.tracks.isEmpty {
                Button {
                    showPicker = true
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "square.and.arrow.down")
                        Text("导入音乐")
                    }
                    .font(.system(size: 15, weight: .medium))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                }
                .buttonStyle(.plain)
            } else {
                ForEach(Array(player.tracks.enumerated()), id: \.element.id) { i, t in
                    Button {
                        player.select(index: i)
                    } label: {
                        HStack(spacing: 12) {
                            AlbumArt(title: t.title, size: 40)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(t.title)
                                    .font(.system(size: 15, weight: i == player.currentIndex ? .semibold : .regular))
                                    .foregroundColor(i == player.currentIndex ? .accentColor : .primary)
                                    .lineLimit(1)
                                Text("本地音乐")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            if i == player.currentIndex && player.isPlaying {
                                Image(systemName: "waveform")
                                    .font(.system(size: 13))
                                    .foregroundColor(.accentColor)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 9)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button(role: .destructive) {
                            player.removeTracks(at: IndexSet(integer: i))
                        } label: {
                            Label("移除", systemImage: "trash")
                        }
                    }
                }
                .padding(.bottom, 8)
            }

            if let err = player.errorMessage {
                Text(err)
                    .font(.system(size: 11))
                    .foregroundColor(.red)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 10)
            }
        }
        .glass()
    }

    // MARK: - Apple Music 面板

    private var applePanel: some View {
        VStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(LinearGradient(colors: [Color(red: 0.98, green: 0.30, blue: 0.42),
                                                          Color(red: 0.95, green: 0.20, blue: 0.55)],
                                                 startPoint: .topLeading, endPoint: .bottomTrailing))
                            .frame(width: 48, height: 48)
                        Image(systemName: "music.note")
                            .font(.system(size: 21, weight: .semibold))
                            .foregroundColor(.white)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Apple Music")
                            .font(.system(size: 17, weight: .semibold))
                        Text(appleStateText)
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                }

                Text("搜 Apple Music 曲库，点结果唤起 Apple Music 播放。会员曲目按你的订阅状态决定能否完整播放。")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 10) {
                    if apple.state != .authorized {
                        Button {
                            apple.requestAuthorization()
                        } label: {
                            Text("授权接入")
                        }
                        .buttonStyle(GlassButtonStyle(prominent: true, tint: Color(red: 0.95, green: 0.25, blue: 0.42)))
                    }
                    Button {
                        apple.openAppleMusicSearch(nil)
                    } label: {
                        Text("打开 Apple Music")
                    }
                    .buttonStyle(GlassButtonStyle())
                }
            }
            .padding(16)
            .glass()

            searchField(text: $appleQuery, placeholder: "搜索歌曲、歌手",
                        tint: Color(red: 0.95, green: 0.25, blue: 0.42)) {
                apple.search(appleQuery)
            }

            if apple.isSearching {
                ProgressView().padding(.vertical, 24)
            }

            if let msg = apple.message {
                Text(msg)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if !apple.results.isEmpty {
                VStack(spacing: 0) {
                    ForEach(apple.results) { r in
                        Button {
                            apple.openResult(r)
                        } label: {
                            HStack(spacing: 12) {
                                artwork(r.artworkURL, size: 46)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(r.title)
                                        .font(.system(size: 15, weight: .medium))
                                        .foregroundColor(.primary)
                                        .lineLimit(1)
                                    Text(r.artist)
                                        .font(.system(size: 12))
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                }
                                Spacer()
                                Image(systemName: "play.circle.fill")
                                    .font(.system(size: 22))
                                    .foregroundColor(Color(red: 0.95, green: 0.25, blue: 0.42))
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 9)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 6)
                .glass()
            }
        }
    }

    private var appleStateText: String {
        switch apple.state {
        case .authorized: return "已授权，可搜索曲库"
        case .denied: return "未授权 · 将跳转到 Apple Music"
        case .unavailable: return "系统不支持直接接入 · 使用跳转"
        case .unknown: return "未接入 · 点下方授权"
        }
    }

    // MARK: - 网易云面板

    private var neteasePanel: some View {
        VStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color(red: 0.90, green: 0.14, blue: 0.16))
                            .frame(width: 48, height: 48)
                        Image(systemName: "waveform")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundColor(.white)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("网易云音乐")
                            .font(.system(size: 17, weight: .semibold))
                        Text("跳转到官方 App 播放")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                }

                Text("网易云没有开放第三方播放接口，所以这里做的是把歌名带过去，播放和会员曲库都在官方客户端完成。")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 10) {
                    Button {
                        NeteaseService.openApp()
                    } label: {
                        Text("打开网易云")
                    }
                    .buttonStyle(GlassButtonStyle(prominent: true, tint: Color(red: 0.90, green: 0.14, blue: 0.16)))

                    Button {
                        NeteaseService.openWeb()
                    } label: {
                        Text("网页版")
                    }
                    .buttonStyle(GlassButtonStyle())
                }
            }
            .padding(16)
            .glass()

            searchField(text: $neteaseQuery, placeholder: "歌名 / 歌手",
                        tint: Color(red: 0.90, green: 0.14, blue: 0.16)) {
                NeteaseService.search(neteaseQuery)
            }

            Text("没装网易云时会自动用浏览器打开 music.163.com。")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - 通用组件

    private func searchField(text: Binding<String>, placeholder: String,
                             tint: Color, onSubmit: @escaping () -> Void) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15))
                .foregroundColor(.secondary)
            TextField(placeholder, text: text)
                .font(.system(size: 15))
                .submitLabel(.search)
                .onSubmit(onSubmit)
            if !text.wrappedValue.isEmpty {
                Button {
                    text.wrappedValue = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            Button(action: onSubmit) {
                Text("搜索")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(tint))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .glassInner(cornerRadius: 20)
    }

    private func artwork(_ url: URL?, size: CGFloat) -> some View {
        Group {
            if let url = url {
                AsyncImage(url: url) { img in
                    img.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.primary.opacity(0.08))
                }
            } else {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.primary.opacity(0.08))
                    .overlay(
                        Image(systemName: "music.note")
                            .font(.system(size: size * 0.3))
                            .foregroundColor(.secondary)
                    )
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
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
            RoundedRectangle(cornerRadius: size * 0.07, style: .continuous)
                .fill(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing))
            RoundedRectangle(cornerRadius: size * 0.07, style: .continuous)
                .fill(LinearGradient(colors: [Color.white.opacity(0.26), Color.clear],
                                     startPoint: .topLeading, endPoint: .center))
            Image(systemName: "music.note")
                .font(.system(size: size * 0.2, weight: .light))
                .foregroundColor(.white.opacity(0.92))
        }
        .frame(width: size, height: size)
        .overlay(
            RoundedRectangle(cornerRadius: size * 0.07, style: .continuous)
                .strokeBorder(Color.white.opacity(0.16), lineWidth: 1)
        )
        .shadow(color: colors[0].opacity(size > 100 ? 0.32 : 0),
                radius: size > 100 ? 26 : 0,
                y: size > 100 ? 14 : 0)
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
