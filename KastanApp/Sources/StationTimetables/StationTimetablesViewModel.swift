import Foundation
import Kastan

/// Preserves a station-timetable form while opening it in another main window or tab.
struct StationTimetableSelection: Codable, Hashable {
    let timetable: TransitTimetable
    let municipality: TransitStationTimetableMunicipality?
    let line: String
    let from: String
    let to: String
    let serviceDate: TransitDate
    let wholeWeek: Bool

    var dataSourceID: TransitDataSourceID { timetable.dataSourceID }

    func hash(into hasher: inout Hasher) {
        hasher.combine(timetable.dataSourceID)
        hasher.combine(timetable.identifier)
        hasher.combine(timetable.displayName)
        hasher.combine(municipality)
        hasher.combine(line)
        hasher.combine(from)
        hasher.combine(to)
        hasher.combine(serviceDate)
        hasher.combine(wholeWeek)
    }
}

/// Builds station-timetable forms from each level of a completed connection result.
enum StationTimetableSelectionFactory {
    static func search(
        timetable: TransitTimetable,
        from: String,
        to: String,
        serviceDate: TransitDate,
        client: any TransitDataSource
    ) -> StationTimetableSelection? {
        make(
            timetable: timetable,
            line: "",
            from: from,
            to: to,
            serviceDate: serviceDate,
            client: client
        )
    }

    /// Uses the result's matched stops and departure date instead of the broader submitted search.
    static func connection(
        _ connection: TransitConnection,
        timetable: TransitTimetable,
        fallbackServiceDate: TransitDate?,
        client: any TransitDataSource
    ) -> StationTimetableSelection? {
        make(
            timetable: timetable,
            line: "",
            from: connection.departureStation,
            to: connection.arrivalStation,
            serviceDate: connection.departureDate ?? fallbackServiceDate,
            client: client
        )
    }

    /// Uses the concrete service's line, matched stops, and calendar day to create a complete query.
    static func service(
        _ leg: TransitConnectionLeg,
        in connection: TransitConnection,
        timetable: TransitTimetable,
        fallbackServiceDate: TransitDate?,
        client: any TransitDataSource
    ) -> StationTimetableSelection? {
        make(
            timetable: timetable,
            line: leg.name,
            from: leg.fromStation,
            to: leg.toStation,
            serviceDate: leg.departureDate ?? connection.departureDate ?? fallbackServiceDate,
            client: client
        )
    }

    private static func make(
        timetable requestedTimetable: TransitTimetable,
        line: String,
        from: String,
        to: String,
        serviceDate: TransitDate?,
        client: any TransitDataSource
    ) -> StationTimetableSelection? {
        guard let serviceDate,
              let timetable = AppTimetableGroup.stationTimetables(in: client.timetables).first(where: {
                  $0.appIdentity == requestedTimetable.appIdentity
              })
        else {
            return nil
        }

        return StationTimetableSelection(
            timetable: timetable,
            municipality: client.defaultStationTimetableMunicipality(for: timetable),
            line: line,
            from: from,
            to: to,
            serviceDate: serviceDate,
            wholeWeek: false
        )
    }
}

/// Owns one MHD or integrated-transport station-timetable query and its selected route stop.
@MainActor
final class StationTimetablesViewModel: ObservableObject {
    @Published var line = ""
    @Published var from = ""
    @Published var to = ""
    @Published var timetable: TransitTimetable
    @Published var municipality: TransitStationTimetableMunicipality?
    @Published var date = Date()
    @Published var wholeWeek = false
    /// Retains the passenger's summary-or-editor choice while the main window displays another search mode.
    @Published private(set) var isSearchFormCollapsed = false
    @Published private(set) var result: TransitStationTimetable?
    @Published private(set) var isSearching = false
    @Published private(set) var resolvingDeparture: StationTimetableDepartureReference?
    @Published var errorMessage: String?

    let client: any TransitDataSource
    private var resultSearchDate: TransitDate?
    private var resultUsesWholeWeek = false
    private var resultRequest: TransitStationTimetableRequest?
    private var hasPendingInitialSelection = false
    @Published var requestsLineFocus = false

    private struct DepartureResolution {
        let selection: ServiceSelection
        let search: ResolvedDepartureSearch
    }

    init(
        client: any TransitDataSource,
        initialSelection: StationTimetableSelection? = nil
    ) {
        self.client = client
        timetable = AppTimetableDefaults.search(
            in: client.timetables,
            defaultTimetable: client.defaultTimetable
        )
        municipality = client.defaultStationTimetableMunicipality(for: timetable)

        if let initialSelection {
            _ = present(initialSelection)
        }
    }

    /// Replaces the editable form and starts complete transferred queries when the view next appears.
    @discardableResult
    func present(_ selection: StationTimetableSelection) -> Bool {
        guard selection.dataSourceID == client.descriptor.id,
              let selectedTimetable = timetables.first(where: {
                  $0.appIdentity == selection.timetable.appIdentity
              })
        else {
            return false
        }

        let selectedMunicipality = selection.municipality.map { requested in
            client.stationTimetableMunicipalities(for: selectedTimetable).first {
                $0.dataSourceID == requested.dataSourceID &&
                    $0.timetableIdentifier == requested.timetableIdentifier &&
                    $0.identifier == requested.identifier
            } ?? requested
        }

        timetable = selectedTimetable
        municipality = selectedMunicipality
        line = selection.line
        from = selection.from
        to = selection.to
        date = TransitRequestFormatting.displayDateAndTime(
            serviceDate: selection.serviceDate,
            serviceTime: TransitTime(hour: 12, minute: 0)
        ) ?? Date()
        wholeWeek = selection.wholeWeek
        result = nil
        resultSearchDate = nil
        resultUsesWholeWeek = false
        resultRequest = nil
        resolvingDeparture = nil
        errorMessage = nil
        hasPendingInitialSelection = canSearch
        isSearchFormCollapsed = hasPendingInitialSelection
        requestsLineFocus = line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return true
    }

    /// Replaces the submitted station-timetable editor with its compact result summary.
    func collapseSearchForm() {
        isSearchFormCollapsed = true
    }

    /// Restores the submitted station-timetable editor for deliberate query changes.
    func revealSearchForm() {
        isSearchFormCollapsed = false
    }

    /// Starts a complete query carried by a newly opened main window exactly once.
    func loadInitialSelectionIfNeeded() async {
        guard hasPendingInitialSelection else { return }
        hasPendingInitialSelection = false
        await search()
    }

    /// Indicates whether a complete transferred query is still waiting for its one automatic search.
    var startsWithInitialSelection: Bool {
        hasPendingInitialSelection
    }

    /// Requests the missing line field after an incomplete connection-level transfer opens the form.
    var startsWithLineFocus: Bool {
        requestsLineFocus
    }

    /// Municipalities available inside the currently selected Station Timetable catalog.
    var municipalities: [TransitStationTimetableMunicipality] {
        client.stationTimetableMunicipalities(for: timetable)
    }

    var timetables: [TransitTimetable] {
        AppTimetableGroup.stationTimetables(in: client.timetables)
    }

    /// Indicates whether timetable minutes can be matched back to the provider's station board.
    var canFindDepartureResults: Bool {
        client.descriptor.supports(.stationTimetableDepartureResolution) &&
            client.descriptor.supports(.departures)
    }

    /// Indicates whether a matched timetable minute can continue into a complete service route.
    var canOpenDepartureServices: Bool {
        canFindDepartureResults && client.descriptor.supports(.serviceDetails)
    }

    var canSearch: Bool {
        [line, from, to].allSatisfy {
            !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        } && (municipalities.isEmpty || municipality != nil) && !isSearching
    }

    /// Applies both terminal names supplied by the data source with a selected line direction.
    func selectLineSuggestion(_ suggestion: TransitSuggestion) {
        line = suggestion.text
        from = suggestion.from ?? ""
        to = suggestion.to ?? ""
        result = nil
        resultRequest = nil
        errorMessage = nil
    }

    /// Clears line-specific input when switching to another transport catalog.
    func selectTimetable(slug: String) {
        guard let selected = timetables.first(where: { $0.slug == slug }),
              selected != timetable
        else {
            return
        }
        timetable = selected
        municipality = client.defaultStationTimetableMunicipality(for: selected)
        clearRoute()
    }

    /// Selects one local network within a multi-municipality catalog and clears its previous route.
    func selectMunicipality(_ selected: TransitStationTimetableMunicipality) {
        guard municipalities.contains(selected), selected != municipality else { return }
        municipality = selected
        clearRoute()
    }

    private func clearRoute() {
        line = ""
        from = ""
        to = ""
        result = nil
        resultSearchDate = nil
        resultRequest = nil
        resolvingDeparture = nil
        errorMessage = nil
    }

    /// Replaces the station-timetable date with today's value from the main-menu shortcut.
    func selectCurrentDate(now: Date = .now) {
        date = now
    }

    /// Swaps both direction stops without repeating the current station-timetable search.
    func swapDirectionStops() {
        swap(&from, &to)
    }

    func search() async {
        let line = line.trimmingCharacters(in: .whitespacesAndNewlines)
        let from = from.trimmingCharacters(in: .whitespacesAndNewlines)
        let to = to.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !line.isEmpty, !from.isEmpty, !to.isEmpty else {
            errorMessage = AppLocalization.string("Enter a line and both direction stops.")
            return
        }

        isSearching = true
        errorMessage = nil
        result = nil
        resultRequest = nil
        resolvingDeparture = nil
        defer { isSearching = false }

        let requestedDate = TransitRequestFormatting.serviceDate(from: date)
        let requestedWholeWeek = wholeWeek

        let request = TransitStationTimetableRequest(
            timetable: timetable,
            municipality: municipality,
            line: line,
            from: from,
            to: to,
            serviceDate: TransitRequestFormatting.serviceDate(from: date),
            wholeWeek: wholeWeek
        )

        do {
            let loadedResult = try await client.findStationTimetable(
                request: request,
                language: AppLanguagePreference.transitLanguage
            )
            resultSearchDate = requestedDate
            resultUsesWholeWeek = requestedWholeWeek
            resultRequest = request
            result = loadedResult
        } catch {
            errorMessage = AppErrorPresentation.message(for: error)
        }
    }

    /// Resolves one displayed value to the provider's dated service identifier only when the passenger opens it.
    func serviceSelection(
        for departure: StationTimetableDepartureReference
    ) async -> ServiceSelection? {
        guard canOpenDepartureServices else { return nil }
        return await resolveDeparture(departure)?.selection
    }

    /// Resolves one timetable minute into the complete Departures result that contains that run.
    func departureSearch(
        for departure: StationTimetableDepartureReference
    ) async -> ResolvedDepartureSearch? {
        guard canFindDepartureResults else { return nil }
        return await resolveDeparture(departure)?.search
    }

    private func resolveDeparture(
        _ departure: StationTimetableDepartureReference
    ) async -> DepartureResolution? {
        guard canFindDepartureResults,
              resolvingDeparture == nil,
              let result,
              let selectedStop = result.selectedStop,
              let resultSearchDate,
              departure.isPresent(in: result)
        else {
            return nil
        }

        let sourceResult = result

        resolvingDeparture = departure
        errorMessage = nil
        defer {
            if resolvingDeparture == departure {
                resolvingDeparture = nil
            }
        }

        do {
            let resolution = try await client.resolveStationTimetableDeparture(
                request: TransitStationTimetableDepartureResolutionRequest(
                    stationTimetable: sourceResult,
                    scheduleIndex: departure.scheduleIndex,
                    hourIndex: departure.hourIndex,
                    departureIndex: departure.departureIndex,
                    serviceDate: resultSearchDate,
                    wholeWeek: resultUsesWholeWeek
                ),
                language: AppLanguagePreference.transitLanguage
            )
            guard result == sourceResult else { return nil }
            guard let resolution else {
                errorMessage = AppLocalization.string(
                    "%@ could not identify this station-timetable departure.",
                    client.descriptor.displayName
                )
                return nil
            }
            let dateAndTime = TransitRequestFormatting.displayDateAndTime(
                serviceDate: resolution.serviceDate,
                serviceTime: resolution.serviceTime
            ) ?? date
            return DepartureResolution(
                selection: ServiceSelection(
                    id: resolution.departure.id,
                    timetable: resolution.departure.appTimetable(in: client.timetables),
                    highlight: ServiceRouteHighlight(
                        fromStop: selectedStop.name,
                        toStop: sourceResult.toStop
                    )
                ),
                search: ResolvedDepartureSearch(
                    request: resolution.request,
                    page: resolution.page,
                    dateAndTime: dateAndTime
                )
            )
        } catch {
            if result == sourceResult {
                errorMessage = AppErrorPresentation.message(for: error)
            }
        }
        return nil
    }

    func selectStop(at index: Int) async {
        guard let result,
              result.stops.indices.contains(index),
              !result.stops[index].isSelected,
              !isSearching
        else {
            return
        }

        if index == result.stops.index(before: result.stops.endIndex) {
            await reverseDirection()
        } else {
            from = result.stops[index].name
            await search()
        }
    }

    /// Builds the independent query represented by activating one stop in the currently displayed route.
    func newWindowSelection(forStopAt index: Int) -> StationTimetableSelection? {
        guard let result,
              let resultRequest,
              let resultSearchDate,
              result.stops.indices.contains(index)
        else {
            return nil
        }

        let stop = result.stops[index]
        var from = resultRequest.from
        var to = resultRequest.to
        if !stop.isSelected {
            if index == result.stops.index(before: result.stops.endIndex) {
                swap(&from, &to)
            } else {
                from = stop.name
            }
        }

        return StationTimetableSelection(
            timetable: resultRequest.timetable,
            municipality: resultRequest.municipality,
            line: resultRequest.line,
            from: from,
            to: to,
            serviceDate: resultSearchDate,
            wholeWeek: resultRequest.wholeWeek
        )
    }

    func reverseDirection() async {
        guard !isSearching else { return }
        swapDirectionStops()
        await search()
    }
}

/// Identifies one visible minute without pretending that the station timetable already contains a service ID.
struct StationTimetableDepartureReference: Hashable {
    let scheduleIndex: Int
    let hourIndex: Int
    let departureIndex: Int
    let value: String

    init?(
        scheduleIndex: Int,
        schedule: TransitStationTimetableSchedule,
        hourIndex: Int,
        departureIndex: Int
    ) {
        guard schedule.hours.indices.contains(hourIndex),
              schedule.hours[hourIndex].departures.indices.contains(departureIndex)
        else {
            return nil
        }

        self.scheduleIndex = scheduleIndex
        self.hourIndex = hourIndex
        self.departureIndex = departureIndex
        value = schedule.hours[hourIndex].departures[departureIndex]
    }

    /// Rejects stale clicks after another station-timetable result has replaced the displayed table.
    func isPresent(in timetable: TransitStationTimetable) -> Bool {
        guard timetable.schedules.indices.contains(scheduleIndex),
              let current = Self(
                  scheduleIndex: scheduleIndex,
                  schedule: timetable.schedules[scheduleIndex],
                  hourIndex: hourIndex,
                  departureIndex: departureIndex
              )
        else {
            return false
        }
        return current == self
    }

}
