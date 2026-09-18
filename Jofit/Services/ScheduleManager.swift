import Foundation
import UserNotifications
import Combine

/// Fires a submission at a precise wall-clock time. iOS suspends timers once the app is
/// backgrounded, so exact-time firing is only reliable while the app is open in the
/// foreground — there's no App Store-safe way to guarantee silent background execution at
/// an exact second. To compensate, a local notification nudges the user to reopen the app
/// shortly before the target time, and the countdown re-syncs to the real clock (rather
/// than counting missed ticks) so a late resume still fires immediately instead of drifting.
@MainActor
final class ScheduleManager: ObservableObject {
    struct ScheduledJob: Identifiable {
        let id = UUID()
        let course: Course
        let fireDate: Date
    }

    @Published var pendingJob: ScheduledJob?
    @Published var countdownText: String = ""
    @Published var lastResult: SubmissionRecord?

    private var timer: Timer?
    private var onFire: ((Course) -> Void)?
    private static let reminderIdentifier = "jofit.reminder"

    func setFireHandler(_ handler: @escaping (Course) -> Void) {
        onFire = handler
    }

    func schedule(course: Course, fireDate: Date, reminderLeadTime: TimeInterval = 120) {
        cancel()
        pendingJob = ScheduledJob(course: course, fireDate: fireDate)
        requestNotificationPermission()
        scheduleReminderNotification(course: course, fireDate: fireDate, leadTime: reminderLeadTime)
        startTimer(fireDate: fireDate)
    }

    func cancel() {
        timer?.invalidate()
        timer = nil
        pendingJob = nil
        countdownText = ""
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [Self.reminderIdentifier])
    }

    private func startTimer(fireDate: Date) {
        let timer = Timer(timeInterval: 0.2, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tick(fireDate: fireDate)
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func tick(fireDate: Date) {
        let remaining = fireDate.timeIntervalSinceNow
        if remaining <= 0 {
            let course = pendingJob?.course
            timer?.invalidate()
            timer = nil
            countdownText = "送出中…"
            if let course {
                onFire?(course)
            }
            return
        }
        let minutes = Int(remaining) / 60
        let seconds = Int(remaining) % 60
        let tenths = Int((remaining - floor(remaining)) * 10)
        countdownText = String(format: "%02d:%02d.%d", minutes, seconds, tenths)
    }

    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private func scheduleReminderNotification(course: Course, fireDate: Date, leadTime: TimeInterval) {
        let triggerDate = fireDate.addingTimeInterval(-leadTime)
        guard triggerDate > Date() else { return }

        let content = UNMutableNotificationContent()
        content.title = "即將自動送出報名"
        content.body = "\(course.submissionText) 即將送出，請打開 App 確保準時完成"
        content.sound = .default

        let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: triggerDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        let request = UNNotificationRequest(identifier: Self.reminderIdentifier, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }
}
