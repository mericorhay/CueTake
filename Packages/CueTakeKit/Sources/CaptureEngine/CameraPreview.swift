import AVFoundation
import SwiftUI
import UIKit

/// The live preview.
///
/// A `UIView` whose backing layer *is* the preview layer, rather than a view with one added as a
/// sublayer: the layer then resizes with the view for free, with no frame bookkeeping on rotation.
public struct CameraPreview: UIViewRepresentable {
    private let session: AVCaptureSession

    public init(session: AVCaptureSession) {
        self.session = session
    }

    public func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.backgroundColor = .black
        view.previewLayer.session = session
        // The studio frames a person, so filling and cropping is right; fitting would letterbox
        // the subject inside a screen the design treats as the viewfinder.
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    public func updateUIView(_ view: PreviewView, context: Context) {
        if view.previewLayer.session !== session {
            view.previewLayer.session = session
        }
    }

    public final class PreviewView: UIView {
        public override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }

        var previewLayer: AVCaptureVideoPreviewLayer {
            // Safe by construction: `layerClass` above decides what this is.
            layer as! AVCaptureVideoPreviewLayer
        }
    }
}
