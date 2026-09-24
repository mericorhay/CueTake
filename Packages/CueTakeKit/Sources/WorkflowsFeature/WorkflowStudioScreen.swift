import DesignSystem
import Domain
import SwiftUI

/// Where a workflow is built: its structure, its look, and its pipeline of automatic tools.
///
/// Everything here can be dragged. Sections are dragged to reorder them; roles are dragged into
/// the structure to add a beat; clips are dragged onto sections to say which footage fills them;
/// tools are dragged into the pipeline, and steps are dragged up and down it. Every drag has a
/// tap that does the same thing, because a drag is the fast way for someone who knows what they
/// want and a terrible way to find out what is possible.
///
/// And it can be written for you. The bar at the top takes a sentence — "three points, cut the
/// pauses, bold captions" — and the on-device model rewrites the whole document, which then
/// appears here as ordinary cards to adjust by hand. Nothing the model makes is hidden in a form
/// only the model can read: the JSON panel shows exactly what is stored.
public struct WorkflowStudioScreen: View {
    @Bindable private var model: WorkflowStudioModel

    private let onBack: () -> Void
    private let onSave: () -> Void
    private let onRun: () -> Void
    private let onStop: () -> Void
    private let onAskAI: () -> Void
    private let onPickClips: () -> Void
    private let onDelete: () -> Void
    private let onOpenResult: () -> Void
    private let onResend: () -> Void

    @State private var showsJSON = false
    @State private var confirmsDelete = false
    @State private var showsPalette = false
    @State private var dropSection: WorkflowSection.ID?
    @State private var structureTargeted = false
    @FocusState private var aiFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(
        model: WorkflowStudioModel,
        onBack: @escaping () -> Void,
        onSave: @escaping () -> Void,
        onRun: @escaping () -> Void,
        onStop: @escaping () -> Void = {},
        onAskAI: @escaping () -> Void,
        onPickClips: @escaping () -> Void,
        onDelete: @escaping () -> Void,
        onOpenResult: @escaping () -> Void = {},
        onResend: @escaping () -> Void = {}
    ) {
        self.model = model
        self.onBack = onBack
        self.onSave = onSave
        self.onRun = onRun
        self.onStop = onStop
        self.onAskAI = onAskAI
        self.onPickClips = onPickClips
        self.onDelete = onDelete
        self.onOpenResult = onOpenResult
        self.onResend = onResend
    }

    public var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    aiBar
                    if let summary = model.lastRunSummary, !model.isRunning {
                        StudioRunResultCard(
                            model: model,
                            summary: summary,
                            onOpen: onOpenResult,
                            onResend: onResend,
                            onDismiss: { withAnimation(DS.Motion.settle) { model.dismissRunSummary() } }
                        )
                        .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .top)))
                    }
                    if !readiness.isEmpty, !model.isRunning {
                        readinessCard
                    }
                    StudioPreview(model: model)
                    structure
                    StudioStyleCard(model: model)
                    StudioPipeline(model: model, onShowPalette: { showsPalette = true })
                }
                .padding(.horizontal, 20)
                .padding(.top, 6)
                .padding(.bottom, 130)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
        }
        .overlay(alignment: .bottom) { runBar }
        .padding(.top, 54)
        .dsScreenLayout()
        .background(DS.Palette.screen)
        .sensoryFeedback(.impact(weight: .light), trigger: model.editPulse)
        .sheet(isPresented: $showsJSON) {
            StudioJSONSheet(model: model, onClose: { showsJSON = false })
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showsPalette) {
            StudioToolPalette(model: model, onClose: { showsPalette = false })
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .onChange(of: model.definition) { onSave() }
        // The closing export says what the style says, the moment the style changes.
        .onChange(of: model.definition.style) { model.syncFinalExport() }
        .sensoryFeedback(.warning, trigger: model.refusedPulse)
        .animation(DS.Motion.settle, value: model.lastRunSummary)
        .confirmationDialog(
            AppLocalization.string("studio.delete.confirm", bundle: .module),
            isPresented: $confirmsDelete,
            titleVisibility: .visible
        ) {
            Button(AppLocalization.string("studio.delete", bundle: .module), role: .destructive, action: onDelete)
        } message: {
            Text("studio.delete.message", bundle: .module)
        }
        .dsEnter(.screen())
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            DSBackButton(size: 34, fontSize: 15, action: onBack)

            VStack(alignment: .leading, spacing: 1) {
                TextField(
                    "",
                    text: Binding(
                        get: { model.definition.name },
                        set: { model.definition.name = $0 }
                    )
                )
                .dsFont(.archivo, .bold, 18)
                .foregroundStyle(DS.Palette.ink)
                .textFieldStyle(.plain)

                Text(Self.originLabel(model.definition.origin))
                    .dsFont(.mono, .medium, 10, letterSpacing: 0.1)
                    .foregroundStyle(DS.Palette.ink(0.52))
            }

            Spacer(minLength: 0)

            iconButton("curlybraces") { showsJSON = true }

            Menu {
                Button {
                    showsJSON = true
                } label: {
                    Label(AppLocalization.string("studio.json", bundle: .module), systemImage: "curlybraces")
                }
                Button(role: .destructive) {
                    confirmsDelete = true
                } label: {
                    Label(AppLocalization.string("studio.delete", bundle: .module), systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(DS.Palette.ink(0.7))
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(DS.Palette.hairline(0.08)))
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
    }

    // MARK: - AI

    /// A sentence in, a workflow out.
    ///
    /// Always visible and always the first thing on the page: describing what you want is faster
    /// than building it for almost everyone, and the cards underneath are there for the last ten
    /// percent — not the other way round.
    private var aiBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: "sparkles")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(DS.Palette.lime)
                    .symbolEffect(.variableColor.iterative, options: .repeating, isActive: model.isAuthoring)

                TextField(
                    AppLocalization.string("studio.ai.placeholder", bundle: .module),
                    text: $model.aiRequest,
                    axis: .vertical
                )
                .dsFont(.sans, .regular, 14)
                .foregroundStyle(DS.Palette.ink)
                .lineLimit(1...4)
                .focused($aiFocused)
                .submitLabel(.send)
                .onSubmit(ask)
                .disabled(model.isAuthoring)

                Button(action: ask) {
                    Group {
                        if model.isAuthoring {
                            ProgressView().tint(DS.Palette.inkInverse)
                        } else {
                            Image(systemName: "arrow.up")
                                .dsActionName("arrow.up")
                                .font(.system(size: 13, weight: .bold))
                        }
                    }
                    .foregroundStyle(DS.Palette.inkInverse)
                    .frame(width: 32, height: 32)
                    .background(
                        Circle().fill(model.aiRequest.isEmpty ? DS.Palette.ink(0.25) : DS.Palette.lime)
                    )
                }
                .buttonStyle(.dsPressIcon)
                .disabled(model.aiRequest.trimmingCharacters(in: .whitespaces).isEmpty || model.isAuthoring)
            }
            .padding(.leading, 14)
            .padding(.trailing, 7)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(DS.Palette.hairline(0.06))
            )
            .overlay {
                // A moving edge while the model writes. The wait is a few seconds, and a field that
                // sits still for a few seconds reads as a field that did not hear you.
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(
                        model.isAuthoring
                            ? AnyShapeStyle(
                                AngularGradient(
                                    colors: [DS.Palette.lime, DS.Palette.accent, DS.Palette.lime.opacity(0.1), DS.Palette.lime],
                                    center: .center
                                )
                            )
                            : AnyShapeStyle(DS.Palette.hairline(aiFocused ? 0.25 : 0.1)),
                        lineWidth: model.isAuthoring ? 1.5 : 1
                    )
            }
            .animation(DS.Motion.snap, value: aiFocused)

            if let failure = model.aiFailure {
                Text(failure)
                    .dsFont(.sans, .regular, 11)
                    .foregroundStyle(DS.Palette.accent)
                    .transition(.opacity)
            }
        }
    }

    private func ask() {
        guard !model.aiRequest.trimmingCharacters(in: .whitespaces).isEmpty, !model.isAuthoring else { return }
        aiFocused = false
        onAskAI()
    }

    // MARK: - Structure

    private var structure: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(
                "studio.structure",
                trailing: String(format: "%.0f s", model.totalSeconds)
            )

            ScrollView(.horizontal) {
                HStack(spacing: 0) {
                    ForEach(Array(model.definition.sections.enumerated()), id: \.element.id) { index, section in
                        if index > 0 {
                            FlowConnector(active: model.isRunning)
                                .frame(width: 22, height: 2)
                                .transition(.opacity)
                        }
                        sectionNode(section, number: index + 1)
                            .transition(
                                reduceMotion
                                    ? .opacity
                                    : .asymmetric(
                                        insertion: .scale(scale: 0.6).combined(with: .opacity),
                                        removal: .scale(scale: 0.8).combined(with: .opacity)
                                    )
                            )
                    }

                    addSectionNode
                        .padding(.leading, model.definition.sections.isEmpty ? 0 : 12)
                }
                .padding(.vertical, 10)
                .padding(.horizontal, 2)
            }
            .scrollIndicators(.hidden)
            .animation(reduceMotion ? nil : DS.Motion.settle, value: model.definition.sections)
            // The whole strip accepts a role dropped past the last card.
            .dropDestination(for: String.self) { items, _ in
                handleStructureDrop(items, before: nil)
            } isTargeted: { structureTargeted = $0 }

            rolePalette
            clipTray
        }
    }

    private func sectionNode(_ section: WorkflowSection, number: Int) -> some View {
        let tint = StudioCatalog.roleTint(section.role)
        let isTarget = dropSection == section.id
        let clip = section.clip.flatMap { slot in model.clips.first { $0.slot == slot } }

        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(tint)
                    .frame(width: 8, height: 8)
                Text(StudioCatalog.roleLabel(section.role))
                    .dsFont(.archivo, .bold, 12)
                    .foregroundStyle(DS.Palette.ink)
                Spacer(minLength: 0)
                Text(verbatim: "\(number)")
                    .dsFont(.mono, .medium, 10)
                    .foregroundStyle(DS.Palette.ink(0.52))
            }

            TextField(
                "",
                text: Binding(
                    get: { section.title },
                    set: { value in model.updateSection(section.id) { $0.title = value } }
                ),
                prompt: Text(StudioCatalog.roleLabel(section.role))
            )
            .dsFont(.sans, .medium, 12)
            .foregroundStyle(DS.Palette.ink(0.8))
            .textFieldStyle(.plain)

            // The clip slot. Empty is drawn as a dashed well, because it is a place to put
            // something, and a place to put something should look like one.
            Group {
                if let clip {
                    HStack(spacing: 5) {
                        Image(systemName: "film")
                            .font(.system(size: 9, weight: .semibold))
                        Text(clip.name)
                            .dsFont(.sans, .medium, 10)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .foregroundStyle(DS.Palette.inkInverse)
                    .padding(.horizontal, 7)
                    .frame(maxWidth: .infinity, minHeight: 26, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(tint))
                    .transition(.scale(scale: 0.7).combined(with: .opacity))
                } else {
                    Text("studio.section.dropClip", bundle: .module)
                        .dsFont(.sans, .regular, 10)
                        .foregroundStyle(DS.Palette.ink(0.52))
                        .frame(maxWidth: .infinity, minHeight: 26)
                        .overlay {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(DS.Palette.hairline(0.2), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                        }
                }
            }
            .animation(DS.Motion.bloom, value: section.clip)

            HStack(spacing: 4) {
                Button {
                    model.updateSection(section.id) { $0.seconds = max(1, $0.seconds - 1) }
                } label: { nudge("minus") }
                    .buttonStyle(.dsPressIcon)

                Text(String(format: "%.0f s", section.seconds))
                    .dsFont(.mono, .medium, 11)
                    .foregroundStyle(DS.Palette.ink(0.7))
                    .contentTransition(.numericText())
                    .frame(maxWidth: .infinity)

                Button {
                    model.updateSection(section.id) { $0.seconds = min(180, $0.seconds + 1) }
                } label: { nudge("plus") }
                    .buttonStyle(.dsPressIcon)
            }
        }
        .padding(10)
        .frame(width: 128)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(DS.Palette.hairline(isTarget ? 0.12 : 0.05))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(isTarget ? tint : DS.Palette.hairline(0.09), lineWidth: isTarget ? 2 : 1)
        }
        .overlay(alignment: .top) {
            // The role's colour as a thin cap, so a strip of cards reads as a coloured sequence at
            // the size of a thumbnail.
            UnevenRoundedRectangle(topLeadingRadius: 16, topTrailingRadius: 16, style: .continuous)
                .fill(tint)
                .frame(height: 3)
        }
        .scaleEffect(isTarget && !reduceMotion ? 1.06 : 1)
        .shadow(color: isTarget ? tint.opacity(0.35) : .clear, radius: 14, y: 6)
        .animation(DS.Motion.snap, value: isTarget)
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .draggable(StudioDrag.section + section.id.uuidString) {
            Text(StudioCatalog.roleLabel(section.role))
                .dsFont(.archivo, .bold, 13)
                .foregroundStyle(DS.Palette.inkInverse)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(Capsule().fill(tint))
        }
        .dropDestination(for: String.self) { items, _ in
            handleStructureDrop(items, before: section.id)
        } isTargeted: { targeted in
            dropSection = targeted ? section.id : (dropSection == section.id ? nil : dropSection)
        }
        .contextMenu {
            Button {
                model.duplicateSection(section.id)
            } label: {
                Label(AppLocalization.string("studio.duplicate", bundle: .module), systemImage: "plus.square.on.square")
            }
            if section.clip != nil {
                Button {
                    model.assign(clip: nil, to: section.id)
                } label: {
                    Label(AppLocalization.string("studio.section.clearClip", bundle: .module), systemImage: "film.stack")
                }
            }
            Button(role: .destructive) {
                model.removeSection(section.id)
            } label: {
                Label(AppLocalization.string("studio.delete", bundle: .module), systemImage: "trash")
            }
        }
    }

    private var addSectionNode: some View {
        Menu {
            ForEach(WorkflowSection.standardRoles, id: \.self) { role in
                Button(StudioCatalog.roleLabel(role)) { model.addSection(role: role) }
            }
        } label: {
            VStack(spacing: 6) {
                Image(systemName: "plus")
                    .font(.system(size: 16, weight: .semibold))
                Text("studio.section.add", bundle: .module)
                    .dsFont(.sans, .medium, 11)
            }
            .foregroundStyle(DS.Palette.ink(structureTargeted ? 0.9 : 0.45))
            .frame(width: 92, height: 150)
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(
                        structureTargeted ? DS.Palette.lime : DS.Palette.hairline(0.18),
                        style: StrokeStyle(lineWidth: 1.2, dash: [5, 4])
                    )
            }
            .animation(DS.Motion.snap, value: structureTargeted)
        }
    }

    /// Roles to drag in. Tapping one appends it, for anyone who does not know they can drag.
    private var rolePalette: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 6) {
                ForEach(WorkflowSection.standardRoles, id: \.self) { role in
                    let tint = StudioCatalog.roleTint(role)
                    Button {
                        model.addSection(role: role)
                    } label: {
                        HStack(spacing: 5) {
                            Circle().fill(tint).frame(width: 6, height: 6)
                            Text(StudioCatalog.roleLabel(role))
                                .dsFont(.mono, .medium, 10, letterSpacing: 0.08)
                                .foregroundStyle(DS.Palette.ink(0.75))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(Capsule().fill(DS.Palette.hairline(0.06)))
                    }
                    .buttonStyle(.dsPress(radius: 20))
                    .draggable(StudioDrag.role + role) {
                        Text(StudioCatalog.roleLabel(role))
                            .dsFont(.archivo, .bold, 13)
                            .foregroundStyle(DS.Palette.inkInverse)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 9)
                            .background(Capsule().fill(tint))
                    }
                }
            }
        }
        .scrollIndicators(.hidden)
    }

    /// The user's clips, to drag onto sections.
    private var clipTray: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("studio.clips", bundle: .module)
                    .dsFont(.mono, .medium, 10, letterSpacing: 0.12)
                    .foregroundStyle(DS.Palette.ink(0.52))
                Spacer(minLength: 0)
                if !model.clips.isEmpty, model.definition.sections.contains(where: { $0.clip == nil }) {
                    Button {
                        withAnimation(DS.Motion.bloom) { model.autoAssignClips() }
                    } label: {
                        Label(AppLocalization.string("studio.clips.auto", bundle: .module), systemImage: "wand.and.stars")
                            .dsFont(.sans, .medium, 11)
                            .foregroundStyle(DS.Palette.lime)
                    }
                    .buttonStyle(.dsPress)
                }
            }

            ScrollView(.horizontal) {
                HStack(spacing: 7) {
                    ForEach(model.clips) { clip in
                        let used = model.definition.sections.contains { $0.clip == clip.slot }
                        HStack(spacing: 6) {
                            Text(verbatim: "\(clip.slot)")
                                .dsFont(.mono, .semibold, 10)
                                .foregroundStyle(DS.Palette.inkInverse)
                                .frame(width: 18, height: 18)
                                .background(Circle().fill(used ? DS.Palette.lime : DS.Palette.ink(0.6)))
                            VStack(alignment: .leading, spacing: 0) {
                                Text(clip.name)
                                    .dsFont(.sans, .medium, 11)
                                    .foregroundStyle(DS.Palette.ink)
                                    .lineLimit(1)
                                Text(String(format: "%.1f s", clip.seconds))
                                    .dsFont(.mono, .medium, 10)
                                    .foregroundStyle(DS.Palette.ink(0.56))
                            }
                        }
                        .padding(.leading, 6)
                        .padding(.trailing, 11)
                        .padding(.vertical, 6)
                        .frame(maxWidth: 150)
                        .background(Capsule().fill(DS.Palette.hairline(used ? 0.09 : 0.05)))
                        .overlay(Capsule().stroke(used ? DS.Palette.lime(0.4) : DS.Palette.hairline(0.08), lineWidth: 1))
                        .draggable(StudioDrag.clip + "\(clip.slot)") {
                            Label(clip.name, systemImage: "film")
                                .dsFont(.sans, .semibold, 12)
                                .foregroundStyle(DS.Palette.inkInverse)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(Capsule().fill(DS.Palette.lime))
                        }
                    }

                    Button(action: onPickClips) {
                        Label(AppLocalization.string("studio.clips.pick", bundle: .module), systemImage: "plus")
                            .dsFont(.sans, .medium, 11)
                            .foregroundStyle(DS.Palette.ink(0.7))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .overlay(
                                Capsule().stroke(DS.Palette.hairline(0.18), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                            )
                    }
                    .buttonStyle(.dsPress(radius: 20))
                }
            }
            .scrollIndicators(.hidden)
        }
    }

    private func handleStructureDrop(_ items: [String], before target: WorkflowSection.ID?) -> Bool {
        guard let item = items.first else { return false }

        withAnimation(reduceMotion ? .easeOut(duration: 0.15) : DS.Motion.settle) {
            if item.hasPrefix(StudioDrag.section), let id = UUID(uuidString: String(item.dropFirst(StudioDrag.section.count))) {
                model.moveSection(id, before: target)
            } else if item.hasPrefix(StudioDrag.role) {
                let role = String(item.dropFirst(StudioDrag.role.count))
                let index = target.flatMap { t in model.definition.sections.firstIndex { $0.id == t } }
                model.addSection(role: role, at: index)
            } else if item.hasPrefix(StudioDrag.clip), let target, let slot = Int(item.dropFirst(StudioDrag.clip.count)) {
                model.assign(clip: slot, to: target)
            }
        }
        dropSection = nil
        return true
    }

    // MARK: - Readiness

    /// What will make this run do less than the user expects, said before they press Run.
    private var readiness: [String] {
        var notes: [String] = []
        let steps = model.definition.steps.filter(\.isEnabled).map(\.kind)
        if steps.contains(.assembleSections) {
            if model.clips.isEmpty {
                notes.append(AppLocalization.string("studio.ready.noClips", bundle: .module))
            } else if model.definition.sections.contains(where: { $0.clip == nil }) {
                notes.append(AppLocalization.string("studio.ready.emptySections", bundle: .module))
            }
        }
        if let delivery = model.definition.delivery, delivery.isEnabled, delivery.url == nil {
            notes.append(AppLocalization.string("studio.warning.deliveryURL", bundle: .module))
        }
        return notes
    }

    private var readinessCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(readiness, id: \.self) { note in
                Label(note, systemImage: "exclamationmark.circle.fill")
                    .dsFont(.sans, .medium, 12, lineHeight: 1.3)
                    .foregroundStyle(DS.Palette.ink(0.8))
                    .symbolRenderingMode(.hierarchical)
            }
            HStack(spacing: 8) {
                if model.clips.isEmpty || model.definition.sections.contains(where: { $0.clip == nil }) {
                    Button(action: onPickClips) {
                        Label(AppLocalization.string("studio.clips.pick", bundle: .module), systemImage: "plus")
                            .dsFont(.sans, .semibold, 12)
                            .foregroundStyle(DS.Palette.inkInverse)
                            .padding(.horizontal, 12)
                            .frame(height: 34)
                            .background(Capsule().fill(DS.Palette.lime))
                    }
                    .buttonStyle(.dsPress(radius: 17))
                }
                if !model.clips.isEmpty, model.definition.sections.contains(where: { $0.clip == nil }) {
                    Button {
                        withAnimation(DS.Motion.bloom) { model.autoAssignClips() }
                    } label: {
                        Label(AppLocalization.string("studio.clips.auto", bundle: .module), systemImage: "wand.and.stars")
                            .dsFont(.sans, .semibold, 12)
                            .foregroundStyle(DS.Palette.ink)
                            .padding(.horizontal, 12)
                            .frame(height: 34)
                            .background(Capsule().fill(DS.Palette.hairline(0.1)))
                    }
                    .buttonStyle(.dsPress(radius: 17))
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(DS.Palette.accentWarm.opacity(0.1)))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(DS.Palette.accentWarm.opacity(0.35), lineWidth: 1)
        }
        .transition(.opacity)
    }

    // MARK: - Run

    private var runBar: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text(
                    String(
                        localized: "studio.run.summary \(model.definition.sections.count) \(model.definition.steps.filter(\.isEnabled).count)",
                        bundle: .module
                    )
                )
                .dsFont(.sans, .semibold, 12)
                .foregroundStyle(DS.Palette.ink)
                Text(model.isRunning ? runningDetail : runDetail)
                    .dsFont(.sans, .regular, 10)
                    .foregroundStyle(model.isRunning ? DS.Palette.lime : DS.Palette.ink(0.4))
                    .contentTransition(.numericText())
            }

            Spacer(minLength: 0)

            if model.isRunning {
                // Stopping is always one tap away: a run of sixty generated videos is not
                // something to be trapped in.
                Button {
                    model.requestStop()
                    onStop()
                } label: {
                    Image(systemName: model.isStopping ? "hourglass" : "stop.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(DS.Palette.ink)
                        .contentTransition(.symbolEffect(.replace))
                        .frame(width: 46, height: 46)
                        .background(Circle().fill(DS.Palette.hairline(0.1)))
                }
                .buttonStyle(.dsPressIcon)
                .disabled(model.isStopping)
                .accessibilityLabel(Text("studio.run.stop", bundle: .module))
                .transition(.scale(scale: 0.6).combined(with: .opacity))
            }

            Button(action: onRun) {
                HStack(spacing: 7) {
                    Image(systemName: model.isRunning ? "hourglass" : (model.resumableProgress == nil ? "play.fill" : "arrow.clockwise"))
                        .font(.system(size: 13, weight: .bold))
                        .contentTransition(.symbolEffect(.replace))
                        .symbolEffect(.rotate, options: .repeating, isActive: model.isRunning && !reduceMotion)
                        .symbolEffect(.bounce, value: model.lastRunSummary)
                    Text(
                        model.isRunning
                            ? AppLocalization.string("studio.run.running", bundle: .module)
                            : AppLocalization.string(model.resumableProgress == nil ? "studio.run" : "studio.run.resume", bundle: .module)
                    )
                    .dsFont(.sans, .semibold, 15)
                }
                .foregroundStyle(DS.Palette.inkInverse)
                .padding(.horizontal, 22)
                .padding(.vertical, 14)
                .background {
                    // The button fills as the run advances, left to right.
                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            Capsule().fill(model.isRunning ? DS.Palette.lime.opacity(0.55) : DS.Palette.accent)
                            if model.isRunning {
                                Capsule()
                                    .fill(DS.Palette.lime)
                                    .frame(width: max(proxy.size.height, proxy.size.width * model.runProgress))
                            }
                        }
                    }
                }
                .clipShape(Capsule())
                .shadow(color: DS.Palette.accent(model.isRunning ? 0 : 0.35), radius: 16, y: 8)
            }
            .buttonStyle(.dsPress(radius: 30))
            .disabled(model.isRunning || model.definition.steps.isEmpty)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .dsGlass(
            tint: DS.Palette.glassSheet(0.9),
            in: RoundedRectangle(cornerRadius: 26, style: .continuous),
            border: DS.Palette.hairline(0.12)
        )
        .padding(.horizontal, 14)
        .padding(.bottom, 26)
        .animation(DS.Motion.snap, value: model.isRunning)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.5), value: model.runProgress)
        .sensoryFeedback(.success, trigger: model.lastRunSummary) { _, summary in
            (summary?.completed ?? 0) > 0
        }
    }

    private var runningDetail: String {
        let total = model.definition.steps.count
        let settled = Int((model.runProgress * Double(total)).rounded())
        if model.isStopping { return AppLocalization.string("studio.run.stopping", bundle: .module) }
        return AppLocalization.string("studio.run.progress \(settled) \(total)", bundle: .module)
    }

    private var runDetail: String {
        if let progress = model.resumableProgress {
            return AppLocalization.string("studio.run.resumeProgress \(Int((progress * 100).rounded()))", bundle: .module)
        }
        guard let summary = model.lastRunSummary else {
            return AppLocalization.string("studio.run.saved", bundle: .module)
        }
        return String(
            localized: "studio.run.result \(summary.completed) \(summary.skipped)",
            bundle: .module
        )
    }

    // MARK: - Parts

    private func sectionHeader(_ key: String.LocalizationValue, trailing: String) -> some View {
        HStack {
            DSKicker(AppLocalization.string(key, bundle: .module), size: 10, color: DS.Palette.ink(0.56))
            Spacer(minLength: 0)
            Text(trailing)
                .dsFont(.mono, .medium, 11)
                .foregroundStyle(DS.Palette.ink(0.56))
                .contentTransition(.numericText())
        }
    }

    private func iconButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .dsActionName(symbol)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(DS.Palette.ink(0.7))
                .frame(width: 34, height: 34)
                .background(Circle().fill(DS.Palette.hairline(0.08)))
        }
        .buttonStyle(.dsPressIcon)
    }

    private func nudge(_ symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(DS.Palette.ink(0.7))
            .frame(width: 22, height: 22)
            .background(Circle().fill(DS.Palette.hairline(0.08)))
    }

    static func originLabel(_ origin: WorkflowOrigin) -> String {
        switch origin {
        case .builtIn: AppLocalization.string("studio.origin.builtIn", bundle: .module)
        case .user: AppLocalization.string("studio.origin.user", bundle: .module)
        case .remote: AppLocalization.string("studio.origin.remote", bundle: .module)
        case .ai: AppLocalization.string("studio.origin.ai", bundle: .module)
        }
    }
}

/// The line between two sections. While a run is going it flows, left to right, the direction
/// the video plays.
///
/// Driven by the display's own clock rather than an animation, because a `Canvas` is redrawn, not
/// interpolated — and paused when there is nothing to show, so an idle studio costs no frames.
struct FlowConnector: View {
    let active: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(paused: reduceMotion || !active)) { timeline in
            let cycle = timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 0.8) / 0.8
            Canvas { context, size in
                var path = Path()
                path.move(to: CGPoint(x: 0, y: size.height / 2))
                path.addLine(to: CGPoint(x: size.width, y: size.height / 2))
                context.stroke(
                    path,
                    with: .color(active ? DS.Palette.lime : DS.Palette.hairline(0.3)),
                    style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [3, 4], dashPhase: -CGFloat(cycle) * 14)
                )
            }
        }
    }
}
