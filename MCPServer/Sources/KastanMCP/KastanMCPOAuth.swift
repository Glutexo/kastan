import Foundation
#if canImport(FoundationNetworking)
@preconcurrency import FoundationNetworking
#endif
import JWTKit
import MCP

/// A bounded HTTPS response used for OAuth discovery and public-key refreshes.
struct KastanOAuthHTTPResponse: Sendable {
    let data: Data
    let cacheLifetime: TimeInterval
}

/// Fetches public OAuth documents without sending application credentials upstream.
enum KastanOAuthHTTPClient {
    static let maximumResponseBytes = 1_048_576

    static func fetch(_ url: URL) async throws -> KastanOAuthHTTPResponse {
        var request = URLRequest(url: url, timeoutInterval: 10)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let session = URLSession(
            configuration: .ephemeral,
            delegate: KastanOAuthNoRedirectDelegate(),
            delegateQueue: nil
        )
        defer { session.invalidateAndCancel() }
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw KastanOAuthHTTPError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw KastanOAuthHTTPError.status(httpResponse.statusCode)
        }
        guard data.count <= maximumResponseBytes else {
            throw KastanOAuthHTTPError.responseTooLarge
        }

        return KastanOAuthHTTPResponse(
            data: data,
            cacheLifetime: cacheLifetime(from: httpResponse)
        )
    }

    private static func cacheLifetime(from response: HTTPURLResponse) -> TimeInterval {
        guard let cacheControl = response.value(forHTTPHeaderField: "Cache-Control") else {
            return 3_600
        }

        for rawDirective in cacheControl.split(separator: ",") {
            let directive = rawDirective.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard directive.hasPrefix("max-age=") else { continue }
            let value = directive.dropFirst("max-age=".count)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            if let seconds = TimeInterval(value) {
                return min(max(seconds, 60), 86_400)
            }
        }
        return 3_600
    }
}

/// Prevents a trusted HTTPS discovery URL from silently redirecting key retrieval elsewhere.
private final class KastanOAuthNoRedirectDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}

/// Reports why a public OAuth document could not be used without exposing any credential material.
enum KastanOAuthHTTPError: LocalizedError {
    case invalidResponse
    case status(Int)
    case responseTooLarge

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            "The OAuth endpoint did not return an HTTP response."
        case .status(let status):
            "The OAuth endpoint returned HTTP \(status)."
        case .responseTooLarge:
            "The OAuth endpoint response exceeded 1 MiB."
        }
    }
}

/// Claims required from every WorkOS access token accepted by the Kaštan resource server.
struct KastanOAuthAccessTokenClaims: JWTPayload, Equatable {
    let issuer: IssuerClaim
    let subject: SubjectClaim
    let audience: AudienceClaim
    let expiration: ExpirationClaim
    let notBefore: NotBeforeClaim?
    let issuedAt: IssuedAtClaim?
    let scope: String?

    enum CodingKeys: String, CodingKey {
        case issuer = "iss"
        case subject = "sub"
        case audience = "aud"
        case expiration = "exp"
        case notBefore = "nbf"
        case issuedAt = "iat"
        case scope
    }

    /// Signature verification is performed by JWTKit; contextual claims are checked by the verifier actor.
    func verify(using algorithm: some JWTAlgorithm) async throws {}
}

/// Validates WorkOS RS256 access tokens and refreshes its public-key cache safely across requests.
actor KastanOAuthJWTVerifier {
    typealias Fetcher = @Sendable (URL) async throws -> KastanOAuthHTTPResponse
    typealias Clock = @Sendable () -> Date

    private struct JOSEHeader: Decodable {
        let algorithm: String
        let keyID: String

        enum CodingKeys: String, CodingKey {
            case algorithm = "alg"
            case keyID = "kid"
        }
    }

    private struct RemoteJWKS: Decodable {
        let keys: [RemoteJWK]
    }

    private struct RemoteJWK: Decodable {
        let keyType: String
        let algorithm: String?
        let use: String?
        let keyID: String
        let modulus: String
        let exponent: String

        enum CodingKeys: String, CodingKey {
            case keyType = "kty"
            case algorithm = "alg"
            case use
            case keyID = "kid"
            case modulus = "n"
            case exponent = "e"
        }
    }

    private let configuration: KastanMCPOAuthConfiguration
    private let fetcher: Fetcher
    private let clock: Clock
    private var keyCollection: JWTKeyCollection?
    private var keyIDs: Set<String> = []
    private var cacheExpiresAt = Date.distantPast
    private var lastRefreshAt = Date.distantPast

    init(
        configuration: KastanMCPOAuthConfiguration,
        fetcher: @escaping Fetcher = { try await KastanOAuthHTTPClient.fetch($0) },
        clock: @escaping Clock = { Date() }
    ) {
        self.configuration = configuration
        self.fetcher = fetcher
        self.clock = clock
    }

    /// Produces standard OAuth resource-server semantics after cryptographic and contextual validation.
    func validate(_ token: String) async -> BearerTokenValidationResult {
        do {
            let header = try parseHeader(token)
            let now = clock()

            if keyCollection == nil || cacheExpiresAt <= now {
                try await refreshKeys(now: now)
            } else if !keyIDs.contains(header.keyID), now.timeIntervalSince(lastRefreshAt) >= 30 {
                // An unknown key normally signals rotation. The cooldown prevents arbitrary KIDs
                // from turning unauthenticated requests into an upstream request flood.
                try await refreshKeys(now: now)
            }

            guard keyIDs.contains(header.keyID), let keyCollection else {
                throw KastanOAuthValidationError.unknownKey
            }
            let claims = try await keyCollection.verify(token, as: KastanOAuthAccessTokenClaims.self)
            return try validateClaims(claims, now: now)
        } catch let error as KastanOAuthValidationError {
            switch error {
            case .insufficientScope(let scopes):
                return .insufficientScope(
                    requiredScopes: scopes,
                    errorDescription: "The access token is missing a required scope."
                )
            default:
                return .invalidToken(errorDescription: "Access token validation failed.")
            }
        } catch {
            return .invalidToken(errorDescription: "Access token validation failed.")
        }
    }

    private func parseHeader(_ token: String) throws -> JOSEHeader {
        guard token.utf8.count <= 65_536 else {
            throw KastanOAuthValidationError.malformedToken
        }
        let segments = token.split(separator: ".", omittingEmptySubsequences: false)
        guard segments.count == 3,
            !segments[0].isEmpty,
            !segments[1].isEmpty,
            !segments[2].isEmpty,
            let headerData = base64URLDecoded(String(segments[0]))
        else {
            throw KastanOAuthValidationError.malformedToken
        }

        let header = try JSONDecoder().decode(JOSEHeader.self, from: headerData)
        guard header.algorithm == "RS256",
            !header.keyID.isEmpty,
            header.keyID.utf8.count <= 256
        else {
            throw KastanOAuthValidationError.unsupportedAlgorithm
        }
        return header
    }

    private func refreshKeys(now: Date) async throws {
        let response = try await fetcher(configuration.jwksURL)
        let document = try JSONDecoder().decode(RemoteJWKS.self, from: response.data)
        let acceptedKeys = document.keys.filter { key in
            key.keyType == "RSA"
                && (key.algorithm == nil || key.algorithm == "RS256")
                && (key.use == nil || key.use == "sig")
                && !key.keyID.isEmpty
                && !key.modulus.isEmpty
                && !key.exponent.isEmpty
        }
        guard !acceptedKeys.isEmpty,
            Set(acceptedKeys.map(\.keyID)).count == acceptedKeys.count
        else {
            throw KastanOAuthValidationError.invalidKeySet
        }

        let replacement = JWTKeyCollection()
        for key in acceptedKeys {
            try await replacement.add(jwk: .rsa(
                .rs256,
                identifier: JWKIdentifier(string: key.keyID),
                modulus: key.modulus,
                exponent: key.exponent
            ))
        }

        keyCollection = replacement
        keyIDs = Set(acceptedKeys.map(\.keyID))
        lastRefreshAt = now
        cacheExpiresAt = now.addingTimeInterval(min(max(response.cacheLifetime, 60), 86_400))
    }

    private func validateClaims(
        _ claims: KastanOAuthAccessTokenClaims,
        now: Date
    ) throws -> BearerTokenValidationResult {
        guard claims.issuer.value == configuration.issuer.absoluteString,
            !claims.subject.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            claims.audience.value.contains(configuration.resource.absoluteString),
            claims.expiration.value > now.addingTimeInterval(-60)
        else {
            throw KastanOAuthValidationError.invalidClaims
        }
        if let notBefore = claims.notBefore,
            notBefore.value > now.addingTimeInterval(60)
        {
            throw KastanOAuthValidationError.invalidClaims
        }
        if let issuedAt = claims.issuedAt,
            issuedAt.value > now.addingTimeInterval(60)
        {
            throw KastanOAuthValidationError.invalidClaims
        }

        let grantedScopes = Set((claims.scope ?? "").split(whereSeparator: \.isWhitespace).map(String.init))
        let missingScopes = configuration.requiredScopes.subtracting(grantedScopes)
        guard missingScopes.isEmpty else {
            throw KastanOAuthValidationError.insufficientScope(configuration.requiredScopes)
        }

        return .valid(BearerTokenInfo(
            audience: claims.audience.value,
            scopes: grantedScopes,
            expiresAt: claims.expiration.value
        ))
    }

    private func base64URLDecoded(_ value: String) -> Data? {
        var base64 = value.replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = base64.utf8.count % 4
        if remainder != 0 {
            base64.append(String(repeating: "=", count: 4 - remainder))
        }
        return Data(base64Encoded: base64)
    }
}

/// Internal validation failures map to deliberately generic public OAuth errors.
enum KastanOAuthValidationError: Error, Equatable {
    case malformedToken
    case unsupportedAlgorithm
    case unknownKey
    case invalidKeySet
    case invalidClaims
    case insufficientScope(Set<String>)
}

/// RFC 9728 discovery document advertised to MCP clients before authorization begins.
private struct KastanOAuthProtectedResourceMetadata: Encodable {
    let resource: String
    let authorizationServers: [URL]
    let bearerMethodsSupported = ["header"]
    let scopesSupported: [String]?

    enum CodingKeys: String, CodingKey {
        case resource
        case authorizationServers = "authorization_servers"
        case bearerMethodsSupported = "bearer_methods_supported"
        case scopesSupported = "scopes_supported"
    }
}

/// Serves OAuth discovery and authorizes HTTP requests in static, hybrid, or OAuth-only mode.
actor KastanMCPHTTPAuthorization {
    typealias Fetcher = KastanOAuthJWTVerifier.Fetcher

    private let configuration: KastanMCPHTTPConfiguration
    private let oauthVerifier: KastanOAuthJWTVerifier?
    private let fetcher: Fetcher
    private let clock: KastanOAuthJWTVerifier.Clock
    private let protectedResourceMetadata: Data?
    private var authorizationServerMetadata: Data?
    private var authorizationServerMetadataExpiresAt = Date.distantPast

    private struct AuthorizationServerMetadata: Decodable {
        let issuer: String
    }

    init(
        configuration: KastanMCPHTTPConfiguration,
        fetcher: @escaping Fetcher = { try await KastanOAuthHTTPClient.fetch($0) },
        clock: @escaping KastanOAuthJWTVerifier.Clock = { Date() }
    ) {
        self.configuration = configuration
        self.fetcher = fetcher
        self.clock = clock

        if let oauth = configuration.oauth {
            self.oauthVerifier = KastanOAuthJWTVerifier(
                configuration: oauth,
                fetcher: fetcher,
                clock: clock
            )
            let metadata = KastanOAuthProtectedResourceMetadata(
                resource: oauth.resource.absoluteString,
                authorizationServers: [oauth.issuer],
                scopesSupported: oauth.requiredScopes.isEmpty ? nil : oauth.requiredScopes.sorted()
            )
            self.protectedResourceMetadata = try? JSONEncoder().encode(metadata)
        } else {
            self.oauthVerifier = nil
            self.protectedResourceMetadata = nil
        }
    }

    /// Returns public RFC 9728 metadata or the WorkOS authorization-server metadata compatibility proxy.
    func discoveryResponse(for request: HTTPRequest) async -> HTTPResponse? {
        guard request.method.uppercased() == "GET", let path = request.path else { return nil }

        if path == "/.well-known/oauth-protected-resource"
            || path.hasPrefix("/.well-known/oauth-protected-resource/")
        {
            guard let protectedResourceMetadata else { return nil }
            return .data(protectedResourceMetadata, headers: [
                HTTPHeaderName.contentType: "application/json",
                HTTPHeaderName.cacheControl: "public, max-age=300",
            ])
        }

        guard path == "/.well-known/oauth-authorization-server",
            let oauth = configuration.oauth
        else {
            return nil
        }
        let now = clock()
        if let authorizationServerMetadata,
            authorizationServerMetadataExpiresAt > now
        {
            return authorizationServerMetadataResponse(authorizationServerMetadata)
        }
        do {
            let response = try await fetcher(oauth.authorizationServerMetadataURL)
            let metadata = try JSONDecoder().decode(AuthorizationServerMetadata.self, from: response.data)
            guard metadata.issuer == oauth.issuer.absoluteString,
                (try JSONSerialization.jsonObject(with: response.data)) is [String: Any]
            else {
                throw KastanOAuthHTTPError.invalidResponse
            }
            authorizationServerMetadata = response.data
            authorizationServerMetadataExpiresAt = now.addingTimeInterval(
                min(max(response.cacheLifetime, 60), 3_600)
            )
            return authorizationServerMetadataResponse(response.data)
        } catch {
            return .error(statusCode: 502, .internalError("OAuth discovery is temporarily unavailable."))
        }
    }

    /// Accepts the configured static token, a validated OAuth access token, or both during migration.
    func validate(_ request: HTTPRequest) async -> HTTPResponse? {
        guard let authorization = request.header(HTTPHeaderName.authorization) else {
            return unauthorized(error: nil)
        }
        guard let token = parseBearerToken(authorization) else {
            return .error(statusCode: 400, .invalidRequest("Bad Request: malformed Bearer authorization"))
        }

        if configuration.authorizationMode != .oauth,
            let expectedToken = configuration.bearerToken,
            constantTimeEquals(token, expectedToken)
        {
            return nil
        }
        guard configuration.authorizationMode != .staticToken,
            let oauthVerifier
        else {
            return unauthorized(error: "invalid_token")
        }

        switch await oauthVerifier.validate(token) {
        case .valid:
            return nil
        case .insufficientScope(let requiredScopes, let errorDescription):
            return .error(
                statusCode: 403,
                .invalidRequest("Forbidden: Insufficient scope"),
                extraHeaders: [
                    HTTPHeaderName.wwwAuthenticate: bearerChallenge(
                        scopes: requiredScopes,
                        error: "insufficient_scope",
                        errorDescription: errorDescription
                    ),
                ]
            )
        case .invalidToken(let errorDescription):
            return unauthorized(error: "invalid_token", errorDescription: errorDescription)
        case .malformedRequest(let errorDescription):
            return .error(
                statusCode: 400,
                .invalidRequest("Bad Request: \(errorDescription ?? "malformed authorization request")")
            )
        }
    }

    private func unauthorized(error: String?, errorDescription: String? = nil) -> HTTPResponse {
        let challenge: String
        if configuration.authorizationMode == .staticToken {
            challenge = "Bearer realm=\"kastan-mcp\""
        } else {
            challenge = bearerChallenge(
                scopes: configuration.oauth?.requiredScopes,
                error: error,
                errorDescription: errorDescription
            )
        }
        return .error(
            statusCode: 401,
            .invalidRequest("Unauthorized"),
            extraHeaders: [HTTPHeaderName.wwwAuthenticate: challenge]
        )
    }

    private func authorizationServerMetadataResponse(_ data: Data) -> HTTPResponse {
        .data(data, headers: [
            HTTPHeaderName.contentType: "application/json",
            HTTPHeaderName.cacheControl: "public, max-age=300",
        ])
    }

    private func bearerChallenge(
        scopes: Set<String>?,
        error: String?,
        errorDescription: String?
    ) -> String {
        guard let oauth = configuration.oauth else {
            return "Bearer realm=\"kastan-mcp\""
        }
        var parameters = [
            "resource_metadata=\"\(escapeAuthParameter(oauth.protectedResourceMetadataURL.absoluteString))\"",
        ]
        if let scopes, !scopes.isEmpty {
            parameters.append("scope=\"\(escapeAuthParameter(scopes.sorted().joined(separator: " ")))\"")
        }
        if let error {
            parameters.append("error=\"\(escapeAuthParameter(error))\"")
        }
        if let errorDescription, !errorDescription.isEmpty {
            parameters.append("error_description=\"\(escapeAuthParameter(errorDescription))\"")
        }
        return "Bearer " + parameters.joined(separator: ", ")
    }

    private func parseBearerToken(_ header: String) -> String? {
        let parts = header.trimmingCharacters(in: .whitespacesAndNewlines)
            .split(maxSplits: 1, whereSeparator: \.isWhitespace)
        guard parts.count == 2,
            parts[0].caseInsensitiveCompare("Bearer") == .orderedSame
        else {
            return nil
        }
        let token = String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty, !token.contains(where: \.isWhitespace) else { return nil }
        return token
    }

    private func constantTimeEquals(_ supplied: String, _ expected: String) -> Bool {
        let suppliedBytes = Array(supplied.utf8)
        let expectedBytes = Array(expected.utf8)
        let count = max(suppliedBytes.count, expectedBytes.count)
        var difference = UInt64(suppliedBytes.count ^ expectedBytes.count)

        for index in 0..<count {
            let suppliedByte = index < suppliedBytes.count ? suppliedBytes[index] : 0
            let expectedByte = index < expectedBytes.count ? expectedBytes[index] : 0
            difference |= UInt64(suppliedByte ^ expectedByte)
        }
        return difference == 0
    }

    private func escapeAuthParameter(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}
