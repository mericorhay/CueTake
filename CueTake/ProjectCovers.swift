import Domain
import MediaEngine
import Persistence
import UIKit

/// Covers for the library: a frame from each of a project's clips, side by side in one picture.
///
/// The cards used to be tinted gradients, one colour in three, so every project in the grid looked
/// like every other and the only way to find one was to read dates. A frame of the footage is the
/// thing people recognise. The frames are drawn as they are — no tint, no filter — because the
/// point is to see the video.
extension AppModel {
    /// Loads covers that exist and draws the ones that are missing or older than their project.
    /// Runs after the library refreshes, in the background; cards fill in as covers arrive.
    func refreshCovers() async {
        let store = dependencies.projectStore
        for summary in library {
            guard let media = try? await store.mediaDirectory(for: summary.id) else { continue }
            let url = media.appending(path: "cover.jpg", directoryHint: .notDirectory)
            let path = url.path(percentEncoded: false)
            let modified = (try? FileManager.default.attributesOfItem(atPath: path))?[.modificationDate] as? Date
            let isCurrent = modified.map { $0 >= summary.updatedAt.addingTimeInterval(-2) } ?? false

            if isCurrent {
                if covers[summary.id] == nil, let image = UIImage(contentsOfFile: path) {
                    covers[summary.id] = image
                }
                continue
            }

            guard let project = try? await store.load(summary.id),
                  let image = await Self.drawCover(for: project, mediaDirectory: media)
            else { continue }
            if let data = image.jpegData(compressionQuality: 0.82) {
                try? data.write(to: url, options: .atomic)
            }
            covers[summary.id] = image
        }
    }

    /// Up to four clips: one fills the card, two split it, three put the first beside the other
    /// two, four make a grid.
    nonisolated static func drawCover(for project: Project, mediaDirectory: URL) async -> UIImage? {
        let sampler = ThumbnailSampler()
        let recordings = Dictionary(uniqueKeysWithValues: project.recordings.map { ($0.id, $0) })
        var frames: [CGImage] = []

        for segment in project.segments {
            guard frames.count < 4,
                  let take = segment.selectedTake,
                  let recording = recordings[take.recordingID]
            else { continue }
            let url = mediaDirectory.appending(
                path: (recording.relativePath as NSString).lastPathComponent,
                directoryHint: .notDirectory
            )
            let length = take.sourceRange.duration.seconds
            // A third of the way in: past the reach for the shutter, into the shot itself.
            let at = take.sourceRange.start.seconds + length * 0.33
            if let frame = await sampler.frames(of: url, from: at, duration: min(0.5, length), count: 1).first {
                frames.append(frame)
            }
        }
        guard !frames.isEmpty else { return nil }

        let size = CGSize(width: 600, height: 800)
        let gap: CGFloat = 3
        let w = size.width, h = size.height
        let rects: [CGRect] = switch frames.count {
        case 1:
            [CGRect(origin: .zero, size: size)]
        case 2:
            [CGRect(x: 0, y: 0, width: (w - gap) / 2, height: h),
             CGRect(x: (w + gap) / 2, y: 0, width: (w - gap) / 2, height: h)]
        case 3:
            [CGRect(x: 0, y: 0, width: (w - gap) / 2, height: h),
             CGRect(x: (w + gap) / 2, y: 0, width: (w - gap) / 2, height: (h - gap) / 2),
             CGRect(x: (w + gap) / 2, y: (h + gap) / 2, width: (w - gap) / 2, height: (h - gap) / 2)]
        default:
            [CGRect(x: 0, y: 0, width: (w - gap) / 2, height: (h - gap) / 2),
             CGRect(x: (w + gap) / 2, y: 0, width: (w - gap) / 2, height: (h - gap) / 2),
             CGRect(x: 0, y: (h + gap) / 2, width: (w - gap) / 2, height: (h - gap) / 2),
             CGRect(x: (w + gap) / 2, y: (h + gap) / 2, width: (w - gap) / 2, height: (h - gap) / 2)]
        }

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.black.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            for (frame, rect) in zip(frames, rects) {
                // Aspect fill, cropped to its cell.
                let imageSize = CGSize(width: frame.width, height: frame.height)
                let scale = max(rect.width / imageSize.width, rect.height / imageSize.height)
                let drawn = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
                let origin = CGPoint(x: rect.midX - drawn.width / 2, y: rect.midY - drawn.height / 2)
                context.cgContext.saveGState()
                context.cgContext.clip(to: rect)
                UIImage(cgImage: frame).draw(in: CGRect(origin: origin, size: drawn))
                context.cgContext.restoreGState()
            }
        }
    }
}
