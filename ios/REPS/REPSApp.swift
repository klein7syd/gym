import SwiftUI
import UserNotifications

@main
struct REPSApp: App {
    init() {
        // 让 Tab 栏和列表保持原生浅色/深色自适应，不做强制覆盖。
        RestTimer.shared.requestNotificationAuthIfNeeded()
    }

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .onAppear {
                    // 切到后台时把计时状态写盘，避免被系统杀掉后丢失进度。
                    Store.shared.writeNow()
                }
        }
    }
}

struct RootTabView: View {
    @State private var selection = 0
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
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
                    Label("成长", systemImage: "chart.line.uptrend.xyaxis")
                }
                .tag(2)

            ProfileView()
                .tabItem {
                    Label("我的", systemImage: "person.crop.circle")
                }
                .tag(3)
        }
        .tint(.accentColor)
        .onChange(of: scenePhase) { phase in
            if phase == .background {
                Store.shared.writeNow()
            }
        }
    }
}
