import Foundation
import Combine

/// Loads the course list from `courses.json` in the repo (raw.githubusercontent.com), so the
/// schedule can be updated by editing that file and pushing to `main` — no app rebuild needed.
/// Falls back to the last successfully fetched copy (cached on disk), and to a small bundled
/// default list if there's no cache yet (first launch, offline).
@MainActor
final class CourseStore: ObservableObject {
    @Published private(set) var courses: [Course]
    @Published private(set) var lastUpdated: Date?
    @Published private(set) var isRefreshing = false
    @Published private(set) var lastError: String?

    private static let remoteURL = URL(
        string: "https://raw.githubusercontent.com/jo1project/jofit.Mark2/main/courses.json"
    )!
    private let cacheURL: URL

    init() {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        cacheURL = dir.appendingPathComponent("courses_cache.json")
        courses = Self.loadCache(from: cacheURL) ?? Courses.fallback
    }

    func refresh() async {
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            var request = URLRequest(url: Self.remoteURL)
            request.cachePolicy = .reloadIgnoringLocalCacheData
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                throw URLError(.badServerResponse)
            }
            let decoded = try JSONDecoder().decode([Course].self, from: data)
            guard !decoded.isEmpty else { throw URLError(.zeroByteResource) }

            courses = decoded
            lastUpdated = Date()
            lastError = nil
            Self.saveCache(decoded, to: cacheURL)
        } catch {
            lastError = "課表更新失敗，目前顯示上次的快取資料（\(error.localizedDescription)）"
        }
    }

    private static func loadCache(from url: URL) -> [Course]? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode([Course].self, from: data)
    }

    private static func saveCache(_ courses: [Course], to url: URL) {
        guard let data = try? JSONEncoder().encode(courses) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
