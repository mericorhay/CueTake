import Domain
import Foundation

// MARK: - fal.ai

/// fal's queue API: submit, poll the status URL, read the result URL.
/// Docs: https://fal.ai/docs/model-apis/model-endpoints/queue
public struct FalVideoGenerator: VideoGenerator {
    public let provider = GenerationProviderID.fal
    let transport: any HTTPTransport

    public init(transport: any HTTPTransport = URLSessionTransport()) {
        self.transport = transport
    }

    private func auth(_ key: String) -> [String: String] { ["Authorization": "Key \(key)"] }

    public func start(_ request: VideoGenerationRequest, key: String) async throws -> GenerationTicket {
        let model = (request.image != nil ? request.imageModel : nil) ?? request.model
        guard !model.isEmpty, let url = URL(string: "https://queue.fal.run/\(model)") else { throw GenerationError.missingModel }
        var input: [String: Any] = [
            "prompt": request.prompt,
            // fal video models take their length as a string enum ("5", "8"…).
            "duration": String(Int(request.seconds.rounded())),
            "aspect_ratio": request.aspect,
            "resolution": request.resolution,
            "generate_audio": request.audio,
        ]
        if let image = request.image { input["image_url"] = HTTP.dataURI(image) }
        if let negative = request.negativePrompt { input["negative_prompt"] = negative }
        let body = try await HTTP.object(
            HTTP.request(url, method: "POST", headers: auth(key), json: input),
            via: transport
        )
        guard let status = body["status_url"] as? String, let response = body["response_url"] as? String else {
            throw GenerationError.rejected(HTTP.message(in: body) ?? "fal did not queue the request")
        }
        return GenerationTicket(provider: .fal, reference: status, resultReference: response)
    }

    public func check(_ ticket: GenerationTicket, key: String) async throws -> GenerationState {
        guard let statusURL = URL(string: ticket.reference) else { throw GenerationError.noOutput }
        let status = try await HTTP.object(HTTP.request(statusURL, headers: auth(key)), via: transport)
        switch status["status"] as? String {
        case "COMPLETED":
            break
        case "FAILED", "ERROR":
            return .failed(HTTP.message(in: status) ?? "fal could not make the video")
        default:
            return .working(nil)
        }
        if let error = status["error"] as? String { return .failed(error) }
        guard let resultURL = ticket.resultReference.flatMap(URL.init(string:)) else { throw GenerationError.noOutput }
        let result: [String: Any]
        do {
            result = try await HTTP.object(HTTP.request(resultURL, headers: auth(key)), via: transport)
        } catch GenerationError.rejected(let message) {
            return .failed(message)
        }
        guard let video = Self.videoURL(in: result) else { return .failed("fal returned no video") }
        return .ready(video, authorized: false)
    }

    /// Video models on fal answer in a few shapes.
    static func videoURL(in result: [String: Any]) -> URL? {
        let candidates: [[Any]] = [["video", "url"], ["video"], ["videos", 0, "url"], ["output", "video", "url"], ["data", "video", "url"]]
        for path in candidates {
            if let text = result.value(at: path) as? String, let url = URL(string: text) { return url }
        }
        return nil
    }

    public func downloadHeaders(key: String) -> [String: String] { [:] }

    public func verify(key: String) async -> Bool? {
        // No account endpoint: a status lookup for a request that does not exist answers 401/403
        // for a bad key and something else for a good one.
        guard let url = URL(string: "https://queue.fal.run/fal-ai/fast-sdxl/requests/00000000-0000-0000-0000-000000000000/status"),
              let request = try? HTTP.request(url, headers: auth(key)),
              let (_, response) = try? await transport.send(request)
        else { return nil }
        return [401, 403].contains(response.statusCode) ? false : nil
    }
}

// MARK: - Google Veo

/// Veo on the Gemini API: `predictLongRunning`, then poll the operation.
/// Docs: https://ai.google.dev/gemini-api/docs/veo
public struct GoogleVeoGenerator: VideoGenerator {
    public let provider = GenerationProviderID.google
    let transport: any HTTPTransport
    static let base = "https://generativelanguage.googleapis.com/v1beta"

    public init(transport: any HTTPTransport = URLSessionTransport()) {
        self.transport = transport
    }

    private func auth(_ key: String) -> [String: String] { ["x-goog-api-key": key] }

    public func start(_ request: VideoGenerationRequest, key: String) async throws -> GenerationTicket {
        guard !request.model.isEmpty,
              let url = URL(string: "\(Self.base)/models/\(request.model):predictLongRunning")
        else { throw GenerationError.missingModel }
        var instance: [String: Any] = ["prompt": request.prompt]
        if let image = request.image {
            instance["image"] = ["bytesBase64Encoded": image.base64EncodedString(), "mimeType": HTTP.mimeType(of: image)]
        }
        var parameters: [String: Any] = [
            "aspectRatio": request.aspect,
            "durationSeconds": Int(request.seconds.rounded()),
            "resolution": request.resolution,
        ]
        if let negative = request.negativePrompt { parameters["negativePrompt"] = negative }
        let body = try await HTTP.object(
            HTTP.request(url, method: "POST", headers: auth(key), json: ["instances": [instance], "parameters": parameters]),
            via: transport
        )
        guard let name = body["name"] as? String else {
            throw GenerationError.rejected(HTTP.message(in: body) ?? "Veo did not start")
        }
        return GenerationTicket(provider: .google, reference: name)
    }

    public func check(_ ticket: GenerationTicket, key: String) async throws -> GenerationState {
        guard let url = URL(string: "\(Self.base)/\(ticket.reference)") else { throw GenerationError.noOutput }
        let operation = try await HTTP.object(HTTP.request(url, headers: auth(key)), via: transport)
        guard operation["done"] as? Bool == true else { return .working(nil) }
        if let error = operation["error"] as? [String: Any] {
            return .failed(error["message"] as? String ?? "Veo could not make the video")
        }
        let response = operation["response"] as? [String: Any] ?? [:]
        if let uri = response.value(at: ["generateVideoResponse", "generatedSamples", 0, "video", "uri"]) as? String,
           let url = URL(string: uri) {
            return .ready(url, authorized: true)
        }
        // The safety filter answers with reasons and no sample.
        if let reasons = response.value(at: ["generateVideoResponse", "raiMediaFilteredReasons"]) as? [String], !reasons.isEmpty {
            return .failed(reasons.joined(separator: " "))
        }
        return .failed("Veo returned no video")
    }

    public func downloadHeaders(key: String) -> [String: String] { auth(key) }

    public func verify(key: String) async -> Bool? {
        guard let url = URL(string: "\(Self.base)/models?pageSize=1"),
              let request = try? HTTP.request(url, headers: auth(key))
        else { return nil }
        return await HTTP.keyStatus(request, via: transport)
    }
}

// MARK: - OpenAI Sora

/// Sora on the OpenAI API: create, poll the video, download its content.
/// Docs: https://developers.openai.com/api/docs/guides/video-generation
public struct OpenAISoraGenerator: VideoGenerator {
    public let provider = GenerationProviderID.openai
    let transport: any HTTPTransport
    static let base = "https://api.openai.com/v1"

    public init(transport: any HTTPTransport = URLSessionTransport()) {
        self.transport = transport
    }

    private func auth(_ key: String) -> [String: String] { ["Authorization": "Bearer \(key)"] }

    /// Sora takes a pixel size rather than a ratio.
    static func size(aspect: String, resolution: String, model: String) -> String {
        let portrait = VideoModelPreset.ratio(aspect) < 1
        let large = model.contains("pro") && VideoModelPreset.lines(resolution) >= 1080
        switch (portrait, large) {
        case (true, false): return "720x1280"
        case (false, false): return "1280x720"
        case (true, true): return "1024x1792"
        case (false, true): return "1792x1024"
        }
    }

    public func start(_ request: VideoGenerationRequest, key: String) async throws -> GenerationTicket {
        guard !request.model.isEmpty, let url = URL(string: "\(Self.base)/videos") else { throw GenerationError.missingModel }
        var form = MultipartForm()
        form.add("model", request.model)
        form.add("prompt", request.prompt)
        form.add("seconds", String(Int(request.seconds.rounded())))
        form.add("size", Self.size(aspect: request.aspect, resolution: request.resolution, model: request.model))
        if let image = request.image {
            let type = HTTP.mimeType(of: image)
            form.addFile("input_reference", filename: type == "image/png" ? "frame.png" : "frame.jpg", type: type, data: image)
        }
        var http = try HTTP.request(url, method: "POST", headers: auth(key))
        http.setValue(form.contentType, forHTTPHeaderField: "Content-Type")
        http.httpBody = form.body
        let body = try await HTTP.object(http, via: transport)
        guard let id = body["id"] as? String else {
            throw GenerationError.rejected(HTTP.message(in: body) ?? "Sora did not start")
        }
        return GenerationTicket(provider: .openai, reference: id)
    }

    public func check(_ ticket: GenerationTicket, key: String) async throws -> GenerationState {
        guard let url = URL(string: "\(Self.base)/videos/\(ticket.reference)") else { throw GenerationError.noOutput }
        let video = try await HTTP.object(HTTP.request(url, headers: auth(key)), via: transport)
        switch video["status"] as? String {
        case "completed":
            guard let content = URL(string: "\(Self.base)/videos/\(ticket.reference)/content") else { throw GenerationError.noOutput }
            return .ready(content, authorized: true)
        case "failed":
            return .failed(HTTP.message(in: video) ?? "Sora could not make the video")
        default:
            let progress = (video["progress"] as? Double) ?? (video["progress"] as? Int).map(Double.init)
            return .working(progress.map { min(max($0 / 100, 0), 1) })
        }
    }

    public func downloadHeaders(key: String) -> [String: String] { auth(key) }

    public func verify(key: String) async -> Bool? {
        guard let url = URL(string: "\(Self.base)/models"),
              let request = try? HTTP.request(url, headers: auth(key))
        else { return nil }
        return await HTTP.keyStatus(request, via: transport)
    }
}

// MARK: - Replicate

/// Replicate's predictions API, for any public video model.
/// Docs: https://replicate.com/docs/reference/http
public struct ReplicateVideoGenerator: VideoGenerator {
    public let provider = GenerationProviderID.replicate
    let transport: any HTTPTransport
    static let base = "https://api.replicate.com/v1"

    public init(transport: any HTTPTransport = URLSessionTransport()) {
        self.transport = transport
    }

    private func auth(_ key: String) -> [String: String] { ["Authorization": "Bearer \(key)"] }

    public func start(_ request: VideoGenerationRequest, key: String) async throws -> GenerationTicket {
        let model = request.model.trimmingCharacters(in: .whitespaces)
        guard !model.isEmpty else { throw GenerationError.missingModel }
        var input: [String: Any] = [
            "prompt": request.prompt,
            "duration": Int(request.seconds.rounded()),
            "aspect_ratio": request.aspect,
            "resolution": request.resolution,
        ]
        if request.audio { input["generate_audio"] = true }
        if let image = request.image { input["image"] = HTTP.dataURI(image) }
        if let negative = request.negativePrompt { input["negative_prompt"] = negative }

        // `owner/name` runs the latest version; `owner/name:version` pins one.
        let url: URL?
        var body: [String: Any] = ["input": input]
        if let colon = model.firstIndex(of: ":") {
            url = URL(string: "\(Self.base)/predictions")
            body["version"] = String(model[model.index(after: colon)...])
        } else {
            url = URL(string: "\(Self.base)/models/\(model)/predictions")
        }
        guard let url else { throw GenerationError.missingModel }
        let prediction = try await HTTP.object(
            HTTP.request(url, method: "POST", headers: auth(key), json: body),
            via: transport
        )
        guard let get = prediction.value(at: ["urls", "get"]) as? String else {
            throw GenerationError.rejected(HTTP.message(in: prediction) ?? "Replicate did not start")
        }
        return GenerationTicket(provider: .replicate, reference: get)
    }

    public func check(_ ticket: GenerationTicket, key: String) async throws -> GenerationState {
        guard let url = URL(string: ticket.reference) else { throw GenerationError.noOutput }
        let prediction = try await HTTP.object(HTTP.request(url, headers: auth(key)), via: transport)
        switch prediction["status"] as? String {
        case "succeeded":
            let output = prediction["output"]
            let text = (output as? String) ?? (output as? [String])?.last ?? (output as? [String: Any])?["video"] as? String
            guard let text, let video = URL(string: text) else { return .failed("Replicate returned no video") }
            return .ready(video, authorized: false)
        case "failed", "canceled":
            return .failed(prediction["error"] as? String ?? "Replicate could not make the video")
        default:
            return .working(nil)
        }
    }

    public func downloadHeaders(key: String) -> [String: String] { [:] }

    public func verify(key: String) async -> Bool? {
        guard let url = URL(string: "\(Self.base)/account"),
              let request = try? HTTP.request(url, headers: auth(key))
        else { return nil }
        return await HTTP.keyStatus(request, via: transport)
    }
}

// MARK: - Multipart

struct MultipartForm {
    let boundary = "cuetake-\(UUID().uuidString)"
    private var parts = Data()
    private static let newline = "\r\n"

    var contentType: String { "multipart/form-data; boundary=\(boundary)" }
    var body: Data { parts + Data("--\(boundary)--\(Self.newline)".utf8) }

    mutating func add(_ name: String, _ value: String) {
        let n = Self.newline
        parts.append(Data("--\(boundary)\(n)Content-Disposition: form-data; name=\"\(name)\"\(n)\(n)\(value)\(n)".utf8))
    }

    mutating func addFile(_ name: String, filename: String, type: String, data: Data) {
        let n = Self.newline
        parts.append(Data("--\(boundary)\(n)Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\(n)Content-Type: \(type)\(n)\(n)".utf8))
        parts.append(data)
        parts.append(Data(n.utf8))
    }
}
