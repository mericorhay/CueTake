import DesignSystem
import Domain
import SwiftUI

/// The creator's voice as a profile: what was measured from their videos — pace, sentence length,
/// fillers — and what is theirs to write: how they open, how they send people to the link, the
/// words they never use. The prompter, the suflör and the AI all read it.
public struct VoiceProfileScreen: View {
    @Binding private var profile: CreatorVoiceProfile
    private let isMeasuring: Bool
    private let onMeasure: () -> Void
    private let onClose: () -> Void

    @State private var newOpening = ""
    @State private var newCall = ""
    @State private var newAvoid = ""
    @FocusState private var focused: Field?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private enum Field { case opening, call, avoid, notes }

    public init(profile: Binding<CreatorVoiceProfile>, isMeasuring: Bool, onMeasure: @escaping () -> Void, onClose: @escaping () -> Void) {
        _profile = profile
        self.isMeasuring = isMeasuring
        self.onMeasure = onMeasure
        self.onClose = onClose
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack {
                    DSKicker(AppLocalization.string("voice.kicker", bundle: .module), size: 11, tracking: 0.16)
                    Spacer(minLength: 0)
                    DSCircleButton("✕", size: 44, fontSize: 15) { onClose() }
                        .accessibilityLabel(Text("voice.close", bundle: .module))
                }
                DSHeadline(AppLocalization.string("voice.title", bundle: .module), size: 34)
                Text("voice.subtitle", bundle: .module)
                    .dsFont(.sans, .regular, 15, lineHeight: 1.4)
                    .foregroundStyle(DS.Palette.ink(0.66))
                    .fixedSize(horizontal: false, vertical: true)

                measured
                paceSwitch
                list("voice.openings", hint: "voice.openings.hint", items: $profile.openings, text: $newOpening, field: .opening, tint: DS.Palette.lime)
                list("voice.calls", hint: "voice.calls.hint", items: $profile.callsToAction, text: $newCall, field: .call, tint: DS.Palette.accentWarm)
                list("voice.avoid", hint: "voice.avoid.hint", items: $profile.avoid, text: $newAvoid, field: .avoid, tint: DS.Palette.accent)
                notes
            }
            .padding(.horizontal, 22)
            .padding(.top, 60)
            .padding(.bottom, 60)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .background(DS.Palette.screen)
        .animation(reduceMotion ? nil : DS.Motion.settle, value: profile)
    }

    // MARK: - Measured

    private var measured: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                stat(profile.wordsPerMinute.map { "\(Int($0.rounded()))" } ?? "—", "voice.stat.pace")
                stat(profile.sentenceWords.map { String(format: "%.0f", $0) } ?? "—", "voice.stat.sentence")
                stat(profile.measuredVideos > 0 ? "\(profile.measuredVideos)" : "—", "voice.stat.videos")
            }
            if !profile.fillers.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    DSKicker(AppLocalization.string("voice.fillers", bundle: .module), size: 10, color: DS.Palette.ink(0.56))
                    FlowLayout(horizontalSpacing: 6, verticalSpacing: 6) {
                        ForEach(profile.fillers, id: \.self) { filler in
                            Text(verbatim: filler)
                                .dsFont(.sans, .semibold, 13)
                                .foregroundStyle(DS.Palette.ink(0.85))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Capsule().fill(DS.Palette.hairline(0.1)))
                        }
                    }
                }
            }
            Group {
                if profile.measuredVideos == 0 {
                    Text("voice.measure.none", bundle: .module)
                } else {
                    Text("voice.measure.from \(profile.measuredWords) \(profile.measuredVideos)", bundle: .module)
                }
            }
            .dsFont(.sans, .regular, 12, lineHeight: 1.3)
            .foregroundStyle(DS.Palette.ink(0.56))
            .fixedSize(horizontal: false, vertical: true)
            Button(action: onMeasure) {
                HStack(spacing: 8) {
                    if isMeasuring {
                        ProgressView().tint(DS.Palette.inkInverse)
                        Text("voice.measuring", bundle: .module)
                    } else {
                        Image(systemName: "waveform.badge.magnifyingglass")
                        Text("voice.measure", bundle: .module)
                    }
                }
                .dsFont(.sans, .semibold, 15)
                .foregroundStyle(DS.Palette.inkInverse)
                .frame(maxWidth: .infinity, minHeight: 50)
                .background(Capsule().fill(DS.Palette.lime))
            }
            .buttonStyle(.dsPress)
            .disabled(isMeasuring)
        }
        .padding(16)
        .dsCard(radius: 22)
    }

    private func stat(_ value: String, _ label: String.LocalizationValue) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(verbatim: value)
                .dsFont(.archivo, .bold, 26)
                .foregroundStyle(DS.Palette.ink)
                .monospacedDigit()
                .contentTransition(.numericText())
            Text(AppLocalization.string(label, bundle: .module))
                .dsFont(.mono, .medium, 9, letterSpacing: 0.1)
                .foregroundStyle(DS.Palette.ink(0.56))
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var paceSwitch: some View {
        Button {
            profile.usesPace.toggle()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "speedometer")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(profile.usesPace ? DS.Palette.inkInverse : DS.Palette.ink(0.8))
                    .frame(width: 42, height: 42)
                    .background(Circle().fill(profile.usesPace ? DS.Palette.lime : DS.Palette.hairline(0.08)))
                VStack(alignment: .leading, spacing: 3) {
                    Text("voice.pace.title", bundle: .module)
                        .dsFont(.sans, .semibold, 15)
                        .foregroundStyle(DS.Palette.ink)
                    Text("voice.pace.detail", bundle: .module)
                        .dsFont(.sans, .regular, 12, lineHeight: 1.3)
                        .foregroundStyle(DS.Palette.ink(0.6))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Capsule()
                    .fill(profile.usesPace ? DS.Palette.lime : DS.Palette.hairline(0.14))
                    .frame(width: 46, height: 28)
                    .overlay(alignment: profile.usesPace ? .trailing : .leading) {
                        Circle().fill(profile.usesPace ? DS.Palette.inkInverse : DS.Palette.ink(0.8)).padding(3)
                    }
            }
            .padding(14)
            .dsCard(radius: 20)
        }
        .buttonStyle(.dsPressCard)
        .accessibilityAddTraits(.isToggle)
    }

    // MARK: - Written

    private func list(
        _ title: String.LocalizationValue,
        hint: String.LocalizationValue,
        items: Binding<[String]>,
        text: Binding<String>,
        field: Field,
        tint: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            DSKicker(AppLocalization.string(title, bundle: .module))
            VStack(alignment: .leading, spacing: 8) {
                ForEach(items.wrappedValue, id: \.self) { item in
                    HStack(spacing: 10) {
                        Capsule().fill(tint).frame(width: 4, height: 18)
                        Text(verbatim: item)
                            .dsFont(.sans, .medium, 15)
                            .foregroundStyle(DS.Palette.ink)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                        Button {
                            items.wrappedValue.removeAll { $0 == item }
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(DS.Palette.ink(0.6))
                                .frame(width: 36, height: 36)
                        }
                        .buttonStyle(.dsPressIcon)
                        .accessibilityLabel(Text("voice.remove \(item)", bundle: .module))
                    }
                    .padding(.leading, 12)
                    .dsCard(radius: 14)
                }
                HStack(spacing: 8) {
                    Image(systemName: "plus").font(.system(size: 12, weight: .bold)).foregroundStyle(DS.Palette.ink(0.6))
                    TextField(AppLocalization.string("voice.add", bundle: .module), text: text)
                        .focused($focused, equals: field)
                        .dsFont(.sans, .medium, 15)
                        .submitLabel(.done)
                        .onSubmit {
                            let value = text.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines)
                            text.wrappedValue = ""
                            guard !value.isEmpty, !items.wrappedValue.contains(value) else { return }
                            items.wrappedValue.append(value)
                            focused = field
                        }
                }
                .padding(.horizontal, 14)
                .frame(minHeight: 48)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(DS.Palette.hairline(0.16), style: StrokeStyle(lineWidth: 1, dash: [4, 4])))
            }
            Text(AppLocalization.string(hint, bundle: .module))
                .dsFont(.sans, .regular, 12)
                .foregroundStyle(DS.Palette.ink(0.52))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var notes: some View {
        VStack(alignment: .leading, spacing: 8) {
            DSKicker(AppLocalization.string("voice.notes", bundle: .module))
            TextField(AppLocalization.string("voice.notes.placeholder", bundle: .module), text: $profile.notes, axis: .vertical)
                .lineLimit(3...6)
                .focused($focused, equals: .notes)
                .dsFont(.sans, .regular, 15)
                .foregroundStyle(DS.Palette.ink)
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .dsCard(radius: 16, border: focused == .notes ? DS.Palette.lime(0.6) : DS.Palette.hairline(0.07))
        }
    }
}
