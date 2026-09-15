import Foundation
import Testing
@testable import Domain
@testable import EditorFeature

@MainActor
struct SegmentReorderTests {
    private func model() -> EditorModel {
        let segments = ["1", "2", "3", "4"].map {
            Segment(role: .mainPoint, title: $0, script: "Segment \($0)")
        }
        return EditorModel(project: Project(title: "t", localeIdentifier: "en", segments: segments))
    }

    @Test func swappingFirstAndThirdKeepsTheMiddleAndEndInPlace() {
        let model = model()

        model.swapSegments(at: 0, with: 2)

        #expect(model.project.segments.map(\.title) == ["3", "2", "1", "4"])
        model.undo()
        #expect(model.project.segments.map(\.title) == ["1", "2", "3", "4"])
    }

    @Test func movingIntoAGapShiftsTheClipsBetweenTheTwoPositions() {
        let model = model()

        model.move(segmentAt: 0, to: 2)

        #expect(model.project.segments.map(\.title) == ["2", "3", "1", "4"])
    }

    @Test func automaticRolesApplyOnceAndRespectManualChoices() {
        var hook = Segment(role: .mainPoint, title: "1", script: "Bunu herkes yanlış yapıyor. Nedenini şimdi göstereyim.")
        hook.metadata["roleAssignment"] = "manual"
        let cta = Segment(role: .mainPoint, title: "2", script: "Devamı için takip et ve kaydet.")
        let model = EditorModel(
            project: Project(title: "t", localeIdentifier: "tr", segments: [hook, cta])
        )

        let changed = model.autoAssignSegmentRoles()

        #expect(changed == 1)
        #expect(model.project.segments[0].role == .mainPoint)
        #expect(model.project.segments[1].role == .callToAction)
        #expect(model.project.segments[1].metadata["roleAssignment"] == "automatic")
        model.undo()
        #expect(model.project.segments.map(\.role) == [.mainPoint, .mainPoint])
    }
}
