import Foundation
import Kastan

/// Preserves one complete departure-board query while opening it in another main window or tab.
struct DepartureSearchSelection: Codable, Hashable {
    let timetable: TransitTimetable
    let station: String
    let serviceDate: TransitDate
    let serviceTime: TransitTime

    var dataSourceID: TransitDataSourceID { timetable.dataSourceID }

    func hash(into hasher: inout Hasher) {
        hasher.combine(timetable.dataSourceID)
        hasher.combine(timetable.identifier)
        hasher.combine(timetable.displayName)
        hasher.combine(station)
        hasher.combine(serviceDate)
        hasher.combine(serviceTime.hour)
        hasher.combine(serviceTime.minute)
    }
}

/// Builds departure-board queries from each level of a completed connection result.
enum DepartureSearchSelectionFactory {
    static func search(
        timetable: TransitTimetable,
        station: String,
        serviceDate: TransitDate,
        serviceTime: TransitTime,
        client: any TransitDataSource
    ) -> DepartureSearchSelection? {
        make(
            timetable: timetable,
            station: station,
            serviceDate: serviceDate,
            serviceTime: serviceTime,
            client: client
        )
    }

    /// Uses the result's matched origin and exact departure instant instead of the broader submitted search.
    static func connection(
        _ connection: TransitConnection,
        timetable: TransitTimetable,
        fallbackServiceDate: TransitDate?,
        client: any TransitDataSource
    ) -> DepartureSearchSelection? {
        make(
            timetable: timetable,
            station: connection.departureStation,
            serviceDate: connection.departureDate ?? fallbackServiceDate,
            serviceTime: TransitRequestFormatting.serviceTime(from: connection.departureTime),
            client: client
        )
    }

    /// Uses the concrete service's matched origin and own departure instant.
    static func service(
        _ leg: TransitConnectionLeg,
        in connection: TransitConnection,
        timetable: TransitTimetable,
        fallbackServiceDate: TransitDate?,
        client: any TransitDataSource
    ) -> DepartureSearchSelection? {
        make(
            timetable: timetable,
            station: leg.fromStation,
            serviceDate: leg.departureDate ?? connection.departureDate ?? fallbackServiceDate,
            serviceTime: TransitRequestFormatting.serviceTime(from: leg.departureTime),
            client: client
        )
    }

    private static func make(
        timetable requestedTimetable: TransitTimetable,
        station: String,
        serviceDate: TransitDate?,
        serviceTime: TransitTime?,
        client: any TransitDataSource
    ) -> DepartureSearchSelection? {
        let station = station.trimmingCharacters(in: .whitespacesAndNewlines)
        guard client.descriptor.supports(.departures),
              !station.isEmpty,
              let serviceDate,
              let serviceTime,
              let timetable = client.timetables.first(where: {
                  $0.appIdentity == requestedTimetable.appIdentity
              })
        else {
            return nil
        }

        return DepartureSearchSelection(
            timetable: timetable,
            station: station,
            serviceDate: serviceDate,
            serviceTime: serviceTime
        )
    }
}

/// Transfers one already resolved provider station-board result into Departures without repeating its request.
struct ResolvedDepartureSearch: Sendable {
    let request: TransitDeparturesRequest
    let page: TransitDeparturePage
    let dateAndTime: Date

    /// Accepts a transfer only when its request and provider-owned page belong to the same source.
    var dataSourceID: TransitDataSourceID? {
        guard request.timetable.dataSourceID == page.dataSourceID else { return nil }
        return page.dataSourceID
    }
}

/// Retains resolved provider state just long enough for a value-based main-window scene to adopt it.
///
/// The scene value carries only the transfer identifier because provider paging continuations are deliberately opaque
/// and cannot be serialized. Keeping the original value in memory preserves those continuations without another
/// provider request; the scene discards the entry as soon as its workspace appears.
@MainActor
final class ResolvedDepartureSearchTransferStore {
    static let shared = ResolvedDepartureSearchTransferStore()

    private var searches: [UUID: ResolvedDepartureSearch] = [:]

    @discardableResult
    func store(_ search: ResolvedDepartureSearch) -> UUID {
        let id = UUID()
        searches[id] = search
        return id
    }

    func search(for id: UUID?) -> ResolvedDepartureSearch? {
        id.flatMap { searches[$0] }
    }

    func discard(_ id: UUID?) {
        guard let id else { return }
        searches.removeValue(forKey: id)
    }
}

/// Owns a station-board query for either departures or arrivals.
@MainActor
final class DeparturesViewModel: ObservableObject {
    @Published var station = "" {
        didSet {
            if let stationSelection, stationSelection.text != station {
                self.stationSelection = nil
            }
        }
    }
    /// The provider-owned station or stop, retained only while its visible text is unchanged.
    @Published var stationSelection: PlaceFieldSelection?
    @Published var timetable: TransitTimetable {
        didSet {
            guard timetable != oldValue else { return }
            stationSelection = nil
            rememberTimetable(timetable)
        }
    }
    @Published var date = Date() {
        didSet { stopFollowingCurrentDateAndTime() }
    }
    @Published var time = Date() {
        didSet { stopFollowingCurrentDateAndTime() }
    }
    /// Distinguishes the live current-moment default from a board instant deliberately chosen or submitted.
    @Published private(set) var usesCurrentDateAndTime = true
    @Published var isArrival = false
    /// Retains the passenger's summary-or-editor choice while the main window displays another search mode.
    @Published private(set) var isSearchFormCollapsed = false
    @Published private(set) var departures: [TransitDeparture] = []
    @Published private(set) var isSearching = false
    @Published private(set) var isLoadingEarlier = false
    @Published private(set) var isLoadingLater = false
    @Published var errorMessage: String?

    let client: any TransitDataSource
    private let rememberTimetable: (TransitTimetable) -> Void
    private var resultPage: TransitDeparturePage?
    private var isRefreshingCurrentDateAndTime = false
    private var hasPendingInitialSelection = false

    init(
        client: any TransitDataSource,
        initialSelection: DepartureSearchSelection? = nil,
        preferredTimetable: TransitTimetable? = nil,
        rememberTimetable: @escaping (TransitTimetable) -> Void = { _ in }
    ) {
        self.client = client
        self.rememberTimetable = rememberTimetable
        timetable = AppTimetableDefaults.search(
            in: client.timetables,
            defaultTimetable: client.defaultTimetable,
            preferredTimetable: preferredTimetable
        )

        if let initialSelection {
            _ = present(initialSelection)
        }
    }

    var timetables: [TransitTimetable] {
        client.timetables
    }

    var canSearch: Bool {
        !station.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !isSearching && !isLoadingEarlier && !isLoadingLater
    }

    var canLoadEarlier: Bool {
        client.descriptor.supports(.departurePaging) &&
            !departures.isEmpty && resultPage?.canLoadEarlier == true && !isSearching && !isLoadingLater
    }

    var canLoadLater: Bool {
        client.descriptor.supports(.departurePaging) &&
            !departures.isEmpty && resultPage?.canLoadLater == true && !isSearching && !isLoadingEarlier
    }

    /// Keeps the untouched station-board instant current while preserving every explicit choice.
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

    /// Replaces only the station-board date while retaining the deliberately selected time.
    func selectCurrentDate(now: Date = .now) {
        usesCurrentDateAndTime = false
        date = now
    }

    /// Replaces only the station-board time while retaining the deliberately selected date.
    func selectCurrentTime(now: Date = .now) {
        usesCurrentDateAndTime = false
        time = now
    }

    /// Replaces the editable station-board form and starts the transferred query when the view next appears.
    @discardableResult
    func present(_ selection: DepartureSearchSelection) -> Bool {
        guard selection.dataSourceID == client.descriptor.id,
              client.descriptor.supports(.departures),
              let selectedTimetable = timetables.first(where: {
                  $0.appIdentity == selection.timetable.appIdentity
              }),
              let dateAndTime = TransitRequestFormatting.displayDateAndTime(
                  serviceDate: selection.serviceDate,
                  serviceTime: selection.serviceTime
              )
        else {
            return false
        }

        timetable = selectedTimetable
        station = selection.station
        stationSelection = nil
        usesCurrentDateAndTime = false
        date = dateAndTime
        time = dateAndTime
        isArrival = false
        departures = []
        resultPage = nil
        isSearching = false
        isLoadingEarlier = false
        isLoadingLater = false
        errorMessage = nil
        hasPendingInitialSelection = true
        isSearchFormCollapsed = true
        return true
    }

    /// Presents a concrete departure lookup handed off by another search mode.
    func present(_ search: ResolvedDepartureSearch) {
        timetable = search.request.timetable
        station = search.request.station
        stationSelection = nil
        usesCurrentDateAndTime = false
        date = search.dateAndTime
        time = search.dateAndTime
        isArrival = false
        departures = search.page.departures
        resultPage = search.page
        isSearching = false
        isLoadingEarlier = false
        isLoadingLater = false
        errorMessage = nil
        hasPendingInitialSelection = false
        isSearchFormCollapsed = true
    }

    /// Starts a complete query carried by a connection result exactly once.
    func loadInitialSelectionIfNeeded() async {
        guard hasPendingInitialSelection else { return }
        hasPendingInitialSelection = false
        await search()
    }

    /// Indicates whether a complete transferred query is still waiting for its one automatic search.
    var startsWithInitialSelection: Bool {
        hasPendingInitialSelection
    }

    /// Replaces the submitted station-board editor with its compact result summary.
    func collapseSearchForm() {
        isSearchFormCollapsed = true
    }

    /// Restores the submitted station-board editor for deliberate query changes.
    func revealSearchForm() {
        isSearchFormCollapsed = false
    }

    func search() async {
        hasPendingInitialSelection = false
        let station = station.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !station.isEmpty else {
            errorMessage = AppLocalization.string("Enter a station or stop.")
            return
        }

        usesCurrentDateAndTime = false
        isSearching = true
        errorMessage = nil
        resultPage = nil
        defer { isSearching = false }

        let request = TransitDeparturesRequest(
            timetable: timetable,
            station: station,
            stationSelection: stationSelection?.text == station ? stationSelection?.placeSelection : nil,
            serviceDate: TransitRequestFormatting.serviceDate(from: date),
            serviceTime: TransitRequestFormatting.serviceTime(from: time),
            isArrival: isArrival
        )

        do {
            let page = try await client.findDeparturesPage(
                request: request,
                language: AppLanguagePreference.transitLanguage
            )
            departures = page.departures
            resultPage = page
        } catch {
            departures = []
            errorMessage = AppErrorPresentation.message(for: error)
        }
    }

    /// Extends the submitted station board at the selected chronological edge without replacing rows.
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
            let page = try await client.findDeparturesPage(from: resultPage, direction: direction)
            self.resultPage = page
            merge(page.departures, direction: direction)
        } catch {
            errorMessage = AppErrorPresentation.message(for: error)
        }
    }

    private func merge(_ additionalDepartures: [TransitDeparture], direction: TransitPageDirection) {
        let knownIDs = Set(departures.map(\.appIdentity))
        let uniqueDepartures = additionalDepartures.filter { !knownIDs.contains($0.appIdentity) }
        if direction == .earlier {
            departures.insert(contentsOf: uniqueDepartures, at: 0)
        } else {
            departures.append(contentsOf: uniqueDepartures)
        }
    }

    /// Treats either editor change as one deliberate station-board instant that must remain stable.
    private func stopFollowingCurrentDateAndTime() {
        guard !isRefreshingCurrentDateAndTime, usesCurrentDateAndTime else { return }
        usesCurrentDateAndTime = false
    }
}
