import CoreTransferable
import Foundation
import UniformTypeIdentifiers

/// The backup as a shareable `.json` file.
nonisolated struct BackupFile: Transferable {
    let data: Data

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .json) { $0.data }
            .suggestedFileName("Ammutta.json")
    }
}

/// Reads a file the person picked, which lives outside the app's sandbox.
enum PickedFile {
    static func data(at url: URL) -> Data? {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        return try? Data(contentsOf: url)
    }
}
