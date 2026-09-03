import Foundation

/// Kaštan's deterministic, network-free provider for CLI tests and explicit interface previews.
///
/// The fixture deliberately supports the main read-only search surfaces while omitting paging, exports, and email.
/// Its stable values make complete product flows testable without depending on a live transport service.
public struct MockTransitDataSource: TransitDataSource {
    public static let descriptor = TransitDataSourceDescriptor(
        id: .mock,
        displayName: "Kaštan Mock",
        capabilities: [
            .timetables,
            .placeSuggestions,
            .coordinatePlaceSelection,
            .stationSearch,
            .connections,
            .departures,
            .stationTimetables,
            .stationTimetableDepartureResolution,
            .serviceDetails,
        ]
    )

    public static let timetable = TransitTimetable(
        dataSourceID: .mock,
        identifier: "mock",
        displayName: "Mock Network"
    )

    private static let places = [
        TransitSuggestion(
            dataSourceID: .mock,
            timetableIdentifier: timetable.identifier,
            identifier: "mock:place:mockov",
            selectedText: "Mockov",
            text: "Mockov",
            description: "mock station"
        ),
        TransitSuggestion(
            dataSourceID: .mock,
            timetableIdentifier: timetable.identifier,
            identifier: "mock:place:testov",
            selectedText: "Testov",
            text: "Testov",
            description: "mock station"
        ),
    ]

    public init() {}

    public var descriptor: TransitDataSourceDescriptor { Self.descriptor }
    public var serviceTimeZone: TimeZone? { TimeZone(secondsFromGMT: 0) }
    public var timetables: [TransitTimetable] { [Self.timetable] }
    public var defaultTimetable: TransitTimetable { Self.timetable }

    public func suggest(
        prefix: String,
        limit: Int,
        timetable: TransitTimetable
    ) async throws -> [TransitSuggestion] {
        try validate(timetable)
        return limitedPlaces(matching: prefix, limit: limit)
    }

    public func searchStations(
        prefix: String,
        limit: Int,
        timetable: TransitTimetable
    ) async throws -> [TransitSuggestion] {
        try validate(timetable)
        return limitedPlaces(matching: prefix, limit: limit)
    }

    public func coordinatePlaceSelection(
        text: String,
        latitude: Double,
        longitude: Double,
        timetable: TransitTimetable
    ) throws -> TransitPlaceSelection {
        try validate(timetable)
        return TransitPlaceSelection(
            dataSourceID: .mock,
            timetableIdentifier: timetable.identifier,
            identifier: "mock:coordinate:\(latitude),\(longitude)",
            text: text,
            isCurrentLocation: true
        )
    }

    public func findConnections(request: TransitConnectionRequest) async throws -> [TransitConnection] {
        try validate(request.timetable)
        guard request.resultLimit != 0 else { return [] }

        let serviceID = "mock:service:1"
        return [TransitConnection(
            dataSourceID: .mock,
            timetableIdentifier: request.timetable.identifier,
            id: "mock:connection:1",
            departureTime: "08:00",
            departureStation: request.from,
            arrivalTime: "08:42",
            arrivalStation: request.to,
            duration: "42 min",
            legs: [TransitConnectionLeg(
                name: "Mock train M1",
                id: serviceID,
                color: "#7A4EAB",
                transportMode: .train,
                departureTime: "08:00",
                fromStation: request.from,
                fromPlatform: "1/1",
                arrivalTime: "08:42",
                toStation: request.to,
                toPlatform: "2/2",
                carrier: "Kaštan Mock"
            )]
        )]
    }

    public func findDepartures(request: TransitDeparturesRequest) async throws -> [TransitDeparture] {
        try validate(request.timetable)
        return [
            Self.departure(station: request.station, time: "08:00", index: 1),
            Self.departure(station: request.station, time: "08:30", index: 2),
        ]
    }

    public func searchStationTimetableLines(
        prefix: String,
        limit: Int,
        timetable: TransitTimetable
    ) async throws -> [TransitSuggestion] {
        try validate(timetable)
        let line = TransitSuggestion(
            dataSourceID: .mock,
            timetableIdentifier: timetable.identifier,
            identifier: "mock:line:m1",
            selectedText: "M1",
            text: "Mock train M1",
            from: "Mockov",
            to: "Testov"
        )
        guard Self.normalized("M1 Mock train").contains(Self.normalized(prefix)) else { return [] }
        return Array([line].prefix(max(0, limit)))
    }

    public func searchStationTimetableStops(
        prefix: String,
        line: String,
        limit: Int,
        timetable: TransitTimetable
    ) async throws -> [TransitSuggestion] {
        try validate(timetable)
        return limitedPlaces(matching: prefix, limit: limit)
    }

    public func findStationTimetable(
        request: TransitStationTimetableRequest,
        language: TransitLanguage
    ) async throws -> TransitStationTimetable {
        try validate(request.timetable)
        return TransitStationTimetable(
            timetable: request.timetable,
            lineName: request.line,
            transportMode: .train,
            fromStop: request.from,
            toStop: request.to,
            stops: [
                TransitStationTimetableStop(
                    name: request.from,
                    platform: "1",
                    isSelected: true
                ),
                TransitStationTimetableStop(
                    name: request.to,
                    minuteOffset: 42,
                    platform: "2"
                ),
            ],
            schedules: [TransitStationTimetableSchedule(
                label: language == .czech ? "Každý den" : "Every day",
                hours: [TransitStationTimetableHour(hour: "8", departures: ["00", "30"])]
            )],
            notes: [language == .czech ? "Stabilní testovací data." : "Stable test data."]
        )
    }

    public func resolveStationTimetableDeparture(
        request: TransitStationTimetableDepartureResolutionRequest,
        language: TransitLanguage
    ) async throws -> TransitStationTimetableDepartureResolution? {
        let timetable = request.stationTimetable
        try validate(timetable.timetable)
        guard timetable.schedules.indices.contains(request.scheduleIndex) else { return nil }
        let schedule = timetable.schedules[request.scheduleIndex]
        guard schedule.hours.indices.contains(request.hourIndex) else { return nil }
        let hour = schedule.hours[request.hourIndex]
        guard hour.departures.indices.contains(request.departureIndex),
              let hourValue = Int(hour.hour),
              let minuteValue = Int(hour.departures[request.departureIndex])
        else {
            return nil
        }

        let serviceTime = TransitTime(hour: hourValue, minute: minuteValue)
        let departure = Self.departure(
            station: timetable.fromStop,
            time: String(format: "%02d:%02d", hourValue, minuteValue),
            index: request.departureIndex + 1,
            destination: timetable.toStop,
            lineName: timetable.lineName
        )
        let departureRequest = TransitDeparturesRequest(
            timetable: timetable.timetable,
            station: timetable.fromStop,
            serviceDate: request.serviceDate,
            serviceTime: serviceTime
        )
        return TransitStationTimetableDepartureResolution(
            departure: departure,
            request: departureRequest,
            page: TransitDeparturePage(departures: [departure], dataSourceID: .mock),
            serviceDate: request.serviceDate,
            serviceTime: serviceTime
        )
    }

    public func serviceDetail(
        id: String,
        timetable: TransitTimetable
    ) async throws -> TransitServiceDetail {
        try validate(timetable)
        return TransitServiceDetail(
            id: id,
            timetable: timetable,
            name: "Mock train M1",
            color: "#7A4EAB",
            transportMode: .train,
            date: "3. 9. 2026",
            stops: [
                TransitServiceStop(
                    name: "Mockov",
                    departureTime: "08:00",
                    platform: "1",
                    track: "1"
                ),
                TransitServiceStop(
                    name: "Testov",
                    arrivalTime: "08:42",
                    platform: "2",
                    track: "2"
                ),
            ],
            information: ["Deterministic test service"]
        )
    }

    private func limitedPlaces(matching prefix: String, limit: Int) -> [TransitSuggestion] {
        let query = Self.normalized(prefix)
        let matches = Self.places.filter {
            query.isEmpty || Self.normalized($0.text).hasPrefix(query)
        }
        return Array(matches.prefix(max(0, limit)))
    }

    private func validate(_ timetable: TransitTimetable) throws {
        guard timetable.dataSourceID == .mock else {
            throw TransitDataSourceError.valueBelongsToDifferentSource(
                expected: .mock,
                actual: timetable.dataSourceID
            )
        }
        guard timetable.identifier == Self.timetable.identifier else {
            throw TransitDataSourceError.valueBelongsToDifferentTimetable(
                expected: Self.timetable.identifier,
                actual: timetable.identifier,
                source: .mock
            )
        }
    }

    private static func departure(
        station: String,
        time: String,
        index: Int,
        destination: String = "Testov",
        lineName: String = "Mock train M1"
    ) -> TransitDeparture {
        TransitDeparture(
            dataSourceID: .mock,
            timetableIdentifier: timetable.identifier,
            id: "mock:service:\(index)",
            stationName: station,
            time: time,
            lineName: lineName,
            lineColor: "#7A4EAB",
            transportMode: .train,
            destination: destination,
            platform: "1/1",
            carrier: "Kaštan Mock"
        )
    }

    private static func normalized(_ value: String) -> String {
        value.folding(
            options: [.diacriticInsensitive, .caseInsensitive],
            locale: Locale(identifier: "en_US_POSIX")
        ).lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
