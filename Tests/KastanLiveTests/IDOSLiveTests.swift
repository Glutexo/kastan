import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import Kastan
import XCTest

/// Exercises Kaštan's public library API against the current, unmocked IDOS service.
final class IDOSLiveTests: XCTestCase {
    private static let optInEnvironmentVariable = "KASTAN_RUN_LIVE_IDOS_TESTS"
    private static let safariUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) " +
        "AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.6.2 Safari/605.1.15"

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
        let fromSuggestion = try exactSuggestion(
            named: "Praha hl.n.",
            in: try await client.suggest(prefix: "Praha hl.n.", limit: 8, timetable: timetable)
        )
        let toSuggestion = try exactSuggestion(
            named: "Brno hl.n.",
            in: try await client.suggest(prefix: "Brno hl.n.", limit: 8, timetable: timetable)
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
            maxTransfers: 4,
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
        let stationSuggestion = try await exactStation(
            named: "Praha hl.n.",
            timetable: timetable,
            client: client
        )
        let request = TransitDeparturesRequest(
            timetable: timetable,
            station: stationSuggestion.text,
            stationSelection: try XCTUnwrap(TransitPlaceSelection(suggestion: stationSuggestion)),
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

    func testConnectionRequestMatchesPublishedBrowserFormContract() async throws {
        let formURL = try XCTUnwrap(
            URL(string: "https://idos.cz/en/vlakyautobusymhdvse/spojeni/")
        )
        let (data, response) = try await htmlResponse(
            from: formURL,
            userAgent: IDOSDataSource.userAgent
        )
        let (safariData, safariResponse) = try await htmlResponse(
            from: formURL,
            userAgent: Self.safariUserAgent
        )
        let httpResponse = try XCTUnwrap(response as? HTTPURLResponse)
        let safariHTTPResponse = try XCTUnwrap(safariResponse as? HTTPURLResponse)
        let html = try XCTUnwrap(String(data: data, encoding: .utf8))
        let safariHTML = try XCTUnwrap(String(data: safariData, encoding: .utf8))
        let contract = try XCTUnwrap(IDOSConnectionFormParser.contract(in: html))
        let safariContract = try XCTUnwrap(IDOSConnectionFormParser.contract(in: safariHTML))
        let request = TransitConnectionRequest(
            from: "Praha",
            to: "Brno",
            transportModeFilter: .init(operation: .exclude, modes: [.regionalTrain]),
            maxTransfers: 3,
            sameNameWalkingTransfersOnly: true,
            wheelchairAccessibleConnectionsOnly: true,
            lowFloorConnectionsOnly: true,
            preferTrainsOverBuses: true,
            trainConnectionsForWheelchairPassengers: true,
            trainConnectionsForPassengersWithChildren: true,
            connectionsForPassengersWithBicycles: true,
            preferBusyRoutes: true
        )
        let items = request.formItems(using: contract)
        let values = Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value) })
        let sentTransportModeIDs = items.compactMap { item -> Int? in
            guard item.name.hasPrefix("trTypeId[") else { return nil }
            return item.value.flatMap(Int.init)
        }

        XCTAssertEqual(httpResponse.statusCode, 200)
        XCTAssertEqual(httpResponse.mimeType, "text/html")
        XCTAssertEqual(safariHTTPResponse.statusCode, 200)
        XCTAssertEqual(safariHTTPResponse.mimeType, httpResponse.mimeType)
        XCTAssertEqual(safariContract, contract)
        XCTAssertEqual(
            sentTransportModeIDs,
            contract.transportModeIDs.filter { $0 != 153 }
        )
        XCTAssertEqual(values["AdvancedForm.AdvancedFormIsOpen"] ?? nil, "true")
        XCTAssertEqual(values["AdvancedForm.MaxChange"] ?? nil, "3")
        let toggleNames = [
            "AdvancedForm.LimitWalkArcs",
            "AdvancedForm.LowDeckConn",
            "AdvancedForm.LowDeckConnTr",
            "AdvancedForm.PrefereTrains",
            "AdvancedForm.WheelChair",
            "AdvancedForm.Children",
            "AdvancedForm.Bicycle",
            "AdvancedForm.AutoStrategy",
        ]
        XCTAssertFalse(toggleNames.filter(contract.contains).isEmpty)
        for name in toggleNames {
            if contract.contains(name) {
                XCTAssertEqual(contract.value(for: name), "false", "Unexpected IDOS value for \(name).")
                XCTAssertEqual(values[name] ?? nil, "false", "Kaštan did not mirror \(name).")
            } else {
                XCTAssertNil(values[name] ?? nil, "Kaštan sent unpublished control \(name).")
            }
        }
        XCTAssertEqual(values["DefaultMaxArcLengthFrom"] ?? nil, contract.value(for: "DefaultMaxArcLengthFrom"))
    }

    func testKastanAndSafariReceiveEquivalentAutocompleteDataAndFormat() async throws {
        var components = try XCTUnwrap(
            URLComponents(string: "https://idos.cz/en/vlaky/Ajax/SearchTimetableObjects/")
        )
        components.queryItems = [
            URLQueryItem(name: "count", value: "18"),
            URLQueryItem(name: "prefixText", value: "Praha"),
            URLQueryItem(name: "searchByPosition", value: "true"),
            URLQueryItem(name: "onlyStation", value: "false"),
            URLQueryItem(name: "line", value: ""),
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "bindTtIndex", value: ""),
            URLQueryItem(name: "date", value: ""),
            URLQueryItem(name: "callback", value: "idosContractCallback"),
            URLQueryItem(name: "_", value: String(Int(Date().timeIntervalSince1970 * 1_000))),
        ]
        let url = try XCTUnwrap(components.url)
        let referer = try XCTUnwrap(URL(string: "https://idos.cz/en/vlaky/spojeni/"))
        let (data, response) = try await javaScriptResponse(
            from: url,
            referer: referer,
            userAgent: IDOSDataSource.userAgent
        )
        let (safariData, safariResponse) = try await javaScriptResponse(
            from: url,
            referer: referer,
            userAgent: Self.safariUserAgent
        )
        let httpResponse = try XCTUnwrap(response as? HTTPURLResponse)
        let safariHTTPResponse = try XCTUnwrap(safariResponse as? HTTPURLResponse)
        let suggestions = try JSONDecoder().decode(
            [TransitSuggestion].self,
            from: IDOSJSONP.decodePayload(from: data)
        )
        let safariSuggestions = try JSONDecoder().decode(
            [TransitSuggestion].self,
            from: IDOSJSONP.decodePayload(from: safariData)
        )

        XCTAssertEqual(httpResponse.statusCode, 200)
        XCTAssertEqual(httpResponse.mimeType, "application/x-javascript")
        XCTAssertEqual(safariHTTPResponse.statusCode, 200)
        XCTAssertEqual(safariHTTPResponse.mimeType, httpResponse.mimeType)
        XCTAssertEqual(safariSuggestions, suggestions)
        XCTAssertFalse(suggestions.isEmpty)
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

    private func htmlResponse(
        from url: URL,
        userAgent: String
    ) async throws -> (Data, URLResponse) {
        var request = URLRequest(url: url)
        request.setValue(
            "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
            forHTTPHeaderField: "Accept"
        )
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        return try await URLSession.shared.data(for: request)
    }

    private func javaScriptResponse(
        from url: URL,
        referer: URL,
        userAgent: String
    ) async throws -> (Data, URLResponse) {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
        request.setValue(
            "text/javascript, application/javascript, application/ecmascript, " +
                "application/x-ecmascript, */*; q=0.01",
            forHTTPHeaderField: "Accept"
        )
        request.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
        request.setValue(referer.absoluteString, forHTTPHeaderField: "Referer")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        return try await URLSession.shared.data(for: request)
    }

    private func exactSuggestion(
        named name: String,
        in suggestions: [TransitSuggestion]
    ) throws -> TransitSuggestion {
        let suggestion = try XCTUnwrap(suggestions.first { suggestion in
            suggestion.text.compare(
                name,
                options: [.caseInsensitive, .diacriticInsensitive]
            ) == .orderedSame
        })
        XCTAssertEqual(suggestion.dataSourceID, .idos)
        XCTAssertNotNil(suggestion.identifier)
        return suggestion
    }

    private func tomorrowServiceDate() throws -> TransitDate {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = IDOSDataSource.serviceTimeZone
        let tomorrow = try XCTUnwrap(calendar.date(byAdding: .day, value: 1, to: Date()))
        return TransitDate(tomorrow, calendar: calendar)
    }
}
