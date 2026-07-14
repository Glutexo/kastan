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
}

/// Presents actionable product errors to MCP clients instead of protocol-level failures.
enum MCPToolError: LocalizedError {
    case unknownTool(String)
    case unknownArguments([String])
    case missingArgument(String)
    case emptyString(String)
    case invalidType(name: String, expected: String)
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

/// Structured outputs keep MCP results self-describing while matching the Kaštan library model.
struct SuggestedPlacesOutput: Encodable {
    let query: String
    let timetable: IDOSTimetable
    let suggestions: [IDOSSuggestion]
}

struct StationsOutput: Encodable {
    let query: String
    let timetable: IDOSTimetable
    let stations: [IDOSSuggestion]
}

struct ConnectionsOutput: Encodable {
    let request: IDOSConnectionRequest
    let connections: [IDOSConnection]
}

struct DeparturesOutput: Encodable {
    let request: IDOSDeparturesRequest
    let departures: [IDOSDeparture]
}

struct ServiceDetailOutput: Encodable {
    let timetable: IDOSTimetable
    let service: IDOSServiceDetail
}

struct TimetablesOutput: Encodable {
    let timetables: [IDOSTimetable]
}
