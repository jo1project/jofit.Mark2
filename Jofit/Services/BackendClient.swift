import Foundation

enum BackendError: Error, LocalizedError {
    case invalidResponse
    case server(Int, String?)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "伺服器回應格式錯誤"
        case .server(403, _):
            return "管理密碼錯誤"
        case .server(429, _):
            return "密碼錯誤次數過多，請 15 分鐘後再試"
        case .server(let code, let message):
            return "伺服器錯誤（\(code)）" + (message.map { "：\($0)" } ?? "")
        }
    }
}

/// Talks to the VPS backend, which owns the actual "submit at the right time" job — this
/// client is just how the app creates/reads/cancels reservations and registers for push.
///
/// The URL and token are hardcoded below at the user's explicit request, with the tradeoff
/// spelled out and accepted: this repo is public, so anyone who finds it can read this token
/// and call the backend directly with it. If that ever becomes a problem, rotate BEARER_TOKEN
/// in the VPS's `backend/.env` and update the value here to match.
struct BackendClient {
    static let defaultBaseURL = "https://jofit.duckdns.org"
    static let defaultToken = "qhvg10B4b53K2kEQwqsGMHUZBr623w_Wqyz02Rnj6MU"

    var baseURL: String = defaultBaseURL
    var token: String = defaultToken

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

    /// Admin only (needs the PIN, which the backend checks). Returns how many were actually
    /// cancelled — rows that started submitting in the meantime are skipped.
    func cancelReservations(ids: [String], pin: String) async throws -> Int {
        let body = try JSONEncoder().encode(["ids": ids])
        let data = try await send("/reservations/cancel", method: "POST", body: body, pin: pin)
        return try JSONDecoder().decode([String: Int].self, from: data)["cancelled"] ?? 0
    }

    /// Empty until an admin has saved a course list once.
    func listCourses() async throws -> [CourseTemplate] {
        let data = try await send("/courses")
        return try JSONDecoder().decode([CourseTemplate].self, from: data)
    }

    /// Admin only: replaces the whole shared course list.
    func saveCourses(_ templates: [CourseTemplate], pin: String) async throws {
        let body = try JSONEncoder().encode(templates)
        _ = try await send("/courses", method: "PUT", body: body, pin: pin)
    }

    func registerDeviceToken(_ token: String) async throws {
        let body = try JSONEncoder().encode(["token": token])
        _ = try await send("/device-token", method: "POST", body: body)
    }

    private func send(_ path: String, method: String = "GET", body: Data? = nil, pin: String? = nil) async throws -> Data {
        guard let url = URL(string: baseURL.trimmingCharacters(in: .whitespaces) + path) else {
            throw BackendError.invalidResponse
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let pin { request.setValue(pin, forHTTPHeaderField: "X-Admin-Pin") }
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
    let reporterName: String?
    let employeeID: String?

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
        case reporterName = "reporter_name"
        case employeeID = "employee_id"
    }

    private static let dateTimeFormatter = ISO8601DateFormatter()

    func toReservation() -> Reservation? {
        guard
            let date = BackendClient.courseDateFormatter.date(from: courseDate),
            let fire = Self.dateTimeFormatter.date(from: fireDate),
            let status = Reservation.Status(rawValue: status)
        else { return nil }

        // courseID is "<templateID>_<yyyyMMdd>" (see CourseTemplate.resolvedCourses) — strip the
        // date stamp back off. Only used for display grouping on already-created reservations,
        // so falling back to the full courseID if the pattern ever doesn't match is harmless.
        let templateID = courseID.range(of: "_[0-9]{8}$", options: .regularExpression)
            .map { String(courseID[..<$0.lowerBound]) } ?? courseID
        let course = Course(id: courseID, templateID: templateID, date: date, time: courseTime, name: courseName)
        let submitted = submittedAt.flatMap { Self.dateTimeFormatter.date(from: $0) }

        return Reservation(
            id: id, course: course, status: status, fireDate: fire,
            submittedAt: submitted, httpStatus: httpStatus, lastError: lastError,
            reporterName: reporterName, employeeID: employeeID
        )
    }
}
