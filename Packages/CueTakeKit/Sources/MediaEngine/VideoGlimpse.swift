import AVFoundation
import Domain
import Foundation
import UIKit

/// Pictures of the finished video for the AI editor to look at.
///
/// The composition gives the picture as the edit makes it: cuts, speed, looks, camera moves,
/// backgrounds. Text, pictures and captions are laid over it here, the way the preview draws them,
/// so the AI sees whether its title sits on a face or on the captions. The captions are drawn
/// plainly, in their colour, size and place, without their animation.
///
/// Small on purpose: every picture is sent over the network and read by a model; 512 points on the
/// long side is enough to read a title and see a face.
/// On the main actor: it is called from the editor, and the pictures are small.
@MainActor
public enum VideoGlimpse {
    public struct Frame: Sendable {
        /// Seconds of the finished video.
        public let seconds: Double
        public let jpeg: Data
    }

    /// The finished video at each moment in `times`, as JPEG.
    public static func frames(
        asset: AVAsset,
        videoComposition: AVVideoComposition?,
        project: Project,
        mediaDirectory: URL,
        at times: [Double],
        longSide: CGFloat = 512
    ) async -> [Frame] {
        let generator = makeGenerator(asset, videoComposition, longSide: longSide)
        var frames: [Frame] = []
        for seconds in times {
            guard let image = await picture(from: generator, at: seconds) else { continue }
            let composed = compose(image, at: seconds, project: project, mediaDirectory: mediaDirectory)
            if let jpeg = composed.jpegData(compressionQuality: 0.62) {
                frames.append(Frame(seconds: seconds, jpeg: jpeg))
            }
        }
        return frames
    }

    /// `count` moments spread through the video, tiled into one picture with their times written
    /// on them: the whole video in one look.
    public static func sheet(
        asset: AVAsset,
        videoComposition: AVVideoComposition?,
        project: Project,
        mediaDirectory: URL,
        duration: Double,
        count: Int = 12,
        columns: Int = 4
    ) async -> (jpeg: Data, times: [Double])? {
        guard duration > 0.2, count > 0 else { return nil }
        let generator = makeGenerator(asset, videoComposition, longSide: 300)
        // The middle of each slice: the first frame of a video is so often a blink.
        let times = (0..<count).map { ((Double($0) + 0.5) / Double(count) * duration * 100).rounded() / 100 }
        var cells: [(seconds: Double, image: UIImage)] = []
        for seconds in times {
            guard let image = await picture(from: generator, at: seconds) else { continue }
            cells.append((seconds, compose(image, at: seconds, project: project, mediaDirectory: mediaDirectory)))
        }
        guard let first = cells.first?.image else { return nil }

        let cell = first.size
        let across = min(columns, cells.count)
        let down = (cells.count + across - 1) / across
        let gap: CGFloat = 4
        let size = CGSize(
            width: CGFloat(across) * cell.width + CGFloat(across - 1) * gap,
            height: CGFloat(down) * cell.height + CGFloat(down - 1) * gap
        )
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let sheet = UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.black.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            for (index, item) in cells.enumerated() {
                let origin = CGPoint(
                    x: CGFloat(index % across) * (cell.width + gap),
                    y: CGFloat(index / across) * (cell.height + gap)
                )
                item.image.draw(in: CGRect(origin: origin, size: cell))
                label(Self.clock(item.seconds), at: CGPoint(x: origin.x + 5, y: origin.y + 5))
            }
        }
        guard let jpeg = sheet.jpegData(compressionQuality: 0.6) else { return nil }
        return (jpeg, cells.map(\.seconds))
    }

    /// `1:05.3`, the way the sheet labels its pictures.
    public nonisolated static func clock(_ seconds: Double) -> String {
        let tenths = Int((max(0, seconds) * 10).rounded())
        return String(format: "%d:%02d.%d", tenths / 600, (tenths / 10) % 60, tenths % 10)
    }

    /// One frame. The callback form keeps the generator on this actor: handing it to the async
    /// form from here is a data race as far as Swift 6 is concerned.
    private static func picture(from generator: AVAssetImageGenerator, at seconds: Double) async -> CGImage? {
        await withCheckedContinuation { continuation in
            generator.generateCGImageAsynchronously(for: CMTime(seconds: seconds, preferredTimescale: 600)) { image, _, _ in
                continuation.resume(returning: image)
            }
        }
    }

    private static func makeGenerator(_ asset: AVAsset, _ videoComposition: AVVideoComposition?, longSide: CGFloat) -> AVAssetImageGenerator {
        let generator = AVAssetImageGenerator(asset: asset)
        generator.videoComposition = videoComposition
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: longSide, height: longSide)
        // Close is enough to judge a title; exact frames cost a decode from the last keyframe.
        let tolerance = CMTime(seconds: 0.1, preferredTimescale: 600)
        generator.requestedTimeToleranceBefore = tolerance
        generator.requestedTimeToleranceAfter = tolerance
        return generator
    }

    /// The frame with what shows over it at that moment: text and pictures, then the caption.
    private static func compose(_ image: CGImage, at seconds: Double, project: Project, mediaDirectory: URL) -> UIImage {
        let size = CGSize(width: image.width, height: image.height)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            let frame = CGRect(origin: .zero, size: size)
            UIImage(cgImage: image).draw(in: frame)
            // Those behind a person are already in the frame: the compositor draws them.
            for overlay in project.overlays where !overlay.isBehindPerson {
                let start = overlay.start.seconds
                guard start <= seconds, seconds < start + overlay.duration.seconds,
                      let drawn = LiveBehind.draw(overlay, size: size, mediaDirectory: mediaDirectory)
                else { continue }
                UIImage(cgImage: drawn).draw(in: frame)
            }
            if let cue = project.caption(at: seconds) {
                caption(cue, style: project.captionStyle, locale: Locale(identifier: cue.localeIdentifier ?? project.localeIdentifier), in: size)
            }
        }
    }

    private static func caption(_ cue: PlacedCue, style: CaptionStyle, locale: Locale, in size: CGSize) {
        let text = style.textCase.apply(to: cue.text, locale: locale)
        guard !text.isEmpty else { return }
        let fontSize = max(8, size.height * CGFloat(style.relativeFontSize) * CGFloat(cue.scale ?? 1))
        let font = CaptionRenderer.makeFont(style, size: fontSize) as UIFont
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: UIColor(cgColor: CaptionRenderer.cgColor(style.textColor)),
            .strokeColor: UIColor.black,
            .strokeWidth: -3,
            .paragraphStyle: paragraph,
        ]
        let string = NSAttributedString(string: text, attributes: attributes)
        let width = size.width * 0.86
        let bounds = string.boundingRect(with: CGSize(width: width, height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin], context: nil)
        let position = cue.position ?? style.position
        let centre = CGPoint(x: size.width * CGFloat(position.x), y: size.height * CGFloat(position.y))
        let box = CGRect(
            x: centre.x - width / 2,
            y: centre.y - bounds.height / 2,
            width: width,
            height: ceil(bounds.height)
        )
        if let background = style.backgroundColor {
            let plate = CGRect(
                x: centre.x - bounds.width / 2 - fontSize * 0.4,
                y: box.minY - fontSize * 0.2,
                width: bounds.width + fontSize * 0.8,
                height: box.height + fontSize * 0.4
            )
            UIColor(cgColor: CaptionRenderer.cgColor(background)).setFill()
            UIBezierPath(roundedRect: plate, cornerRadius: fontSize * 0.3).fill()
        }
        string.draw(with: box, options: [.usesLineFragmentOrigin], context: nil)
    }

    private static func label(_ text: String, at point: CGPoint) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.monospacedDigitSystemFont(ofSize: 15, weight: .bold),
            .foregroundColor: UIColor.white,
        ]
        let string = NSAttributedString(string: text, attributes: attributes)
        let size = string.size()
        UIColor.black.withAlphaComponent(0.7).setFill()
        UIBezierPath(roundedRect: CGRect(x: point.x, y: point.y, width: size.width + 8, height: size.height + 4), cornerRadius: 4).fill()
        string.draw(at: CGPoint(x: point.x + 4, y: point.y + 2))
    }
}
