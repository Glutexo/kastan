import Foundation

/// Preserves one provider service-information line together with its passenger-facing product meaning.
public struct TransitServiceInformation: Codable, Equatable, Sendable {
    /// Complete text supplied by the data source.
    public let text: String

    /// Passenger-facing meaning recognized without altering the original text.
    public let category: Category

    /// Classifies unstructured IDOS text without replacing or translating it.
    ///
    /// `fallbackCategory` is used only when no more specific meaning is recognized. A caller that has parsed
    /// an otherwise implicit operating rule can therefore supply `.operatingCalendar` while retaining the
    /// normal priority of passenger services, restrictions, and other categories.
    public init(text: String, fallbackCategory: Category = .general) {
        self.text = text
        category = Classifier(text).classification(fallback: fallbackCategory).category
    }

    /// Retains the exact category supplied by a structured provider without applying IDOS text rules.
    public init(text: String, category: Category) {
        self.text = text
        self.category = category
    }

    /// Provides the visual marker shared by Kaštan's human-readable interfaces.
    public var symbol: String {
        category.symbol
    }

    /// Adds the shared semantic symbol while retaining the complete IDOS text.
    public var displayText: String {
        "\(symbol) \(text)"
    }

    /// Exposes the concrete text rule that selected the passenger-facing meaning.
    ///
    /// The rule is computed from the retained source text, so encoded results remain compatible while diagnostic
    /// interfaces can explain compound phrase, pattern, and structural matches without exposing only their outcome.
    public var classificationRule: ClassificationRule {
        let classification = Classifier(text).classification(fallback: category)
        return classification.category == category ? classification.rule : .fallback
    }

    /// Describes the successful classifier predicates without replacing the original IDOS wording.
    public indirect enum ClassificationRule: Equatable, Sendable {
        /// The normalized text contains this phrase.
        case contains(String)

        /// The normalized text starts with this phrase.
        case startsWith(String)

        /// The normalized text ends with this phrase.
        case endsWith(String)

        /// The case- and diacritic-insensitive text matches this regular expression.
        case matchesNormalizedPattern(String)

        /// The original text, including its typography, matches this regular expression.
        case matchesOriginalPattern(String)

        /// The text follows IDOS's carrier contact layout of a name, address, and optional phone number.
        case carrierContactStructure

        /// Every nested predicate was required by the selected rule.
        case all([ClassificationRule])

        /// No more specific text rule matched, so the caller-supplied fallback meaning was retained.
        case fallback
    }

    /// Product meanings recognized across the library, CLI, and native app.
    public enum Category: String, CaseIterable, Codable, Equatable, Hashable, Sendable {
        case replacementBus
        case fareConditions
        case integratedTransportTicket
        case ticketPurchase
        case cancellationPolicy
        case phoneReservation
        case domesticTransport
        case carriageRestriction
        case baggage
        case passengerWarning
        case deluxeCompartment
        case sleepingCar
        case couchetteCar
        case throughCoach
        case trainDesignationChange
        case firstClassSeating
        case secondClassOnly
        case selfServiceCheckIn
        case diningCar
        case refreshment
        case webInformation
        case onboardPortal
        case wiFi
        case powerSocket
        case quietCompartment
        case childrenCinema
        case familyCompartment
        case womenCompartment
        case bicycleUnavailable
        case bicycle
        case wheelchair
        case seatReservation
        case connectionWait
        case commercialOperation
        case borderCrossing
        case trafficRestriction
        case operatingCalendar
        case carrier
        case route
        case general

        /// Provides the visual marker shared by Kaštan's human-readable interfaces.
        public var symbol: String {
            switch self {
            case .replacementBus:
                return "🚌"
            case .fareConditions, .ticketPurchase:
                return "🎫"
            case .integratedTransportTicket:
                return "🎟️"
            case .cancellationPolicy:
                return "↩️"
            case .phoneReservation:
                return "📵"
            case .domesticTransport:
                return "✅"
            case .carriageRestriction:
                return "🚫"
            case .baggage:
                return "🧳"
            case .passengerWarning:
                return "⚠️"
            case .deluxeCompartment:
                return "🚿"
            case .sleepingCar:
                return "🛏️"
            case .couchetteCar:
                return "🛌"
            case .throughCoach:
                return "➡️"
            case .trainDesignationChange:
                return "🔄"
            case .firstClassSeating:
                return "1️⃣"
            case .secondClassOnly:
                return "2️⃣"
            case .selfServiceCheckIn:
                return "👁️"
            case .diningCar:
                return "🍽️"
            case .refreshment:
                return "🥤"
            case .webInformation, .onboardPortal:
                return "🌐"
            case .wiFi:
                return "🛜"
            case .powerSocket:
                return "🔌"
            case .quietCompartment:
                return "🤫"
            case .childrenCinema:
                return "📽️"
            case .familyCompartment:
                return "👶🏻"
            case .womenCompartment:
                return "👩🏻"
            case .bicycleUnavailable:
                return "🚳"
            case .bicycle:
                return "🚲"
            case .wheelchair:
                return "♿"
            case .seatReservation:
                return "💺"
            case .connectionWait:
                return "⏱️"
            case .commercialOperation:
                return "💼"
            case .borderCrossing:
                return "🛂"
            case .trafficRestriction:
                return "🚧"
            case .operatingCalendar:
                return "📅"
            case .carrier:
                return "🏢"
            case .route:
                return "🛤️"
            case .general:
                return "ℹ️"
            }
        }
    }
}

/// Contains the ordered language rules that turn unstructured IDOS text into one product category.
private struct Classifier {
    typealias Category = TransitServiceInformation.Category
    typealias Rule = TransitServiceInformation.ClassificationRule

    struct Classification {
        let category: Category
        let rule: Rule
    }

    private let original: String
    private let normalized: String

    /// Prepares stable case- and diacritic-insensitive text while retaining the original route typography.
    init(_ information: String) {
        original = information
        normalized = information
            .folding(
                options: [.diacriticInsensitive, .caseInsensitive],
                locale: Locale(identifier: "en_US_POSIX")
            )
            .lowercased()
    }

    /// Applies specific passenger-facing meanings before broader carrier, route, and fallback categories.
    func classification(fallback: Category) -> Classification {
        if let rule = containsRule(
            anyOf: "nahradni autobusova doprava", "replacement bus", "bus replacement"
        ) {
            return classified(.replacementBus, by: rule)
        }

        // Keep carrier legal forms from overriding information whose subject is the applicable fare.
        if let rule = all(
            containsRule("tarif"),
            containsRule(anyOf: "prepravni podmink", "plati tarif", "tarif vyhlasen")
        ) {
            return classified(.fareConditions, by: rule)
        }
        if let rule = all(
            containsRule(anyOf: "fare", "tariff"),
            containsRule(
                anyOf: "conditions of carriage", "transport conditions",
                "fare announced", "tariff announced"
            )
        ) {
            return classified(.fareConditions, by: rule)
        }
        if let rule = containsRule("plati take jizdni doklady") {
            return classified(.integratedTransportTicket, by: rule)
        }
        if let rule = all(
            containsRule("integrated transport"),
            normalizedPatternRule(#"\btickets?\b"#)
        ) {
            return classified(.integratedTransportTicket, by: rule)
        }
        if let rule = all(
            containsRule("jizdenk"),
            containsRule(anyOf: "zakoup", "predem")
        ) {
            return classified(.ticketPurchase, by: rule)
        }
        if let rule = all(
            normalizedPatternRule(#"\btickets?\b"#),
            containsRule(anyOf: "purchase", "bought in advance", "pre-purchased")
        ) {
            return classified(.ticketPurchase, by: rule)
        }
        if let rule = containsRule(
            anyOf: "stornopodmink", "cancellation conditions", "cancellation policy"
        ) {
            return classified(.cancellationPolicy, by: rule)
        }
        if let rule = all(containsRule("telefonick"), containsRule("rezervac")) {
            return classified(.phoneReservation, by: rule)
        }
        if let rule = containsRule(anyOf: "telephone reservation", "phone reservation") {
            return classified(.phoneReservation, by: rule)
        }
        if let rule = containsRule(
            anyOf: "vnitrostatni preprava", "domestic transport", "domestic carriage"
        ) {
            return classified(.domesticTransport, by: rule)
        }

        // Keep place names such as Kolín from turning unrelated fare notes into bicycle services.
        let bicycleRule = first(
            normalizedPatternRule(#"\bjizdn\p{L}*\s+kol\p{L}*\b"#),
            containsRule(
                anyOf: "bicycle", "bike",
                "preprava spoluzavazadel (do vycerpani kapacity)",
                "carriage of registered luggage (until full capacity)"
            )
        )
        if let rule = all(
            containsRule(anyOf: "neprepravuji", "not carried", "not transported"),
            containsRule(
                anyOf: "zavazadl", "kocark", "zvirat", "baggage", "luggage", "stroller", "animal"
            )
        ) {
            return classified(.carriageRestriction, by: rule)
        }
        // Bicycle facilities use "registered luggage" wording in IDOS, so let the more
        // specific bicycle rules below retain that passenger-facing meaning.
        if bicycleRule == nil,
           let rule = containsRule(anyOf: "zavazadl", "baggage", "luggage")
        {
            return classified(.baggage, by: rule)
        }
        if bicycleRule == nil,
           let rule = containsRule(anyOf: "spoluzavazad", "accompanied luggage")
        {
            return classified(.baggage, by: rule)
        }
        if let rule = containsRule(
            anyOf: "osoby opile", "podnapile", "autosedack", "intoxicated passenger", "car seat"
        ) {
            return classified(.passengerWarning, by: rule)
        }
        if let rule = first(
            all(containsRule("oddil"), containsRule("deluxe")),
            all(containsRule("deluxe"), containsRule("shower"))
        ) {
            return classified(.deluxeCompartment, by: rule)
        }
        if let rule = first(
            all(containsRule("luzkov"), containsRule("vuz")),
            containsRule(anyOf: "sleeping car", "sleeping coach", "sleeper car")
        ) {
            return classified(.sleepingCar, by: rule)
        }
        if let rule = first(
            all(containsRule("lehatkov"), containsRule("vuz")),
            containsRule(anyOf: "couchette car", "couchette coach")
        ) {
            return classified(.couchetteCar, by: rule)
        }
        if let rule = containsRule(anyOf: "primy vuz", "through coach", "through car") {
            return classified(.throughCoach, by: rule)
        }

        // A named train after a departure station marks where the same service changes designation.
        if let rule = first(
            all(startsWithRule("ze stanice "), normalizedPatternRule(#"\bvlak\b"#)),
            all(startsWithRule("from station "), normalizedPatternRule(#"\btrain\b"#))
        ) {
            return classified(.trainDesignationChange, by: rule)
        }

        // Both-class summaries and explicit first-class seating notes describe the same availability.
        if let rule = first(
            all(containsRule("k sezeni i vozy"), containsRule("1. vozove tridy")),
            containsRule(anyOf: "vozy 1. a 2. tridy", "vozy 1. a 2. vozove tridy"),
            containsRule(
                anyOf: "train also consists of 1st class coaches",
                "train also consists of first class coaches"
            ),
            all(
                containsRule("seating"),
                containsRule(anyOf: "1st class coaches", "first class coaches")
            ),
            containsRule(anyOf: "1st and 2nd class coaches", "first and second class coaches")
        ) {
            return classified(.firstClassSeating, by: rule)
        }
        if let rule = first(
            all(containsRule("k sezeni pouze"), containsRule("2. vozove tridy")),
            all(
                containsRule("seating"),
                containsRule(anyOf: "2nd class only", "second class only")
            )
        ) {
            return classified(.secondClassOnly, by: rule)
        }
        if let rule = first(
            all(containsRule("samoobsluzn"), containsRule("odbavovani cestujicich")),
            all(
                containsRule("self-service"),
                containsRule(anyOf: "passenger check-in", "passenger handling")
            )
        ) {
            return classified(.selfServiceCheckIn, by: rule)
        }
        if let rule = containsRule(
            anyOf: "restauracni vuz", "bistrovuz", "restaurant car", "dining car", "bistro car"
        ) {
            return classified(.diningCar, by: rule)
        }
        if let rule = containsRule(anyOf: "obcerstveni", "refreshment", "snack service", "snack-bar") {
            return classified(.refreshment, by: rule)
        }
        if let rule = all(
            containsRule(anyOf: "veskere informace", "all information"),
            containsRule(anyOf: "www.", "http")
        ) {
            return classified(.webInformation, by: rule)
        }
        if let rule = containsRule(anyOf: "palubni portal", "onboard portal", "on-board portal") {
            return classified(.onboardPortal, by: rule)
        }
        if let rule = first(
            containsRule(anyOf: "wi-fi", "wifi", "wireless internet"),
            all(containsRule("bezdratov"), containsRule("internet"))
        ) {
            return classified(.wiFi, by: rule)
        }
        if let rule = containsRule(anyOf: "230 v", "power socket", "power outlet", "electrical socket") {
            return classified(.powerSocket, by: rule)
        }
        if let rule = containsRule(anyOf: "tichy oddil", "quiet compartment", "quiet coach") {
            return classified(.quietCompartment, by: rule)
        }
        if let rule = containsRule(
            anyOf: "detske kino", "children's cinema", "children cinema", "kids cinema",
            "children's theater", "children theater"
        ) {
            return classified(.childrenCinema, by: rule)
        }
        if let rule = containsRule(
            anyOf: "cestujici s detmi", "passengers with children", "family compartment", "family coach"
        ) {
            return classified(.familyCompartment, by: rule)
        }
        if let rule = first(
            all(containsRule("damsk"), containsRule("oddil")),
            all(containsRule("samostatne cestujici"), containsRule("zen")),
            all(
                containsRule("women"),
                containsRule(anyOf: "compartment", "coach", "travelling alone", "traveling alone")
            ),
            all(containsRule("ladies"), containsRule(anyOf: "compartment", "coach"))
        ) {
            return classified(.womenCompartment, by: rule)
        }
        if let rule = all(
            bicycleRule,
            containsRule(anyOf: "vyloucen", "excluded", "not permitted", "not allowed", "prohibited")
        ) {
            return classified(.bicycleUnavailable, by: rule)
        }
        if let bicycleRule {
            return classified(.bicycle, by: bicycleRule)
        }

        // Bus timetables describe accessible and low-floor vehicles without necessarily mentioning a wheelchair.
        if let rule = first(
            containsRule(
                anyOf: "cestujicich na voziku", "bezbarierovy spoj",
                "spoj s bezbarierove pristupnym vozidlem", "wheelchair"
            ),
            all(containsRule("nizkopodlazn"), containsRule("vozidl")),
            all(
                containsRule(anyOf: "low-floor", "low floor"),
                containsRule("vehicle")
            )
        ) {
            return classified(.wheelchair, by: rule)
        }
        if let rule = first(
            containsRule(
                anyOf: "mistenk", "seat reservation", "place reservation", "places reservation",
                "compulsory reservation", "reservations possible in indicated coaches"
            ),
            all(containsRule("rezervac"), containsRule("mist"))
        ) {
            return classified(.seatReservation, by: rule)
        }
        if let rule = first(
            all(containsRule("neceka"), containsRule("pripoj")),
            all(containsRule("zmeskan"), containsRule("navazn"), containsRule("spoj")),
            containsRule(
                anyOf: "does not wait for connection", "doesn't wait for connection",
                "will not wait for connection", "missed connection"
            )
        ) {
            return classified(.connectionWait, by: rule)
        }
        if let rule = containsRule(
            anyOf: "komercni riziko", "nabidkoveho rizeni", "commercial risk", "competitive tender"
        ) {
            return classified(.commercialOperation, by: rule)
        }
        if let rule = containsRule(anyOf: "pohranicni prechodovy bod", "border crossing", "border point") {
            return classified(.borderCrossing, by: rule)
        }
        if let rule = containsRule(
            anyOf: "traffic restriction", "planned restriction", "planovane omezeni",
            "omezeni provozu", "vyluk"
        ) {
            return classified(.trafficRestriction, by: rule)
        }
        if let rule = skipsStopsRule {
            return classified(.route, by: rule)
        }
        if let rule = normalizedPatternRule(
            #"\b(?:jede|nejede|runs?|does\s+not\s+run|valid\s+from|plati\s+od)\b"#
        ) {
            return classified(.operatingCalendar, by: rule)
        }
        if fallback == .operatingCalendar {
            return classified(.operatingCalendar, by: .fallback)
        }
        if let rule = carrierContactRule {
            return classified(.carrier, by: rule)
        }
        if let rule = startsWithRule(anyOf: "linka ", "line ") {
            return classified(.route, by: rule)
        }
        if let rule = routeShapeRule {
            return classified(.route, by: rule)
        }
        if let rule = containsRule(
            anyOf: "carrier:", "dopravce:", "a.s.", "a. s.", "s.r.o.", "s. r. o.", "k.s.", "k. s."
        ) {
            return classified(.carrier, by: rule)
        }
        if let rule = endsWithRule(anyOf: " gmbh", " ltd", " ltd.") {
            return classified(.carrier, by: rule)
        }
        return classified(fallback, by: .fallback)
    }

    /// Recognizes the IDOS carrier contact layout without maintaining a list of operator names.
    private var carrierContactRule: Rule? {
        let fields = normalized
            .split(separator: ";", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard fields.count == 2 || fields.count == 3 else {
            return nil
        }

        let name = fields[0]
        let address = fields[1]
        guard name.contains(where: \.isLetter), address.contains(where: \.isLetter) else {
            return nil
        }
        if fields.count == 2 {
            return address.contains(where: \.isNumber) ? .carrierContactStructure : nil
        }
        return fields[2].filter(\.isNumber).count >= 6 ? .carrierContactStructure : nil
    }

    /// Recognizes an IDOS itinerary without treating date ranges or one hyphenated name as a route.
    private var routeShapeRule: Rule? {
        first(
            originalPatternRule(#"\p{L}\s+[-–—]\s+\p{L}"#),
            originalPatternRule(#"^\p{Lu}[\p{L}\p{M}]{1,}\s*[-–—]\s*\p{Lu}[\p{L}\p{M}]{1,}$"#),
            originalPatternRule(#"\p{L}[-–—]\p{L}.*\p{L}[-–—]\p{L}"#)
        )
    }

    /// Recognizes route instructions that list stops omitted by this particular service.
    private var skipsStopsRule: Rule? {
        first(
            normalizedPatternRule(#"\bvynech\p{L}*\s+zastavk\p{L}*\b"#),
            normalizedPatternRule(#"\b(?:skips?|omits?)\s+(?:the\s+)?(?:following\s+)?stops?\b"#),
            containsRule(
                anyOf: "does not stop at", "doesn't stop at", "will not stop at",
                "does not call at", "doesn't call at", "will not call at"
            )
        )
    }

    private func classified(_ category: Category, by rule: Rule) -> Classification {
        Classification(category: category, rule: rule)
    }

    /// Retains the exact normalized phrase that made one language variant match.
    private func containsRule(_ phrase: String) -> Rule? {
        normalized.contains(phrase) ? .contains(phrase) : nil
    }

    private func containsRule(anyOf phrases: String...) -> Rule? {
        guard let phrase = phrases.first(where: normalized.contains) else { return nil }
        return .contains(phrase)
    }

    private func startsWithRule(_ prefix: String) -> Rule? {
        normalized.hasPrefix(prefix) ? .startsWith(prefix) : nil
    }

    private func startsWithRule(anyOf prefixes: String...) -> Rule? {
        guard let prefix = prefixes.first(where: normalized.hasPrefix) else { return nil }
        return .startsWith(prefix)
    }

    private func endsWithRule(anyOf suffixes: String...) -> Rule? {
        guard let suffix = suffixes.first(where: normalized.hasSuffix) else { return nil }
        return .endsWith(suffix)
    }

    private func normalizedPatternRule(_ pattern: String) -> Rule? {
        normalized.range(of: pattern, options: .regularExpression) == nil
            ? nil
            : .matchesNormalizedPattern(pattern)
    }

    private func originalPatternRule(_ pattern: String) -> Rule? {
        original.range(of: pattern, options: .regularExpression) == nil
            ? nil
            : .matchesOriginalPattern(pattern)
    }

    /// Combines predicates only when every part of one classifier branch matched.
    private func all(_ rules: Rule?...) -> Rule? {
        guard rules.allSatisfy({ $0 != nil }) else { return nil }
        let matched = rules.compactMap(\.self)
        return matched.count == 1 ? matched[0] : .all(matched)
    }

    /// Selects the same first successful alternative as the ordered classifier branch.
    private func first(_ rules: Rule?...) -> Rule? {
        rules.compactMap(\.self).first
    }
}
