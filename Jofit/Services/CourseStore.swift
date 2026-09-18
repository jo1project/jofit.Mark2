import Foundation
import Combine

/// Loads the weekly recurring course schedule from `courses.json` in the repo (raw
/// GitHub URL) at launch and on pull-to-refresh, resolving each recurring slot to the one
/// concrete date currently inside the form's booking window. Caches the raw templates on disk
/// and falls back to a small bundled default list if no fetch has ever succeeded.
@MainActor
final class CourseStore: ObservableObject {
    @Published private(set) var courses: [Course] = []
    @Published private(set) var lastUpdated: Date?
    @Published private(set) var isRefreshing = false
    @Published private(set) var lastError: String?

    private static let remoteURL = URL(
        string: "https://raw.githubusercontent.com/jo1project/jofit.Mark2/main/courses.json"
    )!
    private let cacheURL: URL
    private var templates: [CourseTemplate]

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
            var request = URLRequest(url: Self.remoteURL)
            request.cachePolicy = .reloadIgnoringLocalCacheData
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                throw URLError(.badServerResponse)
            }
            let decoded = try JSONDecoder().decode([CourseTemplate].self, from: data)
            guard !decoded.isEmpty else { throw URLError(.zeroByteResource) }

            templates = decoded
            courses = Self.resolve(decoded)
            lastUpdated = Date()
            lastError = nil
            Self.saveCache(decoded, to: cacheURL)
        } catch {
            // Re-resolve the existing templates in case the day rolled over since launch.
            courses = Self.resolve(templates)
            lastError = "課表更新失敗，目前顯示上次的快取資料（\(error.localizedDescription)）"
        }
    }

    private static func resolve(_ templates: [CourseTemplate]) -> [Course] {
        templates
            .compactMap { $0.resolvedCourse() }
            .sorted { ($0.month, $0.day, $0.time) < ($1.month, $1.day, $1.time) }
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
