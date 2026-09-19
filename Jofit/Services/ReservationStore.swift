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
    /// True once the admin PIN has been accepted this session; from then on `reservations` holds
    /// everyone's (the backend otherwise only returns the caller's own).
    @Published private(set) var isAdminUnlocked = false

    private let client = BackendClient()
    private let fileURL: URL
    private var adminPIN: String?
    private var deviceToken: String?
    private var registeredDevice: String?

    /// Every backend call is scoped to this: the backend has no login, it trusts the caller to
    /// name themselves and only hands back / lets them cancel that person's reservations.
    private var employeeID: String {
        (UserDefaults.standard.string(forKey: UserSettings.employeeIDKey) ?? "").trimmingCharacters(in: .whitespaces)
    }

    init() {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        fileURL = dir.appendingPathComponent("reservations_cache.json")
        loadCache()
        updateWidgetData()
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    /// One reservation per person per class: other students' reservations for the same class
    /// don't count as this user's.
    func reservation(for courseID: String, employeeID: String) -> Reservation? {
        reservations.first { $0.course.id == courseID && $0.isBooked(by: employeeID) }
    }

    func refresh() async {
        await syncDeviceToken()
        guard adminPIN != nil || !employeeID.isEmpty else { return }
        isSyncing = true
        defer { isSyncing = false }
        do {
            reservations = try await client.listReservations(employeeID: employeeID, pin: adminPIN)
            lastSyncError = nil
            saveCache()
        } catch {
            if case BackendError.server(403, _) = error { lockAdmin() }
            lastSyncError = error.localizedDescription
        }
    }

    /// Throws (wrong PIN, network) so the caller can show it. On success the PIN is kept in
    /// memory only, so refreshes keep returning everyone's reservations until the app quits.
    func unlockAdmin(pin: String) async throws {
        reservations = try await client.listReservations(employeeID: employeeID, pin: pin)
        adminPIN = pin
        isAdminUnlocked = true
        lastSyncError = nil
        saveCache()
    }

    private func lockAdmin() {
        adminPIN = nil
        isAdminUnlocked = false
    }

    @discardableResult
    func reserve(course: Course, name: String, employeeID: String) async -> Reservation? {
        await syncDeviceToken()
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
            try await client.cancelReservation(id: reservation.id, employeeID: employeeID, pin: adminPIN)
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

    /// Admin bulk cancel of pending reservations; throws (wrong PIN, network) so the caller can
    /// show it. Returns how many were really cancelled — may be fewer than asked if some fired
    /// in the meantime.
    func cancelPending(_ targets: [Reservation], pin: String) async throws -> Int {
        let cancelled = try await client.cancelReservations(ids: targets.map(\.id), pin: pin)
        await refresh()
        return cancelled
    }

    func registerDeviceToken(_ token: String) async {
        deviceToken = token
        await syncDeviceToken()
    }

    /// The backend sends a push only to the device registered under the reservation's employee
    /// ID, so the token has to be (re)registered once both it and the ID are known, and again if
    /// the ID changes. Called on every refresh/reserve, which covers both without observing.
    private func syncDeviceToken() async {
        let id = employeeID
        guard let token = deviceToken, !id.isEmpty, registeredDevice != "\(token)|\(id)" else { return }
        do {
            try await client.registerDeviceToken(token, employeeID: id)
            registeredDevice = "\(token)|\(id)"
        } catch {}
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
        // The list holds every user's reservations; the widget must only show this user's.
        let mine = UserDefaults.standard.string(forKey: UserSettings.employeeIDKey) ?? ""
        let entries = reservations
            .filter { $0.status == .submitted && $0.isBooked(by: mine) }
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
