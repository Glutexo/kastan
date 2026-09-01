import Foundation
import Kastan

/// Produces the localized plain-text representation that a passenger can share outside Kaštan.
///
/// The layout and semantic markers mirror the CLI's default text output for one selected result. Terminal-only
/// ANSI colors and emphasis are intentionally omitted so every receiving application gets portable plain text.
struct CLIPlainTextPresentation {
    private let bundle: Bundle

    /// Uses the app localization by default while allowing deterministic localized product tests.
    init(bundle: Bundle = .main) {
        self.bundle = bundle
    }

    /// Formats one complete connection as a one-result CLI connection search.
    func connection(_ connection: TransitConnection, timetable: TransitTimetable) -> String {
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

    /// Formats the selected connection as the same portable HTML summary offered by the CLI.
    ///
    /// Mail drafts keep IDOS's editable introductory message above the result instead of replacing it.
    func connectionHTML(
        _ connection: TransitConnection,
        timetable: TransitTimetable,
        introductoryText: String? = nil
    ) -> String {
        let labels = [
            connection.legs.count == 1 ? "➡️  \(text("Direct connection"))" : nil,
            "⚡ \(text("Shortest"))",
        ].compactMap(\.self)
        let labelPrefix = labels.isEmpty
            ? ""
            : "<span class=\"badges\">\(PortableHTML.escape(labels.joined(separator: " · ")))</span> — "
        let rows = connection.legs.map { leg in
            [
                PortableHTML.lineName(leg),
                PortableHTML.escape(leg.fromStation),
                PortableHTML.strong(leg.departureTime),
                PortableHTML.escape(leg.toStation),
                PortableHTML.strong(leg.arrivalTime),
            ]
        }
        let introduction = introductoryText
            .map(PortableHTML.paragraphs)
            .map { "<div class=\"introduction\">\($0)</div>\n<hr>" }
            ?? ""
        let duration = connection.duration.isEmpty ? "" : """
        <p>⏱️ <strong>\(PortableHTML.escape(text("Duration"))):</strong> \(PortableHTML.escape(connection.duration))</p>
        """

        return PortableHTML.document(
            title: text("Connections"),
            language: AppLanguagePreference.transitLanguage.rawValue,
            body: """
            \(introduction)
            <h1>🧭 \(PortableHTML.escape(text("Connections")))</h1>
            \(PortableHTML.routeSummary([
                (label: text("From"), value: connection.departureStation),
                (label: text("To"), value: connection.arrivalStation),
                (label: text("Timetable"), value: timetableName(timetable)),
            ]))
            <h2>1. \(labelPrefix)🕒 \(PortableHTML.strong(connection.departureTime)) \(PortableHTML.escape(connection.departureStation)) → \(PortableHTML.strong(connection.arrivalTime)) \(PortableHTML.escape(connection.arrivalStation))</h2>
            \(duration)
            \(PortableHTML.table(
                headers: [text("Line"), text("From"), text("Departure"), text("To"), text("Arrival")],
                rows: rows
            ))
            """
        )
    }

    /// Formats a dated service with its complete route and information, matching the CLI service command.
    func service(_ service: TransitServiceDetail) -> String {
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
            if let platformTrack = stop.platformTrack {
                details.append(platformTrackDescription(platformTrack))
            } else if let platform = stop.platform, let track = stop.track {
                details.append(platformAndTrackDescription(platform: platform, track: track))
            } else {
                if let platform = stop.platform {
                    details.append(text("platform %@", platform))
                }
                if let track = stop.track {
                    details.append(text("track %@", track))
                }
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

    /// Replaces IDOS's compact `platform/track` notation with passenger-facing words when both
    /// components are present, while retaining unusual source values verbatim.
    private func platformTrackDescription(_ value: String) -> String {
        let parts = value.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 2 else { return text("platform/track %@", value) }

        let platform = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
        let track = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
        guard !platform.isEmpty, !track.isEmpty else {
            return text("platform/track %@", value)
        }
        return platformAndTrackDescription(platform: platform, track: track)
    }

    private func platformAndTrackDescription(platform: String, track: String) -> String {
        "\(text("platform %@", platform)) \(text("track %@", track))"
    }

    private func timetableName(_ timetable: TransitTimetable) -> String {
        guard timetable.dataSourceID == .idos else { return timetable.displayName }
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

/// Generates self-contained HTML that remains useful both as source and after AppKit imports it as rich text.
private enum PortableHTML {
    static func document(title: String, language: String, body: String) -> String {
        """
        <!doctype html>
        <html lang="\(escape(language))">
        <head>
          <meta charset="utf-8">
          <title>\(escape(title))</title>
          <style>
            body, table, h1, h2, p, div, span, th, td {
              font-family: -apple-system, BlinkMacSystemFont, "Helvetica Neue", Helvetica, Arial, sans-serif;
            }
            body { font-size: 15px; line-height: 1.45; margin: 20px; }
            h1, h2 { font-weight: bold; line-height: 1.25; margin: 20px 0 10px; }
            h1 { font-size: 1.55em; }
            h2 { font-size: 1.2em; }
            p { margin: 8px 0 14px; }
            table { border-collapse: collapse; margin: 12px 0 20px; width: 100%; }
            th, td { border: 1px solid #b8bec6; padding: 6px 10px; text-align: left; vertical-align: top; }
            th, .badges { font-weight: bold; }
            .route-summary { background: #f5f6f8; border: 1px solid #d8dce2; }
            .route-summary th, .route-summary td { border: 0; padding: 7px 10px; }
            .route-summary th { color: #5f6872; font-size: 0.85em; white-space: nowrap; width: 7.5em; }
            .route-summary td { font-weight: bold; }
            .route-summary tr + tr th, .route-summary tr + tr td { border-top: 1px solid #e1e4e8; }
            hr { border: 0; border-top: 1px solid #b8bec6; margin: 20px 0; }
          </style>
        </head>
        <body>
        \(body)
        </body>
        </html>
        """
    }

    static func escape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }

    static func strong(_ value: String) -> String {
        guard !value.isEmpty else { return "" }
        return "<strong>\(escape(value))</strong>"
    }

    static func paragraphs(_ value: String) -> String {
        value
            .components(separatedBy: "\n\n")
            .map { "<p>\(escape($0).replacingOccurrences(of: "\n", with: "<br>\n"))</p>" }
            .joined(separator: "\n")
    }

    /// Aligns route labels and values without relying on CSS grid, which Mail's HTML importer does not preserve.
    static func routeSummary(_ items: [(label: String, value: String)]) -> String {
        let rows = items.map { item in
            "<tr><th scope=\"row\">\(escape(item.label))</th><td>\(escape(item.value))</td></tr>"
        }.joined(separator: "\n")
        return "<table class=\"route-summary\">\n<tbody>\n\(rows)\n</tbody>\n</table>"
    }

    /// Renders escaped headers and trusted, already-escaped cell markup.
    static func table(headers: [String], rows: [[String]]) -> String {
        let header = headers.map { "<th scope=\"col\">\(escape($0))</th>" }.joined()
        let body = rows.map { row in
            "<tr>\(row.map { "<td>\($0)</td>" }.joined())</tr>"
        }.joined(separator: "\n")
        return """
        <table>
          <thead><tr>\(header)</tr></thead>
          <tbody>
        \(body)
          </tbody>
        </table>
        """
    }

    static func lineName(_ leg: TransitConnectionLeg) -> String {
        let prefix = leg.transportMode.map { "\($0.emoji) " } ?? "🛣️ "
        let name = escape(leg.name)
        guard let color = leg.color,
              color.range(
                of: #"^#(?:[0-9A-Fa-f]{3}|[0-9A-Fa-f]{4}|[0-9A-Fa-f]{6}|[0-9A-Fa-f]{8})$"#,
                options: .regularExpression
              ) != nil
        else {
            return "\(prefix)\(name)"
        }
        return "\(prefix)<span style=\"color: \(color)\">\(name)</span>"
    }
}
