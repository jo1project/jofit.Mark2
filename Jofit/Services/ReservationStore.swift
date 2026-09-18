import Foundation
import Combine
import UserNotifications

/// Owns the full lifecycle of a reservation: creating it, deciding whether it should submit
/// immediately or wait, persisting it, and actually firing the form submission when its time
/// comes. See the note on `processDue` for why "when its time comes" depends on the app being
/// opened around that time — iOS doesn't run app code on a schedule while backgrounded, let
/// alone after the user force-quits the app.
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
        var updated = reservation
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
        return updated
    }

    private func apply(_ reservation: Reservation) {
        guard let idx = reservations.firstIndex(where: { $0.id == reservation.id }) else { return }
        reservations[idx] = reservation
        save()
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

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        reservations = (try? JSONDecoder().decode([Reservation].self, from: data)) ?? []
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(reservations) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
