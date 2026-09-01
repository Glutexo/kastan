import Foundation
import Kastan

/// Owns one MHD or integrated-transport station-timetable query and its selected route stop.
@MainActor
final class StationTimetablesViewModel: ObservableObject {
    @Published var line = ""
    @Published var from = ""
    @Published var to = ""
    @Published var timetable: IDOSTimetable
    @Published var municipality: IDOSStationTimetableMunicipality?
    @Published var date = Date()
    @Published var wholeWeek = false
    @Published private(set) var result: IDOSStationTimetable?
    @Published private(set) var isSearching = false
    @Published private(set) var resolvingDeparture: StationTimetableDepartureReference?
    @Published var errorMessage: String?

    let client: any IDOSClienting
    private var resultSearchDate: Date?
    private var resultUsesWholeWeek = false

    private struct DepartureResolution {
        let selection: ServiceSelection
        let search: ResolvedDepartureSearch
    }

    init(client: any IDOSClienting) {
        self.client = client
        timetable = AppTimetableDefaults.search
        municipality = IDOSStationTimetableMunicipality.default(for: timetable)
    }

    /// Municipalities available inside the currently selected Station Timetable catalog.
    var municipalities: [IDOSStationTimetableMunicipality] {
        IDOSStationTimetableMunicipality.available(for: timetable)
    }

    var canSearch: Bool {
        [line, from, to].allSatisfy {
            !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        } && (municipalities.isEmpty || municipality != nil) && !isSearching
    }

    /// Applies both terminal names supplied by IDOS with a selected line direction.
    func selectLineSuggestion(_ suggestion: IDOSSuggestion) {
        line = suggestion.text
        from = suggestion.from ?? ""
        to = suggestion.to ?? ""
        result = nil
        errorMessage = nil
    }

    /// Clears line-specific input when switching to another transport catalog.
    func selectTimetable(slug: String) {
        guard let selected = AppTimetableGroup.stationTimetables.first(where: { $0.slug == slug }),
              selected.slug != timetable.slug
        else {
            return
        }
        timetable = selected
        municipality = IDOSStationTimetableMunicipality.default(for: selected)
        clearRoute()
    }

    /// Selects one local network within a multi-municipality catalog and clears its previous route.
    func selectMunicipality(_ selected: IDOSStationTimetableMunicipality) {
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
        resolvingDeparture = nil
        defer { isSearching = false }

        let requestedDate = StationTimetableDepartureLookup.serviceDate(for: date)
        let requestedWholeWeek = wholeWeek

        let request = IDOSStationTimetableRequest(
            timetable: timetable,
            municipality: municipality,
            line: line,
            from: from,
            to: to,
            date: IDOSRequestFormatting.date(from: date),
            wholeWeek: wholeWeek
        )

        do {
            let loadedResult = try await client.findStationTimetable(
                request: request,
                language: AppLanguagePreference.idosLanguage
            )
            resultSearchDate = requestedDate
            resultUsesWholeWeek = requestedWholeWeek
            result = loadedResult
        } catch {
            errorMessage = AppErrorPresentation.message(for: error)
        }
    }

    /// Resolves one displayed minute to IDOS's dated service identifier only when the passenger opens it.
    func serviceSelection(
        for departure: StationTimetableDepartureReference
    ) async -> ServiceSelection? {
        await resolveDeparture(departure)?.selection
    }

    /// Resolves one timetable minute into the complete Departures result that contains that run.
    func departureSearch(
        for departure: StationTimetableDepartureReference
    ) async -> ResolvedDepartureSearch? {
        await resolveDeparture(departure)?.search
    }

    private func resolveDeparture(
        _ departure: StationTimetableDepartureReference
    ) async -> DepartureResolution? {
        guard resolvingDeparture == nil,
              let result,
              let selectedStop = result.selectedStop,
              departure.isPresent(in: result)
        else {
            return nil
        }

        let sourceResult = result
        let calendar = StationTimetableDepartureLookup.serviceCalendar
        let serviceDates = StationTimetableDepartureLookup.candidateServiceDates(
            for: departure.scheduleLabel,
            searchDate: resultSearchDate ?? date,
            wholeWeek: resultUsesWholeWeek,
            calendar: calendar
        )

        resolvingDeparture = departure
        errorMessage = nil
        defer {
            if resolvingDeparture == departure {
                resolvingDeparture = nil
            }
        }

        do {
            for serviceDate in serviceDates {
                guard result == sourceResult,
                      let datedDeparture = calendar.date(
                          byAdding: .day,
                          value: departure.dayOffset,
                          to: serviceDate
                      )
                else {
                    return nil
                }

                let request = IDOSDeparturesRequest(
                    timetable: sourceResult.timetable,
                    station: selectedStop.name,
                    date: StationTimetableDepartureLookup.requestDate(
                        from: datedDeparture,
                        calendar: calendar
                    ),
                    time: departure.displayTime,
                    isArrival: false
                )
                let page = try await client.findDeparturesPage(
                    request: request,
                    language: AppLanguagePreference.idosLanguage
                )

                if let matchedDeparture = StationTimetableDepartureLookup.matchingDeparture(
                    in: page.departures,
                    reference: departure,
                    timetable: sourceResult
                ) {
                    guard result == sourceResult else { return nil }
                    return DepartureResolution(
                        selection: ServiceSelection(
                            id: matchedDeparture.id,
                            highlight: ServiceRouteHighlight(
                                fromStop: selectedStop.name,
                                toStop: sourceResult.toStop
                            )
                        ),
                        search: ResolvedDepartureSearch(
                            request: request,
                            page: page,
                            dateAndTime: StationTimetableDepartureLookup.displayDateAndTime(
                                for: datedDeparture,
                                hour: departure.hour,
                                minute: departure.minute,
                                sourceCalendar: calendar
                            )
                        )
                    )
                }
            }

            if result == sourceResult {
                errorMessage = AppLocalization.string(
                    "IDOS could not identify this station-timetable departure."
                )
            }
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

    func reverseDirection() async {
        guard !isSearching else { return }
        swapDirectionStops()
        await search()
    }
}

/// Identifies one visible minute without pretending that the station timetable already contains a service ID.
struct StationTimetableDepartureReference: Hashable {
    let scheduleIndex: Int
    let scheduleLabel: String
    let hourIndex: Int
    let departureIndex: Int
    let value: String
    let hour: Int
    let minute: Int
    let dayOffset: Int
    let occurrence: Int

    init?(
        scheduleIndex: Int,
        schedule: IDOSStationTimetableSchedule,
        hourIndex: Int,
        departureIndex: Int
    ) {
        guard schedule.hours.indices.contains(hourIndex),
              schedule.hours[hourIndex].departures.indices.contains(departureIndex),
              let hour = Int(schedule.hours[hourIndex].hour),
              (0...23).contains(hour)
        else {
            return nil
        }

        let value = schedule.hours[hourIndex].departures[departureIndex]
        let minuteText = value.prefix(while: \.isNumber)
        guard let minute = Int(minuteText), (0...59).contains(minute) else {
            return nil
        }

        self.scheduleIndex = scheduleIndex
        scheduleLabel = schedule.label
        self.hourIndex = hourIndex
        self.departureIndex = departureIndex
        self.value = value
        self.hour = hour
        self.minute = minute
        dayOffset = Self.dayOffset(forHourAt: hourIndex, in: schedule.hours)
        occurrence = schedule.hours[hourIndex].departures[..<departureIndex].filter {
            Int($0.prefix(while: \.isNumber)) == minute
        }.count
    }

    /// Formats the exact board-search instant while retaining IDOS's unpadded hour convention.
    var displayTime: String {
        String(format: "%d:%02d", hour, minute)
    }

    /// Rejects stale clicks after another station-timetable result has replaced the displayed table.
    func isPresent(in timetable: IDOSStationTimetable) -> Bool {
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

    /// Treats a decreasing hour sequence as the following calendar day of the same service day.
    private static func dayOffset(
        forHourAt requestedIndex: Int,
        in hours: [IDOSStationTimetableHour]
    ) -> Int {
        var previousHour: Int?
        var offset = 0

        for hour in hours.prefix(requestedIndex + 1).compactMap({ Int($0.hour) }) {
            if let previousHour, hour < previousHour {
                offset += 1
            }
            previousHour = hour
        }
        return offset
    }
}

/// Finds the dated station-board entry that supplies the service identifier omitted by IDOS's timetable table.
enum StationTimetableDepartureLookup {
    /// Uses IDOS's Czech service-day boundary independently of the Mac's current time zone.
    static var serviceCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_GB")
        calendar.timeZone = TimeZone(identifier: "Europe/Prague")!
        calendar.firstWeekday = 2
        calendar.minimumDaysInFirstWeek = 4
        return calendar
    }

    /// Preserves the passenger's selected calendar date when constructing IDOS's Prague service day.
    static func serviceDate(
        for selectedDate: Date,
        sourceCalendar: Calendar = .current,
        calendar: Calendar = serviceCalendar
    ) -> Date {
        let components = sourceCalendar.dateComponents([.year, .month, .day], from: selectedDate)
        return calendar.date(from: components) ?? calendar.startOfDay(for: selectedDate)
    }

    /// Formats a service date from Prague calendar components so the Mac's time zone cannot shift the day.
    static func requestDate(
        from date: Date,
        calendar: Calendar = serviceCalendar
    ) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        guard let day = components.day,
              let month = components.month,
              let year = components.year
        else {
            return IDOSRequestFormatting.date(from: date)
        }
        return "\(day).\(month).\(year)"
    }

    /// Rebuilds the resolved Prague service instant in the Mac's calendar for Departures controls.
    static func displayDateAndTime(
        for serviceDate: Date,
        hour: Int,
        minute: Int,
        sourceCalendar: Calendar = serviceCalendar,
        displayCalendar: Calendar = .current
    ) -> Date {
        let date = sourceCalendar.dateComponents([.era, .year, .month, .day], from: serviceDate)
        var components = DateComponents()
        components.era = date.era
        components.year = date.year
        components.month = date.month
        components.day = date.day
        components.hour = hour
        components.minute = minute
        components.second = 0

        return displayCalendar.date(from: components)
            ?? sourceCalendar.date(bySettingHour: hour, minute: minute, second: 0, of: serviceDate)
            ?? serviceDate
    }

    /// Chooses the searched day directly, or the nearest matching weekday inside its Monday–Sunday week.
    static func candidateServiceDates(
        for scheduleLabel: String,
        searchDate: Date,
        wholeWeek: Bool,
        calendar: Calendar = serviceCalendar
    ) -> [Date] {
        let searchDay = calendar.startOfDay(for: searchDate)
        guard wholeWeek,
              let week = calendar.dateInterval(of: .weekOfYear, for: searchDay)
        else {
            return [searchDay]
        }

        let allowedWeekdays = weekdays(in: scheduleLabel)
        return (0..<7).compactMap { offset -> Date? in
            guard let date = calendar.date(byAdding: .day, value: offset, to: week.start),
                  allowedWeekdays?.contains(calendar.component(.weekday, from: date)) ?? true
            else {
                return nil
            }
            return date
        }.sorted { lhs, rhs in
            let lhsDistance = abs(calendar.dateComponents([.day], from: searchDay, to: lhs).day ?? 0)
            let rhsDistance = abs(calendar.dateComponents([.day], from: searchDay, to: rhs).day ?? 0)
            if lhsDistance != rhsDistance {
                return lhsDistance < rhsDistance
            }
            return lhs >= searchDay && rhs < searchDay
        }
    }

    /// Prefers the displayed line and direction, then uses duplicate order for the rare simultaneous runs.
    static func matchingDeparture(
        in departures: [IDOSDeparture],
        reference: StationTimetableDepartureReference,
        timetable: IDOSStationTimetable
    ) -> IDOSDeparture? {
        let line = normalizedLineName(timetable.lineName)
        let candidates = departures.filter { departure in
            guard let time = normalizedTime(departure.time) else { return false }
            return time.0 == reference.hour &&
                time.1 == reference.minute &&
                normalizedLineName(departure.lineName) == line
        }
        guard !candidates.isEmpty else { return nil }

        let destination = normalizedStopName(timetable.toStop)
        let directedCandidates = candidates.filter { departure in
            let candidateDestination = normalizedStopName(departure.destination)
            let candidateVia = normalizedStopName(departure.via ?? "")
            return candidateDestination == destination ||
                (!destination.isEmpty && candidateVia.contains(destination))
        }
        let preferred = directedCandidates.isEmpty ? candidates : directedCandidates
        if preferred.count == 1 {
            return preferred[0]
        }
        guard preferred.indices.contains(reference.occurrence) else { return nil }
        return preferred[reference.occurrence]
    }

    private static let weekdayNames: [(weekday: Int, names: [String])] = [
        (2, ["monday", "pondeli"]),
        (3, ["tuesday", "utery"]),
        (4, ["wednesday", "streda"]),
        (5, ["thursday", "ctvrtek"]),
        (6, ["friday", "patek"]),
        (7, ["saturday", "sobota"]),
        (1, ["sunday", "nedele"]),
    ]

    /// Recognizes the Czech and English grouping labels currently published by IDOS's whole-week view.
    private static func weekdays(in label: String) -> Set<Int>? {
        let value = normalizedText(label)
        if ["workday", "workdays", "working day", "working days", "pracovni den", "pracovni dny"]
            .contains(where: value.contains)
        {
            return [2, 3, 4, 5, 6]
        }

        let matches = weekdayNames.compactMap { weekday, names -> (Int, String.Index)? in
            names.compactMap { value.range(of: $0)?.lowerBound }.min().map { (weekday, $0) }
        }.sorted { $0.1 < $1.1 }
        guard !matches.isEmpty else { return nil }

        if matches.count == 2 {
            let separator = value[matches[0].1..<matches[1].1]
            if separator.contains("-") || separator.contains("–") || separator.contains("—") ||
                separator.contains(" to ") || separator.contains(" az ")
            {
                var weekdays = Set<Int>()
                var weekday = matches[0].0
                for _ in 0..<7 {
                    weekdays.insert(weekday)
                    if weekday == matches[1].0 { break }
                    weekday = weekday == 7 ? 1 : weekday + 1
                }
                return weekdays
            }
        }
        return Set(matches.map(\.0))
    }

    private static func normalizedTime(_ value: String) -> (Int, Int)? {
        let parts = value.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count >= 2,
              let hour = Int(parts[0]),
              let minute = Int(parts[1])
        else {
            return nil
        }
        return (hour, minute)
    }

    private static func normalizedLineName(_ value: String) -> String {
        var normalized = normalizedText(value)
        for prefix in ["line ", "linka "] where normalized.hasPrefix(prefix) {
            normalized.removeFirst(prefix.count)
        }
        return normalized.filter { $0.isLetter || $0.isNumber }
    }

    private static func normalizedStopName(_ value: String) -> String {
        normalizedText(value).filter { $0.isLetter || $0.isNumber }
    }

    private static func normalizedText(_ value: String) -> String {
        value
            .folding(
                options: [.diacriticInsensitive, .caseInsensitive],
                locale: Locale(identifier: "cs_CZ")
            )
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
