import Foundation
@testable import Kastan
@testable import KastanMCP
import MCP
import Testing

@Test func serverAdvertisesReadOnlyKastanTools() async throws {
    let server = await KastanMCPServer.makeServer(client: MockIDOSClient())
    let (clientTransport, serverTransport) = await InMemoryTransport.createConnectedPair()
    let client = Client(name: "kastan-mcp-tests", version: "1.0.0", configuration: .strict)

    try await server.start(transport: serverTransport)
    try await client.connect(transport: clientTransport)

    let (tools, _) = try await client.listTools()
    let names = tools.map(\.name)
    #expect(names == [
        "suggest_places",
        "search_stations",
        "search_station_timetable_lines",
        "search_station_timetable_stops",
        "find_connections",
        "find_departures",
        "find_station_timetable",
        "get_service_detail",
        "list_timetables",
    ])
    #expect(tools.allSatisfy { $0.annotations.readOnlyHint == true })
    #expect(tools.allSatisfy { $0.outputSchema?.objectValue?["type"] == "object" })
    #expect(tools.first { $0.name == "find_connections" }?.inputSchema.objectValue?["required"] == ["from", "to"])
    #expect(tools.first { $0.name == "find_connections" }?.outputSchema?.objectValue?["required"] == ["request", "connections"])
    #expect(
        tools.first { $0.name == "find_station_timetable" }?
            .inputSchema.objectValue?["required"] == ["line", "from", "to"]
    )
    #expect(
        tools.first { $0.name == "find_station_timetable" }?
            .outputSchema?.objectValue?["required"] == ["request", "stationTimetable"]
    )
    #expect(
        tools.first { $0.name == "get_service_detail" }?
            .inputSchema.objectValue?["properties"]?.objectValue?["language"]?.objectValue?["enum"] == ["en", "cs"]
    )

    let result: (content: [Tool.Content], isError: Bool?) = try await client.callTool(name: "list_timetables")
    #expect(result.isError == false)
    #expect(text(from: result.content)?.contains("\"slug\" : \"vlakyautobusymhdvse\"") == true)

    await client.disconnect()
    await server.stop()
}

@Test func connectionToolPassesValidatedRequestToKastan() async throws {
    let mock = MockIDOSClient()
    let tools = KastanMCPTools(client: mock)
    let result = await tools.call(
        name: "find_connections",
        arguments: [
            "from": " Praha ",
            "to": "Brno",
            "timetable": "trains",
            "date": "18.6.2026",
            "time": "12:00",
            "isArrival": true,
            "onlyDirect": true,
            "via": ["Pardubice", "Olomouc"],
            "maxTransfers": 1,
            "minimumTransferTime": 10,
            "limit": 7,
        ]
    )

    #expect(result.isError == false)
    #expect(result.structuredContent?.objectValue?["connections"]?.arrayValue?.count == 1)
    #expect(text(from: result.content)?.contains("\"departureStation\" : \"Praha hl.n.\"") == true)

    let request = await mock.lastConnectionRequest
    #expect(request?.from == "Praha")
    #expect(request?.to == "Brno")
    #expect(request?.timetable.slug == "vlaky")
    #expect(request?.date == "18.6.2026")
    #expect(request?.time == "12:00")
    #expect(request?.isArrival == true)
    #expect(request?.onlyDirect == true)
    #expect(request?.via == ["Pardubice", "Olomouc"])
    #expect(request?.maxTransfers == 1)
    #expect(request?.minimumTransferTime == 10)
    #expect(request?.resultLimit == 7)
}

@Test func suggestionAndStationToolsUseTheirDistinctLibraryOperations() async {
    let mock = MockIDOSClient()
    let tools = KastanMCPTools(client: mock)

    let suggestions = await tools.call(
        name: "suggest_places",
        arguments: ["prefix": "Svinov", "timetable": "odis", "limit": 3]
    )
    let stations = await tools.call(
        name: "search_stations",
        arguments: ["prefix": "Praha"]
    )

    #expect(suggestions.structuredContent?.objectValue?["suggestions"]?.arrayValue?.count == 1)
    #expect(stations.structuredContent?.objectValue?["stations"]?.arrayValue?.count == 1)
    #expect(await mock.lastSuggestionQuery == QueryCall(prefix: "Svinov", limit: 3, timetableSlug: "odis"))
    #expect(await mock.lastStationQuery == QueryCall(prefix: "Praha", limit: 8, timetableSlug: "vlakyautobusymhdvse"))
}

@Test func stationTimetableSuggestionToolsKeepLineDirectionContext() async {
    let mock = MockIDOSClient()
    let tools = KastanMCPTools(client: mock)
    let lines = await tools.call(
        name: "search_station_timetable_lines",
        arguments: ["prefix": "154", "timetable": "pid", "limit": 3]
    )
    let stops = await tools.call(
        name: "search_station_timetable_stops",
        arguments: ["prefix": "Straš", "line": "Bus 154", "timetable": "pid"]
    )

    let line = lines.structuredContent?.objectValue?["lines"]?.arrayValue?.first?.objectValue
    #expect(line?["text"]?.stringValue == "Bus 154")
    #expect(line?["from"]?.stringValue == "Strašnická")
    #expect(line?["to"]?.stringValue == "Sídliště Libuš")
    #expect(stops.structuredContent?.objectValue?["stops"]?.arrayValue?.first?.objectValue?["text"] == "Strašnická")
    #expect(await mock.lastStationTimetableLineQuery == QueryCall(prefix: "154", limit: 3, timetableSlug: "pid"))
    #expect(await mock.lastStationTimetableStopQuery == StationTimetableStopQuery(
        prefix: "Straš",
        line: "Bus 154",
        limit: 8,
        timetableSlug: "pid"
    ))
}

@Test func departureToolLimitsReturnedRowsWithoutChangingIDOSRequest() async {
    let mock = MockIDOSClient()
    let tools = KastanMCPTools(client: mock)
    let result = await tools.call(
        name: "find_departures",
        arguments: [
            "station": "Ostrava-Svinov",
            "time": "16:00",
            "isArrival": true,
            "limit": 1,
        ]
    )

    #expect(result.isError == false)
    #expect(result.structuredContent?.objectValue?["departures"]?.arrayValue?.count == 1)
    let request = await mock.lastDeparturesRequest
    #expect(request?.station == "Ostrava-Svinov")
    #expect(request?.time == "16:00")
    #expect(request?.isArrival == true)
}

@Test func stationTimetableToolPassesCompleteRequestAndLanguageToKastan() async {
    let mock = MockIDOSClient()
    let tools = KastanMCPTools(client: mock)
    let result = await tools.call(
        name: "find_station_timetable",
        arguments: [
            "line": " Bus 154 ",
            "from": " Strašnická ",
            "to": "Sídliště Libuš",
            "timetable": "pid",
            "date": "17.7.2026",
            "wholeWeek": true,
            "language": "cs",
        ]
    )

    #expect(result.isError == false)
    let timetable = result.structuredContent?.objectValue?["stationTimetable"]?.objectValue
    #expect(timetable?["lineName"] == "Bus 154")
    #expect(timetable?["stops"]?.arrayValue?.count == 2)
    #expect(timetable?["schedules"]?.arrayValue?.first?.objectValue?["hours"]?.arrayValue?.count == 1)
    let request = await mock.lastStationTimetableRequest
    #expect(request?.line == "Bus 154")
    #expect(request?.from == "Strašnická")
    #expect(request?.to == "Sídliště Libuš")
    #expect(request?.timetable.slug == "pid")
    #expect(request?.date == "17.7.2026")
    #expect(request?.wholeWeek == true)
    #expect(await mock.lastStationTimetableLanguage == .czech)
}

@Test func serviceDetailToolLoadsCompleteRouteByOpaqueID() async {
    let mock = MockIDOSClient()
    let tools = KastanMCPTools(client: mock)
    let result = await tools.call(
        name: "get_service_detail",
        arguments: [
            "id": "vlaky:0-74552-18.06.2026 12:04:00",
        ]
    )

    #expect(result.isError == false)
    #expect(result.structuredContent?.objectValue?["service"]?.objectValue?["stops"]?.arrayValue?.count == 2)
    #expect(result.structuredContent?.objectValue?["service"]?.objectValue?["timetable"]?.objectValue?["slug"]?.stringValue == "vlaky")
    #expect(text(from: result.content)?.contains("\"name\" : \"RJ 1051 RegioJet\"") == true)
    #expect(await mock.lastServiceID == "vlaky:0-74552-18.06.2026 12:04:00")
    #expect(await mock.lastServiceTimetable == IDOSTimetable.defaultTimetable.slug)
    #expect(await mock.lastServiceLanguage == .english)
}

@Test func serviceDetailToolPassesSelectedLanguageAndLegacyTimetable() async {
    let mock = MockIDOSClient()
    let tools = KastanMCPTools(client: mock)
    let result = await tools.call(
        name: "get_service_detail",
        arguments: [
            "id": "0-74552-18.06.2026 12:04:00",
            "timetable": "odis",
            "language": "cs",
        ]
    )

    #expect(result.isError == false)
    #expect(await mock.lastServiceID == "0-74552-18.06.2026 12:04:00")
    #expect(await mock.lastServiceTimetable == "odis")
    #expect(await mock.lastServiceLanguage == .czech)
}

@Test func invalidToolArgumentsReturnMCPToolErrorsWithoutCallingIDOS() async {
    let mock = MockIDOSClient()
    let tools = KastanMCPTools(client: mock)

    let missing = await tools.call(name: "find_connections", arguments: ["from": "Praha"])
    let wrongType = await tools.call(name: "find_departures", arguments: ["station": "Praha", "limit": "many"])
    let invalidLanguage = await tools.call(
        name: "get_service_detail",
        arguments: ["id": "vlaky:service", "language": "de"]
    )
    let unknown = await tools.call(name: "list_timetables", arguments: ["extra": true])

    #expect(missing.isError == true)
    #expect(text(from: missing.content) == "Error: Missing required argument 'to'.")
    #expect(wrongType.isError == true)
    #expect(text(from: wrongType.content) == "Error: Argument 'limit' must be an integer.")
    #expect(invalidLanguage.isError == true)
    #expect(text(from: invalidLanguage.content) == "Error: Invalid value 'de' for argument 'language'. Use en or cs.")
    #expect(unknown.isError == true)
    #expect(text(from: unknown.content) == "Error: Unknown argument: extra.")
    #expect(await mock.lastConnectionRequest == nil)
    #expect(await mock.lastDeparturesRequest == nil)
}

private func text(from content: [Tool.Content]) -> String? {
    guard case .text(let text, _, _)? = content.first else {
        return nil
    }
    return text
}

private struct QueryCall: Equatable, Sendable {
    let prefix: String
    let limit: Int
    let timetableSlug: String
}

private struct StationTimetableStopQuery: Equatable, Sendable {
    let prefix: String
    let line: String
    let limit: Int
    let timetableSlug: String
}

private actor MockIDOSClient: IDOSClienting {
    var lastSuggestionQuery: QueryCall?
    var lastStationQuery: QueryCall?
    var lastStationTimetableLineQuery: QueryCall?
    var lastStationTimetableStopQuery: StationTimetableStopQuery?
    var lastConnectionRequest: IDOSConnectionRequest?
    var lastDeparturesRequest: IDOSDeparturesRequest?
    var lastStationTimetableRequest: IDOSStationTimetableRequest?
    var lastStationTimetableLanguage: IDOSLanguage?
    var lastServiceID: String?
    var lastServiceTimetable: String?
    var lastServiceLanguage: IDOSLanguage?

    func suggest(prefix: String, limit: Int, timetable: IDOSTimetable) async throws -> [IDOSSuggestion] {
        lastSuggestionQuery = QueryCall(prefix: prefix, limit: limit, timetableSlug: timetable.slug)
        return [IDOSSuggestion(text: "Ostrava-Svinov")]
    }

    func searchStations(prefix: String, limit: Int, timetable: IDOSTimetable) async throws -> [IDOSSuggestion] {
        lastStationQuery = QueryCall(prefix: prefix, limit: limit, timetableSlug: timetable.slug)
        return [IDOSSuggestion(text: "Praha hl.n.")]
    }

    func searchStationTimetableLines(
        prefix: String,
        limit: Int,
        timetable: IDOSTimetable
    ) async throws -> [IDOSSuggestion] {
        lastStationTimetableLineQuery = QueryCall(prefix: prefix, limit: limit, timetableSlug: timetable.slug)
        return [IDOSSuggestion(
            text: "Bus 154",
            description: "Strašnická-Sídliště Libuš",
            from: "Strašnická",
            to: "Sídliště Libuš"
        )]
    }

    func searchStationTimetableStops(
        prefix: String,
        line: String,
        limit: Int,
        timetable: IDOSTimetable
    ) async throws -> [IDOSSuggestion] {
        lastStationTimetableStopQuery = StationTimetableStopQuery(
            prefix: prefix,
            line: line,
            limit: limit,
            timetableSlug: timetable.slug
        )
        return [IDOSSuggestion(text: "Strašnická", description: "Station")]
    }

    func findConnections(request: IDOSConnectionRequest) async throws -> [IDOSConnection] {
        lastConnectionRequest = request
        return [
            IDOSConnection(
                id: "connection-1",
                departureTime: "12:00",
                departureStation: "Praha hl.n.",
                arrivalTime: "14:35",
                arrivalStation: "Brno hl.n.",
                duration: "2 hod 35 min",
                legs: []
            ),
        ]
    }

    func connectionCalendar(for connection: IDOSConnection, timetable: IDOSTimetable) async throws -> String {
        "BEGIN:VCALENDAR\nEND:VCALENDAR"
    }

    func findDepartures(request: IDOSDeparturesRequest) async throws -> [IDOSDeparture] {
        lastDeparturesRequest = request
        return [
            IDOSDeparture(id: "departure-1", time: "16:01", lineName: "S2", destination: "Opava"),
            IDOSDeparture(id: "departure-2", time: "16:05", lineName: "S4", destination: "Bohumín"),
        ]
    }

    func findStationTimetable(
        request: IDOSStationTimetableRequest,
        language: IDOSLanguage
    ) async throws -> IDOSStationTimetable {
        lastStationTimetableRequest = request
        lastStationTimetableLanguage = language
        return IDOSStationTimetable(
            timetable: request.timetable,
            lineName: request.line,
            transportMode: .bus,
            fromStop: request.from,
            toStop: request.to,
            stops: [
                IDOSStationTimetableStop(name: request.from, minuteOffset: 0, isSelected: true),
                IDOSStationTimetableStop(name: request.to, minuteOffset: 42),
            ],
            schedules: [
                IDOSStationTimetableSchedule(
                    label: "17.7.2026 Friday",
                    hours: [IDOSStationTimetableHour(hour: "5", departures: ["13", "35"])]
                ),
            ],
            notes: ["valid from 1.7.2026"],
            shareURL: "https://idos.cz/en/pid/zjr/"
        )
    }

    func serviceDetail(id: String, timetable: IDOSTimetable) async throws -> IDOSServiceDetail {
        lastServiceID = id
        lastServiceTimetable = timetable.slug
        lastServiceLanguage = .english
        return serviceDetailFixture(id: id)
    }

    func serviceDetail(
        id: String,
        timetable: IDOSTimetable,
        language: IDOSLanguage
    ) async throws -> IDOSServiceDetail {
        lastServiceID = id
        lastServiceTimetable = timetable.slug
        lastServiceLanguage = language
        return serviceDetailFixture(id: id)
    }

    private func serviceDetailFixture(id: String) -> IDOSServiceDetail {
        return IDOSServiceDetail(
            id: id,
            timetable: IDOSTimetable(slug: "vlaky", displayName: "Trains"),
            name: "RJ 1051 RegioJet",
            transportMode: .train,
            date: "18.6.2026",
            stops: [
                IDOSServiceStop(name: "Praha hl.n.", departureTime: "12:04"),
                IDOSServiceStop(name: "Brno hl.n.", arrivalTime: "15:44"),
            ]
        )
    }
}
