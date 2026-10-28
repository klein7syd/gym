import SwiftUI
import UserNotifications

@main
struct REPSApp: App {
    init() {
        RestTimer.shared.requestNotificationAuthIfNeeded()
    }

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .onAppear { Store.shared.writeNow() }
        }
    }
}

/// 底部栏用系统原生的 TabView（UIKit 的 UITabBar）：
/// 点按回弹、长按、滚动到底部再点当前页回顶、无障碍朗读、
/// 安全区处理和玻璃材质全部交给系统，新版 iOS 上自动是新外观。
struct RootTabView: View {
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject var player = PlayerPresenter.shared
    @State private var selection = 0

    var body: some View {
        ZStack {
            // 底层：常态用「页面同色」，不是黑色。
            // TabView 和它里面的页面都是按安全区布局的（系统在根视图里已经替它们让开了
            // 状态栏与底部横条）。只要这一层是黑的，任何一处没被内容盖住的安全区就会露出黑边，
            // 所以这里铺的必须是跟页面一样的底色 —— 露出来也看不出来。
            AppBackground()

            // 播放页打开时这一层换成播放页自己的底色（深灰 #212121），当卡片堆叠的底。
            // 用播放页同色而不是纯黑：万一播放页边缘有一点没铺到，露出来的也是同一个颜色。
            // 淡入用 0.25s easeInOut：和 TabView 那 0.46s 的 spring 大致同步，
            // 避免 forceDark 已经切了深色、这一层还是浅灰的那一帧硬闪。
            Color(white: 0.13)
                .opacity(player.isOpen ? 1 : 0)
                .animation(.easeInOut(duration: 0.25), value: player.isOpen)
                .allowsHitTesting(false)

            TabView(selection: $selection) {
                TrainView()
                    .tabItem {
                        Label("训练", systemImage: "figure.strengthtraining.traditional")
                    }
                    .tag(0)

                MusicView()
                    .tabItem {
                        Label("音乐", systemImage: "music.note")
                    }
                    .tag(1)

                GrowthView()
                    .tabItem {
                        Label("成长", systemImage: "chart.xyaxis.line")
                    }
                    .tag(2)

                ProfileView()
                    .tabItem {
                        Label("我的", systemImage: "person.crop.circle")
                    }
                    .tag(3)
            }
            .tint(.accentColor)
            // ★ 4.9 修「一进 App 上下两条大黑边」的真正原因：
            // 以前这里无条件套着 `.clipShape(RoundedRectangle(...))`。TabView 是按安全区
            // 布局的，一旦套上裁剪，即使圆角是 0，也会沿「安全区矩形」硬切一刀 ——
            // 页面延伸到状态栏 / 底部横条上的那部分（导航栏底、标签栏底）被切掉，
            // 露出的就是底下那层，于是上下各留一条边。
            // 现在只在播放页打开（卡片堆叠、需要圆角）时才裁，静止状态完全不裁。
            .modifier(CardClip(active: player.isOpen, radius: 34 - 20 * player.pull))
            // 跟着下拉进度实时变化：拉得越多，下层越接近原始大小、越亮 —— 就是「渐渐回到上一级」
            .scaleEffect(player.isOpen ? 0.94 + 0.06 * player.pull : 1, anchor: .center)
            .overlay {
                // 压暗遮罩抽成了独立小视图，见文件底部的 DimOverlay：
                // pull 每帧都在变，遮罩只依赖 pull，没必要让根视图重新构造它。
                DimOverlay()
            }
            .allowsHitTesting(!player.isOpen)
            .animation(.spring(response: 0.46, dampingFraction: 0.90), value: player.isOpen)

            if player.isOpen {
                NowPlayingView()
                    .zIndex(10)
                    // 移出时只位移、不淡出：淡出会让播放页在半透明的那几帧里
                    // 透出底下那层（深浅色交接处就会闪一下）。滑出时点一下就能盖住。
                    .transition(.asymmetric(
                        insertion: .move(edge: .bottom).combined(with: .opacity),
                        removal: .move(edge: .bottom)
                    ))
            }
        }
        // 状态栏文字转白：只在播放页已经盖满全屏之后才切（切早了会整块闪）
        .preferredColorScheme(player.forceDark ? ColorScheme.dark : nil)
        .onChange(of: scenePhase) { phase in
            if phase == .background {
                Store.shared.writeNow()
            }
        }
    }
}

// `CardClip`（只在播放页打开时才给 TabView 裁圆角）定义在 Theme.swift，
// 播放页 NowPlayingView 用的是同一个修饰符。

// MARK: - 压暗遮罩
//
// 单独抽成一个只观察 player 的小视图：`pull` 是 @Published，拖动时每帧都在变，
// 遮罩只跟 pull 有关（0.42 → 0），没必要每次都让根视图重新构造这一段。
// 数值完全不改：0.42 * (1 - pull)。
//
// 注意它仍然挂在 TabView 的 `.overlay` 上；打开 / 关闭播放页时这层压暗的渐变
// 用与外层同一条 spring（0.46 / 0.90），所以视觉和抽取之前完全一样。
private struct DimOverlay: View {
    @ObservedObject var player = PlayerPresenter.shared

    var body: some View {
        Color.black
            .opacity(player.isOpen ? 0.42 * (1 - Double(player.pull)) : 0)
            // 和外层那圈完全同一条 spring（0.46 / 0.90），只是在这里再写一遍：
            // 这层现在是通过自己的订阅收到 isOpen 变化的，不保证一定落在
            // RootTabView 那圈 `.animation(…, value: player.isOpen)` 的事务里，
            // 少了它就可能变成硬切。参数一模一样，视觉上没有任何差别。
            // 注意 value 只看 isOpen —— 拖动时 opacity 跟 pull 逐帧变化，不能被动画带。
            .animation(.spring(response: 0.46, dampingFraction: 0.90), value: player.isOpen)
            .ignoresSafeArea()
            .allowsHitTesting(false)
    }
}
