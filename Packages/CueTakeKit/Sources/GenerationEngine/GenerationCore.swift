import Domain
import Foundation

/// What to make.
public struct VideoGenerationRequest: Hashable, Sendable {
    public var prompt: String
    /// The provider's model id.
    public var model: String
    /// Used instead of `model` when a starting picture is given and the provider splits them.
    public var imageModel: String?
    public var seconds: Double
    /// `9:16`, `16:9`…
    public var aspect: String
    /// `720p`, `1080p`…
    public var resolution: String
    public var audio: Bool
    /// A first frame, as JPEG or PNG.
    public var image: Data?
    public var negativePrompt: String?

    public init(
        prompt: String,
        model: String,
        imageModel: String? = nil,
        seconds: Double,
        aspect: String,
        resolution: String,
        audio: Bool,
        image: Data? = nil,
        negativePrompt: String? = nil
    ) {
        self.prompt = prompt
        self.model = model
        self.imageModel = imageModel
        self.seconds = seconds
        self.aspect = aspect
        self.resolution = resolution
        self.audio = audio
        self.image = image
        self.negativePrompt = negativePrompt
    }

    /// The request fitted to what a preset accepts.
    public static func fitted(_ options: GenerateVideoOptions, prompt: String, image: Data? = nil) -> VideoGenerationRequest {
        let preset = options.modelPreset
        return VideoGenerationRequest(
            prompt: options.fullPrompt(prompt),
            model: options.resolvedModel,
            imageModel: preset.isCustom ? nil : preset.imageModel,
            seconds: preset.duration(nearest: options.seconds),
            aspect: preset.aspect(nearest: options.aspect),
            resolution: preset.resolution(nearest: options.resolution),
            audio: options.audio && (preset.makesAudio || preset.isCustom),
            image: image
        )
    }
}

public enum GenerationError: Error, Hashable, Sendable, LocalizedError {
    case missingKey(GenerationProviderID)
    case missingModel
    case unauthorized
    /// The provider refused the request: bad parameters, safety filter, no credit.
    case rejected(String)
    case failed(String)
    case timedOut
    case noOutput
    case network(String)

    public var errorDescription: String? {
        switch self {
        case .missingKey(let provider): "No API key for \(provider.displayName)."
        case .missingModel: "No model id."
        case .unauthorized: "The API key was refused."
        case .rejected(let message): message
        case .failed(let message): message
        case .timedOut: "The video took too long."
        case .noOutput: "The provider returned no video."
        case .network(let message): message
        }
    }
}

/// A job the provider is working on.
public struct GenerationTicket: Hashable, Sendable, Codable {
    public var provider: GenerationProviderID
    /// Whatever the provider needs to find the job again: an id, an operation name, a URL.
    public var reference: String
    /// A second reference, such as fal's result URL.
    public var resultReference: String?

    public init(provider: GenerationProviderID, reference: String, resultReference: String? = nil) {
        self.provider = provider
        self.reference = reference
        self.resultReference = resultReference
    }
}

public enum GenerationState: Hashable, Sendable {
    /// Still working; progress 0…1 when the provider says.
    case working(Double?)
    /// Ready to download from here, with the headers the download needs.
    case ready(URL, authorized: Bool)
    case failed(String)
}

/// One provider's video API.
public protocol VideoGenerator: Sendable {
    var provider: GenerationProviderID { get }
    func start(_ request: VideoGenerationRequest, key: String) async throws -> GenerationTicket
    func check(_ ticket: GenerationTicket, key: String) async throws -> GenerationState
    /// Headers for downloading a result that needs the key.
    func downloadHeaders(key: String) -> [String: String]
    /// Whether the key opens the door. Nil when the provider has no cheap way to tell.
    func verify(key: String) async -> Bool?
}

// MARK: - HTTP

/// The network, replaceable in tests.
public protocol HTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
    func download(_ request: URLRequest) async throws -> (URL, HTTPURLResponse)
}

public struct URLSessionTransport: HTTPTransport {
    public init() {}

    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 120
        configuration.timeoutIntervalForResource = 60 * 30
        configuration.waitsForConnectivity = true
        return URLSession(configuration: configuration)
    }()

    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        do {
            let (data, response) = try await Self.session.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw GenerationError.network("No response") }
            return (data, http)
        } catch let error as GenerationError {
            throw error
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw GenerationError.network(error.localizedDescription)
        }
    }

    public func download(_ request: URLRequest) async throws -> (URL, HTTPURLResponse) {
        do {
            let (url, response) = try await Self.session.download(for: request)
            guard let http = response as? HTTPURLResponse else { throw GenerationError.network("No response") }
            return (url, http)
        } catch let error as GenerationError {
            throw error
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw GenerationError.network(error.localizedDescription)
        }
    }
}

enum HTTP {
    static func request(
        _ url: URL,
        method: String = "GET",
        headers: [String: String] = [:],
        json: Any? = nil
    ) throws -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        for (name, value) in headers { request.setValue(value, forHTTPHeaderField: name) }
        if let json {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: json)
        }
        return request
    }

    /// Sends and reads a JSON object, turning HTTP failures into readable errors.
    static func object(_ request: URLRequest, via transport: any HTTPTransport) async throws -> [String: Any] {
        let (data, response) = try await transport.send(request)
        let body = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        switch response.statusCode {
        case 200..<300:
            return body
        case 401, 403:
            throw GenerationError.unauthorized
        default:
            throw GenerationError.rejected(message(in: body) ?? "HTTP \(response.statusCode)")
        }
    }

    /// The human part of an error body, in the shapes providers use.
    static func message(in body: [String: Any]) -> String? {
        if let error = body["error"] as? [String: Any], let text = error["message"] as? String { return text }
        if let text = body["error"] as? String { return text }
        if let text = body["detail"] as? String { return text }
        if let details = body["detail"] as? [[String: Any]] {
            let texts = details.compactMap { $0["msg"] as? String }
            if !texts.isEmpty { return texts.joined(separator: "; ") }
        }
        if let text = body["message"] as? String { return text }
        return nil
    }

    static func mimeType(of image: Data) -> String {
        image.starts(with: [0x89, 0x50, 0x4E, 0x47]) ? "image/png" : "image/jpeg"
    }

    static func dataURI(_ image: Data) -> String {
        "data:\(mimeType(of: image));base64,\(image.base64EncodedString())"
    }

    /// Whether a key-check response means the key is good.
    static func keyStatus(_ request: URLRequest, via transport: any HTTPTransport) async -> Bool? {
        guard let (_, response) = try? await transport.send(request) else { return nil }
        switch response.statusCode {
        case 200..<300: return true
        case 400, 401, 403: return false
        default: return nil
        }
    }
}

extension Dictionary where Key == String, Value == Any {
    /// A value down a path of keys and array indices: `["response", "samples", 0, "uri"]`.
    func value(at path: [Any]) -> Any? {
        var current: Any? = self
        for step in path {
            if let key = step as? String {
                current = (current as? [String: Any])?[key]
            } else if let index = step as? Int {
                guard let array = current as? [Any], array.indices.contains(index) else { return nil }
                current = array[index]
            }
        }
        return current
    }
}
