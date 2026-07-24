import Foundation
import Kastan

/// Identifies the value editor shown by one extensible journey-option row.
enum JourneyOptionKind: String, CaseIterable, Identifiable {
    case via
    case maximumTransfers

    var id: Self { self }

    /// Uses the same product wording in the picker and its corresponding editor.
    var localizedTitle: String {
        switch self {
        case .via:
            AppLocalization.string("Via")
        case .maximumTransfers:
            AppLocalization.string("Maximum number of transfers")
        }
    }

    /// Intermediate places can form an ordered route, while a transfer ceiling is unique.
    var allowsMultiple: Bool {
        self == .via
    }
}

/// Stores one independently editable condition in the journey-options builder.
struct JourneyOptionEntry: Identifiable, Equatable {
    let id: UUID
    var kind: JourneyOptionKind
    var viaPlace: String
    var maximumTransfers: Int

    init(
        id: UUID = UUID(),
        kind: JourneyOptionKind = .via,
        viaPlace: String = "",
        maximumTransfers: Int = 4
    ) {
        self.id = id
        self.kind = kind
        self.viaPlace = viaPlace
        self.maximumTransfers = maximumTransfers
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
        }
    }
    @Published var date = Date()
    @Published var time = Date()
    @Published var isArrival = false
    @Published private(set) var connections: [IDOSConnection] = []
    @Published private(set) var isSearching = false
    @Published private(set) var isLoadingEarlier = false
    @Published private(set) var isLoadingLater = false
    @Published private(set) var importingConnectionID: String?
    @Published private(set) var exportingPDFConnectionID: String?
    @Published private(set) var locatingEndpoint: ConnectionEndpoint?
    @Published var errorMessage: String?

    let client: any IDOSClienting
    private let calendarImporter: any CalendarImporting
    private let pdfExporter: any PDFExporting
    private let currentLocationProvider: any CurrentLocationProviding
    private var resultPage: IDOSConnectionPage?

    init(
        client: any IDOSClienting,
        calendarImporter: any CalendarImporting = WorkspaceCalendarImporter(),
        pdfExporter: any PDFExporting = WorkspacePDFExporter(),
        currentLocationProvider: any CurrentLocationProviding = SystemCurrentLocationProvider()
    ) {
        self.client = client
        self.calendarImporter = calendarImporter
        self.pdfExporter = pdfExporter
        self.currentLocationProvider = currentLocationProvider
    }

    var canSearch: Bool {
        !from.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !to.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !isSearching && !isLoadingEarlier && !isLoadingLater && locatingEndpoint == nil
    }

    var canLoadEarlier: Bool {
        !connections.isEmpty && resultPage?.canLoadEarlier == true && !isSearching && !isLoadingLater
    }

    var canLoadLater: Bool {
        !connections.isEmpty && resultPage?.canLoadLater == true && !isSearching && !isLoadingEarlier
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

    func search() async {
        guard !from.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !to.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            errorMessage = AppLocalization.string("Enter both a departure and an arrival place.")
            return
        }

        isSearching = true
        errorMessage = nil
        resultPage = nil
        defer { isSearching = false }

        let typedCurrentLocationEndpoints = manuallyEnteredCurrentLocationEndpoints
        if !typedCurrentLocationEndpoints.isEmpty,
           !(await resolveCurrentLocation(for: typedCurrentLocationEndpoints)) {
            connections = []
            return
        }

        let departure = from.trimmingCharacters(in: .whitespacesAndNewlines)
        let arrival = to.trimmingCharacters(in: .whitespacesAndNewlines)
        let requestedViaPlaces = viaPlaceNames
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
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
            via: requestedViaPlaces,
            maxTransfers: requestedMaximumTransfers,
            resultLimit: 10
        )

        do {
            let page = try await client.findConnectionsPage(request: request)
            connections = page.connections
            resultPage = page
        } catch {
            connections = []
            errorMessage = AppErrorPresentation.message(for: error)
        }
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

    func addToCalendar(_ connection: IDOSConnection) async {
        importingConnectionID = connection.id
        errorMessage = nil
        defer { importingConnectionID = nil }

        do {
            let calendar = try await client.connectionCalendar(for: connection, timetable: timetable)
            try calendarImporter.open(calendarText: calendar)
        } catch {
            errorMessage = AppErrorPresentation.message(for: error)
        }
    }

    /// Downloads the native IDOS PDF and lets the user choose its destination through macOS.
    func saveAsPDF(_ connection: IDOSConnection) async {
        exportingPDFConnectionID = connection.id
        errorMessage = nil
        defer { exportingPDFConnectionID = nil }

        do {
            let data = try await client.connectionPDF(
                for: connection,
                timetable: timetable,
                language: AppLanguagePreference.idosLanguage
            )
            try await pdfExporter.save(
                pdfData: data,
                suggestedFileName: PDFExportFileName.connection(
                    from: connection.departureStation,
                    to: connection.arrivalStation
                )
            )
        } catch {
            errorMessage = AppErrorPresentation.message(for: error)
        }
    }
}
