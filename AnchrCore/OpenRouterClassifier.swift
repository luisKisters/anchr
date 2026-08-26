import AnchrKit
import Foundation

/// Sends one observation to OpenRouter and returns a verdict. Transport only —
/// the body, the schema and the decoding live in `AnchrKit/OpenRouterRequest.swift`.
///
/// Anchr spawns no processes: this replaced the `codex exec` seam, so the app now
/// has no reason to touch `Process` at all.
public actor OpenRouterClassifier: DriftClassifier {
    public enum Error: Swift.Error, Equatable {
        case missingAPIKey
        case transport(String)
        case httpStatus(Int, String)
        case timedOut
    }

    private let apiKey: String
    private let model: String
    private let endpoint: URL
    private let session: URLSession

    public init(
        apiKey: String,
        model: String = OpenRouterKey.configuredModel,
        endpoint: URL = OpenRouterRequest.endpoint,
        timeout: TimeInterval = 30
    ) {
        self.apiKey = apiKey
        self.model = model
        self.endpoint = endpoint

        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = timeout
        configuration.timeoutIntervalForResource = timeout
        // A drifting user is judged every 45-90 s. A cached answer would judge the
        // window they were in a minute ago.
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        session = URLSession(configuration: configuration)
    }

    /// Fails loudly when no key is configured instead of silently never classifying.
    public init(
        model: String = OpenRouterKey.configuredModel,
        endpoint: URL = OpenRouterRequest.endpoint,
        timeout: TimeInterval = 30
    ) throws {
        guard let key = OpenRouterKey.load() else { throw Error.missingAPIKey }
        self.init(apiKey: key, model: model, endpoint: endpoint, timeout: timeout)
    }

    public func classify(_ observation: Observation) async throws -> Verdict {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // OpenRouter attributes usage to these; they are not tracking of the user.
        request.setValue("https://github.com/luisKisters/anchr", forHTTPHeaderField: "HTTP-Referer")
        request.setValue("Anchr", forHTTPHeaderField: "X-Title")
        request.httpBody = try OpenRouterRequest.body(for: observation, model: model)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError where error.code == .timedOut {
            throw Error.timedOut
        } catch {
            throw Error.transport(error.localizedDescription)
        }

        if let http = response as? HTTPURLResponse, !(200 ..< 300).contains(http.statusCode) {
            let detail = (try? OpenRouterRequest.verdict(from: data)) == nil
                ? String(data: data.prefix(400), encoding: .utf8) ?? ""
                : ""
            throw Error.httpStatus(http.statusCode, detail)
        }

        return try OpenRouterRequest.verdict(from: data)
    }
}
