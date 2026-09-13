import DesignSystem
import SwiftUI

/// "Create with AI": say what the workflow should do, and it opens in the studio written.
///
/// A sheet of its own, one tap from the workflows list. Writing a workflow from a sentence used to
/// be reachable only from inside a new, half-built workflow or through the assistant in the corner,
/// and the most useful way to make one was the hardest to find.
struct WorkflowAISheet: View {
    let onSubmit: (String) async -> String?
    let onClose: () -> Void

    @State private var description = ""
    @State private var isWorking = false
    @State private var failure: String?
    @FocusState private var focused: Bool

    private var ideas: [String] {
        [
            String(localized: "workflows.ai.idea.clean", bundle: .module),
            String(localized: "workflows.ai.idea.reel", bundle: .module),
            String(localized: "workflows.ai.idea.podcast", bundle: .module),
            String(localized: "workflows.ai.idea.tutorial", bundle: .module),
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("workflows.ai.title", bundle: .module)
                        .dsFont(.archivo, .bold, 24)
                        .foregroundStyle(DS.Palette.ink)
                    Text("workflows.ai.note", bundle: .module)
                        .dsFont(.sans, .regular, 13, lineHeight: 1.4)
                        .foregroundStyle(DS.Palette.ink(0.5))
                }
                Spacer(minLength: 0)
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(DS.Palette.ink)
                        .frame(width: 30, height: 30)
                        .background(Circle().fill(DS.Palette.hairline(0.1)))
                }
                .buttonStyle(.dsPressIcon)
            }

            ZStack(alignment: .topLeading) {
                TextField(String(localized: "workflows.ai.placeholder", bundle: .module), text: $description, axis: .vertical)
                    .lineLimit(3...6)
                    .dsFont(.sans, .regular, 15, lineHeight: 1.4)
                    .foregroundStyle(DS.Palette.ink)
                    .tint(DS.Palette.accent)
                    .focused($focused)
                    .disabled(isWorking)
                    .padding(14)
                    .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(DS.Palette.hairline(0.06)))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(focused ? DS.Palette.accent(0.6) : DS.Palette.hairline(0.1), lineWidth: 1)
                    )

                if isWorking {
                    WritingSweep()
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
            }

            if !isWorking {
                FlowLayout(horizontalSpacing: 6, verticalSpacing: 6) {
                    ForEach(ideas, id: \.self) { idea in
                        Button {
                            description = idea
                        } label: {
                            Text(idea)
                                .dsFont(.sans, .medium, 12)
                                .foregroundStyle(DS.Palette.lime)
                                .padding(.horizontal, 11)
                                .padding(.vertical, 7)
                                .background(Capsule().fill(DS.Palette.lime(0.1)))
                                .overlay(Capsule().stroke(DS.Palette.lime(0.25), lineWidth: 1))
                        }
                        .buttonStyle(.dsPress(radius: 20))
                    }
                }
                .transition(.opacity)
            }

            if let failure {
                Text(failure)
                    .dsFont(.sans, .regular, 12)
                    .foregroundStyle(DS.Palette.accent)
                    .transition(.opacity)
            }

            Button {
                Task { await submit() }
            } label: {
                HStack(spacing: 8) {
                    if isWorking {
                        ProgressView().tint(DS.Palette.inkInverse)
                        Text("workflows.ai.working", bundle: .module)
                    } else {
                        Image(systemName: "sparkles")
                        Text("workflows.ai.create", bundle: .module)
                    }
                }
                .dsFont(.sans, .semibold, 16)
                .foregroundStyle(DS.Palette.inkInverse)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(
                    RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                        .fill(DS.gradient(120, [DS.Palette.accent, DS.Palette.accentWarm]))
                )
            }
            .buttonStyle(.dsPress(radius: DS.Radius.card))
            .disabled(isWorking || description.trimmingCharacters(in: .whitespaces).isEmpty)
            .opacity(description.trimmingCharacters(in: .whitespaces).isEmpty ? 0.5 : 1)

            Spacer(minLength: 0)
        }
        .padding(22)
        .background(DS.Palette.screen)
        .animation(DS.Motion.settle, value: isWorking)
        .animation(DS.Motion.settle, value: failure)
        .onAppear { focused = true }
    }

    private func submit() async {
        focused = false
        failure = nil
        isWorking = true
        let message = await onSubmit(description)
        isWorking = false
        if let message {
            failure = message
        } else {
            onClose()
        }
    }
}

/// Light passing over the field while the workflow is written.
private struct WritingSweep: View {
    @State private var sweep = false

    var body: some View {
        GeometryReader { proxy in
            LinearGradient(colors: [.clear, DS.Palette.accent.opacity(0.22), .clear], startPoint: .leading, endPoint: .trailing)
                .frame(width: proxy.size.width * 0.5)
                .offset(x: sweep ? proxy.size.width : -proxy.size.width * 0.5)
                .animation(.easeInOut(duration: 1.2).repeatForever(autoreverses: false), value: sweep)
        }
        .allowsHitTesting(false)
        .onAppear { sweep = true }
    }
}
