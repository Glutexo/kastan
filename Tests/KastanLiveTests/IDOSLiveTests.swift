import Foundation
import Kastan
import XCTest

/// Exercises Kaštan's public library API against the current, unmocked IDOS service.
final class IDOSLiveTests: XCTestCase {
    private static let optInEnvironmentVariable = "KASTAN_RUN_LIVE_IDOS_TESTS"

    override func setUpWithError() throws {
        try super.setUpWithError()
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment[Self.optInEnvironmentVariable] == "1",
            "Set \(Self.optInEnvironmentVariable)=1 to send live requests to IDOS."
        )
    }

    func testTimetableValidityContract() async throws {
        let client = IDOSDataSource()
        let timetable = try client.resolveTimetable("vlaky")

        let validity = try await client.timetableValidity(for: timetable, language: .english)

        XCTAssertLessThanOrEqual(validity.validFrom, validity.validThrough)
        XCTAssertEqual(validity.timeZoneIdentifier, IDOSDataSource.serviceTimeZone.identifier)
    }

    func testStationSuggestionsAndConnectionContract() async throws {
        let client = IDOSDataSource()
        let timetable = try client.resolveTimetable("vlaky")
        let fromSuggestion = try await exactStation(
            named: "Praha hl.n.",
            timetable: timetable,
            client: client
        )
        let toSuggestion = try await exactStation(
            named: "Brno hl.n.",
            timetable: timetable,
            client: client
        )
        let fromSelection = try XCTUnwrap(TransitPlaceSelection(suggestion: fromSuggestion))
        let toSelection = try XCTUnwrap(TransitPlaceSelection(suggestion: toSuggestion))
        let request = TransitConnectionRequest(
            timetable: timetable,
            from: fromSelection.text,
            to: toSelection.text,
            fromSelection: fromSelection,
            toSelection: toSelection,
            serviceDate: try tomorrowServiceDate(),
            serviceTime: TransitTime(hour: 10, minute: 0),
            resultLimit: 1
        )

        let page = try await client.findConnectionsPage(request: request, language: .english)
        let connection = try XCTUnwrap(page.connections.first)

        XCTAssertEqual(page.dataSourceID, .idos)
        XCTAssertEqual(connection.dataSourceID, .idos)
        XCTAssertEqual(connection.timetableIdentifier, timetable.identifier)
        XCTAssertFalse(connection.id.isEmpty)
        XCTAssertFalse(connection.departureStation.isEmpty)
        XCTAssertFalse(connection.arrivalStation.isEmpty)
        XCTAssertFalse(connection.legs.isEmpty)
    }

    func testDepartureBoardAndServiceDetailContract() async throws {
        let client = IDOSDataSource()
        let timetable = try client.resolveTimetable("vlaky")
        let request = TransitDeparturesRequest(
            timetable: timetable,
            station: "Praha hl.n.",
            serviceDate: try tomorrowServiceDate(),
            serviceTime: TransitTime(hour: 10, minute: 0)
        )

        let page = try await client.findDeparturesPage(request: request, language: .english)
        let departure = try XCTUnwrap(page.departures.first)
        let detail = try await client.serviceDetail(
            id: departure.id,
            timetable: timetable,
            language: .english
        )

        XCTAssertEqual(page.dataSourceID, .idos)
        XCTAssertEqual(departure.dataSourceID, .idos)
        XCTAssertEqual(departure.timetableIdentifier, timetable.identifier)
        XCTAssertFalse(departure.time.isEmpty)
        XCTAssertFalse(departure.lineName.isEmpty)
        XCTAssertFalse(departure.destination.isEmpty)
        XCTAssertEqual(detail.id, departure.id)
        XCTAssertEqual(detail.timetable, timetable)
        XCTAssertFalse(detail.name.isEmpty)
        XCTAssertGreaterThan(detail.stops.count, 1)
    }

    func testStationTimetableContract() async throws {
        let client = IDOSDataSource()
        let timetable = try client.resolveTimetable("pid")
        let lineSuggestions = try await client.searchStationTimetableLines(
            prefix: "22",
            limit: 8,
            timetable: timetable
        )
        let line = try XCTUnwrap(lineSuggestions.first { suggestion in
            suggestion.from?.isEmpty == false && suggestion.to?.isEmpty == false
        })
        let from = try XCTUnwrap(line.from)
        let to = try XCTUnwrap(line.to)
        let stopSuggestions = try await client.searchStationTimetableStops(
            prefix: from,
            line: line.text,
            limit: 8,
            timetable: timetable
        )
        let request = TransitStationTimetableRequest(
            timetable: timetable,
            line: line.text,
            from: from,
            to: to,
            serviceDate: try tomorrowServiceDate(),
            wholeWeek: true
        )

        let result = try await client.findStationTimetable(request: request, language: .english)

        XCTAssertTrue(stopSuggestions.contains { suggestion in
            suggestion.text.compare(from, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        })
        XCTAssertEqual(result.timetable, timetable)
        XCTAssertFalse(result.lineName.isEmpty)
        XCTAssertEqual(result.fromStop, from)
        XCTAssertEqual(result.toStop, to)
        XCTAssertGreaterThan(result.stops.count, 1)
        XCTAssertNotNil(result.selectedStop)
        XCTAssertFalse(result.schedules.isEmpty)
    }

    private func exactStation(
        named name: String,
        timetable: TransitTimetable,
        client: IDOSDataSource
    ) async throws -> TransitSuggestion {
        let suggestions = try await client.searchStations(
            prefix: name,
            limit: 8,
            timetable: timetable
        )
        let station = try XCTUnwrap(suggestions.first { suggestion in
            suggestion.text.compare(name, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        })

        XCTAssertEqual(station.dataSourceID, .idos)
        XCTAssertEqual(station.timetableIdentifier, timetable.identifier)
        XCTAssertNotNil(station.identifier)
        return station
    }

    private func tomorrowServiceDate() throws -> TransitDate {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = IDOSDataSource.serviceTimeZone
        let tomorrow = try XCTUnwrap(calendar.date(byAdding: .day, value: 1, to: Date()))
        return TransitDate(tomorrow, calendar: calendar)
    }
}
