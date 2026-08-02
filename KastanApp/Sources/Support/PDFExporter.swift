import AppKit
import Foundation
import SwiftUI
import UniformTypeIdentifiers

/// Describes whether a PDF export should open in Preview or remain as a downloaded file.
enum PDFExportAction: Equatable {
    case openInPreview
    case download

    static func preferred(for modifierFlags: NSEvent.ModifierFlags) -> Self {
        modifierFlags.contains(.option) ? .download : .openInPreview
    }

    var title: LocalizedStringKey {
        switch self {
        case .openInPreview:
            "Open PDF in Preview"
        case .download:
            "Download PDF File"
        }
    }

    var systemImage: String {
        switch self {
        case .openInPreview:
            "doc.text.magnifyingglass"
        case .download:
            "arrow.down.doc"
        }
    }
}

/// Presents Open PDF in Preview as the primary action and Download PDF File while Option is held.
struct PDFExportButton<Label: View>: View {
    let placement: OptionAlternateButtonPlacement
    let perform: (PDFExportAction) -> Void
    let label: (PDFExportAction) -> Label

    init(
        placement: OptionAlternateButtonPlacement,
        perform: @escaping (PDFExportAction) -> Void,
        @ViewBuilder label: @escaping (PDFExportAction) -> Label
    ) {
        self.placement = placement
        self.perform = perform
        self.label = label
    }

    var body: some View {
        OptionAlternateButton(
            placement: placement,
            primaryAction: PDFExportAction.openInPreview,
            alternateAction: PDFExportAction.download,
            title: { $0.title },
            perform: perform,
            label: label
        )
    }
}

/// Opens generated IDOS PDF data in Apple's Preview application.
@MainActor
protocol PDFOpening {
    func open(pdfData: Data, suggestedFileName: String) async throws
}

/// Preserves each PDF in an isolated temporary directory before handing it directly to Preview.
@MainActor
struct WorkspacePDFOpener: PDFOpening {
    private static let previewBundleIdentifier = "com.apple.Preview"

    func open(pdfData: Data, suggestedFileName: String) async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("Kastan", isDirectory: true)
            .appendingPathComponent("PDFExports", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent(suggestedFileName)
        try pdfData.write(to: file, options: .atomic)

        guard let preview = NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: Self.previewBundleIdentifier
        ) else {
            throw PDFOpenError.previewUnavailable
        }

        _ = try await NSWorkspace.shared.open(
            [file],
            withApplicationAt: preview,
            configuration: NSWorkspace.OpenConfiguration()
        )
    }
}

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
        panel.title = AppLocalization.string("Download PDF File")

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

enum PDFOpenError: LocalizedError {
    case previewUnavailable

    var errorDescription: String? {
        AppLocalization.string("Preview is not available.")
    }
}

/// Produces readable route-based export names while removing characters that cannot belong to one file name.
enum ResultExportFileName {
    static func connection(from: String, to: String, pathExtension: String) -> String {
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
        return "\(safeTitle).\(pathExtension)"
    }
}

/// Supplies a native PDF extension for the shared route-based export name.
enum PDFExportFileName {
    static func connection(from: String, to: String) -> String {
        ResultExportFileName.connection(
            from: from,
            to: to,
            pathExtension: "pdf"
        )
    }
}
