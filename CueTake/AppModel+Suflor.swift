import AIServices
import AVFoundation
import Domain
import Foundation
import Persistence
import SettingsFeature
import SpeechEngine
import StudioFeature
import SuflorFeature
import UIKit

/// The suflör's lines to the rest of the app: the server that writes its cards, the transcriber
/// that finds the brand's words in a saved stream, and the studio — the cards read on our own
/// teleprompter, the take becoming the report for the brand.
extension AppModel {
    /// Remembers which project the ad's cards were last taken to the studio in.
    static let adProjectKey = "ad.project"

    func startSuflor(returning origin: Screen = .home) {
        let suflor = suflorModel
        suflor.localeIdentifier = project.localeIdentifier
        let client = dependencies.assistantClient
        if client.isConfigured {
            suflor.writer = { [weak self] brief, locale, voice in
                guard let self, self.settingsModel.settings.aiProcessing == .allowCloud else {
                    throw SuflorModel.WriteError.cloudOff
                }
                do {
                    return try await client.writeSuflor(brief, localeIdentifier: locale, voice: voice)
                } catch AssistantClient.AssistantError.offline {
                    throw SuflorModel.WriteError.offline
                } catch AssistantClient.AssistantError.rejected(let status) {
                    throw SuflorModel.WriteError.server(status)
                } catch {
                    throw SuflorModel.WriteError.empty
                }
            }
            suflor.allowCloud = { [weak self] in
                self?.settingsModel.update(\.aiProcessing, to: .allowCloud)
            }
        } else {
            suflor.writer = nil
        }
        suflor.voiceLoader = { [weak self] in await self?.suflorVoiceSample() }
        let speech = dependencies.speech
        let locale = project.localeIdentifier
        suflor.verifier = { url, session in
            try await Self.check(session, recording: url, speech: speech, localeIdentifier: locale)
        }
        suflor.onRecord = { [weak self] plan in self?.recordAd(plan) }
        suflor.reporter = { [weak self] in await self?.adSession() }
        suflor.hasRecording = ownsAdProject && isAdProject && hasAdTake
        if suflor.stage == .report { suflor.leaveReport() }
        adReturn = origin
        go(to: .suflor)
    }

    /// The report for the ad just recorded in the studio, from the screen after the take.
    func openAdReport() {
        startSuflor(returning: screen)
        Task { await suflorModel.openTakeReport() }
    }

    func leaveAd() {
        go(to: adReturn == .suflor ? .home : adReturn)
    }

    /// Whether the open project is an ad recorded in the studio, for the screen after the take.
    var isAdProject: Bool { Self.adBrief(of: project) != nil }

    private var ownsAdProject: Bool {
        UserDefaults.standard.string(forKey: Self.adProjectKey) == project.id.uuidString
    }

    private var hasAdTake: Bool {
        project.segments.contains { $0.metadata[SuflorModel.roleKey] != nil && $0.selectedTake != nil }
    }

    static func adBrief(of project: Project) -> SuflorBrief? {
        project.metadata[SuflorModel.briefKey].flatMap { try? JSONDecoder().decode(SuflorBrief.self, from: Data($0.utf8)) }
    }

    /// The cards to the studio, as the project's script.
    ///
    /// The same ad's project is updated in place while nothing shot would be lost: its segments
    /// are its cards, so a card rewritten after a take keeps the take. Cards written afresh, or a
    /// card with footage taken away, start a new project instead, and the old one stays in the
    /// library as it was.
    func recordAd(_ plan: SuflorPlan) {
        let ids = Set(plan.ordered.map(\.id))
        let shot = project.segments.filter { !$0.takes.isEmpty }
        let continues = ownsAdProject && isAdProject
            && project.segments.contains { ids.contains($0.id) }
            && shot.allSatisfy { ids.contains($0.id) }
        if !continues {
            adopt(Self.blankProject())
            UserDefaults.standard.set(project.id.uuidString, forKey: Self.adProjectKey)
        }
        project.segments = SuflorModel.segments(for: plan, merging: project.segments, localeIdentifier: project.localeIdentifier)
        if let brief = try? JSONEncoder().encode(plan.brief) {
            project.metadata[SuflorModel.briefKey] = String(decoding: brief, as: UTF8.self)
        }
        if project.recordings.isEmpty {
            let name = [plan.brief.brand, plan.brief.product]
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: " · ")
            if !name.isEmpty { project.title = name }
        }
        project.updatedAt = .now
        scheduleSave()
        studioReturn = .suflor
        openStudio()
    }

    /// What the brand asked to hear in the open project, for the prompter to light.
    var adHighlights: [String] {
        Self.adBrief(of: project)?.mustSay ?? []
    }

    /// The ad's checks for the studio: items to tick as they are heard, words to warn about, the
    /// ad's segments and how long it should run. Nil for anything that is not an ad.
    var adChecks: StudioModel.AdChecks? {
        guard let brief = Self.adBrief(of: project) else { return nil }
        let ad = project.segments.filter { segment in
            segment.metadata[SuflorModel.roleKey].flatMap(SuflorCue.Role.init(rawValue:))?.isAd == true
        }
        return StudioModel.AdChecks(items: brief.mustSay, avoid: brief.avoid, adSegments: Set(ad.map(\.id)), adSeconds: brief.adSeconds)
    }

    /// The brand's terms, for the listeners to expect while an ad is recorded.
    var adSpeechHints: [String] {
        Self.adBrief(of: project)?.recognitionTerms ?? []
    }

    /// The creator's speech from their latest videos: the open project first, then the library,
    /// newest first, until there is enough to hear how they talk.
    func suflorVoiceSample() async -> String? {
        var transcripts = Self.transcripts(of: project)
        let others = library
            .filter { $0.id != project.id }
            .sorted { $0.updatedAt > $1.updatedAt }
            .prefix(8)
        for summary in others {
            if SuflorVoice.wordCount(SuflorVoice.sample(from: transcripts)) >= 450 { break }
            guard let other = try? await dependencies.projectStore.load(summary.id) else { continue }
            transcripts += Self.transcripts(of: other)
        }
        return SuflorVoice.sample(from: transcripts)
    }

    private static func transcripts(of project: Project) -> [Transcript] {
        project.segments.flatMap(\.takes).compactMap(\.transcript).filter { !$0.words.isEmpty }
    }

    /// Listens to a saved stream on this phone — told the brand's words first — and fills in every
    /// check of the report, with a frame from each moment.
    nonisolated static func check(_ session: SuflorSession, recording url: URL, speech: any SpeechTranscribing, localeIdentifier: String) async throws -> SuflorSession {
        let hints = session.plan.brief.recognitionTerms
        let transcript = try await speech.transcribeFile(at: url, localeIdentifier: localeIdentifier, hints: hints)
        var checked = session
        checked.check(transcript.words, localeIdentifier: localeIdentifier)
        var frames: [Double: Data] = [:]
        for second in checked.proofSeconds {
            frames[second] = await frame(in: url, at: second + 0.3)
        }
        checked.attachFrames(frames)
        return checked
    }

    // MARK: - Report from a studio take

    /// One stretch of the finished video: which file it comes from and where.
    private struct Piece {
        var start: Double
        var length: Double
        var speed: Double
        var recording: Recording
        var sourceStart: Double
    }

    /// The report's facts, read from the project: the ad's place in the video, from where its
    /// cards were read, and each item the brand asked for, found in what the take heard, with a
    /// frame from that second.
    func adSession() async -> SuflorSession? {
        takeEditorEditsIfEditing()
        guard var brief = Self.adBrief(of: project) else { return nil }
        // Whatever the cards were written for, this one was recorded as a video.
        brief.kind = .video
        // A take not yet heard has no words to find anything in.
        if project.segments.contains(where: { $0.selectedTake != nil && $0.selectedTake?.transcript == nil }) {
            await transcribeNewTakes(quietly: true)
        }
        let project = self.project
        let cues: [SuflorCue] = project.segments.compactMap { segment in
            guard let raw = segment.metadata[SuflorModel.roleKey], let role = SuflorCue.Role(rawValue: raw) else { return nil }
            return SuflorCue(id: segment.id, role: role, text: segment.script)
        }

        var pieces: [Piece] = []
        var words: [TimedWord] = []
        var adStart: Double?
        var adEnd: Double?
        var offset = 0.0
        for segment in project.segments {
            guard let take = segment.selectedTake, let recording = project.recording(id: take.recordingID) else { continue }
            let speed = max(0.25, segment.playback.speed)
            let length = take.sourceRange.duration.seconds / speed
            pieces.append(Piece(start: offset, length: length, speed: speed, recording: recording, sourceStart: take.sourceRange.start.seconds))
            for word in take.transcript?.words ?? [] {
                var moved = word
                moved.range = MediaTimeRange(
                    start: MediaTime(seconds: offset + word.range.start.seconds / speed),
                    duration: MediaTime(seconds: word.range.duration.seconds / speed)
                )
                words.append(moved)
            }
            let role = segment.metadata[SuflorModel.roleKey].flatMap(SuflorCue.Role.init(rawValue:))
            if role?.isAd == true {
                if adStart == nil { adStart = offset }
                adEnd = offset + length
            }
            offset += length
        }
        guard !pieces.isEmpty else { return nil }

        let started = pieces.map(\.recording.createdAt).min() ?? project.createdAt
        var session = SuflorSession(plan: SuflorPlan(brief: brief, cues: cues), startedAt: started)
        session.endedAt = started.addingTimeInterval(offset)
        session.adStartedAt = adStart
        session.adEndedAt = adEnd

        session.check(words, localeIdentifier: project.localeIdentifier)
        if let media = try? await dependencies.projectStore.mediaDirectory(for: project.id) {
            let base = media.deletingLastPathComponent()
            var frames: [Double: Data] = [:]
            for second in session.proofSeconds {
                guard let piece = pieces.last(where: { $0.start <= second + 0.01 }) else { continue }
                let source = piece.sourceStart + (second - piece.start) * piece.speed + 0.3
                frames[second] = await Self.frame(in: base.appending(path: piece.recording.relativePath), at: source)
            }
            session.attachFrames(frames)
        }
        return session
    }

    /// A small still from a file, for the report.
    nonisolated static func frame(in url: URL, at seconds: Double) async -> Data? {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 480, height: 480)
        guard let shot = try? await generator.image(at: CMTime(seconds: max(0, seconds), preferredTimescale: 600)) else { return nil }
        return withExtendedLifetime(asset) { UIImage(cgImage: shot.image).jpegData(compressionQuality: 0.72) }
    }
}
