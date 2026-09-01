import Foundation
import Kastan

/// Transfers one already resolved provider station-board result into Departures without repeating its request.
struct ResolvedDepartureSearch {
    let request: TransitDeparturesRequest
    let page: TransitDeparturePage
    let dateAndTime: Date
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
    @Published private(set) var departures: [TransitDeparture] = []
    @Published private(set) var isSearching = false
    @Published private(set) var isLoadingEarlier = false
    @Published private(set) var isLoadingLater = false
    @Published var errorMessage: String?

    let client: any TransitDataSource
    private var resultPage: TransitDeparturePage?
    private var isRefreshingCurrentDateAndTime = false

    init(client: any TransitDataSource) {
        self.client = client
        timetable = AppTimetableDefaults.search(
            in: client.timetables,
            defaultTimetable: client.defaultTimetable
        )
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
    }

    func search() async {
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
