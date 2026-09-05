import Foundation
import Kastan
import MCP

/// Validates MCP inputs before sending a query to IDOS.
struct ToolArguments {
    let values: [String: Value]

    init(_ values: [String: Value], allowed: Set<String>) throws {
        let unknown = Set(values.keys).subtracting(allowed).sorted()
        guard unknown.isEmpty else {
            throw MCPToolError.unknownArguments(unknown)
        }
        self.values = values
    }

    func requiredString(_ name: String) throws -> String {
        guard let value = values[name] else {
            throw MCPToolError.missingArgument(name)
        }
        guard let string = value.stringValue else {
            throw MCPToolError.invalidType(name: name, expected: "a string")
        }
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw MCPToolError.emptyString(name)
        }
        return trimmed
    }

    func optionalString(_ name: String) throws -> String? {
        guard let value = values[name], !value.isNull else {
            return nil
        }
        guard let string = value.stringValue else {
            throw MCPToolError.invalidType(name: name, expected: "a string")
        }
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw MCPToolError.emptyString(name)
        }
        return trimmed
    }

    func boolean(_ name: String, default defaultValue: Bool) throws -> Bool {
        guard let value = values[name] else {
            return defaultValue
        }
        guard let boolean = value.boolValue else {
            throw MCPToolError.invalidType(name: name, expected: "a boolean")
        }
        return boolean
    }

    func optionalBoolean(_ name: String) throws -> Bool? {
        guard let value = values[name], !value.isNull else {
            return nil
        }
        guard let boolean = value.boolValue else {
            throw MCPToolError.invalidType(name: name, expected: "a boolean")
        }
        return boolean
    }

    func integer(_ name: String, default defaultValue: Int, range: ClosedRange<Int>) throws -> Int {
        guard let value = values[name] else {
            return defaultValue
        }
        guard let integer = value.intValue else {
            throw MCPToolError.invalidType(name: name, expected: "an integer")
        }
        guard range.contains(integer) else {
            throw MCPToolError.outOfRange(name: name, range: range)
        }
        return integer
    }

    func optionalInteger(_ name: String, minimum: Int) throws -> Int? {
        guard let value = values[name], !value.isNull else {
            return nil
        }
        guard let integer = value.intValue else {
            throw MCPToolError.invalidType(name: name, expected: "an integer")
        }
        guard integer >= minimum else {
            throw MCPToolError.minimum(name: name, value: minimum)
        }
        return integer
    }

    func stringArray(_ name: String, default defaultValue: [String]) throws -> [String] {
        guard let value = values[name] else {
            return defaultValue
        }
        guard let array = value.arrayValue else {
            throw MCPToolError.invalidType(name: name, expected: "an array of strings")
        }
        return try array.enumerated().map { index, value in
            guard let string = value.stringValue else {
                throw MCPToolError.invalidType(name: "\(name)[\(index)]", expected: "a string")
            }
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                throw MCPToolError.emptyString("\(name)[\(index)]")
            }
            return trimmed
        }
    }

    /// Resolves the public language codes accepted by IDOS-backed product text.
    func idosLanguage(_ name: String, default defaultValue: TransitLanguage) throws -> TransitLanguage {
        guard let value = try optionalString(name) else {
            return defaultValue
        }
        guard let language = TransitLanguage(rawValue: value) else {
            throw MCPToolError.invalidValue(name: name, value: value, allowed: ["en", "cs"])
        }
        return language
    }

    /// Resolves the stable provider-neutral values published in the connection tool schema.
    func bedOrCouchettePreference(_ name: String) throws -> TransitBedOrCouchettePreference? {
        guard let value = try optionalString(name) else {
            return nil
        }
        guard let preference = TransitBedOrCouchettePreference(rawValue: value) else {
            throw MCPToolError.invalidValue(
                name: name,
                value: value,
                allowed: TransitBedOrCouchettePreference.allCases.map(\.rawValue)
            )
        }
        return preference
    }
}

/// Presents actionable product errors to MCP clients instead of protocol-level failures.
enum MCPToolError: LocalizedError {
    case unknownTool(String)
    case unknownArguments([String])
    case missingArgument(String)
    case emptyString(String)
    case invalidType(name: String, expected: String)
    case invalidValue(name: String, value: String, allowed: [String])
    case unsupportedConnectionOption(
        name: String,
        timetableName: String,
        timetableIdentifier: String
    )
    case outOfRange(name: String, range: ClosedRange<Int>)
    case minimum(name: String, value: Int)
    case cannotEncodeResult

    var errorDescription: String? {
        switch self {
        case .unknownTool(let name):
            "Unknown tool '\(name)'."
        case .unknownArguments(let names):
            "Unknown argument\(names.count == 1 ? "" : "s"): \(names.joined(separator: ", "))."
        case .missingArgument(let name):
            "Missing required argument '\(name)'."
        case .emptyString(let name):
            "Argument '\(name)' must not be empty."
        case .invalidType(let name, let expected):
            "Argument '\(name)' must be \(expected)."
        case .invalidValue(let name, let value, let allowed):
            "Invalid value '\(value)' for argument '\(name)'. Use \(allowed.joined(separator: " or "))."
        case .unsupportedConnectionOption(let name, let timetableName, let timetableIdentifier):
            "Argument '\(name)' is not supported for timetable \(timetableName) (\(timetableIdentifier))."
        case .outOfRange(let name, let range):
            "Argument '\(name)' must be between \(range.lowerBound) and \(range.upperBound)."
        case .minimum(let name, let value):
            "Argument '\(name)' must be at least \(value)."
        case .cannotEncodeResult:
            "The result could not be encoded as JSON."
        }
    }
}

/// Type-erases an Encodable value while preserving its original JSON representation.
struct AnyEncodable: Encodable {
    let encodeValue: (Encoder) throws -> Void

    init(_ value: any Encodable) {
        encodeValue = value.encode
    }

    func encode(to encoder: Encoder) throws {
        try encodeValue(encoder)
    }
}

/// Keeps provider-owned suggestion metadata internal while preserving the original IDOS MCP schema.
private struct MCPSuggestion: Encodable {
    let selectedText: String?
    let text: String
    let description: String?
    let region: String?
    let value: String?
    let value2: String?
    let iconId: Int?
    let coorX: Double?
    let coorY: Double?
    let from: String?
    let to: String?

    init(_ suggestion: TransitSuggestion) {
        selectedText = suggestion.selectedText
        text = suggestion.text
        description = suggestion.description
        region = suggestion.region
        value = suggestion.value
        value2 = suggestion.value2
        iconId = suggestion.iconId
        coorX = suggestion.coorX
        coorY = suggestion.coorY
        from = suggestion.from
        to = suggestion.to
    }
}

/// Keeps provider and timetable routing metadata out of the stable IDOS connection result contract.
private struct MCPConnection: Encodable {
    let id: String
    let departureTime: String
    let departureStation: String
    let arrivalTime: String
    let arrivalStation: String
    let duration: String
    let legs: [TransitConnectionLeg]
    let shareURL: String?

    init(_ connection: TransitConnection) {
        id = connection.id
        departureTime = connection.departureTime
        departureStation = connection.departureStation
        arrivalTime = connection.arrivalTime
        arrivalStation = connection.arrivalStation
        duration = connection.duration
        legs = connection.legs
        shareURL = connection.shareURL
    }
}

/// Keeps provider and timetable routing metadata out of the stable IDOS station-board contract.
private struct MCPDeparture: Encodable {
    let id: String
    let stationName: String?
    let time: String
    let lineName: String
    let lineColor: String?
    let transportMode: TransitTransportMode?
    let destination: String
    let tariffZone: String?
    let platform: String?
    let via: String?
    let carrier: String?
    let delay: String?
    let serviceInformation: [TransitServiceInformation]

    init(_ departure: TransitDeparture) {
        id = departure.id
        stationName = departure.stationName
        time = departure.time
        lineName = departure.lineName
        lineColor = departure.lineColor
        transportMode = departure.transportMode
        destination = departure.destination
        tariffZone = departure.tariffZone
        platform = departure.platform
        via = departure.via
        carrier = departure.carrier
        delay = departure.delay
        serviceInformation = departure.serviceInformation
    }
}

/// Keeps canonical provider categories internal while preserving the original IDOS service-detail schema.
private struct MCPServiceDetail: Encodable {
    let id: String
    let timetable: TransitTimetable
    let name: String
    let color: String?
    let transportMode: TransitTransportMode?
    let date: String?
    let stops: [TransitServiceStop]
    let information: [String]
    let shareURL: String?

    init(_ service: TransitServiceDetail) {
        id = service.id
        timetable = service.timetable
        name = service.name
        color = service.color
        transportMode = service.transportMode
        date = service.date
        stops = service.stops
        information = service.information
        shareURL = service.shareURL
    }
}

/// Structured outputs keep MCP results self-describing without coupling their schema to library persistence.
struct SuggestedPlacesOutput: Encodable {
    let query: String
    let timetable: TransitTimetable
    private let suggestions: [MCPSuggestion]

    init(query: String, timetable: TransitTimetable, suggestions: [TransitSuggestion]) {
        self.query = query
        self.timetable = timetable
        self.suggestions = suggestions.map(MCPSuggestion.init)
    }
}

struct StationsOutput: Encodable {
    let query: String
    let timetable: TransitTimetable
    private let stations: [MCPSuggestion]

    init(query: String, timetable: TransitTimetable, stations: [TransitSuggestion]) {
        self.query = query
        self.timetable = timetable
        self.stations = stations.map(MCPSuggestion.init)
    }
}

/// Returns Station Timetable line directions together with their search catalog and query.
struct StationTimetableLinesOutput: Encodable {
    let query: String
    let timetable: TransitTimetable
    let municipality: TransitStationTimetableMunicipality?
    private let lines: [MCPSuggestion]

    init(
        query: String,
        timetable: TransitTimetable,
        municipality: TransitStationTimetableMunicipality?,
        lines: [TransitSuggestion]
    ) {
        self.query = query
        self.timetable = timetable
        self.municipality = municipality
        self.lines = lines.map(MCPSuggestion.init)
    }
}

/// Returns the stops available to one Station Timetable line search.
struct StationTimetableStopsOutput: Encodable {
    let query: String
    let line: String
    let timetable: TransitTimetable
    let municipality: TransitStationTimetableMunicipality?
    private let stops: [MCPSuggestion]

    init(
        query: String,
        line: String,
        timetable: TransitTimetable,
        municipality: TransitStationTimetableMunicipality?,
        stops: [TransitSuggestion]
    ) {
        self.query = query
        self.line = line
        self.timetable = timetable
        self.municipality = municipality
        self.stops = stops.map(MCPSuggestion.init)
    }
}

struct ConnectionsOutput: Encodable {
    let request: TransitConnectionRequest
    private let connections: [MCPConnection]

    init(request: TransitConnectionRequest, connections: [TransitConnection]) {
        self.request = request
        self.connections = connections.map(MCPConnection.init)
    }
}

struct DeparturesOutput: Encodable {
    let request: TransitDeparturesRequest
    private let departures: [MCPDeparture]

    init(request: TransitDeparturesRequest, departures: [TransitDeparture]) {
        self.request = request
        self.departures = departures.map(MCPDeparture.init)
    }
}

/// Keeps the validated Station Timetable request beside the IDOS result for MCP clients.
struct StationTimetableOutput: Encodable {
    let request: TransitStationTimetableRequest
    let stationTimetable: TransitStationTimetable
}

struct ServiceDetailOutput: Encodable {
    private let service: MCPServiceDetail

    init(service: TransitServiceDetail) {
        self.service = MCPServiceDetail(service)
    }
}

struct TimetablesOutput: Encodable {
    let timetables: [TransitTimetable]
}

/// Describes every structured tool result with the same field names and optionality as the public Kaštan models.
enum MCPOutputSchemas {
    static let suggestedPlaces = objectSchema(
        properties: [
            "query": stringSchema,
            "timetable": timetableSchema,
            "suggestions": arraySchema(items: suggestionSchema),
        ],
        required: ["query", "timetable", "suggestions"]
    )

    static let stations = objectSchema(
        properties: [
            "query": stringSchema,
            "timetable": timetableSchema,
            "stations": arraySchema(items: suggestionSchema),
        ],
        required: ["query", "timetable", "stations"]
    )

    static let stationTimetableLines = objectSchema(
        properties: [
            "query": stringSchema,
            "timetable": timetableSchema,
            "municipality": stationTimetableMunicipalitySchema,
            "lines": arraySchema(items: suggestionSchema),
        ],
        required: ["query", "timetable", "lines"]
    )

    static let stationTimetableStops = objectSchema(
        properties: [
            "query": stringSchema,
            "line": stringSchema,
            "timetable": timetableSchema,
            "municipality": stationTimetableMunicipalitySchema,
            "stops": arraySchema(items: suggestionSchema),
        ],
        required: ["query", "line", "timetable", "stops"]
    )

    static let connections = objectSchema(
        properties: [
            "request": connectionRequestSchema,
            "connections": arraySchema(items: connectionSchema),
        ],
        required: ["request", "connections"]
    )

    static let departures = objectSchema(
        properties: [
            "request": departuresRequestSchema,
            "departures": arraySchema(items: departureSchema),
        ],
        required: ["request", "departures"]
    )

    static let stationTimetable = objectSchema(
        properties: [
            "request": stationTimetableRequestSchema,
            "stationTimetable": stationTimetableSchema,
        ],
        required: ["request", "stationTimetable"]
    )

    static let serviceDetail = objectSchema(
        properties: ["service": serviceDetailSchema],
        required: ["service"]
    )

    static let timetables = objectSchema(
        properties: ["timetables": arraySchema(items: timetableSchema)],
        required: ["timetables"]
    )

    private static let timetableSchema = objectSchema(
        properties: [
            "slug": stringSchema,
            "displayName": stringSchema,
        ],
        required: ["slug", "displayName"]
    )

    private static let stationTimetableMunicipalitySchema = objectSchema(
        properties: [
            "name": stringSchema,
            "timetableIndex": integerSchema,
            "timetableName": stringSchema,
        ],
        required: ["name", "timetableIndex", "timetableName"]
    )

    private static let suggestionSchema = objectSchema(
        properties: [
            "selectedText": stringSchema,
            "text": stringSchema,
            "description": stringSchema,
            "region": stringSchema,
            "value": stringSchema,
            "value2": stringSchema,
            "iconId": integerSchema,
            "coorX": numberSchema,
            "coorY": numberSchema,
            "from": stringSchema,
            "to": stringSchema,
        ],
        required: ["text"]
    )

    private static let connectionRequestSchema = objectSchema(
        properties: [
            "timetable": timetableSchema,
            "from": stringSchema,
            "to": stringSchema,
            "date": stringSchema,
            "time": stringSchema,
            "isArrival": booleanSchema,
            "onlyDirect": booleanSchema,
            "via": stringArraySchema,
            "maxTransfers": integerSchema,
            "minimumTransferTime": integerSchema,
            "maximumTransferTime": integerSchema,
            "maximumWalkingTime": integerSchema,
            "maximumCityWalkingTime": integerSchema,
            "walkToNearbyStops": booleanSchema,
            "sameNameWalkingTransfersOnly": booleanSchema,
            "wheelchairAccessibleConnectionsOnly": booleanSchema,
            "lowFloorConnectionsOnly": booleanSchema,
            "preferTrainsOverBuses": booleanSchema,
            "trainConnectionsForWheelchairPassengers": booleanSchema,
            "trainConnectionsForPassengersWithChildren": booleanSchema,
            "connectionsForPassengersWithBicycles": booleanSchema,
            "preferBusyRoutes": booleanSchema,
            "bedOrCouchettePreference": bedOrCouchettePreferenceSchema,
            "resultLimit": integerSchema,
        ],
        required: ["timetable", "from", "to", "isArrival", "onlyDirect", "via", "resultLimit"]
    )

    private static let connectionSchema = objectSchema(
        properties: [
            "id": stringSchema,
            "departureTime": stringSchema,
            "departureStation": stringSchema,
            "arrivalTime": stringSchema,
            "arrivalStation": stringSchema,
            "duration": stringSchema,
            "legs": arraySchema(items: connectionLegSchema),
            "shareURL": stringSchema,
        ],
        required: [
            "id", "departureTime", "departureStation", "arrivalTime", "arrivalStation", "duration", "legs",
        ]
    )

    private static let connectionLegSchema = objectSchema(
        properties: [
            "name": stringSchema,
            "id": stringSchema,
            "color": stringSchema,
            "transportMode": transportModeSchema,
            "departureTime": stringSchema,
            "fromStation": stringSchema,
            "fromTariffZone": stringSchema,
            "fromPlatform": stringSchema,
            "arrivalTime": stringSchema,
            "toStation": stringSchema,
            "toTariffZone": stringSchema,
            "toPlatform": stringSchema,
            "carrier": stringSchema,
            "delay": stringSchema,
            "serviceInformation": arraySchema(items: serviceInformationSchema),
        ],
        required: ["name", "departureTime", "fromStation", "arrivalTime", "toStation"]
    )

    private static let departuresRequestSchema = objectSchema(
        properties: [
            "timetable": timetableSchema,
            "station": stringSchema,
            "date": stringSchema,
            "time": stringSchema,
            "isArrival": booleanSchema,
        ],
        required: ["timetable", "station", "isArrival"]
    )

    private static let departureSchema = objectSchema(
        properties: [
            "id": stringSchema,
            "stationName": stringSchema,
            "time": stringSchema,
            "lineName": stringSchema,
            "lineColor": stringSchema,
            "transportMode": transportModeSchema,
            "destination": stringSchema,
            "tariffZone": stringSchema,
            "platform": stringSchema,
            "via": stringSchema,
            "carrier": stringSchema,
            "delay": stringSchema,
            "serviceInformation": arraySchema(items: serviceInformationSchema),
        ],
        required: ["id", "time", "lineName", "destination"]
    )

    private static let serviceInformationSchema = objectSchema(
        properties: [
            "text": stringSchema,
            "category": stringSchema,
        ],
        required: ["text", "category"]
    )

    private static let stationTimetableRequestSchema = objectSchema(
        properties: [
            "timetable": timetableSchema,
            "municipality": stationTimetableMunicipalitySchema,
            "line": stringSchema,
            "from": stringSchema,
            "to": stringSchema,
            "date": stringSchema,
            "wholeWeek": booleanSchema,
        ],
        required: ["timetable", "line", "from", "to", "wholeWeek"]
    )

    private static let stationTimetableSchema = objectSchema(
        properties: [
            "timetable": timetableSchema,
            "municipality": stationTimetableMunicipalitySchema,
            "lineName": stringSchema,
            "transportMode": transportModeSchema,
            "fromStop": stringSchema,
            "toStop": stringSchema,
            "stops": arraySchema(items: stationTimetableStopSchema),
            "schedules": arraySchema(items: stationTimetableScheduleSchema),
            "explanations": stringArraySchema,
            "notes": stringArraySchema,
            "isLockout": booleanSchema,
            "shareURL": stringSchema,
        ],
        required: [
            "timetable", "lineName", "fromStop", "toStop", "stops", "schedules",
            "explanations", "notes", "isLockout",
        ]
    )

    private static let stationTimetableStopSchema = objectSchema(
        properties: [
            "name": stringSchema,
            "minuteOffset": integerSchema,
            "tariffZone": stringSchema,
            "platform": stringSchema,
            "isSelected": booleanSchema,
            "notes": stringArraySchema,
        ],
        required: ["name", "isSelected", "notes"]
    )

    private static let stationTimetableScheduleSchema = objectSchema(
        properties: [
            "label": stringSchema,
            "hours": arraySchema(items: stationTimetableHourSchema),
        ],
        required: ["label", "hours"]
    )

    private static let stationTimetableHourSchema = objectSchema(
        properties: [
            "hour": stringSchema,
            "departures": stringArraySchema,
        ],
        required: ["hour", "departures"]
    )

    private static let serviceDetailSchema = objectSchema(
        properties: [
            "id": stringSchema,
            "timetable": timetableSchema,
            "name": stringSchema,
            "color": stringSchema,
            "transportMode": transportModeSchema,
            "date": stringSchema,
            "stops": arraySchema(items: serviceStopSchema),
            "information": stringArraySchema,
            "shareURL": stringSchema,
        ],
        required: ["id", "timetable", "name", "stops", "information"]
    )

    private static let serviceStopSchema = objectSchema(
        properties: [
            "name": stringSchema,
            "arrivalTime": stringSchema,
            "departureTime": stringSchema,
            "tariffZone": stringSchema,
            "platform": stringSchema,
            "track": stringSchema,
            "platformTrack": stringSchema,
            "distance": stringSchema,
            "notes": stringArraySchema,
        ],
        required: ["name", "notes"]
    )

    private static let transportModeSchema: Value = .object([
        "type": "string",
        "enum": ["train", "bus", "tram", "metro", "trolleybus", "ferry", "cableCar", "plane", "walk"],
    ])

    private static let bedOrCouchettePreferenceSchema: Value = .object([
        "type": "string",
        "enum": .array(TransitBedOrCouchettePreference.allCases.map { .string($0.rawValue) }),
    ])

    private static let stringSchema: Value = .object(["type": "string"])
    private static let integerSchema: Value = .object(["type": "integer"])
    private static let numberSchema: Value = .object(["type": "number"])
    private static let booleanSchema: Value = .object(["type": "boolean"])
    private static let stringArraySchema = arraySchema(items: stringSchema)

    private static func arraySchema(items: Value) -> Value {
        .object([
            "type": "array",
            "items": items,
        ])
    }

    private static func objectSchema(properties: [String: Value], required: [String]) -> Value {
        .object([
            "type": "object",
            "properties": .object(properties),
            "required": .array(required.map(Value.string)),
            "additionalProperties": false,
        ])
    }
}
