import SwiftUI

/// The one big action on a screen. Large hit area, Liquid Glass.
public struct PrimaryActionButton: View {
    private let label: Text
    private let systemImage: String?
    private let action: () -> Void

    public init(_ label: Text, systemImage: String? = nil, action: @escaping () -> Void) {
        self.label = label
        self.systemImage = systemImage
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: Spacing.s) {
                if let systemImage {
                    Image(systemName: systemImage)
                }
                label
            }
            .font(.cfHeadline)
            .frame(maxWidth: .infinity)
            .padding(.vertical, Spacing.s)
        }
        .buttonStyle(.glassProminent)
        .tint(Palette.accent)
        .controlSize(.large)
    }
}

/// Camera-style shutter. Visual only until capture is implemented.
public struct RecordButton: View {
    private let isRecording: Bool
    private let action: () -> Void

    public init(isRecording: Bool, action: @escaping () -> Void) {
        self.isRecording = isRecording
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .strokeBorder(.white, lineWidth: 4)
                    .frame(width: 78, height: 78)
                RoundedRectangle(cornerRadius: isRecording ? 8 : 31)
                    .fill(Palette.recording)
                    .frame(width: isRecording ? 30 : 62, height: isRecording ? 30 : 62)
            }
        }
        .buttonStyle(.plain)
        .animation(Motion.snappy, value: isRecording)
        .accessibilityLabel(isRecording ? Text("recordButton.stop", bundle: .module) : Text("recordButton.start", bundle: .module))
    }
}
