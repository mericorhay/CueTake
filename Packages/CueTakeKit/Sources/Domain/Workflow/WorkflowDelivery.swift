import Foundation

/// Where a workflow sends its finished video: the user's own endpoint.
///
/// One per workflow, kept inside that workflow's export step, so a "Shorts for client A" workflow
/// posts to client A and nothing else. The secret that authorises the request is *not* here: a
/// workflow is a document people copy and share, and the token lives in this phone's Keychain,
/// keyed by the workflow's id.
public struct WorkflowDelivery: Hashable, Sendable, Codable {
    public enum Method: String, Hashable, Sendable, Codable, CaseIterable {
        case post = "POST"
        case put = "PUT"
    }

    /// What the request carries.
    public enum Payload: String, Hashable, Sendable, Codable, CaseIterable {
        /// `multipart/form-data`: the video as a file field, and the details as text fields.
        /// What most upload APIs and automation tools (Make, n8n, Zapier) accept.
        case multipart
        /// The video file as the whole body — a presigned S3 or R2 URL, a Cloudflare Stream upload.
        case rawVideo
        /// Only the details, as JSON. For a webhook that should know a video was made.
        case json
    }

    public var isEnabled: Bool
    public var endpoint: String
    public var method: Method
    public var payload: Payload
    /// The header the secret goes in, and what comes before it: `Authorization` / `Bearer `.
    public var authHeader: String
    public var authPrefix: String
    /// The form field the video goes in, for `multipart`.
    public var fileField: String
    /// Sent with every delivery: a channel id, a folder, a caption.
    public var fields: [String: String]

    public init(
        isEnabled: Bool = false,
        endpoint: String = "",
        method: Method = .post,
        payload: Payload = .multipart,
        authHeader: String = "Authorization",
        authPrefix: String = "Bearer ",
        fileField: String = "video",
        fields: [String: String] = [:]
    ) {
        self.isEnabled = isEnabled
        self.endpoint = endpoint
        self.method = method
        self.payload = payload
        self.authHeader = authHeader
        self.authPrefix = authPrefix
        self.fileField = fileField
        self.fields = fields
    }

    private enum CodingKeys: String, CodingKey {
        case isEnabled, endpoint, url, method, payload, authHeader, authPrefix, fileField, fields
    }

    /// Lenient like every workflow part: `"url"` for `"endpoint"`, lower-case methods, numbers in
    /// fields.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let fallback = WorkflowDelivery()
        endpoint = (try? c.decodeIfPresent(String.self, forKey: .endpoint))
            ?? (try? c.decodeIfPresent(String.self, forKey: .url)) ?? ""
        isEnabled = (try? c.decodeIfPresent(Bool.self, forKey: .isEnabled)) ?? !endpoint.isEmpty
        method = ((try? c.decodeIfPresent(String.self, forKey: .method)) ?? nil)
            .flatMap { Method(rawValue: $0.uppercased()) } ?? fallback.method
        payload = (try? c.decodeIfPresent(Payload.self, forKey: .payload)) ?? fallback.payload
        authHeader = (try? c.decodeIfPresent(String.self, forKey: .authHeader)) ?? fallback.authHeader
        authPrefix = (try? c.decodeIfPresent(String.self, forKey: .authPrefix)) ?? fallback.authPrefix
        fileField = (try? c.decodeIfPresent(String.self, forKey: .fileField)) ?? fallback.fileField
        if let strings = try? c.decodeIfPresent([String: String].self, forKey: .fields) {
            fields = strings
        } else if let numbers = try? c.decodeIfPresent([String: Double].self, forKey: .fields) {
            fields = numbers.mapValues { String($0) }
        } else {
            fields = [:]
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(isEnabled, forKey: .isEnabled)
        try c.encode(endpoint, forKey: .endpoint)
        try c.encode(method, forKey: .method)
        try c.encode(payload, forKey: .payload)
        try c.encode(authHeader, forKey: .authHeader)
        try c.encode(authPrefix, forKey: .authPrefix)
        try c.encode(fileField, forKey: .fileField)
        try c.encode(fields, forKey: .fields)
    }

    /// The endpoint, when it is one a phone should send a video to: HTTPS, or HTTP to this
    /// network's own machines for testing.
    public var url: URL? {
        let text = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: text), let scheme = url.scheme?.lowercased(), let host = url.host(), !host.isEmpty else { return nil }
        if scheme == "https" { return url }
        if scheme == "http", Self.isLocal(host) { return url }
        return nil
    }

    /// Ready to send: switched on and pointing somewhere valid.
    public var isReady: Bool { isEnabled && url != nil }

    static func isLocal(_ host: String) -> Bool {
        host == "localhost" || host.hasSuffix(".local") || host.hasPrefix("192.168.") || host.hasPrefix("10.") || host == "127.0.0.1"
    }

    /// The header that carries the secret, when there is one.
    public func authorization(secret: String?) -> (name: String, value: String)? {
        guard let secret = secret?.trimmingCharacters(in: .whitespacesAndNewlines), !secret.isEmpty else { return nil }
        let name = authHeader.trimmingCharacters(in: .whitespaces)
        return (name.isEmpty ? "Authorization" : name, authPrefix + secret)
    }
}

/// What a delivery says about the video it carries. Sent as form fields or as the JSON body.
public struct WorkflowDeliveryReport: Hashable, Sendable, Codable {
    public var workflowID: UUID
    public var workflowName: String
    public var projectID: UUID
    public var projectTitle: String
    public var seconds: Double
    public var width: Int
    public var height: Int
    public var frameRate: Int
    public var fileName: String
    public var fileBytes: Int64?
    public var captions: String
    public var createdAt: Date

    public init(
        workflowID: UUID,
        workflowName: String,
        projectID: UUID,
        projectTitle: String,
        seconds: Double,
        width: Int,
        height: Int,
        frameRate: Int,
        fileName: String,
        fileBytes: Int64?,
        captions: String,
        createdAt: Date = .now
    ) {
        self.workflowID = workflowID
        self.workflowName = workflowName
        self.projectID = projectID
        self.projectTitle = projectTitle
        self.seconds = seconds
        self.width = width
        self.height = height
        self.frameRate = frameRate
        self.fileName = fileName
        self.fileBytes = fileBytes
        self.captions = captions
        self.createdAt = createdAt
    }

    /// Flat text fields, snake_case, the way form APIs name them. The user's own fields win.
    public func fields(adding extra: [String: String]) -> [(String, String)] {
        var result: [(String, String)] = [
            ("workflow_id", workflowID.uuidString),
            ("workflow_name", workflowName),
            ("project_id", projectID.uuidString),
            ("title", projectTitle),
            ("duration", String(format: "%.2f", seconds)),
            ("width", String(width)),
            ("height", String(height)),
            ("fps", String(frameRate)),
            ("file_name", fileName),
            ("captions", captions),
            ("created_at", ISO8601DateFormatter().string(from: createdAt)),
        ]
        if let fileBytes { result.append(("file_bytes", String(fileBytes))) }
        let extraKeys = Set(extra.keys)
        result.removeAll { extraKeys.contains($0.0) }
        result += extra.sorted { $0.key < $1.key }.map { ($0.key, $0.value) }
        return result
    }

    /// The same details as a JSON object.
    public func json(adding extra: [String: String]) -> Data {
        var object: [String: String] = [:]
        for (key, value) in fields(adding: extra) { object[key] = value }
        return (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])) ?? Data("{}".utf8)
    }
}

extension WorkflowDefinition {
    /// The workflow's closing step. Every workflow has exactly one, last, switched on.
    public var finalExport: WorkflowStep? {
        steps.last.flatMap { step in
            if case .export = step.kind { step } else { nil }
        }
    }

    /// The delivery of the closing export, if the user set one up.
    public var delivery: WorkflowDelivery? {
        guard case .export(let preset)? = finalExport?.kind else { return nil }
        return preset.delivery
    }

    /// Puts the one export step at the end, and makes it say what the style says.
    ///
    /// Workflows written before the rule, by an AI, or pasted as JSON may have no export, two, or
    /// one in the middle; all of them come out of here with a single enabled export last. The
    /// kept step is the last export found, so its destination and delivery survive.
    public mutating func ensureFinalExport() {
        let exports = steps.filter { if case .export = $0.kind { true } else { false } }
        var closing = exports.last ?? WorkflowStep(kind: .export(.shortFormVertical))
        steps.removeAll { if case .export = $0.kind { true } else { false } }
        if case .export(var preset) = closing.kind {
            preset.format = style.format
            preset.burnsInCaptions = style.captions
            closing.kind = .export(preset)
        }
        closing.isEnabled = true
        steps.append(closing)
    }

    /// A copy with the final export in place.
    public func withFinalExport() -> WorkflowDefinition {
        var copy = self
        copy.ensureFinalExport()
        return copy
    }
}

extension WorkflowStepKind {
    /// The closing export, which cannot be removed, moved or switched off.
    public var isFinalExport: Bool {
        if case .export = self { true } else { false }
    }
}
