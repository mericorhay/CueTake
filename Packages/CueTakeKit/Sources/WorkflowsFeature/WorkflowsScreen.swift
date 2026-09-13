import DesignSystem
import Domain
import SwiftUI

/// The stored workflows, and the way to make a new one.
///
/// Each card shows the workflow's shape rather than describing it: a coloured bar of its sections
/// to scale, and its tools in order. A workflow is recognised by what it does to a video, and that
/// is faster to see than to read.
public struct WorkflowsScreen: View {
    private let workflows: [WorkflowDefinition]
    private let onOpen: (WorkflowDefinition) -> Void
    private let onCreate: () -> Void

    public init(
        workflows: [WorkflowDefinition],
        onOpen: @escaping (WorkflowDefinition) -> Void,
        onCreate: @escaping () -> Void
    ) {
        self.workflows = workflows
        self.onOpen = onOpen
        self.onCreate = onCreate
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                DSHeadline(String(localized: "workflows.title", bundle: .module), size: 34)

                Text("workflows.subtitle", bundle: .module)
                    .dsFont(.sans, .regular, 13)
                    .foregroundStyle(DS.Palette.ink(0.42))
                    .padding(.top, 6)

                createCard
                    .padding(.top, 22)
                    .dsEnter(.rise(duration: 0.45))

                VStack(spacing: 13) {
                    ForEach(Array(workflows.enumerated()), id: \.element.id) { index, workflow in
                        Button {
                            onOpen(workflow)
                        } label: {
                            card(workflow)
                        }
                        .buttonStyle(.dsPress)
                        .dsEnter(.rise(duration: 0.5, delay: Double(index + 1) * 0.06))
                    }
                }
                .padding(.top, 13)
            }
            .padding(.horizontal, 22)
            .padding(.top, 64)
            .padding(.bottom, 108)
        }
        .scrollIndicators(.hidden)
        .dsScreenLayout(scrolls: true)
        .background(DS.Palette.screen)
        .dsEnter(.screen())
    }

    private var createCard: some View {
        Button(action: onCreate) {
            HStack(spacing: 12) {
                Image(systemName: "sparkles")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(DS.Palette.inkInverse)
                    .frame(width: 42, height: 42)
                    .background(
                        RoundedRectangle(cornerRadius: 13, style: .continuous)
                            .fill(DS.gradient(135, [DS.Palette.lime, DS.Palette.accent]))
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text("workflows.new", bundle: .module)
                        .dsFont(.archivo, .bold, 17)
                        .foregroundStyle(DS.Palette.ink)
                    Text("workflows.new.note", bundle: .module)
                        .dsFont(.sans, .regular, 12)
                        .foregroundStyle(DS.Palette.ink(0.45))
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(DS.Palette.ink(0.3))
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.cardLarge, style: .continuous)
                    .fill(DS.Palette.hairline(0.05))
            )
            .overlay {
                RoundedRectangle(cornerRadius: DS.Radius.cardLarge, style: .continuous)
                    .stroke(DS.Palette.lime(0.35), style: StrokeStyle(lineWidth: 1.2, dash: [6, 4]))
            }
            .contentShape(RoundedRectangle(cornerRadius: DS.Radius.cardLarge, style: .continuous))
        }
        .buttonStyle(.dsPress(radius: DS.Radius.cardLarge))
    }

    private func card(_ workflow: WorkflowDefinition) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 11) {
                Text(Self.mark(for: workflow.name))
                    .dsFont(.archivo, .bold, 12)
                    .foregroundStyle(DS.Palette.inkInverse)
                    .frame(width: 32, height: 32)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(StudioCatalog.roleTint(workflow.sections.first?.role ?? "point"))
                    )

                VStack(alignment: .leading, spacing: 1) {
                    Text(workflow.name)
                        .dsFont(.archivo, .bold, 17)
                        .foregroundStyle(DS.Palette.ink)
                        .lineLimit(1)
                    if let summary = workflow.summary, !summary.isEmpty {
                        Text(summary)
                            .dsFont(.sans, .regular, 11)
                            .foregroundStyle(DS.Palette.ink(0.42))
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 0)

                if workflow.origin == .ai {
                    Image(systemName: "sparkles")
                        .font(.system(size: 11))
                        .foregroundStyle(DS.Palette.lime)
                }
            }

            // The structure, to scale.
            if !workflow.sections.isEmpty {
                GeometryReader { proxy in
                    let total = max(1, workflow.sections.reduce(0) { $0 + $1.seconds })
                    let gaps = CGFloat(workflow.sections.count - 1) * 3
                    HStack(spacing: 3) {
                        ForEach(workflow.sections) { section in
                            Capsule()
                                .fill(StudioCatalog.roleTint(section.role))
                                .frame(width: max(4, (proxy.size.width - gaps) * section.seconds / total))
                        }
                    }
                }
                .frame(height: 5)
            }

            FlowLayout(horizontalSpacing: 6, verticalSpacing: 6) {
                ForEach(workflow.steps.filter(\.isEnabled)) { step in
                    let tool = StudioCatalog.tool(for: step.kind.typeName)
                    HStack(spacing: 4) {
                        Image(systemName: tool.symbol)
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(StudioCatalog.tint(tool.category))
                        Text(String(localized: tool.title, bundle: .module))
                            .dsFont(.mono, .medium, 10, letterSpacing: 0.04)
                            .foregroundStyle(DS.Palette.ink(0.6))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(DS.Palette.hairline(0.06))
                    )
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .dsCard(radius: DS.Radius.cardLarge)
    }

    static func mark(for name: String) -> String {
        let letters = name.split(separator: " ").prefix(2).compactMap(\.first)
        return letters.isEmpty ? "W" : String(letters).uppercased()
    }
}
