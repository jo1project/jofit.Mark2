import Foundation
import Combine
import WidgetKit

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

    /// Persisted by `AppTheme.current` (App Group defaults, shared with the widget).
    @Published var theme: AppTheme {
        didSet {
            AppTheme.current = theme
            Theme.applyAppearance()
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    /// Also read by `ReservationStore` to keep the widget to the current user's own reservations.
    static let employeeIDKey = "settings.employeeID"

    private enum Keys {
        static let name = "settings.name"
        static let employeeID = UserSettings.employeeIDKey
        static let hasOnboarded = "settings.hasOnboarded"
    }

    init() {
        name = UserDefaults.standard.string(forKey: Keys.name) ?? ""
        employeeID = UserDefaults.standard.string(forKey: Keys.employeeID) ?? ""
        hasOnboarded = UserDefaults.standard.bool(forKey: Keys.hasOnboarded)
        theme = AppTheme.current
    }

    /// Soft gate only (the name is just typed into Settings): it decides which screens show. The
    /// real protection is the admin PIN the backend checks on every admin action.
    var isAdmin: Bool { name.trimmingCharacters(in: .whitespaces) == "林晏瑜" }

    var isComplete: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty &&
        !employeeID.trimmingCharacters(in: .whitespaces).isEmpty
    }
}
