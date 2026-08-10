import Foundation
@testable import KastanMCP
import MCP
import Testing

private let testBearerToken = String(repeating: "a", count: 32)

@Test func commandLineKeepsStdioAsTheDefaultTransport() throws {
    let command = try KastanMCPCommandLine.parse(arguments: [], environment: [:])
    #expect(command == .run(.init(transport: .stdio, http: nil)))
}

@Test func healthEndpointAvoidsCloudRunReservedSuffix() {
    #expect(KastanMCPHTTPConfiguration.healthEndpoint == "/health")
    #expect(!KastanMCPHTTPConfiguration.healthEndpoint.hasSuffix("z"))
}

@Test func commandLineBuildsCloudRunHTTPConfiguration() throws {
    let command = try KastanMCPCommandLine.parse(
        arguments: [
            "--transport", "http",
            "--host", "0.0.0.0",
            "--port", "9090",
            "--requests-per-minute", "12",
        ],
        environment: [
            "KASTAN_MCP_BEARER_TOKEN": testBearerToken,
            "KASTAN_MCP_ALLOWED_ORIGINS": "https://example.com/, https://mcp.example.cz",
        ]
    )

    #expect(command == .run(.init(
        transport: .http,
        http: .init(
            host: "0.0.0.0",
            port: 9090,
            bearerToken: testBearerToken,
            allowedOrigins: ["https://example.com", "https://mcp.example.cz"],
            requestsPerMinute: 12
        )
    )))
}

@Test func commandLineUsesCloudRunPortAndRequiresAStrongToken() throws {
    let command = try KastanMCPCommandLine.parse(
        arguments: ["--transport", "http"],
        environment: [
            "PORT": "8181",
            "KASTAN_MCP_BEARER_TOKEN": testBearerToken,
        ]
    )
    guard case .run(let configuration) = command else {
        Issue.record("Expected a run command")
        return
    }
    #expect(configuration.http?.port == 8181)

    #expect(configurationError(
        arguments: ["--transport", "http"],
        environment: [:]
    ) == .missingBearerToken)
    #expect(configurationError(
        arguments: ["--transport", "http"],
        environment: ["KASTAN_MCP_BEARER_TOKEN": "short"]
    ) == .weakBearerToken)
}

@Test func commandLineRejectsWildcardAndPathOrigins() {
    #expect(configurationError(
        arguments: ["--transport", "http"],
        environment: [
            "KASTAN_MCP_BEARER_TOKEN": testBearerToken,
            "KASTAN_MCP_ALLOWED_ORIGINS": "*",
        ]
    ) == .invalidAllowedOrigin("*"))
    #expect(configurationError(
        arguments: ["--transport", "http"],
        environment: [
            "KASTAN_MCP_BEARER_TOKEN": testBearerToken,
            "KASTAN_MCP_ALLOWED_ORIGINS": "https://example.com/path",
        ]
    ) == .invalidAllowedOrigin("https://example.com/path"))
}

@Test func staticBearerValidatorRequiresTheExactToken() {
    let validator = KastanStaticBearerTokenValidator(expectedToken: testBearerToken)
    let context = HTTPValidationContext(httpMethod: "POST")

    let missing = validator.validate(HTTPRequest(method: "POST"), context: context)
    #expect(missing?.statusCode == 401)
    #expect(missing?.headers[HTTPHeaderName.wwwAuthenticate] == "Bearer realm=\"kastan-mcp\"")

    let wrong = validator.validate(
        HTTPRequest(method: "POST", headers: ["Authorization": "Bearer \(String(repeating: "b", count: 32))"]),
        context: context
    )
    #expect(wrong?.statusCode == 401)

    let accepted = validator.validate(
        HTTPRequest(method: "POST", headers: ["authorization": "bearer \(testBearerToken)"]),
        context: context
    )
    #expect(accepted == nil)
}

@Test func originValidatorRejectsUnlistedBrowserOrigins() {
    let validator = KastanAllowedOriginValidator(allowedOrigins: ["https://allowed.example"])
    let context = HTTPValidationContext(httpMethod: "POST")

    #expect(validator.validate(HTTPRequest(method: "POST"), context: context) == nil)
    #expect(validator.validate(
        HTTPRequest(method: "POST", headers: ["Origin": "https://allowed.example/"]),
        context: context
    ) == nil)
    #expect(validator.validate(
        HTTPRequest(method: "POST", headers: ["Origin": "https://blocked.example"]),
        context: context
    )?.statusCode == 403)
}

@Test func fixedWindowRateLimiterResetsAfterOneMinute() {
    let start = Date(timeIntervalSince1970: 1_000)
    var limiter = KastanFixedWindowRateLimiter(limit: 2, windowStart: start)

    #expect(limiter.retryAfter(now: start) == nil)
    #expect(limiter.retryAfter(now: start.addingTimeInterval(1)) == nil)
    #expect(limiter.retryAfter(now: start.addingTimeInterval(2)) == 58)
    #expect(limiter.retryAfter(now: start.addingTimeInterval(60)) == nil)
}

@Test func HTTPApplicationProtectsMCPAndKeepsHealthPublic() async throws {
    let application = KastanMCPHTTPApplication(configuration: .init(
        host: "127.0.0.1",
        port: 8080,
        bearerToken: testBearerToken,
        allowedOrigins: [],
        requestsPerMinute: 10
    ))

    let health = await application.handleRequest(HTTPRequest(
        method: "GET",
        path: KastanMCPHTTPConfiguration.healthEndpoint
    ))
    #expect(health.statusCode == 200)
    #expect(String(data: try #require(health.bodyData), encoding: .utf8) == "ok\n")

    let unauthorized = await application.handleRequest(HTTPRequest(
        method: "POST",
        headers: mcpHeaders(includeToken: false),
        body: initializeBody(),
        path: KastanMCPHTTPConfiguration.endpoint
    ))
    #expect(unauthorized.statusCode == 401)

    let initialized = await application.handleRequest(HTTPRequest(
        method: "POST",
        headers: mcpHeaders(),
        body: initializeBody(),
        path: KastanMCPHTTPConfiguration.endpoint
    ))
    #expect(initialized.statusCode == 200)
    #expect(String(data: try #require(initialized.bodyData), encoding: .utf8)?.contains("kastan-mcp") == true)

    let tools = await application.handleRequest(HTTPRequest(
        method: "POST",
        headers: mcpHeaders(),
        body: Data(#"{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}"#.utf8),
        path: KastanMCPHTTPConfiguration.endpoint
    ))
    #expect(tools.statusCode == 200)
    let toolsText = String(data: try #require(tools.bodyData), encoding: .utf8)
    #expect(toolsText?.contains("find_connections") == true)

    let noSSE = await application.handleRequest(HTTPRequest(
        method: "GET",
        headers: ["Authorization": "Bearer \(testBearerToken)", "Accept": "text/event-stream"],
        path: KastanMCPHTTPConfiguration.endpoint
    ))
    #expect(noSSE.statusCode == 405)
}

private func configurationError(
    arguments: [String],
    environment: [String: String]
) -> KastanMCPConfigurationError? {
    do {
        _ = try KastanMCPCommandLine.parse(arguments: arguments, environment: environment)
        return nil
    } catch let error as KastanMCPConfigurationError {
        return error
    } catch {
        Issue.record("Unexpected error: \(error)")
        return nil
    }
}

private func mcpHeaders(includeToken: Bool = true) -> [String: String] {
    var headers = [
        "Content-Type": "application/json",
        "Accept": "application/json, text/event-stream",
        "MCP-Protocol-Version": "2025-06-18",
    ]
    if includeToken {
        headers["Authorization"] = "Bearer \(testBearerToken)"
    }
    return headers
}

private func initializeBody() -> Data {
    Data(
        #"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"http-test","version":"1.0"}}}"#.utf8
    )
}
