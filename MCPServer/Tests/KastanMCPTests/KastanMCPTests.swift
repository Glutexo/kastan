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
        "find_connections",
        "find_departures",
        "list_timetables",
    ])
    #expect(tools.allSatisfy { $0.annotations.readOnlyHint == true })
    #expect(tools.first { $0.name == "find_connections" }?.inputSchema.objectValue?["required"] == ["from", "to"])

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

@Test func invalidToolArgumentsReturnMCPToolErrorsWithoutCallingIDOS() async {
    let mock = MockIDOSClient()
    let tools = KastanMCPTools(client: mock)

    let missing = await tools.call(name: "find_connections", arguments: ["from": "Praha"])
    let wrongType = await tools.call(name: "find_departures", arguments: ["station": "Praha", "limit": "many"])
    let unknown = await tools.call(name: "list_timetables", arguments: ["extra": true])

    #expect(missing.isError == true)
    #expect(text(from: missing.content) == "Error: Missing required argument 'to'.")
    #expect(wrongType.isError == true)
    #expect(text(from: wrongType.content) == "Error: Argument 'limit' must be an integer.")
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

private actor MockIDOSClient: IDOSClienting {
    var lastSuggestionQuery: QueryCall?
    var lastStationQuery: QueryCall?
    var lastConnectionRequest: IDOSConnectionRequest?
    var lastDeparturesRequest: IDOSDeparturesRequest?

    func suggest(prefix: String, limit: Int, timetable: IDOSTimetable) async throws -> [IDOSSuggestion] {
        lastSuggestionQuery = QueryCall(prefix: prefix, limit: limit, timetableSlug: timetable.slug)
        return [IDOSSuggestion(text: "Ostrava-Svinov")]
    }

    func searchStations(prefix: String, limit: Int, timetable: IDOSTimetable) async throws -> [IDOSSuggestion] {
        lastStationQuery = QueryCall(prefix: prefix, limit: limit, timetableSlug: timetable.slug)
        return [IDOSSuggestion(text: "Praha hl.n.")]
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
}
