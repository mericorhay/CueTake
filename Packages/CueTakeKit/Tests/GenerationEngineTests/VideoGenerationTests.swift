import Domain
import Foundation
import Testing
@testable import GenerationEngine

/// A network that answers from a script and remembers what it was asked.
final class ScriptedTransport: HTTPTransport, @unchecked Sendable {
    struct Reply {
        var status: Int
        var json: Any
    }

    private let lock = NSLock()
    private var replies: [(match: String, reply: Reply)]
    private(set) var sent: [URLRequest] = []
    let downloadFile: URL

    init(_ replies: [(String, Reply)]) {
        self.replies = replies.map { (match: $0.0, reply: $0.1) }
        downloadFile = FileManager.default.temporaryDirectory.appending(path: "scripted-\(UUID().uuidString).mp4")
        FileManager.default.createFile(atPath: downloadFile.path(percentEncoded: false), contents: Data("video".utf8))
    }

    var requests: [URLRequest] { lock.withLock { sent } }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let url = request.url!.absoluteString
        let reply: Reply = lock.withLock {
            sent.append(request)
            // The first matching reply is used once, so a poll can answer "working" then "done".
            guard let index = replies.firstIndex(where: { url.contains($0.match) }) else {
                return Reply(status: 404, json: ["error": "unscripted \(url)"])
            }
            let found = replies[index].reply
            if replies.filter({ url.contains($0.match) }).count > 1 { replies.remove(at: index) }
            return found
        }
        let data = try JSONSerialization.data(withJSONObject: reply.json)
        return (data, HTTPURLResponse(url: request.url!, statusCode: reply.status, httpVersion: nil, headerFields: nil)!)
    }

    func download(_ request: URLRequest) async throws -> (URL, HTTPURLResponse) {
        lock.withLock { sent.append(request) }
        let copy = FileManager.default.temporaryDirectory.appending(path: "dl-\(UUID().uuidString).mp4")
        try FileManager.default.copyItem(at: downloadFile, to: copy)
        return (copy, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }
}

private func body(_ request: URLRequest) -> [String: Any] {
    (request.httpBody.flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any]) ?? [:]
}

private let output = FileManager.default.temporaryDirectory.appending(path: "generation-tests", directoryHint: .isDirectory)

struct VideoGenerationTests {
    private func service(_ transport: ScriptedTransport) -> VideoGenerationService {
        VideoGenerationService(transport: transport, pollInterval: .milliseconds(1), timeout: .seconds(5))
    }

    @Test func seedanceOnFalQueuesPollsAndDownloads() async throws {
        let transport = ScriptedTransport([
            ("queue.fal.run/bytedance/seedance-2.5/text-to-video", .init(status: 200, json: [
                "request_id": "r1",
                "status_url": "https://queue.fal.run/bytedance/seedance-2.5/requests/r1/status",
                "response_url": "https://queue.fal.run/bytedance/seedance-2.5/requests/r1/response",
            ])),
            ("/requests/r1/status", .init(status: 200, json: ["status": "IN_PROGRESS"])),
            ("/requests/r1/status", .init(status: 200, json: ["status": "COMPLETED"])),
            ("/requests/r1/response", .init(status: 200, json: ["video": ["url": "https://v3.fal.media/out.mp4"]])),
        ])
        let options = GenerateVideoOptions(preset: "seedance-2.5", seconds: 12.4, aspect: "9:16", resolution: "720p")
        let request = VideoGenerationRequest.fitted(options, prompt: "A cat surfing")
        let file = try await service(transport).generate(request, provider: .fal, key: "fal-key", into: output)

        #expect(FileManager.default.fileExists(atPath: file.path(percentEncoded: false)))
        let submit = transport.requests[0]
        #expect(submit.value(forHTTPHeaderField: "Authorization") == "Key fal-key")
        #expect(body(submit)["duration"] as? String == "12")
        #expect(body(submit)["aspect_ratio"] as? String == "9:16")
        #expect(body(submit)["generate_audio"] as? Bool == true)
        // A public result URL is fetched without the key.
        #expect(transport.requests.last?.value(forHTTPHeaderField: "Authorization") == nil)
    }

    @Test func veoWaitsForTheOperationAndDownloadsWithTheKey() async throws {
        let transport = ScriptedTransport([
            ("veo-3.1-fast-generate-preview:predictLongRunning", .init(status: 200, json: [
                "name": "models/veo-3.1-fast-generate-preview/operations/op1",
            ])),
            ("operations/op1", .init(status: 200, json: ["done": false])),
            ("operations/op1", .init(status: 200, json: [
                "done": true,
                "response": ["generateVideoResponse": ["generatedSamples": [["video": ["uri": "https://generativelanguage.googleapis.com/v1beta/files/f1:download"]]]]],
            ])),
        ])
        let options = GenerateVideoOptions(preset: "veo-3.1-fast", seconds: 10, aspect: "4:5")
        let request = VideoGenerationRequest.fitted(options, prompt: "Sunrise")
        #expect(request.seconds == 8)
        #expect(request.aspect == "9:16")

        _ = try await service(transport).generate(request, provider: .google, key: "g-key", into: output)
        let submit = transport.requests[0]
        #expect(submit.value(forHTTPHeaderField: "x-goog-api-key") == "g-key")
        let parameters = body(submit)["parameters"] as? [String: Any]
        #expect(parameters?["durationSeconds"] as? Int == 8)
        #expect((body(submit)["instances"] as? [[String: Any]])?.first?["prompt"] as? String == "Sunrise")
        #expect(transport.requests.last?.value(forHTTPHeaderField: "x-goog-api-key") == "g-key")
    }

    @Test func soraSendsAFormAndReportsAFailure() async throws {
        let transport = ScriptedTransport([
            ("api.openai.com/v1/videos/vid_1", .init(status: 200, json: [
                "id": "vid_1", "status": "failed", "error": ["message": "Blocked by moderation"],
            ])),
            ("api.openai.com/v1/videos", .init(status: 200, json: ["id": "vid_1", "status": "queued"])),
        ])
        let options = GenerateVideoOptions(preset: "sora-2", seconds: 10, aspect: "9:16")
        let request = VideoGenerationRequest.fitted(options, prompt: "A drone shot")
        await #expect(throws: GenerationError.failed("Blocked by moderation")) {
            _ = try await service(transport).generate(request, provider: .openai, key: "sk-x", into: output)
        }
        let submit = transport.requests[0]
        #expect(submit.value(forHTTPHeaderField: "Content-Type")?.hasPrefix("multipart/form-data") == true)
        let form = String(decoding: submit.httpBody ?? Data(), as: UTF8.self)
        #expect(form.contains("720x1280"))
        #expect(form.contains("name=\"seconds\"\r\n\r\n8\r\n"))
    }

    @Test func replicateRunsAnyModelById() async throws {
        let transport = ScriptedTransport([
            ("api.replicate.com/v1/models/kwaivgi/kling-v2.1/predictions", .init(status: 201, json: [
                "id": "p1", "status": "starting", "urls": ["get": "https://api.replicate.com/v1/predictions/p1"],
            ])),
            ("v1/predictions/p1", .init(status: 200, json: ["status": "succeeded", "output": "https://replicate.delivery/out.mp4"])),
        ])
        let options = GenerateVideoOptions(preset: "replicate-custom", customModel: "kwaivgi/kling-v2.1", seconds: 5)
        let request = VideoGenerationRequest.fitted(options, prompt: "Rain")
        _ = try await service(transport).generate(request, provider: .replicate, key: "r8_x", into: output)
        #expect(body(transport.requests[0])["input"] as? [String: Any] != nil)
        #expect(transport.requests[0].value(forHTTPHeaderField: "Authorization") == "Bearer r8_x")
    }

    @Test func aRefusedKeyIsReported() async {
        let transport = ScriptedTransport([
            ("api.openai.com/v1/videos", .init(status: 401, json: ["error": ["message": "bad key"]])),
            ("api.openai.com/v1/models", .init(status: 401, json: [:])),
        ])
        let request = VideoGenerationRequest.fitted(GenerateVideoOptions(preset: "sora-2"), prompt: "x")
        await #expect(throws: GenerationError.unauthorized) {
            _ = try await service(transport).generate(request, provider: .openai, key: "sk-bad", into: output)
        }
        #expect(await service(transport).verify("sk-bad", for: .openai) == false)
    }

    @Test func aMissingKeyOrModelStopsBeforeTheNetwork() async {
        let transport = ScriptedTransport([])
        let custom = VideoGenerationRequest.fitted(GenerateVideoOptions(preset: "fal-custom"), prompt: "x")
        await #expect(throws: GenerationError.missingModel) {
            _ = try await service(transport).generate(custom, provider: .fal, key: "k", into: output)
        }
        let request = VideoGenerationRequest.fitted(GenerateVideoOptions(), prompt: "x")
        await #expect(throws: GenerationError.missingKey(.fal)) {
            _ = try await service(transport).generate(request, provider: .fal, key: "", into: output)
        }
        #expect(transport.requests.isEmpty)
    }
}

struct GenerateVideoStepTests {
    @Test func aWorkflowWrittenByAModelIsUnderstood() throws {
        let json = #"""
        {"name":"Shorts","steps":[
          {"type":"generateVideo","parameters":{"model":"veo-3.1","prompt":"A city at night","duration":"6","aspect":"9:16"}},
          {"type":"generateVideo","parameters":{"model":"fal-ai/kling-video/v2.1/master/text-to-video","prompts":["a","b"]}}
        ]}
        """#
        let workflow = try JSONDecoder().decode(WorkflowDefinition.self, from: Data(json.utf8))
        guard case .generateVideo(let first) = workflow.steps[0].kind,
              case .generateVideo(let second) = workflow.steps[1].kind
        else {
            Issue.record("steps did not decode")
            return
        }
        #expect(first.preset == "veo-3.1")
        #expect(first.prompts == ["A city at night"])
        #expect(first.seconds == 6)
        #expect(second.preset == "fal-custom")
        #expect(second.resolvedModel == "fal-ai/kling-video/v2.1/master/text-to-video")
        #expect(second.prompts.count == 2)

        let again = try JSONDecoder().decode(WorkflowDefinition.self, from: JSONEncoder().encode(workflow))
        #expect(again.steps.map(\.kind) == workflow.steps.map(\.kind))
    }

    @Test func settingsAreFittedToTheModel() {
        let sora = VideoModelPreset.preset(id: "sora-2-pro")
        #expect(sora.duration(nearest: 30) == 12)
        #expect(sora.aspect(nearest: "1:1") == "9:16" || sora.aspect(nearest: "1:1") == "16:9")
        #expect(sora.resolution(nearest: "4k") == "1080p")
        #expect(OpenAISoraGenerator.size(aspect: "9:16", resolution: "1080p", model: "sora-2-pro") == "1024x1792")
        #expect(OpenAISoraGenerator.size(aspect: "16:9", resolution: "1080p", model: "sora-2") == "1280x720")
    }
}
