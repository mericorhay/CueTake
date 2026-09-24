import DesignSystem
import Domain
import Foundation
import SuflorFeature
import SwiftUI

/// Every suflör report, kept on the phone whatever the plan: the brand's proof is worth having
/// later, and CueTake+ opens the ones made before it was bought.
enum SuflorReportStore {
    private static var folder: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appending(path: "SuflorReports", directoryHint: .isDirectory)
    }

    /// One file per stream, named by when it started, so a report read again replaces itself.
    private static func file(for session: SuflorSession) -> URL {
        folder.appending(path: "\(Int(session.startedAt.timeIntervalSince1970 * 1000)).json", directoryHint: .notDirectory)
    }

    static func save(_ session: SuflorSession) {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(session) else { return }
        try? data.write(to: file(for: session), options: .atomic)
    }

    /// Newest first.
    static func all() -> [SuflorSession] {
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        return files
            .filter { $0.pathExtension == "json" }
            .compactMap { try? JSONDecoder().decode(SuflorSession.self, from: Data(contentsOf: $0)) }
            .sorted { $0.startedAt > $1.startedAt }
    }

    /// How many are kept, without reading them: each can carry frames from the stream.
    static func count() -> Int {
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.pathExtension == "json" }.count
    }

    static func delete(_ session: SuflorSession) {
        try? FileManager.default.removeItem(at: file(for: session))
    }
}

extension AppModel {
    /// The suflör keeps each report, and opens it only on CueTake+.
    func connectSuflorReports() {
        let suflor = suflorModel
        suflor.reportSaver = { [weak self] session in
            SuflorReportStore.save(session)
            self?.suflorReportCount = SuflorReportStore.count()
        }
        suflor.reportLocked = access.plan != .pro
        suflor.onUnlockReport = { [weak self] in
            guard let self else { return }
            // On CueTake+ this lets the page open; on the free plan it shows the CueTake+ card.
            if self.access.use(.suflorReport) { self.suflorModel.reportLocked = false }
        }
    }

    /// A kept report, opened from Settings.
    func openSavedSuflorReport(_ session: SuflorSession) {
        startSuflor(returning: .settings)
        suflorModel.openSaved(session)
    }
}

/// The kept reports, newest first, from Settings.
struct SuflorReportsList: View {
    let isLocked: Bool
    let onOpen: (SuflorSession) -> Void
    let onClose: () -> Void

    @State private var reports: [SuflorSession] = []

    var body: some View {
        NavigationStack {
            Group {
                if reports.isEmpty {
                    ContentUnavailableView {
                        Label(AppLocalization.string("suflorReports.empty.title"), systemImage: "doc.text.magnifyingglass")
                    } description: {
                        Text("suflorReports.empty.detail")
                    }
                } else {
                    List {
                        if isLocked {
                            Label(AppLocalization.string("suflorReports.locked"), systemImage: "lock.fill")
                                .font(DS.sans(.medium, 13))
                                .foregroundStyle(DS.Palette.accent)
                        }
                        ForEach(reports, id: \.startedAt) { report in
                            Button { onOpen(report) } label: { row(report) }
                                .swipeActions {
                                    Button(role: .destructive) {
                                        SuflorReportStore.delete(report)
                                        reports = SuflorReportStore.all()
                                    } label: {
                                        Label(AppLocalization.string("suflorReports.delete"), systemImage: "trash")
                                    }
                                }
                        }
                    }
                    .scrollContentBackground(.hidden)
                }
            }
            .background(DS.Palette.screen)
            .navigationTitle(AppLocalization.string("suflorReports.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(AppLocalization.string("suflorReports.done"), action: onClose)
                }
            }
        }
        .onAppear { reports = SuflorReportStore.all() }
    }

    private func row(_ report: SuflorSession) -> some View {
        let brand = report.plan.brief.brand.trimmingCharacters(in: .whitespacesAndNewlines)
        let said = report.allProofs.count
        let asked = report.plan.brief.mustSay.count
        return HStack(spacing: 12) {
            Image(systemName: isLocked ? "lock.doc" : "doc.text")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(isLocked ? DS.Palette.ink(0.5) : DS.Palette.lime)
                .frame(width: 34)
            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: brand.isEmpty ? AppLocalization.string("suflorReports.untitled") : brand)
                    .font(DS.sans(.semibold, 15))
                    .foregroundStyle(DS.Palette.ink)
                Text(verbatim: report.startedAt.formatted(.dateTime.day().month().year().hour().minute().locale(AppLocalization.locale)))
                    .font(DS.mono(11))
                    .foregroundStyle(DS.Palette.ink(0.55))
            }
            Spacer(minLength: 0)
            if asked > 0 {
                Text(verbatim: "\(min(said, asked))/\(asked)")
                    .font(DS.mono(12))
                    .foregroundStyle(DS.Palette.ink(0.7))
            }
        }
        .contentShape(Rectangle())
    }
}
