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
                .onAppear {
                    Store.shared.writeNow()
                }
        }
    }
}

struct RootTabView: View {
    @State private var selection = 0
    @Environment(\.scenePhase) private var scenePhase

    private let items: [LiquidTabItem] = [
        LiquidTabItem(title: "训练", icon: "figure.strengthtraining.traditional",
                      activeIcon: "figure.strengthtraining.traditional"),
        LiquidTabItem(title: "音乐", icon: "music.note", activeIcon: "music.note"),
        LiquidTabItem(title: "成长", icon: "chart.xyaxis.line", activeIcon: "chart.xyaxis.line"),
        LiquidTabItem(title: "我的", icon: "person.crop.circle", activeIcon: "person.crop.circle.fill")
    ]

    var body: some View {
        ZStack(alignment: .bottom) {
            AppBackground()

            // 四个页面常驻，切换不丢状态（训练做到一半去听歌，回来组还在）
            ZStack {
                TrainView()
                    .opacity(selection == 0 ? 1 : 0)
                    .allowsHitTesting(selection == 0)
                    .zIndex(selection == 0 ? 1 : 0)

                MusicView()
                    .opacity(selection == 1 ? 1 : 0)
                    .allowsHitTesting(selection == 1)
                    .zIndex(selection == 1 ? 1 : 0)

                GrowthView()
                    .opacity(selection == 2 ? 1 : 0)
                    .allowsHitTesting(selection == 2)
                    .zIndex(selection == 2 ? 1 : 0)

                ProfileView()
                    .opacity(selection == 3 ? 1 : 0)
                    .allowsHitTesting(selection == 3)
                    .zIndex(selection == 3 ? 1 : 0)
            }

            LiquidTabBar(selection: $selection, items: items)
        }
        .tint(.accentColor)
        .onChange(of: scenePhase) { phase in
            if phase == .background {
                Store.shared.writeNow()
            }
        }
    }
}
