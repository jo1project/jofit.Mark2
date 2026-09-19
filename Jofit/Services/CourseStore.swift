import Foundation
import Combine

/// Loads the weekly recurring course schedule at launch and on pull-to-refresh — from the
/// backend once an admin has edited it there, else from `courses.json` in the repo (raw GitHub
/// URL) — expanding each recurring slot into concrete instances for
/// the next 4 weeks. Caches the raw templates on disk and falls back to a small bundled default
/// list if no fetch has ever succeeded.
@MainActor
final class CourseStore: ObservableObject {
    static let weeksAhead = 4

    @Published private(set) var courses: [Course] = []
    @Published private(set) var lastUpdated: Date?
    @Published private(set) var isRefreshing = false
    @Published private(set) var lastError: String?

    private static let remoteURL = URL(
        string: "https://raw.githubusercontent.com/jo1project/jofit.Mark2/main/courses.json"
    )!
    private let cacheURL: URL
    private let client = BackendClient()
    private(set) var templates: [CourseTemplate]

    init() {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        cacheURL = dir.appendingPathComponent("courses_cache.json")
        templates = Self.loadCache(from: cacheURL) ?? CourseTemplates.fallback
        courses = Self.resolve(templates)
    }

    func refresh() async {
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            apply(try await fetchTemplates())
            lastError = nil
        } catch {
            // Re-resolve the existing templates in case the day rolled over since launch.
            courses = Self.resolve(templates)
            lastError = "課表更新失敗，目前顯示上次的快取資料（\(error.localizedDescription)）"
        }
    }

    /// Admin only: saves the list on the backend (everyone's app picks it up on their next
    /// refresh), then adopts it locally. Throws on a wrong PIN or network error.
    func save(_ new: [CourseTemplate], pin: String) async throws {
        try await client.saveCourses(new, pin: pin)
        apply(new)
    }

    /// The backend's list is the source of truth once an admin has saved one; until then it's
    /// empty and the repo's `courses.json` is used. A backend error deliberately doesn't fall
    /// through to the repo list — that could be older than the shared one we have cached.
    private func fetchTemplates() async throws -> [CourseTemplate] {
        let shared = try await client.listCourses()
        if !shared.isEmpty { return shared }

        var request = URLRequest(url: Self.remoteURL)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        let decoded = try JSONDecoder().decode([CourseTemplate].self, from: data)
        guard !decoded.isEmpty else { throw URLError(.zeroByteResource) }
        return decoded
    }

    // `templates` is set before `courses` on purpose: EditCoursesView reads it when `$courses` fires.
    private func apply(_ new: [CourseTemplate]) {
        templates = new
        courses = Self.resolve(new)
        lastUpdated = Date()
        Self.saveCache(new, to: cacheURL)
    }

    private static func resolve(_ templates: [CourseTemplate]) -> [Course] {
        templates
            .flatMap { $0.resolvedCourses(weeksAhead: weeksAhead) }
            // id as a final tiebreaker: multiple classrooms can share the same date+time, and
            // ties broken only by input order are fragile — see CoursesView.groupedByWeekday.
            .sorted { ($0.date, $0.time, $0.id) < ($1.date, $1.time, $1.id) }
    }

    private static func loadCache(from url: URL) -> [CourseTemplate]? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode([CourseTemplate].self, from: data)
    }

    private static func saveCache(_ templates: [CourseTemplate], to url: URL) {
        guard let data = try? JSONEncoder().encode(templates) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
