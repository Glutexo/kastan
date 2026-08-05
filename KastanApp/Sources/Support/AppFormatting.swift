import AppKit
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
    private static let countryCodeByEnglishName: [String: String] = {
        let english = Locale(identifier: "en_US")
        var result: [String: String] = [:]
        for region in Locale.Region.isoRegions {
            if let name = english.localizedString(forRegionCode: region.identifier) {
                result[normalizedCountryName(name)] = region.identifier
            }
        }
        return result
    }()

    static var idosLanguage: IDOSLanguage {
        Bundle.main.preferredLocalizations.first == "cs" ? .czech : .english
    }

    /// Localizes an English country name returned in IDOS metadata through its ISO region code.
    static func localizedCountryName(fromEnglishName name: String, language: IDOSLanguage) -> String? {
        guard let regionCode = countryCodeByEnglishName[normalizedCountryName(name)] else {
            return nil
        }
        let locale = switch language {
        case .czech:
            Locale(identifier: "cs_CZ")
        case .english:
            Locale(identifier: "en_US")
        }
        return locale.localizedString(forRegionCode: regionCode)
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

    private static func normalizedCountryName(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US"))
            .lowercased()
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
        return String(
            format: format,
            locale: pluralLocale(for: bundle),
            arguments: [Int64(count)]
        )
    }

    /// Resolves the locale represented by a localization resource bundle.
    static func locale(for bundle: Bundle) -> Locale {
        if bundle.bundleURL.pathExtension == "lproj" {
            return Locale(
                identifier: bundle.bundleURL.deletingPathExtension().lastPathComponent
            )
        }

        let localization = bundle.preferredLocalizations.first
            ?? bundle.developmentLocalization
        guard let localization, localization != "Base" else {
            return .current
        }
        return Locale(identifier: localization)
    }

    /// Keeps plural rules aligned with the localization that supplied the product wording,
    /// independently of the Mac's language or the environment running the application tests.
    static func pluralLocale(for bundle: Bundle) -> Locale {
        locale(for: bundle)
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
        case .emailUnavailable:
            return AppLocalization.string("IDOS did not provide email data for this connection.")
        case .emailSendingFailed(let detail):
            let detail = detail.trimmingCharacters(in: .whitespacesAndNewlines)
            return detail.isEmpty
                ? AppLocalization.string("IDOS could not send the connection by email.")
                : AppLocalization.string("IDOS could not send the connection by email. %@", detail)
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

/// Keeps every macOS search mode aligned on the narrowest useful timetable available to all of them.
enum AppTimetableDefaults {
    static let search = IDOSTimetable.known.first { $0.slug == "vlaky" }
        ?? IDOSTimetable(slug: "vlaky", displayName: "Trains")
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

    /// Limits station timetables to trains, integrated systems, and individual MHD catalogs supported by IDOS.
    static var stationTimetables: [IDOSTimetable] {
        let trains = general.timetables.filter { $0.slug == "vlaky" }
        return trains + integratedSystems.timetables + cityTransport.timetables
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

/// Defines the application-wide persisted choice for showing optional item metadata.
enum ResultItemDetailsPreference {
    static let storageKey = "showsItemDetails"
    static let defaultValue = false
}

/// Defines the application-wide persisted choice for visually separating adjacent data rows.
enum AlternatingRowBackgroundPreference {
    static let storageKey = "showsAlternatingRowBackgrounds"
    static let defaultValue = true
}

/// Decides which data rows receive the subtle alternate tint shared across result views.
enum AlternatingRowBackgroundPresentation {
    /// Mirrors the horizontal rows affected by the presentation setting in the View menu.
    static let menuSystemImage = "rectangle.split.1x2"

    static func isTinted(rowAt index: Int, isEnabled: Bool) -> Bool {
        isEnabled && !index.isMultiple(of: 2)
    }
}

private struct ShowsAlternatingRowBackgroundsEnvironmentKey: EnvironmentKey {
    static let defaultValue = AlternatingRowBackgroundPreference.defaultValue
}

extension EnvironmentValues {
    /// Propagates the global row-background preference through every result window and preview.
    var showsAlternatingRowBackgrounds: Bool {
        get { self[ShowsAlternatingRowBackgroundsEnvironmentKey.self] }
        set { self[ShowsAlternatingRowBackgroundsEnvironmentKey.self] = newValue }
    }
}

/// Applies one adaptive system-color band without obscuring selection or route highlighting.
private struct AlternatingRowBackgroundModifier: ViewModifier {
    @Environment(\.showsAlternatingRowBackgrounds) private var isEnabled
    let index: Int

    func body(content: Content) -> some View {
        content.background(
            AlternatingRowBackgroundPresentation.isTinted(rowAt: index, isEnabled: isEnabled)
                ? Color.secondary.opacity(0.08)
                : Color.clear
        )
    }
}

extension View {
    /// Gives a data row its position-aware background while respecting the global View setting.
    func alternatingRowBackground(at index: Int) -> some View {
        modifier(AlternatingRowBackgroundModifier(index: index))
    }
}

/// Defines one application-wide persisted choice for replacing compact service and stop symbols
/// with the complete wording supplied by IDOS.
enum SymbolTextPreference {
    static let storageKey = "showsSymbolsAsText"
    static let defaultValue = false

    /// Retains an enabled text presentation when upgrading from either former independent setting.
    static let legacyStorageKeys = [
        "showsServiceInformationText",
        "showsStopNoteText",
    ]

    static func migrateLegacyValues(in defaults: UserDefaults = .standard) {
        guard defaults.object(forKey: storageKey) == nil else {
            return
        }

        let storedLegacyKeys = legacyStorageKeys.filter {
            defaults.object(forKey: $0) != nil
        }
        guard !storedLegacyKeys.isEmpty else {
            return
        }

        defaults.set(
            storedLegacyKeys.contains { defaults.bool(forKey: $0) },
            forKey: storageKey
        )
    }
}

/// Preserves the order and complete meaning of the facilities and restrictions printed by IDOS.
struct ServiceInformationPresentation: Equatable {
    let values: [IDOSServiceInformation]

    var symbols: String {
        values.map(\.symbol).joined(separator: " ")
    }

    var text: String {
        values.map(\.text).joined(separator: " · ")
    }

    var accessibilityLabel: String {
        values.map(\.text).joined(separator: ". ")
    }

    var helpText: String {
        values.map(\.text).joined(separator: "\n")
    }

    func content(showsText: Bool) -> String {
        showsText ? text : symbols
    }
}

/// Describes the classifier result that selected one semantic service-information emoji.
struct ServiceInformationRulePresentation: Equatable {
    let information: IDOSServiceInformation

    /// Keeps the complete IDOS wording beside the exact product category and its selected symbol.
    func explanation(bundle: Bundle = .main) -> String {
        let format = bundle.localizedString(
            forKey: "Matched rule: service information classified as “%@”, whose symbol is %@.",
            value: nil,
            table: nil
        )
        let rule = String(
            format: format,
            locale: AppLocalization.pluralLocale(for: bundle),
            arguments: [information.category.rawValue, information.symbol]
        )
        return "\(information.text)\n\(rule)"
    }
}

/// Shows compact semantic emoji by default and the unabridged IDOS wording on request.
struct ServiceInformationSummary: View {
    let values: [IDOSServiceInformation]
    let showsText: Bool

    var body: some View {
        let presentation = ServiceInformationPresentation(values: values)

        if !values.isEmpty, showsText {
            Text(verbatim: presentation.content(showsText: showsText))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel(Text(verbatim: presentation.accessibilityLabel))
                .help(presentation.helpText)
        } else if !values.isEmpty {
            HStack(spacing: 4) {
                ForEach(Array(values.enumerated()), id: \.offset) { _, information in
                    InspectableSemanticSymbol(
                        symbol: information.symbol,
                        helpText: information.text,
                        ruleExplanation: ServiceInformationRulePresentation(
                            information: information
                        ).explanation()
                    )
                }
            }
            .font(.headline)
            .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Keeps common stop properties next to the stop name while retaining any note that cannot be
/// represented unambiguously by a passenger-facing symbol.
struct StopNotePresentation: Equatable {
    struct Symbol: Equatable {
        let emoji: String
        let note: String
        let matchedRule: String

        /// Combines the original IDOS note with the exact rule requested by Option-clicking its emoji.
        func ruleExplanation(bundle: Bundle = .main) -> String {
            let format = bundle.localizedString(
                forKey: "Matched rule: note contains “%@” after ignoring letter case and diacritics.",
                value: nil,
                table: nil
            )
            let rule = String(
                format: format,
                locale: AppLocalization.pluralLocale(for: bundle),
                arguments: [matchedRule]
            )
            return "\(note)\n\(rule)"
        }
    }

    private struct EmojiRule {
        let emoji: String
        let phrases: [String]
    }

    /// Rule order preserves the established preference when one note matches multiple meanings.
    private static let emojiRules = [
        EmojiRule(emoji: "♿", phrases: ["wheelchair accessible", "bezbarier"]),
        EmojiRule(
            emoji: "🚉",
            phrases: [
                "rail station",
                "railway station",
                "zeleznicni stanice",
                "zeleznicni dopravu",
            ]
        ),
        EmojiRule(emoji: "🚇", phrases: ["undeground", "underground", "metro"]),
        EmojiRule(
            emoji: "🚧",
            phrases: ["traffic restriction", "vyluk", "omezeni provozu"]
        ),
        EmojiRule(emoji: "🔔", phrases: ["stops on signal", "request stop", "na znameni"]),
    ]

    let symbols: [Symbol]
    let textNotes: [String]

    init(notes: [String], showsText: Bool) {
        guard !showsText else {
            symbols = []
            textNotes = notes
            return
        }

        var symbols: [Symbol] = []
        var textNotes: [String] = []
        for note in notes {
            if let symbol = Self.symbol(for: note) {
                symbols.append(symbol)
            } else {
                textNotes.append(note)
            }
        }
        self.symbols = symbols
        self.textNotes = textNotes
    }

    private static func symbol(for note: String) -> Symbol? {
        let normalized = note
            .folding(
                options: [.diacriticInsensitive, .caseInsensitive],
                locale: Locale(identifier: "en_US_POSIX")
            )
            .lowercased()

        for rule in emojiRules {
            if let matchedRule = rule.phrases.first(where: normalized.contains) {
                return Symbol(emoji: rule.emoji, note: note, matchedRule: matchedRule)
            }
        }
        return nil
    }
}

/// Exposes the original IDOS wording to VoiceOver and on hover without taking the compact symbol
/// away from the stop title.
struct StopNoteSymbols: View {
    let values: [StopNotePresentation.Symbol]

    var body: some View {
        ForEach(Array(values.enumerated()), id: \.offset) { _, value in
            StopNoteSymbol(value: value)
        }
    }
}

/// Keeps ordinary hover help compact and opens the matching rule only after an explicit Option-click.
struct StopNoteSymbol: View {
    let value: StopNotePresentation.Symbol

    var body: some View {
        InspectableSemanticSymbol(
            symbol: value.emoji,
            helpText: value.note,
            ruleExplanation: value.ruleExplanation()
        )
    }
}

/// Gives every compact semantic symbol the same hover help, Option-click popover, and VoiceOver action.
struct InspectableSemanticSymbol: View {
    let symbol: String
    let helpText: String
    let ruleExplanation: String
    @State private var showsRuleExplanation = false

    var body: some View {
        Text(verbatim: symbol)
            .accessibilityLabel(Text(verbatim: helpText))
            .accessibilityAction(named: Text("Show matched rule")) {
                showsRuleExplanation = true
            }
            .help(Text(verbatim: helpText))
            .overlay {
                OptionClickOverlay {
                    showsRuleExplanation = true
                }
            }
            .popover(isPresented: $showsRuleExplanation, arrowEdge: .bottom) {
                RuleExplanationPopover(text: ruleExplanation)
            }
    }
}

/// Keeps diagnostic matching details readable and selectable without taking over the result window.
struct RuleExplanationPopover: View {
    let text: String

    var body: some View {
        Text(verbatim: text)
            .font(.callout)
            .frame(width: 320, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .textSelection(.enabled)
            .padding(12)
    }
}

/// Adds a modifier-sensitive click target without turning the emoji into a nested button.
struct OptionClickOverlay: NSViewRepresentable {
    let action: () -> Void

    func makeNSView(context: Context) -> OptionClickCaptureView {
        OptionClickCaptureView(action: action)
    }

    func updateNSView(_ nsView: OptionClickCaptureView, context: Context) {
        nsView.action = action
    }
}

/// Observes Option-modified primary clicks over its symbol without entering SwiftUI's hit-testing,
/// so ordinary clicks continue to reach the surrounding result row.
final class OptionClickCaptureView: NSView {
    var action: () -> Void
    /// AppKit creates and consumes this opaque token exclusively on the main thread.
    nonisolated(unsafe) private var eventMonitor: Any?

    init(action: @escaping () -> Void) {
        self.action = action
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is unavailable")
    }

    deinit {
        if let eventMonitor {
            MainActor.assumeIsolated {
                NSEvent.removeMonitor(eventMonitor)
            }
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        removeEventMonitor()
        guard window != nil else { return }
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            guard let self else { return event }
            return process(event)
        }
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    static func handles(_ event: NSEvent) -> Bool {
        event.type == .leftMouseDown && event.modifierFlags.contains(.option)
    }

    func captures(_ event: NSEvent) -> Bool {
        guard Self.handles(event), event.window === window else { return false }
        return bounds.contains(convert(event.locationInWindow, from: nil))
    }

    /// Mirrors the local event monitor so the complete window-and-coordinate decision stays testable.
    func process(_ event: NSEvent) -> NSEvent? {
        guard captures(event) else { return event }
        action()
        return nil
    }

    private func removeEventMonitor() {
        guard let eventMonitor else { return }
        NSEvent.removeMonitor(eventMonitor)
        self.eventMonitor = nil
    }
}

/// Keeps optional stop facts visually subordinate while their hover and VoiceOver wording stays explicit.
struct CompactStopMetadata: View {
    let values: [ResultMetadata.CompactItem]

    var body: some View {
        ForEach(Array(values.enumerated()), id: \.offset) { _, value in
            Text(verbatim: value.text)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize()
                .help(Text(verbatim: value.helpText))
                .accessibilityLabel(Text(verbatim: value.helpText))
        }
    }
}

/// Keeps optional metadata compact, readable, and governed by the global View preference.
enum ResultMetadata {
    /// Keeps the source value short on the route while retaining its complete localized meaning.
    struct CompactItem: Equatable {
        let text: String
        let helpText: String
    }

    private static let currentDelayExpressions = [
        #"^Current\s+delay\s+of\s+([0-9]+)\s+minutes?$"#,
        #"^Aktuální\s+zpoždění\s+([0-9]+)\s+minut(?:a|y)?$"#,
    ].compactMap {
        try? NSRegularExpression(pattern: $0, options: [.caseInsensitive])
    }

    static func joined(_ values: String?...) -> String? {
        joined(values)
    }

    /// Returns joined metadata only when the user has enabled item details for the application.
    static func visible(showsDetails: Bool, _ values: String?...) -> String? {
        guard showsDetails else { return nil }
        return joined(values)
    }

    /// Shows compact stop facts only while item details are enabled and symbols remain compact.
    static func compactStopValues(
        showsDetails: Bool,
        showsSymbolsAsText: Bool,
        _ values: [CompactItem]
    ) -> [CompactItem] {
        guard showsDetails, !showsSymbolsAsText else { return [] }
        return values
    }

    private static func joined(_ values: [String?]) -> String? {
        let content = values
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
        return content.isEmpty ? nil : content
    }

    static func station(
        tariffZone: String?,
        platform: String?,
        track: String? = nil,
        platformTrack: String? = nil
    ) -> String? {
        let position: String?
        if let platformTrack {
            position = platformTrackDescription(platformTrack)
        } else if let platform, let track {
            position = platformAndTrackDescription(platform: platform, track: track)
        } else {
            position = joined(
                platform.map { AppLocalization.string("Platform %@", $0) },
                track.map { AppLocalization.string("Track %@", $0) }
            )
        }
        return joined(
            tariffZone.map { AppLocalization.string("Zone %@", $0) },
            position
        )
    }

    /// Places fare zones and a complete-route platform or track beside the stop title in symbol mode.
    static func compactStation(
        tariffZone: String?,
        platform: String?,
        track: String? = nil,
        platformTrack: String? = nil,
        bundle: Bundle = .main
    ) -> [CompactItem] {
        [
            compactZone(tariffZone, bundle: bundle),
            compactPosition(
                platform: platform,
                track: track,
                platformTrack: platformTrack,
                platformLocalizationKey: "Platform %@",
                bundle: bundle
            ),
        ].compactMap(\.self)
    }

    /// Uses the timetable's neutral platform-or-stand wording for its compact stop position.
    static func compactStationTimetable(
        tariffZone: String?,
        platform: String?,
        bundle: Bundle = .main
    ) -> [CompactItem] {
        [
            compactZone(tariffZone, bundle: bundle),
            cleaned(platform).map {
                CompactItem(
                    text: $0,
                    helpText: localized(
                        "Station timetable platform %@",
                        $0,
                        bundle: bundle
                    )
                )
            },
        ].compactMap(\.self)
    }

    /// Matches IDOS connection results by omitting tariff zones that a compact service row cannot
    /// unambiguously associate with either endpoint.
    static func connectionLeg(_ leg: IDOSConnectionLeg, showsDetails: Bool) -> String? {
        visible(
            showsDetails: showsDetails,
            leg.carrier,
            delay(leg.delay),
            leg.fromPlatform.map {
                connectionPlatformDescription($0, transportMode: leg.transportMode)
            }
        )
    }

    /// Expands IDOS's compact railway `platform/track` value into an unambiguous localized phrase.
    static func platformTrackDescription(
        _ value: String,
        bundle: Bundle = .main
    ) -> String {
        guard let components = platformTrackComponents(value) else {
            return localized("platform/track %@", value, bundle: bundle)
        }
        return platformAndTrackDescription(
            platform: components.platform,
            track: components.track,
            bundle: bundle
        )
    }

    private static func platformAndTrackDescription(
        platform: String,
        track: String,
        separator: String = " ",
        bundle: Bundle = .main
    ) -> String {
        return [
            localized("Platform %@", platform, bundle: bundle),
            localized("track %@", track, bundle: bundle),
        ].joined(separator: separator)
    }

    private static func compactZone(
        _ value: String?,
        bundle: Bundle
    ) -> CompactItem? {
        guard let value = cleaned(value) else { return nil }
        let zones = value
            .split(separator: ",", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !zones.isEmpty else { return nil }

        let text = zones.joined(separator: ",")
        if zones.count == 1 {
            return CompactItem(
                text: text,
                helpText: localized("Zone %@", zones[0], bundle: bundle)
            )
        }

        let formatter = ListFormatter()
        formatter.locale = AppLocalization.locale(for: bundle)
        let list = formatter.string(from: zones) ?? zones.joined(separator: ", ")
        return CompactItem(
            text: text,
            helpText: localized("Zones %@", list, bundle: bundle)
        )
    }

    private static func compactPosition(
        platform: String?,
        track: String?,
        platformTrack: String?,
        platformLocalizationKey: String,
        bundle: Bundle
    ) -> CompactItem? {
        if let platformTrack = cleaned(platformTrack) {
            guard let components = platformTrackComponents(platformTrack) else {
                return CompactItem(
                    text: platformTrack,
                    helpText: localized("platform/track %@", platformTrack, bundle: bundle)
                )
            }
            return CompactItem(
                text: "\(components.platform)/\(components.track)",
                helpText: platformAndTrackDescription(
                    platform: components.platform,
                    track: components.track,
                    separator: ", ",
                    bundle: bundle
                )
            )
        }

        let platform = cleaned(platform)
        let track = cleaned(track)
        if let platform, let track {
            return CompactItem(
                text: "\(platform)/\(track)",
                helpText: platformAndTrackDescription(
                    platform: platform,
                    track: track,
                    separator: ", ",
                    bundle: bundle
                )
            )
        }
        if let platform {
            return CompactItem(
                text: platform,
                helpText: localized(platformLocalizationKey, platform, bundle: bundle)
            )
        }
        if let track {
            return CompactItem(
                text: track,
                helpText: localized("Track %@", track, bundle: bundle)
            )
        }
        return nil
    }

    private static func cleaned(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty
        else { return nil }
        return value
    }

    private static func localized(
        _ key: String,
        _ value: String,
        bundle: Bundle
    ) -> String {
        let format = bundle.localizedString(forKey: key, value: key, table: nil)
        return String(
            format: format,
            locale: AppLocalization.locale(for: bundle),
            arguments: [value]
        )
    }

    private static func connectionPlatformDescription(
        _ value: String,
        transportMode: IDOSTransportMode?
    ) -> String {
        guard transportMode == .train, platformTrackComponents(value) != nil else {
            return AppLocalization.string("Platform %@", value)
        }
        return platformTrackDescription(value)
    }

    private static func platformTrackComponents(
        _ value: String
    ) -> (platform: String, track: String)? {
        let parts = value.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 2 else { return nil }

        let platform = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
        let track = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
        guard !platform.isEmpty, !track.isEmpty else { return nil }
        return (platform, track)
    }

    /// Localizes known Czech or English IDOS punctuality states and live minute counts while
    /// preserving other messages.
    static func delay(_ value: String?, bundle: Bundle = .main) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }

        if let minutes = currentDelayMinutes(from: value) {
            return AppLocalization.plural(
                "Current delay of %lld minutes",
                count: minutes,
                bundle: bundle
            )
        }

        let knownStates: [(key: String, sourceVariants: [String])] = [
            ("Currently no delay", ["Currently no delay", "Aktuálně bez zpoždění"]),
            ("Departure tends to be on time", ["Departure tends to be on time", "Odjezd bývá včas"]),
            ("Arrival tends to be on time", ["Arrival tends to be on time", "Příjezd bývá včas"]),
            ("Departure tends to be delayed", ["Departure tends to be delayed", "Odjezd bývá zpožděn"]),
            ("Arrival tends to be delayed", ["Arrival tends to be delayed", "Příjezd bývá zpožděn"]),
        ]
        if let state = knownStates.first(where: { state in
            state.sourceVariants.contains {
                value.compare($0, options: .caseInsensitive) == .orderedSame
            }
        }) {
            return bundle.localizedString(forKey: state.key, value: state.key, table: nil)
        }
        return value
    }

    /// Reads the equivalent English and Czech live-delay sentences emitted by IDOS.
    private static func currentDelayMinutes(from value: String) -> Int? {
        let fullRange = NSRange(value.startIndex..<value.endIndex, in: value)

        for expression in currentDelayExpressions {
            guard let match = expression.firstMatch(in: value, range: fullRange),
               match.range == fullRange,
               let numberRange = Range(match.range(at: 1), in: value),
               let minutes = Int(value[numberRange])
            else {
                continue
            }
            return minutes
        }
        return nil
    }
}

/// Preserves note text while turning system-recognized web addresses and telephone numbers into links.
struct NoteText: View {
    let value: String

    init(_ value: String) {
        self.value = value
    }

    var body: some View {
        Text(Self.linkedContent(value))
    }

    /// Builds testable attributed content without interpreting timetable dates as phone numbers.
    static func linkedContent(_ value: String) -> AttributedString {
        guard let detector = try? NSDataDetector(
            types: NSTextCheckingResult.CheckingType.link.rawValue
                | NSTextCheckingResult.CheckingType.phoneNumber.rawValue
        ) else {
            return AttributedString(value)
        }

        let matches = detector.matches(
            in: value,
            range: NSRange(value.startIndex..., in: value)
        )
        guard !matches.isEmpty else { return AttributedString(value) }

        var result = AttributedString()
        var currentIndex = value.startIndex
        for match in matches {
            let destination = match.url ?? match.phoneNumber.flatMap(telephoneURL)
            guard let destination,
                  let range = Range(match.range, in: value),
                  range.lowerBound >= currentIndex
            else {
                continue
            }

            result += AttributedString(value[currentIndex..<range.lowerBound])
            var linkedText = AttributedString(value[range])
            linkedText.link = destination
            result += linkedText
            currentIndex = range.upperBound
        }
        result += AttributedString(value[currentIndex...])
        return result
    }

    private static func telephoneURL(for phoneNumber: String) -> URL? {
        let normalized = phoneNumber.enumerated().compactMap { index, character -> Character? in
            if character.isNumber || (character == "+" && index == 0) {
                return character
            }
            return nil
        }
        guard !normalized.isEmpty else { return nil }
        return URL(string: "tel:\(String(normalized))")
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
