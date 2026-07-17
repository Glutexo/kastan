import Foundation
import Kastan
import MCP

/// Runs Kaštan as a local MCP server over standard input and output.
@main
struct KastanMCPApp {
    static func main() async throws {
        try await KastanMCPServer.run(client: IDOSClient())
    }
}

/// Configures the product-facing MCP tools and connects them to an MCP transport.
enum KastanMCPServer {
    static let version = "0.1.0"

    static func makeServer(client: any IDOSClienting) async -> Server {
        let tools = KastanMCPTools(client: client)
        let server = Server(
            name: "kastan-mcp",
            version: version,
            title: "Kaštan",
            instructions: "Search the Czech IDOS journey planner. All tools are read-only and return both JSON text and structured MCP content.",
            capabilities: .init(tools: .init(listChanged: false)),
            configuration: .strict
        )

        await server.withMethodHandler(ListTools.self) { _ in
            .init(tools: KastanMCPTools.definitions)
        }
        await server.withMethodHandler(CallTool.self) { parameters in
            await tools.call(name: parameters.name, arguments: parameters.arguments ?? [:])
        }

        return server
    }

    static func run(client: any IDOSClienting) async throws {
        let server = await makeServer(client: client)
        let transport = StdioTransport()
        try await server.start(transport: transport)
        await server.waitUntilCompleted()
    }
}

/// Exposes the stable Kaštan library operations as read-only MCP tools.
struct KastanMCPTools: Sendable {
    let client: any IDOSClienting

    static let definitions: [Tool] = [
        Tool(
            name: "suggest_places",
            title: "Suggest IDOS places",
            description: "Suggest stops, addresses, and other places matching a text prefix in an IDOS timetable.",
            inputSchema: objectSchema(
                properties: [
                    "prefix": stringSchema("Text prefix to suggest places for."),
                    "timetable": timetableSchema,
                    "limit": integerSchema("Maximum number of suggestions to return. Defaults to 8.", minimum: 1, maximum: 20),
                ],
                required: ["prefix"]
            ),
            annotations: readOnlyAnnotations(title: "Suggest IDOS places"),
            outputSchema: MCPOutputSchemas.suggestedPlaces
        ),
        Tool(
            name: "search_stations",
            title: "Search IDOS stations",
            description: "Search only stations and stops matching a text prefix in an IDOS timetable.",
            inputSchema: objectSchema(
                properties: [
                    "prefix": stringSchema("Station or stop name prefix to search for."),
                    "timetable": timetableSchema,
                    "limit": integerSchema("Maximum number of stations to return. Defaults to 8.", minimum: 1, maximum: 20),
                ],
                required: ["prefix"]
            ),
            annotations: readOnlyAnnotations(title: "Search IDOS stations"),
            outputSchema: MCPOutputSchemas.stations
        ),
        Tool(
            name: "search_station_timetable_lines",
            title: "Search IDOS Station Timetable lines",
            description: "Suggest MHD or integrated-transport lines and their terminal pairs for IDOS Station Timetables.",
            inputSchema: objectSchema(
                properties: [
                    "prefix": stringSchema("Line number or name prefix to search for."),
                    "timetable": timetableSchema,
                    "limit": integerSchema("Maximum number of line directions to return. Defaults to 8.", minimum: 1, maximum: 20),
                ],
                required: ["prefix"]
            ),
            annotations: readOnlyAnnotations(title: "Search IDOS Station Timetable lines"),
            outputSchema: MCPOutputSchemas.stationTimetableLines
        ),
        Tool(
            name: "search_station_timetable_stops",
            title: "Search IDOS Station Timetable stops",
            description: "Suggest stops served by one MHD or integrated-transport line for IDOS Station Timetables.",
            inputSchema: objectSchema(
                properties: [
                    "prefix": stringSchema("Stop name prefix to search for."),
                    "line": stringSchema("Line name returned by search_station_timetable_lines."),
                    "timetable": timetableSchema,
                    "limit": integerSchema("Maximum number of stops to return. Defaults to 8.", minimum: 1, maximum: 20),
                ],
                required: ["prefix", "line"]
            ),
            annotations: readOnlyAnnotations(title: "Search IDOS Station Timetable stops"),
            outputSchema: MCPOutputSchemas.stationTimetableStops
        ),
        Tool(
            name: "find_connections",
            title: "Find IDOS connections",
            description: "Find public transport connections between two places through the Czech IDOS journey planner.",
            inputSchema: objectSchema(
                properties: [
                    "from": stringSchema("Departure place or station."),
                    "to": stringSchema("Arrival place or station."),
                    "timetable": timetableSchema,
                    "date": stringSchema("Search date in the IDOS format d.M.yyyy. Omit to let IDOS use the current date."),
                    "time": stringSchema("Search time in the IDOS format H:mm. Omit to let IDOS use the current time."),
                    "isArrival": booleanSchema("When true, the requested time is the arrival time; otherwise it is the departure time."),
                    "onlyDirect": booleanSchema("When true, return direct connections only."),
                    "via": stringArraySchema("Optional ordered places that the connection must travel via."),
                    "maxTransfers": integerSchema("Maximum permitted number of transfers, including 0.", minimum: 0),
                    "minimumTransferTime": integerSchema("Minimum transfer time in minutes, including 0.", minimum: 0),
                    "limit": integerSchema("Maximum number of connections to return. Defaults to 5.", minimum: 1, maximum: 20),
                ],
                required: ["from", "to"]
            ),
            annotations: readOnlyAnnotations(title: "Find IDOS connections"),
            outputSchema: MCPOutputSchemas.connections
        ),
        Tool(
            name: "find_departures",
            title: "Find IDOS departures",
            description: "Find departures or arrivals at a station through the Czech IDOS journey planner.",
            inputSchema: objectSchema(
                properties: [
                    "station": stringSchema("Station or stop to search at."),
                    "timetable": timetableSchema,
                    "date": stringSchema("Search date in the IDOS format d.M.yyyy. Omit to let IDOS use the current date."),
                    "time": stringSchema("Search time in the IDOS format H:mm. Omit to let IDOS use the current time."),
                    "isArrival": booleanSchema("When true, find arrivals instead of departures."),
                    "limit": integerSchema("Maximum number of departures or arrivals to return. Defaults to 8.", minimum: 1, maximum: 20),
                ],
                required: ["station"]
            ),
            annotations: readOnlyAnnotations(title: "Find IDOS departures"),
            outputSchema: MCPOutputSchemas.departures
        ),
        Tool(
            name: "find_station_timetable",
            title: "Find an IDOS Station Timetable",
            description: "Load an MHD or integrated-transport Station Timetable for one line, direction, date, and selected stop.",
            inputSchema: objectSchema(
                properties: [
                    "line": stringSchema("Line name returned by search_station_timetable_lines."),
                    "from": stringSchema("Stop at which the displayed timetable starts."),
                    "to": stringSchema("Direction stop for the selected line."),
                    "timetable": timetableSchema,
                    "date": stringSchema("Search date in the IDOS format d.M.yyyy. Omit to let IDOS use the current date."),
                    "wholeWeek": booleanSchema("When true, return schedules for the whole week instead of one date."),
                    "language": languageSchema,
                ],
                required: ["line", "from", "to"]
            ),
            annotations: readOnlyAnnotations(title: "Find an IDOS Station Timetable"),
            outputSchema: MCPOutputSchemas.stationTimetable
        ),
        Tool(
            name: "get_service_detail",
            title: "Get an IDOS service detail",
            description: "Load the complete route, stop times, and information for a service ID returned by a connection leg or departure.",
            inputSchema: objectSchema(
                properties: [
                    "id": stringSchema("Opaque service ID returned by Kaštan."),
                    "timetable": stringSchema("Optional timetable context for legacy service IDs that do not embed a timetable slug."),
                    "language": languageSchema,
                ],
                required: ["id"]
            ),
            annotations: readOnlyAnnotations(title: "Get an IDOS service detail"),
            outputSchema: MCPOutputSchemas.serviceDetail
        ),
        Tool(
            name: "list_timetables",
            title: "List IDOS timetables",
            description: "List timetable slugs and English display names accepted by the Kaštan tools.",
            inputSchema: objectSchema(properties: [:]),
            annotations: .init(
                title: "List IDOS timetables",
                readOnlyHint: true,
                destructiveHint: false,
                idempotentHint: true,
                openWorldHint: false
            ),
            outputSchema: MCPOutputSchemas.timetables
        ),
    ]

    func call(name: String, arguments: [String: Value]) async -> CallTool.Result {
        do {
            let output: any Encodable = switch name {
            case "suggest_places":
                try await suggestPlaces(arguments)
            case "search_stations":
                try await searchStations(arguments)
            case "search_station_timetable_lines":
                try await searchStationTimetableLines(arguments)
            case "search_station_timetable_stops":
                try await searchStationTimetableStops(arguments)
            case "find_connections":
                try await findConnections(arguments)
            case "find_departures":
                try await findDepartures(arguments)
            case "find_station_timetable":
                try await findStationTimetable(arguments)
            case "get_service_detail":
                try await getServiceDetail(arguments)
            case "list_timetables":
                try listTimetables(arguments)
            default:
                throw MCPToolError.unknownTool(name)
            }

            return try success(output)
        } catch {
            return .init(
                content: [.text(text: "Error: \(error.localizedDescription)", annotations: nil, _meta: nil)],
                isError: true
            )
        }
    }

    private func suggestPlaces(_ values: [String: Value]) async throws -> SuggestedPlacesOutput {
        let arguments = try ToolArguments(values, allowed: ["prefix", "timetable", "limit"])
        let prefix = try arguments.requiredString("prefix")
        let timetable = try IDOSTimetable.resolve(arguments.optionalString("timetable"))
        let limit = try arguments.integer("limit", default: 8, range: 1...20)
        let suggestions = try await client.suggest(prefix: prefix, limit: limit, timetable: timetable)
        return SuggestedPlacesOutput(query: prefix, timetable: timetable, suggestions: suggestions)
    }

    private func searchStations(_ values: [String: Value]) async throws -> StationsOutput {
        let arguments = try ToolArguments(values, allowed: ["prefix", "timetable", "limit"])
        let prefix = try arguments.requiredString("prefix")
        let timetable = try IDOSTimetable.resolve(arguments.optionalString("timetable"))
        let limit = try arguments.integer("limit", default: 8, range: 1...20)
        let stations = try await client.searchStations(prefix: prefix, limit: limit, timetable: timetable)
        return StationsOutput(query: prefix, timetable: timetable, stations: stations)
    }

    private func searchStationTimetableLines(
        _ values: [String: Value]
    ) async throws -> StationTimetableLinesOutput {
        let arguments = try ToolArguments(values, allowed: ["prefix", "timetable", "limit"])
        let prefix = try arguments.requiredString("prefix")
        let timetable = try IDOSTimetable.resolve(arguments.optionalString("timetable"))
        let limit = try arguments.integer("limit", default: 8, range: 1...20)
        let lines = try await client.searchStationTimetableLines(
            prefix: prefix,
            limit: limit,
            timetable: timetable
        )
        return StationTimetableLinesOutput(query: prefix, timetable: timetable, lines: lines)
    }

    private func searchStationTimetableStops(
        _ values: [String: Value]
    ) async throws -> StationTimetableStopsOutput {
        let arguments = try ToolArguments(values, allowed: ["prefix", "line", "timetable", "limit"])
        let prefix = try arguments.requiredString("prefix")
        let line = try arguments.requiredString("line")
        let timetable = try IDOSTimetable.resolve(arguments.optionalString("timetable"))
        let limit = try arguments.integer("limit", default: 8, range: 1...20)
        let stops = try await client.searchStationTimetableStops(
            prefix: prefix,
            line: line,
            limit: limit,
            timetable: timetable
        )
        return StationTimetableStopsOutput(query: prefix, line: line, timetable: timetable, stops: stops)
    }

    private func findConnections(_ values: [String: Value]) async throws -> ConnectionsOutput {
        let arguments = try ToolArguments(
            values,
            allowed: [
                "from", "to", "timetable", "date", "time", "isArrival", "onlyDirect", "via",
                "maxTransfers", "minimumTransferTime", "limit",
            ]
        )
        let timetable = try IDOSTimetable.resolve(arguments.optionalString("timetable"))
        let request = IDOSConnectionRequest(
            timetable: timetable,
            from: try arguments.requiredString("from"),
            to: try arguments.requiredString("to"),
            date: try arguments.optionalString("date"),
            time: try arguments.optionalString("time"),
            isArrival: try arguments.boolean("isArrival", default: false),
            onlyDirect: try arguments.boolean("onlyDirect", default: false),
            via: try arguments.stringArray("via", default: []),
            maxTransfers: try arguments.optionalInteger("maxTransfers", minimum: 0),
            minimumTransferTime: try arguments.optionalInteger("minimumTransferTime", minimum: 0),
            resultLimit: try arguments.integer("limit", default: 5, range: 1...20)
        )
        let connections = try await client.findConnections(request: request)
        return ConnectionsOutput(request: request, connections: connections)
    }

    private func findDepartures(_ values: [String: Value]) async throws -> DeparturesOutput {
        let arguments = try ToolArguments(values, allowed: ["station", "timetable", "date", "time", "isArrival", "limit"])
        let timetable = try IDOSTimetable.resolve(arguments.optionalString("timetable"))
        let request = IDOSDeparturesRequest(
            timetable: timetable,
            station: try arguments.requiredString("station"),
            date: try arguments.optionalString("date"),
            time: try arguments.optionalString("time"),
            isArrival: try arguments.boolean("isArrival", default: false)
        )
        let limit = try arguments.integer("limit", default: 8, range: 1...20)
        let departures = try await client.findDepartures(request: request)
        return DeparturesOutput(request: request, departures: Array(departures.prefix(limit)))
    }

    private func findStationTimetable(_ values: [String: Value]) async throws -> StationTimetableOutput {
        let arguments = try ToolArguments(
            values,
            allowed: ["line", "from", "to", "timetable", "date", "wholeWeek", "language"]
        )
        let request = IDOSStationTimetableRequest(
            timetable: try IDOSTimetable.resolve(arguments.optionalString("timetable")),
            line: try arguments.requiredString("line"),
            from: try arguments.requiredString("from"),
            to: try arguments.requiredString("to"),
            date: try arguments.optionalString("date"),
            wholeWeek: try arguments.boolean("wholeWeek", default: false)
        )
        let stationTimetable = try await client.findStationTimetable(
            request: request,
            language: try arguments.idosLanguage("language", default: .english)
        )
        return StationTimetableOutput(request: request, stationTimetable: stationTimetable)
    }

    private func getServiceDetail(_ values: [String: Value]) async throws -> ServiceDetailOutput {
        let arguments = try ToolArguments(values, allowed: ["id", "timetable", "language"])
        let id = try arguments.requiredString("id")
        let language = try arguments.idosLanguage("language", default: .english)
        let service: IDOSServiceDetail
        if let timetableValue = try arguments.optionalString("timetable") {
            service = try await client.serviceDetail(
                id: id,
                timetable: IDOSTimetable.resolve(timetableValue),
                language: language
            )
        } else {
            service = try await client.serviceDetail(id: id, language: language)
        }
        return ServiceDetailOutput(service: service)
    }

    private func listTimetables(_ values: [String: Value]) throws -> TimetablesOutput {
        _ = try ToolArguments(values, allowed: [])
        return TimetablesOutput(timetables: IDOSTimetable.known)
    }

    private func success(_ output: any Encodable) throws -> CallTool.Result {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(AnyEncodable(output))
        let value = try JSONDecoder().decode(Value.self, from: data)
        guard let json = String(data: data, encoding: .utf8) else {
            throw MCPToolError.cannotEncodeResult
        }
        return .init(
            content: [.text(text: json, annotations: nil, _meta: nil)],
            structuredContent: Optional.some(value),
            isError: false
        )
    }

    private static func objectSchema(properties: [String: Value], required: [String] = []) -> Value {
        var schema: [String: Value] = [
            "type": "object",
            "properties": .object(properties),
            "additionalProperties": false,
        ]
        if !required.isEmpty {
            schema["required"] = .array(required.map(Value.string))
        }
        return .object(schema)
    }

    private static func stringSchema(_ description: String) -> Value {
        .object(["type": "string", "description": .string(description), "minLength": 1])
    }

    private static func integerSchema(_ description: String, minimum: Int, maximum: Int? = nil) -> Value {
        var schema: [String: Value] = [
            "type": "integer",
            "description": .string(description),
            "minimum": .int(minimum),
        ]
        if let maximum {
            schema["maximum"] = .int(maximum)
        }
        return .object(schema)
    }

    private static func booleanSchema(_ description: String) -> Value {
        .object(["type": "boolean", "description": .string(description)])
    }

    private static func stringArraySchema(_ description: String) -> Value {
        .object([
            "type": "array",
            "description": .string(description),
            "items": .object(["type": "string", "minLength": 1]),
        ])
    }

    private static let timetableSchema = stringSchema(
        "Timetable alias, English catalog name, or IDOS URL slug. Defaults to vlakyautobusymhdvse (All timetables)."
    )

    private static let languageSchema: Value = .object([
        "type": "string",
        "description": "Language for names, notes, and information supplied by IDOS. Defaults to en.",
        "enum": ["en", "cs"],
    ])

    private static func readOnlyAnnotations(title: String) -> Tool.Annotations {
        .init(
            title: title,
            readOnlyHint: true,
            destructiveHint: false,
            idempotentHint: true,
            openWorldHint: true
        )
    }
}
