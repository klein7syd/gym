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
            // 底层只有一层：**页面同色 + 铺满安全区**。
            //
            // 4.9.6 之前这里还叠过一层 `Color(white: 0.13)`（播放页深灰）当卡片堆叠的底，
            // 但那层没有 ignoresSafeArea：缩小后的页面四周就露出一圈深灰，
            // 上下安全区又因为它是按安全区布局的而露出浅灰 —— 灰带 + 黑圈，
            // 和状态栏 / 电池区完全割裂，下拉时特别明显。现在整层删掉，
            // AppBackground() 自己带 ignoresSafeArea，露出来的永远是页面同色，四周接得住。
            AppBackground()

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
            .modifier(CardClip(active: player.isOpen, radius: 22 - 12 * player.pull))
            // 跟着下拉进度实时变化：拉得越多，下层越接近原始大小、越亮 —— 就是「渐渐回到上一级」
            // 缩放幅度从 6% 收到 3%（0.97 + 0.03 * pull）：原来的 0.94 在拖到一半时
            // 把整页压得太小，内容挤成一坨。现在只是「轻微退后一级」，文字不再明显变形。
            .scaleEffect(player.isOpen ? 0.97 + 0.03 * player.pull : 1, anchor: .center)
            .overlay {
                // 压暗遮罩抽成了独立小视图，见文件底部的 DimOverlay：
                // pull 每帧都在变，遮罩只依赖 pull，没必要让根视图重新构造它。
                DimOverlay()
            }
            // 播放页盖在上面时，底下这层不接受点击：否则键盘弹着的时候，
            // 下拉露出来的搜索框还能被戳到。用 allowsHitTesting + accessibilityHidden，
            // 不额外加 .disabled —— .disabled 会把底下所有按钮画成灰态，
            // 而下拉过程中这层是看得见的，按钮会一个个变灰（视觉副作用明显）。
            .allowsHitTesting(!player.isOpen)
            .accessibilityHidden(player.isOpen)
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
// 遮罩只跟 pull 有关（0.28 → 0），没必要每次都让根视图重新构造这一段。
// 压暗峰值 4.9.6 由 0.42 收到 0.28：配合缩放从 6% 收到 3%，下拉时只是「略微退后」，
// 不再像关灯一样整屏变黑。
//
// 注意它仍然挂在 TabView 的 `.overlay` 上；打开 / 关闭播放页时这层压暗的渐变
// 用与外层同一条 spring（0.46 / 0.90），所以视觉和抽取之前完全一样。
private struct DimOverlay: View {
    @ObservedObject var player = PlayerPresenter.shared

    var body: some View {
        Color.black
            .opacity(player.isOpen ? 0.28 * (1 - Double(player.pull)) : 0)
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
