import SwiftUI
import UIKit
import MediaPlayer

// MARK: - 专辑封面
//
// 以前只有全屏播放页有封面，其他位置（迷你播放条、正在播放卡片、播放列表）
// 全是默认图标 —— 因为 PlayItem 的 artworkURL 是 nil（搜索结果来自资料库，
// 没有网络图地址），而那些位置只认 artworkURL。
//
// 现在统一走这里：按 persistentID 从 MPMediaItem 取真实封面，带内存缓存。
// 关键是**必须后台取** —— MPMediaItem.artwork?.image(at:) 是同步调用，
// 600x600 解码要几十毫秒，在主线程连取几次就是明显卡顿（点播放卡一下的主因之一）。

final class ArtworkStore: ObservableObject {
    static let shared = ArtworkStore()

    private var cache: [MPMediaEntityPersistentID: UIImage] = [:]
    private var inFlight = Set<MPMediaEntityPersistentID>()
    private let queue = DispatchQueue(label: "reps.artwork", qos: .userInitiated,
                                      attributes: .concurrent)
    /// 每次有新图进来就 +1，界面靠它触发重画（比发 objectWillChange 更省）
    @Published private(set) var revision = 0

    private init() {}

    func cached(_ id: MPMediaEntityPersistentID) -> UIImage? {
        cache[id]
    }

    /// 命中缓存直接返回；没命中就排进后台队列，取到后 revision+1 让界面自动刷新。
    @discardableResult
    func request(_ id: MPMediaEntityPersistentID, side: CGFloat = 600) -> UIImage? {
        if let img = cache[id] { return img }
        guard !inFlight.contains(id) else { return nil }
        guard let item = AppleMusicService.shared.item(for: id) else { return nil }

        inFlight.insert(id)
        queue.async { [weak self] in
            let img = item.artwork?.image(at: CGSize(width: side, height: side))
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.inFlight.remove(id)
                guard let img = img else { return }
                self.cache[id] = img
                self.revision &+= 1
            }
        }
        return nil
    }

    /// 预热：只排前若干张，避免一次把几十个解码任务塞进并发队列。
    func prefetch(_ items: [MPMediaItem], side: CGFloat = 240, limit: Int = 8) {
        for it in items.prefix(limit) {
            if cache[it.persistentID] == nil {
                _ = request(it.persistentID, side: side)
            }
        }
    }
}

// MARK: - 通用封面视图
//
// 一个 view 覆盖所有位置：资料库曲目（persistentID）取真实封面，
// 本地导入的音乐没有内嵌图就落到纯色占位。
// 圆角固定按尺寸比例走，大小位置都跟 Apple Music 一致。

struct TrackArt: View {
    var title: String
    var mediaID: MPMediaEntityPersistentID?
    var size: CGFloat
    var corner: CGFloat?

    @ObservedObject private var store = ArtworkStore.shared

    init(title: String,
         mediaID: MPMediaEntityPersistentID? = nil,
         size: CGFloat,
         corner: CGFloat? = nil) {
        self.title = title
        self.mediaID = mediaID
        self.size = size
        self.corner = corner
    }

    var body: some View {
        ZStack {
            AlbumArt(title: title, size: size)
            if let img = image {
                Image(uiImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: corner ?? max(4, size * 0.08),
                                    style: .continuous))
        .onAppear(perform: load)
        .onChange(of: mediaID) { _ in load() }
    }

    private var image: UIImage? {
        guard let id = mediaID else { return nil }
        return store.cached(id)
    }

    private func load() {
        guard let id = mediaID else { return }
        _ = store.request(id, side: size * 3)
    }
}
