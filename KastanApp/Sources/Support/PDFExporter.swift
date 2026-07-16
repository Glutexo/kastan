import AppKit
import Foundation
import UniformTypeIdentifiers

/// Presents downloaded IDOS PDF data as a native user-selected file export.
@MainActor
protocol PDFExporting {
    func save(pdfData: Data, suggestedFileName: String) async throws
}

/// Uses the standard macOS save panel and writes only to the location explicitly chosen by the user.
@MainActor
struct WorkspacePDFExporter: PDFExporting {
    func save(pdfData: Data, suggestedFileName: String) async throws {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.nameFieldStringValue = suggestedFileName
        panel.title = AppLocalization.string("Save as PDF")

        guard panel.runModal() == .OK, let destination = panel.url else {
            return
        }

        let isSecurityScoped = destination.startAccessingSecurityScopedResource()
        defer {
            if isSecurityScoped {
                destination.stopAccessingSecurityScopedResource()
            }
        }
        try pdfData.write(to: destination, options: .atomic)
    }
}

/// Produces a readable route-based name while removing path separators that cannot belong to one file name.
enum PDFExportFileName {
    static func connection(from: String, to: String) -> String {
        var invalidCharacters = CharacterSet(charactersIn: "/:")
        invalidCharacters.formUnion(.newlines)
        let title = AppLocalization.string(
            "Connection %@ – %@",
            from.trimmingCharacters(in: .whitespacesAndNewlines),
            to.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        var trailingCharacters = CharacterSet.whitespacesAndNewlines
        trailingCharacters.insert(charactersIn: ".")
        let safeTitle = title
            .components(separatedBy: invalidCharacters)
            .joined(separator: "-")
            .trimmingCharacters(in: trailingCharacters)
        return "\(safeTitle).pdf"
    }
}
