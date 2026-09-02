import Foundation
import Kastan

/// Identifies the value editor shown by one extensible journey-option row.
enum JourneyOptionKind: String, CaseIterable, Identifiable {
    case via
    case maximumTransfers
    case minimumTransferTime
    case maximumTransferTime
    case maximumWalkingTime
    case maximumCityWalkingTime
    case walkToNearbyStops
    case sameNameWalkingTransfersOnly

    var id: Self { self }

    /// Maps one product editor to the provider-neutral option advertised by a data source.
    var transitConnectionOption: TransitConnectionOption {
        switch self {
        case .via:
            .via
        case .maximumTransfers:
            .maximumTransfers
        case .minimumTransferTime:
            .minimumTransferTime
        case .maximumTransferTime:
            .maximumTransferTime
        case .maximumWalkingTime:
            .maximumWalkingTime
        case .maximumCityWalkingTime:
            .maximumCityWalkingTime
        case .walkToNearbyStops:
            .walkToNearbyStops
        case .sameNameWalkingTransfersOnly:
            .sameNameWalkingTransfersOnly
        }
    }

    /// Uses the same product wording in the picker and its corresponding editor.
    var localizedTitle: String {
        switch self {
        case .via:
            AppLocalization.string("Via")
        case .maximumTransfers:
            AppLocalization.string("Maximum number of transfers")
        case .minimumTransferTime:
            AppLocalization.string("Minimum transfer time")
        case .maximumTransferTime:
            AppLocalization.string("Maximum transfer time")
        case .maximumWalkingTime:
            AppLocalization.string("Maximum distance to walk")
        case .maximumCityWalkingTime:
            AppLocalization.string("Maximum distance to walk, if there is Urban Public Transport available")
        case .walkToNearbyStops:
            AppLocalization.string("Walk to a nearby stop at the beginning/end of journey")
        case .sameNameWalkingTransfersOnly:
            AppLocalization.string("Use transfers only between stops of the same name")
        }
    }

    /// Intermediate places can form an ordered route, while every IDOS transfer control is unique.
    var allowsMultiple: Bool {
        self == .via
    }

    /// Identifies conditions whose previous value should survive a temporary direct-only search.
    var usesRememberedTransferValue: Bool {
        switch self {
        case .maximumTransfers, .minimumTransferTime, .maximumTransferTime:
            true
        case .via, .maximumWalkingTime, .maximumCityWalkingTime,
             .walkToNearbyStops, .sameNameWalkingTransfersOnly:
            false
        }
    }

    /// Direct journeys have no transfer whose waiting time could be constrained.
    var isTransferTimeCondition: Bool {
        self == .minimumTransferTime || self == .maximumTransferTime
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
    var maximumTransfers: Int
    var minimumTransferTime: Int
    var maximumTransferTime: Int
    var maximumWalkingTime: Int
    var maximumCityWalkingTime: Int
    var walkToNearbyStops: Bool
    var sameNameWalkingTransfersOnly: Bool

    init(
        id: UUID = UUID(),
        kind: JourneyOptionKind = .via,
        viaPlace: String = "",
        viaSelection: PlaceFieldSelection? = nil,
        maximumTransfers: Int = 4,
        minimumTransferTime: Int = -1,
        maximumTransferTime: Int = 240,
        maximumWalkingTime: Int = 60,
        maximumCityWalkingTime: Int = 10,
        walkToNearbyStops: Bool = true,
        sameNameWalkingTransfersOnly: Bool = false
    ) {
        self.id = id
        self.kind = kind
        self.viaPlace = viaPlace
        self.viaSelection = viaSelection
        self.maximumTransfers = maximumTransfers
        self.minimumTransferTime = minimumTransferTime
        self.maximumTransferTime = maximumTransferTime
        self.maximumWalkingTime = maximumWalkingTime
        self.maximumCityWalkingTime = maximumCityWalkingTime
        self.walkToNearbyStops = walkToNearbyStops
        self.sameNameWalkingTransfersOnly = sameNameWalkingTransfersOnly
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
        // An empty via field is an inactive affordance. Every other editor carries a meaningful default value,
        // so sources without via support start with no row until the user explicitly adds a condition.
        journeyOptions = client.descriptor.connectionOptions.contains(.via)
            ? [JourneyOptionEntry(kind: .via)]
            : []
        timetable = AppTimetableDefaults.search(
            in: client.timetables,
            defaultTimetable: client.defaultTimetable
        )
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

    /// Limits the extensible editor to fields the selected provider promises to interpret.
    var supportedJourneyOptionKinds: [JourneyOptionKind] {
        JourneyOptionKind.allCases.filter {
            client.descriptor.connectionOptions.contains($0.transitConnectionOption)
        }
    }

    var supportsOnlyDirect: Bool {
        client.descriptor.connectionOptions.contains(.onlyDirect)
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
        return journeyOptions.first { $0.kind == .maximumTransfers }?.maximumTransfers
    }

    /// Returns each optional IDOS transfer control only while its row remains visible.
    var minimumTransferTime: Int? {
        journeyOptions.first { $0.kind == .minimumTransferTime }?.minimumTransferTime
    }

    var maximumTransferTime: Int? {
        journeyOptions.first { $0.kind == .maximumTransferTime }?.maximumTransferTime
    }

    var maximumWalkingTime: Int? {
        journeyOptions.first { $0.kind == .maximumWalkingTime }?.maximumWalkingTime
    }

    var maximumCityWalkingTime: Int? {
        journeyOptions.first { $0.kind == .maximumCityWalkingTime }?.maximumCityWalkingTime
    }

    var walkToNearbyStops: Bool? {
        journeyOptions.first { $0.kind == .walkToNearbyStops }?.walkToNearbyStops
    }

    var sameNameWalkingTransfersOnly: Bool? {
        journeyOptions.first { $0.kind == .sameNameWalkingTransfersOnly }?.sameNameWalkingTransfersOnly
    }

    /// Presents an active transfer ceiling, retaining only IDOS's established implicit four-transfer default.
    var transferLimitLabel: String {
        if hasNoTransfers {
            return AppLocalization.string("Direct only")
        }

        if let maximumTransfers,
           client.descriptor.connectionOptions.contains(.maximumTransfers) {
            return AppLocalization.plural("Up to %lld transfers", count: maximumTransfers)
        }

        guard client.descriptor.id == .idos,
              client.descriptor.connectionOptions.contains(.maximumTransfers)
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

    /// Keeps each picker limited to repeatable conditions and currently unused singleton conditions.
    func availableJourneyOptionKinds(for id: JourneyOptionEntry.ID) -> [JourneyOptionKind] {
        supportedJourneyOptionKinds.filter { kind in
            (!hasNoTransfers || !kind.isTransferTimeCondition) &&
                (kind.allowsMultiple || !journeyOptions.contains { option in
                    option.id != id && option.kind == kind
                })
        }
    }

    /// Applies a selected condition kind and restores the last value removed for transfer-related conditions.
    func setJourneyOptionKind(_ kind: JourneyOptionKind, for id: JourneyOptionEntry.ID) {
        guard supportedJourneyOptionKinds.contains(kind) else { return }
        guard let currentOption = journeyOptions.first(where: { $0.id == id }) else { return }
        guard currentOption.kind != kind else { return }

        if onlyDirect,
           currentOption.kind == .maximumTransfers,
           currentOption.maximumTransfers == 0 {
            onlyDirect = false
        } else if onlyDirect, kind.isTransferTimeCondition {
            setOnlyDirect(false)
        }

        guard let index = journeyOptions.firstIndex(where: { $0.id == id }) else { return }

        rememberTransferValue(from: currentOption)
        journeyOptions[index].kind = kind
        if kind.usesRememberedTransferValue {
            restoreRememberedTransferValues(at: index)
        }
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
        if onlyDirect,
           removedOption.kind == .maximumTransfers,
           removedOption.maximumTransfers == 0 {
            onlyDirect = false
        }
        if journeyOptions.count == 1 {
            if client.descriptor.connectionOptions.contains(.via) {
                journeyOptions[0] = makeJourneyOptionEntry(id: id, kind: .via)
            } else {
                journeyOptions.remove(at: index)
            }
        } else {
            journeyOptions.remove(at: index)
        }
    }

    /// Keeps the inactive sole via row stable while allowing an active provider-specific row to be removed.
    func canRemoveJourneyOption(id: JourneyOptionEntry.ID) -> Bool {
        guard journeyOptions.contains(where: { $0.id == id }) else { return false }
        return journeyOptions.count > 1 || !client.descriptor.connectionOptions.contains(.via)
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
            guard client.descriptor.connectionOptions.contains(.maximumTransfers) else { return }
            if let index = journeyOptions.firstIndex(where: { $0.kind == .maximumTransfers }) {
                rememberTransferValue(from: journeyOptions[index])
                journeyOptions[index].maximumTransfers = 0
            } else {
                var directOption = makeJourneyOptionEntry(kind: .maximumTransfers)
                directOption.maximumTransfers = 0
                journeyOptions.append(directOption)
            }
        } else if let directOption = journeyOptions.first(where: {
            $0.kind == .maximumTransfers && $0.maximumTransfers == 0
        }) {
            removeJourneyOption(id: directOption.id)
        }
    }

    /// Treats zero transfers as the direct-only shortcut; positive values continue editing the visible condition.
    func setMaximumTransfers(_ value: Int, for id: JourneyOptionEntry.ID) {
        guard client.descriptor.connectionOptions.contains(.maximumTransfers),
              let index = journeyOptions.firstIndex(where: { $0.id == id }),
              journeyOptions[index].kind == .maximumTransfers
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
            guard client.descriptor.connectionOptions.contains(.via), option.kind == .via else {
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
        let requestedMaximumTransfers = client.descriptor.connectionOptions.contains(.maximumTransfers)
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
                !client.descriptor.connectionOptions.contains(.minimumTransferTime)
                ? nil : minimumTransferTime,
            maximumTransferTime: requestHasNoTransfers ||
                !client.descriptor.connectionOptions.contains(.maximumTransferTime)
                ? nil : maximumTransferTime,
            maximumWalkingTime: client.descriptor.connectionOptions.contains(.maximumWalkingTime)
                ? maximumWalkingTime : nil,
            maximumCityWalkingTime: client.descriptor.connectionOptions.contains(.maximumCityWalkingTime)
                ? maximumCityWalkingTime : nil,
            walkToNearbyStops: client.descriptor.connectionOptions.contains(.walkToNearbyStops)
                ? walkToNearbyStops : nil,
            sameNameWalkingTransfersOnly: client.descriptor.connectionOptions
                .contains(.sameNameWalkingTransfersOnly)
                ? sameNameWalkingTransfersOnly : nil,
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
        JourneyOptionEntry(
            id: id,
            kind: kind,
            maximumTransfers: rememberedTransferValues.maximumTransfers,
            minimumTransferTime: rememberedTransferValues.minimumTransferTime,
            maximumTransferTime: rememberedTransferValues.maximumTransferTime
        )
    }

    private var availableJourneyOptionKindsForNewRow: JourneyOptionKind? {
        supportedJourneyOptionKinds.first { kind in
            (!hasNoTransfers || !kind.isTransferTimeCondition) &&
                (kind.allowsMultiple || !journeyOptions.contains { $0.kind == kind })
        }
    }

    /// Captures only a row's active transfer value so unrelated hidden defaults cannot overwrite remembered choices.
    private func rememberTransferValue(from option: JourneyOptionEntry) {
        switch option.kind {
        case .maximumTransfers:
            if option.maximumTransfers > 0 {
                rememberedTransferValues.maximumTransfers = option.maximumTransfers
            }
        case .minimumTransferTime:
            rememberedTransferValues.minimumTransferTime = option.minimumTransferTime
        case .maximumTransferTime:
            rememberedTransferValues.maximumTransferTime = option.maximumTransferTime
        case .via, .maximumWalkingTime, .maximumCityWalkingTime,
             .walkToNearbyStops, .sameNameWalkingTransfersOnly:
            break
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
        let removedOptions = journeyOptions.filter { $0.kind.isTransferTimeCondition }
        removedOptions.forEach(rememberTransferValue)
        journeyOptions.removeAll { $0.kind.isTransferTimeCondition }
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
