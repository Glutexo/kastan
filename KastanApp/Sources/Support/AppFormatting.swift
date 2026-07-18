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

/// Preserves the submitted query as a compact, readable replacement for an expanded search form.
struct SearchSummaryPresentation: Equatable {
    let title: String
    let details: [String]

    var detailText: String {
        details.joined(separator: " · ")
    }

    static func connection(
        from: String,
        to: String,
        timetable: String,
        date: String,
        time: String,
        mode: String,
        via: [String],
        transferLimit: String
    ) -> Self {
        let departure = cleaned(from)
        let arrival = cleaned(to)
        let viaPlaces = via.map(cleaned).filter { !$0.isEmpty }
        var details = baseDetails(timetable: timetable, date: date, time: time, mode: mode)

        if !viaPlaces.isEmpty {
            details.append(AppLocalization.string("via %@", viaPlaces.joined(separator: " → ")))
        }
        details.append(cleaned(transferLimit))

        return Self(
            title: "\(departure) → \(arrival)",
            details: details.filter { !$0.isEmpty }
        )
    }

    static func station(
        name: String,
        timetable: String,
        date: String,
        time: String,
        mode: String
    ) -> Self {
        Self(
            title: cleaned(name),
            details: baseDetails(timetable: timetable, date: date, time: time, mode: mode)
        )
    }

    private static func baseDetails(
        timetable: String,
        date: String,
        time: String,
        mode: String
    ) -> [String] {
        let dateTime = [cleaned(date), cleaned(time)]
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return [cleaned(timetable), dateTime, cleaned(mode)].filter { !$0.isEmpty }
    }

    private static func cleaned(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// Selects the IDOS text variant that matches the app's current system language.
enum AppLanguagePreference {
    static var idosLanguage: IDOSLanguage {
        Bundle.main.preferredLocalizations.first == "cs" ? .czech : .english
    }

    /// Converts a permanent IDOS result link to the website variant matching the app language.
    static func localizedIDOSURL(from value: String) -> URL? {
        localizedIDOSURL(from: value, language: idosLanguage)
    }

    /// Provides an explicit language variant for deterministic presentation tests.
    static func localizedIDOSURL(from value: String, language: IDOSLanguage) -> URL? {
        guard let url = URL(string: value),
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else {
            return nil
        }

        guard components.host?.lowercased() == "idos.cz" else {
            return url
        }

        var path = components.percentEncodedPath
        switch language {
        case .czech:
            if path == "/en" {
                path = "/"
            } else if path.hasPrefix("/en/") {
                path.removeFirst(3)
            }
        case .english:
            if path != "/en", !path.hasPrefix("/en/") {
                path = "/en" + (path.hasPrefix("/") ? path : "/\(path)")
            }
        }
        components.percentEncodedPath = path
        return components.url
    }
}

/// Resolves runtime-generated text through the same bundle localization SwiftUI uses for static labels.
enum AppLocalization {
    static func string(_ key: String, _ arguments: CVarArg...) -> String {
        let format = Bundle.main.localizedString(forKey: key, value: key, table: nil)
        return String(format: format, locale: .current, arguments: arguments)
    }

    /// Resolves number-dependent wording through the locale's Unicode plural rules.
    static func plural(_ key: String, count: Int, bundle: Bundle = .main) -> String {
        let format = bundle.localizedString(forKey: key, value: key, table: nil)
        return String.localizedStringWithFormat(format, Int64(count))
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
        case .pdfUnavailable:
            return AppLocalization.string("IDOS did not provide PDF export data for this connection.")
        case .stationTimetableUnavailable:
            return AppLocalization.string(
                "IDOS could not generate a station timetable for this line, direction, and date."
            )
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

/// Stores an ordered, persistent subset of the known timetable catalog for quick picker access.
struct TimetableFavorites: Equatable {
    static let storageKey = "favoriteTimetableSlugs"

    private(set) var slugs: [String]

    init(slugs: [String] = []) {
        let knownSlugs = Set(IDOSTimetable.known.map(\.slug))
        var uniqueSlugs = Set<String>()
        self.slugs = slugs.filter { slug in
            knownSlugs.contains(slug) && uniqueSlugs.insert(slug).inserted
        }
    }

    init(serialized: String) {
        guard let data = serialized.data(using: .utf8),
              let slugs = try? JSONDecoder().decode([String].self, from: data)
        else {
            self.init()
            return
        }
        self.init(slugs: slugs)
    }

    var serialized: String {
        guard let data = try? JSONEncoder().encode(slugs),
              let value = String(data: data, encoding: .utf8)
        else {
            return "[]"
        }
        return value
    }

    var timetables: [IDOSTimetable] {
        slugs.compactMap { slug in
            IDOSTimetable.known.first { $0.slug == slug }
        }
    }

    func contains(_ timetable: IDOSTimetable) -> Bool {
        slugs.contains(timetable.slug)
    }

    mutating func toggle(_ timetable: IDOSTimetable) {
        if let index = slugs.firstIndex(of: timetable.slug) {
            slugs.remove(at: index)
        } else if IDOSTimetable.known.contains(where: { $0.slug == timetable.slug }) {
            slugs.append(timetable.slug)
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

    /// Limits station timetables to the integrated systems and individual MHD catalogs supported by IDOS.
    static var stationTimetables: [IDOSTimetable] {
        integratedSystems.timetables + cityTransport.timetables
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

/// Supplies one sectioned timetable menu to search pickers, optionally limited to a supported subset.
struct AppTimetablePickerOptions: View {
    let favoriteSlugs: [String]
    let allowedTimetables: [IDOSTimetable]

    init(
        favoriteSlugs: [String] = [],
        allowedTimetables: [IDOSTimetable] = IDOSTimetable.known
    ) {
        self.favoriteSlugs = favoriteSlugs
        self.allowedTimetables = allowedTimetables
    }

    var body: some View {
        if !favoriteTimetables.isEmpty {
            Section {
                ForEach(favoriteTimetables, id: \.slug) { timetable in
                    Text(timetable.appDisplayName).tag(timetable.slug)
                }
            } header: {
                Text("Favorites")
            }
        }

        ForEach(AppTimetableGroup.allCases) { group in
            let timetables = catalogTimetables(in: group)
            if !timetables.isEmpty {
                Section {
                    ForEach(timetables, id: \.slug) { timetable in
                        Text(timetable.appDisplayName).tag(timetable.slug)
                    }
                } header: {
                    Text(group.title)
                }
            }
        }
    }

    private var favorites: TimetableFavorites {
        TimetableFavorites(slugs: favoriteSlugs)
    }

    private var favoriteTimetables: [IDOSTimetable] {
        favorites.timetables.filter(isAllowed)
    }

    /// Keeps every allowed timetable in its catalog section, even when favorites also expose it
    /// for quick access.
    func catalogTimetables(in group: AppTimetableGroup) -> [IDOSTimetable] {
        group.timetables.filter(isAllowed)
    }

    private func isAllowed(_ timetable: IDOSTimetable) -> Bool {
        allowedTimetables.contains(where: { $0.slug == timetable.slug })
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
                return String(displayName.dropFirst(prefix.count))
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

    /// Localizes known IDOS delay states while preserving unrecognized carrier messages verbatim.
    static func delay(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        if value.compare("Currently no delay", options: .caseInsensitive) == .orderedSame {
            return AppLocalization.string("Currently no delay")
        }
        return value
    }
}

/// Presents IDOS notes and service information with consistent list indentation and readable wrapping.
struct BulletedTextList: View {
    let items: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("•")
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)
                        .frame(width: 8, alignment: .center)
                        .accessibilityHidden(true)
                    Text(item)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
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
