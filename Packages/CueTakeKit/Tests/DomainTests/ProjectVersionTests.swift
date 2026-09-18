import Foundation
import Testing
@testable import Domain

struct ProjectVersionTests {
    private func version(_ kind: ProjectVersion.Kind, minutesAgo: Double, now: Date) -> ProjectVersion {
        ProjectVersion(name: "v", kind: kind, savedAt: now.addingTimeInterval(-minutesAgo * 60), seconds: 10, clips: 2)
    }

    @Test func onlyTheOldestAutomaticVersionsPastTheLimitGo() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let automatic = (0..<(ProjectVersion.automaticLimit + 2)).map { version(.automatic, minutesAgo: Double($0), now: now) }
        let manual = version(.manual, minutesAgo: 10_000, now: now)
        let dropped = Set(ProjectVersion.overflow(in: automatic + [manual]))

        #expect(dropped.count == 2)
        // The two oldest automatic ones, never the far older manual one.
        let oldest = Set(automatic.suffix(2).map(\.id))
        #expect(dropped == oldest)
        #expect(!dropped.contains(manual.id))
    }

    @Test func openingTheEditorTwiceInAnHourKeepsOneSafetyCopy() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        #expect(ProjectVersion.wantsAutomatic(since: [], now: now))
        #expect(!ProjectVersion.wantsAutomatic(since: [version(.automatic, minutesAgo: 20, now: now)], now: now))
        #expect(ProjectVersion.wantsAutomatic(since: [version(.automatic, minutesAgo: 90, now: now)], now: now))
        // A version the person saved by hand is not the app's safety copy.
        #expect(ProjectVersion.wantsAutomatic(since: [version(.manual, minutesAgo: 5, now: now)], now: now))
    }

    @Test func aBlankNameBecomesTheTitleAndALongOneIsCut() {
        let project = Project(title: "Kahve Lab", localeIdentifier: "tr-TR", segments: [], recordings: [])
        #expect(ProjectVersion(of: project, name: "   ", kind: .manual).name == "Kahve Lab")
        let long = String(repeating: "a", count: 200)
        #expect(ProjectVersion(of: project, name: long, kind: .manual).name.count == ProjectVersion.longestName)
    }
}
