import Foundation

/// Selects how an MCP client exchanges protocol messages with Kaštan.
enum KastanMCPTransportMode: String, Equatable, Sendable {
    case stdio
    case http
}

/// Selects the credential types accepted by the remote MCP endpoint during an OAuth migration.
enum KastanMCPHTTPAuthorizationMode: String, Equatable, Sendable {
    case staticToken = "static"
    case hybrid
    case oauth
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
    let authorizationMode: KastanMCPHTTPAuthorizationMode
    let bearerToken: String?
    let oauth: KastanMCPOAuthConfiguration?
    let allowedOrigins: Set<String>
    let requestsPerMinute: Int

    init(
        host: String,
        port: Int,
        authorizationMode: KastanMCPHTTPAuthorizationMode = .staticToken,
        bearerToken: String?,
        oauth: KastanMCPOAuthConfiguration? = nil,
        allowedOrigins: Set<String>,
        requestsPerMinute: Int
    ) {
        self.host = host
        self.port = port
        self.authorizationMode = authorizationMode
        self.bearerToken = bearerToken
        self.oauth = oauth
        self.allowedOrigins = allowedOrigins
        self.requestsPerMinute = requestsPerMinute
    }
}

/// Describes one OAuth 2.1 protected resource and the authorization server trusted to issue its tokens.
struct KastanMCPOAuthConfiguration: Equatable, Sendable {
    let issuer: URL
    let resource: URL
    let jwksURL: URL
    let requiredScopes: Set<String>

    /// Discovery URL advertised in Bearer challenges and served without authentication.
    var protectedResourceMetadataURL: URL {
        var components = URLComponents(url: resource, resolvingAgainstBaseURL: false)!
        components.path = "/.well-known/oauth-protected-resource"
        components.query = nil
        components.fragment = nil
        return components.url!
    }

    /// Compatibility discovery URL proxied from the configured authorization server.
    var authorizationServerMetadataURL: URL {
        issuer.appending(path: ".well-known/oauth-authorization-server")
    }
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
    case invalidAuthorizationMode(String)
    case missingBearerToken
    case weakBearerToken
    case missingOAuthSetting(String)
    case invalidOAuthURL(String, String)
    case invalidOAuthResource(String)
    case invalidOAuthScope(String)
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
        case .invalidAuthorizationMode(let value):
            "Invalid HTTP authorization mode '\(value)'. Use static, hybrid, or oauth."
        case .missingBearerToken:
            "Static and hybrid HTTP authorization require KASTAN_MCP_BEARER_TOKEN."
        case .weakBearerToken:
            "KASTAN_MCP_BEARER_TOKEN must contain at least 32 non-whitespace bytes."
        case .missingOAuthSetting(let name):
            "OAuth HTTP authorization requires \(name)."
        case .invalidOAuthURL(let name, let value):
            "Invalid \(name) URL '\(value)'. Use an absolute HTTPS URL without credentials, a query, or a fragment."
        case .invalidOAuthResource(let value):
            "Invalid KASTAN_MCP_OAUTH_RESOURCE '\(value)'. Its path must be exactly /mcp."
        case .invalidOAuthScope(let value):
            "Invalid OAuth scope '\(value)'. Use visible ASCII characters other than quotation marks and backslashes."
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
          KASTAN_MCP_AUTH_MODE        static (default), hybrid, or oauth
          KASTAN_MCP_BEARER_TOKEN     Bearer token required by static and hybrid modes
          KASTAN_MCP_OAUTH_ISSUER     OAuth issuer URL required by hybrid and oauth modes
          KASTAN_MCP_OAUTH_RESOURCE   Exact public /mcp URL required by hybrid and oauth modes
          KASTAN_MCP_OAUTH_JWKS_URL   Optional JWKS URL; defaults to ISSUER/oauth2/jwks
          KASTAN_MCP_OAUTH_REQUIRED_SCOPES
                                      Optional comma- or space-separated required scopes
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

        let authorizationModeValue = nonEmpty(environment["KASTAN_MCP_AUTH_MODE"]) ?? "static"
        guard let authorizationMode = KastanMCPHTTPAuthorizationMode(
            rawValue: authorizationModeValue.lowercased()
        ) else {
            throw KastanMCPConfigurationError.invalidAuthorizationMode(authorizationModeValue)
        }

        let bearerToken: String?
        if authorizationMode == .oauth {
            bearerToken = nil
        } else {
            guard let rawToken = environment["KASTAN_MCP_BEARER_TOKEN"] else {
                throw KastanMCPConfigurationError.missingBearerToken
            }
            let token = rawToken.trimmingCharacters(in: .whitespacesAndNewlines)
            guard token.utf8.count >= 32, !token.contains(where: \Character.isWhitespace) else {
                throw KastanMCPConfigurationError.weakBearerToken
            }
            bearerToken = token
        }

        let oauth = try parseOAuthConfiguration(
            authorizationMode: authorizationMode,
            environment: environment
        )

        let allowedOrigins = try parseAllowedOrigins(environment["KASTAN_MCP_ALLOWED_ORIGINS"])
        let http = KastanMCPHTTPConfiguration(
            host: normalizedHost,
            port: port,
            authorizationMode: authorizationMode,
            bearerToken: bearerToken,
            oauth: oauth,
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

    private static func parseOAuthConfiguration(
        authorizationMode: KastanMCPHTTPAuthorizationMode,
        environment: [String: String]
    ) throws -> KastanMCPOAuthConfiguration? {
        guard authorizationMode != .staticToken else { return nil }

        let issuerName = "KASTAN_MCP_OAUTH_ISSUER"
        let resourceName = "KASTAN_MCP_OAUTH_RESOURCE"
        guard let issuerValue = nonEmpty(environment[issuerName]) else {
            throw KastanMCPConfigurationError.missingOAuthSetting(issuerName)
        }
        guard let resourceValue = nonEmpty(environment[resourceName]) else {
            throw KastanMCPConfigurationError.missingOAuthSetting(resourceName)
        }

        let issuer = try parseHTTPSURL(issuerValue, setting: issuerName, removingTrailingSlash: true)
        let resource = try parseHTTPSURL(resourceValue, setting: resourceName)
        guard resource.path == KastanMCPHTTPConfiguration.endpoint else {
            throw KastanMCPConfigurationError.invalidOAuthResource(resourceValue)
        }

        let jwksName = "KASTAN_MCP_OAUTH_JWKS_URL"
        let jwksURL: URL
        if let jwksValue = nonEmpty(environment[jwksName]) {
            jwksURL = try parseHTTPSURL(jwksValue, setting: jwksName)
        } else {
            jwksURL = issuer.appending(path: "oauth2/jwks")
        }

        let requiredScopes = try parseOAuthScopes(environment["KASTAN_MCP_OAUTH_REQUIRED_SCOPES"])
        return KastanMCPOAuthConfiguration(
            issuer: issuer,
            resource: resource,
            jwksURL: jwksURL,
            requiredScopes: requiredScopes
        )
    }

    private static func parseHTTPSURL(
        _ value: String,
        setting: String,
        removingTrailingSlash: Bool = false
    ) throws -> URL {
        guard var components = URLComponents(string: value),
            components.scheme?.lowercased() == "https",
            components.host != nil,
            components.user == nil,
            components.password == nil,
            components.query == nil,
            components.fragment == nil
        else {
            throw KastanMCPConfigurationError.invalidOAuthURL(setting, value)
        }

        if removingTrailingSlash {
            while components.path.count > 1 && components.path.hasSuffix("/") {
                components.path.removeLast()
            }
            if components.path == "/" {
                components.path = ""
            }
        }
        guard let url = components.url else {
            throw KastanMCPConfigurationError.invalidOAuthURL(setting, value)
        }
        return url
    }

    private static func parseOAuthScopes(_ value: String?) throws -> Set<String> {
        guard let value = nonEmpty(value) else { return [] }

        let scopes = value.split { character in
            character == "," || character.isWhitespace
        }.map(String.init)

        for scope in scopes where !scope.utf8.allSatisfy({ byte in
            byte == 0x21 || (0x23...0x5B).contains(byte) || (0x5D...0x7E).contains(byte)
        }) {
            throw KastanMCPConfigurationError.invalidOAuthScope(scope)
        }
        return Set(scopes)
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
