import Domain
import Foundation

/// Sends a workflow's finished video to the endpoint the user set up for that workflow.
///
/// The body is written to a file first and uploaded from it, so a two-hundred-megabyte 4K video
/// never sits in memory.
public struct WorkflowDeliveryClient: Sendable {
    public struct Outcome: Sendable, Equatable {
        public var status: Int
        /// The start of what the server answered, for the user to read.
        public var reply: String
        public var succeeded: Bool { (200..<300).contains(status) }
    }

    public enum DeliveryError: Error, Equatable, Sendable {
        case invalidEndpoint
        case missingFile
        case rejected(status: Int, reply: String)
        case transport(String)
    }

    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    /// Sends the video (or only its details, for a JSON delivery).
    public func deliver(
        _ delivery: WorkflowDelivery,
        video: URL?,
        report: WorkflowDeliveryReport,
        secret: String?,
        idempotencyKey: String? = nil
    ) async throws -> Outcome {
        guard let url = delivery.url else { throw DeliveryError.invalidEndpoint }
        var request = URLRequest(url: url, timeoutInterval: 600)
        request.httpMethod = delivery.method.rawValue
        request.setValue("CueTake", forHTTPHeaderField: "User-Agent")
        if let idempotencyKey, !idempotencyKey.isEmpty {
            request.setValue(idempotencyKey, forHTTPHeaderField: "Idempotency-Key")
        }
        if let auth = delivery.authorization(secret: secret) {
            request.setValue(auth.value, forHTTPHeaderField: auth.name)
        }

        let body: URL
        var ownsBody = true
        switch delivery.payload {
        case .json:
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            body = try Self.temporaryFile(delivery.payload)
            try report.json(adding: delivery.fields).write(to: body)
        case .rawVideo:
            guard let video, FileManager.default.fileExists(atPath: video.path) else { throw DeliveryError.missingFile }
            request.setValue(Self.mimeType(for: video), forHTTPHeaderField: "Content-Type")
            // Details travel as headers when the body is the file itself.
            request.setValue(Self.headerSafe(report.fileName), forHTTPHeaderField: "X-CueTake-File-Name")
            request.setValue(report.workflowID.uuidString, forHTTPHeaderField: "X-CueTake-Workflow")
            body = video
            ownsBody = false
        case .multipart:
            guard let video, FileManager.default.fileExists(atPath: video.path) else { throw DeliveryError.missingFile }
            let boundary = "CueTake-\(UUID().uuidString)"
            request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
            body = try Self.temporaryFile(delivery.payload)
            try Self.writeMultipart(
                to: body,
                boundary: boundary,
                fields: report.fields(adding: delivery.fields),
                fileField: delivery.fileField.isEmpty ? "video" : delivery.fileField,
                file: video,
                fileName: report.fileName
            )
        }
        defer { if ownsBody { try? FileManager.default.removeItem(at: body) } }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.upload(for: request, fromFile: body)
        } catch {
            throw DeliveryError.transport(error.localizedDescription)
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let reply = String(decoding: data.prefix(300), as: UTF8.self)
        guard (200..<300).contains(status) else { throw DeliveryError.rejected(status: status, reply: reply) }
        return Outcome(status: status, reply: reply)
    }

    /// A small JSON request marked as a test, for the button beside the settings.
    public func test(_ delivery: WorkflowDelivery, workflow: WorkflowDefinition, secret: String?) async throws -> Outcome {
        var probe = delivery
        probe.payload = .json
        probe.fields["test"] = "true"
        let format = workflow.style.format
        let size = format.renderSize
        let report = WorkflowDeliveryReport(
            workflowID: workflow.id,
            workflowName: workflow.name,
            projectID: UUID(),
            projectTitle: "CueTake test",
            seconds: 0,
            width: size.width,
            height: size.height,
            frameRate: format.frameRate,
            fileName: "test.mov",
            fileBytes: nil,
            captions: ""
        )
        return try await deliver(probe, video: nil, report: report, secret: secret)
    }

    // MARK: - Body

    static func temporaryFile(_ payload: WorkflowDelivery.Payload) throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appending(path: "deliveries", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appending(path: "\(UUID().uuidString).\(payload.rawValue)", directoryHint: .notDirectory)
    }

    static func mimeType(for file: URL) -> String {
        switch file.pathExtension.lowercased() {
        case "mp4", "m4v": "video/mp4"
        default: "video/quicktime"
        }
    }

    static func headerSafe(_ text: String) -> String {
        String(String.UnicodeScalarView(text.unicodeScalars.filter { $0.isASCII && $0.value >= 32 && $0.value != 34 }))
    }

    /// Fields, then the file, copied from disk a megabyte at a time.
    static func writeMultipart(
        to destination: URL,
        boundary: String,
        fields: [(String, String)],
        fileField: String,
        file: URL,
        fileName: String
    ) throws {
        let crlf = String(decoding: [13, 10], as: UTF8.self)
        FileManager.default.createFile(atPath: destination.path, contents: nil)
        let output = try FileHandle(forWritingTo: destination)
        defer { try? output.close() }

        func write(_ text: String) throws { try output.write(contentsOf: Data(text.utf8)) }

        for (name, value) in fields {
            try write("--" + boundary + crlf)
            try write("Content-Disposition: form-data; name=\"" + escaped(name) + "\"" + crlf + crlf)
            try write(value + crlf)
        }
        try write("--" + boundary + crlf)
        try write("Content-Disposition: form-data; name=\"" + escaped(fileField) + "\"; filename=\"" + escaped(fileName) + "\"" + crlf)
        try write("Content-Type: " + mimeType(for: file) + crlf + crlf)
        let input = try FileHandle(forReadingFrom: file)
        defer { try? input.close() }
        while let chunk = try input.read(upToCount: 1 << 20), !chunk.isEmpty {
            try output.write(contentsOf: chunk)
        }
        try write(crlf + "--" + boundary + "--" + crlf)
    }

    private static func escaped(_ text: String) -> String {
        String(String.UnicodeScalarView(text.unicodeScalars.filter { $0.value >= 32 }))
            .replacingOccurrences(of: "\"", with: "%22")
    }
}
