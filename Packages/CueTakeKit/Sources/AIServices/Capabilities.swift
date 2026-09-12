import Domain
import Foundation

// One protocol per AICapability. Inputs and outputs are Domain types, so features never see
// provider-specific request formats.

/// `.scriptWriting`: brief → script. Streams partial drafts so segments appear as they are written.
public protocol ScriptWriting: AIProvider {
    func writeScript(_ brief: ScriptBrief, localeIdentifier: String) -> AsyncThrowingStream<ScriptDraft, any Error>
}

/// `.scriptSegmentation`: a pasted or hand-written script → segments with roles.
public protocol ScriptSegmenting: AIProvider {
    func segment(script: String, localeIdentifier: String) async throws -> [SegmentDraft]
}

/// `.speechAlignment`: post-recording alignment of what was said to the script.
/// Used to split a continuous take into per-segment takes.
public protocol SpeechAligning: AIProvider {
    func align(_ transcript: Transcript, to segments: [Segment]) async throws -> [SegmentAlignment]
}

public struct SegmentAlignment: Hashable, Sendable {
    public var segmentID: Segment.ID
    /// In the transcript's time base.
    public var range: MediaTimeRange
    public var confidence: Double

    public init(segmentID: Segment.ID, range: MediaTimeRange, confidence: Double) {
        self.segmentID = segmentID
        self.range = range
        self.confidence = confidence
    }
}

/// `.captionGeneration`: transcript → caption cues (line breaking, emphasis, cleanup).
public protocol CaptionGenerating: AIProvider {
    func captions(for transcript: Transcript, style: CaptionStyle) async throws -> [CaptionCue]
}

/// `.videoAnalysis`: flags problems worth a retake.
public protocol VideoAnalyzing: AIProvider {
    func analyze(recordingAt url: URL, transcript: Transcript?) async throws -> VideoAnalysisReport
}

public struct VideoAnalysisReport: Hashable, Sendable {
    public struct Finding: Hashable, Sendable {
        public enum Kind: String, Hashable, Sendable {
            case fillerWord
            case longPause
            case offScript
            case lookedAway
            case lowAudio
        }

        public var kind: Kind
        public var range: MediaTimeRange
        public var note: String?

        public init(kind: Kind, range: MediaTimeRange, note: String? = nil) {
            self.kind = kind
            self.range = range
            self.note = note
        }
    }

    public var findings: [Finding]

    public init(findings: [Finding]) {
        self.findings = findings
    }
}

/// `.workflowAI`: "make me a workflow for product videos" → workflow definition.
public protocol WorkflowAssisting: AIProvider {
    func draftWorkflow(from prompt: String, localeIdentifier: String) async throws -> WorkflowDefinition
}
