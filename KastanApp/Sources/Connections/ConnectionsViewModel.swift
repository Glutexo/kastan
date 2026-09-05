import Foundation
import Kastan

/// Groups the extensible journey-option catalog using the corresponding IDOS advanced-form sections.
enum JourneyOptionGroup: CaseIterable {
    case transfers
    case additionalParameters

    var localizedTitle: String {
        switch self {
        case .transfers:
            AppLocalization.string("Transfers")
        case .additionalParameters:
            AppLocalization.string("Additional parameters")
        }
    }
}

/// Identifies one connection requirement that can be combined with other requirements in the journey builder.
enum JourneyConnectionRequirement: String, CaseIterable, Identifiable {
    case wheelchairAccessibleConnectionsOnly
    case lowFloorConnectionsOnly
    case trainConnectionsForWheelchairPassengers
    case trainConnectionsForPassengersWithChildren
    case connectionsForPassengersWithBicycles

    var id: Self { self }

    /// Maps the compact product choice to the independent provider-neutral request option.
    var transitConnectionOption: TransitConnectionOption {
        switch self {
        case .wheelchairAccessibleConnectionsOnly:
            .wheelchairAccessibleConnectionsOnly
        case .lowFloorConnectionsOnly:
            .lowFloorConnectionsOnly
        case .trainConnectionsForWheelchairPassengers:
            .trainConnectionsForWheelchairPassengers
        case .trainConnectionsForPassengersWithChildren:
            .trainConnectionsForPassengersWithChildren
        case .connectionsForPassengersWithBicycles:
            .connectionsForPassengersWithBicycles
        }
    }

    /// Preserves the wording of each corresponding IDOS advanced-search choice.
    var localizedTitle: String {
        switch self {
        case .wheelchairAccessibleConnectionsOnly:
            AppLocalization.string("Wheelchair accessible connections only")
        case .lowFloorConnectionsOnly:
            AppLocalization.string("Low-floor lines only")
        case .trainConnectionsForWheelchairPassengers:
            AppLocalization.string("Wheelchair accessible connections (trains)")
        case .trainConnectionsForPassengersWithChildren:
            AppLocalization.string("Connections for passengers with children (trains)")
        case .connectionsForPassengersWithBicycles:
            AppLocalization.string("Connections for passengers with bicycles (trains + buses)")
        }
    }

    static var localizedCatalogTitles: [String] {
        allCases.map(\.localizedTitle)
    }
}

/// Identifies one route preference that can be combined with another preference in the journey builder.
enum JourneyPreference: String, CaseIterable, Identifiable {
    case busyRoutes
    case trainsOverBuses

    var id: Self { self }

    /// Maps the compact product choice to the independent provider-neutral request option.
    var transitConnectionOption: TransitConnectionOption {
        switch self {
        case .busyRoutes:
            .preferBusyRoutes
        case .trainsOverBuses:
            .preferTrainsOverBuses
        }
    }

    /// Names only the selected value because the shared row label already supplies the preference verb.
    var localizedTitle: String {
        switch self {
        case .busyRoutes:
            AppLocalization.string("Busy routes")
        case .trainsOverBuses:
            AppLocalization.string("Trains instead of buses")
        }
    }

    static var localizedCatalogTitles: [String] {
        allCases.map(\.localizedTitle)
    }
}

/// Identifies one independently repeatable transfer constraint inside the shared Transfers condition.
enum JourneyTransferConstraint: String, CaseIterable, Identifiable {
    case maximumTransfers
    case minimumTransferTime
    case maximumTransferTime

    var id: Self { self }

    /// Maps the compact subchoice to the provider-neutral request option it configures.
    var transitConnectionOption: TransitConnectionOption {
        switch self {
        case .maximumTransfers:
            .maximumTransfers
        case .minimumTransferTime:
            .minimumTransferTime
        case .maximumTransferTime:
            .maximumTransferTime
        }
    }

    /// Keeps each subchoice concise because the parent condition already supplies the transfer context.
    var localizedTitle: String {
        switch self {
        case .maximumTransfers:
            AppLocalization.string("Maximum number")
        case .minimumTransferTime:
            AppLocalization.string("Minimum time")
        case .maximumTransferTime:
            AppLocalization.string("Maximum time")
        }
    }

    static var localizedCatalogTitles: [String] {
        allCases.map(\.localizedTitle)
    }

    /// Direct journeys have no transfer whose waiting time could be constrained.
    var isTransferTimeConstraint: Bool {
        self == .minimumTransferTime || self == .maximumTransferTime
    }
}

/// Identifies one independently repeatable walking-distance limit inside the shared Walking distances condition.
enum JourneyWalkingDistanceConstraint: String, CaseIterable, Identifiable {
    case maximumWalkingTime
    case maximumCityWalkingTime

    var id: Self { self }

    /// Maps the compact subchoice to the provider-neutral request option it configures.
    var transitConnectionOption: TransitConnectionOption {
        switch self {
        case .maximumWalkingTime:
            .maximumWalkingTime
        case .maximumCityWalkingTime:
            .maximumCityWalkingTime
        }
    }

    /// Preserves the wording of each corresponding IDOS walking-distance control.
    var localizedTitle: String {
        switch self {
        case .maximumWalkingTime:
            AppLocalization.string("Maximum distance to walk")
        case .maximumCityWalkingTime:
            AppLocalization.string("Maximum distance to walk, if there is Urban Public Transport available")
        }
    }

    static var localizedCatalogTitles: [String] {
        allCases.map(\.localizedTitle)
    }
}

/// Identifies one independently repeatable walking-transfer rule inside the shared Walking transfer condition.
enum JourneyWalkingTransferPolicy: String, CaseIterable, Identifiable {
    case walkToNearbyStops
    case sameNameWalkingTransfersOnly

    var id: Self { self }

    /// Maps the compact subchoice to the provider-neutral request option it configures.
    var transitConnectionOption: TransitConnectionOption {
        switch self {
        case .walkToNearbyStops:
            .walkToNearbyStops
        case .sameNameWalkingTransfersOnly:
            .sameNameWalkingTransfersOnly
        }
    }

    /// Names only the selected rule because the shared row label already identifies it as a walking transfer.
    var localizedTitle: String {
        switch self {
        case .walkToNearbyStops:
            AppLocalization.string("On foot between stops")
        case .sameNameWalkingTransfersOnly:
            AppLocalization.string("Between stops of the same name")
        }
    }

    static var localizedCatalogTitles: [String] {
        allCases.map(\.localizedTitle)
    }
}

/// Identifies the value editor shown by one extensible journey-option row.
enum JourneyOptionKind: String, CaseIterable, Identifiable {
    case via
    case transfers
    case walkingDistances
    case walkingTransfer
    case onlyConnections
    case preference
    case bedOrCouchettePreference

    var id: Self { self }

    /// Maps one product editor to every provider-neutral option that it can configure.
    var transitConnectionOptions: [TransitConnectionOption] {
        switch self {
        case .via:
            [.via]
        case .transfers:
            JourneyTransferConstraint.allCases.map(\.transitConnectionOption)
        case .walkingDistances:
            JourneyWalkingDistanceConstraint.allCases.map(\.transitConnectionOption)
        case .walkingTransfer:
            JourneyWalkingTransferPolicy.allCases.map(\.transitConnectionOption)
        case .onlyConnections:
            JourneyConnectionRequirement.allCases.map(\.transitConnectionOption)
        case .preference:
            JourneyPreference.allCases.map(\.transitConnectionOption)
        case .bedOrCouchettePreference:
            [.bedOrCouchettePreference]
        }
    }

    /// Uses the same product wording in the picker and its corresponding editor.
    var localizedTitle: String {
        switch self {
        case .via:
            AppLocalization.string("Via")
        case .transfers:
            AppLocalization.string("Transfers")
        case .walkingDistances:
            AppLocalization.string("Walking distances")
        case .walkingTransfer:
            AppLocalization.string("Walking transfer")
        case .onlyConnections:
            AppLocalization.string("Only connections")
        case .preference:
            AppLocalization.string("Prefer")
        case .bedOrCouchettePreference:
            AppLocalization.string("Bed / Couchette")
        }
    }

    /// Places every existing transfer control before the additional IDOS search parameters.
    var group: JourneyOptionGroup {
        switch self {
        case .via, .transfers, .walkingDistances, .walkingTransfer:
            .transfers
        case .onlyConnections, .preference, .bedOrCouchettePreference:
            .additionalParameters
        }
    }

    /// Reserves enough native popup width for both section headings and every localized option.
    static var localizedCatalogTitles: [String] {
        JourneyOptionGroup.allCases.flatMap { group in
            [group.localizedTitle] + allCases.filter { $0.group == group }.map(\.localizedTitle)
        }
    }

    /// Intermediate places and combined choices can form repeatable rows with distinct subchoices.
    var allowsMultiple: Bool {
        self == .via || self == .transfers || self == .walkingDistances ||
            self == .walkingTransfer || self == .onlyConnections || self == .preference
    }

    /// Identifies conditions whose previous value should survive a temporary direct-only search.
    var usesRememberedTransferValue: Bool {
        switch self {
        case .transfers:
            true
        case .via, .walkingDistances, .walkingTransfer,
             .onlyConnections, .preference, .bedOrCouchettePreference:
            false
        }
    }

}

/// Presents each minute value supported by the corresponding IDOS transfer control.
struct JourneyDurationChoice: Identifiable, Equatable {
    let minutes: Int

    var id: Int { minutes }

    func localizedTitle(bundle: Bundle = .main) -> String {
        guard minutes >= 0 else {
            return bundle.localizedString(forKey: "Standard", value: "Standard", table: nil)
        }

        let displaysHours = minutes >= 60 && minutes.isMultiple(of: 60)
        let value = displaysHours ? minutes / 60 : minutes
        let key = displaysHours ? "%lld hr" : "%lld min"
        let format = bundle.localizedString(forKey: key, value: key, table: nil)
        return String(
            format: format,
            locale: AppLocalization.locale(for: bundle),
            arguments: [Int64(value)]
        )
    }

    /// Mirrors the discrete values offered by IDOS, including its timetable-specific standard.
    static let minimumTransferTimes = [-1, 0, 1, 2, 3, 4, 5, 10, 20, 30, 60].map(Self.init)
    static let maximumTransferTimes = [10, 20, 30, 45, 60, 120, 240, 360, 480, 720, 1_080].map(Self.init)
    static let maximumWalkingTimes = [0, 5, 10, 20, 30, 45, 60].map(Self.init)
}

extension TransitBedOrCouchettePreference {
    /// Uses the same accommodation choices and wording as the selected IDOS control.
    func localizedTitle(bundle: Bundle = .main) -> String {
        let key = switch self {
        case .noLimitation:
            "(no limitation)"
        case .use:
            "use"
        case .doNotUse:
            "don't use"
        }
        return bundle.localizedString(forKey: key, value: key, table: nil)
    }
}

/// Stores one independently editable condition in the journey-options builder.
struct JourneyOptionEntry: Identifiable, Equatable {
    let id: UUID
    var kind: JourneyOptionKind
    var viaPlace: String {
        didSet {
            if viaSelection?.text != viaPlace {
                viaSelection = nil
            }
        }
    }
    /// Retains an exact IDOS place only while its visible via-place text remains unchanged.
    var viaSelection: PlaceFieldSelection?
    var transferConstraint: JourneyTransferConstraint
    var walkingDistanceConstraint: JourneyWalkingDistanceConstraint
    var walkingTransferPolicy: JourneyWalkingTransferPolicy
    var maximumTransfers: Int
    var minimumTransferTime: Int
    var maximumTransferTime: Int
    var maximumWalkingTime: Int
    var maximumCityWalkingTime: Int
    var walkToNearbyStops: Bool
    var sameNameWalkingTransfersOnly: Bool
    var connectionRequirement: JourneyConnectionRequirement
    var preference: JourneyPreference
    var bedOrCouchettePreference: TransitBedOrCouchettePreference

    /// Distinguishes the two transfer-waiting rows that direct-only mode makes meaningless.
    var isTransferTimeCondition: Bool {
        kind == .transfers && transferConstraint.isTransferTimeConstraint
    }

    /// Connects the direct-only shortcut to its visible zero-transfer representation.
    var isZeroTransferLimit: Bool {
        kind == .transfers && transferConstraint == .maximumTransfers && maximumTransfers == 0
    }

    init(
        id: UUID = UUID(),
        kind: JourneyOptionKind = .via,
        viaPlace: String = "",
        viaSelection: PlaceFieldSelection? = nil,
        transferConstraint: JourneyTransferConstraint = .maximumTransfers,
        walkingDistanceConstraint: JourneyWalkingDistanceConstraint = .maximumWalkingTime,
        walkingTransferPolicy: JourneyWalkingTransferPolicy = .walkToNearbyStops,
        maximumTransfers: Int = 4,
        minimumTransferTime: Int = -1,
        maximumTransferTime: Int = 240,
        maximumWalkingTime: Int = 60,
        maximumCityWalkingTime: Int = 10,
        walkToNearbyStops: Bool = true,
        sameNameWalkingTransfersOnly: Bool = false,
        connectionRequirement: JourneyConnectionRequirement = .wheelchairAccessibleConnectionsOnly,
        preference: JourneyPreference = .busyRoutes,
        bedOrCouchettePreference: TransitBedOrCouchettePreference = .noLimitation
    ) {
        self.id = id
        self.kind = kind
        self.viaPlace = viaPlace
        self.viaSelection = viaSelection
        self.transferConstraint = transferConstraint
        self.walkingDistanceConstraint = walkingDistanceConstraint
        self.walkingTransferPolicy = walkingTransferPolicy
        self.maximumTransfers = maximumTransfers
        self.minimumTransferTime = minimumTransferTime
        self.maximumTransferTime = maximumTransferTime
        self.maximumWalkingTime = maximumWalkingTime
        self.maximumCityWalkingTime = maximumCityWalkingTime
        self.walkToNearbyStops = walkToNearbyStops
        self.sameNameWalkingTransfersOnly = sameNameWalkingTransfersOnly
        self.connectionRequirement = connectionRequirement
        self.preference = preference
        self.bedOrCouchettePreference = bedOrCouchettePreference
    }
}

/// Identifies which connection endpoint should receive an explicitly requested current location.
enum ConnectionEndpoint: Equatable {
    case from
    case to
}

/// Owns one connection search and exposes only UI-ready state to the SwiftUI view.
@MainActor
final class ConnectionsViewModel: ObservableObject {
    static let maximumTransferRange = 0...10
    private static let defaultMaximumTransfers = 4

    /// Retains useful transfer values after direct-only mode removes their mutually exclusive rows.
    private struct RememberedTransferValues {
        var maximumTransfers = 4
        var minimumTransferTime = -1
        var maximumTransferTime = 240
    }

    @Published var from = "" {
        didSet {
            if let fromSelection, fromSelection.text != from {
                self.fromSelection = nil
            }
        }
    }
    @Published var to = "" {
        didSet {
            if let toSelection, toSelection.text != to {
                self.toSelection = nil
            }
        }
    }
    /// Exact provider-owned choices retained only while their corresponding visible text is unchanged.
    @Published var fromSelection: PlaceFieldSelection?
    @Published var toSelection: PlaceFieldSelection?
    @Published var journeyOptions: [JourneyOptionEntry]
    @Published var timetable: TransitTimetable {
        didSet {
            guard timetable != oldValue else { return }
            // Even a current-location value is encoded by its provider for one timetable. Keep its visible
            // text so the next search can resolve the coordinate again for the newly selected catalog.
            fromSelection = nil
            toSelection = nil
            for index in journeyOptions.indices {
                journeyOptions[index].viaSelection = nil
            }
            removeJourneyOptionsUnavailableForCurrentTimetable()
        }
    }
    @Published var date = Date() {
        didSet { stopFollowingCurrentDateAndTime() }
    }
    @Published var time = Date() {
        didSet { stopFollowingCurrentDateAndTime() }
    }
    /// Distinguishes the live current-moment default from a journey instant deliberately chosen or submitted.
    @Published private(set) var usesCurrentDateAndTime = true
    @Published var isArrival = false
    @Published private(set) var onlyDirect = false
    @Published private(set) var connections: [TransitConnection] = []
    @Published private(set) var hasCompletedSearch = false
    @Published private(set) var isSearching = false
    @Published private(set) var isLoadingEarlier = false
    @Published private(set) var isLoadingLater = false
    @Published private(set) var processingEmailConnectionID: AppTransitValueIdentity?
    @Published private(set) var processingCalendarConnectionID: AppTransitValueIdentity?
    @Published private(set) var processingPDFConnectionID: AppTransitValueIdentity?
    @Published private(set) var locatingEndpoint: ConnectionEndpoint?
    @Published var errorMessage: String?

    let client: any TransitDataSource
    private let calendarImporter: any CalendarImporting
    private let calendarSaver: any CalendarSaving
    private let pdfOpener: any PDFOpening
    private let pdfExporter: any PDFExporting
    private let emailMailComposer: any ConnectionEmailMailComposing
    private let currentLocationProvider: any CurrentLocationProviding
    private var resultPage: TransitConnectionPage?
    private var isRefreshingCurrentDateAndTime = false
    private var rememberedTransferValues = RememberedTransferValues()

    init(
        client: any TransitDataSource,
        calendarImporter: any CalendarImporting = WorkspaceCalendarImporter(),
        calendarSaver: any CalendarSaving = WorkspaceCalendarSaver(),
        pdfOpener: any PDFOpening = WorkspacePDFOpener(),
        pdfExporter: any PDFExporting = WorkspacePDFExporter(),
        emailMailComposer: any ConnectionEmailMailComposing = WorkspaceConnectionEmailMailComposer(),
        currentLocationProvider: any CurrentLocationProviding = SystemCurrentLocationProvider()
    ) {
        self.client = client
        let selectedTimetable = AppTimetableDefaults.search(
            in: client.timetables,
            defaultTimetable: client.defaultTimetable
        )
        // An empty via field is an inactive affordance. Every other editor carries a meaningful default value,
        // so sources without via support start with no row until the user explicitly adds a condition.
        journeyOptions = client.supportsConnectionOption(.via, for: selectedTimetable)
            ? [JourneyOptionEntry(kind: .via)]
            : []
        timetable = selectedTimetable
        self.calendarImporter = calendarImporter
        self.calendarSaver = calendarSaver
        self.pdfOpener = pdfOpener
        self.pdfExporter = pdfExporter
        self.emailMailComposer = emailMailComposer
        self.currentLocationProvider = currentLocationProvider
    }

    var timetables: [TransitTimetable] {
        client.timetables
    }

    /// Limits the extensible editor to fields the provider promises to interpret for the selected timetable.
    var supportedJourneyOptionKinds: [JourneyOptionKind] {
        JourneyOptionKind.allCases.filter { kind in
            kind.transitConnectionOptions.contains(where: supportsConnectionOption)
        }
    }

    /// Limits the shared Transfers popup to subchoices interpreted by the selected timetable.
    var supportedTransferConstraints: [JourneyTransferConstraint] {
        JourneyTransferConstraint.allCases.filter {
            supportsConnectionOption($0.transitConnectionOption)
        }
    }

    /// Limits the shared Walking distances popup to subchoices interpreted by the selected timetable.
    var supportedWalkingDistanceConstraints: [JourneyWalkingDistanceConstraint] {
        JourneyWalkingDistanceConstraint.allCases.filter {
            supportsConnectionOption($0.transitConnectionOption)
        }
    }

    /// Limits the shared Walking transfer popup to subchoices interpreted by the selected timetable.
    var supportedWalkingTransferPolicies: [JourneyWalkingTransferPolicy] {
        JourneyWalkingTransferPolicy.allCases.filter {
            supportsConnectionOption($0.transitConnectionOption)
        }
    }

    /// Limits the combined requirement popup to choices interpreted by the selected timetable.
    var supportedConnectionRequirements: [JourneyConnectionRequirement] {
        JourneyConnectionRequirement.allCases.filter {
            supportsConnectionOption($0.transitConnectionOption)
        }
    }

    /// Limits the combined preference popup to choices interpreted by the selected timetable.
    var supportedJourneyPreferences: [JourneyPreference] {
        JourneyPreference.allCases.filter {
            supportsConnectionOption($0.transitConnectionOption)
        }
    }

    var supportsOnlyDirect: Bool {
        supportsConnectionOption(.onlyDirect)
    }

    /// Treats a zero transfer ceiling as a direct journey even when the provider has no separate direct flag.
    var hasNoTransfers: Bool {
        onlyDirect || maximumTransfers == 0
    }

    var hasConfigurableConnectionOptions: Bool {
        supportsOnlyDirect || !supportedJourneyOptionKinds.isEmpty
    }

    /// Exposes the location shortcut only when the selected source can turn coordinates into an exact place.
    var canFillCurrentLocation: Bool {
        client.descriptor.supports(.coordinatePlaceSelection)
    }

    var canSearch: Bool {
        !from.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !to.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            endpointValidationMessage == nil && !isSearching && !isLoadingEarlier &&
            !isLoadingLater && locatingEndpoint == nil
    }

    var canLoadEarlier: Bool {
        client.descriptor.supports(.connectionPaging) &&
            !connections.isEmpty && resultPage?.canLoadEarlier == true && !isSearching && !isLoadingLater
    }

    var canLoadLater: Bool {
        client.descriptor.supports(.connectionPaging) &&
            !connections.isEmpty && resultPage?.canLoadLater == true && !isSearching && !isLoadingEarlier
    }

    /// Keeps untouched launch defaults current until the first search, while preserving every explicit choice.
    func refreshCurrentDateAndTime(now: Date = .now) {
        guard usesCurrentDateAndTime else { return }

        selectCurrentDateAndTime(now: now)
    }

    /// Restores the live current-moment choice from the compact date-and-time editor.
    func selectCurrentDateAndTime(now: Date = .now) {
        usesCurrentDateAndTime = true

        isRefreshingCurrentDateAndTime = true
        defer { isRefreshingCurrentDateAndTime = false }
        date = now
        time = now
    }

    /// Replaces only the journey date while retaining the deliberately selected time.
    func selectCurrentDate(now: Date = .now) {
        usesCurrentDateAndTime = false
        date = now
    }

    /// Replaces only the journey time while retaining the deliberately selected date.
    func selectCurrentTime(now: Date = .now) {
        usesCurrentDateAndTime = false
        time = now
    }

    /// Gives the editable form immediate guidance before an invalid route can start searching.
    var endpointValidationMessage: String? {
        let departure = from.trimmingCharacters(in: .whitespacesAndNewlines)
        let arrival = to.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !departure.isEmpty, !arrival.isEmpty,
              endpointsReferToSamePlace(departure: departure, arrival: arrival)
        else {
            return nil
        }
        return AppLocalization.string("Choose a different departure or arrival place.")
    }

    /// Keeps the retry action off input guidance that can only be resolved by editing the route.
    var showsRefreshActionForError: Bool {
        guard errorMessage != nil else { return false }
        return endpointValidationMessage == nil
    }

    /// Returns intermediate places in their visible row order for the request and collapsed summary.
    var viaPlaceNames: [String] {
        journeyOptions.compactMap { option in
            option.kind == .via ? option.viaPlace : nil
        }
    }

    /// Returns the single visible transfer ceiling, including the zero that represents direct-only mode.
    var maximumTransfers: Int? {
        journeyOptions.first {
            $0.kind == .transfers && $0.transferConstraint == .maximumTransfers
        }?.maximumTransfers
    }

    /// Returns each optional IDOS transfer control only while its row remains visible.
    var minimumTransferTime: Int? {
        journeyOptions.first {
            $0.kind == .transfers && $0.transferConstraint == .minimumTransferTime
        }?.minimumTransferTime
    }

    var maximumTransferTime: Int? {
        journeyOptions.first {
            $0.kind == .transfers && $0.transferConstraint == .maximumTransferTime
        }?.maximumTransferTime
    }

    var maximumWalkingTime: Int? {
        journeyOptions.first {
            $0.kind == .walkingDistances &&
                $0.walkingDistanceConstraint == .maximumWalkingTime
        }?.maximumWalkingTime
    }

    var maximumCityWalkingTime: Int? {
        journeyOptions.first {
            $0.kind == .walkingDistances &&
                $0.walkingDistanceConstraint == .maximumCityWalkingTime
        }?.maximumCityWalkingTime
    }

    var walkToNearbyStops: Bool? {
        journeyOptions.first {
            $0.kind == .walkingTransfer && $0.walkingTransferPolicy == .walkToNearbyStops
        }?.walkToNearbyStops
    }

    var sameNameWalkingTransfersOnly: Bool? {
        journeyOptions.first {
            $0.kind == .walkingTransfer &&
                $0.walkingTransferPolicy == .sameNameWalkingTransfersOnly
        }?.sameNameWalkingTransfersOnly
    }

    var wheelchairAccessibleConnectionsOnly: Bool? {
        connectionRequirementIsSelected(.wheelchairAccessibleConnectionsOnly)
    }

    var lowFloorConnectionsOnly: Bool? {
        connectionRequirementIsSelected(.lowFloorConnectionsOnly)
    }

    var preferTrainsOverBuses: Bool? {
        journeyPreferenceIsSelected(.trainsOverBuses)
    }

    var trainConnectionsForWheelchairPassengers: Bool? {
        connectionRequirementIsSelected(.trainConnectionsForWheelchairPassengers)
    }

    var trainConnectionsForPassengersWithChildren: Bool? {
        connectionRequirementIsSelected(.trainConnectionsForPassengersWithChildren)
    }

    var connectionsForPassengersWithBicycles: Bool? {
        connectionRequirementIsSelected(.connectionsForPassengersWithBicycles)
    }

    var preferBusyRoutes: Bool? {
        journeyPreferenceIsSelected(.busyRoutes)
    }

    var bedOrCouchettePreference: TransitBedOrCouchettePreference? {
        journeyOptions.first {
            $0.kind == .bedOrCouchettePreference
        }?.bedOrCouchettePreference
    }

    /// Presents an active transfer ceiling, retaining only IDOS's established implicit four-transfer default.
    var transferLimitLabel: String {
        if hasNoTransfers {
            return AppLocalization.string("Direct only")
        }

        if let maximumTransfers,
           supportsConnectionOption(.maximumTransfers) {
            return AppLocalization.plural("Up to %lld transfers", count: maximumTransfers)
        }

        guard client.descriptor.id == .idos,
              supportsConnectionOption(.maximumTransfers)
        else {
            return ""
        }
        return AppLocalization.plural(
            "Up to %lld transfers",
            count: Self.defaultMaximumTransfers
        )
    }

    func swapEndpoints() {
        let previousFrom = from
        let previousFromSelection = fromSelection
        from = to
        fromSelection = toSelection
        to = previousFrom
        toSelection = previousFromSelection
    }

    /// Fills one endpoint with the selected provider's coordinate-owned place after an explicit shortcut action.
    func fillCurrentLocation(in endpoint: ConnectionEndpoint) async {
        _ = await resolveCurrentLocation(for: [endpoint])
    }

    /// Keeps each picker limited to repeatable conditions with a free value and currently unused singletons.
    func availableJourneyOptionKinds(for id: JourneyOptionEntry.ID) -> [JourneyOptionKind] {
        supportedJourneyOptionKinds.filter { kind in
            canUseJourneyOptionKind(kind, excluding: id)
        }
    }

    /// Offers the row's current transfer subchoice and every supported subchoice not selected elsewhere.
    func availableTransferConstraints(
        for id: JourneyOptionEntry.ID
    ) -> [JourneyTransferConstraint] {
        availableTransferConstraints(excluding: id)
    }

    /// Offers the row's current walking-distance limit and every supported limit not selected elsewhere.
    func availableWalkingDistanceConstraints(
        for id: JourneyOptionEntry.ID
    ) -> [JourneyWalkingDistanceConstraint] {
        availableWalkingDistanceConstraints(excluding: id)
    }

    /// Offers the row's current walking-transfer rule and every supported rule not selected elsewhere.
    func availableWalkingTransferPolicies(
        for id: JourneyOptionEntry.ID
    ) -> [JourneyWalkingTransferPolicy] {
        availableWalkingTransferPolicies(excluding: id)
    }

    /// Offers the row's current requirement and every supported requirement not already selected elsewhere.
    func availableConnectionRequirements(
        for id: JourneyOptionEntry.ID
    ) -> [JourneyConnectionRequirement] {
        availableConnectionRequirements(excluding: id)
    }

    /// Offers the row's current preference and every supported preference not already selected elsewhere.
    func availableJourneyPreferences(for id: JourneyOptionEntry.ID) -> [JourneyPreference] {
        availableJourneyPreferences(excluding: id)
    }

    /// Applies a selected condition kind and restores the last value removed for transfer-related conditions.
    func setJourneyOptionKind(_ kind: JourneyOptionKind, for id: JourneyOptionEntry.ID) {
        guard availableJourneyOptionKinds(for: id).contains(kind) else { return }
        guard let currentOption = journeyOptions.first(where: { $0.id == id }) else { return }
        guard currentOption.kind != kind else { return }

        let connectionRequirement: JourneyConnectionRequirement?
        let preference: JourneyPreference?
        let transferConstraint: JourneyTransferConstraint?
        let walkingDistanceConstraint: JourneyWalkingDistanceConstraint?
        let walkingTransferPolicy: JourneyWalkingTransferPolicy?
        switch kind {
        case .transfers:
            let availableConstraints = availableTransferConstraints(excluding: id)
            transferConstraint = availableConstraints.contains(currentOption.transferConstraint)
                ? currentOption.transferConstraint
                : availableConstraints.first
            walkingDistanceConstraint = nil
            walkingTransferPolicy = nil
            connectionRequirement = nil
            preference = nil
            guard transferConstraint != nil else { return }
        case .walkingDistances:
            let availableConstraints = availableWalkingDistanceConstraints(excluding: id)
            walkingDistanceConstraint = availableConstraints.contains(
                currentOption.walkingDistanceConstraint
            ) ? currentOption.walkingDistanceConstraint : availableConstraints.first
            transferConstraint = nil
            walkingTransferPolicy = nil
            connectionRequirement = nil
            preference = nil
            guard walkingDistanceConstraint != nil else { return }
        case .walkingTransfer:
            let availablePolicies = availableWalkingTransferPolicies(excluding: id)
            walkingTransferPolicy = availablePolicies.contains(currentOption.walkingTransferPolicy)
                ? currentOption.walkingTransferPolicy
                : availablePolicies.first
            transferConstraint = nil
            walkingDistanceConstraint = nil
            connectionRequirement = nil
            preference = nil
            guard walkingTransferPolicy != nil else { return }
        case .onlyConnections:
            let availableRequirements = availableConnectionRequirements(excluding: id)
            connectionRequirement = availableRequirements.contains(currentOption.connectionRequirement)
                ? currentOption.connectionRequirement
                : availableRequirements.first
            preference = nil
            transferConstraint = nil
            walkingDistanceConstraint = nil
            walkingTransferPolicy = nil
            guard connectionRequirement != nil else { return }
        case .preference:
            let availablePreferences = availableJourneyPreferences(excluding: id)
            preference = availablePreferences.contains(currentOption.preference)
                ? currentOption.preference
                : availablePreferences.first
            connectionRequirement = nil
            transferConstraint = nil
            walkingDistanceConstraint = nil
            walkingTransferPolicy = nil
            guard preference != nil else { return }
        default:
            connectionRequirement = nil
            preference = nil
            transferConstraint = nil
            walkingDistanceConstraint = nil
            walkingTransferPolicy = nil
        }

        if onlyDirect, currentOption.isZeroTransferLimit {
            onlyDirect = false
        }

        guard let index = journeyOptions.firstIndex(where: { $0.id == id }) else { return }

        rememberTransferValue(from: currentOption)
        journeyOptions[index].kind = kind
        if let transferConstraint {
            journeyOptions[index].transferConstraint = transferConstraint
        }
        if let walkingDistanceConstraint {
            journeyOptions[index].walkingDistanceConstraint = walkingDistanceConstraint
        }
        if let walkingTransferPolicy {
            journeyOptions[index].walkingTransferPolicy = walkingTransferPolicy
        }
        if let connectionRequirement {
            journeyOptions[index].connectionRequirement = connectionRequirement
        }
        if let preference {
            journeyOptions[index].preference = preference
        }
        if kind.usesRememberedTransferValue {
            restoreRememberedTransferValues(at: index)
        }
    }

    /// Applies one supported, distinct transfer constraint to an existing shared Transfers row.
    func setTransferConstraint(
        _ constraint: JourneyTransferConstraint,
        for id: JourneyOptionEntry.ID
    ) {
        guard availableTransferConstraints(excluding: id).contains(constraint),
              let index = journeyOptions.firstIndex(where: { $0.id == id }),
              journeyOptions[index].kind == .transfers,
              journeyOptions[index].transferConstraint != constraint
        else {
            return
        }

        let currentOption = journeyOptions[index]
        if onlyDirect, currentOption.isZeroTransferLimit {
            onlyDirect = false
        }
        rememberTransferValue(from: currentOption)
        journeyOptions[index].transferConstraint = constraint
        restoreRememberedTransferValues(at: index)
    }

    /// Applies one supported, distinct walking-distance limit to an existing shared Walking distances row.
    func setWalkingDistanceConstraint(
        _ constraint: JourneyWalkingDistanceConstraint,
        for id: JourneyOptionEntry.ID
    ) {
        guard availableWalkingDistanceConstraints(excluding: id).contains(constraint),
              let index = journeyOptions.firstIndex(where: { $0.id == id }),
              journeyOptions[index].kind == .walkingDistances
        else {
            return
        }
        journeyOptions[index].walkingDistanceConstraint = constraint
    }

    /// Applies one supported, distinct walking-transfer rule to an existing shared Walking transfer row.
    func setWalkingTransferPolicy(
        _ policy: JourneyWalkingTransferPolicy,
        for id: JourneyOptionEntry.ID
    ) {
        guard availableWalkingTransferPolicies(excluding: id).contains(policy),
              let index = journeyOptions.firstIndex(where: { $0.id == id }),
              journeyOptions[index].kind == .walkingTransfer
        else {
            return
        }
        journeyOptions[index].walkingTransferPolicy = policy
    }

    /// Applies one supported, distinct requirement to an existing combined-condition row.
    func setConnectionRequirement(
        _ requirement: JourneyConnectionRequirement,
        for id: JourneyOptionEntry.ID
    ) {
        guard availableConnectionRequirements(excluding: id).contains(requirement),
              let index = journeyOptions.firstIndex(where: { $0.id == id }),
              journeyOptions[index].kind == .onlyConnections
        else {
            return
        }
        journeyOptions[index].connectionRequirement = requirement
    }

    /// Applies one supported, distinct route preference to an existing combined-condition row.
    func setJourneyPreference(_ preference: JourneyPreference, for id: JourneyOptionEntry.ID) {
        guard availableJourneyPreferences(excluding: id).contains(preference),
              let index = journeyOptions.firstIndex(where: { $0.id == id }),
              journeyOptions[index].kind == .preference
        else {
            return
        }
        journeyOptions[index].preference = preference
    }

    /// Inserts a new, immediately editable condition directly after the selected row.
    func addJourneyOption(after id: JourneyOptionEntry.ID) {
        guard let index = journeyOptions.firstIndex(where: { $0.id == id }),
              let kind = availableJourneyOptionKindsForNewRow
        else { return }
        journeyOptions.insert(makeJourneyOptionEntry(kind: kind), at: index + 1)
    }

    /// Activates the first supported condition after an initially empty provider-specific editor.
    func addJourneyOption() {
        guard journeyOptions.isEmpty,
              let kind = availableJourneyOptionKindsForNewRow
        else { return }
        journeyOptions.append(makeJourneyOptionEntry(kind: kind))
    }

    var canAddJourneyOption: Bool {
        availableJourneyOptionKindsForNewRow != nil
    }

    /// Removes the selected condition while retaining its transfer value and an inactive via field when available.
    func removeJourneyOption(id: JourneyOptionEntry.ID) {
        guard let index = journeyOptions.firstIndex(where: { $0.id == id }) else { return }
        let removedOption = journeyOptions[index]
        rememberTransferValue(from: removedOption)
        if onlyDirect, removedOption.isZeroTransferLimit {
            onlyDirect = false
        }
        if journeyOptions.count == 1 {
            if supportsConnectionOption(.via) {
                journeyOptions[0] = makeJourneyOptionEntry(id: id, kind: .via)
            } else {
                journeyOptions.remove(at: index)
            }
        } else {
            journeyOptions.remove(at: index)
        }
    }

    /// Disables only the sole inactive via field while keeping every row's minus action visible.
    func canRemoveJourneyOption(id: JourneyOptionEntry.ID) -> Bool {
        guard let option = journeyOptions.first(where: { $0.id == id }) else { return false }
        return journeyOptions.count > 1 || option.kind != .via ||
            !option.viaPlace.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Synchronizes direct-only mode with a visible zero-transfer row and removes transfer-time conditions.
    func setOnlyDirect(_ onlyDirect: Bool) {
        guard supportsOnlyDirect else {
            self.onlyDirect = false
            return
        }
        self.onlyDirect = onlyDirect
        if onlyDirect {
            removeTransferTimeConditions()
            guard supportsConnectionOption(.maximumTransfers) else { return }
            if let index = journeyOptions.firstIndex(where: {
                $0.kind == .transfers && $0.transferConstraint == .maximumTransfers
            }) {
                rememberTransferValue(from: journeyOptions[index])
                journeyOptions[index].maximumTransfers = 0
            } else {
                var directOption = makeJourneyOptionEntry(kind: .transfers)
                directOption.transferConstraint = .maximumTransfers
                directOption.maximumTransfers = 0
                journeyOptions.append(directOption)
            }
        } else if let directOption = journeyOptions.first(where: \.isZeroTransferLimit) {
            removeJourneyOption(id: directOption.id)
        }
    }

    /// Treats zero transfers as the direct-only shortcut; positive values continue editing the visible condition.
    func setMaximumTransfers(_ value: Int, for id: JourneyOptionEntry.ID) {
        guard supportsConnectionOption(.maximumTransfers),
              let index = journeyOptions.firstIndex(where: { $0.id == id }),
              journeyOptions[index].kind == .transfers,
              journeyOptions[index].transferConstraint == .maximumTransfers
        else {
            return
        }

        let clampedValue = min(
            max(value, Self.maximumTransferRange.lowerBound),
            Self.maximumTransferRange.upperBound
        )
        if clampedValue == 0 {
            rememberTransferValue(from: journeyOptions[index])
            journeyOptions[index].maximumTransfers = 0
            removeTransferTimeConditions()
            if supportsOnlyDirect {
                setOnlyDirect(true)
            } else {
                onlyDirect = false
            }
            return
        }

        onlyDirect = false
        journeyOptions[index].maximumTransfers = clampedValue
        rememberedTransferValues.maximumTransfers = clampedValue
    }

    func search() async {
        let enteredDeparture = from.trimmingCharacters(in: .whitespacesAndNewlines)
        let enteredArrival = to.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !enteredDeparture.isEmpty, !enteredArrival.isEmpty else {
            errorMessage = AppLocalization.string("Enter both a departure and an arrival place.")
            return
        }
        if let endpointValidationMessage {
            connections = []
            resultPage = nil
            errorMessage = endpointValidationMessage
            return
        }

        usesCurrentDateAndTime = false
        isSearching = true
        errorMessage = nil
        resultPage = nil
        defer {
            hasCompletedSearch = true
            isSearching = false
        }

        let typedCurrentLocationEndpoints = manuallyEnteredCurrentLocationEndpoints
        if !typedCurrentLocationEndpoints.isEmpty,
           !(await resolveCurrentLocation(for: typedCurrentLocationEndpoints)) {
            connections = []
            return
        }

        let departure = from.trimmingCharacters(in: .whitespacesAndNewlines)
        let arrival = to.trimmingCharacters(in: .whitespacesAndNewlines)
        let requestedViaEntries = journeyOptions.compactMap {
            option -> (place: String, selection: TransitPlaceSelection?)? in
            guard supportsConnectionOption(.via), option.kind == .via else {
                return nil
            }
            let place = option.viaPlace.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !place.isEmpty else { return nil }
            let selection = option.viaSelection?.text == place
                ? option.viaSelection?.placeSelection
                : nil
            return (place, selection)
        }
        let requestedViaSelections = requestedViaEntries.isEmpty
            ? nil
            : requestedViaEntries.map(\.selection)
        let requestedMaximumTransfers = supportsConnectionOption(.maximumTransfers)
            ? maximumTransfers
            : nil
        let requestsOnlyDirect = supportsOnlyDirect && onlyDirect
        let requestHasNoTransfers = requestsOnlyDirect || requestedMaximumTransfers == 0
        let request = TransitConnectionRequest(
            timetable: timetable,
            from: departure,
            to: arrival,
            fromSelection: fromSelection?.text == departure ? fromSelection?.placeSelection : nil,
            toSelection: toSelection?.text == arrival ? toSelection?.placeSelection : nil,
            serviceDate: TransitRequestFormatting.serviceDate(from: date),
            serviceTime: TransitRequestFormatting.serviceTime(from: time),
            isArrival: isArrival,
            onlyDirect: requestsOnlyDirect,
            via: requestedViaEntries.map(\.place),
            viaSelections: requestedViaSelections,
            maxTransfers: requestedMaximumTransfers,
            minimumTransferTime: requestHasNoTransfers ||
                !supportsConnectionOption(.minimumTransferTime)
                ? nil : minimumTransferTime,
            maximumTransferTime: requestHasNoTransfers ||
                !supportsConnectionOption(.maximumTransferTime)
                ? nil : maximumTransferTime,
            maximumWalkingTime: supportsConnectionOption(.maximumWalkingTime)
                ? maximumWalkingTime : nil,
            maximumCityWalkingTime: supportsConnectionOption(.maximumCityWalkingTime)
                ? maximumCityWalkingTime : nil,
            walkToNearbyStops: supportsConnectionOption(.walkToNearbyStops)
                ? walkToNearbyStops : nil,
            sameNameWalkingTransfersOnly: supportsConnectionOption(.sameNameWalkingTransfersOnly)
                ? sameNameWalkingTransfersOnly : nil,
            wheelchairAccessibleConnectionsOnly: supportsConnectionOption(.wheelchairAccessibleConnectionsOnly)
                ? wheelchairAccessibleConnectionsOnly : nil,
            lowFloorConnectionsOnly: supportsConnectionOption(.lowFloorConnectionsOnly)
                ? lowFloorConnectionsOnly : nil,
            preferTrainsOverBuses: supportsConnectionOption(.preferTrainsOverBuses)
                ? preferTrainsOverBuses : nil,
            trainConnectionsForWheelchairPassengers: supportsConnectionOption(
                .trainConnectionsForWheelchairPassengers
            )
                ? trainConnectionsForWheelchairPassengers : nil,
            trainConnectionsForPassengersWithChildren: supportsConnectionOption(
                .trainConnectionsForPassengersWithChildren
            )
                ? trainConnectionsForPassengersWithChildren : nil,
            connectionsForPassengersWithBicycles: supportsConnectionOption(
                .connectionsForPassengersWithBicycles
            )
                ? connectionsForPassengersWithBicycles : nil,
            preferBusyRoutes: supportsConnectionOption(.preferBusyRoutes)
                ? preferBusyRoutes : nil,
            bedOrCouchettePreference: supportsConnectionOption(.bedOrCouchettePreference)
                ? bedOrCouchettePreference : nil,
            resultLimit: 10
        )

        do {
            let page = try await client.findConnectionsPage(
                request: request,
                language: AppLanguagePreference.transitLanguage
            )
            connections = page.connections
            resultPage = page
        } catch {
            connections = []
            errorMessage = AppErrorPresentation.message(for: error)
        }
    }

    /// Builds a fresh row with the most recently chosen transfer values ready for a later kind selection.
    private func makeJourneyOptionEntry(
        id: JourneyOptionEntry.ID = UUID(),
        kind: JourneyOptionKind = .via
    ) -> JourneyOptionEntry {
        var option = JourneyOptionEntry(
            id: id,
            kind: kind,
            maximumTransfers: rememberedTransferValues.maximumTransfers,
            minimumTransferTime: rememberedTransferValues.minimumTransferTime,
            maximumTransferTime: rememberedTransferValues.maximumTransferTime
        )
        if kind == .transfers,
           let constraint = availableTransferConstraints(excluding: nil).first {
            option.transferConstraint = constraint
        }
        if kind == .walkingDistances,
           let constraint = availableWalkingDistanceConstraints(excluding: nil).first {
            option.walkingDistanceConstraint = constraint
        }
        if kind == .walkingTransfer,
           let policy = availableWalkingTransferPolicies(excluding: nil).first {
            option.walkingTransferPolicy = policy
        }
        if kind == .onlyConnections,
           let requirement = availableConnectionRequirements(excluding: nil).first {
            option.connectionRequirement = requirement
        }
        if kind == .preference,
           let preference = availableJourneyPreferences(excluding: nil).first {
            option.preference = preference
        }
        return option
    }

    private var availableJourneyOptionKindsForNewRow: JourneyOptionKind? {
        supportedJourneyOptionKinds.first { kind in
            canUseJourneyOptionKind(kind, excluding: nil)
        }
    }

    /// Treats each combined subchoice as unique even though its parent row kind is repeatable.
    private func canUseJourneyOptionKind(
        _ kind: JourneyOptionKind,
        excluding id: JourneyOptionEntry.ID?
    ) -> Bool {
        if kind == .transfers {
            return !availableTransferConstraints(excluding: id).isEmpty
        }
        if kind == .walkingDistances {
            return !availableWalkingDistanceConstraints(excluding: id).isEmpty
        }
        if kind == .walkingTransfer {
            return !availableWalkingTransferPolicies(excluding: id).isEmpty
        }
        if kind == .onlyConnections {
            return !availableConnectionRequirements(excluding: id).isEmpty
        }
        if kind == .preference {
            return !availableJourneyPreferences(excluding: id).isEmpty
        }
        return kind.allowsMultiple || !journeyOptions.contains { option in
            option.id != id && option.kind == kind
        }
    }

    private func availableTransferConstraints(
        excluding id: JourneyOptionEntry.ID?
    ) -> [JourneyTransferConstraint] {
        supportedTransferConstraints.filter { constraint in
            (!hasNoTransfers || !constraint.isTransferTimeConstraint) &&
                !journeyOptions.contains { option in
                    option.id != id && option.kind == .transfers &&
                        option.transferConstraint == constraint
                }
        }
    }

    private func availableWalkingDistanceConstraints(
        excluding id: JourneyOptionEntry.ID?
    ) -> [JourneyWalkingDistanceConstraint] {
        supportedWalkingDistanceConstraints.filter { constraint in
            !journeyOptions.contains { option in
                option.id != id && option.kind == .walkingDistances &&
                    option.walkingDistanceConstraint == constraint
            }
        }
    }

    private func availableWalkingTransferPolicies(
        excluding id: JourneyOptionEntry.ID?
    ) -> [JourneyWalkingTransferPolicy] {
        supportedWalkingTransferPolicies.filter { policy in
            !journeyOptions.contains { option in
                option.id != id && option.kind == .walkingTransfer &&
                    option.walkingTransferPolicy == policy
            }
        }
    }

    private func availableJourneyPreferences(
        excluding id: JourneyOptionEntry.ID?
    ) -> [JourneyPreference] {
        supportedJourneyPreferences.filter { preference in
            !journeyOptions.contains { option in
                option.id != id && option.kind == .preference && option.preference == preference
            }
        }
    }

    private func availableConnectionRequirements(
        excluding id: JourneyOptionEntry.ID?
    ) -> [JourneyConnectionRequirement] {
        supportedConnectionRequirements.filter { requirement in
            !journeyOptions.contains { option in
                option.id != id && option.kind == .onlyConnections &&
                    option.connectionRequirement == requirement
            }
        }
    }

    /// A combined requirement row activates its selected provider flag; absence leaves that flag unspecified.
    private func connectionRequirementIsSelected(
        _ requirement: JourneyConnectionRequirement
    ) -> Bool? {
        journeyOptions.contains { option in
            option.kind == .onlyConnections && option.connectionRequirement == requirement
        } ? true : nil
    }

    /// A combined preference row activates its selected provider flag; absence leaves that flag unspecified.
    private func journeyPreferenceIsSelected(_ preference: JourneyPreference) -> Bool? {
        journeyOptions.contains { option in
            option.kind == .preference && option.preference == preference
        } ? true : nil
    }

    /// Captures only a row's active transfer value so unrelated hidden defaults cannot overwrite remembered choices.
    private func rememberTransferValue(from option: JourneyOptionEntry) {
        guard option.kind == .transfers else { return }
        switch option.transferConstraint {
        case .maximumTransfers:
            if option.maximumTransfers > 0 {
                rememberedTransferValues.maximumTransfers = option.maximumTransfers
            }
        case .minimumTransferTime:
            rememberedTransferValues.minimumTransferTime = option.minimumTransferTime
        case .maximumTransferTime:
            rememberedTransferValues.maximumTransferTime = option.maximumTransferTime
        }
    }

    /// Hydrates a row before it becomes one of the mutually exclusive transfer conditions.
    private func restoreRememberedTransferValues(at index: Int) {
        journeyOptions[index].maximumTransfers = rememberedTransferValues.maximumTransfers
        journeyOptions[index].minimumTransferTime = rememberedTransferValues.minimumTransferTime
        journeyOptions[index].maximumTransferTime = rememberedTransferValues.maximumTransferTime
    }

    /// Removes both transfer-time conditions made meaningless by direct-only mode without forgetting their values.
    private func removeTransferTimeConditions() {
        let removedOptions = journeyOptions.filter(\.isTransferTimeCondition)
        removedOptions.forEach(rememberTransferValue)
        journeyOptions.removeAll(where: \.isTransferTimeCondition)
    }

    /// Removes conditions that IDOS does not publish for the newly selected timetable.
    private func removeJourneyOptionsUnavailableForCurrentTimetable() {
        let unavailableOptionIDs = journeyOptions.compactMap { option in
            supportsJourneyOption(option) ? nil : option.id
        }
        unavailableOptionIDs.forEach { removeJourneyOption(id: $0) }
        if !supportsOnlyDirect {
            onlyDirect = false
        }
    }

    private func supportsJourneyOption(_ option: JourneyOptionEntry) -> Bool {
        if option.kind == .transfers {
            return supportsConnectionOption(option.transferConstraint.transitConnectionOption)
        }
        if option.kind == .walkingDistances {
            return supportsConnectionOption(option.walkingDistanceConstraint.transitConnectionOption)
        }
        if option.kind == .walkingTransfer {
            return supportsConnectionOption(option.walkingTransferPolicy.transitConnectionOption)
        }
        if option.kind == .onlyConnections {
            return supportsConnectionOption(option.connectionRequirement.transitConnectionOption)
        }
        if option.kind == .preference {
            return supportsConnectionOption(option.preference.transitConnectionOption)
        }
        return option.kind.transitConnectionOptions.contains(where: supportsConnectionOption)
    }

    /// Resolves provider support against the timetable currently represented by this form.
    private func supportsConnectionOption(_ option: TransitConnectionOption) -> Bool {
        client.supportsConnectionOption(option, for: timetable)
    }

    /// Treats either date or time editing as one deliberate journey-time choice that must remain stable.
    private func stopFollowingCurrentDateAndTime() {
        guard !isRefreshingCurrentDateAndTime, usesCurrentDateAndTime else { return }
        usesCurrentDateAndTime = false
    }

    /// Rejects only the same exact IDOS object, while preserving distinct same-named place choices.
    private func endpointsReferToSamePlace(departure: String, arrival: String) -> Bool {
        if let fromSelection, let toSelection {
            if fromSelection.isCurrentLocation, toSelection.isCurrentLocation {
                return true
            }
            return fromSelection.placeSelection.dataSourceID == toSelection.placeSelection.dataSourceID &&
                fromSelection.placeSelection.identifier == toSelection.placeSelection.identifier
        }
        return departure.localizedCaseInsensitiveCompare(arrival) == .orderedSame
    }

    /// Treats the exact localized `My location` phrase as an explicit location request when searching.
    private var manuallyEnteredCurrentLocationEndpoints: [ConnectionEndpoint] {
        guard canFillCurrentLocation else { return [] }
        let locationText = AppLocalization.string("My location")
        var endpoints: [ConnectionEndpoint] = []

        if fromSelection == nil, matchesCurrentLocationText(from, localizedText: locationText) {
            endpoints.append(.from)
        }
        if toSelection == nil, matchesCurrentLocationText(to, localizedText: locationText) {
            endpoints.append(.to)
        }
        return endpoints
    }

    private func matchesCurrentLocationText(_ value: String, localizedText: String) -> Bool {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
            .localizedCaseInsensitiveCompare(localizedText) == .orderedSame
    }

    /// Resolves one coordinate once and applies it to every endpoint requested by the same user action.
    private func resolveCurrentLocation(for endpoints: [ConnectionEndpoint]) async -> Bool {
        guard canFillCurrentLocation,
              let firstEndpoint = endpoints.first,
              locatingEndpoint == nil
        else {
            return false
        }

        locatingEndpoint = firstEndpoint
        errorMessage = nil
        defer { locatingEndpoint = nil }

        do {
            let coordinate = try await currentLocationProvider.currentLocation()
            let text = AppLocalization.string("My location")
            let selection = PlaceFieldSelection(
                placeSelection: try client.coordinatePlaceSelection(
                    text: text,
                    latitude: coordinate.latitude,
                    longitude: coordinate.longitude,
                    timetable: timetable
                ),
                kind: nil
            )

            for endpoint in endpoints {
                switch endpoint {
                case .from:
                    from = text
                    fromSelection = selection
                case .to:
                    to = text
                    toSelection = selection
                }
            }
            return true
        } catch {
            errorMessage = CurrentLocationErrorPresentation.message(for: error)
            return false
        }
    }

    /// Repeats the submitted query to replace stale results and establish fresh IDOS paging state.
    func refresh() async {
        await search()
    }

    /// Extends the submitted connection search at the selected chronological edge without replacing results.
    func loadMore(_ direction: TransitPageDirection) async {
        guard let resultPage,
              (direction == .earlier ? canLoadEarlier : canLoadLater)
        else {
            return
        }

        if direction == .earlier {
            isLoadingEarlier = true
        } else {
            isLoadingLater = true
        }
        errorMessage = nil
        defer {
            isLoadingEarlier = false
            isLoadingLater = false
        }

        do {
            let page = try await client.findConnectionsPage(from: resultPage, direction: direction)
            self.resultPage = page
            merge(page.connections, direction: direction)
        } catch {
            errorMessage = AppErrorPresentation.message(for: error)
        }
    }

    private func merge(_ additionalConnections: [TransitConnection], direction: TransitPageDirection) {
        let knownIDs = Set(connections.map(\.appIdentity))
        let uniqueConnections = additionalConnections.filter { !knownIDs.contains($0.appIdentity) }
        if direction == .earlier {
            connections.insert(contentsOf: uniqueConnections, at: 0)
        } else {
            connections.append(contentsOf: uniqueConnections)
        }
    }

    /// Downloads the localized IDOS message and attachments before opening an unsent draft in Mail.
    func composeEmailInMail(for connection: TransitConnection) async {
        guard processingEmailConnectionID == nil else { return }

        processingEmailConnectionID = connection.appIdentity
        errorMessage = nil
        defer { processingEmailConnectionID = nil }

        do {
            let draft = try await ConnectionEmailMailDraft.prepare(
                connection: connection,
                timetable: connection.appTimetable(in: client.timetables),
                language: AppLanguagePreference.transitLanguage,
                client: client
            )
            guard !Task.isCancelled else { return }
            try emailMailComposer.compose(draft)
        } catch {
            guard !Task.isCancelled else { return }
            errorMessage = AppErrorPresentation.message(for: error)
        }
    }

    /// Fetches one native IDOS calendar and either opens it or lets the user retain its ICS file.
    func performCalendarAction(
        _ action: CalendarExportAction,
        for connection: TransitConnection
    ) async {
        processingCalendarConnectionID = connection.appIdentity
        errorMessage = nil
        defer { processingCalendarConnectionID = nil }

        do {
            let calendar = try await client.connectionCalendar(
                for: connection,
                timetable: connection.appTimetable(in: client.timetables),
                language: AppLanguagePreference.transitLanguage
            )
            switch action {
            case .addToCalendar:
                try calendarImporter.open(calendarText: calendar)
            case .download:
                try calendarSaver.save(
                    calendarText: calendar,
                    suggestedFileName: CalendarExportFileName.connection(
                        from: connection.departureStation,
                        to: connection.arrivalStation
                    )
                )
            }
        } catch {
            errorMessage = AppErrorPresentation.message(for: error)
        }
    }

    /// Fetches one native IDOS PDF and either opens it in Preview or lets the user retain its file.
    func performPDFAction(
        _ action: PDFExportAction,
        for connection: TransitConnection
    ) async {
        processingPDFConnectionID = connection.appIdentity
        errorMessage = nil
        defer { processingPDFConnectionID = nil }

        do {
            let data = try await client.connectionPDF(
                for: connection,
                timetable: connection.appTimetable(in: client.timetables),
                language: AppLanguagePreference.transitLanguage
            )
            let fileName = PDFExportFileName.connection(
                from: connection.departureStation,
                to: connection.arrivalStation
            )
            switch action {
            case .openInPreview:
                try await pdfOpener.open(pdfData: data, suggestedFileName: fileName)
            case .download:
                try await pdfExporter.save(pdfData: data, suggestedFileName: fileName)
            }
        } catch {
            errorMessage = AppErrorPresentation.message(for: error)
        }
    }
}
