import Foundation

/// Selects how an MCP client exchanges protocol messages with Kaštan.
enum KastanMCPTransportMode: String, Equatable, Sendable {
    case stdio
    case http
}

/// Holds the process-level transport choice and its validated HTTP settings when applicable.
struct KastanMCPRuntimeConfiguration: Equatable, Sendable {
    let transport: KastanMCPTransportMode
    let http: KastanMCPHTTPConfiguration?
}

/// Configures the protected Streamable HTTP endpoint used by remote MCP clients.
struct KastanMCPHTTPConfiguration: Equatable, Sendable {
    static let endpoint = "/mcp"
    // Cloud Run reserves some paths ending in "z", so the public probe must not use /healthz.
    static let healthEndpoint = "/health"
    static let maximumRequestBodyBytes = 1_048_576

    let host: String
    let port: Int
    let bearerToken: String
    let allowedOrigins: Set<String>
    let requestsPerMinute: Int
}

/// Represents one complete command-line action for the MCP executable.
enum KastanMCPCommand: Equatable, Sendable {
    case help
    case version
    case run(KastanMCPRuntimeConfiguration)
}

/// Reports configuration mistakes before the MCP server opens a local or network transport.
enum KastanMCPConfigurationError: LocalizedError, Equatable {
    case missingValue(String)
    case unknownOption(String)
    case invalidTransport(String)
    case invalidHost
    case invalidPort(String)
    case missingBearerToken
    case weakBearerToken
    case invalidAllowedOrigin(String)
    case invalidRateLimit(String)
    case standaloneOption(String)
    case missingHTTPConfiguration

    var errorDescription: String? {
        switch self {
        case .missingValue(let option):
            "Option '\(option)' requires a value."
        case .unknownOption(let option):
            "Unknown option '\(option)'. Use --help for supported options."
        case .invalidTransport(let value):
            "Invalid transport '\(value)'. Use stdio or http."
        case .invalidHost:
            "The HTTP host must not be empty."
        case .invalidPort(let value):
            "Invalid HTTP port '\(value)'. Use a number from 1 through 65535."
        case .missingBearerToken:
            "HTTP transport requires KASTAN_MCP_BEARER_TOKEN."
        case .weakBearerToken:
            "KASTAN_MCP_BEARER_TOKEN must contain at least 32 non-whitespace bytes."
        case .invalidAllowedOrigin(let value):
            "Invalid allowed origin '\(value)'. Use an explicit http:// or https:// origin without a path."
        case .invalidRateLimit(let value):
            "Invalid requests-per-minute value '\(value)'. Use a number from 1 through 10000."
        case .standaloneOption(let option):
            "Option '\(option)' must be used on its own."
        case .missingHTTPConfiguration:
            "HTTP transport configuration is missing."
        }
    }
}

/// Parses the small public interface shared by local stdio use and hosted HTTP deployments.
enum KastanMCPCommandLine {
    static let help = """
        🌰 Kaštan MCP server

        Usage:
          kastan-mcp [--transport stdio|http] [--host ADDRESS] [--port PORT]
                     [--requests-per-minute COUNT]
          kastan-mcp --help
          kastan-mcp --version

        Options:
          --transport MODE            MCP transport; defaults to stdio
          --host ADDRESS              HTTP bind address; defaults to 127.0.0.1
          --port PORT                 HTTP port; defaults to KASTAN_MCP_PORT, PORT, or 8080
          --requests-per-minute COUNT Shared HTTP request limit; defaults to 60
          -h, --help                  Show this help
          --version                   Show the server version

        HTTP environment:
          KASTAN_MCP_BEARER_TOKEN     Required Bearer token with at least 32 bytes
          KASTAN_MCP_ALLOWED_ORIGINS  Optional comma-separated browser origins
          KASTAN_MCP_TRANSPORT        Default transport when --transport is omitted
          KASTAN_MCP_HOST             Default HTTP bind address
          KASTAN_MCP_PORT             Default HTTP port before the platform PORT value
          KASTAN_MCP_REQUESTS_PER_MINUTE
                                      Default shared HTTP request limit
        """

    static func parse(
        arguments: [String],
        environment: [String: String]
    ) throws -> KastanMCPCommand {
        if arguments.contains("--help") || arguments.contains("-h") {
            guard arguments.count == 1 else {
                throw KastanMCPConfigurationError.standaloneOption("--help")
            }
            return .help
        }
        if arguments.contains("--version") {
            guard arguments.count == 1 else {
                throw KastanMCPConfigurationError.standaloneOption("--version")
            }
            return .version
        }

        var transportValue = nonEmpty(environment["KASTAN_MCP_TRANSPORT"]) ?? "stdio"
        var host = nonEmpty(environment["KASTAN_MCP_HOST"]) ?? "127.0.0.1"
        var portValue = nonEmpty(environment["KASTAN_MCP_PORT"])
            ?? nonEmpty(environment["PORT"])
            ?? "8080"
        var rateLimitValue = nonEmpty(environment["KASTAN_MCP_REQUESTS_PER_MINUTE"]) ?? "60"

        var index = 0
        while index < arguments.count {
            let option = arguments[index]
            switch option {
            case "--transport":
                transportValue = try requiredValue(after: &index, option: option, arguments: arguments)
            case "--host":
                host = try requiredValue(after: &index, option: option, arguments: arguments)
            case "--port":
                portValue = try requiredValue(after: &index, option: option, arguments: arguments)
            case "--requests-per-minute":
                rateLimitValue = try requiredValue(after: &index, option: option, arguments: arguments)
            default:
                throw KastanMCPConfigurationError.unknownOption(option)
            }
            index += 1
        }

        guard let transport = KastanMCPTransportMode(rawValue: transportValue.lowercased()) else {
            throw KastanMCPConfigurationError.invalidTransport(transportValue)
        }
        guard transport == .http else {
            return .run(.init(transport: .stdio, http: nil))
        }

        let normalizedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedHost.isEmpty else {
            throw KastanMCPConfigurationError.invalidHost
        }
        guard let port = Int(portValue), (1...65_535).contains(port) else {
            throw KastanMCPConfigurationError.invalidPort(portValue)
        }
        guard let requestsPerMinute = Int(rateLimitValue), (1...10_000).contains(requestsPerMinute) else {
            throw KastanMCPConfigurationError.invalidRateLimit(rateLimitValue)
        }

        guard let rawToken = environment["KASTAN_MCP_BEARER_TOKEN"] else {
            throw KastanMCPConfigurationError.missingBearerToken
        }
        let token = rawToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard token.utf8.count >= 32, !token.contains(where: \Character.isWhitespace) else {
            throw KastanMCPConfigurationError.weakBearerToken
        }

        let allowedOrigins = try parseAllowedOrigins(environment["KASTAN_MCP_ALLOWED_ORIGINS"])
        let http = KastanMCPHTTPConfiguration(
            host: normalizedHost,
            port: port,
            bearerToken: token,
            allowedOrigins: allowedOrigins,
            requestsPerMinute: requestsPerMinute
        )
        return .run(.init(transport: .http, http: http))
    }

    private static func requiredValue(
        after index: inout Int,
        option: String,
        arguments: [String]
    ) throws -> String {
        index += 1
        guard index < arguments.count else {
            throw KastanMCPConfigurationError.missingValue(option)
        }
        return arguments[index]
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value else { return nil }
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty ? nil : normalized
    }

    private static func parseAllowedOrigins(_ value: String?) throws -> Set<String> {
        guard let value = nonEmpty(value) else { return [] }

        return try Set(value.split(separator: ",").map { rawOrigin in
            let origin = rawOrigin.trimmingCharacters(in: .whitespacesAndNewlines)
            guard origin != "*",
                let components = URLComponents(string: origin),
                let scheme = components.scheme?.lowercased(),
                scheme == "http" || scheme == "https",
                components.host != nil,
                components.user == nil,
                components.password == nil,
                components.query == nil,
                components.fragment == nil,
                components.path.isEmpty || components.path == "/"
            else {
                throw KastanMCPConfigurationError.invalidAllowedOrigin(origin)
            }
            return origin.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        })
    }
}
