import DesignSystem
import Domain
import SwiftUI

/// Reusable recipes. Each row previews the workflow's steps as chips.
public struct WorkflowsScreen: View {
    public struct Row: Identifiable {
        public let id: UUID
        public var name: String
        public var mark: String
        public var runs: String
        public var steps: [String]
        public var chipTint: Int

        public init(
            id: UUID = UUID(),
            name: String,
            mark: String,
            runs: String,
            steps: [String],
            chipTint: Int
        ) {
            self.id = id
            self.name = name
            self.mark = mark
            self.runs = runs
            self.steps = steps
            self.chipTint = chipTint
        }
    }

    private let workflows: [Row]
    private let onOpen: (Row) -> Void

    public init(workflows: [Row] = Row.samples, onOpen: @escaping (Row) -> Void) {
        self.workflows = workflows
        self.onOpen = onOpen
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                DSHeadline(String(localized: "workflows.title", bundle: .module), size: 34)

                Text("workflows.subtitle", bundle: .module)
                    .dsFont(.sans, .regular, 13)
                    .foregroundStyle(DS.Palette.ink(0.42))
                    .padding(.top, 6)

                VStack(spacing: 13) {
                    ForEach(Array(workflows.enumerated()), id: \.element.id) { index, workflow in
                        Button {
                            onOpen(workflow)
                        } label: {
                            card(workflow)
                        }
                        .buttonStyle(.dsPress)
                        .dsEnter(.rise(duration: 0.5, delay: Double(index) * 0.07))
                    }
                }
                .padding(.top, 22)
            }
            .padding(.horizontal, 22)
            .padding(.top, 64)
            .padding(.bottom, 108)
        }
        .scrollIndicators(.hidden)
        .background(DS.Palette.screen)
        .dsEnter(.screen())
    }

    private func card(_ workflow: Row) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 11) {
                Text(workflow.mark)
                    .dsFont(.archivo, .bold, 12)
                    .foregroundStyle(DS.Palette.inkInverse)
                    .frame(width: 32, height: 32)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(chipColor(workflow.chipTint))
                    )

                Text(workflow.name)
                    .dsFont(.archivo, .bold, 17)
                    .foregroundStyle(DS.Palette.ink)

                Spacer(minLength: 0)

                Text(workflow.runs)
                    .dsFont(.mono, .medium, 10)
                    .foregroundStyle(DS.Palette.ink(0.32))
            }

            FlowLayout(horizontalSpacing: 6, verticalSpacing: 6) {
                ForEach(workflow.steps, id: \.self) { step in
                    Text(step)
                        .dsFont(.mono, .medium, 10, letterSpacing: 0.06)
                        .foregroundStyle(DS.Palette.ink(0.6))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(DS.Palette.hairline(0.06))
                        )
                }
            }
            .padding(.top, 14)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .dsCard(radius: DS.Radius.cardLarge)
    }

    private func chipColor(_ tint: Int) -> Color {
        switch tint {
        case 0: DS.Palette.lime
        case 1: DS.Palette.accent
        default: DS.Palette.accentWarm
        }
    }
}

extension WorkflowsScreen.Row {
    public static let samples: [WorkflowsScreen.Row] = [
        WorkflowsScreen.Row(
            name: "Product Reel",
            mark: "PR",
            runs: "12 runs",
            steps: ["Idea", "Script", "Record", "Captions", "Export"],
            chipTint: 0
        ),
        WorkflowsScreen.Row(
            name: "Weekly Update",
            mark: "WU",
            runs: "31 runs",
            steps: ["Script", "Record", "Export"],
            chipTint: 1
        ),
        WorkflowsScreen.Row(
            name: "Tutorial Long",
            mark: "TL",
            runs: "4 runs",
            steps: ["Idea", "Blueprint", "Record", "Retake", "Captions", "Export"],
            chipTint: 2
        ),
    ]
}
