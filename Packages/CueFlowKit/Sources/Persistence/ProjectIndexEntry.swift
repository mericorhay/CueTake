import Foundation
import SwiftData

/// Library index row. Rebuildable from the project documents at any time,
/// so it can be dropped and recreated instead of migrated.
@Model
public final class ProjectIndexEntry {
    @Attribute(.unique) public var projectID: UUID
    public var title: String
    public var updatedAt: Date
    public var segmentCount: Int

    public init(summary: ProjectSummary) {
        self.projectID = summary.id
        self.title = summary.title
        self.updatedAt = summary.updatedAt
        self.segmentCount = summary.segmentCount
    }
}
