import Foundation
import Combine

final class UserSettings: ObservableObject {
    @Published var name: String {
        didSet { UserDefaults.standard.set(name, forKey: Keys.name) }
    }
    @Published var employeeID: String {
        didSet { UserDefaults.standard.set(employeeID, forKey: Keys.employeeID) }
    }

    private enum Keys {
        static let name = "settings.name"
        static let employeeID = "settings.employeeID"
    }

    init() {
        name = UserDefaults.standard.string(forKey: Keys.name) ?? ""
        employeeID = UserDefaults.standard.string(forKey: Keys.employeeID) ?? ""
    }

    var isComplete: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty &&
        !employeeID.trimmingCharacters(in: .whitespaces).isEmpty
    }
}
