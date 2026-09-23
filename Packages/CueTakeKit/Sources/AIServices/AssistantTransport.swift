import Foundation

/// Every request to the assistant server goes through here, and a request the network dropped is
/// sent again instead of reaching the user as an error.
///
/// The first tap after a while used to fail and the second work. The phone keeps a connection to
/// the server open between requests; the server closes idle ones, and a POST sent down a connection
/// that has just been closed fails with "the network connection was lost". The system retries such
/// a request only when it is a GET. Also sent again: the few seconds a gateway is busy (502–504,
/// Cloudflare's 52x) and a short per-minute limit (429).
public enum AssistantTransport {
    /// Its own session, so connections to the server are not shared with downloads and uploads of
    /// footage elsewhere in the app.
    static let session: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.waitsForConnectivity = false
        configuration.timeoutIntervalForResource = 600
        return URLSession(configuration: configuration)
    }()

    /// Tries after the first: a moment, then longer.
    private static let pauses: [Duration] = [.milliseconds(350), .milliseconds(1500)]

    public static func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        try await send { try await session.data(for: request) }
    }

    public static func upload(for request: URLRequest, fromFile url: URL) async throws -> (Data, URLResponse) {
        try await send { try await session.upload(for: request, fromFile: url) }
    }

    /// A file from anywhere (stock footage), with the same second chance.
    public static func download(from url: URL) async throws -> (URL, URLResponse) {
        try await send {
            let (file, response) = try await session.download(from: url)
            // The system deletes its temporary file when this returns; keep it under our own name.
            let kept = FileManager.default.temporaryDirectory.appending(path: "download-\(UUID().uuidString)", directoryHint: .notDirectory)
            try FileManager.default.moveItem(at: file, to: kept)
            return (kept, response)
        }
    }

    private static func send<T>(_ attempt: () async throws -> (T, URLResponse)) async throws -> (T, URLResponse) {
        var tries = 0
        while true {
            do {
                let result = try await attempt()
                if tries < pauses.count, let http = result.1 as? HTTPURLResponse, retries(status: http.statusCode) {
                    let wait = http.statusCode == 429 ? max(pauses[tries], .seconds(2)) : pauses[tries]
                    tries += 1
                    try await Task.sleep(for: wait)
                    continue
                }
                return result
            } catch let error as URLError where tries < pauses.count && retries(error.code) {
                try await Task.sleep(for: pauses[tries])
                tries += 1
            }
        }
    }

    static func retries(status: Int) -> Bool {
        status == 429 || status == 502 || status == 503 || status == 504 || (520...524).contains(status)
    }

    static func retries(_ code: URLError.Code) -> Bool {
        switch code {
        case .networkConnectionLost, .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed,
             .secureConnectionFailed, .resourceUnavailable, .notConnectedToInternet:
            true
        default:
            false
        }
    }
}
