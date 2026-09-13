import DesignSystem
import Domain
import SwiftUI

/// Everything that can be done to one sound, on one panel.
///
/// The controls are ordered by how often they are touched, not by how the engine is built: level
/// first because it is touched every time, then ducking because it is the reason the level is
/// wrong, then the fades, then speed, and the repair switches last because they are set once and
/// forgotten. An inspector ordered by the data model instead of by the hand is how professional
/// tools end up needing a manual.
struct AudioInspector: View {
    @Bindable var model: EditorModel
    let clip: AudioClip

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            level

            HStack(spacing: 9) {
                toggle(
                    "editor.audio.duck",
                    symbol: "waveform.badge.mic",
                    isOn: clip.ducksUnderVoice
                ) {
                    model.updateAudio(clip.id) { $0.ducksUnderVoice.toggle() }
                }

                toggle(
                    clip.isMuted ? "editor.tool.unmute" : "editor.tool.mute",
                    symbol: clip.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill",
                    isOn: clip.isMuted
                ) {
                    model.updateAudio(clip.id) { $0.isMuted.toggle() }
                }
            }

            fades

            speed

            effects
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 9) {
            Image(systemName: AudioLane.symbol(for: clip))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(AudioLane.tint(for: clip.role))

            Text(clip.name)
                .dsFont(.archivo, .bold, 17)
                .foregroundStyle(DS.Palette.ink)
                .lineLimit(1)

            Spacer(minLength: 0)

            // Role is what ducking keys off, so it is a control and not a label.
            Picker("", selection: roleBinding) {
                ForEach(AudioClip.Role.allCases, id: \.self) { role in
                    Text(Self.roleLabel(role)).tag(role)
                }
            }
            .pickerStyle(.menu)
            .tint(DS.Palette.ink(0.6))
        }
    }

    private var roleBinding: Binding<AudioClip.Role> {
        Binding(
            get: { clip.role },
            set: { role in
                model.updateAudio(clip.id) { edited in
                    edited.role = role
                    // Music arriving as music should duck; a voiceover should not duck under the
                    // voice it is competing with, it should replace it.
                    edited.ducksUnderVoice = role == .music
                }
            }
        )
    }

    // MARK: - Level

    /// In dB, because that is the scale ears are on. A linear fader spends three quarters of its
    /// travel in a range nobody uses and makes −6 and −12 feel like the same place.
    private var level: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("editor.audio.level", bundle: .module)
                    .dsFont(.mono, .medium, 9, letterSpacing: 0.12)
                    .foregroundStyle(DS.Palette.ink(0.38))
                Spacer(minLength: 0)
                Text(AudioLane.levelLabel(for: clip) + " dB")
                    .dsFont(.mono, .medium, 11)
                    .foregroundStyle(DS.Palette.ink(0.7))
                    .contentTransition(.numericText())
            }

            Slider(
                value: Binding(
                    get: { min(max(clip.decibels, -40), 6) },
                    set: { value in model.updateAudio(clip.id) { $0.setDecibels(value) } }
                ),
                in: -40...6
            )
            .tint(AudioLane.tint(for: clip.role))
            .disabled(clip.isMuted)
            .opacity(clip.isMuted ? 0.35 : 1)
        }
    }

    // MARK: - Fades

    private var fades: some View {
        HStack(spacing: 10) {
            stepper(
                "editor.audio.fadeIn",
                value: clip.fadeIn.seconds,
                symbol: "arrow.up.right"
            ) { delta in
                model.updateAudio(clip.id) {
                    $0.fadeIn = MediaTime(seconds: max(0, $0.fadeIn.seconds + delta))
                }
            }

            stepper(
                "editor.audio.fadeOut",
                value: clip.fadeOut.seconds,
                symbol: "arrow.down.right"
            ) { delta in
                model.updateAudio(clip.id) {
                    $0.fadeOut = MediaTime(seconds: max(0, $0.fadeOut.seconds + delta))
                }
            }
        }
    }

    // MARK: - Speed

    /// Fixed steps rather than a slider. Nobody wants 1.07×, and the steps are the ones people
    /// actually ask for. Pitch is preserved on export, so the voice stays the same person.
    private var speed: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("editor.audio.speed", bundle: .module)
                .dsFont(.mono, .medium, 9, letterSpacing: 0.12)
                .foregroundStyle(DS.Palette.ink(0.38))

            HStack(spacing: 6) {
                ForEach([0.5, 0.75, 1.0, 1.25, 1.5, 2.0], id: \.self) { value in
                    let isOn = abs(clip.speed - value) < 0.01
                    Button {
                        model.pulse(.speed)
                        model.updateAudio(clip.id) { $0.speed = value }
                    } label: {
                        Text(Self.speedLabel(value))
                            .dsFont(.mono, .medium, 11)
                            .foregroundStyle(isOn ? DS.Palette.inkInverse : DS.Palette.ink(0.6))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 9)
                            .background(
                                RoundedRectangle(cornerRadius: 11, style: .continuous)
                                    .fill(isOn ? DS.Palette.ink : DS.Palette.hairline(0.07))
                            )
                    }
                    .buttonStyle(.dsPress(radius: 11))
                    .dsMotion(DS.Motion.snap, reduced: reduceMotion, value: isOn)
                }
            }
        }
    }

    // MARK: - Repair

    /// Three switches, not a parametric EQ.
    ///
    /// Someone editing on a phone wants the sound fixed, not four bands and a Q control. The
    /// frequencies live in the engine where they can be tuned once for everybody — see
    /// `AudioEffectRenderer`, which is also honest about what filtering can and cannot do.
    private var effects: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("editor.audio.repair", bundle: .module)
                .dsFont(.mono, .medium, 9, letterSpacing: 0.12)
                .foregroundStyle(DS.Palette.ink(0.38))

            HStack(spacing: 9) {
                toggle(
                    "editor.audio.denoise",
                    symbol: "wind",
                    isOn: clip.effects.noiseReduction
                ) {
                    model.updateAudio(clip.id) { $0.effects.noiseReduction.toggle() }
                }

                toggle(
                    "editor.audio.enhance",
                    symbol: "person.wave.2",
                    isOn: clip.effects.voiceEnhance
                ) {
                    model.updateAudio(clip.id) { $0.effects.voiceEnhance.toggle() }
                }

                toggle(
                    "editor.audio.derumble",
                    symbol: "car",
                    isOn: clip.effects.deRumble
                ) {
                    model.updateAudio(clip.id) { $0.effects.deRumble.toggle() }
                }
            }
        }
    }

    // MARK: - Parts

    private func toggle(
        _ key: String.LocalizationValue,
        symbol: String,
        isOn: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: symbol)
                    .font(.system(size: 13, weight: .medium))
                    .symbolEffect(.bounce, value: isOn)
                Text(String(localized: key, bundle: .module))
                    .dsFont(.sans, .medium, 10)
                    .lineLimit(1)
            }
            .foregroundStyle(isOn ? DS.Palette.inkInverse : DS.Palette.ink(0.65))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(isOn ? DS.Palette.ink : DS.Palette.hairline(0.07))
            )
            .contentShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        }
        .buttonStyle(.dsPress(radius: 13))
        .dsMotion(DS.Motion.snap, reduced: reduceMotion, value: isOn)
    }

    private func stepper(
        _ key: String.LocalizationValue,
        value: Double,
        symbol: String,
        change: @escaping (Double) -> Void
    ) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(DS.Palette.ink(0.45))

            VStack(alignment: .leading, spacing: 1) {
                Text(String(localized: key, bundle: .module))
                    .dsFont(.mono, .medium, 9, letterSpacing: 0.12)
                    .foregroundStyle(DS.Palette.ink(0.38))
                Text(String(format: "%.1fs", value))
                    .dsFont(.mono, .medium, 12)
                    .foregroundStyle(DS.Palette.ink)
                    .contentTransition(.numericText())
            }

            Spacer(minLength: 0)

            Button { change(-0.2) } label: { nudge("minus") }
                .buttonStyle(.dsPressIcon)
            Button { change(0.2) } label: { nudge("plus") }
                .buttonStyle(.dsPressIcon)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(DS.Palette.hairline(0.05))
        )
    }

    private func nudge(_ symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(DS.Palette.ink(0.8))
            .frame(width: 26, height: 26)
            .background(Circle().fill(DS.Palette.hairline(0.09)))
    }

    static func speedLabel(_ value: Double) -> String {
        value == 1 ? "1×" : String(format: "%g×", value)
    }

    static func roleLabel(_ role: AudioClip.Role) -> String {
        switch role {
        case .music: String(localized: "editor.audio.role.music", bundle: .module)
        case .voiceover: String(localized: "editor.audio.role.voiceover", bundle: .module)
        case .effect: String(localized: "editor.audio.role.effect", bundle: .module)
        }
    }
}
