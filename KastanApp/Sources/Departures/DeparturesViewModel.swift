import Foundation
import Kastan

/// Preserves one complete departures-or-arrivals board query while opening it elsewhere.
struct DepartureSearchSelection: Codable, Hashable {
    let timetable: TransitTimetable
    let station: String
    let serviceDate: TransitDate
    let serviceTime: TransitTime
    let isArrival: Bool

    init(
        timetable: TransitTimetable,
        station: String,
        serviceDate: TransitDate,
        serviceTime: TransitTime,
        isArrival: Bool = false
    ) {
        self.timetable = timetable
        self.station = station
        self.serviceDate = serviceDate
        self.serviceTime = serviceTime
        self.isArrival = isArrival
    }

    var dataSourceID: TransitDataSourceID { timetable.dataSourceID }

    func hash(into hasher: inout Hasher) {
        hasher.combine(timetable.dataSourceID)
        hasher.combine(timetable.identifier)
        hasher.combine(timetable.displayName)
        hasher.combine(station)
        hasher.combine(serviceDate)
        hasher.combine(serviceTime.hour)
        hasher.combine(serviceTime.minute)
        hasher.combine(isArrival)
    }

    private enum CodingKeys: String, CodingKey {
        case timetable
        case station
        case serviceDate
        case serviceTime
        case isArrival
    }

    /// Keeps main-window values written before arrival transfers were added restorable as departures.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            timetable: try container.decode(TransitTimetable.self, forKey: .timetable),
            station: try container.decode(String.self, forKey: .station),
            serviceDate: try container.decode(TransitDate.self, forKey: .serviceDate),
            serviceTime: try container.decode(TransitTime.self, forKey: .serviceTime),
            isArrival: try container.decodeIfPresent(Bool.self, forKey: .isArrival) ?? false
        )
    }
}

/// Builds station-board queries from submitted searches and concrete provider results.
enum DepartureSearchSelectionFactory {
    static func search(
        timetable: TransitTimetable,
        station: String,
        serviceDate: TransitDate,
        serviceTime: TransitTime,
        isArrival: Bool = false,
        client: any TransitDataSource
    ) -> DepartureSearchSelection? {
        make(
            timetable: timetable,
            station: station,
            serviceDate: serviceDate,
            serviceTime: serviceTime,
            isArrival: isArrival,
            client: client
        )
    }

    /// Uses the matched endpoint and exact instant for the requested side of a concrete connection.
    static func connection(
        _ connection: TransitConnection,
        timetable: TransitTimetable,
        fallbackServiceDate: TransitDate?,
        isArrival: Bool = false,
        client: any TransitDataSource
    ) -> DepartureSearchSelection? {
        let departureDate = connection.departureDate ?? fallbackServiceDate
        return make(
            timetable: timetable,
            station: isArrival ? connection.arrivalStation : connection.departureStation,
            serviceDate: isArrival
                ? arrivalServiceDate(for: connection, fallbackServiceDate: fallbackServiceDate)
                : departureDate,
            serviceTime: TransitRequestFormatting.serviceTime(
                from: isArrival ? connection.arrivalTime : connection.departureTime
            ),
            isArrival: isArrival,
            client: client
        )
    }

    /// Uses the matched endpoint and exact instant for the requested side of a concrete service.
    static func service(
        _ leg: TransitConnectionLeg,
        in connection: TransitConnection,
        timetable: TransitTimetable,
        fallbackServiceDate: TransitDate?,
        isArrival: Bool = false,
        client: any TransitDataSource
    ) -> DepartureSearchSelection? {
        let departureDate = leg.departureDate ?? connection.departureDate ?? fallbackServiceDate
        return make(
            timetable: timetable,
            station: isArrival ? leg.toStation : leg.fromStation,
            serviceDate: isArrival
                ? arrivalServiceDate(
                    for: leg,
                    in: connection,
                    fallbackServiceDate: fallbackServiceDate
                )
                : departureDate,
            serviceTime: TransitRequestFormatting.serviceTime(
                from: isArrival ? leg.arrivalTime : leg.departureTime
            ),
            isArrival: isArrival,
            client: client
        )
    }

    /// Uses a station-board row's matched stop, displayed instant, and owning timetable.
    static func departure(
        _ departure: TransitDeparture,
        station: String,
        timetable: TransitTimetable,
        fallbackServiceDate: TransitDate?,
        client: any TransitDataSource
    ) -> DepartureSearchSelection? {
        make(
            timetable: timetable,
            station: station,
            serviceDate: departure.serviceDate ?? fallbackServiceDate,
            serviceTime: TransitRequestFormatting.serviceTime(from: departure.time),
            client: client
        )
    }

    private static func make(
        timetable requestedTimetable: TransitTimetable,
        station: String,
        serviceDate: TransitDate?,
        serviceTime: TransitTime?,
        isArrival: Bool = false,
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
            serviceTime: serviceTime,
            isArrival: isArrival
        )
    }

    /// Follows provider-supplied leg dates and displayed times to the connection's final civil day.
    private static func arrivalServiceDate(
        for connection: TransitConnection,
        fallbackServiceDate: TransitDate?
    ) -> TransitDate? {
        guard let lastLegIndex = connection.legs.indices.last else {
            return arrivalServiceDate(
                departureDate: connection.departureDate ?? fallbackServiceDate,
                departureTime: connection.departureTime,
                arrivalTime: connection.arrivalTime
            )
        }
        guard let finalLegDate = serviceDate(
            atArrivalOfLegAt: lastLegIndex,
            in: connection,
            fallbackServiceDate: fallbackServiceDate
        ) else {
            return nil
        }

        let finalLegTime = TransitRequestFormatting.serviceTime(
            from: connection.legs[lastLegIndex].arrivalTime
        )
        let connectionTime = TransitRequestFormatting.serviceTime(from: connection.arrivalTime)
        return crossesMidnight(from: finalLegTime, to: connectionTime)
            ? addingDays(1, to: finalLegDate)
            : finalLegDate
    }

    private static func arrivalServiceDate(
        for leg: TransitConnectionLeg,
        in connection: TransitConnection,
        fallbackServiceDate: TransitDate?
    ) -> TransitDate? {
        guard let legIndex = connection.legs.firstIndex(of: leg) else {
            return arrivalServiceDate(
                departureDate: leg.departureDate ?? connection.departureDate ?? fallbackServiceDate,
                departureTime: leg.departureTime,
                arrivalTime: leg.arrivalTime
            )
        }
        return serviceDate(
            atArrivalOfLegAt: legIndex,
            in: connection,
            fallbackServiceDate: fallbackServiceDate
        )
    }

    /// Walks the displayed route until one leg's arrival and honors any exact dates along the way.
    private static func serviceDate(
        atArrivalOfLegAt finalLegIndex: Int,
        in connection: TransitConnection,
        fallbackServiceDate: TransitDate?
    ) -> TransitDate? {
        guard connection.legs.indices.contains(finalLegIndex),
              var currentDate = connection.departureDate ?? fallbackServiceDate
        else {
            return nil
        }
        var previousTime = TransitRequestFormatting.serviceTime(from: connection.departureTime)

        for legIndex in connection.legs.indices where legIndex <= finalLegIndex {
            let leg = connection.legs[legIndex]
            let departureTime = TransitRequestFormatting.serviceTime(from: leg.departureTime)
            if let exactDate = leg.departureDate {
                currentDate = exactDate
            } else if crossesMidnight(from: previousTime, to: departureTime) {
                guard let nextDate = addingDays(1, to: currentDate) else { return nil }
                currentDate = nextDate
            }
            previousTime = departureTime ?? previousTime

            let arrivalTime = TransitRequestFormatting.serviceTime(from: leg.arrivalTime)
            if crossesMidnight(from: previousTime, to: arrivalTime) {
                guard let nextDate = addingDays(1, to: currentDate) else { return nil }
                currentDate = nextDate
            }
            previousTime = arrivalTime ?? previousTime
        }
        return currentDate
    }

    /// Advances a service's departure day when its arrival clock wraps past midnight.
    private static func arrivalServiceDate(
        departureDate: TransitDate?,
        departureTime: String,
        arrivalTime: String
    ) -> TransitDate? {
        guard let departureDate else { return nil }
        let departure = TransitRequestFormatting.serviceTime(from: departureTime)
        let arrival = TransitRequestFormatting.serviceTime(from: arrivalTime)
        return crossesMidnight(from: departure, to: arrival)
            ? addingDays(1, to: departureDate)
            : departureDate
    }

    private static func crossesMidnight(from earlier: TransitTime?, to later: TransitTime?) -> Bool {
        guard let earlier, let later else { return false }
        let earlierMinute = (earlier.hour * 60) + earlier.minute
        let laterMinute = (later.hour * 60) + later.minute
        return laterMinute < earlierMinute
    }

    private static func addingDays(_ days: Int, to date: TransitDate) -> TransitDate? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        guard let absoluteDate = date.date(in: calendar),
              let adjusted = calendar.date(byAdding: .day, value: days, to: absoluteDate)
        else {
            return nil
        }
        return TransitDate(adjusted, calendar: calendar)
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

    /// Recreates the submitted board as a departures query for any supported destination.
    func submittedHeaderDepartureSearch() -> DepartureSearchSelection? {
        DepartureSearchSelectionFactory.search(
            timetable: timetable,
            station: station,
            serviceDate: TransitRequestFormatting.serviceDate(from: date),
            serviceTime: TransitRequestFormatting.serviceTime(from: time),
            client: client
        )
    }

    /// Prepares a station-timetable form from the submitted board stop and its selected day.
    func submittedHeaderStationTimetableSelection() -> StationTimetableSelection? {
        StationTimetableSelectionFactory.stationBoard(
            timetable: timetable,
            station: station,
            serviceDate: TransitRequestFormatting.serviceDate(from: date),
            client: client
        )
    }

    /// Builds a departures query from one provider-returned service row and its exact board instant.
    func departureSearch(for departure: TransitDeparture) -> DepartureSearchSelection? {
        DepartureSearchSelectionFactory.departure(
            departure,
            station: departure.stationName ?? station,
            timetable: departure.appTimetable(in: timetables),
            fallbackServiceDate: TransitRequestFormatting.serviceDate(from: date),
            client: client
        )
    }

    /// Builds a complete line-and-direction station timetable from one provider-returned service row.
    func stationTimetableSelection(for departure: TransitDeparture) -> StationTimetableSelection? {
        StationTimetableSelectionFactory.departure(
            departure,
            station: departure.stationName ?? station,
            timetable: departure.appTimetable(in: timetables),
            fallbackServiceDate: TransitRequestFormatting.serviceDate(from: date),
            client: client
        )
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
        isArrival = selection.isArrival
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
        isArrival = search.request.isArrival
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
