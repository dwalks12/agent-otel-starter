import Foundation

/// A minimal ClickHouse HTTP client: POST the SQL, read JSONEachRow back.
struct ClickHouseClient: Sendable {
    let baseURL: URL

    enum Failure: LocalizedError {
        case unreachable(String)
        case server(String)

        var errorDescription: String? {
            switch self {
            case .unreachable(let detail): "Can’t reach ClickHouse (\(detail)). Is the stack up? Run ./run.sh"
            case .server(let message): message
            }
        }
    }

    func rows<Row: Decodable>(_ sql: String, as: Row.Type = Row.self) async throws -> [Row] {
        let data = try await execute(sql + "\nFORMAT JSONEachRow")
        let decoder = JSONDecoder()
        return try data.split(separator: UInt8(ascii: "\n")).map { try decoder.decode(Row.self, from: Data($0)) }
    }

    /// Runs a statement as it is (DDL, or an INSERT with its rows) and returns the response body.
    @discardableResult
    func execute(_ sql: String) async throws -> Data {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            // Numbers as JSON numbers, not quoted strings; NULL stays null.
            URLQueryItem(name: "output_format_json_quote_64bit_integers", value: "0"),
            URLQueryItem(name: "output_format_json_quote_decimals", value: "0"),
        ]
        var request = URLRequest(url: components.url!, timeoutInterval: 5)
        request.httpMethod = "POST"
        request.httpBody = Data(sql.utf8)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw Failure.unreachable(error.localizedDescription)
        }
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            let message = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            throw Failure.server(message.isEmpty ? "ClickHouse returned HTTP \(http.statusCode)" : message)
        }
        return data
    }
}
