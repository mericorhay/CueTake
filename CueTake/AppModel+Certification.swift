import AIServices
import Domain
import EditorFeature
import Foundation
import StudioFeature
import UIKit

/// Counting toward the certificates: active time, finished projects, workflow runs and the tasks
/// projects show were done. Kept on the phone; signed by the server when one is earned.
extension AppModel {
    static let certificationKey = "certification.v1"

    static func loadCertification() -> CertificationProgress {
        guard let data = UserDefaults.standard.data(forKey: certificationKey),
              let saved = try? JSONDecoder().decode(CertificationProgress.self, from: data)
        else { return CertificationProgress() }
        return saved
    }

    func saveCertification() {
        if let data = try? JSONEncoder().encode(certification) {
            UserDefaults.standard.set(data, forKey: Self.certificationKey)
        }
    }

    /// Screens where the time is work: making, not browsing.
    private static let workingScreens: Set<Screen> = [.editor, .studio, .retake, .captions, .export, .workflowDetail]

    /// Ticks every half minute for as long as the app runs.
    func startCertificationClock() {
        guard certificationClock == nil else { return }
        certificationClock = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                self?.tickCertification()
            }
        }
    }

    func tickCertification() {
        let now = Date.now
        let working = UIApplication.shared.applicationState == .active && Self.workingScreens.contains(screen)
        if working {
            // Work shows itself: an edit in the last two minutes, a video playing, a take rolling.
            let edited = now.timeIntervalSince(editorModel.project.updatedAt) <= CertificationProgress.idleLimit
            if edited || editorModel.isPlaying || studioModel.phase == .recording || workflowRunTask != nil {
                certification.noteActivity(at: now)
            }
        }
        certification.tick(at: now, working: working)
        if screen == .editor { certification.observe(editorModel.project, at: now) }
        announce(certification.award(at: now))
        saveCertification()
    }

    /// A project was exported: it counts as finished, once.
    func noteCertifiedExport(of project: Project) {
        certification.noteFinished(project: project.id)
        certification.observe(project, at: .now)
        announce(certification.award(at: .now))
        saveCertification()
    }

    func noteCertifiedWorkflowRun() {
        certification.noteWorkflowRun(at: .now)
        announce(certification.award(at: .now))
        saveCertification()
    }

    func noteCertifiedVersion() {
        certification.complete(.namedVersion, at: .now)
        saveCertification()
    }

    func setCertificateName(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        certification.holderName = trimmed.isEmpty ? nil : String(trimmed.prefix(60))
        saveCertification()
    }

    /// Has the server sign an earned certificate. Nil when it did; otherwise what to say.
    func signCertificate(_ level: CertificationLevel) async -> String? {
        guard let id = certification.certificateID(for: level) else {
            return String(localized: "cert.error.notEarned")
        }
        let request = AssistantClient.CertificateRequest(
            level: level,
            id: id,
            name: certification.holderName ?? "",
            progress: certification
        )
        do {
            let signed = try await dependencies.assistantClient.certify(request)
            certification.signed[level] = signed
            saveCertification()
            return nil
        } catch AssistantClient.AssistantError.rejected(let status) where status == 422 {
            return String(localized: "cert.error.refused")
        } catch AssistantClient.AssistantError.rejected(let status) where status == 501 {
            return String(localized: "cert.error.notReady")
        } catch {
            return String(localized: "cert.error.offline")
        }
    }

    private func announce(_ levels: [CertificationLevel]) {
        guard let level = levels.last else { return }
        let title = switch level {
        case .creator: "CueTake Creator"
        case .advancedCreator: "CueTake Advanced Creator"
        case .workflowSpecialist: "CueTake Workflow Specialist"
        }
        show(notice: String(localized: "cert.earned \(title)"))
    }

    /// For the settings row: where the creator stands.
    var certificationSummary: String {
        if let next = certification.next {
            let standing = certification.standing(for: next)
            return String(localized: "cert.summary \(Int((standing.fraction * 100).rounded()))")
        }
        return String(localized: "cert.summary.all")
    }
}
