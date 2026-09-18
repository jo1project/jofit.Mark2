import Foundation
import Combine
import UserNotifications
import WidgetKit

/// Owns the full lifecycle of a reservation: creating it, deciding whether it should submit
/// immediately or wait, persisting it, and actually firing the form submission when its time
/// comes. See the note on `processDue` for why "when its time comes" depends on the app being
/// opened around that time — iOS doesn't run app code on a schedule while backgrounded, let
/// alone after the user force-quits the app.
///
/// Duplicate-submission safety: each reservation is only ever submitted once. `reserve` is
/// idempotent per course (tapping an already-reserved course is a no-op), and the moment a
/// submit actually starts, the reservation flips to `.submitting` *before* the network await —
/// so a second `processDue` sweep that runs while the first request is still in flight (e.g.
/// the 1-second foreground timer ticking again before a slow request returns) will not pick
/// the same reservation up again, because `processDue` only ever selects `.pending` ones. If
/// the app is killed mid-request, the reservation is stuck in `.submitting` with no way to know
/// whether the POST actually landed — on next launch that's treated as `.failed` with an
/// explicit "status unknown" message rather than silently retried, since retrying an ambiguous
/// outcome risks a real duplicate booking (Google Forms has no de-duplication of its own).
@MainActor
final class ReservationStore: ObservableObject {
    @Published private(set) var reservations: [Reservation] = []

    private let service = FormSubmissionService()
    private let fileURL: URL

    init() {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        fileURL = dir.appendingPathComponent("reservations.json")
        load()
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func reservation(for courseID: String) -> Reservation? {
        reservations.first { $0.course.id == courseID }
    }

    @discardableResult
    func reserve(course: Course, name: String, employeeID: String) async -> Reservation {
        if let existing = reservation(for: course.id) {
            return existing
        }

        let fireDate = Reservation.computeFireDate(for: course)
        var reservation = Reservation(
            id: UUID(), course: course, createdAt: Date(), fireDate: fireDate,
            status: .pending, submittedAt: nil, httpStatus: nil, lastError: nil
        )
        reservations.append(reservation)
        save()

        if fireDate <= Date() {
            reservation = await submit(reservation, name: name, employeeID: employeeID)
        } else {
            scheduleReminderNotification(for: reservation)
        }
        return reservation
    }

    func cancel(_ reservation: Reservation) {
        reservations.removeAll { $0.id == reservation.id }
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [reservation.id.uuidString])
        save()
        updateWidgetData()
    }

    /// Submits every pending reservation whose fire time has arrived. This is what actually
    /// makes scheduled reservations happen — call it whenever the app becomes active (launch,
    /// returning from background, or the user tapping a reminder notification), plus
    /// periodically while the app stays open in the foreground.
    func processDue(name: String, employeeID: String) async {
        let due = reservations.filter { $0.status == .pending && $0.fireDate <= Date() }
        for reservation in due {
            _ = await submit(reservation, name: name, employeeID: employeeID)
        }
    }

    private func submit(_ reservation: Reservation, name: String, employeeID: String) async -> Reservation {
        var marking = reservation
        marking.status = .submitting
        apply(marking)

        var updated = marking
        do {
            let status = try await service.submit(name: name, employeeID: employeeID, courseText: reservation.course.submissionText)
            let ok = (200...299).contains(status)
            updated.status = ok ? .submitted : .failed
            updated.httpStatus = status
            updated.submittedAt = Date()
            updated.lastError = ok ? nil : "表單回應狀態碼 \(status)"
        } catch {
            updated.status = .failed
            updated.lastError = error.localizedDescription
        }
        apply(updated)
        notifyResult(updated)
        return updated
    }

    private func notifyResult(_ reservation: Reservation) {
        let content = UNMutableNotificationContent()
        switch reservation.status {
        case .submitted:
            content.title = "報名已送出"
            content.body = "\(reservation.course.submissionText) 已送出"
        case .failed:
            content.title = "報名送出失敗"
            content.body = "\(reservation.course.submissionText)：\(reservation.lastError ?? "請打開 App 查看")"
        case .pending, .submitting:
            return
        }
        content.sound = .default
        let request = UNNotificationRequest(identifier: "\(reservation.id.uuidString)_result", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    private func apply(_ reservation: Reservation) {
        guard let idx = reservations.firstIndex(where: { $0.id == reservation.id }) else { return }
        reservations[idx] = reservation
        save()
        updateWidgetData()
    }

    private func scheduleReminderNotification(for reservation: Reservation) {
        let content = UNMutableNotificationContent()
        content.title = "可以報名了"
        content.body = "\(reservation.course.submissionText) 開放預約囉，點這則通知打開 App 完成送出"
        content.sound = .default

        let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: reservation.fireDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        let request = UNNotificationRequest(identifier: reservation.id.uuidString, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }

    /// Writes the currently-submitted reservations into the shared App Group container and
    /// asks WidgetKit to redraw — the widget process can't see this app's own storage directly.
    private func updateWidgetData() {
        let entries = reservations
            .filter { $0.status == .submitted }
            .map { SharedCourseEntry(date: $0.course.date, name: $0.course.name, time: $0.course.time) }
        WidgetData(submittedCourses: entries, updatedAt: Date()).save()
        WidgetCenter.shared.reloadAllTimelines()
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        var loaded = (try? JSONDecoder().decode([Reservation].self, from: data)) ?? []

        var recovered = false
        for index in loaded.indices where loaded[index].status == .submitting {
            loaded[index].status = .failed
            loaded[index].lastError = "上次送出時 App 被中止，無法確認是否已成功報名，請手動確認，避免重複送出"
            recovered = true
        }

        reservations = loaded
        if recovered {
            save()
        }
        updateWidgetData()
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(reservations) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
