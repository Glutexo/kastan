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
    /// Exact IDOS choices retained only while their corresponding visible text is unchanged.
    @Published var fromSelection: PlaceFieldSelection?
    @Published var toSelection: PlaceFieldSelection?
    @Published var journeyOptions = [JourneyOptionEntry()]
    @Published var timetable = AppTimetableDefaults.search {
        didSet {
            guard timetable.slug != oldValue.slug else { return }
            if fromSelection?.isCurrentLocation != true {
                fromSelection = nil
            }
            if toSelection?.isCurrentLocation != true {
                toSelection = nil
            }
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
    @Published private(set) var connections: [IDOSConnection] = []
    @Published private(set) var hasCompletedSearch = false
    @Published private(set) var isSearching = false
    @Published private(set) var isLoadingEarlier = false
    @Published private(set) var isLoadingLater = false
    @Published private(set) var processingEmailConnectionID: String?
    @Published private(set) var processingCalendarConnectionID: String?
    @Published private(set) var processingPDFConnectionID: String?
    @Published private(set) var locatingEndpoint: ConnectionEndpoint?
    @Published var errorMessage: String?

    let client: any IDOSClienting
    private let calendarImporter: any CalendarImporting
    private let calendarSaver: any CalendarSaving
    private let pdfOpener: any PDFOpening
    private let pdfExporter: any PDFExporting
    private let emailMailComposer: any ConnectionEmailMailComposing
    private let currentLocationProvider: any CurrentLocationProviding
    private var resultPage: IDOSConnectionPage?
    private var isRefreshingCurrentDateAndTime = false

    init(
        client: any IDOSClienting,
        calendarImporter: any CalendarImporting = WorkspaceCalendarImporter(),
        calendarSaver: any CalendarSaving = WorkspaceCalendarSaver(),
        pdfOpener: any PDFOpening = WorkspacePDFOpener(),
        pdfExporter: any PDFExporting = WorkspacePDFExporter(),
        emailMailComposer: any ConnectionEmailMailComposing = WorkspaceConnectionEmailMailComposer(),
        currentLocationProvider: any CurrentLocationProviding = SystemCurrentLocationProvider()
    ) {
        self.client = client
        self.calendarImporter = calendarImporter
        self.calendarSaver = calendarSaver
        self.pdfOpener = pdfOpener
        self.pdfExporter = pdfExporter
        self.emailMailComposer = emailMailComposer
        self.currentLocationProvider = currentLocationProvider
    }

    var canSearch: Bool {
        !from.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !to.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            endpointValidationMessage == nil && !isSearching && !isLoadingEarlier &&
            !isLoadingLater && locatingEndpoint == nil
    }

    var canLoadEarlier: Bool {
        !connections.isEmpty && resultPage?.canLoadEarlier == true && !isSearching && !isLoadingLater
    }

    var canLoadLater: Bool {
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

    /// Returns the single visible transfer ceiling, or `nil` when that condition was not selected.
    var maximumTransfers: Int? {
        journeyOptions.first { $0.kind == .maximumTransfers }?.maximumTransfers
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

    /// Mirrors the direct-connection shortcut with the equivalent zero-transfer journey condition.
    var onlyDirect: Bool {
        maximumTransfers == 0
    }

    /// Presents the explicit transfer ceiling, or IDOS's four-transfer default, in the summary.
    var transferLimitLabel: String {
        let transferLimit = maximumTransfers ?? Self.defaultMaximumTransfers
        if transferLimit == 0 {
            return AppLocalization.string("Direct only")
        }
        return AppLocalization.plural("Up to %lld transfers", count: transferLimit)
    }

    func swapEndpoints() {
        let previousFrom = from
        let previousFromSelection = fromSelection
        from = to
        fromSelection = toSelection
        to = previousFrom
        toSelection = previousFromSelection
    }

    /// Fills one endpoint with the localized IDOS `My location` object after an explicit shortcut action.
    func fillCurrentLocation(in endpoint: ConnectionEndpoint) async {
        _ = await resolveCurrentLocation(for: [endpoint])
    }

    /// Keeps each picker limited to repeatable conditions and currently unused singleton conditions.
    func availableJourneyOptionKinds(for id: JourneyOptionEntry.ID) -> [JourneyOptionKind] {
        JourneyOptionKind.allCases.filter { kind in
            kind.allowsMultiple || !journeyOptions.contains { option in
                option.id != id && option.kind == kind
            }
        }
    }

    /// Inserts a new, immediately editable condition directly after the selected row.
    func addJourneyOption(after id: JourneyOptionEntry.ID) {
        guard let index = journeyOptions.firstIndex(where: { $0.id == id }) else { return }
        journeyOptions.insert(JourneyOptionEntry(), at: index + 1)
    }

    /// Removes the selected condition while retaining one empty row for future input.
    func removeJourneyOption(id: JourneyOptionEntry.ID) {
        guard let index = journeyOptions.firstIndex(where: { $0.id == id }) else { return }
        if journeyOptions.count == 1 {
            journeyOptions[0] = JourneyOptionEntry(id: id)
        } else {
            journeyOptions.remove(at: index)
        }
    }

    /// Applies the direct shortcut without exposing the journey-options editor or creating duplicate limits.
    func setOnlyDirect(_ onlyDirect: Bool) {
        if onlyDirect {
            if let index = journeyOptions.firstIndex(where: { $0.kind == .maximumTransfers }) {
                journeyOptions[index].maximumTransfers = 0
            } else {
                journeyOptions.append(
                    JourneyOptionEntry(kind: .maximumTransfers, maximumTransfers: 0)
                )
            }
        } else if let option = journeyOptions.first(where: {
            $0.kind == .maximumTransfers && $0.maximumTransfers == 0
        }) {
            removeJourneyOption(id: option.id)
        }
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
            option -> (place: String, selection: IDOSPlaceSelection?)? in
            guard option.kind == .via else { return nil }
            let place = option.viaPlace.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !place.isEmpty else { return nil }
            let selection = option.viaSelection?.text == place
                ? option.viaSelection?.idosSelection
                : nil
            return (place, selection)
        }
        let requestedViaSelections = requestedViaEntries.isEmpty
            ? nil
            : requestedViaEntries.map(\.selection)
        let requestedMaximumTransfers = maximumTransfers
        let request = IDOSConnectionRequest(
            timetable: timetable,
            from: departure,
            to: arrival,
            fromSelection: fromSelection?.text == departure ? fromSelection?.idosSelection : nil,
            toSelection: toSelection?.text == arrival ? toSelection?.idosSelection : nil,
            date: IDOSRequestFormatting.date(from: date),
            time: IDOSRequestFormatting.time(from: time),
            isArrival: isArrival,
            onlyDirect: requestedMaximumTransfers == 0,
            via: requestedViaEntries.map(\.place),
            viaSelections: requestedViaSelections,
            maxTransfers: requestedMaximumTransfers,
            minimumTransferTime: minimumTransferTime,
            maximumTransferTime: maximumTransferTime,
            maximumWalkingTime: maximumWalkingTime,
            maximumCityWalkingTime: maximumCityWalkingTime,
            walkToNearbyStops: walkToNearbyStops,
            sameNameWalkingTransfersOnly: sameNameWalkingTransfersOnly,
            resultLimit: 10
        )

        do {
            let page = try await client.findConnectionsPage(
                request: request,
                language: AppLanguagePreference.idosLanguage
            )
            connections = page.connections
            resultPage = page
        } catch {
            connections = []
            errorMessage = AppErrorPresentation.message(for: error)
        }
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
            return fromSelection.idosSelection.listID == toSelection.idosSelection.listID &&
                fromSelection.idosSelection.itemID == toSelection.idosSelection.itemID
        }
        return departure.localizedCaseInsensitiveCompare(arrival) == .orderedSame
    }

    /// Treats the exact localized `My location` phrase as an explicit location request when searching.
    private var manuallyEnteredCurrentLocationEndpoints: [ConnectionEndpoint] {
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
        guard let firstEndpoint = endpoints.first, locatingEndpoint == nil else { return false }

        locatingEndpoint = firstEndpoint
        errorMessage = nil
        defer { locatingEndpoint = nil }

        do {
            let coordinate = try await currentLocationProvider.currentLocation()
            let text = AppLocalization.string("My location")
            let selection = PlaceFieldSelection(
                idosSelection: IDOSPlaceSelection.currentLocation(
                    text: text,
                    latitude: coordinate.latitude,
                    longitude: coordinate.longitude
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
    func loadMore(_ direction: IDOSPageDirection) async {
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

    private func merge(_ additionalConnections: [IDOSConnection], direction: IDOSPageDirection) {
        let knownIDs = Set(connections.map(\.id))
        let uniqueConnections = additionalConnections.filter { !knownIDs.contains($0.id) }
        if direction == .earlier {
            connections.insert(contentsOf: uniqueConnections, at: 0)
        } else {
            connections.append(contentsOf: uniqueConnections)
        }
    }

    /// Downloads the localized IDOS message and attachments before opening an unsent draft in Mail.
    func composeEmailInMail(for connection: IDOSConnection) async {
        guard processingEmailConnectionID == nil else { return }

        processingEmailConnectionID = connection.id
        errorMessage = nil
        defer { processingEmailConnectionID = nil }

        do {
            let draft = try await ConnectionEmailMailDraft.prepare(
                connection: connection,
                timetable: timetable,
                language: AppLanguagePreference.idosLanguage,
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
        for connection: IDOSConnection
    ) async {
        processingCalendarConnectionID = connection.id
        errorMessage = nil
        defer { processingCalendarConnectionID = nil }

        do {
            let calendar = try await client.connectionCalendar(
                for: connection,
                timetable: timetable,
                language: AppLanguagePreference.idosLanguage
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
        for connection: IDOSConnection
    ) async {
        processingPDFConnectionID = connection.id
        errorMessage = nil
        defer { processingPDFConnectionID = nil }

        do {
            let data = try await client.connectionPDF(
                for: connection,
                timetable: timetable,
                language: AppLanguagePreference.idosLanguage
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
