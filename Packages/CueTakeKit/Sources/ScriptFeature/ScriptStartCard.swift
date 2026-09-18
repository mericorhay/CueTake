import DesignSystem
import Domain
import SwiftUI

/// Where a script begins: pasted from somewhere, written by the AI from an idea, or picked from the
/// scripts kept for reuse.
struct ScriptStartCard: View {
    enum Mode: Hashable {
        case paste
        case write
    }

    let localeIdentifier: String
    let library: ScriptLibraryStore?
    let writer: ScriptScreen.Writer?
    /// The beats to put in the project, and a title when the AI gave one.
    let onBeats: ([SegmentDraft], String?) -> Void
    let onEditBrand: () -> Void

    @State private var mode: Mode = .paste
    @State private var pasted = ""
    @State private var idea = ""
    @State private var seconds = 30
    @State private var isWriting = false
    @State private var failure: String?
    @State private var savedNote = false
    @FocusState private var typing: Bool

    private var pastedIsEmpty: Bool { pasted.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    private var ideaIsEmpty: Bool { idea.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if writer != nil {
                modePicker
            }

            switch mode {
            case .paste: pasteBody
            case .write: writeBody
            }

            if let library, !library.scripts.isEmpty {
                savedRow(library)
            }
        }
        .padding(16)
        .dsCard(radius: DS.Radius.card)
        .animation(DS.Motion.settle, value: mode)
        .animation(DS.Motion.settle, value: isWriting)
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    // MARK: - Mode

    private var modePicker: some View {
        HStack(spacing: 6) {
            modeButton(.paste, symbol: "doc.on.clipboard") {
                Text("script.start.paste", bundle: .module)
            }
            modeButton(.write, symbol: "sparkles") {
                Text("script.start.write", bundle: .module)
            }
        }
    }

    private func modeButton<Title: View>(_ target: Mode, symbol: String, @ViewBuilder label: () -> Title) -> some View {
        let isOn = mode == target
        return Button {
            typing = false
            mode = target
        } label: {
            HStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.system(size: 12, weight: .semibold))
                label()
                    .dsFont(.sans, .semibold, 13)
            }
            .foregroundStyle(isOn ? DS.Palette.inkInverse : DS.Palette.ink(0.7))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isOn ? DS.Palette.lime : DS.Palette.hairline(0.06))
            )
        }
        .buttonStyle(.dsPress(radius: 12))
    }

    // MARK: - Paste

    private var pasteBody: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("script.paste.title", bundle: .module)
                    .dsFont(.sans, .semibold, 15)
                    .foregroundStyle(DS.Palette.ink)
                Spacer(minLength: 0)
                PasteButton(payloadType: String.self) { strings in
                    guard let text = strings.first else { return }
                    Task { @MainActor in pasted = text }
                }
                .buttonBorderShape(.capsule)
                .labelStyle(.titleAndIcon)
                .tint(DS.Palette.lime)
                .controlSize(.small)
            }

            TextField(String(localized: "script.paste.placeholder", bundle: .module), text: $pasted, axis: .vertical)
                .lineLimit(6...14)
                .dsFont(.sans, .regular, 15, lineHeight: 1.45)
                .foregroundStyle(DS.Palette.ink)
                .tint(DS.Palette.lime)
                .focused($typing)
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(DS.Palette.hairline(0.05)))

            HStack(spacing: 8) {
                Text("script.paste.hint", bundle: .module)
                    .dsFont(.sans, .regular, 12, lineHeight: 1.35)
                    .foregroundStyle(DS.Palette.ink(0.56))
                Spacer(minLength: 0)
                if let library, !pastedIsEmpty {
                    Button {
                        library.save(pasted)
                        savedNote = true
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: savedNote ? "checkmark" : "bookmark")
                                .font(.system(size: 11, weight: .semibold))
                            if savedNote {
                                Text("script.library.saved", bundle: .module)
                            } else {
                                Text("script.library.save", bundle: .module)
                            }
                        }
                        .dsFont(.sans, .medium, 12)
                        .foregroundStyle(DS.Palette.lime)
                    }
                    .buttonStyle(.dsPress)
                    .disabled(savedNote)
                }
            }
            .onChange(of: pasted) { _, _ in savedNote = false }

            DSPrimaryButton(
                String(localized: "script.paste.split", bundle: .module),
                verticalPadding: 14,
                fontSize: 15,
                glow: false
            ) {
                let beats = ScriptText.beats(from: pasted, localeIdentifier: localeIdentifier)
                guard !beats.isEmpty else { return }
                typing = false
                onBeats(beats, nil)
                pasted = ""
            }
            .disabled(pastedIsEmpty)
            .opacity(pastedIsEmpty ? 0.45 : 1)
        }
    }

    // MARK: - Write

    private var writeBody: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("script.write.title", bundle: .module)
                .dsFont(.sans, .semibold, 15)
                .foregroundStyle(DS.Palette.ink)

            TextField(String(localized: "script.write.placeholder", bundle: .module), text: $idea, axis: .vertical)
                .lineLimit(2...5)
                .dsFont(.sans, .regular, 15, lineHeight: 1.45)
                .foregroundStyle(DS.Palette.ink)
                .tint(DS.Palette.lime)
                .focused($typing)
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(DS.Palette.hairline(0.05)))
                .disabled(isWriting)

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("script.write.length", bundle: .module)
                        .dsFont(.sans, .medium, 12)
                        .foregroundStyle(DS.Palette.ink(0.55))
                    Spacer(minLength: 0)
                    Text(String(localized: "script.write.words \(ScriptBudget.maxWords(seconds: Double(seconds), localeIdentifier: localeIdentifier))", bundle: .module))
                        .dsFont(.mono, .medium, 10)
                        .foregroundStyle(DS.Palette.ink(0.56))
                        .contentTransition(.numericText())
                }
                HStack(spacing: 6) {
                    ForEach(ScriptBudget.lengthChoices, id: \.self) { choice in
                        DSPill(
                            String(localized: "script.write.seconds \(choice)", bundle: .module),
                            isOn: seconds == choice,
                            fontSize: 12,
                            radius: 10,
                            verticalPadding: 8
                        ) {
                            seconds = choice
                        }
                    }
                }
            }

            if let library {
                brandRow(library)
            }

            if let failure {
                Text(failure)
                    .dsFont(.sans, .regular, 12, lineHeight: 1.35)
                    .foregroundStyle(DS.Palette.accent)
                    .transition(.opacity)
            }

            Button {
                write()
            } label: {
                HStack(spacing: 8) {
                    if isWriting {
                        ProgressView()
                            .tint(DS.Palette.inkInverse)
                            .controlSize(.small)
                        Text("script.write.working", bundle: .module)
                    } else {
                        Image(systemName: "sparkles")
                            .font(.system(size: 13, weight: .semibold))
                        Text("script.write.go", bundle: .module)
                    }
                }
                .dsFont(.sans, .semibold, 15)
                .foregroundStyle(DS.Palette.inkInverse)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(DS.Palette.lime)
                )
            }
            .buttonStyle(.dsPress(radius: 16))
            .disabled(ideaIsEmpty || isWriting)
            .opacity(ideaIsEmpty && !isWriting ? 0.45 : 1)
        }
    }

    private func brandRow(_ library: ScriptLibraryStore) -> some View {
        HStack(spacing: 8) {
            if library.brand.isEmpty {
                Button(action: onEditBrand) {
                    HStack(spacing: 6) {
                        Image(systemName: "seal")
                            .font(.system(size: 12, weight: .semibold))
                        Text("script.brand.add", bundle: .module)
                            .dsFont(.sans, .medium, 12)
                    }
                    .foregroundStyle(DS.Palette.ink(0.7))
                }
                .buttonStyle(.dsPress)
            } else {
                Button {
                    library.setUsesBrand(!library.usesBrand)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: library.usesBrand ? "checkmark.seal.fill" : "seal")
                            .font(.system(size: 12, weight: .semibold))
                        Text(String(localized: "script.brand.use \(Self.brandName(library.brand))", bundle: .module))
                            .dsFont(.sans, .medium, 12)
                            .lineLimit(1)
                    }
                    .foregroundStyle(library.usesBrand ? DS.Palette.lime : DS.Palette.ink(0.5))
                }
                .buttonStyle(.dsPress)

                Spacer(minLength: 0)

                Button(action: onEditBrand) {
                    Text("script.brand.edit", bundle: .module)
                        .dsFont(.sans, .medium, 12)
                        .foregroundStyle(DS.Palette.ink(0.6))
                }
                .buttonStyle(.dsPress)
            }
        }
    }

    static func brandName(_ brand: BrandVoice) -> String {
        let name = brand.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? String(localized: "script.brand.unnamed", bundle: .module) : name
    }

    private func write() {
        guard let writer, !ideaIsEmpty, !isWriting else { return }
        typing = false
        failure = nil
        isWriting = true
        let brief = ScriptBrief(
            topic: idea.trimmingCharacters(in: .whitespacesAndNewlines),
            targetDuration: MediaTime(seconds: Double(seconds)),
            platform: .generic,
            localeIdentifier: localeIdentifier,
            brand: library?.activeBrand
        )
        Task { @MainActor in
            do {
                let draft = try await writer(brief)
                isWriting = false
                guard !draft.segments.isEmpty else {
                    failure = String(localized: "script.write.empty", bundle: .module)
                    return
                }
                onBeats(draft.segments, draft.title)
                idea = ""
            } catch {
                isWriting = false
                failure = error.localizedDescription
            }
        }
    }

    // MARK: - Saved

    private func savedRow(_ library: ScriptLibraryStore) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            DSKicker(String(localized: "script.library.title", bundle: .module), size: 10, color: DS.Palette.ink(0.56))
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(library.scripts) { saved in
                        Button {
                            library.touch(saved.id)
                            pasted = saved.text
                            mode = .paste
                        } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(saved.title)
                                    .dsFont(.sans, .semibold, 13)
                                    .foregroundStyle(DS.Palette.ink)
                                    .lineLimit(1)
                                Text(String(localized: "script.library.words \(ScriptText.words(in: saved.text).count)", bundle: .module))
                                    .dsFont(.mono, .medium, 10)
                                    .foregroundStyle(DS.Palette.ink(0.56))
                            }
                            .frame(width: 140, alignment: .leading)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(DS.Palette.hairline(0.06))
                            )
                        }
                        .buttonStyle(.dsPress(radius: 12))
                        .contextMenu {
                            Button(role: .destructive) {
                                library.delete(saved.id)
                            } label: {
                                Label(String(localized: "script.library.delete", bundle: .module), systemImage: "trash")
                            }
                        }
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
    }
}

/// The brand the AI writes for: a few short fields, not a brand book.
struct BrandVoiceSheet: View {
    let initial: BrandVoice
    let onSave: (BrandVoice) -> Void
    let onClose: () -> Void

    @State private var draft = BrandVoice()

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(String(localized: "script.brand.name", bundle: .module), text: $draft.name)
                    TextField(String(localized: "script.brand.about", bundle: .module), text: $draft.about, axis: .vertical)
                        .lineLimit(2...4)
                    TextField(String(localized: "script.brand.audience", bundle: .module), text: $draft.audience, axis: .vertical)
                        .lineLimit(1...3)
                } footer: {
                    Text("script.brand.footer", bundle: .module)
                }
                Section {
                    TextField(String(localized: "script.brand.mustSay", bundle: .module), text: $draft.mustSay, axis: .vertical)
                        .lineLimit(1...3)
                    TextField(String(localized: "script.brand.avoid", bundle: .module), text: $draft.avoid, axis: .vertical)
                        .lineLimit(1...3)
                }
            }
            .scrollContentBackground(.hidden)
            .background(DS.Palette.screen)
            .navigationTitle(String(localized: "script.brand.title", bundle: .module))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "script.brand.cancel", bundle: .module), action: onClose)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "script.brand.save", bundle: .module)) {
                        onSave(draft)
                        onClose()
                    }
                }
            }
        }
        .tint(DS.Palette.lime)
        .onAppear { draft = initial }
    }
}
