import CoreTransferable
import Foundation
import UniformTypeIdentifiers

/// A video coming out of the photo picker.
///
/// `PhotosPickerItem` will not hand over a `URL` for a video: the asset may not be on the device
/// at all, and the file it eventually produces is scoped to the transfer. So the movie is received
/// as a file and copied somewhere we control before that scope ends — `MediaImporter` then copies
/// it again into the project, which is the copy that actually matters.
struct ImportedMovie: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { movie in
            SentTransferredFile(movie.url)
        } importing: { received in
            // Received files are deleted when the transfer completes, so this cannot be lazy.
            let destination = FileManager.default.temporaryDirectory
                .appending(path: "import-\(UUID().uuidString).\(received.file.pathExtension)")
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.copyItem(at: received.file, to: destination)
            return ImportedMovie(url: destination)
        }
    }
}
