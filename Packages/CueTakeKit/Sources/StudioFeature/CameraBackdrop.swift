import DesignSystem
import SwiftUI

/// Stands in for the camera preview until CaptureEngine is implemented.
///
/// The design puts a photo here with a scrim over it; the scrim is what the controls sit on, so it
/// is part of the screen, not the placeholder. `AVCaptureVideoPreviewLayer` replaces the fill
/// underneath and everything above it stays as it is.
public struct CameraBackdrop: View {
    public init() {}

    public var body: some View {
        DS.Palette.camera
            .overlay {
                LinearGradient(
                    stops: [
                        .init(color: Color(hex: 0x0B0B0D, alpha: 0.55), location: 0),
                        .init(color: Color(hex: 0x0B0B0D, alpha: 0.15), location: 0.35),
                        .init(color: Color(hex: 0x0B0B0D, alpha: 0.82), location: 1),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            .allowsHitTesting(false)
            .ignoresSafeArea()
    }
}
