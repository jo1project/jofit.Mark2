import Foundation

enum FormSubmissionError: Error {
    case incompleteProfile
    case invalidResponse
}

/// Submits directly to the Google Form's `formResponse` endpoint (no WebView needed),
/// which is both faster and more reliable for winning a race against other submitters.
struct FormSubmissionService {
    // Jofit 模擬表單 (test form). Swap this URL + the entry IDs below when Jofit switches
    // the real registration form in — open the new form's page source and search for
    // `entry.` to find the replacement IDs.
    private static let formActionURL = URL(
        string: "https://docs.google.com/forms/d/e/1FAIpQLSfkfXdRQzbU37S56equARw25SIM4XatGt14TgPCny5_ri9Bog/formResponse"
    )!

    private enum Entry {
        static let name = "entry.954137713"
        static let employeeID = "entry.698318826"
        static let course = "entry.1514588416"
    }

    /// Returns the HTTP status code. Google Forms doesn't return a machine-readable
    /// success flag, so a 200 is the best available signal that the response was recorded.
    func submit(name: String, employeeID: String, courseText: String) async throws -> Int {
        guard !name.isEmpty, !employeeID.isEmpty else {
            throw FormSubmissionError.incompleteProfile
        }

        var request = URLRequest(url: Self.formActionURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded; charset=UTF-8", forHTTPHeaderField: "Content-Type")

        var components = URLComponents()
        components.queryItems = [
            URLQueryItem(name: Entry.name, value: name),
            URLQueryItem(name: Entry.employeeID, value: employeeID),
            URLQueryItem(name: Entry.course, value: courseText),
            URLQueryItem(name: "fvv", value: "1"),
            URLQueryItem(name: "pageHistory", value: "0"),
        ]
        request.httpBody = components.percentEncodedQuery?.data(using: .utf8)

        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw FormSubmissionError.invalidResponse
        }
        return http.statusCode
    }
}
