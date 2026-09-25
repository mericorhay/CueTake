import AVFoundation
import DesignSystem
import Domain
import Foundation
import MediaEngine
import SwiftUI

/// One round of the AI editor with the server: the conversation so far in, the model's next move out.
public typealias AIAgentRequester = (AgentRequest) async throws -> AgentReply

/// The AI editor working in rounds.
///
/// The old way was one answer written blind: the whole video as text, a list of changes back, one
/// more look afterwards. Here the model has tools and a few rounds. It sees the video (a sheet of
/// pictures at the start, closer looks when it asks), makes changes with the same operations as
/// before, and gets back what landed, what was refused and why, what looks wrong — a title on the
/// captions, two texts on top of each other — with pictures of what it changed and the video as it
/// now is. It fixes what it sees and says when it is finished.
///
/// On the way it says in a sentence what it is doing, asks the user when a wrong guess would waste
/// the edit, saves preferences the user states for every later video (`AIMemory`), and ends with
/// what the user might ask next, one tap each.
///
/// Every tool runs here, on the editor, with the live run the user already knows: the timeline
/// travels, the change lands and lights up, and each round's changes can be taken back like any
/// other AI change. The server only holds the key and the prompt.
extension EditorModel {
    /// Rounds the model gets: enough to look, change, check and fix twice.
    static let agentRounds = 8
    /// Pictures one look can ask for.
    static let agentLookLimit = 6

    enum AgentOutcome: Equatable {
        /// The run happened, whatever came of it.
        case done
        /// The server could not start it; nothing was changed.
        case unavailable
    }

    func runAgent(_ instruction: String, using agent: @escaping AIAgentRequester) async -> AgentOutcome {
        var document = await seenDocument(of: project)
        document.videoModel = aiVideoModel
        let sheet = await agentSheet()
        guard !Task.isCancelled else { return .done }

        var turns: [AgentTurn] = []
        var counts: (applied: Int, skipped: Int) = (0, 0)
        var summary = ""

        rounds: for round in 0..<Self.agentRounds {
            if round > 0 { setAgentActivity(.planning) }
            let reply: AgentReply
            do {
                reply = try await agent(AgentRequest(
                    instruction: instruction, document: document, sheet: sheet, turns: turns,
                    memory: AIMemory.facts.isEmpty ? nil : AIMemory.facts
                ))
            } catch {
                guard !Task.isCancelled else { return .done }
                // Nothing changed yet: the old way takes over. Otherwise what landed stays.
                if counts.applied == 0 {
                    withAnimation(.snappy(duration: 0.3)) {
                        aiSession?.activity = nil
                        aiSession?.note = nil
                        aiSession?.question = nil
                        aiSession?.suggestions = []
                    }
                    return .unavailable
                }
                break rounds
            }
            guard !Task.isCancelled else { return .done }
            guard !reply.calls.isEmpty else {
                if let text = reply.text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty, summary.isEmpty {
                    summary = text
                }
                break rounds
            }

            if let note = reply.text?.trimmingCharacters(in: .whitespacesAndNewlines), !note.isEmpty {
                withAnimation(.snappy(duration: 0.3)) { aiSession?.note = String(note.prefix(160)) }
            }
            turns.append(.assistant(reply.text, calls: reply.calls))
            var results: [AgentResult] = []
            var images: [AgentImage] = []
            var finished = false
            var appliedThisRound = false
            for call in reply.calls {
                guard !Task.isCancelled else { return .done }
                switch call.name {
                case "look":
                    let (result, pictures) = await agentLook(call)
                    results.append(result)
                    images += pictures
                case "apply" where appliedThisRound:
                    // Written against the document before the first apply, whose ids that one changed.
                    results.append(AgentResult(id: call.id, text: "Not done: only one apply per round, because ids and times change after each. Send it again with the newest document's ids."))
                case "apply":
                    appliedThisRound = true
                    let (result, pictures, total) = await agentApply(call, instruction: instruction, carrying: counts)
                    results.append(result)
                    images += pictures
                    counts = total
                case "ask":
                    results.append(AgentResult(id: call.id, text: await agentAsk(call)))
                case "remember":
                    results.append(AgentResult(id: call.id, text: agentRemember(call)))
                case "finish":
                    let ending = Self.agentEnding(of: call)
                    summary = ending.summary ?? summary
                    withAnimation(.snappy(duration: 0.3)) { aiSession?.suggestions = ending.next }
                    finished = true
                    results.append(AgentResult(id: call.id, text: "Finished."))
                default:
                    results.append(AgentResult(id: call.id, text: "There is no tool called \(call.name). The tools are look, apply, ask, remember and finish."))
                }
            }
            turns = Self.agentTrimmed(turns, keepingDocument: !results.contains { $0.document != nil }, keepingImages: images.isEmpty)
            turns.append(.tool(results, images: images))
            if finished { break rounds }
        }
        guard !Task.isCancelled else { return .done }

        withAnimation(.spring(response: 0.5, dampingFraction: 0.72)) {
            aiSession?.activity = nil
            aiSession?.note = nil
            if counts.applied > 0 || aiSession?.remembered.isEmpty == false {
                if !summary.isEmpty { aiSession?.summary = summary }
                aiSession?.phase = .finished(applied: counts.applied, skipped: counts.skipped)
            } else {
                aiSession?.phase = .failed(
                    summary.isEmpty
                        ? AppLocalization.string("editor.ai.nothing", bundle: .module)
                        : AppLocalization.string("editor.ai.nothingDone \(summary)", bundle: .module)
                )
            }
        }
        return .done
    }

    // MARK: - Tools

    /// Pictures of the finished video at the moments the model asked for.
    private func agentLook(_ call: AgentCall) async -> (AgentResult, [AgentImage]) {
        struct Input: Decodable { var at: [Double]? }
        let asked = (try? JSONDecoder().decode(Input.self, from: Data(call.input.utf8)))?.at ?? []
        let times = asked.prefix(Self.agentLookLimit).map { min(max(0, $0), max(0, duration - 0.05)) }
        guard !times.isEmpty else {
            return (AgentResult(id: call.id, text: "No moments given: send {\"at\":[seconds,…]}."), [])
        }
        setAgentActivity(.looking)
        // The playhead goes where the AI is looking, so the user sees it too.
        seek(to: times[0])
        let frames = await agentFrames(times)
        guard !frames.isEmpty else {
            return (AgentResult(id: call.id, text: "No picture could be made: this video has no footage to show yet. Work from the document."), [])
        }
        let list = frames.map { Self.agentNumber($0.seconds) }.joined(separator: ", ")
        return (
            AgentResult(id: call.id, text: "Pictures attached, in order, at \(list) s."),
            frames.map { AgentImage(jpeg: $0.jpeg.base64EncodedString(), at: [$0.seconds]) }
        )
    }

    /// Carries out operations live, then says what came of them: what landed, what was refused and
    /// why, what looks wrong, pictures of what changed, and the video as it now is.
    private func agentApply(
        _ call: AgentCall,
        instruction: String,
        carrying earlier: (applied: Int, skipped: Int)
    ) async -> (AgentResult, [AgentImage], (applied: Int, skipped: Int)) {
        guard let raw = try? EditPlan.decode(from: call.input) else {
            return (AgentResult(id: call.id, text: "Could not read that: send {\"summary\":\"…\",\"operations\":[…]}."), [], earlier)
        }
        var notes: [String] = []
        let guarded = raw.keepingCaptions(unlessAskedIn: instruction)
        if guarded.operations.count < raw.operations.count {
            notes.append("\(raw.operations.count - guarded.operations.count) caption operation(s) refused: the user did not ask about the captions' words.")
        }
        let plan = withoutRepeats(guarded)
        if plan.operations.count < guarded.operations.count {
            notes.append("\(guarded.operations.count - plan.operations.count) operation(s) left out: the same title or look is already there.")
        }
        let (steps, skipped) = aiSteps(for: plan.resolvingReferences(in: project))
        if !skipped.isEmpty {
            notes.append("Not done, they named something that is not there or not allowed: \(skipped.joined(separator: ", ")). Use ids from the latest document.")
        }
        guard !steps.isEmpty else {
            return (AgentResult(id: call.id, text: (["Nothing changed."] + notes).joined(separator: " ")), [], earlier)
        }

        let before = project
        setAgentActivity(nil)
        await drive(plan, carrying: earlier)
        var total = earlier
        if case .finished(let applied, let skippedCount)? = aiSession?.phase {
            total = (applied, skippedCount)
        }
        // Stopped during the run: it ended itself, showing what landed.
        guard !Task.isCancelled else { return (AgentResult(id: call.id, text: "Stopped."), [], total) }
        // Between rounds the AI is thinking again; the change set of this round is kept.
        withAnimation(.snappy(duration: 0.3)) { aiSession?.phase = .thinking }

        setAgentActivity(.looking)
        let pictures = await agentPictures(ofChangesSince: before)
        let warnings = agentWarnings()
        var document = await seenDocument(of: project)
        document.videoModel = aiVideoModel

        var text = ["Applied \(total.applied - earlier.applied) change(s)."] + notes
        if !warnings.isEmpty { text.append("Check these: " + warnings.joined(separator: " ")) }
        if !pictures.isEmpty {
            text.append("Pictures of what changed are attached, at \(pictures.map { Self.agentNumber($0.at.first ?? 0) }.joined(separator: ", ")) s.")
        }
        text.append("The video now is the document below: its ids and times replace the earlier ones.")
        return (AgentResult(id: call.id, text: text.joined(separator: " "), document: document), pictures, total)
    }

    /// Shows the AI's question and waits for a tap. Stopping the AI answers it with nothing.
    private func agentAsk(_ call: AgentCall) async -> String {
        struct Input: Decodable {
            var question: String?
            var options: [String]?
        }
        let input = try? JSONDecoder().decode(Input.self, from: Data(call.input.utf8))
        let text = input?.question?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let options = (input?.options ?? [])
            .map { String($0.trimmingCharacters(in: .whitespacesAndNewlines).prefix(60)) }
            .filter { !$0.isEmpty }
            .prefix(4)
        guard !text.isEmpty else { return "No question given. Decide yourself." }
        setAgentActivity(nil)
        withAnimation(.snappy(duration: 0.3)) {
            aiSession?.question = AIQuestion(text: String(text.prefix(200)), options: Array(options))
        }
        let answer: String? = await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                if Task.isCancelled {
                    continuation.resume(returning: nil)
                } else {
                    aiQuestionReply = continuation
                }
            }
        } onCancel: {
            Task { @MainActor [weak self] in self?.answerAIQuestion(nil) }
        }
        withAnimation(.snappy(duration: 0.3)) { aiSession?.question = nil }
        guard let answer, !answer.isEmpty else {
            return "The user left it to you: decide yourself and do not ask again."
        }
        return "The user answered: \(answer)"
    }

    /// Answers the AI's question; nil leaves the choice to the AI.
    public func answerAIQuestion(_ answer: String?) {
        guard let reply = aiQuestionReply else { return }
        aiQuestionReply = nil
        reply.resume(returning: answer)
    }

    private func agentRemember(_ call: AgentCall) -> String {
        struct Input: Decodable { var fact: String? }
        guard let fact = (try? JSONDecoder().decode(Input.self, from: Data(call.input.utf8)))?.fact,
              let kept = AIMemory.remember(fact)
        else { return "Nothing to remember was given." }
        withAnimation(.snappy(duration: 0.3)) { aiSession?.remembered.append(kept) }
        return "Saved for this creator's later videos."
    }

    // MARK: - Pictures

    /// The player's item once it shows the edit as it is now. The editor does not rebuild the
    /// preview while the AI works, so the AI rebuilds it for itself before it looks.
    private func agentPlayerItem() async -> AVPlayerItem? {
        guard let mediaDirectory else { return nil }
        // Looks, people-behind titles and keyed videos are read live by the compositor.
        syncLiveFilters()
        syncLiveBehind()
        syncLiveKeys()
        if !isPictureCurrent {
            await loadPlayback(mediaDirectory: mediaDirectory, cleanVoiceNow: false)
        }
        // Another build may have been under way and taken over: wait for it, a few seconds at most.
        for _ in 0..<15 where !isPictureCurrent && !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(200))
        }
        return player?.currentItem
    }

    private func agentFrames(_ times: [Double]) async -> [VideoGlimpse.Frame] {
        guard let item = await agentPlayerItem(), let mediaDirectory else { return [] }
        return await VideoGlimpse.frames(
            asset: item.asset,
            videoComposition: item.videoComposition,
            project: project,
            mediaDirectory: mediaDirectory,
            at: times
        )
    }

    private func agentSheet() async -> AgentImage? {
        guard let item = await agentPlayerItem(), let mediaDirectory,
              let sheet = await VideoGlimpse.sheet(
                  asset: item.asset,
                  videoComposition: item.videoComposition,
                  project: project,
                  mediaDirectory: mediaDirectory,
                  duration: duration
              )
        else { return nil }
        return AgentImage(jpeg: sheet.jpeg.base64EncodedString(), at: sheet.times)
    }

    /// Pictures of up to three things a round changed that can be seen: new or moved text and
    /// pictures first, else the new caption look, else a new look on the picture.
    private func agentPictures(ofChangesSince before: Project) async -> [AgentImage] {
        var times: [Double] = []
        for overlay in project.overlays where !before.overlays.contains(overlay) {
            times.append(overlay.start.seconds + min(0.6, overlay.duration.seconds / 2))
        }
        if times.isEmpty, project.captionStyle != before.captionStyle, let cue = project.captionCues.first {
            times.append(cue.range.start.seconds + min(0.3, cue.range.duration.seconds / 2))
        }
        if times.isEmpty, let effect = project.effects.first(where: { !before.effects.contains($0) }) {
            times.append(effect.start.seconds + min(0.5, effect.duration.seconds / 2))
        }
        let moments = times.sorted().prefix(3).map { min(max(0, $0), max(0, duration - 0.05)) }
        guard !moments.isEmpty else { return [] }
        return await agentFrames(Array(moments)).map { AgentImage(jpeg: $0.jpeg.base64EncodedString(), at: [$0.seconds]) }
    }

    // MARK: - Checking

    /// What looks wrong on screen after a round, in the document's names: text on the captions,
    /// text at the edge of the frame, two texts in the same place at the same time.
    func agentWarnings() -> [String] {
        let cues = project.captionCues
        let captionY = project.captionStyle.position.y
        let texts = project.overlays.enumerated().filter { $0.element.isText }
        var warnings: [String] = []
        for (n, item) in texts.enumerated() {
            let overlay = item.element
            let name = "o\(item.offset + 1)"
            let from = overlay.start.seconds
            let to = from + overlay.duration.seconds
            let y = overlay.transform.y
            if y < 0.08 || y > 0.92 {
                warnings.append("\(name) is at the edge of the frame (y \(Self.agentNumber(y))); keep text between 0.1 and 0.9.")
            }
            if abs(y - captionY) < 0.1,
               cues.contains(where: { $0.range.start.seconds < to && from < $0.range.end.seconds }) {
                warnings.append("\(name) sits on the captions (y \(Self.agentNumber(y)), captions at \(Self.agentNumber(captionY))) during \(Self.agentNumber(from))–\(Self.agentNumber(to)) s.")
            }
            for other in texts.dropFirst(n + 1) {
                let start = other.element.start.seconds
                let end = start + other.element.duration.seconds
                guard start < to, from < end,
                      abs(other.element.transform.y - y) < 0.1,
                      abs(other.element.transform.x - overlay.transform.x) < 0.3
                else { continue }
                warnings.append("\(name) and o\(other.offset + 1) are on screen in the same place during \(Self.agentNumber(max(from, start)))–\(Self.agentNumber(min(to, end))) s.")
            }
        }
        return Array(warnings.prefix(8))
    }

    // MARK: - Conversation

    /// Keeps each round small: earlier versions of the video and earlier pictures are dropped once
    /// newer ones follow. What each call did is still said.
    static func agentTrimmed(_ turns: [AgentTurn], keepingDocument: Bool, keepingImages: Bool) -> [AgentTurn] {
        turns.map { turn in
            var turn = turn
            if !keepingDocument, let results = turn.results {
                turn.results = results.map { result in
                    guard result.document != nil else { return result }
                    var kept = result
                    kept.document = nil
                    kept.text += " (The document from this point is left out: a newer one follows.)"
                    return kept
                }
            }
            if !keepingImages, turn.images != nil {
                turn.images = nil
                turn.results = turn.results?.map { result in
                    var kept = result
                    kept.text += " (Its pictures were seen and are left out now.)"
                    return kept
                }
            }
            return turn
        }
    }

    /// The summary `finish` gave, and up to three things to ask next.
    static func agentEnding(of call: AgentCall) -> (summary: String?, next: [String]) {
        struct Input: Decodable {
            var summary: String?
            var next: [String]?
        }
        let input = try? JSONDecoder().decode(Input.self, from: Data(call.input.utf8))
        let summary = input?.summary?.trimmingCharacters(in: .whitespacesAndNewlines)
        let next = (input?.next ?? [])
            .map { String($0.trimmingCharacters(in: .whitespacesAndNewlines).prefix(80)) }
            .filter { !$0.isEmpty }
        return (summary?.isEmpty == false ? summary : nil, Array(next.prefix(3)))
    }

    static func agentNumber(_ value: Double) -> String {
        String(format: "%.2f", value)
            .replacingOccurrences(of: #"\.?0+$"#, with: "", options: .regularExpression)
    }

    private func setAgentActivity(_ activity: AIActivity?) {
        guard aiSession?.activity != activity else { return }
        withAnimation(.snappy(duration: 0.3)) { aiSession?.activity = activity }
    }
}
