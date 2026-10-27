import SwiftUI
import UniformTypeIdentifiers

struct MusicView: View {
    @ObservedObject var player = AudioPlayer.shared
    @ObservedObject var store = Store.shared

    @State private var showPicker = false
    @State private var showClearAlert = false

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                List {
                    nowPlayingSection
                    playlistSection
                }
                .listStyle(.insetGrouped)
            }
            .background(Color(UIColor.systemGroupedBackground).ignoresSafeArea())
            .navigationTitle("音乐")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showPicker = true
                    } label: {
                        Label("导入", systemImage: "plus")
                    }
                }
            }
            .sheet(isPresented: $showPicker) {
                DocumentPicker(contentTypes: [.audio], allowsMultiple: true) { urls in
                    let n = player.importFiles(urls)
                    if n > 0 && !player.isPlaying && player.tracks.count == n {
                        player.select(index: 0)
                    }
                }
            }
        }
        .navigationViewStyle(.stack)
    }

    // MARK: - 正在播放

    private var nowPlayingSection: some View {
        Section {
            VStack(spacing: 18) {
                ZStack {
                    Circle()
                        .fill(Color(UIColor.tertiarySystemFill))
                        .frame(width: 120, height: 120)
                    Image(systemName: player.isPlaying ? "waveform" : "music.note")
                        .font(.system(size: 40))
                        .foregroundColor(.accentColor)
                }
                .padding(.top, 8)

                VStack(spacing: 4) {
                    Text(player.currentTrack?.title ?? "还没有音乐")
                        .font(.headline)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                    Text(player.tracks.isEmpty ? "点右上角导入手机里的音频文件" : "第 \(player.currentIndex + 1) 首 / 共 \(player.tracks.count) 首")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                VStack(spacing: 6) {
                    Slider(value: Binding(get: { player.currentTime },
                                          set: { player.seek(to: $0) }),
                           in: 0...max(1, player.duration))
                        .disabled(player.currentTrack == nil)
                    HStack {
                        Text(AudioPlayer.formatTime(player.currentTime))
                        Spacer()
                        Text(AudioPlayer.formatTime(player.duration))
                    }
                    .font(.caption2)
                    .monospacedDigit()
                    .foregroundColor(.secondary)
                }

                HStack(spacing: 40) {
                    Button { player.previous() } label: {
                        Image(systemName: "backward.fill").font(.title2)
                    }
                    Button { player.toggle() } label: {
                        Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                            .font(.system(size: 56))
                    }
                    .disabled(player.tracks.isEmpty)
                    Button { player.next() } label: {
                        Image(systemName: "forward.fill").font(.title2)
                    }
                }
                .foregroundColor(.accentColor)
                .disabled(player.tracks.isEmpty)
                .padding(.bottom, 8)
            }
            .frame(maxWidth: .infinity)
            .listRowBackground(Color(UIColor.secondarySystemGroupedBackground))
        } footer: {
            if !player.tracks.isEmpty {
                Text("锁屏和控制中心可以暂停、切歌、拖进度。音乐文件已存进 App，重开不用重新导入。")
            }
        }
    }

    // MARK: - 播放列表

    private var playlistSection: some View {
        Section(header: Text("播放列表 · \(player.tracks.count) 首")) {
            if player.tracks.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("支持 mp3、m4a、wav 等本地音频")
                        .font(.subheadline)
                    Text("从「文件」App 里选，音乐会复制到 App 内长期保存。")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Button {
                        showPicker = true
                    } label: {
                        Label("导入音乐", systemImage: "square.and.arrow.down")
                    }
                    .padding(.top, 4)
                }
                .padding(.vertical, 8)
            } else {
                ForEach(Array(player.tracks.enumerated()), id: \.element.id) { i, t in
                    Button {
                        player.select(index: i)
                    } label: {
                        HStack {
                            Text("\(i + 1)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .frame(width: 24, alignment: .leading)
                            Text(t.title)
                                .foregroundColor(.primary)
                                .lineLimit(1)
                            Spacer()
                            if i == player.currentIndex {
                                Image(systemName: player.isPlaying ? "speaker.wave.2.fill" : "speaker.fill")
                                    .foregroundColor(.accentColor)
                                    .font(.caption)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
                .onDelete(perform: player.removeTracks)
            }

            if let err = player.errorMessage {
                Text(err)
                    .font(.caption)
                    .foregroundColor(.red)
            }
        }
    }
}
