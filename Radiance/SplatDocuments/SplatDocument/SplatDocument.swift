import RadianceSupport
import SwiftUI
import UniformTypeIdentifiers

// MARK: - SplatDocument

/// A document type for Gaussian Splat files.
/// Supports .sog, .ply, .splat, and .spv file formats.
/// This document only stores metadata - the actual splat data is loaded by the view.
struct SplatDocument: FileDocument {
    /// The file type of the document
    var contentType: UTType?

    static var readableContentTypes: [UTType] {
        [.sog, .ply, .antimatter15Splat, .spz, .image]
    }

    static var writableContentTypes: [UTType] {
        [] // Read-only document
    }

    init() {
        contentType = nil
    }

    init(configuration: ReadConfiguration) {
        // Don't load the data here - let the view handle loading from the file URL
        contentType = configuration.contentType
    }

    func fileWrapper(configuration _: WriteConfiguration) throws -> FileWrapper {
        throw CocoaError(.fileWriteNoPermission) // Read-only document
    }
}
