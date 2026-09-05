import Foundation

/// A stable namespace for values owned by one transit-data provider.
public struct TransitDataSourceID: RawRepresentable, Codable, Equatable, Hashable, Sendable,
    ExpressibleByStringLiteral, CustomStringConvertible
{
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(_ rawValue: String) {
        self.init(rawValue: rawValue)
    }

    public init(stringLiteral value: String) {
        self.init(value)
    }

    public static let idos: Self = "idos"

    /// Kaštan's deterministic provider for explicit testing and interface previews.
    public static let mock: Self = "mock"

    public var description: String {
        rawValue
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.init(try container.decode(String.self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

/// A provider-neutral Gregorian civil date used to constrain a transit search.
public struct TransitDate: Codable, Equatable, Hashable, Sendable {
    public let year: Int
    public let month: Int
    public let day: Int

    public init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    /// Reads the civil components of an absolute date in the caller-selected calendar.
    public init(_ date: Date, calendar: Calendar) {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        self.init(
            year: components.year ?? 1,
            month: components.month ?? 1,
            day: components.day ?? 1
        )
    }

    /// Builds an absolute date without assigning the provider's civil day to the device time zone implicitly.
    public func date(in calendar: Calendar, at time: TransitTime? = nil) -> Date? {
        calendar.date(from: DateComponents(
            timeZone: calendar.timeZone,
            year: year,
            month: month,
            day: day,
            hour: time?.hour,
            minute: time?.minute,
            second: time == nil ? nil : 0
        ))
    }
}

/// A provider-neutral local wall-clock time, expressed to the minute, used to constrain a transit search.
public struct TransitTime: Codable, Equatable, Sendable {
    public let hour: Int
    public let minute: Int

    public init(hour: Int, minute: Int) {
        self.hour = hour
        self.minute = minute
    }
}

/// Product capabilities that an interface can offer only when its selected source implements them.
public enum TransitDataSourceCapability: String, CaseIterable, Codable, Equatable, Hashable, Sendable {
    case timetables
    case placeSuggestions
    case coordinatePlaceSelection
    case stationSearch
    case connections
    case connectionPaging
    case departures
    case departurePaging
    case stationTimetables
    /// Indicates that station-timetable rows can be matched to this provider's departure-board results.
    case stationTimetableDepartureResolution
    case serviceDetails
    case timetableValidity
    case serviceDateLimits
    case connectionCalendarExport
    case connectionPDFExport
    case serviceCalendarExport
    case servicePDFExport
    case connectionEmail
}

/// Groups the detailed connection-search transport modes exactly as journey planners present them.
public enum TransitConnectionTransportModeGroup: String, CaseIterable, Codable, Equatable, Hashable, Sendable {
    /// Train classes and the adjacent general bus, ship, and other choices.
    case trains
    /// Local, long-distance, and international bus choices.
    case buses
    /// Tram, bus, cableway, and trolleybus choices within city transport.
    case cityTransport
}

/// Identifies one detailed means-of-transport choice that a connection search may retain or omit.
///
/// The train group includes the bus, ship, and other categories exposed beside train quality classes by IDOS.
/// Bus and city-transport cases remain distinct even when their visible labels match.
public enum TransitConnectionTransportMode: String, CaseIterable, Codable, Equatable, Hashable, Sendable {
    /// A highest-quality train such as SC or ICE.
    case highestQualityTrain
    /// A higher-quality train such as EC or IC.
    case higherQualityTrain
    /// An interregional train such as R.
    case interregionalTrain
    /// A regional train such as Os or Sp.
    case regionalTrain
    /// The general bus choice presented within the train group.
    case trainBus
    /// The ship choice presented within the train group.
    case trainShip
    /// The other-transport choice presented within the train group.
    case trainOther
    /// A local bus.
    case localBus
    /// A long-distance bus.
    case longDistanceBus
    /// An international bus.
    case internationalBus
    /// A city tram.
    case cityTram
    /// A city bus.
    case cityBus
    /// A city cableway.
    case cityCableway
    /// A city trolleybus.
    case cityTrolleybus

    /// Locates the choice under its stable presentation group.
    public var group: TransitConnectionTransportModeGroup {
        switch self {
        case .highestQualityTrain, .higherQualityTrain, .interregionalTrain, .regionalTrain,
             .trainBus, .trainShip, .trainOther:
            .trains
        case .localBus, .longDistanceBus, .internationalBus:
            .buses
        case .cityTram, .cityBus, .cityCableway, .cityTrolleybus:
            .cityTransport
        }
    }
}

/// Selects whether one detailed transport mode is retained exclusively or omitted from a connection search.
public enum TransitConnectionTransportModeFilterOperation: String, CaseIterable, Codable, Equatable, Hashable, Sendable {
    /// Retains the selected mode as part of the permitted union.
    case only
    /// Removes the selected mode from the permitted catalog.
    case exclude
}

/// Stores one repeatable means-of-transport rule in a provider-neutral connection request.
public struct TransitConnectionTransportModeFilter: Codable, Equatable, Hashable, Sendable {
    /// Whether this rule retains or omits its mode.
    public var operation: TransitConnectionTransportModeFilterOperation
    /// The detailed means of transport affected by this rule.
    public var mode: TransitConnectionTransportMode

    /// Creates one repeatable rule without exposing a provider's form identifiers.
    public init(
        operation: TransitConnectionTransportModeFilterOperation,
        mode: TransitConnectionTransportMode
    ) {
        self.operation = operation
        self.mode = mode
    }
}

/// Identifies one independently selectable connection-search option a provider understands.
///
/// Interfaces use this contract to offer only controls whose values the selected provider can honor. Supporting
/// connection search alone does not imply support for any individual option.
public enum TransitConnectionOption: String, CaseIterable, Codable, Equatable, Hashable, Sendable {
    /// Limits results to journeys that require no transfer.
    case onlyDirect
    /// Adds an ordered intermediate place through which the journey must travel.
    case via
    /// Selects or omits detailed means of transport through repeatable grouped rules.
    case transportModeFilters
    /// Limits how many transfers a journey may contain.
    case maximumTransfers
    /// Requires at least a selected amount of time for each transfer.
    case minimumTransferTime
    /// Limits how long a transfer may take.
    case maximumTransferTime
    /// Limits walking between stops during the journey.
    case maximumWalkingTime
    /// Applies a separate walking limit where urban public transport is available.
    case maximumCityWalkingTime
    /// Allows the journey to begin or end at a nearby stop reached on foot.
    case walkToNearbyStops
    /// Restricts walking transfers to stops that share the same name.
    case sameNameWalkingTransfersOnly
    /// Limits results to connections advertised as wheelchair accessible.
    case wheelchairAccessibleConnectionsOnly
    /// Limits results to connections served by low-floor vehicles.
    case lowFloorConnectionsOnly
    /// Prefers train connections when a bus alternative is also available.
    case preferTrainsOverBuses
    /// Limits train results to connections suitable for wheelchair passengers.
    case trainConnectionsForWheelchairPassengers
    /// Limits train results to connections suitable for passengers with children.
    case trainConnectionsForPassengersWithChildren
    /// Limits train and bus results to connections that carry bicycles.
    case connectionsForPassengersWithBicycles
    /// Prefers routes served more frequently.
    case preferBusyRoutes
    /// Selects whether journeys should use or avoid bed and couchette accommodation.
    case bedOrCouchettePreference
}

/// Selects how a connection search should treat services offering beds or couchettes.
public enum TransitBedOrCouchettePreference: String, CaseIterable, Codable, Equatable, Hashable, Sendable {
    /// Applies no accommodation restriction.
    case noLimitation
    /// Requires the journey to use bed or couchette accommodation.
    case use
    /// Requires the journey not to use bed or couchette accommodation.
    case doNotUse
}

/// Identifies one provider and advertises only the product operations that it can fulfill.
public struct TransitDataSourceDescriptor: Codable, Equatable, Sendable {
    public let id: TransitDataSourceID
    public let displayName: String
    public let capabilities: Set<TransitDataSourceCapability>
    /// Connection-search controls whose values this provider can honor independently.
    public let connectionOptions: Set<TransitConnectionOption>

    public init(
        id: TransitDataSourceID,
        displayName: String,
        capabilities: Set<TransitDataSourceCapability>,
        connectionOptions: Set<TransitConnectionOption> = []
    ) {
        self.id = id
        self.displayName = displayName
        self.capabilities = capabilities
        self.connectionOptions = connectionOptions
    }

    /// Metadata for Kaštan's built-in IDOS web data source.
    public static let idos = Self(
        id: .idos,
        displayName: "IDOS",
        capabilities: Set(TransitDataSourceCapability.allCases),
        connectionOptions: Set(TransitConnectionOption.allCases)
    )

    /// Conservative metadata for an older `IDOSClienting` conformer that has not declared its operations.
    ///
    /// Such a conformer keeps compiling and can opt into its implemented capabilities by supplying `descriptor`.
    public static let legacyIDOSClient = Self(
        id: .idos,
        displayName: "IDOS",
        capabilities: [
            .timetables,
            .placeSuggestions,
            .coordinatePlaceSelection,
            .stationSearch,
            .connections,
            .departures,
            .serviceDetails,
            .connectionCalendarExport,
        ]
    )

    public func supports(_ capability: TransitDataSourceCapability) -> Bool {
        capabilities.contains(capability)
    }

    /// Reports whether an individual connection-search control can be offered for this provider.
    public func supports(_ option: TransitConnectionOption) -> Bool {
        connectionOptions.contains(option)
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case displayName
        case capabilities
        case connectionOptions
    }

    /// Decodes descriptors written before fine-grained connection options as supporting no implicit options.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decode(TransitDataSourceID.self, forKey: .id),
            displayName: try container.decode(String.self, forKey: .displayName),
            capabilities: try container.decode(Set<TransitDataSourceCapability>.self, forKey: .capabilities),
            connectionOptions: try container.decodeIfPresent(
                Set<TransitConnectionOption>.self,
                forKey: .connectionOptions
            ) ?? []
        )
    }

    /// Keeps descriptors with no declared connection options in their historical encoded shape.
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(displayName, forKey: .displayName)
        try container.encode(capabilities, forKey: .capabilities)
        if !connectionOptions.isEmpty {
            try container.encode(connectionOptions, forKey: .connectionOptions)
        }
    }
}

/// Type-erases a provider's private paging state while retaining Swift concurrency safety.
public struct TransitPageContinuation: Sendable {
    private let storage: any Sendable

    public init<Value: Sendable>(_ value: Value) {
        storage = value
    }

    /// Recovers the value only for the provider that knows its concrete continuation type.
    public func value<Value: Sendable>(as type: Value.Type = Value.self) -> Value? {
        storage as? Value
    }
}

/// Provider-neutral failures produced before a concrete data source performs its own request.
public enum TransitDataSourceError: LocalizedError, Equatable, Sendable {
    case unsupported(TransitDataSourceCapability, source: TransitDataSourceDescriptor)
    case invalidTimetable(String, source: TransitDataSourceDescriptor)
    case invalidStationTimetableMunicipality(String, source: TransitDataSourceDescriptor)
    case invalidDataSourceValue(source: TransitDataSourceDescriptor)
    case valueBelongsToDifferentSource(expected: TransitDataSourceID, actual: TransitDataSourceID)
    case valueBelongsToDifferentTimetable(
        expected: String,
        actual: String,
        source: TransitDataSourceID
    )
    case pageBelongsToDifferentSource(expected: TransitDataSourceID, actual: TransitDataSourceID)

    public var errorDescription: String? {
        switch self {
        case .unsupported(let capability, let source):
            return "\(source.displayName) does not support \(capability.productDescription)."
        case .invalidTimetable(let value, let source):
            return "Invalid \(source.displayName) timetable: \(value)."
        case .invalidStationTimetableMunicipality(let value, let source):
            return "Invalid \(source.displayName) station-timetable municipality: \(value)."
        case .invalidDataSourceValue(let source):
            return "Transit value has an invalid \(source.displayName) identifier."
        case .valueBelongsToDifferentSource(let expected, let actual):
            return "Transit value belongs to data source \(actual.rawValue), not \(expected.rawValue)."
        case .valueBelongsToDifferentTimetable(let expected, let actual, let source):
            return "Transit value belongs to timetable \(actual) of \(source.rawValue), not \(expected)."
        case .pageBelongsToDifferentSource(let expected, let actual):
            return "Result page belongs to data source \(actual.rawValue), not \(expected.rawValue)."
        }
    }
}

private extension TransitDataSourceCapability {
    var productDescription: String {
        switch self {
        case .timetables: "timetable catalogs"
        case .placeSuggestions: "place suggestions"
        case .coordinatePlaceSelection: "coordinate-based place selection"
        case .stationSearch: "station search"
        case .connections: "connection search"
        case .connectionPaging: "connection paging"
        case .departures: "station boards"
        case .departurePaging: "station-board paging"
        case .stationTimetables: "station timetables"
        case .stationTimetableDepartureResolution: "station-timetable departure resolution"
        case .serviceDetails: "service details"
        case .timetableValidity: "timetable validity"
        case .serviceDateLimits: "service operating-day calendars"
        case .connectionCalendarExport: "connection calendar export"
        case .connectionPDFExport: "connection PDF export"
        case .serviceCalendarExport: "service calendar export"
        case .servicePDFExport: "service PDF export"
        case .connectionEmail: "connection email delivery"
        }
    }
}

/// Supplies stable identity and a capability contract shared by every data-source facet.
public protocol TransitDataSourceDescribing: Sendable {
    var descriptor: TransitDataSourceDescriptor { get }
    /// Identifies the provider's civil service-day zone when calendar-backed presentation needs an absolute date.
    var serviceTimeZone: TimeZone? { get }
}

public extension TransitDataSourceDescribing {
    /// Leaves the zone unspecified for providers whose contract is expressed entirely through `TransitDate`.
    var serviceTimeZone: TimeZone? { nil }
}

/// Supplies the provider-scoped timetable catalog accepted by all search operations.
public protocol TransitTimetableProviding: TransitDataSourceDescribing {
    var timetables: [TransitTimetable] { get }
    var defaultTimetable: TransitTimetable { get }
    func resolveTimetable(_ value: String?) throws -> TransitTimetable
}

/// Suggests provider-owned places and restricts suggestions to stations when requested.
public protocol TransitPlaceSearching: TransitDataSourceDescribing {
    func suggest(prefix: String, limit: Int, timetable: TransitTimetable) async throws -> [TransitSuggestion]
    func searchStations(prefix: String, limit: Int, timetable: TransitTimetable) async throws -> [TransitSuggestion]
    func coordinatePlaceSelection(
        text: String,
        latitude: Double,
        longitude: Double,
        timetable: TransitTimetable
    ) throws -> TransitPlaceSelection
}

/// Searches connections and optionally extends a result through provider-owned continuation state.
public protocol TransitConnectionSearching: TransitDataSourceDescribing {
    /// Reports whether one advertised connection option is available for the selected timetable.
    func supportsConnectionOption(
        _ option: TransitConnectionOption,
        for timetable: TransitTimetable
    ) -> Bool
    func findConnections(request: TransitConnectionRequest) async throws -> [TransitConnection]
    func findConnectionsPage(request: TransitConnectionRequest) async throws -> TransitConnectionPage
    func findConnectionsPage(
        request: TransitConnectionRequest,
        language: TransitLanguage
    ) async throws -> TransitConnectionPage
    func findConnectionsPage(
        from page: TransitConnectionPage,
        direction: TransitPageDirection
    ) async throws -> TransitConnectionPage
}

/// Searches station boards and optionally extends a result through provider-owned continuation state.
public protocol TransitDepartureBoardProviding: TransitDataSourceDescribing {
    func findDepartures(request: TransitDeparturesRequest) async throws -> [TransitDeparture]
    func findDeparturesPage(request: TransitDeparturesRequest) async throws -> TransitDeparturePage
    func findDeparturesPage(
        request: TransitDeparturesRequest,
        language: TransitLanguage
    ) async throws -> TransitDeparturePage
    func findDeparturesPage(
        from page: TransitDeparturePage,
        direction: TransitPageDirection
    ) async throws -> TransitDeparturePage
}

/// Provides line-oriented station timetables when the selected provider publishes them.
public protocol TransitStationTimetableProviding: TransitDataSourceDescribing {
    func stationTimetableMunicipalities(
        for timetable: TransitTimetable
    ) -> [TransitStationTimetableMunicipality]
    func defaultStationTimetableMunicipality(
        for timetable: TransitTimetable
    ) -> TransitStationTimetableMunicipality?
    func resolveStationTimetableMunicipality(
        _ value: String?,
        timetable: TransitTimetable
    ) throws -> TransitStationTimetableMunicipality?
    func searchStationTimetableLines(
        prefix: String,
        limit: Int,
        timetable: TransitTimetable
    ) async throws -> [TransitSuggestion]
    func searchStationTimetableLines(
        prefix: String,
        limit: Int,
        timetable: TransitTimetable,
        municipality: TransitStationTimetableMunicipality?
    ) async throws -> [TransitSuggestion]
    func searchStationTimetableStops(
        prefix: String,
        line: String,
        limit: Int,
        timetable: TransitTimetable
    ) async throws -> [TransitSuggestion]
    func searchStationTimetableStops(
        prefix: String,
        line: String,
        limit: Int,
        timetable: TransitTimetable,
        municipality: TransitStationTimetableMunicipality?
    ) async throws -> [TransitSuggestion]
    func findStationTimetable(
        request: TransitStationTimetableRequest,
        language: TransitLanguage
    ) async throws -> TransitStationTimetable
}

/// Identifies one provider-rendered station-timetable value without interpreting its display text.
public struct TransitStationTimetableDepartureResolutionRequest: Codable, Equatable, Sendable {
    public let stationTimetable: TransitStationTimetable
    public let scheduleIndex: Int
    public let hourIndex: Int
    public let departureIndex: Int
    /// The civil date selected for the station-timetable search.
    public let serviceDate: TransitDate
    public let wholeWeek: Bool

    public init(
        stationTimetable: TransitStationTimetable,
        scheduleIndex: Int,
        hourIndex: Int,
        departureIndex: Int,
        serviceDate: TransitDate,
        wholeWeek: Bool
    ) {
        self.stationTimetable = stationTimetable
        self.scheduleIndex = scheduleIndex
        self.hourIndex = hourIndex
        self.departureIndex = departureIndex
        self.serviceDate = serviceDate
        self.wholeWeek = wholeWeek
    }
}

/// Carries the concrete station-board result selected by a provider for one timetable value.
public struct TransitStationTimetableDepartureResolution: Sendable {
    public let departure: TransitDeparture
    public let request: TransitDeparturesRequest
    public let page: TransitDeparturePage
    /// The provider-local civil date on which the resolved departure runs.
    public let serviceDate: TransitDate
    /// The provider-local wall-clock time shown by the resolved departure.
    public let serviceTime: TransitTime

    public init(
        departure: TransitDeparture,
        request: TransitDeparturesRequest,
        page: TransitDeparturePage,
        serviceDate: TransitDate,
        serviceTime: TransitTime
    ) {
        self.departure = departure
        self.request = request
        self.page = page
        self.serviceDate = serviceDate
        self.serviceTime = serviceTime
    }
}

/// Lets a provider interpret its own station-timetable values and resolve them to station-board results.
public protocol TransitStationTimetableDepartureResolving: TransitDataSourceDescribing {
    func resolveStationTimetableDeparture(
        request: TransitStationTimetableDepartureResolutionRequest,
        language: TransitLanguage
    ) async throws -> TransitStationTimetableDepartureResolution?
}

/// Resolves complete service routes and provider-published operating intervals.
public protocol TransitServiceDetailProviding: TransitDataSourceDescribing {
    func serviceDetail(id: String, timetable: TransitTimetable) async throws -> TransitServiceDetail
    func serviceDetail(
        id: String,
        timetable: TransitTimetable,
        language: TransitLanguage
    ) async throws -> TransitServiceDetail
    func timetableValidity(
        for timetable: TransitTimetable,
        language: TransitLanguage
    ) async throws -> TransitTimetableValidity
    func serviceDateLimits(
        for service: TransitServiceDetail,
        language: TransitLanguage
    ) async throws -> TransitServiceDateLimits
}

/// Exports connection results in the native formats supported by a provider.
public protocol TransitConnectionExporting: TransitDataSourceDescribing {
    func connectionCalendar(
        for connection: TransitConnection,
        timetable: TransitTimetable
    ) async throws -> String
    func connectionCalendar(
        for connection: TransitConnection,
        timetable: TransitTimetable,
        language: TransitLanguage
    ) async throws -> String
    func connectionPDF(
        for connection: TransitConnection,
        timetable: TransitTimetable,
        language: TransitLanguage
    ) async throws -> Data
}

/// Exports dated service details in the native formats supported by a provider.
public protocol TransitServiceExporting: TransitDataSourceDescribing {
    func serviceCalendar(for service: TransitServiceDetail) async throws -> String
    func serviceCalendar(for service: TransitServiceDetail, language: TransitLanguage) async throws -> String
    func servicePDF(for service: TransitServiceDetail, language: TransitLanguage) async throws -> Data
}

/// Prepares and sends provider-generated connection attachments after explicit user confirmation.
public protocol TransitConnectionEmailSending: TransitDataSourceDescribing {
    func connectionEmailDraft(
        for connection: TransitConnection,
        timetable: TransitTimetable,
        language: TransitLanguage
    ) async throws -> TransitConnectionEmailDraft
    func sendConnectionByEmail(
        _ connection: TransitConnection,
        to recipient: String,
        message: String,
        timetable: TransitTimetable,
        language: TransitLanguage
    ) async throws
}

/// Complete provider contract consumed by Kaštan's provider-neutral composition roots.
///
/// Individual facets keep optional product capabilities explicit. Default implementations fail with
/// `TransitDataSourceError.unsupported`, so a future source can implement only the capabilities it advertises.
/// Every source declares its stable identity and capabilities through an explicit `descriptor` implementation.
public protocol TransitDataSource: TransitTimetableProviding, TransitPlaceSearching,
    TransitConnectionSearching, TransitDepartureBoardProviding, TransitStationTimetableProviding,
    TransitStationTimetableDepartureResolving, TransitServiceDetailProviding,
    TransitConnectionExporting, TransitServiceExporting, TransitConnectionEmailSending
{}

public extension TransitTimetableProviding {
    var timetables: [TransitTimetable] {
        [defaultTimetable]
    }

    var defaultTimetable: TransitTimetable {
        TransitTimetable(
            dataSourceID: descriptor.id,
            identifier: "default",
            displayName: descriptor.displayName
        )
    }

    func resolveTimetable(_ value: String?) throws -> TransitTimetable {
        guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return defaultTimetable
        }

        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if let timetable = timetables.first(where: {
            $0.identifier.caseInsensitiveCompare(normalized) == .orderedSame
        }) {
            return timetable
        }
        if let timetable = timetables.first(where: {
            $0.displayName.caseInsensitiveCompare(normalized) == .orderedSame
        }) {
            return timetable
        }

        throw TransitDataSourceError.invalidTimetable(value, source: descriptor)
    }
}

public extension TransitPlaceSearching {
    func suggest(prefix: String, limit: Int, timetable: TransitTimetable) async throws -> [TransitSuggestion] {
        throw TransitDataSourceError.unsupported(.placeSuggestions, source: descriptor)
    }

    func searchStations(prefix: String, limit: Int, timetable: TransitTimetable) async throws -> [TransitSuggestion] {
        throw TransitDataSourceError.unsupported(.stationSearch, source: descriptor)
    }

    func coordinatePlaceSelection(
        text: String,
        latitude: Double,
        longitude: Double,
        timetable: TransitTimetable
    ) throws -> TransitPlaceSelection {
        throw TransitDataSourceError.unsupported(.coordinatePlaceSelection, source: descriptor)
    }
}

public extension TransitConnectionSearching {
    /// Providers without timetable-specific restrictions inherit their descriptor's advertised support.
    func supportsConnectionOption(
        _ option: TransitConnectionOption,
        for timetable: TransitTimetable
    ) -> Bool {
        descriptor.supports(option)
    }

    func findConnections(request: TransitConnectionRequest) async throws -> [TransitConnection] {
        throw TransitDataSourceError.unsupported(.connections, source: descriptor)
    }

    func findConnectionsPage(request: TransitConnectionRequest) async throws -> TransitConnectionPage {
        TransitConnectionPage(
            connections: try await findConnections(request: request),
            dataSourceID: descriptor.id
        )
    }

    func findConnectionsPage(
        request: TransitConnectionRequest,
        language: TransitLanguage
    ) async throws -> TransitConnectionPage {
        try await findConnectionsPage(request: request)
    }

    func findConnectionsPage(
        from page: TransitConnectionPage,
        direction: TransitPageDirection
    ) async throws -> TransitConnectionPage {
        try validate(page.dataSourceID)
        throw TransitDataSourceError.unsupported(.connectionPaging, source: descriptor)
    }

    private func validate(_ pageSourceID: TransitDataSourceID) throws {
        guard pageSourceID == descriptor.id else {
            throw TransitDataSourceError.pageBelongsToDifferentSource(
                expected: descriptor.id,
                actual: pageSourceID
            )
        }
    }
}

public extension TransitDepartureBoardProviding {
    func findDepartures(request: TransitDeparturesRequest) async throws -> [TransitDeparture] {
        throw TransitDataSourceError.unsupported(.departures, source: descriptor)
    }

    func findDeparturesPage(request: TransitDeparturesRequest) async throws -> TransitDeparturePage {
        let departures = try await findDepartures(request: request)
        return TransitDeparturePage(
            departures: Array(departures.prefix(20)),
            dataSourceID: descriptor.id
        )
    }

    func findDeparturesPage(
        request: TransitDeparturesRequest,
        language: TransitLanguage
    ) async throws -> TransitDeparturePage {
        try await findDeparturesPage(request: request)
    }

    func findDeparturesPage(
        from page: TransitDeparturePage,
        direction: TransitPageDirection
    ) async throws -> TransitDeparturePage {
        guard page.dataSourceID == descriptor.id else {
            throw TransitDataSourceError.pageBelongsToDifferentSource(
                expected: descriptor.id,
                actual: page.dataSourceID
            )
        }
        throw TransitDataSourceError.unsupported(.departurePaging, source: descriptor)
    }
}

public extension TransitStationTimetableProviding {
    func stationTimetableMunicipalities(
        for timetable: TransitTimetable
    ) -> [TransitStationTimetableMunicipality] {
        []
    }

    func defaultStationTimetableMunicipality(
        for timetable: TransitTimetable
    ) -> TransitStationTimetableMunicipality? {
        stationTimetableMunicipalities(for: timetable).first
    }

    func resolveStationTimetableMunicipality(
        _ value: String?,
        timetable: TransitTimetable
    ) throws -> TransitStationTimetableMunicipality? {
        guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        throw TransitDataSourceError.invalidStationTimetableMunicipality(value, source: descriptor)
    }

    func searchStationTimetableLines(
        prefix: String,
        limit: Int,
        timetable: TransitTimetable
    ) async throws -> [TransitSuggestion] {
        throw TransitDataSourceError.unsupported(.stationTimetables, source: descriptor)
    }

    func searchStationTimetableLines(
        prefix: String,
        limit: Int,
        timetable: TransitTimetable,
        municipality: TransitStationTimetableMunicipality?
    ) async throws -> [TransitSuggestion] {
        try await searchStationTimetableLines(prefix: prefix, limit: limit, timetable: timetable)
    }

    func searchStationTimetableStops(
        prefix: String,
        line: String,
        limit: Int,
        timetable: TransitTimetable
    ) async throws -> [TransitSuggestion] {
        throw TransitDataSourceError.unsupported(.stationTimetables, source: descriptor)
    }

    func searchStationTimetableStops(
        prefix: String,
        line: String,
        limit: Int,
        timetable: TransitTimetable,
        municipality: TransitStationTimetableMunicipality?
    ) async throws -> [TransitSuggestion] {
        try await searchStationTimetableStops(
            prefix: prefix,
            line: line,
            limit: limit,
            timetable: timetable
        )
    }

    func findStationTimetable(
        request: TransitStationTimetableRequest,
        language: TransitLanguage
    ) async throws -> TransitStationTimetable {
        throw TransitDataSourceError.unsupported(.stationTimetables, source: descriptor)
    }
}

public extension TransitStationTimetableDepartureResolving {
    func resolveStationTimetableDeparture(
        request: TransitStationTimetableDepartureResolutionRequest,
        language: TransitLanguage
    ) async throws -> TransitStationTimetableDepartureResolution? {
        throw TransitDataSourceError.unsupported(
            .stationTimetableDepartureResolution,
            source: descriptor
        )
    }
}

public extension TransitServiceDetailProviding {
    func serviceDetail(id: String, timetable: TransitTimetable) async throws -> TransitServiceDetail {
        throw TransitDataSourceError.unsupported(.serviceDetails, source: descriptor)
    }

    func serviceDetail(
        id: String,
        timetable: TransitTimetable,
        language: TransitLanguage
    ) async throws -> TransitServiceDetail {
        try await serviceDetail(id: id, timetable: timetable)
    }

    func serviceDetail(id: String) async throws -> TransitServiceDetail {
        try await serviceDetail(id: id, timetable: defaultTimetableForServiceLookup)
    }

    func serviceDetail(id: String, language: TransitLanguage) async throws -> TransitServiceDetail {
        try await serviceDetail(
            id: id,
            timetable: defaultTimetableForServiceLookup,
            language: language
        )
    }

    func timetableValidity(
        for timetable: TransitTimetable,
        language: TransitLanguage
    ) async throws -> TransitTimetableValidity {
        throw TransitDataSourceError.unsupported(.timetableValidity, source: descriptor)
    }

    func serviceDateLimits(
        for service: TransitServiceDetail,
        language: TransitLanguage
    ) async throws -> TransitServiceDateLimits {
        throw TransitDataSourceError.unsupported(.serviceDateLimits, source: descriptor)
    }

    private var defaultTimetableForServiceLookup: TransitTimetable {
        if let source = self as? any TransitTimetableProviding {
            return source.defaultTimetable
        }
        return TransitTimetable(
            dataSourceID: descriptor.id,
            identifier: "default",
            displayName: descriptor.displayName
        )
    }
}

public extension TransitConnectionExporting {
    func connectionCalendar(
        for connection: TransitConnection,
        timetable: TransitTimetable
    ) async throws -> String {
        throw TransitDataSourceError.unsupported(.connectionCalendarExport, source: descriptor)
    }

    func connectionCalendar(
        for connection: TransitConnection,
        timetable: TransitTimetable,
        language: TransitLanguage
    ) async throws -> String {
        try await connectionCalendar(for: connection, timetable: timetable)
    }

    func connectionPDF(
        for connection: TransitConnection,
        timetable: TransitTimetable,
        language: TransitLanguage
    ) async throws -> Data {
        throw TransitDataSourceError.unsupported(.connectionPDFExport, source: descriptor)
    }
}

public extension TransitServiceExporting {
    func serviceCalendar(for service: TransitServiceDetail) async throws -> String {
        throw TransitDataSourceError.unsupported(.serviceCalendarExport, source: descriptor)
    }

    func serviceCalendar(for service: TransitServiceDetail, language: TransitLanguage) async throws -> String {
        try await serviceCalendar(for: service)
    }

    func servicePDF(for service: TransitServiceDetail, language: TransitLanguage) async throws -> Data {
        throw TransitDataSourceError.unsupported(.servicePDFExport, source: descriptor)
    }
}

public extension TransitConnectionEmailSending {
    func connectionEmailDraft(
        for connection: TransitConnection,
        timetable: TransitTimetable,
        language: TransitLanguage
    ) async throws -> TransitConnectionEmailDraft {
        throw TransitDataSourceError.unsupported(.connectionEmail, source: descriptor)
    }

    func sendConnectionByEmail(
        _ connection: TransitConnection,
        to recipient: String,
        message: String,
        timetable: TransitTimetable,
        language: TransitLanguage
    ) async throws {
        throw TransitDataSourceError.unsupported(.connectionEmail, source: descriptor)
    }
}

/// Compatibility refinement for existing custom IDOS clients and test doubles.
///
/// Its defaults retain the historical IDOS identity, catalog, required operations, and optional-operation errors.
/// Provider-neutral composition roots consume `TransitDataSource`; explicitly IDOS-only interfaces can retain this
/// refinement.
public protocol IDOSClienting: TransitDataSource {}

public extension IDOSClienting {
    var descriptor: TransitDataSourceDescriptor { .legacyIDOSClient }
    var serviceTimeZone: TimeZone? { IDOSDataSource.serviceTimeZone }
    var timetables: [TransitTimetable] { TransitTimetable.known }
    var defaultTimetable: TransitTimetable { .defaultTimetable }

    func resolveTimetable(_ value: String?) throws -> TransitTimetable {
        try TransitTimetable.resolve(value)
    }

    /// Retains the original empty-page fallback for source-compatible legacy conformers.
    func findConnectionsPage(
        from page: TransitConnectionPage,
        direction: TransitPageDirection
    ) async throws -> TransitConnectionPage {
        guard page.dataSourceID == descriptor.id else {
            throw TransitDataSourceError.pageBelongsToDifferentSource(
                expected: descriptor.id,
                actual: page.dataSourceID
            )
        }
        return TransitConnectionPage(connections: [], dataSourceID: descriptor.id)
    }

    /// Retains the original empty-page fallback for source-compatible legacy conformers.
    func findDeparturesPage(
        from page: TransitDeparturePage,
        direction: TransitPageDirection
    ) async throws -> TransitDeparturePage {
        guard page.dataSourceID == descriptor.id else {
            throw TransitDataSourceError.pageBelongsToDifferentSource(
                expected: descriptor.id,
                actual: page.dataSourceID
            )
        }
        return TransitDeparturePage(departures: [], dataSourceID: descriptor.id)
    }

    /// Converts a device coordinate to IDOS's exact `My location` selection while retaining legacy conformers.
    func coordinatePlaceSelection(
        text: String,
        latitude: Double,
        longitude: Double,
        timetable: TransitTimetable
    ) throws -> TransitPlaceSelection {
        guard timetable.dataSourceID == descriptor.id else {
            throw TransitDataSourceError.valueBelongsToDifferentSource(
                expected: descriptor.id,
                actual: timetable.dataSourceID
            )
        }
        return TransitPlaceSelection.currentLocation(
            text: text,
            latitude: latitude,
            longitude: longitude,
            timetableIdentifier: timetable.identifier
        )
    }

    func stationTimetableMunicipalities(
        for timetable: TransitTimetable
    ) -> [TransitStationTimetableMunicipality] {
        TransitStationTimetableMunicipality.available(for: timetable)
    }

    func defaultStationTimetableMunicipality(
        for timetable: TransitTimetable
    ) -> TransitStationTimetableMunicipality? {
        TransitStationTimetableMunicipality.default(for: timetable)
    }

    func resolveStationTimetableMunicipality(
        _ value: String?,
        timetable: TransitTimetable
    ) throws -> TransitStationTimetableMunicipality? {
        try TransitStationTimetableMunicipality.resolve(value, timetable: timetable)
    }

    func connectionEmailDraft(
        for connection: TransitConnection,
        timetable: TransitTimetable,
        language: TransitLanguage
    ) async throws -> TransitConnectionEmailDraft {
        throw IDOSError.emailUnavailable
    }

    func sendConnectionByEmail(
        _ connection: TransitConnection,
        to recipient: String,
        message: String,
        timetable: TransitTimetable,
        language: TransitLanguage
    ) async throws {
        throw IDOSError.emailUnavailable
    }

    func searchStationTimetableLines(
        prefix: String,
        limit: Int,
        timetable: TransitTimetable
    ) async throws -> [TransitSuggestion] {
        throw IDOSError.stationTimetableUnavailable
    }

    func searchStationTimetableStops(
        prefix: String,
        line: String,
        limit: Int,
        timetable: TransitTimetable
    ) async throws -> [TransitSuggestion] {
        throw IDOSError.stationTimetableUnavailable
    }

    func findStationTimetable(
        request: TransitStationTimetableRequest,
        language: TransitLanguage
    ) async throws -> TransitStationTimetable {
        throw IDOSError.stationTimetableUnavailable
    }

    func timetableValidity(
        for timetable: TransitTimetable,
        language: TransitLanguage
    ) async throws -> TransitTimetableValidity {
        throw IDOSError.invalidResponse
    }

    func serviceCalendar(for service: TransitServiceDetail) async throws -> String {
        throw IDOSError.calendarUnavailable
    }

    func servicePDF(for service: TransitServiceDetail, language: TransitLanguage) async throws -> Data {
        throw IDOSError.pdfUnavailable
    }

    func connectionPDF(
        for connection: TransitConnection,
        timetable: TransitTimetable,
        language: TransitLanguage
    ) async throws -> Data {
        throw IDOSError.pdfUnavailable
    }

    func serviceDateLimits(
        for service: TransitServiceDetail,
        language: TransitLanguage
    ) async throws -> TransitServiceDateLimits {
        throw IDOSError.dateLimitsUnavailable
    }
}

/// Resolves registered providers by stable source ID without coupling consumers to concrete implementations.
public struct TransitDataSourceRegistry: Sendable {
    private let dataSources: [TransitDataSourceID: any TransitDataSource]
    private let regularDataSourceIDs: Set<TransitDataSourceID>
    private let explicitDataSourceIDs: Set<TransitDataSourceID>
    public let defaultDataSourceID: TransitDataSourceID

    /// Registers ordinary user-facing providers and optional providers that require an explicit testing choice.
    ///
    /// Explicit providers remain resolvable by stable ID, but do not affect provider counts, default selection, or
    /// ordinary provider pickers. The default must always belong to `dataSources` rather than
    /// `explicitDataSources`.
    public init(
        dataSources: [any TransitDataSource],
        defaultDataSourceID: TransitDataSourceID,
        explicitDataSources: [any TransitDataSource] = []
    ) throws {
        var indexed: [TransitDataSourceID: any TransitDataSource] = [:]
        for dataSource in dataSources + explicitDataSources {
            let id = dataSource.descriptor.id
            guard indexed[id] == nil else {
                throw TransitDataSourceRegistryError.duplicate(id)
            }
            let defaultTimetable = dataSource.defaultTimetable
            guard defaultTimetable.dataSourceID == id else {
                throw TransitDataSourceRegistryError.timetableBelongsToDifferentSource(
                    expected: id,
                    actual: defaultTimetable.dataSourceID,
                    identifier: defaultTimetable.identifier,
                    role: .defaultTimetable
                )
            }
            if let timetable = dataSource.timetables.first(where: { $0.dataSourceID != id }) {
                throw TransitDataSourceRegistryError.timetableBelongsToDifferentSource(
                    expected: id,
                    actual: timetable.dataSourceID,
                    identifier: timetable.identifier,
                    role: .catalogEntry
                )
            }
            guard dataSource.timetables.contains(defaultTimetable) else {
                throw TransitDataSourceRegistryError.defaultTimetableMissingFromCatalog(
                    source: id,
                    identifier: defaultTimetable.identifier
                )
            }
            var timetableIdentifiers = Set<String>()
            if let duplicate = dataSource.timetables.first(where: {
                !timetableIdentifiers.insert($0.identifier.lowercased()).inserted
            }) {
                throw TransitDataSourceRegistryError.duplicateTimetableIdentifier(
                    source: id,
                    identifier: duplicate.identifier
                )
            }
            indexed[id] = dataSource
        }
        let regularDataSourceIDs = Set(dataSources.map(\.descriptor.id))
        guard regularDataSourceIDs.contains(defaultDataSourceID) else {
            if indexed[defaultDataSourceID] != nil {
                throw TransitDataSourceRegistryError.defaultDataSourceRequiresExplicitSelection(
                    defaultDataSourceID
                )
            }
            throw TransitDataSourceRegistryError.missingDefault(defaultDataSourceID)
        }

        self.dataSources = indexed
        self.regularDataSourceIDs = regularDataSourceIDs
        explicitDataSourceIDs = Set(explicitDataSources.map(\.descriptor.id))
        self.defaultDataSourceID = defaultDataSourceID
    }

    public static let builtIn: Self = {
        do {
            return try Self(
                dataSources: [IDOSDataSource()],
                defaultDataSourceID: .idos,
                explicitDataSources: [MockTransitDataSource()]
            )
        } catch {
            preconditionFailure("Invalid built-in data-source registry: \(error.localizedDescription)")
        }
    }()

    /// Ordinary providers offered without a special testing gesture or command-line choice.
    public var descriptors: [TransitDataSourceDescriptor] {
        descriptors(for: regularDataSourceIDs)
    }

    /// Providers available only through an explicit testing choice.
    public var explicitDataSourceDescriptors: [TransitDataSourceDescriptor] {
        descriptors(for: explicitDataSourceIDs)
    }

    public var defaultDataSource: any TransitDataSource {
        dataSources[defaultDataSourceID]!
    }

    public func dataSource(for id: TransitDataSourceID) -> (any TransitDataSource)? {
        dataSources[id]
    }

    private func descriptors(
        for ids: Set<TransitDataSourceID>
    ) -> [TransitDataSourceDescriptor] {
        ids.compactMap { dataSources[$0]?.descriptor }
            .sorted { $0.id.rawValue < $1.id.rawValue }
    }
}

/// Identifies which provider-owned timetable value violated a registry invariant.
public enum TransitDataSourceTimetableRole: String, Equatable, Sendable {
    case defaultTimetable = "default"
    case catalogEntry = "catalog"
}

public enum TransitDataSourceRegistryError: LocalizedError, Equatable, Sendable {
    case duplicate(TransitDataSourceID)
    case duplicateTimetableIdentifier(source: TransitDataSourceID, identifier: String)
    case defaultTimetableMissingFromCatalog(source: TransitDataSourceID, identifier: String)
    case missingDefault(TransitDataSourceID)
    case defaultDataSourceRequiresExplicitSelection(TransitDataSourceID)
    case timetableBelongsToDifferentSource(
        expected: TransitDataSourceID,
        actual: TransitDataSourceID,
        identifier: String,
        role: TransitDataSourceTimetableRole
    )

    public var errorDescription: String? {
        switch self {
        case .duplicate(let id):
            return "Data source is registered more than once: \(id.rawValue)."
        case .duplicateTimetableIdentifier(let source, let identifier):
            return "Timetable identifier \(identifier) is registered more than once for \(source.rawValue)."
        case .defaultTimetableMissingFromCatalog(let source, let identifier):
            return "Default timetable \(identifier) is not present in the catalog for \(source.rawValue)."
        case .missingDefault(let id):
            return "Default data source is not registered: \(id.rawValue)."
        case .defaultDataSourceRequiresExplicitSelection(let id):
            return "Default data source requires explicit selection: \(id.rawValue)."
        case .timetableBelongsToDifferentSource(let expected, let actual, let identifier, let role):
            return "The \(role.rawValue) timetable \(identifier) belongs to \(actual.rawValue), not \(expected.rawValue)."
        }
    }
}
