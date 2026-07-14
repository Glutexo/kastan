import AppKit
import Foundation

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
