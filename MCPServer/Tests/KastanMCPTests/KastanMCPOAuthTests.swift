import Foundation
import JWTKit
@testable import KastanMCP
import MCP
import Testing

private let oauthNow = Date(timeIntervalSince1970: 2_000_000_000)
private let oauthIssuer = URL(string: "https://kastan-test.authkit.app")!
private let oauthResource = URL(string: "https://mcp.example.com/mcp")!
private let oauthKeyID = "kastan-test-key"
private let oauthModulus = """
    vTHHoCaR0tlYfvapRv94hUTMrdSymIrWIIZ5Kmv5bIYWtK0TMX0icLkB0PzR2IDLj1L7hzBKUljBGzjf6ujfZwru5-odDZ344A6AhH5B5Zie1ALUTnizD-8XtWcdOtv4aF5NwgRJns0YY-HVr_KKfPZurfMf7JI2wSCt0TRRUixkfJgypnLNZNMowcMiGD9GYdCb2mC43V8DKNpUIIIUJK_auxqAxdEnY6GwI4zYnQdCv8ULai_LcB2CQhj5gm9PeKI6K1qkKs5_F1N2-2y9srrSk7pYPU0xxrj5Ap5GsTaJJJhV9QV1bgDiJaakWhh2m9jSs6SsufHCPT5RiCVh5Q
    """
private let oauthExponent = "AQAB"
private let oauthPrivateExponent = """
    B0fVIMqbLfwDNc-UMBFAuBAvuDjJLqmZF-NU4lcJYC3Aze8jH_Jq0t-rvDkecjBypO9Skp8_HPAhbkTACTAw-KwpCW-u8okzvJuSQocBTi6TXiFFvkdSzLgst2RicZNpecq3P1Ie6yeFWsKkEINK5Qguti72-Yme5cu2JKjYwEq37c94_hNdD4CPY7XebgcXeb8dnqr40--WVIbyxSYl5uV6ZRx7vQGXyZwFezhgoyYMhkoRs88iukTeOjs_MRfmTr-akfYm67Pzwm0bC7gHU0aNS_apl7KDNfIO2MOE11WDYKmul1VmH6N0mEaxdOa_Mw5S0JlB9szX3lAEd5-buQ
    """

@Test func commandLineBuildsWorkOSOAuthAndHybridConfigurations() throws {
    let oauthEnvironment = [
        "KASTAN_MCP_AUTH_MODE": "oauth",
        "KASTAN_MCP_OAUTH_ISSUER": "https://kastan-test.authkit.app/",
        "KASTAN_MCP_OAUTH_RESOURCE": "https://mcp.example.com/mcp",
        "KASTAN_MCP_OAUTH_REQUIRED_SCOPES": "openid, kastan:read",
    ]
    let oauthCommand = try KastanMCPCommandLine.parse(
        arguments: ["--transport", "http"],
        environment: oauthEnvironment
    )
    guard case .run(let oauthRuntime) = oauthCommand,
        let oauthHTTP = oauthRuntime.http,
        let oauth = oauthHTTP.oauth
    else {
        Issue.record("Expected an OAuth HTTP configuration")
        return
    }
    #expect(oauthHTTP.authorizationMode == .oauth)
    #expect(oauthHTTP.bearerToken == nil)
    #expect(oauth.issuer == oauthIssuer)
    #expect(oauth.resource == oauthResource)
    #expect(oauth.jwksURL == URL(string: "https://kastan-test.authkit.app/oauth2/jwks"))
    #expect(oauth.requiredScopes == ["openid", "kastan:read"])

    var hybridEnvironment = oauthEnvironment
    hybridEnvironment["KASTAN_MCP_AUTH_MODE"] = "hybrid"
    hybridEnvironment["KASTAN_MCP_BEARER_TOKEN"] = String(repeating: "h", count: 32)
    let hybridCommand = try KastanMCPCommandLine.parse(
        arguments: ["--transport", "http"],
        environment: hybridEnvironment
    )
    guard case .run(let hybridRuntime) = hybridCommand else {
        Issue.record("Expected a hybrid HTTP configuration")
        return
    }
    #expect(hybridRuntime.http?.authorizationMode == .hybrid)
    #expect(hybridRuntime.http?.bearerToken == String(repeating: "h", count: 32))
    #expect(hybridRuntime.http?.oauth == oauth)
}

@Test func commandLineRejectsIncompleteOrUnsafeOAuthConfiguration() {
    #expect(oauthConfigurationError(["KASTAN_MCP_AUTH_MODE": "oidc"]) == .invalidAuthorizationMode("oidc"))
    #expect(oauthConfigurationError([
        "KASTAN_MCP_AUTH_MODE": "oauth",
    ]) == .missingOAuthSetting("KASTAN_MCP_OAUTH_ISSUER"))
    #expect(oauthConfigurationError([
        "KASTAN_MCP_AUTH_MODE": "oauth",
        "KASTAN_MCP_OAUTH_ISSUER": "http://auth.example.com",
        "KASTAN_MCP_OAUTH_RESOURCE": oauthResource.absoluteString,
    ]) == .invalidOAuthURL("KASTAN_MCP_OAUTH_ISSUER", "http://auth.example.com"))
    #expect(oauthConfigurationError([
        "KASTAN_MCP_AUTH_MODE": "oauth",
        "KASTAN_MCP_OAUTH_ISSUER": oauthIssuer.absoluteString,
        "KASTAN_MCP_OAUTH_RESOURCE": "https://mcp.example.com/not-mcp",
    ]) == .invalidOAuthResource("https://mcp.example.com/not-mcp"))
    #expect(oauthConfigurationError([
        "KASTAN_MCP_AUTH_MODE": "hybrid",
        "KASTAN_MCP_OAUTH_ISSUER": oauthIssuer.absoluteString,
        "KASTAN_MCP_OAUTH_RESOURCE": oauthResource.absoluteString,
    ]) == .missingBearerToken)
}

@Test func OAuthDiscoveryIsPublicAndChallengesPointToIt() async throws {
    let upstreamMetadata = Data(#"{"issuer":"https://kastan-test.authkit.app","authorization_endpoint":"https://kastan-test.authkit.app/oauth2/authorize"}"#.utf8)
    let fetchRecorder = OAuthFetchRecorder(responses: [
        oauthConfiguration().authorizationServerMetadataURL: .init(
            data: upstreamMetadata,
            cacheLifetime: 600
        ),
    ])
    let application = KastanMCPHTTPApplication(
        configuration: oauthHTTPConfiguration(),
        oauthFetcher: { try await fetchRecorder.fetch($0) },
        clock: { oauthNow }
    )

    let rootMetadata = await application.handleRequest(HTTPRequest(
        method: "GET",
        path: "/.well-known/oauth-protected-resource"
    ))
    #expect(rootMetadata.statusCode == 200)
    let metadataData = try #require(rootMetadata.bodyData)
    let metadataObject = try #require(
        JSONSerialization.jsonObject(with: metadataData) as? [String: Any]
    )
    #expect(metadataObject["resource"] as? String == oauthResource.absoluteString)
    #expect(metadataObject["authorization_servers"] as? [String] == [oauthIssuer.absoluteString])
    #expect(metadataObject["bearer_methods_supported"] as? [String] == ["header"])
    #expect(Set(metadataObject["scopes_supported"] as? [String] ?? []) == ["kastan:read"])

    let pathMetadata = await application.handleRequest(HTTPRequest(
        method: "GET",
        path: "/.well-known/oauth-protected-resource/mcp"
    ))
    #expect(pathMetadata.statusCode == 200)
    #expect(pathMetadata.bodyData == rootMetadata.bodyData)

    let compatibilityMetadata = await application.handleRequest(HTTPRequest(
        method: "GET",
        path: "/.well-known/oauth-authorization-server"
    ))
    #expect(compatibilityMetadata.statusCode == 200)
    #expect(compatibilityMetadata.bodyData == upstreamMetadata)
    let cachedCompatibilityMetadata = await application.handleRequest(HTTPRequest(
        method: "GET",
        path: "/.well-known/oauth-authorization-server"
    ))
    #expect(cachedCompatibilityMetadata.bodyData == upstreamMetadata)
    #expect(await fetchRecorder.fetchCount == 1)

    let unauthorized = await application.handleRequest(HTTPRequest(
        method: "POST",
        path: KastanMCPHTTPConfiguration.endpoint
    ))
    #expect(unauthorized.statusCode == 401)
    let challenge = try #require(unauthorized.headers[HTTPHeaderName.wwwAuthenticate])
    #expect(challenge.contains("resource_metadata=\"https://mcp.example.com/.well-known/oauth-protected-resource\""))
    #expect(challenge.contains("scope=\"kastan:read\""))
    #expect(!challenge.contains("error="))
}

@Test func WorkOSJWTVerifierChecksSignatureClaimsScopesAndCachesJWKS() async throws {
    let fetchRecorder = OAuthFetchRecorder(responses: [
        oauthConfiguration().jwksURL: .init(data: oauthJWKS(), cacheLifetime: 3_600),
    ])
    let verifier = KastanOAuthJWTVerifier(
        configuration: oauthConfiguration(),
        fetcher: { try await fetchRecorder.fetch($0) },
        clock: { oauthNow }
    )

    let validToken = try await signedOAuthToken()
    guard case .valid(let info) = await verifier.validate(validToken) else {
        Issue.record("Expected a valid WorkOS token")
        return
    }
    #expect(info.audience == [oauthResource.absoluteString])
    #expect(info.scopes == ["kastan:read", "openid"])

    guard case .valid = await verifier.validate(validToken) else {
        Issue.record("Expected the cached WorkOS key to remain valid")
        return
    }
    #expect(await fetchRecorder.fetchCount == 1)

    let wrongIssuer = try await signedOAuthToken(issuer: "https://other.authkit.app")
    guard case .invalidToken = await verifier.validate(wrongIssuer) else {
        Issue.record("Expected issuer validation to fail")
        return
    }

    let wrongAudience = try await signedOAuthToken(audience: "https://mcp.example.com/other")
    guard case .invalidToken = await verifier.validate(wrongAudience) else {
        Issue.record("Expected audience validation to fail")
        return
    }

    let expired = try await signedOAuthToken(expiration: oauthNow.addingTimeInterval(-61))
    guard case .invalidToken = await verifier.validate(expired) else {
        Issue.record("Expected expiry validation to fail")
        return
    }

    let future = try await signedOAuthToken(notBefore: oauthNow.addingTimeInterval(61))
    guard case .invalidToken = await verifier.validate(future) else {
        Issue.record("Expected not-before validation to fail")
        return
    }

    let missingScope = try await signedOAuthToken(scope: "openid")
    guard case .insufficientScope(let scopes, _) = await verifier.validate(missingScope) else {
        Issue.record("Expected scope validation to fail")
        return
    }
    #expect(scopes == ["kastan:read"])

    let corrupted = corruptSignature(validToken)
    guard case .invalidToken = await verifier.validate(corrupted) else {
        Issue.record("Expected signature validation to fail")
        return
    }
}

@Test func HTTPApplicationAcceptsOAuthAndHybridCredentials() async throws {
    let fetchRecorder = OAuthFetchRecorder(responses: [
        oauthConfiguration().jwksURL: .init(data: oauthJWKS(), cacheLifetime: 3_600),
    ])
    let token = try await signedOAuthToken()
    let oauthApplication = KastanMCPHTTPApplication(
        configuration: oauthHTTPConfiguration(),
        oauthFetcher: { try await fetchRecorder.fetch($0) },
        clock: { oauthNow }
    )

    let initialized = await oauthApplication.handleRequest(HTTPRequest(
        method: "POST",
        headers: oauthMCPHeaders(token: token),
        body: oauthInitializeBody(),
        path: KastanMCPHTTPConfiguration.endpoint
    ))
    #expect(initialized.statusCode == 200)

    let staticToken = String(repeating: "s", count: 32)
    let hybridApplication = KastanMCPHTTPApplication(
        configuration: oauthHTTPConfiguration(mode: .hybrid, bearerToken: staticToken),
        oauthFetcher: { try await fetchRecorder.fetch($0) },
        clock: { oauthNow }
    )
    let staticInitialized = await hybridApplication.handleRequest(HTTPRequest(
        method: "POST",
        headers: oauthMCPHeaders(token: staticToken),
        body: oauthInitializeBody(),
        path: KastanMCPHTTPConfiguration.endpoint
    ))
    #expect(staticInitialized.statusCode == 200)
}

private actor OAuthFetchRecorder {
    let responses: [URL: KastanOAuthHTTPResponse]
    private(set) var fetchCount = 0

    init(responses: [URL: KastanOAuthHTTPResponse]) {
        self.responses = responses
    }

    func fetch(_ url: URL) throws -> KastanOAuthHTTPResponse {
        fetchCount += 1
        guard let response = responses[url] else {
            throw KastanOAuthHTTPError.invalidResponse
        }
        return response
    }
}

private func oauthConfiguration(requiredScopes: Set<String> = ["kastan:read"]) -> KastanMCPOAuthConfiguration {
    KastanMCPOAuthConfiguration(
        issuer: oauthIssuer,
        resource: oauthResource,
        jwksURL: oauthIssuer.appending(path: "oauth2/jwks"),
        requiredScopes: requiredScopes
    )
}

private func oauthHTTPConfiguration(
    mode: KastanMCPHTTPAuthorizationMode = .oauth,
    bearerToken: String? = nil
) -> KastanMCPHTTPConfiguration {
    KastanMCPHTTPConfiguration(
        host: "127.0.0.1",
        port: 8080,
        authorizationMode: mode,
        bearerToken: bearerToken,
        oauth: oauthConfiguration(),
        allowedOrigins: [],
        requestsPerMinute: 20
    )
}

private func oauthConfigurationError(_ environment: [String: String]) -> KastanMCPConfigurationError? {
    do {
        _ = try KastanMCPCommandLine.parse(
            arguments: ["--transport", "http"],
            environment: environment
        )
        return nil
    } catch let error as KastanMCPConfigurationError {
        return error
    } catch {
        Issue.record("Unexpected error: \(error)")
        return nil
    }
}

private func signedOAuthToken(
    issuer: String = oauthIssuer.absoluteString,
    audience: String = oauthResource.absoluteString,
    expiration: Date = oauthNow.addingTimeInterval(600),
    notBefore: Date? = nil,
    scope: String = "openid kastan:read"
) async throws -> String {
    let signingKeys = try await JWTKeyCollection().add(jwk: .rsa(
        .rs256,
        identifier: JWKIdentifier(string: oauthKeyID),
        modulus: oauthModulus,
        exponent: oauthExponent,
        privateExponent: oauthPrivateExponent
    ))
    let claims = KastanOAuthAccessTokenClaims(
        issuer: IssuerClaim(value: issuer),
        subject: SubjectClaim(value: "user_test"),
        audience: AudienceClaim(value: [audience]),
        expiration: ExpirationClaim(value: expiration),
        notBefore: notBefore.map(NotBeforeClaim.init(value:)),
        issuedAt: IssuedAtClaim(value: oauthNow),
        scope: scope
    )
    return try await signingKeys.sign(claims, kid: JWKIdentifier(string: oauthKeyID))
}

private func oauthJWKS() -> Data {
    try! JSONSerialization.data(withJSONObject: [
        "keys": [[
            "kty": "RSA",
            "alg": "RS256",
            "use": "sig",
            "kid": oauthKeyID,
            "n": oauthModulus,
            "e": oauthExponent,
        ]],
    ])
}

private func corruptSignature(_ token: String) -> String {
    var segments = token.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
    let replacement = segments[2].first == "A" ? "B" : "A"
    segments[2].replaceSubrange(segments[2].startIndex...segments[2].startIndex, with: replacement)
    return segments.joined(separator: ".")
}

private func oauthMCPHeaders(token: String) -> [String: String] {
    [
        "Authorization": "Bearer \(token)",
        "Content-Type": "application/json",
        "Accept": "application/json, text/event-stream",
        "MCP-Protocol-Version": "2025-06-18",
    ]
}

private func oauthInitializeBody() -> Data {
    Data(
        #"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"oauth-test","version":"1.0"}}}"#.utf8
    )
}
