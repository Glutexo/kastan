import Foundation
import Kastan

/// A language supported by Kaštan's human-readable command-line output.
enum AppLanguage: String, CaseIterable {
    case english = "en"
    case czech = "cs"

    /// Resolves a command-line or locale identifier, including regional variants such as `cs-CZ`.
    init?(identifier: String) {
        let normalized = identifier
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "_", with: "-")
            .lowercased()
        let languageCode = normalized
            .split(separator: ".", maxSplits: 1)
            .first?
            .split(separator: "-", maxSplits: 1)
            .first

        switch languageCode {
        case "en":
            self = .english
        case "cs", "cz":
            self = .czech
        default:
            return nil
        }
    }

    /// Selects the first supported system language and falls back to English.
    static func preferred(
        languageIdentifiers: [String],
        environment: [String: String]
    ) -> AppLanguage {
        let environmentIdentifiers = ["LC_ALL", "LC_MESSAGES", "LANGUAGE", "LANG"]
            .compactMap { environment[$0] }
            .flatMap { $0.split(separator: ":").map(String.init) }

        return (languageIdentifiers + environmentIdentifiers)
            .lazy
            .compactMap(AppLanguage.init(identifier:))
            .first ?? .english
    }
}

/// Typed keys keep product copy centralized in the localized resource files.
enum LocalizationKey: String, CaseIterable {
    case appDescription = "app.description"
    case appHelpHint = "app.helpHint"
    case help = "help"
    case unknownCommand = "command.unknown"
    case fallbackError = "error.fallback"
    case errorLabel = "error.label"
    case invalidLanguage = "error.invalidLanguage"
    case missingLanguage = "error.missingLanguage"
    case invalidOutputFormat = "error.invalidOutputFormat"
    case invalidNonNegativeInteger = "error.invalidNonNegativeInteger"
    case conflictingOptions = "error.conflictingOptions"
    case aliasTimetableMismatch = "error.aliasTimetableMismatch"
    case conflictingAliasTimetables = "error.conflictingAliasTimetables"
    case calendarImportUnavailable = "error.calendarImportUnavailable"
    case unknownOption = "error.unknownOption"
    case unsupportedOutputFormat = "error.unsupportedOutputFormat"
    case usageSuggest = "usage.suggest"
    case usageStations = "usage.stations"
    case usageConnections = "usage.connections"
    case usageDepartures = "usage.departures"
    case usageAliases = "usage.aliases"
    case usageAliasesAdd = "usage.aliasesAdd"
    case usageAliasesRemove = "usage.aliasesRemove"
    case idosNoConnections = "error.idosNoConnections"
    case idosInvalidResponse = "error.idosInvalidResponse"
    case idosInvalidURL = "error.idosInvalidURL"
    case idosInvalidJSONP = "error.idosInvalidJSONP"
    case idosInvalidTimetable = "error.idosInvalidTimetable"
    case networkUnavailable = "error.networkUnavailable"
    case networkUnavailableWithDetail = "error.networkUnavailableWithDetail"
    case calendarUnavailable = "error.calendarUnavailable"
    case aliasNotFound = "error.aliasNotFound"
    case invalidAliasName = "error.invalidAliasName"
    case invalidAliasStation = "error.invalidAliasStation"
    case noSuggestedPlaces = "output.noSuggestedPlaces"
    case suggestedPlaces = "output.suggestedPlaces"
    case noStations = "output.noStations"
    case stations = "output.stations"
    case connections = "output.connections"
    case noConnections = "output.noConnections"
    case arrivals = "output.arrivals"
    case departures = "output.departures"
    case noArrivals = "output.noArrivals"
    case noDepartures = "output.noDepartures"
    case idosNoArrivals = "output.idosNoArrivals"
    case idosNoDepartures = "output.idosNoDepartures"
    case timetables = "output.timetables"
    case customTimetableHint = "output.customTimetableHint"
    case noStopAliases = "output.noStopAliases"
    case stopAliases = "output.stopAliases"
    case aliasDatabase = "output.aliasDatabase"
    case aliasDatabaseText = "output.aliasDatabaseText"
    case aliasMutation = "output.aliasMutation"
    case stopAliasMutation = "output.stopAliasMutation"
    case calendarOpened = "output.calendarOpened"
    case calendarImport = "output.calendarImport"
    case direct = "output.direct"
    case shortest = "output.shortest"
    case added = "output.added"
    case updated = "output.updated"
    case removed = "output.removed"
    case ambiguousStation = "error.ambiguousStation"
    case ambiguousPlace = "error.ambiguousPlace"
    case chooseOne = "error.chooseOne"
    case timetable = "label.timetable"
    case place = "label.place"
    case details = "label.details"
    case identifier = "label.identifier"
    case from = "label.from"
    case to = "label.to"
    case via = "label.via"
    case duration = "label.duration"
    case line = "label.line"
    case fromTariffZone = "label.fromTariffZone"
    case fromPlatform = "label.fromPlatform"
    case departure = "label.departure"
    case toTariffZone = "label.toTariffZone"
    case toPlatform = "label.toPlatform"
    case arrival = "label.arrival"
    case carrier = "label.carrier"
    case delay = "label.delay"
    case station = "label.station"
    case time = "label.time"
    case destination = "label.destination"
    case tariffZone = "label.tariffZone"
    case platform = "label.platform"
    case slug = "label.slug"
    case name = "label.name"
    case alias = "label.alias"
    case database = "label.database"
    case connection = "label.connection"
    case file = "label.file"
    case viaInline = "inline.via"
    case tariffZoneInline = "inline.tariffZone"
    case platformInline = "inline.platform"
    case timetableAll = "timetable.all"
    case timetableTrainsBusesMHD = "timetable.trainsBusesMHD"
    case timetableTrains = "timetable.trains"
    case timetableBuses = "timetable.buses"
    case timetableTrainsBuses = "timetable.trainsBuses"
    case timetablePraguePID = "timetable.praguePID"
    case timetableMHD = "timetable.mhd"
}

/// Provides localized product text without changing command names, option names, or JSON keys.
struct Localization {
    let language: AppLanguage

    private let bundle: Bundle

    init(language: AppLanguage) {
        self.language = language

        if let path = Bundle.module.path(forResource: language.rawValue, ofType: "lproj"),
           let localizedBundle = Bundle(path: path)
        {
            bundle = localizedBundle
        } else {
            bundle = Bundle.module
        }
    }

    /// Looks up a localized template and replaces ordered `{0}` placeholders.
    func text(_ key: LocalizationKey, _ arguments: String...) -> String {
        let template = bundle.localizedString(forKey: key.rawValue, value: key.rawValue, table: nil)
        var result = ""
        var cursor = template.startIndex

        while let openingBrace = template[cursor...].firstIndex(of: "{") {
            result += template[cursor..<openingBrace]
            guard let closingBrace = template[openingBrace...].firstIndex(of: "}") else {
                result += template[openingBrace...]
                return result
            }

            let numberStart = template.index(after: openingBrace)
            let placeholder = template[numberStart..<closingBrace]
            if let index = Int(placeholder), arguments.indices.contains(index) {
                result += arguments[index]
            } else {
                result += template[openingBrace...closingBrace]
            }
            cursor = template.index(after: closingBrace)
        }

        result += template[cursor...]
        return result
    }

    /// Localizes known timetable names for human-readable formats while leaving encoded data unchanged.
    func timetableName(_ timetable: IDOSTimetable) -> String {
        switch timetable.slug {
        case "vlakyautobusymhdvse":
            return text(.timetableAll)
        case "vlakyautobusymhd":
            return text(.timetableTrainsBusesMHD)
        case "vlaky":
            return text(.timetableTrains)
        case "autobusy":
            return text(.timetableBuses)
        case "vlakyautobusy":
            return text(.timetableTrainsBuses)
        case "pid":
            return text(.timetablePraguePID)
        default:
            let prefix = "Urban Public Transport "
            if timetable.displayName.hasPrefix(prefix) {
                return text(.timetableMHD, String(timetable.displayName.dropFirst(prefix.count)))
            }
            return timetable.displayName
        }
    }
}
