import DesignSystem
import Domain
import SwiftUI

/// The selected camera move's own controls, under the timeline it is shown on.
struct CameraMotionPanel: View {
    @Bindable var model: EditorModel
    let recipe: CameraMotionRecipe
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            CameraPanelHeader(
                title: Text(Self.title(recipe.kind), bundle: .module),
                symbol: Self.symbol(recipe.kind),
                tint: DS.Palette.lime,
                range: model.timelineRange(ofCameraMotion: recipe.id),
                onClose: onClose
            )

            Text("editor.cameraPanel.hint", bundle: .module)
                .dsFont(.sans, .regular, 11, lineHeight: 1.35)
                .foregroundStyle(DS.Palette.ink(0.55))

            HStack(spacing: 7) {
                ForEach([CameraMotionRecipe.Kind.pushIn, .punch, .pullOut, .hold], id: \.self) { kind in
                    let active = recipe.kind == kind
                    Button {
                        withAnimation(DS.Motion.snap) {
                            model.updateCameraMotion(recipe.id) { $0.kind = kind }
                        }
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: Self.symbol(kind))
                                .font(.system(size: 13, weight: .semibold))
                            Text(Self.title(kind), bundle: .module)
                                .dsFont(.sans, .semibold, 10)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                        .foregroundStyle(active ? DS.Palette.inkInverse : DS.Palette.ink(0.74))
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(active ? DS.Palette.lime : DS.Palette.hairline(0.07))
                        )
                    }
                    .buttonStyle(.dsPress(radius: 14))
                    .accessibilityAddTraits(active ? .isSelected : [])
                }
            }

            if recipe.kind != .hold {
                HStack(spacing: 6) {
                    Text("editor.zoom.feel", bundle: .module)
                        .dsFont(.sans, .medium, 10)
                        .foregroundStyle(DS.Palette.ink(0.56))
                    Spacer(minLength: 4)
                    ForEach(CameraMotionRecipe.Feel.allCases, id: \.self) { feel in
                        let active = recipe.feel == feel
                        Button {
                            withAnimation(DS.Motion.snap) {
                                model.updateCameraMotion(recipe.id) { $0.feel = feel }
                            }
                        } label: {
                            Text(Self.feelTitle(feel), bundle: .module)
                                .dsFont(.sans, .semibold, 10)
                                .foregroundStyle(active ? DS.Palette.inkInverse : DS.Palette.ink(0.62))
                                .padding(.horizontal, 10)
                                .frame(height: 32)
                                .background(Capsule().fill(active ? DS.Palette.lime : DS.Palette.hairline(0.06)))
                        }
                        .buttonStyle(.dsPress(radius: 16))
                    }
                }
            }

            HStack(spacing: 9) {
                Image(systemName: "plus.magnifyingglass")
                    .foregroundStyle(DS.Palette.ink(0.56))
                Slider(
                    value: Binding(
                        get: { recipe.amount },
                        set: { value in model.updateCameraMotion(recipe.id, coalescing: "amount") { $0.amount = value } }
                    ),
                    in: 0.02...0.8
                )
                .tint(DS.Palette.lime)
                Text(verbatim: "+%\(Int((recipe.amount * 100).rounded()))")
                    .dsFont(.mono, .medium, 10)
                    .foregroundStyle(DS.Palette.ink(0.72))
                    .frame(width: 40, alignment: .trailing)
            }

            CameraPanelDelete(title: Text("editor.cameraPanel.delete", bundle: .module)) {
                let id = recipe.id
                withAnimation(DS.Motion.settle) { model.removeCameraMotion(id) }
            }
        }
        .cameraPanelSurface()
    }

    static func symbol(_ kind: CameraMotionRecipe.Kind) -> String {
        switch kind {
        case .hold: "viewfinder.circle"
        case .pushIn: "arrow.down.right"
        case .pullOut: "arrow.up.left"
        case .punch: "bolt.fill"
        }
    }

    static func title(_ kind: CameraMotionRecipe.Kind) -> LocalizedStringKey {
        switch kind {
        case .hold: "editor.zoom.static"
        case .pushIn: "editor.zoom.push"
        case .pullOut: "editor.zoom.pull"
        case .punch: "editor.zoom.punch"
        }
    }

    static func feelTitle(_ feel: CameraMotionRecipe.Feel) -> LocalizedStringKey {
        switch feel {
        case .calm: "editor.zoom.feel.calm"
        case .natural: "editor.zoom.feel.natural"
        case .energetic: "editor.zoom.feel.energetic"
        }
    }
}

/// The selected clip's subject track: how it went, where to fix it, and a way to remove it.
struct SubjectTrackPanel: View {
    @Bindable var model: EditorModel
    let span: SubjectTrackSpan
    let onEdit: () -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            CameraPanelHeader(
                title: Text("editor.trackLane.title", bundle: .module),
                symbol: "scope",
                tint: SubjectTrackLane.tint,
                range: span.start...span.end,
                onClose: onClose
            )

            HStack(spacing: 8) {
                Image(systemName: span.issueTimes.isEmpty ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(span.issueTimes.isEmpty ? DS.Palette.lime : DS.Palette.accentWarm)
                Text(
                    span.issueTimes.isEmpty
                        ? String(localized: "editor.trackPanel.stable", bundle: .module)
                        : String(localized: "editor.trackPanel.issues \(span.issueTimes.count)", bundle: .module)
                )
                .dsFont(.sans, .semibold, 12)
                .foregroundStyle(DS.Palette.ink(0.8))
                Spacer(minLength: 0)
            }

            // Each lost moment, as a way to go there.
            if !span.issueTimes.isEmpty {
                ScrollView(.horizontal) {
                    HStack(spacing: 7) {
                        ForEach(span.issueTimes, id: \.self) { time in
                            Button {
                                model.pause()
                                model.seek(to: time)
                            } label: {
                                Text(verbatim: MediaTime(seconds: time).preciseTimecode)
                                    .dsFont(.mono, .medium, 10)
                                    .foregroundStyle(DS.Palette.accentWarm)
                                    .padding(.horizontal, 10)
                                    .frame(height: 32)
                                    .background(Capsule().fill(DS.Palette.accentWarm.opacity(0.12)))
                            }
                            .buttonStyle(.dsPress(radius: 16))
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }

            Text("editor.trackPanel.hint", bundle: .module)
                .dsFont(.sans, .regular, 11, lineHeight: 1.35)
                .foregroundStyle(DS.Palette.ink(0.55))

            Button {
                model.pause()
                // The drawing opens on the frame under the playhead: the first lost moment if
                // there is one, otherwise somewhere inside this track.
                if let time = span.issueTimes.first {
                    model.seek(to: time)
                } else if !(span.start...span.end).contains(model.playhead) {
                    model.seek(to: span.start + 0.01)
                }
                onEdit()
            } label: {
                Label {
                    Text("editor.trackPanel.edit", bundle: .module)
                } icon: {
                    Image(systemName: "hand.draw")
                }
                .dsFont(.sans, .semibold, 13)
                .foregroundStyle(DS.Palette.inkInverse)
                .frame(maxWidth: .infinity)
                .frame(height: 46)
                .background(Capsule().fill(DS.Palette.accent))
            }
            .buttonStyle(.dsPress(radius: 23))

            CameraPanelDelete(title: Text("editor.trackPanel.delete", bundle: .module)) {
                let id = span.segmentID
                withAnimation(DS.Motion.settle) { model.removeSubjectTrack(forSegment: id) }
            }
        }
        .cameraPanelSurface()
    }
}

struct CameraPanelHeader: View {
    let title: Text
    let symbol: String
    let tint: Color
    let range: ClosedRange<Double>?
    let onClose: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(DS.Palette.inkInverse)
                .frame(width: 28, height: 28)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(tint))
            VStack(alignment: .leading, spacing: 1) {
                title
                    .dsFont(.sans, .semibold, 14)
                    .foregroundStyle(DS.Palette.ink)
                if let range {
                    Text(verbatim: "\(MediaTime(seconds: range.lowerBound).preciseTimecode) – \(MediaTime(seconds: range.upperBound).preciseTimecode)")
                        .dsFont(.mono, .medium, 10)
                        .foregroundStyle(DS.Palette.ink(0.56))
                        .contentTransition(.numericText())
                }
            }
            Spacer(minLength: 0)
            Button(action: onClose) {
                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(DS.Palette.inkInverse)
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(DS.Palette.lime))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.dsPressIcon)
            .accessibilityLabel(Text("editor.done", bundle: .module))
        }
    }
}

struct CameraPanelDelete: View {
    let title: Text
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label {
                title
            } icon: {
                Image(systemName: "trash")
                    .dsActionName("trash")
            }
            .dsFont(.sans, .semibold, 12)
            .foregroundStyle(DS.Palette.accentWarm)
            .frame(maxWidth: .infinity)
            .frame(height: 42)
            .background(Capsule().fill(DS.Palette.accentWarm.opacity(0.1)))
        }
        .buttonStyle(.dsPress(radius: 21))
    }
}

extension View {
    func cameraPanelSurface() -> some View {
        ScrollView {
            padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollBounceBehavior(.basedOnSize)
        .scrollIndicators(.hidden)
        .frame(maxHeight: 380)
        .dsGlass(
            tint: DS.Palette.glassSheet(0.95),
            in: UnevenRoundedRectangle(topLeadingRadius: DS.Radius.sheet, topTrailingRadius: DS.Radius.sheet, style: .continuous),
            border: DS.Palette.hairline(0.12)
        )
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}
