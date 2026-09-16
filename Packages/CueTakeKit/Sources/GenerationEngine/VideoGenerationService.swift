import Domain
import Foundation

/// Makes a video from start to file: submits, waits, downloads.
///
/// Waiting is a slow poll with a ceiling rather than a busy loop: a model can take minutes, and
/// asking every second spends the user's rate limit for nothing.
public struct VideoGenerationService: Sendable {
    let generators: [GenerationProviderID: any VideoGenerator]
    let transport: any HTTPTransport
    let pollInterval: Duration
    let timeout: Duration

    public init(
        transport: any HTTPTransport = URLSessionTransport(),
        pollInterval: Duration = .seconds(5),
        timeout: Duration = .seconds(20 * 60)
    ) {
        self.transport = transport
        self.pollInterval = pollInterval
        self.timeout = timeout
        generators = [
            .fal: FalVideoGenerator(transport: transport),
            .google: GoogleVeoGenerator(transport: transport),
            .openai: OpenAISoraGenerator(transport: transport),
            .replicate: ReplicateVideoGenerator(transport: transport),
        ]
    }

    public func generator(for provider: GenerationProviderID) -> any VideoGenerator {
        generators[provider]!
    }

    /// Whether a key works. Nil when the provider cannot say without spending anything.
    public func verify(_ key: String, for provider: GenerationProviderID) async -> Bool? {
        await generator(for: provider).verify(key: key)
    }

    /// Makes one video and saves it into `directory`.
    /// - Parameter progress: 0…1 when the provider reports it, nil while it only says "working".
    @concurrent
    public func generate(
        _ request: VideoGenerationRequest,
        provider: GenerationProviderID,
        key: String,
        into directory: URL,
        progress: @escaping @Sendable (Double?) -> Void = { _ in }
    ) async throws -> URL {
        guard !key.isEmpty else { throw GenerationError.missingKey(provider) }
        guard !request.model.isEmpty else { throw GenerationError.missingModel }
        let generator = generator(for: provider)
        let ticket = try await generator.start(request, key: key)
        progress(0)

        let clock = ContinuousClock()
        let deadline = clock.now + timeout
        var failures = 0
        while true {
            try Task.checkCancellation()
            try await Task.sleep(for: pollInterval)
            let state: GenerationState
            do {
                state = try await generator.check(ticket, key: key)
                failures = 0
            } catch GenerationError.network {
                // A dropped connection while waiting is not a failed video: try again a few times.
                failures += 1
                guard failures < 5 else { throw GenerationError.network("Lost the connection while waiting") }
                continue
            }
            switch state {
            case .working(let fraction):
                progress(fraction)
                if clock.now > deadline { throw GenerationError.timedOut }
            case .failed(let message):
                throw GenerationError.failed(message)
            case .ready(let remote, let authorized):
                progress(1)
                return try await download(
                    remote,
                    headers: authorized ? generator.downloadHeaders(key: key) : [:],
                    into: directory
                )
            }
        }
    }

    func download(_ remote: URL, headers: [String: String], into directory: URL) async throws -> URL {
        let request = try HTTP.request(remote, headers: headers)
        let (temporary, response) = try await transport.download(request)
        guard (200..<300).contains(response.statusCode) else {
            try? FileManager.default.removeItem(at: temporary)
            throw response.statusCode == 401 || response.statusCode == 403
                ? GenerationError.unauthorized
                : GenerationError.failed("Download failed (HTTP \(response.statusCode))")
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let destination = directory.appending(path: "generated-\(UUID().uuidString).mp4", directoryHint: .notDirectory)
        try FileManager.default.moveItem(at: temporary, to: destination)
        return destination
    }
}
