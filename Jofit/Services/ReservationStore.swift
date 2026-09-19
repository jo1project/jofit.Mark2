import Foundation
import Combine
import UserNotifications
import WidgetKit

/// The client-side view of reservations. All the actual scheduling — deciding when to submit
/// and doing it — happens on the VPS backend now (see `BackendClient`), so this store is a thin
/// sync layer: it mirrors the backend's state, caches the last-known state on disk for offline
/// display, and keeps the home screen widget's shared data up to date.
@MainActor
final class ReservationStore: ObservableObject {
    @Published private(set) var reservations: [Reservation] = []
    @Published private(set) var isSyncing = false
    @Published var lastSyncError: String?

    private let client = BackendClient()
    private let fileURL: URL

    init() {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        fileURL = dir.appendingPathComponent("reservations_cache.json")
        loadCache()
        updateWidgetData()
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    func reservation(for courseID: String) -> Reservation? {
        reservations.first { $0.course.id == courseID }
    }

    func refresh() async {
        isSyncing = true
        defer { isSyncing = false }
        do {
            reservations = try await client.listReservations()
            lastSyncError = nil
            saveCache()
        } catch {
            lastSyncError = error.localizedDescription
        }
    }

    @discardableResult
    func reserve(course: Course, name: String, employeeID: String) async -> Reservation? {
        do {
            let reservation = try await client.createReservation(course: course, name: name, employeeID: employeeID)
            upsert(reservation)
            lastSyncError = nil
            return reservation
        } catch {
            lastSyncError = error.localizedDescription
            return nil
        }
    }

    func cancel(_ reservation: Reservation) async {
        do {
            try await client.cancelReservation(id: reservation.id)
        } catch BackendError.server(404, _) {
            // Already gone, or sent in the meantime (a lost DELETE response lands here too);
            // the refresh below shows which.
        } catch {
            lastSyncError = error.localizedDescription
            return
        }
        // Confirm against the backend's list rather than trusting our own removal.
        await refresh()
        if lastSyncError == nil, reservations.contains(where: { $0.id == reservation.id }) {
            lastSyncError = "這筆預約已無法取消"
        }
    }

    func registerDeviceToken(_ token: String) async {
        try? await client.registerDeviceToken(token)
    }

    private func upsert(_ reservation: Reservation) {
        if let idx = reservations.firstIndex(where: { $0.id == reservation.id }) {
            reservations[idx] = reservation
        } else {
            reservations.append(reservation)
        }
        saveCache()
    }

    /// Writes today's submitted courses into the shared App Group container and asks WidgetKit
    /// to redraw — the widget process can't see this app's own storage directly.
    private func updateWidgetData() {
        let entries = reservations
            .filter { $0.status == .submitted }
            .map { SharedCourseEntry(date: $0.course.date, name: $0.course.name, time: $0.course.time) }
        WidgetData(submittedCourses: entries, updatedAt: Date()).save()
        WidgetCenter.shared.reloadAllTimelines()
    }

    private func loadCache() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        reservations = (try? JSONDecoder().decode([Reservation].self, from: data)) ?? []
    }

    private func saveCache() {
        updateWidgetData()
        guard let data = try? JSONEncoder().encode(reservations) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
