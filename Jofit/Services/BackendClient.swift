import Foundation

enum BackendError: Error, LocalizedError {
    case notConfigured
    case invalidResponse
    case server(Int, String?)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "尚未在設定裡填寫後端網址與授權金鑰"
        case .invalidResponse:
            return "伺服器回應格式錯誤"
        case .server(let code, let message):
            return "伺服器錯誤（\(code)）" + (message.map { "：\($0)" } ?? "")
        }
    }
}

/// Talks to the VPS backend, which owns the actual "submit at the right time" job — this
/// client is just how the app creates/reads/cancels reservations and registers for push.
struct BackendClient {
    var baseURL: String
    var token: String

    private var isConfigured: Bool {
        !baseURL.trimmingCharacters(in: .whitespaces).isEmpty &&
        !token.trimmingCharacters(in: .whitespaces).isEmpty
    }

    func listReservations() async throws -> [Reservation] {
        let data = try await send("/reservations")
        return try JSONDecoder().decode([ReservationDTO].self, from: data).compactMap { $0.toReservation() }
    }

    func createReservation(course: Course, name: String, employeeID: String) async throws -> Reservation {
        let payload = CreateReservationRequest(
            course: .init(
                id: course.id,
                date: Self.courseDateFormatter.string(from: course.date),
                time: course.time,
                name: course.name
            ),
            name: name,
            employeeID: employeeID
        )
        let body = try JSONEncoder().encode(payload)
        let data = try await send("/reservations", method: "POST", body: body)
        guard let reservation = try JSONDecoder().decode(ReservationDTO.self, from: data).toReservation() else {
            throw BackendError.invalidResponse
        }
        return reservation
    }

    func cancelReservation(id: String) async throws {
        _ = try await send("/reservations/\(id)", method: "DELETE")
    }

    func registerDeviceToken(_ token: String) async throws {
        let body = try JSONEncoder().encode(["token": token])
        _ = try await send("/device-token", method: "POST", body: body)
    }

    private func send(_ path: String, method: String = "GET", body: Data? = nil) async throws -> Data {
        guard isConfigured,
              let url = URL(string: baseURL.trimmingCharacters(in: .whitespaces) + path) else {
            throw BackendError.notConfigured
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = body
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw BackendError.invalidResponse }
        guard (200...299).contains(http.statusCode) else {
            throw BackendError.server(http.statusCode, String(data: data, encoding: .utf8))
        }
        return data
    }

    static let courseDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "Asia/Taipei")
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()
}

private struct CreateReservationRequest: Encodable {
    struct CourseIn: Encodable {
        let id: String
        let date: String
        let time: String
        let name: String
    }
    let course: CourseIn
    let name: String
    let employeeID: String

    enum CodingKeys: String, CodingKey {
        case course, name
        case employeeID = "employee_id"
    }
}

private struct ReservationDTO: Decodable {
    let id: String
    let courseID: String
    let courseDate: String
    let courseTime: String
    let courseName: String
    let status: String
    let fireDate: String
    let submittedAt: String?
    let httpStatus: Int?
    let lastError: String?

    enum CodingKeys: String, CodingKey {
        case id, status
        case courseID = "course_id"
        case courseDate = "course_date"
        case courseTime = "course_time"
        case courseName = "course_name"
        case fireDate = "fire_date"
        case submittedAt = "submitted_at"
        case httpStatus = "http_status"
        case lastError = "last_error"
    }

    private static let dateTimeFormatter = ISO8601DateFormatter()

    func toReservation() -> Reservation? {
        guard
            let date = BackendClient.courseDateFormatter.date(from: courseDate),
            let fire = Self.dateTimeFormatter.date(from: fireDate),
            let status = Reservation.Status(rawValue: status)
        else { return nil }

        let course = Course(id: courseID, date: date, time: courseTime, name: courseName)
        let submitted = submittedAt.flatMap { Self.dateTimeFormatter.date(from: $0) }

        return Reservation(
            id: id, course: course, status: status, fireDate: fire,
            submittedAt: submitted, httpStatus: httpStatus, lastError: lastError
        )
    }
}
