import AIServices
import Analytics
import AVFoundation
import DesignSystem
import Domain
import EditorFeature
import Foundation
import Photos
import UIKit

/// After the export: the words to post it with, and a cover image.
extension AppModel {
    /// Asks for the post kit of the video just exported. Counted as writing, like a script.
    func makePostKit() {
        let transcript = project.spokenTranscript
        guard !transcript.isEmpty else {
            exportModel.postKitState = .failed(AppLocalization.string("postKit.noSpeech"))
            return
        }
        guard access.use(.scriptWriting) else {
            exportModel.postKitState = .failed(AccessModel.message(for: access.decision(.scriptWriting)))
            return
        }
        let platforms = Self.postPlatforms(for: exportModel.finishedPlatforms.isEmpty ? exportModel.platforms : exportModel.finishedPlatforms)
        let client = dependencies.assistantClient
        exportModel.postKitState = .loading
        Task {
            do {
                let kit = try await client.postKit(transcript: transcript, platforms: platforms)
                exportModel.postKitState = .ready(kit)
                Analytics.track("post_kit", ["ok": true, "hook_score": .int(kit.hook.score), "platforms": .int(kit.posts.count)])
            } catch {
                access.refund(.scriptWriting)
                exportModel.postKitState = .failed(Self.assistantFailureMessage(error))
                Analytics.track("post_kit", ["ok": false])
            }
        }
    }

    /// The export's platforms as the post kit names them; the three short-video apps when none
    /// was picked.
    static func postPlatforms(for picked: [SocialPlatform]) -> [String] {
        var names: [String] = []
        for platform in picked {
            let name: String = switch platform {
            case .tiktok: "tiktok"
            case .instagramReels, .instagramStory, .instagramPost, .square: "instagram"
            case .youtubeShorts, .youtube: "youtube"
            }
            if !names.contains(name) { names.append(name) }
        }
        return names.isEmpty ? ["tiktok", "instagram", "youtube"] : names
    }

    /// A cover: a frame of the finished video with the cover line across it, saved to Photos so it
    /// can be picked as the cover in TikTok or Instagram.
    func saveCover(_ line: String) {
        guard let video = exportModel.outputURL else { return }
        Task {
            let saved = await Self.writeCover(line, from: video)
            exportModel.coverSaved = saved
            Analytics.track("cover_saved", ["ok": .flag(saved)])
        }
    }

    nonisolated private static func writeCover(_ line: String, from video: URL) async -> Bool {
        let asset = AVURLAsset(url: video)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 1080, height: 1920)
        let seconds = min(1.5, max(0, ((try? await asset.load(.duration).seconds) ?? 0) * 0.2))
        guard let (frame, _) = try? await generator.image(at: CMTime(seconds: seconds, preferredTimescale: 600)) else { return false }
        let image = drawCover(line, on: UIImage(cgImage: frame))
        guard let data = image.jpegData(compressionQuality: 0.92) else { return false }

        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else { return false }
        do {
            try await PHPhotoLibrary.shared().performChanges { @Sendable in
                PHAssetCreationRequest.forAsset().addResource(with: .photo, data: data, options: nil)
            }
            return true
        } catch {
            return false
        }
    }

    /// The line big and bold in the upper third, white on a dark band, the way covers are made to
    /// read as a small tile in a grid.
    nonisolated private static func drawCover(_ line: String, on frame: UIImage) -> UIImage {
        let size = frame.size
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            frame.draw(in: CGRect(origin: .zero, size: size))
            // A soft darkening towards the top, so the words read over any picture.
            let colors = [UIColor.black.withAlphaComponent(0.55).cgColor, UIColor.black.withAlphaComponent(0).cgColor] as CFArray
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) {
                context.cgContext.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: size.height * 0.6), options: [])
            }
            let text = line.uppercased(with: AppLocalization.locale)
            let width = size.width * 0.84
            var fontSize = size.width * 0.13
            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = .center
            paragraph.lineHeightMultiple = 0.92
            func attributes(_ size: CGFloat) -> [NSAttributedString.Key: Any] {
                [
                    .font: UIFont(name: "Archivo-ExtraBold", size: size) ?? .systemFont(ofSize: size, weight: .black),
                    .foregroundColor: UIColor.white,
                    .paragraphStyle: paragraph,
                    .strokeColor: UIColor.black,
                    .strokeWidth: -3.0,
                ]
            }
            var bounds = (text as NSString).boundingRect(with: CGSize(width: width, height: .greatestFiniteMagnitude),
                                                        options: .usesLineFragmentOrigin, attributes: attributes(fontSize), context: nil)
            while bounds.height > size.height * 0.3, fontSize > 24 {
                fontSize *= 0.9
                bounds = (text as NSString).boundingRect(with: CGSize(width: width, height: .greatestFiniteMagnitude),
                                                        options: .usesLineFragmentOrigin, attributes: attributes(fontSize), context: nil)
            }
            let origin = CGPoint(x: (size.width - width) / 2, y: size.height * 0.2)
            (text as NSString).draw(in: CGRect(origin: origin, size: CGSize(width: width, height: bounds.height + 4)),
                                    withAttributes: attributes(fontSize))
        }
    }
}
