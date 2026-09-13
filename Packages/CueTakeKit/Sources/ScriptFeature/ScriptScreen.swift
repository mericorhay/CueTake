import AIServices
import DesignSystem
import Domain
import SwiftUI

/// The full script, one card per beat — and every word of it editable.
///
/// It used to be read-only, with rewrite chips that ran string tricks: "shorter" kept the first
/// sentence, "rewrite" put the sentences in reverse order. Now a card opens into a text field,
/// the chips ask the on-device model (with the rest of the script as context), a rewrite can be
/// taken back, and beats can be added, moved and removed. Timings follow the words.
public struct ScriptScreen: View {
    @Binding private var project: Project
    @State private var openSegment: Segment.ID?
    @State private var working: Segment.ID?
    /// The text before the last rewrite of each beat, for taking it back.
    @State private var beforeRewrite: [Segment.ID: String] = [:]
    @State private var failure: String?
    @FocusState private var focused: Segment.ID?

    private let onBack: () -> Void
    private let onOpenStudio: () -> Void

    public init(
        project: Binding<Project>,
        onBack: @escaping () -> Void,
        onOpenStudio: @escaping () -> Void
    ) {
        self._project = project
        self.onBack = onBack
        self.onOpenStudio = onOpenStudio
    }

    public var body: some View {
        VStack(spacing: 0) {
            header

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 11) {
                        ForEach(Array(project.segments.enumerated()), id: \.element.id) { index, segment in
                            card(for: segment, at: index)
                                .id(segment.id)
                                .dsEnter(.rise(duration: 0.5, delay: Double(index) * 0.06))
                        }

                        addButton
                    }
                    .padding(.horizontal, 22)
                    .padding(.top, 4)
                    .padding(.bottom, 16)
                    .animation(DS.Motion.settle, value: project.segments.map(\.id))
                }
                .scrollIndicators(.hidden)
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: openSegment) { _, id in
                    guard let id else { return }
                    withAnimation(DS.Motion.settle) { proxy.scrollTo(id, anchor: .top) }
                }
            }

            if let failure {
                Text(failure)
                    .dsFont(.sans, .regular, 12)
                    .foregroundStyle(DS.Palette.accent)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 22)
                    .padding(.top, 6)
                    .transition(.opacity)
            }

            if focused == nil {
                DSPrimaryButton(
                    String(localized: "script.studio", bundle: .module),
                    verticalPadding: 18,
                    fontSize: 16,
                    action: onOpenStudio
                )
                .padding(.horizontal, 22)
                .padding(.top, 8)
                .padding(.bottom, 30)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .dsScreenLayout()
        .background(DS.Palette.screen)
        .animation(DS.Motion.settle, value: focused)
        .animation(DS.Motion.settle, value: failure)
        .dsEnter(.screen())
    }

    private var header: some View {
        HStack {
            DSBackButton(action: onBack)
            Spacer(minLength: 0)
            DSKicker(String(localized: "script.kicker \(project.wordCount)", bundle: .module))
                .contentTransition(.numericText())
            Spacer(minLength: 0)
            if focused != nil {
                Button {
                    focused = nil
                } label: {
                    Text("script.done", bundle: .module)
                        .dsFont(.sans, .semibold, 13)
                        .foregroundStyle(DS.Palette.ink)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .dsGlass(tint: DS.Palette.glass(0.6), in: Capsule())
                }
                .buttonStyle(.dsPress)
                .transition(.scale.combined(with: .opacity))
            } else {
                Color.clear.frame(width: 36, height: 36)
            }
        }
        .padding(.horizontal, 22)
        .padding(.top, 62)
        .padding(.bottom, 14)
    }

    // MARK: - Card

    private func card(for segment: Segment, at index: Int) -> some View {
        let isOpen = openSegment == segment.id
        let isWorking = working == segment.id
        let color = DS.Palette.segment(at: segment.role.paletteIndex)

        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 9) {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(color)
                    .frame(width: 8, height: 8)

                Text(segment.role.displayLabel)
                    .dsFont(.mono, .medium, 11, letterSpacing: 0.14)
                    .foregroundStyle(DS.Palette.ink(0.55))

                Spacer(minLength: 0)

                Text(verbatim: "\(Int(segment.barWeight.rounded()))s")
                    .dsFont(.mono, .medium, 10)
                    .foregroundStyle(DS.Palette.ink(0.28))
                    .contentTransition(.numericText())

                if isOpen {
                    menu(at: index)
                }
            }

            if isOpen {
                TextField(
                    String(localized: "script.placeholder", bundle: .module),
                    text: scriptBinding(at: index),
                    axis: .vertical
                )
                .dsFont(.sans, .regular, 16, lineHeight: 1.5)
                .foregroundStyle(DS.Palette.ink)
                .tint(color)
                .focused($focused, equals: segment.id)
                .padding(.top, 10)
                .disabled(isWorking)
                .opacity(isWorking ? 0.45 : 1)
                .overlay {
                    if isWorking { WritingShimmer(color: color) }
                }
            } else {
                Text(segment.script.isEmpty ? String(localized: "script.empty", bundle: .module) : segment.script)
                    .dsFont(.sans, .regular, 16, lineHeight: 1.5)
                    .foregroundStyle(segment.script.isEmpty ? DS.Palette.ink(0.35) : DS.Palette.ink)
                    .multilineTextAlignment(.leading)
                    .padding(.top, 10)
            }

            if isOpen {
                rewriteRow(for: segment, at: index)
                    .padding(.top, 14)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                .fill(isOpen ? DS.Palette.surfaceActive : DS.Palette.surface)
        )
        .overlay {
            RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                .stroke(isOpen ? color : DS.Palette.hairline(0.07), lineWidth: 1)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            guard !isOpen else { return }
            withAnimation(DS.Easing.ease(0.3)) {
                openSegment = segment.id
            }
        }
    }

    private func menu(at index: Int) -> some View {
        Menu {
            Button {
                move(from: index, to: index - 1)
            } label: {
                Label(String(localized: "script.moveUp", bundle: .module), systemImage: "arrow.up")
            }
            .disabled(index == 0)

            Button {
                move(from: index, to: index + 1)
            } label: {
                Label(String(localized: "script.moveDown", bundle: .module), systemImage: "arrow.down")
            }
            .disabled(index + 1 >= project.segments.count)

            Button(role: .destructive) {
                remove(at: index)
            } label: {
                Label(String(localized: "script.delete", bundle: .module), systemImage: "trash")
            }
            .disabled(project.segments.count <= 1)
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(DS.Palette.ink(0.7))
                .frame(width: 28, height: 28)
                .background(Circle().fill(DS.Palette.hairline(0.07)))
        }
    }

    private func rewriteRow(for segment: Segment, at index: Int) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Rectangle()
                .fill(DS.Palette.hairline(0.08))
                .frame(height: 1)
                .padding(.bottom, 13)

            HStack {
                Text("script.rewriteAs", bundle: .module)
                    .dsFont(.mono, .medium, 9, letterSpacing: 0.14)
                    .foregroundStyle(DS.Palette.ink(0.3))
                Spacer(minLength: 0)
                if beforeRewrite[segment.id] != nil, working == nil {
                    Button {
                        undoRewrite(at: index)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.uturn.backward")
                                .font(.system(size: 10, weight: .semibold))
                            Text("script.undo", bundle: .module)
                                .dsFont(.sans, .medium, 11)
                        }
                        .foregroundStyle(DS.Palette.ink(0.7))
                    }
                    .buttonStyle(.dsPress)
                    .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(.bottom, 9)

            if ScriptRewriter.isAvailable {
                FlowLayout(horizontalSpacing: 7, verticalSpacing: 7) {
                    ForEach(RewriteAction.allCases, id: \.self) { action in
                        rewriteButton(action, index: index, enabled: working == nil && !segment.script.isEmpty)
                    }
                }
            } else {
                Text("script.rewrite.unavailable", bundle: .module)
                    .dsFont(.sans, .regular, 12, lineHeight: 1.4)
                    .foregroundStyle(DS.Palette.ink(0.45))
            }
        }
    }

    private func rewriteButton(_ action: RewriteAction, index: Int, enabled: Bool) -> some View {
        Button {
            Task { await rewrite(at: index, with: action) }
        } label: {
            Text(String(localized: action.labelKey, bundle: .module))
                .dsFont(.sans, .medium, 12)
                .foregroundStyle(DS.Palette.lime)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: DS.Radius.m, style: .continuous)
                        .fill(DS.Palette.lime(0.1))
                )
                .overlay {
                    RoundedRectangle(cornerRadius: DS.Radius.m, style: .continuous)
                        .stroke(DS.Palette.lime(0.28), lineWidth: 1)
                }
        }
        .buttonStyle(.dsPress)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.4)
    }

    private var addButton: some View {
        Button {
            add()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .bold))
                Text("script.add", bundle: .module)
                    .dsFont(.sans, .medium, 14)
            }
            .foregroundStyle(DS.Palette.ink(0.7))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                    .strokeBorder(DS.Palette.hairline(0.14), style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
            )
        }
        .buttonStyle(.dsPress(radius: DS.Radius.card))
    }

    // MARK: - Editing

    private func scriptBinding(at index: Int) -> Binding<String> {
        Binding(
            get: { project.segments.indices.contains(index) ? project.segments[index].script : "" },
            set: { text in
                guard project.segments.indices.contains(index) else { return }
                setScript(text, at: index)
            }
        )
    }

    /// Writes a beat's text, and its length with it while nothing has been shot: the blueprint bar,
    /// the studio pips and the running total all read that estimate.
    private func setScript(_ text: String, at index: Int) {
        project.segments[index].script = text
        if project.segments[index].takes.isEmpty {
            let words = ScriptText.words(in: text).count
            let perMinute = SpeakingRate.wordsPerMinute(forLocaleIdentifier: project.localeIdentifier)
            project.segments[index].estimatedDuration = MediaTime(seconds: max(1, Double(words) / perMinute * 60))
        }
        project.updatedAt = .now
    }

    private func rewrite(at index: Int, with action: RewriteAction) async {
        guard project.segments.indices.contains(index) else { return }
        let segment = project.segments[index]
        focused = nil
        failure = nil
        withAnimation(DS.Motion.settle) { working = segment.id }
        defer { withAnimation(DS.Motion.settle) { working = nil } }

        do {
            let result = try await ScriptRewriter().rewrite(
                segment.script,
                instruction: action.instruction,
                role: segment.role.displayLabel,
                script: project.segments.map(\.script).joined(separator: "\n"),
                localeIdentifier: project.localeIdentifier
            )
            guard !result.isEmpty, let current = project.segments.firstIndex(where: { $0.id == segment.id }) else { return }
            beforeRewrite[segment.id] = segment.script
            withAnimation(DS.Easing.ease(0.3)) { setScript(result, at: current) }
        } catch {
            failure = String(localized: "script.rewrite.failed", bundle: .module)
        }
    }

    private func undoRewrite(at index: Int) {
        guard project.segments.indices.contains(index),
              let previous = beforeRewrite.removeValue(forKey: project.segments[index].id)
        else { return }
        withAnimation(DS.Easing.ease(0.3)) { setScript(previous, at: index) }
    }

    private func add() {
        let segment = Segment(role: .mainPoint, script: "", estimatedDuration: MediaTime(seconds: 5))
        withAnimation(DS.Motion.settle) {
            project.segments.append(segment)
            project.updatedAt = .now
            openSegment = segment.id
        }
        focused = segment.id
    }

    private func move(from index: Int, to destination: Int) {
        guard project.segments.indices.contains(index), project.segments.indices.contains(destination) else { return }
        withAnimation(DS.Motion.settle) {
            project.segments.swapAt(index, destination)
            project.updatedAt = .now
        }
    }

    private func remove(at index: Int) {
        guard project.segments.indices.contains(index), project.segments.count > 1 else { return }
        withAnimation(DS.Motion.settle) {
            let removed = project.segments.remove(at: index)
            if openSegment == removed.id { openSegment = nil }
            project.updatedAt = .now
        }
    }
}

/// A band of light that sweeps across a beat while the model writes it.
private struct WritingShimmer: View {
    let color: Color
    @State private var sweep = false

    var body: some View {
        GeometryReader { proxy in
            LinearGradient(
                colors: [.clear, color.opacity(0.35), .clear],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: proxy.size.width * 0.5)
            .offset(x: sweep ? proxy.size.width : -proxy.size.width * 0.5)
            .animation(.easeInOut(duration: 1.1).repeatForever(autoreverses: false), value: sweep)
        }
        .allowsHitTesting(false)
        .clipped()
        .onAppear { sweep = true }
    }
}

/// The rewrite chips, each one an instruction to the on-device model.
public enum RewriteAction: String, CaseIterable, Sendable {
    case rewrite
    case shorter
    case longer
    case moreNatural
    case moreEnergetic

    var labelKey: String.LocalizationValue {
        switch self {
        case .rewrite: "script.action.rewrite"
        case .shorter: "script.action.shorter"
        case .longer: "script.action.longer"
        case .moreNatural: "script.action.moreNatural"
        case .moreEnergetic: "script.action.moreEnergetic"
        }
    }

    var instruction: ScriptRewriter.Instruction {
        switch self {
        case .rewrite: .rewrite
        case .shorter: .shorter
        case .longer: .longer
        case .moreNatural: .moreNatural
        case .moreEnergetic: .moreEnergetic
        }
    }
}
