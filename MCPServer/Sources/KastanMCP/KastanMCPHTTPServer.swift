import Foundation
import Kastan
import MCP
@preconcurrency import NIOCore
@preconcurrency import NIOHTTP1
@preconcurrency import NIOPosix

/// Validates the temporary pre-shared Bearer credential used before Kaštan gains OAuth discovery.
struct KastanStaticBearerTokenValidator: HTTPRequestValidator {
    let expectedToken: String

    func validate(_ request: HTTPRequest, context: HTTPValidationContext) -> HTTPResponse? {
        guard let authorization = request.header(HTTPHeaderName.authorization) else {
            return unauthorized()
        }

        let parts = authorization.split(maxSplits: 1, whereSeparator: \Character.isWhitespace)
        guard parts.count == 2,
            parts[0].caseInsensitiveCompare("Bearer") == .orderedSame,
            constantTimeEquals(String(parts[1]), expectedToken)
        else {
            return unauthorized()
        }
        return nil
    }

    private func unauthorized() -> HTTPResponse {
        .error(
            statusCode: 401,
            .invalidRequest("Unauthorized"),
            extraHeaders: [HTTPHeaderName.wwwAuthenticate: "Bearer realm=\"kastan-mcp\""]
        )
    }

    /// Compares every byte without an early mismatch exit so token guesses do not leak useful prefixes.
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
}

/// Rejects browser-originated requests unless their exact origin was explicitly configured.
struct KastanAllowedOriginValidator: HTTPRequestValidator {
    let allowedOrigins: Set<String>

    func validate(_ request: HTTPRequest, context: HTTPValidationContext) -> HTTPResponse? {
        guard let origin = request.header(HTTPHeaderName.origin) else { return nil }
        let normalized = origin
            .lowercased()
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard allowedOrigins.contains(normalized) else {
            return .error(statusCode: 403, .invalidRequest("Forbidden: Origin not allowed"))
        }
        return nil
    }
}

/// Caps authenticated MCP traffic in a fixed one-minute window to protect the personal-use IDOS integration.
struct KastanFixedWindowRateLimiter: Sendable {
    let limit: Int
    private(set) var windowStart: Date
    private(set) var requestCount: Int

    init(limit: Int, windowStart: Date = Date(), requestCount: Int = 0) {
        self.limit = limit
        self.windowStart = windowStart
        self.requestCount = requestCount
    }

    /// Records one request or returns the number of seconds until the current window resets.
    mutating func retryAfter(now: Date = Date()) -> Int? {
        let elapsed = now.timeIntervalSince(windowStart)
        if elapsed >= 60 || elapsed < 0 {
            windowStart = now
            requestCount = 0
        }

        guard requestCount < limit else {
            return max(1, Int(ceil(60 - max(0, elapsed))))
        }
        requestCount += 1
        return nil
    }
}

/// Routes health checks and authenticated MCP requests independently of the concrete HTTP framework.
actor KastanMCPHTTPApplication {
    typealias ClientFactory = @Sendable () -> any IDOSClienting

    private let configuration: KastanMCPHTTPConfiguration
    private let securityValidation: StandardValidationPipeline
    private let protocolValidation: StandardValidationPipeline
    private let clientFactory: ClientFactory
    private var rateLimiter: KastanFixedWindowRateLimiter

    init(
        configuration: KastanMCPHTTPConfiguration,
        clientFactory: @escaping ClientFactory = { IDOSClient() }
    ) {
        self.configuration = configuration
        self.clientFactory = clientFactory
        self.rateLimiter = KastanFixedWindowRateLimiter(limit: configuration.requestsPerMinute)
        self.securityValidation = StandardValidationPipeline(validators: [
            KastanAllowedOriginValidator(allowedOrigins: configuration.allowedOrigins),
            KastanStaticBearerTokenValidator(expectedToken: configuration.bearerToken),
        ])
        self.protocolValidation = StandardValidationPipeline(validators: [
            AcceptHeaderValidator(mode: .jsonOnly),
            ContentTypeValidator(),
            ProtocolVersionValidator(),
        ])
    }

    func handleRequest(_ request: HTTPRequest) async -> HTTPResponse {
        if request.path == KastanMCPHTTPConfiguration.healthEndpoint,
            request.method.uppercased() == "GET"
        {
            return .data(
                Data("ok\n".utf8),
                headers: ["Content-Type": "text/plain; charset=utf-8"]
            )
        }

        guard request.path == KastanMCPHTTPConfiguration.endpoint else {
            return .error(statusCode: 404, .invalidRequest("Not Found"))
        }

        let validationContext = HTTPValidationContext(httpMethod: request.method.uppercased())
        if let rejection = securityValidation.validate(request, context: validationContext) {
            return rejection
        }
        if let retryAfter = rateLimiter.retryAfter() {
            return .error(
                statusCode: 429,
                .serverError(code: -32000, message: "Too many requests"),
                extraHeaders: ["Retry-After": String(retryAfter)]
            )
        }

        let transport = StatelessHTTPServerTransport(validationPipeline: protocolValidation)
        // Each HTTP POST is independent, so it receives a fresh lenient server instead of
        // carrying initialization state that could be lost when Cloud Run scales to zero.
        let server = await KastanMCPServer.makeServer(
            client: clientFactory(),
            configuration: .default
        )

        do {
            try await server.start(transport: transport)
            let response = await transport.handleRequest(request)
            await server.stop()
            return response
        } catch {
            await server.stop()
            return .error(
                statusCode: 500,
                .internalError("Failed to process the MCP request: \(error.localizedDescription)")
            )
        }
    }
}

/// Hosts Kaštan's framework-independent MCP application with a small SwiftNIO HTTP/1.1 adapter.
struct KastanMCPHTTPServer {
    let configuration: KastanMCPHTTPConfiguration

    func run() async throws {
        let application = KastanMCPHTTPApplication(configuration: configuration)
        let eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)

        do {
            let channel = try await ServerBootstrap(group: eventLoopGroup)
                .serverChannelOption(ChannelOptions.backlog, value: 128)
                .serverChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
                .childChannelInitializer { channel in
                    channel.pipeline.configureHTTPServerPipeline().flatMap {
                        channel.pipeline.addHandler(KastanMCPHTTPHandler(
                            application: application,
                            maximumRequestBodyBytes: KastanMCPHTTPConfiguration.maximumRequestBodyBytes
                        ))
                    }
                }
                .childChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
                .bind(host: configuration.host, port: configuration.port)
                .get()

            FileHandle.standardError.write(Data(
                "kastan-mcp: listening on http://\(configuration.host):\(configuration.port)\(KastanMCPHTTPConfiguration.endpoint)\n".utf8
            ))
            try await channel.closeFuture.get()
            try await eventLoopGroup.shutdownGracefully()
        } catch {
            try? await eventLoopGroup.shutdownGracefully()
            throw error
        }
    }
}

/// Converts one bounded HTTP request at a time between SwiftNIO and the MCP SDK transport types.
private final class KastanMCPHTTPHandler: ChannelInboundHandler, @unchecked Sendable {
    typealias InboundIn = HTTPServerRequestPart
    typealias OutboundOut = HTTPServerResponsePart

    private struct RequestState {
        var head: HTTPRequestHead
        var body: ByteBuffer
        var isTooLarge: Bool
    }

    private let application: KastanMCPHTTPApplication
    private let maximumRequestBodyBytes: Int
    private var requestState: RequestState?

    init(application: KastanMCPHTTPApplication, maximumRequestBodyBytes: Int) {
        self.application = application
        self.maximumRequestBodyBytes = maximumRequestBodyBytes
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        switch unwrapInboundIn(data) {
        case .head(let head):
            requestState = RequestState(
                head: head,
                body: context.channel.allocator.buffer(capacity: 0),
                isTooLarge: false
            )
        case .body(var buffer):
            guard var state = requestState else { return }
            if state.body.readableBytes + buffer.readableBytes > maximumRequestBodyBytes {
                state.isTooLarge = true
            } else if !state.isTooLarge {
                state.body.writeBuffer(&buffer)
            }
            requestState = state
        case .end:
            guard let state = requestState else { return }
            requestState = nil

            nonisolated(unsafe) let channelContext = context
            Task { @MainActor in
                await self.handleRequest(state, context: channelContext)
            }
        }
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        FileHandle.standardError.write(Data("kastan-mcp: HTTP connection error: \(error.localizedDescription)\n".utf8))
        context.close(promise: nil)
    }

    private func handleRequest(
        _ state: RequestState,
        context: ChannelHandlerContext
    ) async {
        if state.isTooLarge {
            await writeResponse(
                .error(statusCode: 413, .invalidRequest("Request body exceeds 1 MiB")),
                version: state.head.version,
                context: context
            )
            return
        }

        let request = makeRequest(from: state)
        let response = await application.handleRequest(request)
        await writeResponse(response, version: state.head.version, context: context)
    }

    private func makeRequest(from state: RequestState) -> HTTPRequest {
        var headers: [String: String] = [:]
        for (name, value) in state.head.headers {
            if let existing = headers[name] {
                headers[name] = existing + ", " + value
            } else {
                headers[name] = value
            }
        }

        let body: Data?
        if state.body.readableBytes > 0,
            let bytes = state.body.getBytes(at: 0, length: state.body.readableBytes)
        {
            body = Data(bytes)
        } else {
            body = nil
        }

        let path = String(state.head.uri.split(separator: "?").first ?? Substring(state.head.uri))
        return HTTPRequest(
            method: state.head.method.rawValue,
            headers: headers,
            body: body,
            path: path
        )
    }

    private func writeResponse(
        _ response: HTTPResponse,
        version: HTTPVersion,
        context: ChannelHandlerContext
    ) async {
        nonisolated(unsafe) let channelContext = context
        let eventLoop = channelContext.eventLoop

        switch response {
        case .stream(let stream, let headers):
            eventLoop.execute {
                var head = HTTPResponseHead(
                    version: version,
                    status: HTTPResponseStatus(statusCode: response.statusCode)
                )
                for (name, value) in headers {
                    head.headers.add(name: name, value: value)
                }
                head.headers.replaceOrAdd(name: "Transfer-Encoding", value: "chunked")
                channelContext.write(self.wrapOutboundOut(.head(head)), promise: nil)
                channelContext.flush()
            }

            do {
                for try await chunk in stream {
                    eventLoop.execute {
                        var buffer = channelContext.channel.allocator.buffer(capacity: chunk.count)
                        buffer.writeBytes(chunk)
                        channelContext.writeAndFlush(
                            self.wrapOutboundOut(.body(.byteBuffer(buffer))),
                            promise: nil
                        )
                    }
                }
            } catch {
                // Closing the response below is sufficient after an interrupted optional SSE stream.
            }
            eventLoop.execute {
                channelContext.writeAndFlush(self.wrapOutboundOut(.end(nil)), promise: nil)
            }

        default:
            let body = response.bodyData
            eventLoop.execute {
                var head = HTTPResponseHead(
                    version: version,
                    status: HTTPResponseStatus(statusCode: response.statusCode)
                )
                for (name, value) in response.headers {
                    head.headers.add(name: name, value: value)
                }
                head.headers.replaceOrAdd(name: "Content-Length", value: String(body?.count ?? 0))
                channelContext.write(self.wrapOutboundOut(.head(head)), promise: nil)

                if let body {
                    var buffer = channelContext.channel.allocator.buffer(capacity: body.count)
                    buffer.writeBytes(body)
                    channelContext.write(self.wrapOutboundOut(.body(.byteBuffer(buffer))), promise: nil)
                }
                channelContext.writeAndFlush(self.wrapOutboundOut(.end(nil)), promise: nil)
            }
        }
    }
}
