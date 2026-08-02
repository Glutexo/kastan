import AppKit
import Foundation
import SwiftUI
import UniformTypeIdentifiers

/// Describes whether a calendar export should open in the calendar app or remain as a downloaded ICS file.
enum CalendarExportAction: Equatable {
    case addToCalendar
    case download

    static func preferred(for modifierFlags: NSEvent.ModifierFlags) -> Self {
        modifierFlags.contains(.option) ? .download : .addToCalendar
    }

    var title: LocalizedStringKey {
        switch self {
        case .addToCalendar:
            "Add to Calendar"
        case .download:
            "Download ICS File"
        }
    }

    var systemImage: String {
        switch self {
        case .addToCalendar:
            "calendar.badge.plus"
        case .download:
            "arrow.down.to.line"
        }
    }
}

/// Presents Add to Calendar as the primary action and Download ICS File while Option is held.
struct CalendarExportButton<Label: View>: View {
    let placement: OptionAlternateButtonPlacement
    let perform: (CalendarExportAction) -> Void
    let label: (CalendarExportAction) -> Label

    init(
        placement: OptionAlternateButtonPlacement,
        perform: @escaping (CalendarExportAction) -> Void,
        @ViewBuilder label: @escaping (CalendarExportAction) -> Label
    ) {
        self.placement = placement
        self.perform = perform
        self.label = label
    }

    var body: some View {
        OptionAlternateButton(
            placement: placement,
            primaryAction: CalendarExportAction.addToCalendar,
            alternateAction: CalendarExportAction.download,
            title: { $0.title },
            perform: perform,
            label: label
        )
    }
}

/// Opens calendar data through the user's selected macOS calendar application.
@MainActor
protocol CalendarImporting {
    func open(calendarText: String) throws
}

/// Writes each IDOS calendar response to a distinct temporary file before handing it to macOS.
@MainActor
struct WorkspaceCalendarImporter: CalendarImporting {
    func open(calendarText: String) throws {
        guard let data = calendarText.data(using: .utf8) else {
            throw CalendarImportError.invalidText
        }

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("Kastan", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory
            .appendingPathComponent("connection-\(UUID().uuidString)")
            .appendingPathExtension("ics")
        try data.write(to: file, options: .atomic)

        guard NSWorkspace.shared.open(file) else {
            throw CalendarImportError.cannotOpen
        }
    }
}

/// Saves calendar data only to a location explicitly selected by the user.
@MainActor
protocol CalendarSaving {
    func save(calendarText: String, suggestedFileName: String) throws
}

/// Uses the native macOS save panel to preserve an IDOS calendar export as an ICS file.
@MainActor
struct WorkspaceCalendarSaver: CalendarSaving {
    func save(calendarText: String, suggestedFileName: String) throws {
        guard let data = calendarText.data(using: .utf8) else {
            throw CalendarImportError.invalidText
        }

        let panel = NSSavePanel()
        if let contentType = UTType(filenameExtension: "ics") {
            panel.allowedContentTypes = [contentType]
        }
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.nameFieldStringValue = suggestedFileName
        panel.title = AppLocalization.string("Download ICS File")

        guard panel.runModal() == .OK, let destination = panel.url else {
            return
        }

        let isSecurityScoped = destination.startAccessingSecurityScopedResource()
        defer {
            if isSecurityScoped {
                destination.stopAccessingSecurityScopedResource()
            }
        }
        try data.write(to: destination, options: .atomic)
    }
}

/// Gives connection and service calendar downloads the same readable route-based stem as PDF exports.
enum CalendarExportFileName {
    static func connection(from: String, to: String) -> String {
        ResultExportFileName.connection(
            from: from,
            to: to,
            pathExtension: "ics"
        )
    }
}

enum CalendarImportError: LocalizedError {
    case invalidText
    case cannotOpen

    var errorDescription: String? {
        switch self {
        case .invalidText:
            AppLocalization.string("The calendar data could not be saved.")
        case .cannotOpen:
            AppLocalization.string("No application could open the calendar event.")
        }
    }
}
