import Foundation
@testable import Kastan
@testable import KastanMCP
import MCP
import Testing

@Test func serverAdvertisesReadOnlyKastanTools() async throws {
    let server = await KastanMCPServer.makeServer(dataSource: MockIDOSClient())
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
    #expect(tools.allSatisfy {
        let properties = $0.inputSchema.objectValue?["properties"]?.objectValue
        return properties?["dataSource"] == nil && properties?["source"] == nil
    })
    #expect(tools.first { $0.name == "find_connections" }?.inputSchema.objectValue?["required"] == ["from", "to"])
    #expect(tools.first { $0.name == "find_connections" }?.outputSchema?.objectValue?["required"] == ["request", "connections"])
    let connectionProperties = try #require(
        tools.first { $0.name == "find_connections" }?
            .inputSchema.objectValue?["properties"]?.objectValue
    )
    #expect(Set(connectionProperties.keys) == Set([
        "from", "to", "timetable", "date", "time", "isArrival", "limit",
    ] + TransitConnectionOption.allCases.map(\.mcpArgumentName)))
    #expect(TransitConnectionOption.allCases.map(\.mcpArgumentName).count == 18)
    #expect(connectionProperties["minimumTransferTime"]?.objectValue?["minimum"] == -1)
    let transportModeItems = try #require(
        connectionProperties["transportModeFilters"]?.objectValue?["items"]?.objectValue
    )
    #expect(transportModeItems["required"] == ["operation", "mode"])
    #expect(
        transportModeItems["properties"]?.objectValue?["operation"]?.objectValue?["enum"]
            == ["only", "exclude"]
    )
    #expect(
        transportModeItems["properties"]?.objectValue?["mode"]?.objectValue?["enum"]
            == .array(TransitConnectionTransportMode.allCases.map { Value.string($0.rawValue) })
    )
    #expect(
        connectionProperties["bedOrCouchettePreference"]?.objectValue?["enum"]
            == ["noLimitation", "use", "doNotUse"]
    )
    #expect(
        tools.first { $0.name == "find_station_timetable" }?
            .inputSchema.objectValue?["required"] == ["line", "from", "to"]
    )
    #expect(
        tools.first { $0.name == "search_station_timetable_lines" }?
            .inputSchema.objectValue?["properties"]?.objectValue?["municipality"]?
            .objectValue?["type"] == "string"
    )
    #expect(
        tools.first { $0.name == "find_station_timetable" }?
            .outputSchema?.objectValue?["required"] == ["request", "stationTimetable"]
    )
    #expect(
        tools.first { $0.name == "find_station_timetable" }?
            .outputSchema?.objectValue?["properties"]?.objectValue?["stationTimetable"]?
            .objectValue?["properties"]?.objectValue?["explanations"]?.objectValue?["type"] == "array"
    )
    #expect(
        tools.first { $0.name == "get_service_detail" }?
            .inputSchema.objectValue?["properties"]?.objectValue?["language"]?.objectValue?["enum"] == ["en", "cs"]
    )

    let result: (content: [Tool.Content], isError: Bool?) = try await client.callTool(name: "list_timetables")
    #expect(result.isError == false)
    #expect(text(from: result.content)?.contains("\"slug\" : \"vlakyautobusymhdvse\"") == true)
    #expect(text(from: result.content)?.contains("\"slug\" : \"idsok\"") == true)
    #expect(text(from: result.content)?.contains("\"slug\" : \"iredo\"") == true)
    #expect(text(from: result.content)?.contains("\"slug\" : \"ideska\"") == true)
    #expect(text(from: result.content)?.contains("\"slug\" : \"ceskykrumlov\"") == true)
    #expect(text(from: result.content)?.contains("\"slug\" : \"varnsdorf\"") == true)
    #expect(text(from: result.content)?.contains("\"slug\" : \"praha\"") == false)

    await client.disconnect()
    await server.stop()
}

@Test func connectionToolPassesValidatedRequestToKastan() async throws {
    let mock = MockIDOSClient()
    let tools = KastanMCPTools(dataSource: mock)
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
            "transportModeFilters": .array([
                .object(["operation": "only", "mode": "regionalTrain"]),
                .object(["operation": "exclude", "mode": "cityTrolleybus"]),
            ]),
            "maxTransfers": 1,
            "minimumTransferTime": -1,
            "maximumTransferTime": 360,
            "maximumWalkingTime": 45,
            "maximumCityWalkingTime": 20,
            "walkToNearbyStops": true,
            "sameNameWalkingTransfersOnly": false,
            "wheelchairAccessibleConnectionsOnly": true,
            "lowFloorConnectionsOnly": false,
            "preferTrainsOverBuses": true,
            "trainConnectionsForWheelchairPassengers": false,
            "trainConnectionsForPassengersWithChildren": true,
            "connectionsForPassengersWithBicycles": false,
            "preferBusyRoutes": true,
            "bedOrCouchettePreference": "use",
            "limit": 7,
        ]
    )

    #expect(result.isError == false)
    #expect(result.structuredContent?.objectValue?["connections"]?.arrayValue?.count == 1)
    let serviceInformation = result.structuredContent?
        .objectValue?["connections"]?.arrayValue?.first?
        .objectValue?["legs"]?.arrayValue?.first?
        .objectValue?["serviceInformation"]?.arrayValue?.first?.objectValue
    #expect(serviceInformation?["category"]?.stringValue == "wiFi")
    #expect(serviceInformation?["text"]?.stringValue == "Wireless internet connection")
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
    #expect(request?.transportModeFilters == [
        .init(operation: .only, mode: .regionalTrain),
        .init(operation: .exclude, mode: .cityTrolleybus),
    ])
    #expect(request?.maxTransfers == 1)
    #expect(request?.minimumTransferTime == -1)
    #expect(request?.maximumTransferTime == 360)
    #expect(request?.maximumWalkingTime == 45)
    #expect(request?.maximumCityWalkingTime == 20)
    #expect(request?.walkToNearbyStops == true)
    #expect(request?.sameNameWalkingTransfersOnly == false)
    #expect(request?.wheelchairAccessibleConnectionsOnly == true)
    #expect(request?.lowFloorConnectionsOnly == false)
    #expect(request?.preferTrainsOverBuses == true)
    #expect(request?.trainConnectionsForWheelchairPassengers == false)
    #expect(request?.trainConnectionsForPassengersWithChildren == true)
    #expect(request?.connectionsForPassengersWithBicycles == false)
    #expect(request?.preferBusyRoutes == true)
    #expect(request?.bedOrCouchettePreference == .use)
    #expect(request?.resultLimit == 7)
    #expect(
        result.structuredContent?.objectValue?["request"]?
            .objectValue?["bedOrCouchettePreference"] == "use"
    )
    #expect(
        result.structuredContent?.objectValue?["request"]?
            .objectValue?["transportModeFilters"]?.arrayValue?.count == 2
    )
    let outputSchema = try #require(
        KastanMCPTools.definitions.first { $0.name == "find_connections" }?.outputSchema
    )
    #expect(
        schemaValidationErrors(
            for: try #require(result.structuredContent),
            schema: outputSchema
        ).isEmpty
    )
}

@Test func connectionToolRejectsTimetableSpecificOptionBeforeCallingIDOS() async {
    let mock = MockIDOSClient()
    let tools = KastanMCPTools(dataSource: mock)
    let result = await tools.call(
        name: "find_connections",
        arguments: [
            "from": "Praha",
            "to": "Brno",
            "timetable": "autobusy",
            "bedOrCouchettePreference": "use",
        ]
    )

    #expect(result.isError == true)
    #expect(
        text(from: result.content)
            == "Error: Argument 'bedOrCouchettePreference' is not supported for timetable Buses (autobusy)."
    )
    #expect(await mock.lastConnectionRequest == nil)
}

/// Keeps the public IDOS MCP schema stable when library models retain internal timetable routing metadata.
@Test func nonDefaultTimetableOutputsOmitInternalRoutingMetadataAndMatchTheirSchemas() async throws {
    let tools = KastanMCPTools(dataSource: MockIDOSClient())
    let calls: [(name: String, arguments: [String: Value])] = [
        ("suggest_places", ["prefix": "Svinov", "timetable": "odis"]),
        ("search_stations", ["prefix": "Svinov", "timetable": "odis"]),
        (
            "search_station_timetable_lines",
            ["prefix": "301", "timetable": "odis", "municipality": "FM"]
        ),
        (
            "search_station_timetable_stops",
            ["prefix": "Stra", "line": "Bus 154", "timetable": "odis", "municipality": "FM"]
        ),
        ("find_connections", ["from": "Praha", "to": "Brno", "timetable": "odis"]),
        ("find_departures", ["station": "Ostrava-Svinov", "timetable": "odis"]),
    ]

    for call in calls {
        let result = await tools.call(name: call.name, arguments: call.arguments)
        let structuredContent = try #require(result.structuredContent)
        let schema = try #require(
            KastanMCPTools.definitions.first { $0.name == call.name }?.outputSchema
        )

        #expect(result.isError == false)
        #expect(!containsInternalRoutingMetadata(structuredContent))
        #expect(text(from: result.content)?.contains("\"timetableIdentifier\"") == false)
        #expect(text(from: result.content)?.contains("\"dataSourceID\"") == false)
        #expect(schemaValidationErrors(for: structuredContent, schema: schema).isEmpty)
    }
}

@Test func suggestionAndStationToolsUseTheirDistinctLibraryOperations() async {
    let mock = MockIDOSClient()
    let tools = KastanMCPTools(dataSource: mock)

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
    let tools = KastanMCPTools(dataSource: mock)
    let lines = await tools.call(
        name: "search_station_timetable_lines",
        arguments: [
            "prefix": "301", "timetable": "odis", "municipality": "Frýdek-Místek",
            "limit": 3,
        ]
    )
    let stops = await tools.call(
        name: "search_station_timetable_stops",
        arguments: [
            "prefix": "Ře", "line": "Bus 154", "timetable": "odis",
            "municipality": "FM",
        ]
    )

    let line = lines.structuredContent?.objectValue?["lines"]?.arrayValue?.first?.objectValue
    #expect(line?["text"]?.stringValue == "Bus 154")
    #expect(line?["from"]?.stringValue == "Strašnická")
    #expect(line?["to"]?.stringValue == "Sídliště Libuš")
    #expect(lines.structuredContent?.objectValue?["municipality"]?.objectValue?["name"] == "Frýdek-Místek")
    #expect(stops.structuredContent?.objectValue?["stops"]?.arrayValue?.first?.objectValue?["text"] == "Strašnická")
    #expect(await mock.lastStationTimetableLineQuery == QueryCall(prefix: "301", limit: 3, timetableSlug: "odis"))
    #expect(await mock.lastStationTimetableLineMunicipality?.timetableName == "FM")
    #expect(await mock.lastStationTimetableStopQuery == StationTimetableStopQuery(
        prefix: "Ře",
        line: "Bus 154",
        limit: 8,
        timetableSlug: "odis"
    ))
    #expect(await mock.lastStationTimetableStopMunicipality?.timetableIndex == 3)
}

@Test func stationTimetableSuggestionToolsUseIREDODefaultMunicipality() async {
    let mock = MockIDOSClient()
    let tools = KastanMCPTools(dataSource: mock)
    let lines = await tools.call(
        name: "search_station_timetable_lines",
        arguments: ["prefix": "481", "timetable": "iredo"]
    )

    #expect(
        lines.structuredContent?.objectValue?["municipality"]?.objectValue?["name"]
            == "Dvůr Králové nad Labem"
    )
    #expect(await mock.lastStationTimetableLineQuery == QueryCall(
        prefix: "481",
        limit: 8,
        timetableSlug: "iredo"
    ))
    #expect(await mock.lastStationTimetableLineMunicipality?.timetableIndex == 2)
    #expect(await mock.lastStationTimetableLineMunicipality?.timetableName == "DvurKral")
}

@Test func stationTimetableSuggestionToolsUseIDOLDefaultMunicipality() async {
    let mock = MockIDOSClient()
    let tools = KastanMCPTools(dataSource: mock)
    let lines = await tools.call(
        name: "search_station_timetable_lines",
        arguments: ["prefix": "202", "timetable": "idol"]
    )

    #expect(
        lines.structuredContent?.objectValue?["municipality"]?.objectValue?["name"]
            == "Česká Lípa"
    )
    #expect(await mock.lastStationTimetableLineQuery == QueryCall(
        prefix: "202",
        limit: 8,
        timetableSlug: "idol"
    ))
    #expect(await mock.lastStationTimetableLineMunicipality?.timetableIndex == 2)
    #expect(await mock.lastStationTimetableLineMunicipality?.timetableName == "CeskaLipa")
}

@Test func departureToolLimitsReturnedRowsWithoutChangingIDOSRequest() async {
    let mock = MockIDOSClient()
    let tools = KastanMCPTools(dataSource: mock)
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
    let serviceInformation = result.structuredContent?
        .objectValue?["departures"]?.arrayValue?.first?
        .objectValue?["serviceInformation"]?.arrayValue?.first?.objectValue
    #expect(serviceInformation?["category"]?.stringValue == "wheelchair")
    let request = await mock.lastDeparturesRequest
    #expect(request?.station == "Ostrava-Svinov")
    #expect(request?.time == "16:00")
    #expect(request?.isArrival == true)
}

@Test func stationTimetableToolPassesCompleteRequestAndLanguageToKastan() async {
    let mock = MockIDOSClient()
    let tools = KastanMCPTools(dataSource: mock)
    let result = await tools.call(
        name: "find_station_timetable",
        arguments: [
            "line": " Bus 154 ",
            "from": " Strašnická ",
            "to": "Sídliště Libuš",
            "timetable": "odis",
            "municipality": "Frýdek-Místek",
            "date": "17.7.2026",
            "wholeWeek": true,
            "language": "cs",
        ]
    )

    #expect(result.isError == false)
    let timetable = result.structuredContent?.objectValue?["stationTimetable"]?.objectValue
    #expect(timetable?["lineName"] == "Bus 154")
    #expect(timetable?["stops"]?.arrayValue?.count == 2)
    #expect(timetable?["stops"]?.arrayValue?.first?.objectValue?["platform"] == "1")
    #expect(timetable?["schedules"]?.arrayValue?.first?.objectValue?["hours"]?.arrayValue?.count == 1)
    #expect(timetable?["explanations"]?.arrayValue?.first == "A: runs only to stop Háje")
    #expect(timetable?["notes"]?.arrayValue?.first == "valid from 1.7.2026")
    #expect(timetable?["municipality"]?.objectValue?["timetableName"] == "FM")
    let request = await mock.lastStationTimetableRequest
    #expect(request?.line == "Bus 154")
    #expect(request?.from == "Strašnická")
    #expect(request?.to == "Sídliště Libuš")
    #expect(request?.timetable.slug == "odis")
    #expect(request?.municipality?.name == "Frýdek-Místek")
    #expect(request?.date == "17.7.2026")
    #expect(request?.wholeWeek == true)
    #expect(await mock.lastStationTimetableLanguage == .czech)
}

@Test func serviceDetailToolLoadsCompleteRouteByOpaqueID() async throws {
    let mock = MockIDOSClient()
    let tools = KastanMCPTools(dataSource: mock)
    let result = await tools.call(
        name: "get_service_detail",
        arguments: [
            "id": "vlaky:0-74552-18.06.2026 12:04:00",
        ]
    )

    #expect(result.isError == false)
    let service = try #require(result.structuredContent?.objectValue?["service"]?.objectValue)
    #expect(service["stops"]?.arrayValue?.count == 2)
    #expect(service["timetable"]?.objectValue?["slug"]?.stringValue == "vlaky")
    #expect(service["information"]?.arrayValue?.first == "Operating dates")
    #expect(service["serviceInformation"] == nil)
    let schema = try #require(
        KastanMCPTools.definitions.first { $0.name == "get_service_detail" }?.outputSchema
    )
    #expect(schemaValidationErrors(for: try #require(result.structuredContent), schema: schema).isEmpty)
    #expect(text(from: result.content)?.contains("\"name\" : \"RJ 1051 RegioJet\"") == true)
    #expect(await mock.lastServiceID == "vlaky:0-74552-18.06.2026 12:04:00")
    #expect(await mock.lastServiceTimetable == IDOSTimetable.defaultTimetable.slug)
    #expect(await mock.lastServiceLanguage == .english)
}

@Test func serviceDetailToolPassesSelectedLanguageAndLegacyTimetable() async {
    let mock = MockIDOSClient()
    let tools = KastanMCPTools(dataSource: mock)
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
    let tools = KastanMCPTools(dataSource: mock)

    let missing = await tools.call(name: "find_connections", arguments: ["from": "Praha"])
    let wrongType = await tools.call(name: "find_departures", arguments: ["station": "Praha", "limit": "many"])
    let invalidLanguage = await tools.call(
        name: "get_service_detail",
        arguments: ["id": "vlaky:service", "language": "de"]
    )
    let unknown = await tools.call(name: "list_timetables", arguments: ["extra": true])
    let invalidMunicipality = await tools.call(
        name: "find_station_timetable",
        arguments: [
            "line": "Bus 154", "from": "Strašnická", "to": "Sídliště Libuš",
            "timetable": "pid", "municipality": "Ostrava",
        ]
    )
    let invalidBoolean = await tools.call(
        name: "find_connections",
        arguments: ["from": "Praha", "to": "Brno", "preferBusyRoutes": "yes"]
    )
    let invalidMinimumTransferTime = await tools.call(
        name: "find_connections",
        arguments: ["from": "Praha", "to": "Brno", "minimumTransferTime": -2]
    )
    let invalidBedOrCouchette = await tools.call(
        name: "find_connections",
        arguments: ["from": "Praha", "to": "Brno", "bedOrCouchettePreference": "sometimes"]
    )
    let invalidTransportMode = await tools.call(
        name: "find_connections",
        arguments: [
            "from": "Praha", "to": "Brno",
            "transportModeFilters": .array([
                .object(["operation": "only", "mode": "hovercraft"]),
            ]),
        ]
    )
    let incompleteTransportModeFilter = await tools.call(
        name: "find_connections",
        arguments: [
            "from": "Praha", "to": "Brno",
            "transportModeFilters": .array([
                .object(["operation": "exclude"]),
            ]),
        ]
    )

    #expect(missing.isError == true)
    #expect(text(from: missing.content) == "Error: Missing required argument 'to'.")
    #expect(wrongType.isError == true)
    #expect(text(from: wrongType.content) == "Error: Argument 'limit' must be an integer.")
    #expect(invalidLanguage.isError == true)
    #expect(text(from: invalidLanguage.content) == "Error: Invalid value 'de' for argument 'language'. Use en or cs.")
    #expect(unknown.isError == true)
    #expect(text(from: unknown.content) == "Error: Unknown argument: extra.")
    #expect(invalidMunicipality.isError == true)
    #expect(
        text(from: invalidMunicipality.content) ==
            "Error: Timetable Prague + PID does not offer a municipality choice."
    )
    #expect(invalidBoolean.isError == true)
    #expect(
        text(from: invalidBoolean.content)
            == "Error: Argument 'preferBusyRoutes' must be a boolean."
    )
    #expect(invalidMinimumTransferTime.isError == true)
    #expect(
        text(from: invalidMinimumTransferTime.content)
            == "Error: Argument 'minimumTransferTime' must be at least -1."
    )
    #expect(invalidBedOrCouchette.isError == true)
    #expect(
        text(from: invalidBedOrCouchette.content)
            == "Error: Invalid value 'sometimes' for argument 'bedOrCouchettePreference'. Use noLimitation or use or doNotUse."
    )
    #expect(invalidTransportMode.isError == true)
    #expect(
        text(from: invalidTransportMode.content)?.contains(
            "Invalid value 'hovercraft' for argument 'transportModeFilters[0].mode'."
        ) == true
    )
    #expect(incompleteTransportModeFilter.isError == true)
    #expect(
        text(from: incompleteTransportModeFilter.content)
            == "Error: Missing required argument 'transportModeFilters[0].mode'."
    )
    #expect(await mock.lastConnectionRequest == nil)
    #expect(await mock.lastDeparturesRequest == nil)
}

private func text(from content: [Tool.Content]) -> String? {
    guard case .text(let text, _, _)? = content.first else {
        return nil
    }
    return text
}

/// Detects implementation-only identity keys at any depth of a public MCP result.
private func containsInternalRoutingMetadata(_ value: Value) -> Bool {
    switch value {
    case .array(let values):
        return values.contains(where: containsInternalRoutingMetadata)
    case .object(let object):
        let internalKeys: Set<String> = ["dataSourceID", "timetableIdentifier", "identifier"]
        return !internalKeys.isDisjoint(with: object.keys) ||
            object.values.contains(where: containsInternalRoutingMetadata)
    default:
        return false
    }
}

/// Validates the JSON Schema subset used by every MCP output, including closed nested objects.
private func schemaValidationErrors(
    for value: Value,
    schema: Value,
    path: String = "$"
) -> [String] {
    guard let definition = schema.objectValue else {
        return ["\(path): schema is not an object"]
    }

    var errors: [String] = []
    if let allowedValues = definition["enum"]?.arrayValue, !allowedValues.contains(value) {
        errors.append("\(path): value is outside the advertised enum")
    }

    switch definition["type"]?.stringValue {
    case "object":
        guard let object = value.objectValue else {
            return errors + ["\(path): expected an object"]
        }
        let properties = definition["properties"]?.objectValue ?? [:]
        let required = Set(definition["required"]?.arrayValue?.compactMap(\.stringValue) ?? [])
        for key in required.subtracting(object.keys).sorted() {
            errors.append("\(path): missing required property \(key)")
        }
        if definition["additionalProperties"]?.boolValue == false {
            for key in Set(object.keys).subtracting(properties.keys).sorted() {
                errors.append("\(path): unexpected property \(key)")
            }
        }
        for key in object.keys.sorted() {
            guard let propertySchema = properties[key], let property = object[key] else { continue }
            errors += schemaValidationErrors(
                for: property,
                schema: propertySchema,
                path: "\(path).\(key)"
            )
        }
    case "array":
        guard let values = value.arrayValue else {
            return errors + ["\(path): expected an array"]
        }
        guard let itemSchema = definition["items"] else {
            return errors + ["\(path): array schema has no item definition"]
        }
        for (index, item) in values.enumerated() {
            errors += schemaValidationErrors(
                for: item,
                schema: itemSchema,
                path: "\(path)[\(index)]"
            )
        }
    case "string":
        if value.stringValue == nil {
            errors.append("\(path): expected a string")
        }
    case "integer":
        if value.intValue == nil {
            errors.append("\(path): expected an integer")
        }
    case "number":
        if value.intValue == nil && value.doubleValue == nil {
            errors.append("\(path): expected a number")
        }
    case "boolean":
        if value.boolValue == nil {
            errors.append("\(path): expected a boolean")
        }
    case .none:
        errors.append("\(path): schema has no type")
    case .some(let type):
        errors.append("\(path): unsupported schema type \(type)")
    }

    return errors
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
    nonisolated let descriptor = TransitDataSourceDescriptor.idos
    var lastSuggestionQuery: QueryCall?
    var lastStationQuery: QueryCall?
    var lastStationTimetableLineQuery: QueryCall?
    var lastStationTimetableStopQuery: StationTimetableStopQuery?
    var lastStationTimetableLineMunicipality: IDOSStationTimetableMunicipality?
    var lastStationTimetableStopMunicipality: IDOSStationTimetableMunicipality?
    var lastConnectionRequest: IDOSConnectionRequest?
    var lastDeparturesRequest: IDOSDeparturesRequest?
    var lastStationTimetableRequest: IDOSStationTimetableRequest?
    var lastStationTimetableLanguage: IDOSLanguage?
    var lastServiceID: String?
    var lastServiceTimetable: String?
    var lastServiceLanguage: IDOSLanguage?

    func suggest(prefix: String, limit: Int, timetable: IDOSTimetable) async throws -> [IDOSSuggestion] {
        lastSuggestionQuery = QueryCall(prefix: prefix, limit: limit, timetableSlug: timetable.slug)
        return [IDOSSuggestion(timetableIdentifier: timetable.identifier, text: "Ostrava-Svinov")]
    }

    func searchStations(prefix: String, limit: Int, timetable: IDOSTimetable) async throws -> [IDOSSuggestion] {
        lastStationQuery = QueryCall(prefix: prefix, limit: limit, timetableSlug: timetable.slug)
        return [IDOSSuggestion(timetableIdentifier: timetable.identifier, text: "Praha hl.n.")]
    }

    func searchStationTimetableLines(
        prefix: String,
        limit: Int,
        timetable: IDOSTimetable
    ) async throws -> [IDOSSuggestion] {
        lastStationTimetableLineQuery = QueryCall(prefix: prefix, limit: limit, timetableSlug: timetable.slug)
        return [IDOSSuggestion(
            timetableIdentifier: timetable.identifier,
            text: "Bus 154",
            description: "Strašnická-Sídliště Libuš",
            from: "Strašnická",
            to: "Sídliště Libuš"
        )]
    }

    func searchStationTimetableLines(
        prefix: String,
        limit: Int,
        timetable: IDOSTimetable,
        municipality: IDOSStationTimetableMunicipality?
    ) async throws -> [IDOSSuggestion] {
        lastStationTimetableLineMunicipality = municipality
        return try await searchStationTimetableLines(
            prefix: prefix,
            limit: limit,
            timetable: timetable
        )
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
        return [IDOSSuggestion(
            timetableIdentifier: timetable.identifier,
            text: "Strašnická",
            description: "Station"
        )]
    }

    func searchStationTimetableStops(
        prefix: String,
        line: String,
        limit: Int,
        timetable: IDOSTimetable,
        municipality: IDOSStationTimetableMunicipality?
    ) async throws -> [IDOSSuggestion] {
        lastStationTimetableStopMunicipality = municipality
        return try await searchStationTimetableStops(
            prefix: prefix,
            line: line,
            limit: limit,
            timetable: timetable
        )
    }

    func findConnections(request: IDOSConnectionRequest) async throws -> [IDOSConnection] {
        lastConnectionRequest = request
        return [
            IDOSConnection(
                timetableIdentifier: request.timetable.identifier,
                id: "connection-1",
                departureTime: "12:00",
                departureStation: "Praha hl.n.",
                arrivalTime: "14:35",
                arrivalStation: "Brno hl.n.",
                duration: "2 hod 35 min",
                legs: [
                    IDOSConnectionLeg(
                        name: "R 879",
                        departureTime: "12:00",
                        fromStation: "Praha hl.n.",
                        arrivalTime: "14:35",
                        toStation: "Brno hl.n.",
                        serviceInformation: [
                            IDOSServiceInformation(text: "Wireless internet connection"),
                        ]
                    ),
                ]
            ),
        ]
    }

    func connectionCalendar(for connection: IDOSConnection, timetable: IDOSTimetable) async throws -> String {
        "BEGIN:VCALENDAR\nEND:VCALENDAR"
    }

    func findDepartures(request: IDOSDeparturesRequest) async throws -> [IDOSDeparture] {
        lastDeparturesRequest = request
        return [
            IDOSDeparture(
                timetableIdentifier: request.timetable.identifier,
                id: "departure-1",
                time: "16:01",
                lineName: "S2",
                destination: "Opava",
                serviceInformation: [
                    IDOSServiceInformation(text: "Wheelchair accessible carriage"),
                ]
            ),
            IDOSDeparture(
                timetableIdentifier: request.timetable.identifier,
                id: "departure-2",
                time: "16:05",
                lineName: "S4",
                destination: "Bohumín"
            ),
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
            municipality: request.municipality,
            lineName: request.line,
            transportMode: .bus,
            fromStop: request.from,
            toStop: request.to,
            stops: [
                IDOSStationTimetableStop(name: request.from, minuteOffset: 0, platform: "1", isSelected: true),
                IDOSStationTimetableStop(name: request.to, minuteOffset: 42, platform: "2"),
            ],
            schedules: [
                IDOSStationTimetableSchedule(
                    label: "17.7.2026 Friday",
                    hours: [IDOSStationTimetableHour(hour: "5", departures: ["13", "35A"])]
                ),
            ],
            explanations: ["A: runs only to stop Háje"],
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
            ],
            serviceInformation: [
                IDOSServiceInformation(text: "Operating dates", category: .wheelchair),
            ]
        )
    }
}
