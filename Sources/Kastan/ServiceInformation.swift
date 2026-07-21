import Foundation

/// Preserves one IDOS service-information line together with the product meaning recognized in its text.
public struct IDOSServiceInformation: Equatable, Sendable {
    /// Complete text supplied by IDOS.
    public let text: String

    /// Passenger-facing meaning recognized without altering the original text.
    public let category: Category

    /// Classifies the original IDOS text without replacing or translating it.
    ///
    /// `fallbackCategory` is used only when no more specific meaning is recognized. A caller that has parsed
    /// an otherwise implicit operating rule can therefore supply `.operatingCalendar` while retaining the
    /// normal priority of passenger services, restrictions, and other categories.
    public init(text: String, fallbackCategory: Category = .general) {
        self.text = text
        category = Classifier(text).category(fallback: fallbackCategory)
    }

    /// Provides the visual marker shared by Kaštan's human-readable interfaces.
    public var symbol: String {
        category.symbol
    }

    /// Adds the shared semantic symbol while retaining the complete IDOS text.
    public var displayText: String {
        "\(symbol) \(text)"
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

public extension IDOSServiceDetail {
    /// Exposes every raw information line as a classified product model in the original IDOS order.
    var serviceInformation: [IDOSServiceInformation] {
        information.map { IDOSServiceInformation(text: $0) }
    }
}

/// Contains the ordered language rules that turn unstructured IDOS text into one product category.
private struct Classifier {
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
    func category(
        fallback: IDOSServiceInformation.Category
    ) -> IDOSServiceInformation.Category {
        if contains(anyOf: "nahradni autobusova doprava", "replacement bus", "bus replacement") {
            return .replacementBus
        }
        // Keep carrier legal forms from overriding information whose subject is the applicable fare.
        if (contains("tarif") &&
            contains(anyOf: "prepravni podmink", "plati tarif", "tarif vyhlasen")) ||
            (contains(anyOf: "fare", "tariff") &&
                contains(
                    anyOf: "conditions of carriage", "transport conditions",
                    "fare announced", "tariff announced"
                ))
        {
            return .fareConditions
        }
        if contains("plati take jizdni doklady") ||
            (contains("integrated transport") && matches(#"\btickets?\b"#))
        {
            return .integratedTransportTicket
        }
        if (contains("jizdenk") && contains(anyOf: "zakoup", "predem")) ||
            (matches(#"\btickets?\b"#) &&
                contains(anyOf: "purchase", "bought in advance", "pre-purchased"))
        {
            return .ticketPurchase
        }
        if contains(anyOf: "stornopodmink", "cancellation conditions", "cancellation policy") {
            return .cancellationPolicy
        }
        if (contains("telefonick") && contains("rezervac")) ||
            contains(anyOf: "telephone reservation", "phone reservation")
        {
            return .phoneReservation
        }
        if contains(anyOf: "vnitrostatni preprava", "domestic transport", "domestic carriage") {
            return .domesticTransport
        }

        // Keep place names such as Kolín from turning unrelated fare notes into bicycle services.
        let mentionsBicycle = matches(#"\bjizdn\p{L}*\s+kol\p{L}*\b"#) ||
            contains(anyOf: "bicycle", "bike")
        if contains(anyOf: "neprepravuji", "not carried", "not transported") &&
            contains(
                anyOf: "zavazadl", "kocark", "zvirat", "baggage", "luggage", "stroller", "animal"
            )
        {
            return .carriageRestriction
        }
        if contains(anyOf: "zavazadl", "baggage", "luggage") ||
            (contains(anyOf: "spoluzavazad", "accompanied luggage") && !mentionsBicycle)
        {
            return .baggage
        }
        if contains(
            anyOf: "osoby opile", "podnapile", "autosedack", "intoxicated passenger", "car seat"
        ) {
            return .passengerWarning
        }
        if (contains("oddil") && contains("deluxe")) ||
            (contains("deluxe") && contains("shower"))
        {
            return .deluxeCompartment
        }
        if (contains("luzkov") && contains("vuz")) ||
            contains(anyOf: "sleeping car", "sleeping coach", "sleeper car")
        {
            return .sleepingCar
        }
        if (contains("lehatkov") && contains("vuz")) ||
            contains(anyOf: "couchette car", "couchette coach")
        {
            return .couchetteCar
        }
        if contains(anyOf: "primy vuz", "through coach", "through car") {
            return .throughCoach
        }
        // A named train after a departure station marks where the same service changes designation.
        if (hasPrefix("ze stanice ") && matches(#"\bvlak\b"#)) ||
            (hasPrefix("from station ") && matches(#"\btrain\b"#))
        {
            return .trainDesignationChange
        }
        if (contains("k sezeni i vozy") && contains("1. vozove tridy")) ||
            (contains("seating") && contains(anyOf: "1st class coaches", "first class coaches"))
        {
            return .firstClassSeating
        }
        if (contains("k sezeni pouze") && contains("2. vozove tridy")) ||
            (contains("seating") && contains(anyOf: "2nd class only", "second class only"))
        {
            return .secondClassOnly
        }
        if (contains("samoobsluzn") && contains("odbavovani cestujicich")) ||
            (contains("self-service") &&
                contains(anyOf: "passenger check-in", "passenger handling"))
        {
            return .selfServiceCheckIn
        }
        if contains(
            anyOf: "restauracni vuz", "bistrovuz", "restaurant car", "dining car", "bistro car"
        ) {
            return .diningCar
        }
        if contains(anyOf: "obcerstveni", "refreshment", "snack service") {
            return .refreshment
        }
        if contains(anyOf: "veskere informace", "all information") &&
            contains(anyOf: "www.", "http")
        {
            return .webInformation
        }
        if contains(anyOf: "palubni portal", "onboard portal", "on-board portal") {
            return .onboardPortal
        }
        if contains(anyOf: "wi-fi", "wifi", "wireless internet") ||
            (contains("bezdratov") && contains("internet"))
        {
            return .wiFi
        }
        if contains(anyOf: "230 v", "power socket", "power outlet", "electrical socket") {
            return .powerSocket
        }
        if contains(anyOf: "tichy oddil", "quiet compartment", "quiet coach") {
            return .quietCompartment
        }
        if contains(anyOf: "detske kino", "children's cinema", "children cinema", "kids cinema") {
            return .childrenCinema
        }
        if contains(
            anyOf: "cestujici s detmi", "passengers with children", "family compartment", "family coach"
        ) {
            return .familyCompartment
        }
        if (contains("damsk") && contains("oddil")) ||
            (contains("samostatne cestujici") && contains("zen")) ||
            (contains("women") &&
                contains(anyOf: "compartment", "coach", "travelling alone", "traveling alone")) ||
            (contains("ladies") && contains(anyOf: "compartment", "coach"))
        {
            return .womenCompartment
        }
        if mentionsBicycle &&
            contains(anyOf: "vyloucen", "excluded", "not permitted", "not allowed", "prohibited")
        {
            return .bicycleUnavailable
        }
        if mentionsBicycle {
            return .bicycle
        }
        if contains(anyOf: "cestujicich na voziku", "wheelchair") {
            return .wheelchair
        }
        if contains(anyOf: "mistenk", "seat reservation", "place reservation", "places reservation") ||
            (contains("rezervac") && contains("mist"))
        {
            return .seatReservation
        }
        if (contains("neceka") && contains("pripoj")) ||
            (contains("zmeskan") && contains("navazn") && contains("spoj")) ||
            contains(
                anyOf: "does not wait for connection", "doesn't wait for connection",
                "will not wait for connection", "missed connection"
            )
        {
            return .connectionWait
        }
        if contains(
            anyOf: "komercni riziko", "nabidkoveho rizeni", "commercial risk", "competitive tender"
        ) {
            return .commercialOperation
        }
        if contains(anyOf: "pohranicni prechodovy bod", "border crossing", "border point") {
            return .borderCrossing
        }
        if contains(
            anyOf: "traffic restriction", "planned restriction", "planovane omezeni",
            "omezeni provozu", "vyluk"
        ) {
            return .trafficRestriction
        }
        if matches(#"\b(?:jede|nejede|runs?|does\s+not\s+run|valid\s+from|plati\s+od)\b"#) ||
            fallback == .operatingCalendar
        {
            return .operatingCalendar
        }
        if hasCarrierContactShape {
            return .carrier
        }
        if hasPrefix(anyOf: "linka ", "line ") || hasRouteShape {
            return .route
        }
        if contains(
            anyOf: "carrier:", "dopravce:", "a.s.", "a. s.", "s.r.o.", "s. r. o.", "k.s.", "k. s."
        ) || hasSuffix(anyOf: " gmbh", " ltd", " ltd.")
        {
            return .carrier
        }
        return fallback
    }

    /// Recognizes the IDOS carrier contact layout without maintaining a list of operator names.
    private var hasCarrierContactShape: Bool {
        let fields = normalized
            .split(separator: ";", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard fields.count == 2 || fields.count == 3 else {
            return false
        }

        let name = fields[0]
        let address = fields[1]
        guard name.contains(where: \.isLetter), address.contains(where: \.isLetter) else {
            return false
        }
        if fields.count == 2 {
            return address.contains(where: \.isNumber)
        }
        return fields[2].filter(\.isNumber).count >= 6
    }

    /// Recognizes an IDOS itinerary without treating date ranges or one hyphenated name as a route.
    private var hasRouteShape: Bool {
        original.range(
            of: #"\p{L}\s+[-–—]\s+\p{L}"#,
            options: .regularExpression
        ) != nil || original.range(
            of: #"^\p{Lu}[\p{L}\p{M}]{1,}\s*[-–—]\s*\p{Lu}[\p{L}\p{M}]{1,}$"#,
            options: .regularExpression
        ) != nil || original.range(
            of: #"\p{L}[-–—]\p{L}.*\p{L}[-–—]\p{L}"#,
            options: .regularExpression
        ) != nil
    }

    /// Keeps phrase matching readable while all language variants remain visible at the rule site.
    private func contains(_ phrase: String) -> Bool {
        normalized.contains(phrase)
    }

    /// Matches any language-specific phrase belonging to one semantic rule.
    private func contains(anyOf phrases: String...) -> Bool {
        phrases.contains(where: normalized.contains)
    }

    /// Matches a prefix where IDOS places a stable subject before variable route content.
    private func hasPrefix(_ prefix: String) -> Bool {
        normalized.hasPrefix(prefix)
    }

    /// Matches any known language variant of a stable prefix.
    private func hasPrefix(anyOf prefixes: String...) -> Bool {
        prefixes.contains(where: normalized.hasPrefix)
    }

    /// Matches carrier legal forms that IDOS places at the end of a line.
    private func hasSuffix(anyOf suffixes: String...) -> Bool {
        suffixes.contains(where: normalized.hasSuffix)
    }

    /// Handles word boundaries and route shapes that cannot be expressed safely as substring checks.
    private func matches(_ pattern: String) -> Bool {
        normalized.range(of: pattern, options: .regularExpression) != nil
    }
}
