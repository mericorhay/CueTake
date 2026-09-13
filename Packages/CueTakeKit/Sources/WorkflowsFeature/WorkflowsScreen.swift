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
    private let onCreateWithAI: (String) async -> String?
    private let onDuplicate: (WorkflowDefinition) -> Void
    private let onDelete: (WorkflowDefinition) -> Void

    @State private var showsAI = false
    @State private var pendingDelete: WorkflowDefinition?

    public init(
        workflows: [WorkflowDefinition],
        onOpen: @escaping (WorkflowDefinition) -> Void,
        onCreate: @escaping () -> Void,
        onCreateWithAI: @escaping (String) async -> String? = { _ in nil },
        onDuplicate: @escaping (WorkflowDefinition) -> Void = { _ in },
        onDelete: @escaping (WorkflowDefinition) -> Void = { _ in }
    ) {
        self.workflows = workflows
        self.onOpen = onOpen
        self.onCreate = onCreate
        self.onCreateWithAI = onCreateWithAI
        self.onDuplicate = onDuplicate
        self.onDelete = onDelete
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
                        // Long press for the same actions as the ••• button, the way lists
                        // everywhere else on the phone work.
                        .contextMenu { actions(for: workflow) }
                        .overlay(alignment: .topTrailing) {
                            Menu {
                                actions(for: workflow)
                            } label: {
                                Image(systemName: "ellipsis")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(DS.Palette.ink(0.7))
                                    .frame(width: 40, height: 40)
                                    .contentShape(Rectangle())
                            }
                            .padding(6)
                        }
                        .transition(.asymmetric(insertion: .scale(scale: 0.95).combined(with: .opacity), removal: .scale(scale: 0.8).combined(with: .opacity)))
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
        .animation(DS.Motion.settle, value: workflows.map(\.id))
        .sheet(isPresented: $showsAI) {
            WorkflowAISheet(onSubmit: onCreateWithAI, onClose: { showsAI = false })
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(30)
        }
        .confirmationDialog(
            String(localized: "workflows.delete.title", bundle: .module),
            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            titleVisibility: .visible,
            presenting: pendingDelete
        ) { workflow in
            Button(String(localized: "workflows.delete", bundle: .module), role: .destructive) {
                onDelete(workflow)
            }
        } message: { workflow in
            Text(workflow.name)
        }
        .dsEnter(.screen())
    }

    @ViewBuilder
    private func actions(for workflow: WorkflowDefinition) -> some View {
        Button {
            onOpen(workflow)
        } label: {
            Label(String(localized: "workflows.action.open", bundle: .module), systemImage: "slider.horizontal.3")
        }
        Button {
            onDuplicate(workflow)
        } label: {
            Label(String(localized: "workflows.action.duplicate", bundle: .module), systemImage: "plus.square.on.square")
        }
        Button(role: .destructive) {
            pendingDelete = workflow
        } label: {
            Label(String(localized: "workflows.delete", bundle: .module), systemImage: "trash")
        }
    }

    /// Two ways in, side by side: describe it and let AI write it, or build it by hand.
    private var createCard: some View {
        HStack(spacing: 10) {
            Button {
                showsAI = true
            } label: {
                VStack(alignment: .leading, spacing: 8) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(DS.Palette.inkInverse)
                        .symbolEffect(.breathe, options: .repeating)
                    Text("workflows.new.ai", bundle: .module)
                        .dsFont(.archivo, .bold, 16)
                        .foregroundStyle(DS.Palette.inkInverse)
                    Text("workflows.new.ai.note", bundle: .module)
                        .dsFont(.sans, .medium, 11)
                        .foregroundStyle(DS.Palette.inkInverse.opacity(0.7))
                        .lineLimit(2)
                }
                .padding(16)
                .frame(maxWidth: .infinity, minHeight: 118, alignment: .topLeading)
                .background(
                    RoundedRectangle(cornerRadius: DS.Radius.cardLarge, style: .continuous)
                        .fill(DS.gradient(135, [DS.Palette.lime, DS.Palette.accent]))
                )
                .contentShape(RoundedRectangle(cornerRadius: DS.Radius.cardLarge, style: .continuous))
            }
            .buttonStyle(.dsPress(radius: DS.Radius.cardLarge))

            manualCard
        }
    }

    private var manualCard: some View {
        Button(action: onCreate) {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: "hand.draw")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(DS.Palette.lime)
                Text("workflows.new.manual", bundle: .module)
                    .dsFont(.archivo, .bold, 16)
                    .foregroundStyle(DS.Palette.ink)
                Text("workflows.new.manual.note", bundle: .module)
                    .dsFont(.sans, .medium, 11)
                    .foregroundStyle(DS.Palette.ink(0.45))
                    .lineLimit(2)
            }
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: 118, alignment: .topLeading)
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
                // Room for the ••• menu laid over this corner.
                Color.clear.frame(width: 26, height: 1)
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
