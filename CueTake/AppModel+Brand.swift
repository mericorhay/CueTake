import DesignSystem
import Domain
import EditorFeature
import Foundation
import Persistence
import ScriptFeature
import UIKit

/// The brand kit and the templates: what every video this person makes looks like.
extension AppModel {
    /// Where the logo lives: with the app, not with a project, because it belongs to the person.
    var brandFolder: URL {
        URL.applicationSupportDirectory.appending(path: "Brand", directoryHint: .isDirectory)
    }

    var brandLogoURL: URL? {
        guard let file = scriptLibrary.kit.logoFile else { return nil }
        let url = brandFolder.appending(path: file, directoryHint: .notDirectory)
        return FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) ? url : nil
    }

    /// Everything the editor's brand sheet shows and can do.
    var brandTools: BrandTools {
        BrandTools(
            kit: scriptLibrary.kit,
            templates: scriptLibrary.templates,
            hasLogo: brandLogoURL != nil,
            setKit: { [weak self] kit in self?.setBrandKit(kit) },
            applyKit: { [weak self] in self?.applyBrandKit() },
            pickLogo: { [weak self] in self?.isPickingBrandLogo = true },
            applyTemplate: { [weak self] template in self?.applyTemplate(template) },
            saveTemplate: { [weak self] name in self?.saveTemplate(named: name) },
            deleteTemplate: { [weak self] id in self?.scriptLibrary.deleteTemplate(id) }
        )
    }

    /// A colour, a face or the watermark changed. The video follows at once when it already wears
    /// the brand, so the picture answers the tap rather than waiting for "apply".
    func setBrandKit(_ kit: BrandKit) {
        let wasWatermarked = editorModel.project.hasWatermark
        let watermarkChanged = scriptLibrary.kit.watermark != kit.watermark
        scriptLibrary.setKit(kit)
        guard screen == .editor else { return }
        if wasWatermarked || (watermarkChanged && kit.watermark.isOn) {
            Task { await applyWatermark(record: false) }
        }
    }

    /// Paints the open video in the brand's colours.
    func applyBrandKit() {
        guard screen == .editor else { return }
        editorModel.record("editor.change.brand", symbol: "paintpalette")
        editorModel.project.apply(scriptLibrary.kit)
        editorModel.project.updatedAt = .now
        Task {
            await applyWatermark(record: false)
            adoptEditorEdits()
            scheduleSave()
        }
    }

    /// Puts the logo in the video, or takes it out, copying the file in beside the footage so the
    /// project can be exported and moved without it going missing.
    func applyWatermark(record: Bool = true) async {
        let kit = scriptLibrary.kit
        var aspect = kit.logoAspect
        if kit.watermark.isOn, let logo = brandLogoURL {
            guard let media = try? await dependencies.projectStore.mediaDirectory(for: editorModel.project.id) else { return }
            let destination = media.appending(path: BrandKit.logoInProject, directoryHint: .notDirectory)
            try? FileManager.default.removeItem(at: destination)
            try? FileManager.default.copyItem(at: logo, to: destination)
            if let image = UIImage(contentsOfFile: destination.path(percentEncoded: false)), image.size.height > 0 {
                aspect = image.size.width / image.size.height
            }
        }
        if record { editorModel.record("editor.change.brand", symbol: "paintpalette") }
        editorModel.project.setWatermark(kit, aspect: aspect, totalSeconds: editorModel.duration)
        editorModel.project.updatedAt = .now
        adoptEditorEdits()
        scheduleSave()
    }

    /// A logo picked from the photo library, kept as the brand's.
    func adoptBrandLogo(_ data: Data) async {
        guard let image = UIImage(data: data), image.size.height > 0 else { return }
        let files = FileManager.default
        try? files.createDirectory(at: brandFolder, withIntermediateDirectories: true)
        let url = brandFolder.appending(path: "logo.png", directoryHint: .notDirectory)
        guard let png = image.pngData() else { return }
        do {
            try png.write(to: url, options: .atomic)
        } catch {
            show(notice: AppLocalization.string("brand.logo.failed"))
            return
        }
        var kit = scriptLibrary.kit
        kit.logoFile = "logo.png"
        kit.logoAspect = image.size.width / image.size.height
        kit.watermark.isOn = true
        scriptLibrary.setKit(kit)
        if screen == .editor {
            await applyWatermark()
        }
    }

    /// Makes the open video look like a template.
    func applyTemplate(_ template: VideoTemplate) {
        guard screen == .editor else { return }
        editorModel.record("editor.change.template", symbol: "square.on.square")
        editorModel.project.apply(template, brand: template.usesBrand ? scriptLibrary.kit : nil)
        Task {
            if template.usesBrand { await applyWatermark(record: false) }
            adoptEditorEdits()
            scheduleSave()
            show(notice: AppLocalization.string("brand.template.applied \(template.name)"))
        }
    }

    /// Keeps the way this video was made, for the next one.
    func saveTemplate(named name: String) {
        takeEditorEditsIfEditing()
        let template = VideoTemplate(name: name, from: project)
        scriptLibrary.save(template)
        show(notice: AppLocalization.string("brand.template.saved \(template.name)"))
    }
}
