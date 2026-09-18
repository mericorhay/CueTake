import DesignSystem
import Domain
import Persistence
import SwiftUI
import UIKit
import WorkflowEngine

/// The closing export: the format the video is written in, where it goes on the phone, and the
/// API it is sent to.
///
/// Resolution and frame rate are the style's own numbers, shown again here because this is where
/// people look for them. They used to be a fixed "1080p · 30fps" on this card whatever the style
/// said, and the run ignored the card entirely.
struct StudioExportEditor: View {
    @Bindable var model: WorkflowStudioModel
    let preset: ExportPreset

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            chips(
                "studio.style.resolution",
                options: VideoFormat.Resolution.allCases,
                selected: model.definition.style.resolution,
                enabled: { _ in true },
                label: { $0.label }
            ) { value in
                withAnimation(DS.Motion.snap) { model.setExportFormat(resolution: value) }
            }

            chips(
                "studio.style.frameRate",
                options: VideoFormat.frameRateChoices,
                selected: model.definition.style.frameRate,
                enabled: { rate in
                    VideoFormat(aspectRatio: model.definition.style.aspect, resolution: model.definition.style.resolution, frameRate: rate).isPhysicallyPlausible
                },
                label: { "\($0) fps" }
            ) { value in
                withAnimation(DS.Motion.snap) { model.setExportFormat(frameRate: value) }
            }

            let size = model.definition.style.format.renderSize
            Text(verbatim: "\(size.width)×\(size.height) · \(model.definition.style.frameRate) fps · \(model.definition.style.resolution.prefersHEVC ? "HEVC" : "H.264")")
                .dsFont(.mono, .medium, 10)
                .foregroundStyle(DS.Palette.ink(0.56))
                .contentTransition(.numericText())

            chips(
                "studio.param.destination",
                options: ExportDestination.allCases,
                selected: preset.destination,
                enabled: { _ in true },
                label: { $0 == .photoLibrary
                    ? String(localized: "studio.param.photos", bundle: .module)
                    : String(localized: "studio.param.files", bundle: .module) }
            ) { value in
                model.updateExport { $0.destination = value }
            }

            StudioDeliveryEditor(model: model, delivery: preset.delivery ?? WorkflowDelivery())
        }
    }

    private func chips<Value: Hashable>(
        _ key: String.LocalizationValue,
        options: [Value],
        selected: Value,
        enabled: @escaping (Value) -> Bool,
        label text: @escaping (Value) -> String,
        set: @escaping (Value) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(String(localized: key, bundle: .module))
                .dsFont(.mono, .medium, 10, letterSpacing: 0.12)
                .foregroundStyle(DS.Palette.ink(0.52))
            HStack(spacing: 5) {
                ForEach(options, id: \.self) { option in
                    let isOn = option == selected
                    let isEnabled = enabled(option)
                    Button {
                        set(option)
                    } label: {
                        Text(text(option))
                            .dsFont(.mono, .medium, 11)
                            .foregroundStyle(isOn ? DS.Palette.inkInverse : DS.Palette.ink(isEnabled ? 0.6 : 0.2))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 9)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(isOn ? DS.Palette.ink : DS.Palette.hairline(0.07))
                            )
                    }
                    .buttonStyle(.dsPress(radius: 10))
                    .disabled(!isEnabled)
                    .animation(DS.Motion.snap, value: isOn)
                }
            }
        }
    }
}

/// The workflow's own API: where the finished video is sent, how, and with what secret.
struct StudioDeliveryEditor: View {
    @Bindable var model: WorkflowStudioModel
    let delivery: WorkflowDelivery

    @State private var secret = ""
    @State private var savedSuffix: String?
    @State private var newFieldKey = ""
    @State private var newFieldValue = ""
    @State private var showsAdvanced = false
    @FocusState private var focused: Field?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private enum Field: Hashable { case endpoint, secret, header, prefix, fileField, key, value }

    private let secrets = WorkflowSecretStore()
    private var workflowID: UUID { model.definition.id }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "paperplane.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(delivery.isEnabled ? DS.Palette.lime : DS.Palette.ink(0.4))
                    .symbolEffect(.bounce, value: delivery.isEnabled)
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(DS.Palette.hairline(0.08)))
                VStack(alignment: .leading, spacing: 1) {
                    Text("studio.delivery.title", bundle: .module)
                        .dsFont(.sans, .semibold, 13)
                        .foregroundStyle(DS.Palette.ink)
                    Text("studio.delivery.note", bundle: .module)
                        .dsFont(.sans, .regular, 10, lineHeight: 1.3)
                        .foregroundStyle(DS.Palette.ink(0.56))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Toggle("", isOn: Binding(
                    get: { delivery.isEnabled },
                    set: { value in withAnimation(DS.Motion.settle) { model.updateDelivery { $0.isEnabled = value } } }
                ))
                .labelsHidden()
                .tint(DS.Palette.lime)
            }

            if delivery.isEnabled {
                settings
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(DS.Palette.hairline(0.05)))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(delivery.isEnabled ? DS.Palette.lime(0.35) : DS.Palette.hairline(0.08), lineWidth: 1)
        }
        .animation(reduceMotion ? nil : DS.Motion.settle, value: delivery.isEnabled)
        .onAppear { savedSuffix = secrets.suffix(for: workflowID) }
    }

    private var settings: some View {
        VStack(alignment: .leading, spacing: 10) {
            field(
                "studio.delivery.endpoint",
                text: Binding(get: { delivery.endpoint }, set: { value in model.updateDelivery { $0.endpoint = value } }),
                prompt: "https://api.example.com/videos",
                focus: .endpoint,
                keyboard: .URL
            )
            if !delivery.endpoint.isEmpty, delivery.url == nil {
                Label(String(localized: "studio.warning.deliveryURL", bundle: .module), systemImage: "exclamationmark.triangle.fill")
                    .dsFont(.sans, .regular, 10)
                    .foregroundStyle(DS.Palette.accentWarm)
            }

            HStack(spacing: 5) {
                ForEach(WorkflowDelivery.Payload.allCases, id: \.self) { payload in
                    pill(Self.payloadTitle(payload), isOn: delivery.payload == payload) {
                        model.updateDelivery { $0.payload = payload }
                    }
                }
            }
            Text(Self.payloadNote(delivery.payload))
                .dsFont(.sans, .regular, 10, lineHeight: 1.3)
                .foregroundStyle(DS.Palette.ink(0.56))
                .fixedSize(horizontal: false, vertical: true)
                .contentTransition(.opacity)

            secretRow

            DisclosureGroup(isExpanded: $showsAdvanced) {
                advanced
                    .padding(.top, 8)
            } label: {
                Text("studio.delivery.advanced", bundle: .module)
                    .dsFont(.sans, .medium, 12)
                    .foregroundStyle(DS.Palette.ink(0.7))
            }
            .tint(DS.Palette.ink(0.5))

            testRow
        }
    }

    // MARK: - Secret

    private var secretRow: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("studio.delivery.secret", bundle: .module)
                .dsFont(.mono, .medium, 10, letterSpacing: 0.12)
                .foregroundStyle(DS.Palette.ink(0.52))
            HStack(spacing: 6) {
                SecureField(
                    savedSuffix.map { String(localized: "studio.delivery.secret.saved \($0)", bundle: .module) }
                        ?? String(localized: "studio.delivery.secret.placeholder", bundle: .module),
                    text: $secret
                )
                .dsFont(.mono, .regular, 12)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($focused, equals: .secret)
                .submitLabel(.done)
                .onSubmit(saveSecret)
                .padding(.horizontal, 10)
                .padding(.vertical, 9)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(DS.Palette.hairline(0.06)))

                if !secret.isEmpty {
                    Button(action: saveSecret) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(DS.Palette.inkInverse)
                            .frame(width: 36, height: 36)
                            .background(Circle().fill(DS.Palette.lime))
                    }
                    .buttonStyle(.dsPressIcon)
                    .accessibilityLabel(Text("studio.delivery.secret.save", bundle: .module))
                    .transition(.scale.combined(with: .opacity))
                } else if savedSuffix != nil {
                    Button {
                        secrets.remove(for: workflowID)
                        withAnimation(DS.Motion.snap) { savedSuffix = nil }
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(DS.Palette.accent)
                            .frame(width: 36, height: 36)
                            .background(Circle().fill(DS.Palette.hairline(0.08)))
                    }
                    .buttonStyle(.dsPressIcon)
                    .accessibilityLabel(Text("studio.delivery.secret.remove", bundle: .module))
                }
            }
            .animation(DS.Motion.snap, value: secret.isEmpty)
            Text("studio.delivery.secret.note", bundle: .module)
                .dsFont(.sans, .regular, 10)
                .foregroundStyle(DS.Palette.ink(0.52))
        }
    }

    private func saveSecret() {
        guard !secret.isEmpty else { return }
        secrets.save(secret, for: workflowID)
        secret = ""
        focused = nil
        withAnimation(DS.Motion.snap) { savedSuffix = secrets.suffix(for: workflowID) }
        model.deliveryTest = nil
    }

    // MARK: - Advanced

    private var advanced: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 5) {
                ForEach(WorkflowDelivery.Method.allCases, id: \.self) { method in
                    pill(method.rawValue, isOn: delivery.method == method) {
                        model.updateDelivery { $0.method = method }
                    }
                }
            }
            HStack(spacing: 6) {
                field(
                    "studio.delivery.header",
                    text: Binding(get: { delivery.authHeader }, set: { value in model.updateDelivery { $0.authHeader = value } }),
                    prompt: "Authorization",
                    focus: .header
                )
                field(
                    "studio.delivery.prefix",
                    text: Binding(get: { delivery.authPrefix }, set: { value in model.updateDelivery { $0.authPrefix = value } }),
                    prompt: "Bearer ",
                    focus: .prefix
                )
            }
            if delivery.payload == .multipart {
                field(
                    "studio.delivery.fileField",
                    text: Binding(get: { delivery.fileField }, set: { value in model.updateDelivery { $0.fileField = value } }),
                    prompt: "video",
                    focus: .fileField
                )
            }

            Text("studio.delivery.fields", bundle: .module)
                .dsFont(.mono, .medium, 10, letterSpacing: 0.12)
                .foregroundStyle(DS.Palette.ink(0.52))
            ForEach(delivery.fields.keys.sorted(), id: \.self) { key in
                HStack(spacing: 6) {
                    Text(verbatim: key)
                        .dsFont(.mono, .semibold, 11)
                        .foregroundStyle(DS.Palette.ink(0.8))
                    Text(verbatim: delivery.fields[key] ?? "")
                        .dsFont(.mono, .regular, 11)
                        .foregroundStyle(DS.Palette.ink(0.55))
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Button {
                        withAnimation(DS.Motion.snap) { model.updateDelivery { $0.fields[key] = nil } }
                    } label: {
                        Image(systemName: "xmark")
                            .dsActionName("xmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(DS.Palette.ink(0.5))
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.dsPressIcon)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Capsule().fill(DS.Palette.hairline(0.06)))
                .transition(.opacity)
            }
            HStack(spacing: 6) {
                TextField(String(localized: "studio.delivery.fieldKey", bundle: .module), text: $newFieldKey)
                    .focused($focused, equals: .key)
                    .frame(maxWidth: 110)
                TextField(String(localized: "studio.delivery.fieldValue", bundle: .module), text: $newFieldValue)
                    .focused($focused, equals: .value)
                    .onSubmit(addField)
                Button(action: addField) {
                    Image(systemName: "plus")
                        .dsActionName("plus")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(DS.Palette.inkInverse)
                        .frame(width: 30, height: 30)
                        .background(Circle().fill(newFieldKey.isEmpty ? DS.Palette.ink(0.25) : DS.Palette.lime))
                }
                .buttonStyle(.dsPressIcon)
                .disabled(newFieldKey.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .dsFont(.mono, .regular, 11)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(DS.Palette.hairline(0.05)))
        }
    }

    private func addField() {
        let key = newFieldKey.trimmingCharacters(in: .whitespaces)
        guard !key.isEmpty else { return }
        let value = newFieldValue
        withAnimation(DS.Motion.snap) { model.updateDelivery { $0.fields[key] = value } }
        newFieldKey = ""
        newFieldValue = ""
        focused = .key
    }

    // MARK: - Test

    private var testRow: some View {
        HStack(spacing: 8) {
            Button {
                Task { await runTest() }
            } label: {
                HStack(spacing: 6) {
                    if model.deliveryTest == .sending {
                        ProgressView().controlSize(.small).tint(DS.Palette.ink)
                    } else {
                        Image(systemName: "bolt.horizontal.fill")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    Text("studio.delivery.test", bundle: .module)
                        .dsFont(.sans, .semibold, 12)
                }
                .foregroundStyle(DS.Palette.ink)
                .padding(.horizontal, 14)
                .frame(height: 38)
                .background(Capsule().fill(DS.Palette.hairline(0.1)))
            }
            .buttonStyle(.dsPress(radius: 19))
            .disabled(delivery.url == nil || model.deliveryTest == .sending)

            Group {
                switch model.deliveryTest {
                case .sent(let status):
                    Label(String(localized: "studio.delivery.ok \(status)", bundle: .module), systemImage: "checkmark.circle.fill")
                        .foregroundStyle(DS.Palette.lime)
                case .failed(let reason):
                    Label(reason, systemImage: "xmark.octagon.fill")
                        .foregroundStyle(DS.Palette.accent)
                        .lineLimit(2)
                default:
                    EmptyView()
                }
            }
            .dsFont(.sans, .medium, 11)
            .transition(.blurReplace)
        }
        .animation(DS.Motion.snap, value: model.deliveryTest)
        .sensoryFeedback(trigger: model.deliveryTest) { _, result in
            switch result {
            case .sent: .success
            case .failed: .error
            default: nil
            }
        }
    }

    private func runTest() async {
        saveSecret()
        model.deliveryTest = .sending
        let current = delivery
        let definition = model.definition
        let secret = secrets.secret(for: workflowID)
        do {
            let outcome = try await WorkflowDeliveryClient().test(current, workflow: definition, secret: secret)
            model.deliveryTest = .sent(status: outcome.status)
        } catch {
            model.deliveryTest = .failed(Self.describe(error))
        }
    }

    // MARK: - Parts

    private func field(
        _ key: String.LocalizationValue,
        text: Binding<String>,
        prompt: String,
        focus: Field,
        keyboard: UIKeyboardType = .default
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(String(localized: key, bundle: .module))
                .dsFont(.mono, .medium, 10, letterSpacing: 0.12)
                .foregroundStyle(DS.Palette.ink(0.52))
            TextField(prompt, text: text)
                .dsFont(.mono, .regular, 12)
                .keyboardType(keyboard)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($focused, equals: focus)
                .padding(.horizontal, 10)
                .padding(.vertical, 9)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(DS.Palette.hairline(0.06)))
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(focused == focus ? DS.Palette.lime(0.6) : .clear, lineWidth: 1)
                }
        }
    }

    private func pill(_ title: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button {
            withAnimation(DS.Motion.snap) { action() }
        } label: {
            Text(title)
                .dsFont(.sans, .semibold, 11)
                .foregroundStyle(isOn ? DS.Palette.inkInverse : DS.Palette.ink(0.65))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(Capsule().fill(isOn ? DS.Palette.ink : DS.Palette.hairline(0.07)))
        }
        .buttonStyle(.dsPress(radius: 16))
    }

    static func payloadTitle(_ payload: WorkflowDelivery.Payload) -> String {
        switch payload {
        case .multipart: String(localized: "studio.delivery.multipart", bundle: .module)
        case .rawVideo: String(localized: "studio.delivery.raw", bundle: .module)
        case .json: String(localized: "studio.delivery.json", bundle: .module)
        }
    }

    static func payloadNote(_ payload: WorkflowDelivery.Payload) -> String {
        switch payload {
        case .multipart: String(localized: "studio.delivery.multipart.note", bundle: .module)
        case .rawVideo: String(localized: "studio.delivery.raw.note", bundle: .module)
        case .json: String(localized: "studio.delivery.json.note", bundle: .module)
        }
    }

    static func describe(_ error: any Error) -> String { StudioDeliveryText.describe(error) }
}

/// A delivery failure in words, for the editor here and the run in the app.
public enum StudioDeliveryText {
    public static func describe(_ error: any Error) -> String {
        switch error {
        case WorkflowDeliveryClient.DeliveryError.invalidEndpoint:
            String(localized: "studio.warning.deliveryURL", bundle: .module)
        case WorkflowDeliveryClient.DeliveryError.missingFile:
            String(localized: "studio.delivery.error.file", bundle: .module)
        case WorkflowDeliveryClient.DeliveryError.rejected(let status, let reply):
            String(localized: "studio.delivery.error.status \(status)", bundle: .module)
                + (reply.isEmpty ? "" : " · " + String(reply.prefix(80)))
        case WorkflowDeliveryClient.DeliveryError.transport(let reason):
            reason
        default:
            error.localizedDescription
        }
    }
}
