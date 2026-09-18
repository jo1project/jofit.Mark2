import Foundation
import Combine

final class UserSettings: ObservableObject {
    @Published var name: String {
        didSet { UserDefaults.standard.set(name, forKey: Keys.name) }
    }
    @Published var employeeID: String {
        didSet { UserDefaults.standard.set(employeeID, forKey: Keys.employeeID) }
    }
    /// Set once the user completes the first-launch onboarding screen. Kept separate from
    /// `isComplete` so clearing a field later in Settings doesn't unexpectedly re-trigger
    /// the full-screen onboarding gate.
    @Published var hasOnboarded: Bool {
        didSet { UserDefaults.standard.set(hasOnboarded, forKey: Keys.hasOnboarded) }
    }
    /// Where reservations actually get submitted from now — see `BackendClient`.
    @Published var backendURL: String {
        didSet { UserDefaults.standard.set(backendURL, forKey: Keys.backendURL) }
    }
    /// Shared secret the backend expects as `Authorization: Bearer <token>`. Never hardcode
    /// this in source (the repo is public) — it only ever lives in UserDefaults on-device.
    @Published var backendToken: String {
        didSet { UserDefaults.standard.set(backendToken, forKey: Keys.backendToken) }
    }

    private enum Keys {
        static let name = "settings.name"
        static let employeeID = "settings.employeeID"
        static let hasOnboarded = "settings.hasOnboarded"
        static let backendURL = "settings.backendURL"
        static let backendToken = "settings.backendToken"
    }

    init() {
        name = UserDefaults.standard.string(forKey: Keys.name) ?? ""
        employeeID = UserDefaults.standard.string(forKey: Keys.employeeID) ?? ""
        hasOnboarded = UserDefaults.standard.bool(forKey: Keys.hasOnboarded)
        backendURL = UserDefaults.standard.string(forKey: Keys.backendURL) ?? "https://jofit.duckdns.org"
        backendToken = UserDefaults.standard.string(forKey: Keys.backendToken) ?? ""
    }

    var isComplete: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty &&
        !employeeID.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var isBackendConfigured: Bool {
        !backendURL.trimmingCharacters(in: .whitespaces).isEmpty &&
        !backendToken.trimmingCharacters(in: .whitespaces).isEmpty
    }
}
