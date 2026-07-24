import AppKit
import Foundation
import Kastan

/// Produces the localized plain-text representation that a passenger can paste outside Kaštan.
///
/// The layout and semantic markers mirror the CLI's default text output for one selected result. Terminal-only
/// ANSI colors and emphasis are intentionally omitted so the clipboard always contains portable plain text.
struct CLIPlainTextPresentation {
    private let bundle: Bundle

    /// Uses the app localization by default while allowing deterministic localized product tests.
    init(bundle: Bundle = .main) {
        self.bundle = bundle
    }

    /// Formats one complete connection as a one-result CLI connection search.
    func connection(_ connection: IDOSConnection, timetable: IDOSTimetable) -> String {
        let labels = [
            connection.legs.count == 1 ? "➡️  \(text("Direct connection"))" : nil,
            "⚡ \(text("Shortest"))",
        ].compactMap(\.self)
        let labelPrefix = labels.isEmpty ? "" : "\(labels.joined(separator: " · ")) — "

        var summary = "1. \(labelPrefix)🕒 \(connection.departureTime) \(connection.departureStation) → \(connection.arrivalTime) \(connection.arrivalStation)"
        if !connection.duration.isEmpty {
            summary += " (\(connection.duration))"
        }

        if !connection.legs.isEmpty {
            let legs = connection.legs.map { leg in
                let lineName = [leg.transportMode?.emoji ?? "🛣️", leg.name]
                    .filter { !$0.isEmpty }
                    .joined(separator: " ")
                return "   \(lineName) \(leg.fromStation) \(leg.departureTime) → \(leg.arrivalTime) \(leg.toStation)"
            }
            summary += "\n\(legs.joined(separator: "\n"))"
        }

        return """
        🧭 \(text("Connections")) \(connection.departureStation) → \(connection.arrivalStation) (\(timetableName(timetable))):
        \(summary)
        """
    }

    /// Formats a dated service with its complete route and information, matching the CLI service command.
    func service(_ service: IDOSServiceDetail) -> String {
        let displayName = [service.transportMode?.emoji, service.name]
            .compactMap(\.self)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        var lines = [
            "\(displayName) · \(text("Service")) (\(timetableName(service.timetable)))",
            "   🆔 \(text("Service ID")): \(service.id)",
        ]
        if let date = service.date {
            lines.append("   📅 \(text("Date")): \(date)")
        }
        lines.append("🛤️ \(text("Route")):")

        lines.append(contentsOf: service.stops.enumerated().map { index, stop in
            var details: [String] = []
            if let arrivalTime = stop.arrivalTime {
                details.append("\(text("Arrival")) \(arrivalTime)")
            }
            if let departureTime = stop.departureTime {
                details.append("\(text("Departure")) \(departureTime)")
            }
            if let tariffZone = stop.tariffZone {
                details.append(text("tariff zone %@", tariffZone))
            }
            if let platform = stop.platform {
                details.append(text("platform %@", platform))
            }
            if let track = stop.track {
                details.append(text("track %@", track))
            }
            if let platformTrack = stop.platformTrack {
                details.append(text("platform/track %@", platformTrack))
            }
            if let distance = stop.distance {
                details.append(distance)
            }

            let suffix = details.isEmpty ? "" : " — \(details.joined(separator: " · "))"
            let notes = stop.notes.map { "\n      \(serviceStopNote($0))" }.joined()
            return "\(index + 1). 📍 \(stop.name)\(suffix)\(notes)"
        })

        if !service.information.isEmpty {
            lines.append("")
            lines.append("ℹ️ \(text("Information")):")
            lines.append(contentsOf: service.serviceInformation.map { "   \($0.displayText)" })
        }

        return lines.joined(separator: "\n")
    }

    private func timetableName(_ timetable: IDOSTimetable) -> String {
        switch timetable.slug {
        case "vlakyautobusymhdvse":
            return text("All timetables")
        case "vlakyautobusymhd":
            return text("Trains + Buses + Urban Public Transport")
        case "vlaky":
            return text("Trains")
        case "autobusy":
            return text("Buses")
        case "vlakyautobusy":
            return text("Trains + Buses")
        case "pid":
            return text("Prague + PID")
        default:
            let prefix = "Urban Public Transport "
            if timetable.displayName.hasPrefix(prefix) {
                return text("Urban Public Transport %@", String(timetable.displayName.dropFirst(prefix.count)))
            }
            return timetable.displayName
        }
    }

    /// Keeps the stop-note symbols aligned with CLI output without replacing the complete IDOS wording.
    private func serviceStopNote(_ note: String) -> String {
        let normalized = note
            .folding(
                options: [.diacriticInsensitive, .caseInsensitive],
                locale: Locale(identifier: "en_US_POSIX")
            )
            .lowercased()
        let symbol: String

        if normalized.contains("wheelchair accessible") || normalized.contains("bezbarier") {
            symbol = "♿"
        } else if normalized.contains("rail station") ||
            normalized.contains("railway station") ||
            normalized.contains("zeleznicni stanice") ||
            normalized.contains("zeleznicni dopravu")
        {
            symbol = "🚉"
        } else if normalized.contains("undeground") ||
            normalized.contains("underground") ||
            normalized.contains("metro")
        {
            symbol = "🚇"
        } else if normalized.contains("traffic restriction") ||
            normalized.contains("vyluk") ||
            normalized.contains("omezeni provozu")
        {
            symbol = "🚧"
        } else if normalized.contains("stops on signal") ||
            normalized.contains("request stop") ||
            normalized.contains("na znameni")
        {
            symbol = "🔔"
        } else {
            symbol = "ℹ️"
        }

        return "\(symbol) \(note)"
    }

    private func text(_ key: String, _ arguments: CVarArg...) -> String {
        let format = bundle.localizedString(forKey: key, value: key, table: nil)
        return String(format: format, locale: .current, arguments: arguments)
    }
}

/// Places complete connection and service details on the system clipboard as portable localized text.
@MainActor
enum ResultClipboard {
    /// Copies a complete connection with its timetable context in the same shape as a one-result CLI search.
    static func copy(connection: IDOSConnection, timetable: IDOSTimetable) {
        copy(CLIPlainTextPresentation().connection(connection, timetable: timetable))
    }

    /// Copies every stop and information row shown by a complete service detail.
    static func copy(service: IDOSServiceDetail) {
        copy(CLIPlainTextPresentation().service(service))
    }

    /// Replaces the clipboard atomically so a paste cannot mix a stale representation with the new result.
    @discardableResult
    static func copy(_ text: String, to pasteboard: NSPasteboard = .general) -> Bool {
        pasteboard.clearContents()
        return pasteboard.setString(text, forType: .string)
    }
}
