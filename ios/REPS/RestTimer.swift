import Foundation
import Combine
import AVFoundation
import AudioToolbox
import UserNotifications
import UIKit

/// 组间休息计时器。
/// 关键点：用「结束时刻的绝对时间戳」算剩余，不用累减计数 —— 这样 App 被切到后台、
/// 甚至 JS/RunLoop 被挂起，回来后剩余时间依然准确。后台到点由本地通知负责提醒。
final class RestTimer: NSObject, ObservableObject {
    static let shared = RestTimer()

    @Published private(set) var endDate: Date?
    @Published private(set) var total: Int = 120
    @Published private(set) var tick = Date()

    private var timer: Timer?
    private let notificationID = "reps.rest.finished"
    private var didRequestAuth = false

    var isRunning: Bool { endDate != nil }

    var remaining: Int {
        guard let end = endDate else { return 0 }
        return max(0, Int(ceil(end.timeIntervalSince(tick))))
    }

    var progress: Double {
        guard total > 0 else { return 0 }
        return min(1, max(0, 1 - Double(remaining) / Double(total)))
    }

    var remainingText: String {
        let r = remaining
        return String(format: "%d:%02d", r / 60, r % 60)
    }

    private override init() {
        super.init()
        NotificationCenter.default.addObserver(self, selector: #selector(enteredForeground),
                                               name: UIApplication.willEnterForegroundNotification, object: nil)
    }

    func requestNotificationAuthIfNeeded() {
        guard !didRequestAuth else { return }
        didRequestAuth = true
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    // MARK: - 控制

    func start(seconds: Int) {
        requestNotificationAuthIfNeeded()
        total = max(5, seconds)
        endDate = Date().addingTimeInterval(TimeInterval(total))
        tick = Date()
        startTicking()
        scheduleNotification(after: TimeInterval(total))
        UIApplication.shared.isIdleTimerDisabled = true
    }

    func add(seconds: Int) {
        guard let end = endDate else { return }
        endDate = end.addingTimeInterval(TimeInterval(seconds))
        total = max(total, remaining)
        tick = Date()
        scheduleNotification(after: endDate?.timeIntervalSinceNow ?? 0)
    }

    func skip() {
        cancelNotification()
        endDate = nil
        stopTicking()
        UIApplication.shared.isIdleTimerDisabled = false
    }

    private func finish() {
        // 先把排队中的通知撤掉：前台 tick 可能比通知触发早几十毫秒判定归零，
        // 若不取消，稍后 App 一进后台仍会弹一条「休息结束」，等于重复提醒。
        cancelNotification()
        endDate = nil
        stopTicking()
        UIApplication.shared.isIdleTimerDisabled = false
        // 前台提示：铃声 + 震动。后台提示走本地通知。
        AudioServicesPlaySystemSound(1005)
        AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
    }

    // MARK: - 内部

    private func startTicking() {
        stopTicking()
        let t = Timer(timeInterval: 0.2, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            self.tick = Date()
            if self.remaining <= 0 { self.finish() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func stopTicking() {
        timer?.invalidate()
        timer = nil
    }

    @objc private func enteredForeground() {
        tick = Date()
        if isRunning && remaining <= 0 { finish() }
    }

    private func scheduleNotification(after interval: TimeInterval) {
        cancelNotification()
        guard interval > 1 else { return }
        let content = UNMutableNotificationContent()
        content.title = "休息结束"
        content.body = "该上下一组了。"
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        let req = UNNotificationRequest(identifier: notificationID, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(req, withCompletionHandler: nil)
    }

    private func cancelNotification() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [notificationID])
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [notificationID])
    }
}
