import AVFoundation
import CaptureEngine
import DesignSystem
import SwiftUI

/// What sits behind the studio: the camera, or a stand-in for it, under the design's scrim.
///
/// The scrim is what the controls and the prompter are legible against, so it belongs to the
/// screen rather than to the placeholder. Passing a session swaps only the fill underneath;
/// everything above stays exactly as it was drawn.
public struct CameraBackdrop: View {
    private let session: AVCaptureSession?

    /// - Parameter session: the live preview, or `nil` for the flat plate — still the right answer
    ///   before permission is granted, and on the screens that review footage rather than shoot it.
    public init(session: AVCaptureSession? = nil) {
        self.session = session
    }

    public var body: some View {
        Group {
            if let session {
                CameraPreview(session: session)
            } else {
                DS.Palette.camera
            }
        }
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
