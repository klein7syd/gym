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
            // 播放页推上来时，底下的菜单缩小、压暗，露出这层底（iOS 卡片堆叠的观感）
            Color.black.ignoresSafeArea()

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
            // 跟着下拉进度实时变化：拉得越多，下层越接近原始大小、越亮 —— 就是「渐渐回到上一级」
            .scaleEffect(player.isOpen ? 0.94 + 0.06 * player.pull : 1, anchor: .center)
            .clipShape(RoundedRectangle(cornerRadius: player.isOpen ? 34 - 20 * player.pull : 0,
                                        style: .continuous))
            .overlay {
                Color.black
                    .opacity(player.isOpen ? 0.42 * (1 - Double(player.pull)) : 0)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }
            .allowsHitTesting(!player.isOpen)
            .animation(.spring(response: 0.46, dampingFraction: 0.90), value: player.isOpen)

            if player.isOpen {
                NowPlayingView()
                    .zIndex(10)
                    .transition(.asymmetric(
                        insertion: .move(edge: .bottom).combined(with: .opacity),
                        removal: .move(edge: .bottom).combined(with: .opacity)
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
