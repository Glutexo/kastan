import Foundation
import Kastan
import SwiftUI

/// Converts app controls into the date and time values expected by IDOS.
enum IDOSRequestFormatting {
    static func date(from value: Date) -> String {
        formatter(format: "d.M.yyyy").string(from: value)
    }

    static func time(from value: Date) -> String {
        formatter(format: "H:mm").string(from: value)
    }

    private static func formatter(format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = format
        return formatter
    }
}

/// Selects the IDOS text variant that matches the app's current system language.
enum AppLanguagePreference {
    static var idosLanguage: IDOSLanguage {
        Bundle.main.preferredLocalizations.first == "cs" ? .czech : .english
    }
}

/// Resolves runtime-generated text through the same bundle localization SwiftUI uses for static labels.
enum AppLocalization {
    static func string(_ key: String, _ arguments: CVarArg...) -> String {
        let format = Bundle.main.localizedString(forKey: key, value: key, table: nil)
        return String(format: format, locale: .current, arguments: arguments)
    }
}

/// Converts library failures into app-localized, actionable messages without hiding platform detail.
enum AppErrorPresentation {
    static func message(for error: Error) -> String {
        guard let error = error as? IDOSError else {
            return error.localizedDescription
        }

        switch error {
        case .invalidResponse:
            return AppLocalization.string("IDOS returned an unexpected response.")
        case .invalidURL:
            return AppLocalization.string("Could not build the IDOS URL.")
        case .invalidJSONP:
            return AppLocalization.string("IDOS returned an unexpected JSONP format.")
        case .invalidTimetable(let value):
            return AppLocalization.string("Invalid timetable: %@.", value)
        case .networkUnavailable(let detail):
            let detail = detail.trimmingCharacters(in: .whitespacesAndNewlines)
            return detail.isEmpty
                ? AppLocalization.string("Network request failed. Check your internet connection.")
                : AppLocalization.string("Network request failed. Check your internet connection. %@", detail)
        case .calendarUnavailable:
            return AppLocalization.string("IDOS did not provide calendar export data for this connection.")
        case .invalidServiceIdentifier(let value):
            return AppLocalization.string("Invalid service ID: %@.", value)
        case .serviceDetailUnavailable(let detail):
            let detail = detail.trimmingCharacters(in: .whitespacesAndNewlines)
            return detail.isEmpty
                ? AppLocalization.string("IDOS could not load this service detail.")
                : AppLocalization.string("IDOS could not load this service detail. %@", detail)
        }
    }
}

/// Product-facing sections that keep the long IDOS timetable catalog scannable.
enum AppTimetableGroup: CaseIterable, Identifiable {
    case general
    case integratedSystems
    case cityTransport

    private static let generalSlugs: Set<String> = [
        "vlakyautobusymhdvse",
        "vlakyautobusymhd",
        "vlaky",
        "autobusy",
        "vlakyautobusy"
    ]
    private static let cityTransportPrefix = "Urban Public Transport "

    var id: Self { self }

    var title: LocalizedStringKey {
        switch self {
        case .general:
            "Trains, buses, and all"
        case .integratedSystems:
            "Integrated transport systems"
        case .cityTransport:
            "Urban public transport by city"
        }
    }

    var timetables: [IDOSTimetable] {
        let matches = IDOSTimetable.known.filter(contains)
        guard self == .cityTransport else { return matches }
        return matches.sorted {
            $0.appDisplayName.localizedStandardCompare($1.appDisplayName) == .orderedAscending
        }
    }

    private func contains(_ timetable: IDOSTimetable) -> Bool {
        let isGeneral = Self.generalSlugs.contains(timetable.slug)
        let isCityTransport = timetable.displayName.hasPrefix(Self.cityTransportPrefix)

        switch self {
        case .general:
            return isGeneral
        case .integratedSystems:
            return !isGeneral && !isCityTransport
        case .cityTransport:
            return isCityTransport
        }
    }
}

/// Supplies the same sectioned timetable menu to connection and station-board pickers.
struct AppTimetablePickerOptions: View {
    var body: some View {
        ForEach(AppTimetableGroup.allCases) { group in
            Section {
                ForEach(group.timetables, id: \.slug) { timetable in
                    Text(timetable.appDisplayName).tag(timetable.slug)
                }
            } header: {
                Text(group.title)
            }
        }
    }
}

extension IDOSTimetable {
    /// Localizes catalog labels while preserving city and integrated-system proper names.
    var appDisplayName: String {
        switch slug {
        case "vlakyautobusymhdvse":
            return AppLocalization.string("All timetables")
        case "vlakyautobusymhd":
            return AppLocalization.string("Trains + Buses + Urban Public Transport")
        case "vlaky":
            return AppLocalization.string("Trains")
        case "autobusy":
            return AppLocalization.string("Buses")
        case "vlakyautobusy":
            return AppLocalization.string("Trains + Buses")
        case "pid":
            return AppLocalization.string("Prague + PID")
        default:
            let prefix = "Urban Public Transport "
            if displayName.hasPrefix(prefix) {
                return "\(AppLocalization.string("Urban Public Transport")) \(displayName.dropFirst(prefix.count))"
            }
            return displayName
        }
    }
}

/// Keeps optional metadata compact and readable in result rows.
enum ResultMetadata {
    static func joined(_ values: String?...) -> String? {
        let content = values
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
        return content.isEmpty ? nil : content
    }

    static func station(tariffZone: String?, platform: String?) -> String? {
        joined(
            tariffZone.map { AppLocalization.string("Zone %@", $0) },
            platform.map { AppLocalization.string("Platform %@", $0) }
        )
    }
}

extension Color {
    /// Preserves an IDOS line color when it uses the HTML `#RRGGBB` representation.
    init?(idosHTMLColor value: String?) {
        guard let value else {
            return nil
        }
        let hex = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard hex.hasPrefix("#"), hex.count == 7,
              let rgb = UInt64(hex.dropFirst(), radix: 16)
        else {
            return nil
        }

        self.init(
            red: Double((rgb >> 16) & 0xFF) / 255,
            green: Double((rgb >> 8) & 0xFF) / 255,
            blue: Double(rgb & 0xFF) / 255
        )
    }
}
