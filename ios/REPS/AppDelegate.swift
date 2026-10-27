import UIKit
import AVFoundation

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {

    var window: UIWindow?

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {

        configureAudioSession()

        let w = UIWindow(frame: UIScreen.main.bounds)
        w.backgroundColor = UIColor(red: 13 / 255, green: 13 / 255, blue: 20 / 255, alpha: 1)
        w.rootViewController = WebViewController()
        w.makeKeyAndVisible()
        window = w

        return true
    }

    /// 息屏不断的关键：playback 类别 + Info.plist 里的 UIBackgroundModes = audio
    /// 这样锁屏后 App 不会被挂起，网页里的音乐 / 静音保活音轨 / 计时都还能跑。
    private func configureAudioSession() {
        do {
            let s = AVAudioSession.sharedInstance()
            try s.setCategory(.playback, mode: .default, options: [])
            try s.setActive(true)
        } catch {
            NSLog("[REPS] audio session error: \(error)")
        }
    }
}
