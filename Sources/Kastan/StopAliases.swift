import Foundation

public struct StopAlias: Codable, Equatable, Sendable {
    public var name: String
    public var station: String
    public var timetable: IDOSTimetable

    public init(name: String, station: String, timetable: IDOSTimetable) {
        self.name = name
        self.station = station
        self.timetable = timetable
    }
}

public struct StopAliasDatabase: Codable, Equatable, Sendable {
    public private(set) var aliases: [StopAlias]

    public init(aliases: [StopAlias] = []) {
        self.aliases = aliases.sortedByName()
    }

    public func alias(named name: String) -> StopAlias? {
        let key = Self.lookupKey(name)
        return aliases.first { Self.lookupKey($0.name) == key }
    }

    public mutating func upsert(_ alias: StopAlias) throws {
        let name = alias.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let station = alias.station.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !name.isEmpty else {
            throw StopAliasError.invalidAliasName
        }

        guard !station.isEmpty else {
            throw StopAliasError.invalidStation
        }

        let normalized = Self.lookupKey(name)
        let cleaned = StopAlias(name: name, station: station, timetable: alias.timetable)

        if let index = aliases.firstIndex(where: { Self.lookupKey($0.name) == normalized }) {
            aliases[index] = cleaned
        } else {
            aliases.append(cleaned)
        }

        aliases = aliases.sortedByName()
    }

    @discardableResult
    public mutating func remove(name: String) throws -> StopAlias {
        let key = Self.lookupKey(name)
        guard let index = aliases.firstIndex(where: { Self.lookupKey($0.name) == key }) else {
            throw StopAliasError.aliasNotFound(name)
        }

        return aliases.remove(at: index)
    }

    private static func lookupKey(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "cs_CZ"))
            .filter { $0.isLetter || $0.isNumber }
    }
}

public struct StopAliasFile: Sendable {
    public var fileURL: URL

    public init(fileURL: URL = Self.defaultFileURL()) {
        self.fileURL = fileURL
    }

    public func load() throws -> StopAliasDatabase {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return StopAliasDatabase()
        }

        let data = try Data(contentsOf: fileURL)
        guard !data.isEmpty else {
            return StopAliasDatabase()
        }

        return try JSONDecoder().decode(StopAliasDatabase.self, from: data)
    }

    public func save(_ database: StopAliasDatabase) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(database)
        try data.write(to: fileURL, options: [.atomic])
    }

    public static func defaultFileURL(environment: [String: String] = ProcessInfo.processInfo.environment) -> URL {
        if let value = environment["KASTAN_ALIAS_DATABASE"], !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return URL(fileURLWithPath: value)
        }

        if let value = environment["XDG_CONFIG_HOME"], !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return URL(fileURLWithPath: value)
                .appendingPathComponent("kastan")
                .appendingPathComponent("aliases.json")
        }

        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config")
            .appendingPathComponent("kastan")
            .appendingPathComponent("aliases.json")
    }
}

public enum StopAliasError: LocalizedError, Sendable {
    case aliasNotFound(String)
    case invalidAliasName
    case invalidStation

    public var errorDescription: String? {
        switch self {
        case .aliasNotFound(let name):
            return "Stop alias not found: \(name)."
        case .invalidAliasName:
            return "Stop alias name cannot be empty."
        case .invalidStation:
            return "Stop alias station cannot be empty."
        }
    }
}

private extension Array where Element == StopAlias {
    func sortedByName() -> [StopAlias] {
        sorted { first, second in
            first.name.localizedCaseInsensitiveCompare(second.name) == .orderedAscending
        }
    }
}
