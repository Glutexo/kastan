import Foundation
#if canImport(CoreFoundation)
import CoreFoundation
#endif
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// A language variant exposed by IDOS for platform-supplied names, notes, and messages.
public enum IDOSLanguage: String, Codable, Equatable, Sendable {
    case english = "en"
    case czech = "cs"

    /// Builds an IDOS endpoint path; Czech is the site's unprefixed default language.
    func path(timetable: IDOSTimetable, endpoint: String) -> String {
        let languagePrefix = self == .english ? "/en" : ""
        return "\(languagePrefix)/\(timetable.slug)/\(endpoint)"
    }
}

/// Selects the chronological edge extended by an IDOS result-page request.
public enum IDOSPageDirection: String, Codable, Equatable, Hashable, Sendable {
    case earlier
    case later
}

/// Carries one connection batch together with the opaque IDOS continuation state for both edges.
public struct IDOSConnectionPage: Sendable {
    public let connections: [IDOSConnection]
    public let canLoadEarlier: Bool
    public let canLoadLater: Bool
    let pagingContext: IDOSConnectionPagingContext?

    public init(
        connections: [IDOSConnection],
        canLoadEarlier: Bool = false,
        canLoadLater: Bool = false
    ) {
        self.connections = connections
        self.canLoadEarlier = canLoadEarlier
        self.canLoadLater = canLoadLater
        pagingContext = nil
    }

    init(connections: [IDOSConnection], pagingContext: IDOSConnectionPagingContext?) {
        self.connections = connections
        canLoadEarlier = pagingContext?.allowPrevious ?? false
        canLoadLater = pagingContext?.allowNext ?? false
        self.pagingContext = pagingContext
    }
}

/// Carries one station-board batch together with the search window used to extend either edge.
public struct IDOSDeparturePage: Sendable {
    public let departures: [IDOSDeparture]
    public let canLoadEarlier: Bool
    public let canLoadLater: Bool
    let pagingContext: IDOSDeparturePagingContext?

    public init(
        departures: [IDOSDeparture],
        canLoadEarlier: Bool = false,
        canLoadLater: Bool = false
    ) {
        self.departures = departures
        self.canLoadEarlier = canLoadEarlier
        self.canLoadLater = canLoadLater
        pagingContext = nil
    }

    init(departures: [IDOSDeparture], pagingContext: IDOSDeparturePagingContext?) {
        self.departures = departures
        canLoadEarlier = pagingContext != nil
        canLoadLater = pagingContext != nil
        self.pagingContext = pagingContext
    }
}

public protocol IDOSClienting: Sendable {
    func suggest(prefix: String, limit: Int, timetable: IDOSTimetable) async throws -> [IDOSSuggestion]
    func searchStations(prefix: String, limit: Int, timetable: IDOSTimetable) async throws -> [IDOSSuggestion]
    func searchStationTimetableLines(
        prefix: String,
        limit: Int,
        timetable: IDOSTimetable
    ) async throws -> [IDOSSuggestion]
    func searchStationTimetableLines(
        prefix: String,
        limit: Int,
        timetable: IDOSTimetable,
        municipality: IDOSStationTimetableMunicipality?
    ) async throws -> [IDOSSuggestion]
    func searchStationTimetableStops(
        prefix: String,
        line: String,
        limit: Int,
        timetable: IDOSTimetable
    ) async throws -> [IDOSSuggestion]
    func searchStationTimetableStops(
        prefix: String,
        line: String,
        limit: Int,
        timetable: IDOSTimetable,
        municipality: IDOSStationTimetableMunicipality?
    ) async throws -> [IDOSSuggestion]
    func findStationTimetable(
        request: IDOSStationTimetableRequest,
        language: IDOSLanguage
    ) async throws -> IDOSStationTimetable
    /// Loads the inclusive validity interval published for one IDOS timetable.
    func timetableValidity(
        for timetable: IDOSTimetable,
        language: IDOSLanguage
    ) async throws -> IDOSTimetableValidity
    func findConnections(request: IDOSConnectionRequest) async throws -> [IDOSConnection]
    /// Starts a connection search while retaining IDOS's continuation state for both chronological edges.
    func findConnectionsPage(request: IDOSConnectionRequest) async throws -> IDOSConnectionPage
    /// Starts a connection search with platform-supplied result text in the selected language.
    func findConnectionsPage(
        request: IDOSConnectionRequest,
        language: IDOSLanguage
    ) async throws -> IDOSConnectionPage
    /// Extends an existing connection search through IDOS's native earlier/later paging endpoint.
    func findConnectionsPage(
        from page: IDOSConnectionPage,
        direction: IDOSPageDirection
    ) async throws -> IDOSConnectionPage
    /// Loads IDOS's localized message and attachment names before a connection email is sent.
    func connectionEmailDraft(
        for connection: IDOSConnection,
        timetable: IDOSTimetable,
        language: IDOSLanguage
    ) async throws -> IDOSConnectionEmailDraft
    /// Sends one connection as IDOS-generated PDF and calendar attachments to confirmed recipients.
    func sendConnectionByEmail(
        _ connection: IDOSConnection,
        to recipient: String,
        message: String,
        timetable: IDOSTimetable,
        language: IDOSLanguage
    ) async throws
    /// Loads IDOS's native calendar export using the historical English default.
    func connectionCalendar(for connection: IDOSConnection, timetable: IDOSTimetable) async throws -> String
    /// Loads IDOS's native calendar export in the selected language.
    func connectionCalendar(
        for connection: IDOSConnection,
        timetable: IDOSTimetable,
        language: IDOSLanguage
    ) async throws -> String
    /// Loads the IDOS calendar export represented by a dated service's permanent result link.
    func serviceCalendar(for service: IDOSServiceDetail) async throws -> String
    /// Loads a dated service's IDOS calendar export in the selected language.
    func serviceCalendar(for service: IDOSServiceDetail, language: IDOSLanguage) async throws -> String
    /// Downloads IDOS's PDF represented by a dated service's permanent result link.
    func servicePDF(for service: IDOSServiceDetail, language: IDOSLanguage) async throws -> Data
    /// Downloads IDOS's printable representation of one connection in the selected language.
    func connectionPDF(
        for connection: IDOSConnection,
        timetable: IDOSTimetable,
        language: IDOSLanguage
    ) async throws -> Data
    func findDepartures(request: IDOSDeparturesRequest) async throws -> [IDOSDeparture]
    /// Starts a station-board search while retaining its chronological search window.
    func findDeparturesPage(request: IDOSDeparturesRequest) async throws -> IDOSDeparturePage
    /// Starts a station-board search with platform-supplied result text in the selected language.
    func findDeparturesPage(
        request: IDOSDeparturesRequest,
        language: IDOSLanguage
    ) async throws -> IDOSDeparturePage
    /// Extends a station board with an adjacent IDOS time window.
    func findDeparturesPage(
        from page: IDOSDeparturePage,
        direction: IDOSPageDirection
    ) async throws -> IDOSDeparturePage
    func serviceDetail(id: String, timetable: IDOSTimetable) async throws -> IDOSServiceDetail
    /// Loads a complete route with platform-supplied text in the selected language.
    func serviceDetail(
        id: String,
        timetable: IDOSTimetable,
        language: IDOSLanguage
    ) async throws -> IDOSServiceDetail
    /// Loads IDOS's exact per-day operating states for one dated service.
    func serviceDateLimits(
        for service: IDOSServiceDetail,
        language: IDOSLanguage
    ) async throws -> IDOSServiceDateLimits
}

public extension IDOSClienting {
    /// Adapts clients without paging support to a single non-extendable connection page.
    func findConnectionsPage(request: IDOSConnectionRequest) async throws -> IDOSConnectionPage {
        IDOSConnectionPage(connections: try await findConnections(request: request))
    }

    /// Preserves compatibility for custom clients that do not provide localized connection pages yet.
    func findConnectionsPage(
        request: IDOSConnectionRequest,
        language: IDOSLanguage
    ) async throws -> IDOSConnectionPage {
        try await findConnectionsPage(request: request)
    }

    /// Returns no continuation for clients that only implement one-shot connection searches.
    func findConnectionsPage(
        from page: IDOSConnectionPage,
        direction: IDOSPageDirection
    ) async throws -> IDOSConnectionPage {
        IDOSConnectionPage(connections: [])
    }

    /// Preserves compatibility for custom clients that do not provide connection email delivery yet.
    func connectionEmailDraft(
        for connection: IDOSConnection,
        timetable: IDOSTimetable,
        language: IDOSLanguage
    ) async throws -> IDOSConnectionEmailDraft {
        throw IDOSError.emailUnavailable
    }

    /// Preserves compatibility for custom clients that do not provide connection email delivery yet.
    func sendConnectionByEmail(
        _ connection: IDOSConnection,
        to recipient: String,
        message: String,
        timetable: IDOSTimetable,
        language: IDOSLanguage
    ) async throws {
        throw IDOSError.emailUnavailable
    }

    /// Adapts clients without paging support to the first twenty station-board entries.
    func findDeparturesPage(request: IDOSDeparturesRequest) async throws -> IDOSDeparturePage {
        let departures = try await findDepartures(request: request)
        return IDOSDeparturePage(departures: Array(departures.prefix(20)))
    }

    /// Preserves compatibility for custom clients that do not provide localized station-board pages yet.
    func findDeparturesPage(
        request: IDOSDeparturesRequest,
        language: IDOSLanguage
    ) async throws -> IDOSDeparturePage {
        try await findDeparturesPage(request: request)
    }

    /// Returns no continuation for clients that only implement one-shot station-board searches.
    func findDeparturesPage(
        from page: IDOSDeparturePage,
        direction: IDOSPageDirection
    ) async throws -> IDOSDeparturePage {
        IDOSDeparturePage(departures: [])
    }

    /// Preserves compatibility for custom clients that do not provide station-timetable searches yet.
    func searchStationTimetableLines(
        prefix: String,
        limit: Int,
        timetable: IDOSTimetable
    ) async throws -> [IDOSSuggestion] {
        throw IDOSError.stationTimetableUnavailable
    }

    /// Lets existing custom clients ignore a municipality until they adopt the municipality-aware overload.
    func searchStationTimetableLines(
        prefix: String,
        limit: Int,
        timetable: IDOSTimetable,
        municipality: IDOSStationTimetableMunicipality?
    ) async throws -> [IDOSSuggestion] {
        try await searchStationTimetableLines(prefix: prefix, limit: limit, timetable: timetable)
    }

    /// Preserves compatibility for custom clients that do not provide station-timetable searches yet.
    func searchStationTimetableStops(
        prefix: String,
        line: String,
        limit: Int,
        timetable: IDOSTimetable
    ) async throws -> [IDOSSuggestion] {
        throw IDOSError.stationTimetableUnavailable
    }

    /// Lets existing custom clients ignore a municipality until they adopt the municipality-aware overload.
    func searchStationTimetableStops(
        prefix: String,
        line: String,
        limit: Int,
        timetable: IDOSTimetable,
        municipality: IDOSStationTimetableMunicipality?
    ) async throws -> [IDOSSuggestion] {
        try await searchStationTimetableStops(
            prefix: prefix,
            line: line,
            limit: limit,
            timetable: timetable
        )
    }

    /// Preserves compatibility for custom clients that do not provide station-timetable searches yet.
    func findStationTimetable(
        request: IDOSStationTimetableRequest,
        language: IDOSLanguage
    ) async throws -> IDOSStationTimetable {
        throw IDOSError.stationTimetableUnavailable
    }

    /// Preserves compatibility for custom clients that do not expose timetable validity yet.
    func timetableValidity(
        for timetable: IDOSTimetable,
        language: IDOSLanguage
    ) async throws -> IDOSTimetableValidity {
        throw IDOSError.invalidResponse
    }

    /// Preserves compatibility for custom clients whose calendar export is not language-aware yet.
    func connectionCalendar(
        for connection: IDOSConnection,
        timetable: IDOSTimetable,
        language: IDOSLanguage
    ) async throws -> String {
        try await connectionCalendar(for: connection, timetable: timetable)
    }

    /// Preserves compatibility for custom clients that do not provide dated-service calendar exports yet.
    func serviceCalendar(for service: IDOSServiceDetail) async throws -> String {
        throw IDOSError.calendarUnavailable
    }

    /// Preserves compatibility for custom clients whose dated-service calendar export is not language-aware yet.
    func serviceCalendar(for service: IDOSServiceDetail, language: IDOSLanguage) async throws -> String {
        try await serviceCalendar(for: service)
    }

    /// Preserves compatibility for custom clients that do not provide dated-service PDF exports yet.
    func servicePDF(for service: IDOSServiceDetail, language: IDOSLanguage) async throws -> Data {
        throw IDOSError.pdfUnavailable
    }

    /// Preserves compatibility for custom clients that do not provide IDOS PDF exports yet.
    func connectionPDF(
        for connection: IDOSConnection,
        timetable: IDOSTimetable,
        language: IDOSLanguage
    ) async throws -> Data {
        throw IDOSError.pdfUnavailable
    }

    /// Loads a service whose self-contained ID carries its own timetable context.
    func serviceDetail(id: String) async throws -> IDOSServiceDetail {
        try await serviceDetail(id: id, timetable: .defaultTimetable)
    }

    /// Loads a self-contained service ID using the selected language for text supplied by IDOS.
    func serviceDetail(id: String, language: IDOSLanguage) async throws -> IDOSServiceDetail {
        try await serviceDetail(id: id, timetable: .defaultTimetable, language: language)
    }

    /// Preserves compatibility for custom clients that have not added language-aware service details yet.
    func serviceDetail(
        id: String,
        timetable: IDOSTimetable,
        language: IDOSLanguage
    ) async throws -> IDOSServiceDetail {
        try await serviceDetail(id: id, timetable: timetable)
    }

    /// Preserves compatibility for custom clients that do not expose IDOS date-limit data yet.
    func serviceDateLimits(
        for service: IDOSServiceDetail,
        language: IDOSLanguage
    ) async throws -> IDOSServiceDateLimits {
        throw IDOSError.dateLimitsUnavailable
    }
}

public struct IDOSClient: IDOSClienting {
    public var baseURL: URL

    public init(baseURL: URL = URL(string: "https://idos.cz")!) {
        self.baseURL = baseURL
    }

    public func suggest(prefix: String, limit: Int = 8, timetable: IDOSTimetable = .defaultTimetable) async throws -> [IDOSSuggestion] {
        try await searchTimetableObjects(prefix: prefix, limit: limit, timetable: timetable, onlyStation: false)
    }

    public func searchStations(prefix: String, limit: Int = 8, timetable: IDOSTimetable = .defaultTimetable) async throws -> [IDOSSuggestion] {
        try await searchTimetableObjects(prefix: prefix, limit: limit, timetable: timetable, onlyStation: true)
    }

    /// Suggests MHD or integrated-transport lines and includes each available terminal pair.
    public func searchStationTimetableLines(
        prefix: String,
        limit: Int = 8,
        timetable: IDOSTimetable
    ) async throws -> [IDOSSuggestion] {
        try await searchStationTimetableLines(
            prefix: prefix,
            limit: limit,
            timetable: timetable,
            municipality: IDOSStationTimetableMunicipality.default(for: timetable)
        )
    }

    /// Suggests line directions within the municipality selected by a multi-municipality IDOS catalog.
    public func searchStationTimetableLines(
        prefix: String,
        limit: Int = 8,
        timetable: IDOSTimetable,
        municipality: IDOSStationTimetableMunicipality?
    ) async throws -> [IDOSSuggestion] {
        try await searchStationTimetableObjects(
            endpoint: "ZJRLines",
            prefix: prefix,
            line: nil,
            limit: limit,
            timetable: timetable,
            municipality: municipality,
            onlyStation: false
        )
    }

    /// Suggests stops served by one station-timetable line.
    public func searchStationTimetableStops(
        prefix: String,
        line: String,
        limit: Int = 8,
        timetable: IDOSTimetable
    ) async throws -> [IDOSSuggestion] {
        try await searchStationTimetableStops(
            prefix: prefix,
            line: line,
            limit: limit,
            timetable: timetable,
            municipality: IDOSStationTimetableMunicipality.default(for: timetable)
        )
    }

    /// Suggests line stops within the municipality selected by a multi-municipality IDOS catalog.
    public func searchStationTimetableStops(
        prefix: String,
        line: String,
        limit: Int = 8,
        timetable: IDOSTimetable,
        municipality: IDOSStationTimetableMunicipality?
    ) async throws -> [IDOSSuggestion] {
        try await searchStationTimetableObjects(
            endpoint: "ZJRStationsOnLine",
            prefix: prefix,
            line: line,
            limit: limit,
            timetable: timetable,
            municipality: municipality,
            onlyStation: true
        )
    }

    private func searchTimetableObjects(
        prefix: String,
        limit: Int,
        timetable: IDOSTimetable,
        onlyStation: Bool
    ) async throws -> [IDOSSuggestion] {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
        components.path = "/en/\(timetable.slug)/Ajax/SearchTimetableObjects/"
        components.queryItems = [
            URLQueryItem(name: "count", value: String(limit)),
            URLQueryItem(name: "prefixText", value: prefix),
            URLQueryItem(name: "positionAccuracy", value: "0"),
            URLQueryItem(name: "searchByPosition", value: "false"),
            URLQueryItem(name: "onlyStation", value: onlyStation ? "true" : "false"),
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "bindTtIndex", value: ""),
            URLQueryItem(name: "callback", value: "idosCallback"),
        ]

        let data = try await data(from: components.requiredURL)
        return try decodedSuggestions(from: data)
    }

    private func searchStationTimetableObjects(
        endpoint: String,
        prefix: String,
        line: String?,
        limit: Int,
        timetable: IDOSTimetable,
        municipality: IDOSStationTimetableMunicipality?,
        onlyStation: Bool
    ) async throws -> [IDOSSuggestion] {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
        components.path = "/en/\(timetable.slug)/Ajax/\(endpoint)/"
        var queryItems = Self.stationTimetableSuggestionQueryItems(
            prefix: prefix,
            limit: limit,
            municipality: municipality,
            onlyStation: onlyStation
        )
        if let line, !line.isEmpty {
            queryItems.append(URLQueryItem(name: "line", value: line))
        }
        components.queryItems = queryItems

        let data = try await data(from: components.requiredURL)
        return try decodedSuggestions(from: data)
    }

    /// Builds the municipality-aware query shared by both Station Timetable suggestion endpoints.
    static func stationTimetableSuggestionQueryItems(
        prefix: String,
        limit: Int,
        municipality: IDOSStationTimetableMunicipality?,
        onlyStation: Bool
    ) -> [URLQueryItem] {
        [
            URLQueryItem(name: "count", value: String(limit)),
            URLQueryItem(name: "prefixText", value: prefix),
            URLQueryItem(name: "positionAccuracy", value: "0"),
            URLQueryItem(name: "searchByPosition", value: "false"),
            URLQueryItem(name: "onlyStation", value: onlyStation ? "true" : "false"),
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "bindTtIndex", value: String(municipality?.timetableIndex ?? 0)),
            URLQueryItem(name: "callback", value: "idosCallback"),
        ]
    }

    /// Decodes IDOS suggestions while applying the same readable symbols used by every other result.
    private func decodedSuggestions(from data: Data) throws -> [IDOSSuggestion] {
        let json = try IDOSJSONP.decodePayload(from: data)
        return try JSONDecoder().decode([IDOSSuggestion].self, from: json)
            .map(IDOSPresentationText.normalize)
    }

    /// Loads one IDOS station timetable for an MHD or integrated-transport line and direction.
    public func findStationTimetable(
        request: IDOSStationTimetableRequest,
        language: IDOSLanguage = .english
    ) async throws -> IDOSStationTimetable {
        guard request.isComplete else {
            throw IDOSError.stationTimetableUnavailable
        }

        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
        components.path = language.path(timetable: request.timetable, endpoint: "zjr/")
        components.queryItems = request.queryItems
        let resultURL = try components.requiredURL
        let data = try await data(from: resultURL)
        guard let html = String(data: data, encoding: .utf8),
              let result = IDOSStationTimetableParser.parse(
                  html: html,
                  request: request,
                  shareURL: resultURL.absoluteString
              )
        else {
            throw IDOSError.stationTimetableUnavailable
        }
        return result
    }

    /// Loads the exact inclusive date range embedded in the selected IDOS search form.
    public func timetableValidity(
        for timetable: IDOSTimetable,
        language: IDOSLanguage = .english
    ) async throws -> IDOSTimetableValidity {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
        components.path = language.path(timetable: timetable, endpoint: "spojeni/")
        let data = try await data(from: components.requiredURL)
        guard let html = String(data: data, encoding: .utf8),
              let validity = IDOSTimetableValidityParser.parse(html: html)
        else {
            throw IDOSError.invalidResponse
        }
        return validity
    }

    public func findConnections(request: IDOSConnectionRequest) async throws -> [IDOSConnection] {
        try await findConnectionsPage(request: request).connections
    }

    public func findConnectionsPage(request: IDOSConnectionRequest) async throws -> IDOSConnectionPage {
        try await findConnectionsPage(request: request, language: .english)
    }

    public func findConnectionsPage(
        request: IDOSConnectionRequest,
        language: IDOSLanguage
    ) async throws -> IDOSConnectionPage {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
        components.path = language.path(timetable: request.timetable, endpoint: "spojeni/")

        var urlRequest = URLRequest(url: try components.requiredURL)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        urlRequest.httpBody = Self.formURLEncodedData(request.formItems)

        let data = try await data(for: urlRequest)
        guard let html = String(data: data, encoding: .utf8) else {
            throw IDOSError.invalidResponse
        }

        var connections = IDOSConnectionParser.parse(html: html, timetable: request.timetable)
        guard var paging = IDOSConnectionParser.pagingContext(html: html) else {
            return IDOSConnectionPage(connections: connections)
        }
        paging.timetable = request.timetable
        paging.language = language
        paging.listedIDs = connections.compactMap { Int($0.id) }

        if let limit = request.resultLimit {
            while connections.count < limit, paging.allowNext {
                let page = try await connectionPage(paging: paging, direction: .later)

                guard !page.connections.isEmpty, let nextPaging = page.pagingContext else {
                    break
                }

                connections.append(contentsOf: page.connections)
                paging = nextPaging
            }

            connections = Array(connections.prefix(limit))
            paging.listedIDs = connections.compactMap { Int($0.id) }
        }

        return IDOSConnectionPage(connections: connections, pagingContext: paging)
    }

    public func findConnectionsPage(
        from page: IDOSConnectionPage,
        direction: IDOSPageDirection
    ) async throws -> IDOSConnectionPage {
        guard let paging = page.pagingContext else {
            return IDOSConnectionPage(connections: [])
        }
        return try await connectionPage(paging: paging, direction: direction)
    }

    private func connectionPage(
        paging: IDOSConnectionPagingContext,
        direction: IDOSPageDirection
    ) async throws -> IDOSConnectionPage {
        let isPrevious = direction == .earlier
        guard let connectionID = isPrevious ? paging.listedIDs.first : paging.listedIDs.last else {
            return IDOSConnectionPage(connections: [])
        }

        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
        components.path = paging.language.path(
            timetable: paging.timetable,
            endpoint: "Ajax/ConnPaging"
        )
        components.queryItems = [URLQueryItem(name: "callback", value: "idosCallback")]

        var urlRequest = URLRequest(url: try components.requiredURL)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/x-www-form-urlencoded; charset=UTF-8", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
        urlRequest.setValue(
            "\(baseURL.absoluteString)\(paging.language.path(timetable: paging.timetable, endpoint: "spojeni/"))",
            forHTTPHeaderField: "Referer"
        )

        var items = paging.listedIDs.map { URLQueryItem(name: "listedIds[]", value: String($0)) }
        items.append(contentsOf: [
            URLQueryItem(name: "isPrev", value: isPrevious ? "true" : "false"),
            URLQueryItem(name: "handle", value: String(paging.handle)),
            URLQueryItem(name: "searchDate", value: paging.searchDate),
            URLQueryItem(name: "connId", value: String(connectionID)),
            URLQueryItem(name: "arrivalThere", value: paging.arrivalThere),
            URLQueryItem(name: "from", value: paging.from),
            URLQueryItem(name: "to", value: paging.to),
        ])
        urlRequest.httpBody = Self.formURLEncodedData(items)

        let data = try await data(for: urlRequest)
        let json = try IDOSJSONP.decodePayload(from: data)
        guard let object = try JSONSerialization.jsonObject(with: json) as? [String: Any] else {
            throw IDOSError.invalidResponse
        }

        if let errorMessage = object["errorMessage"] as? String, !errorMessage.isEmpty {
            throw IDOSError.invalidResponse
        }

        let html = (object["newConnections"] as? [String] ?? []).joined(separator: "\n")
        guard let searchItem = try JSONSerialization.jsonObject(with: paging.searchItem) as? [String: Any] else {
            throw IDOSError.invalidResponse
        }
        let result: [String: Any] = [
            "handle": paging.handle,
            "connData": object["connData"] as? [[String: Any]] ?? [],
            "searchItem": searchItem,
        ]
        let parsed = IDOSConnectionParser.parse(html: html, result: result, timetable: paging.timetable)
        let knownIDs = Set(paging.listedIDs.map(String.init))
        let connections = parsed.filter { !knownIDs.contains($0.id) }

        var updatedPaging = paging
        updatedPaging.allowPrevious = object["allowPrev"] as? Bool ?? paging.allowPrevious
        updatedPaging.allowNext = object["allowNext"] as? Bool ?? paging.allowNext
        let newIDs = connections.compactMap { Int($0.id) }
        let combinedIDs = isPrevious
            ? newIDs + paging.listedIDs
            : paging.listedIDs + newIDs
        var uniqueIDs = Set<Int>()
        updatedPaging.listedIDs = combinedIDs.filter { uniqueIDs.insert($0).inserted }
        if updatedPaging.listedIDs.count >= 50 {
            updatedPaging.allowPrevious = false
            updatedPaging.allowNext = false
        }

        return IDOSConnectionPage(connections: connections, pagingContext: updatedPaging)
    }

    /// Loads the wording and attachment names IDOS will use for one connection email.
    public func connectionEmailDraft(
        for connection: IDOSConnection,
        timetable: IDOSTimetable = .defaultTimetable,
        language: IDOSLanguage = .english
    ) async throws -> IDOSConnectionEmailDraft {
        let body = try connectionEmailFormData(
            for: connection,
            rootName: "pdfModel"
        )
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
        components.path = language.path(timetable: timetable, endpoint: "Ajax/GetShareLabels")

        var urlRequest = URLRequest(url: try components.requiredURL)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = body

        let data = try await data(for: urlRequest)
        return try Self.connectionEmailDraft(from: data)
    }

    /// Validates and maps the small JSON document returned while IDOS prepares email attachments.
    static func connectionEmailDraft(from data: Data) throws -> IDOSConnectionEmailDraft {
        guard let response = try? JSONDecoder().decode(IDOSShareLabelsResponse.self, from: data),
              response.error?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false,
              let pdfFileName = response.filename?.trimmingCharacters(in: .whitespacesAndNewlines),
              !pdfFileName.isEmpty
        else {
            throw IDOSError.emailUnavailable
        }

        let calendarFileName = response.filename2?.trimmingCharacters(in: .whitespacesAndNewlines)
        return IDOSConnectionEmailDraft(
            message: response.message ?? "",
            description: response.description ?? "",
            attachmentFileNames: [pdfFileName, calendarFileName]
                .compactMap { $0 }
                .filter { !$0.isEmpty }
        )
    }

    /// Asks IDOS to deliver one connection as the same PDF and calendar attachments as its website.
    public func sendConnectionByEmail(
        _ connection: IDOSConnection,
        to recipient: String,
        message: String,
        timetable: IDOSTimetable = .defaultTimetable,
        language: IDOSLanguage = .english
    ) async throws {
        let recipient = recipient.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !recipient.isEmpty else {
            throw IDOSError.emailSendingFailed("Enter an email address.")
        }

        let body = try connectionEmailFormData(
            for: connection,
            rootName: "model",
            additionalValues: [
                "emailAdress": recipient,
                "message": message,
            ]
        )
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
        components.path = language.path(timetable: timetable, endpoint: "Ajax/SendPdfByEmail")

        var urlRequest = URLRequest(url: try components.requiredURL)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = body

        let data = try await data(for: urlRequest)
        try Self.validateConnectionEmailDelivery(from: data)
    }

    /// Converts IDOS's delivery result into either success or a user-facing delivery error.
    static func validateConnectionEmailDelivery(from data: Data) throws {
        guard let response = try? JSONDecoder().decode(IDOSEmailSendResponse.self, from: data),
              let errors = response.errors
        else {
            throw IDOSError.invalidResponse
        }
        guard errors.isEmpty else {
            throw IDOSError.emailSendingFailed(errors.joined(separator: " "))
        }
    }

    /// Reuses the opaque sharing model parsed from the selected result without exposing IDOS internals publicly.
    private func connectionEmailFormData(
        for connection: IDOSConnection,
        rootName: String,
        additionalValues: [String: String] = [:]
    ) throws -> Data {
        guard let model = connection.pdfModel,
              let source = model.data(using: .utf8),
              var object = try? JSONSerialization.jsonObject(with: source) as? [String: Any]
        else {
            throw IDOSError.emailUnavailable
        }

        for (key, value) in additionalValues {
            object[key] = value
        }
        guard let data = IDOSFormEncoding.nestedData(rootName: rootName, value: object) else {
            throw IDOSError.emailUnavailable
        }
        return data
    }

    /// Loads IDOS's native calendar export using the historical English default.
    public func connectionCalendar(
        for connection: IDOSConnection,
        timetable: IDOSTimetable = .defaultTimetable
    ) async throws -> String {
        try await connectionCalendar(for: connection, timetable: timetable, language: .english)
    }

    /// Loads IDOS's native calendar export with human-readable text in the selected language.
    public func connectionCalendar(
        for connection: IDOSConnection,
        timetable: IDOSTimetable = .defaultTimetable,
        language: IDOSLanguage
    ) async throws -> String {
        guard let model = connection.calendarModel, !model.isEmpty else {
            throw IDOSError.calendarUnavailable
        }

        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
        components.path = language.path(timetable: timetable, endpoint: "spojeni/kalendar")

        var urlRequest = URLRequest(url: try components.requiredURL)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        urlRequest.httpBody = Self.formURLEncodedData([URLQueryItem(name: "model", value: model)])

        let data = try await data(for: urlRequest)
        guard let calendar = String(data: data, encoding: .utf8),
              calendar.contains("BEGIN:VCALENDAR")
        else {
            throw IDOSError.invalidResponse
        }

        return calendar
    }

    /// Resolves a dated service's permanent result using the historical English calendar default.
    public func serviceCalendar(for service: IDOSServiceDetail) async throws -> String {
        try await serviceCalendar(for: service, language: .english)
    }

    /// Resolves a dated service's permanent result and returns IDOS's calendar export in the selected language.
    public func serviceCalendar(
        for service: IDOSServiceDetail,
        language: IDOSLanguage
    ) async throws -> String {
        let connection = try await resultConnection(
            for: service,
            unavailableError: .calendarUnavailable
        )
        return try await connectionCalendar(
            for: connection,
            timetable: service.timetable,
            language: language
        )
    }

    /// Resolves a dated service's permanent result and returns the native PDF generated by IDOS.
    public func servicePDF(
        for service: IDOSServiceDetail,
        language: IDOSLanguage = .english
    ) async throws -> Data {
        let connection = try await resultConnection(
            for: service,
            unavailableError: .pdfUnavailable
        )
        return try await connectionPDF(
            for: connection,
            timetable: service.timetable,
            language: language
        )
    }

    /// Downloads the single-connection PDF generated by IDOS's native sharing workflow.
    public func connectionPDF(
        for connection: IDOSConnection,
        timetable: IDOSTimetable = .defaultTimetable,
        language: IDOSLanguage = .english
    ) async throws -> Data {
        guard let model = connection.pdfModel else {
            throw IDOSError.pdfUnavailable
        }

        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
        components.path = language.path(timetable: timetable, endpoint: "spojeni/pdf")

        var urlRequest = URLRequest(url: try components.requiredURL)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = Self.formURLEncodedData([URLQueryItem(name: "model", value: model)])

        let data = try await data(for: urlRequest)
        guard data.starts(with: Data("%PDF-".utf8)) else {
            throw IDOSError.invalidResponse
        }
        return data
    }

    public func findDepartures(request: IDOSDeparturesRequest) async throws -> [IDOSDeparture] {
        try await departureResults(request: request, language: .english)
    }

    public func findDeparturesPage(request: IDOSDeparturesRequest) async throws -> IDOSDeparturePage {
        try await findDeparturesPage(request: request, language: .english)
    }

    public func findDeparturesPage(
        request: IDOSDeparturesRequest,
        language: IDOSLanguage
    ) async throws -> IDOSDeparturePage {
        let departures = Array(
            try await departureResults(request: request, language: language).prefix(20)
        )
        let dates = departures.compactMap { IDOSDepartureParser.scheduledDate(for: $0) }
        guard let earliest = dates.min(), let latest = dates.max() else {
            return IDOSDeparturePage(departures: departures)
        }

        let paging = IDOSDeparturePagingContext(
            request: request,
            language: language,
            earliestCursor: earliest,
            latestCursor: latest,
            listedIDs: Set(departures.map(\.id))
        )
        return IDOSDeparturePage(departures: departures, pagingContext: paging)
    }

    public func findDeparturesPage(
        from page: IDOSDeparturePage,
        direction: IDOSPageDirection
    ) async throws -> IDOSDeparturePage {
        guard var paging = page.pagingContext else {
            return IDOSDeparturePage(departures: [])
        }

        let pageDuration: TimeInterval = 60 * 60
        let boundary = direction == .earlier ? paging.earliestCursor : paging.latestCursor
        let queryDate = direction == .earlier
            ? boundary.addingTimeInterval(-pageDuration)
            : boundary.addingTimeInterval(60)
        let request = Self.departureRequest(paging.request, at: queryDate)
        let fetched = try await departureResults(request: request, language: paging.language)
        let knownIDs = paging.listedIDs
        let departures = fetched.filter { departure in
            guard !knownIDs.contains(departure.id),
                  let date = IDOSDepartureParser.scheduledDate(for: departure)
            else {
                return false
            }
            return direction == .earlier ? date < boundary : date > boundary
        }

        let loadedDates = departures.compactMap { IDOSDepartureParser.scheduledDate(for: $0) }
        if direction == .earlier {
            paging.earliestCursor = loadedDates.min() ?? queryDate
        } else {
            paging.latestCursor = loadedDates.max() ?? queryDate.addingTimeInterval(pageDuration)
        }
        paging.listedIDs.formUnion(departures.map(\.id))

        return IDOSDeparturePage(departures: departures, pagingContext: paging)
    }

    private func departureResults(
        request: IDOSDeparturesRequest,
        language: IDOSLanguage
    ) async throws -> [IDOSDeparture] {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
        components.path = language.path(timetable: request.timetable, endpoint: "odjezdy/")

        var urlRequest = URLRequest(url: try components.requiredURL)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        urlRequest.httpBody = Self.formURLEncodedData(request.formItems)

        let data = try await data(for: urlRequest)
        guard let html = String(data: data, encoding: .utf8) else {
            throw IDOSError.invalidResponse
        }

        return IDOSDepartureParser.parse(html: html, timetable: request.timetable)
    }

    private static func departureRequest(
        _ original: IDOSDeparturesRequest,
        at date: Date
    ) -> IDOSDeparturesRequest {
        var request = original
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Prague")!
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        request.date = String(
            format: "%02d.%02d.%04d",
            components.day ?? 1,
            components.month ?? 1,
            components.year ?? 1
        )
        request.time = String(
            format: "%02d:%02d",
            components.hour ?? 0,
            components.minute ?? 0
        )
        return request
    }

    /// Loads a complete route; `timetable` is used only when a legacy ID lacks embedded context.
    public func serviceDetail(
        id: String,
        timetable: IDOSTimetable = .defaultTimetable
    ) async throws -> IDOSServiceDetail {
        try await serviceDetail(id: id, timetable: timetable, language: .english)
    }

    /// Loads a complete route in the selected IDOS language; `timetable` is only a legacy-ID fallback.
    public func serviceDetail(
        id: String,
        timetable: IDOSTimetable = .defaultTimetable,
        language: IDOSLanguage
    ) async throws -> IDOSServiceDetail {
        let reference = try IDOSServiceReference(id: id, fallbackTimetable: timetable)
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
        components.path = language.path(timetable: reference.timetable, endpoint: "Ajax/TrainDetail")
        components.queryItems = [URLQueryItem(name: "callback", value: "idosCallback")]

        var urlRequest = URLRequest(url: try components.requiredURL)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/x-www-form-urlencoded; charset=UTF-8", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = Self.formURLEncodedData(reference.formItems)

        let data = try await data(for: urlRequest)
        let json = try IDOSJSONP.decodePayload(from: data)
        guard let object = try JSONSerialization.jsonObject(with: json) as? [String: Any] else {
            throw IDOSError.invalidResponse
        }

        if object["hasError"] as? Bool == true {
            throw IDOSError.serviceDetailUnavailable(object["error"] as? String ?? "")
        }

        guard let html = object["content"] as? String,
              let detail = IDOSServiceDetailParser.parse(
                html: html,
                id: reference.id,
                timetable: reference.timetable,
                language: language
              )
        else {
            throw IDOSError.invalidResponse
        }

        return detail
    }

    /// Loads the same exact run, non-run, and unavailable states shown by IDOS's date-restriction dialog.
    public func serviceDateLimits(
        for service: IDOSServiceDetail,
        language: IDOSLanguage = .english
    ) async throws -> IDOSServiceDateLimits {
        let reference = try IDOSServiceReference(
            id: service.id,
            fallbackTimetable: service.timetable
        )

        var formComponents = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
        formComponents.path = language.path(timetable: reference.timetable, endpoint: "spojeni/")
        let formData = try await data(from: formComponents.requiredURL)
        guard let formHTML = String(data: formData, encoding: .utf8),
              let combinationID = IDOSConnectionFormParser.combinationID(in: formHTML)
        else {
            throw IDOSError.dateLimitsUnavailable
        }

        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
        components.path = language.path(
            timetable: reference.timetable,
            endpoint: "Ajax/GetDateLimitsRoute"
        )
        components.queryItems = [
            URLQueryItem(name: "ttIndex", value: String(reference.timetableIndex)),
            URLQueryItem(name: "train", value: String(reference.trainID)),
            URLQueryItem(name: "combId", value: combinationID),
            URLQueryItem(name: "stationFromIndex", value: "0"),
            URLQueryItem(name: "dateFrom", value: "\(reference.day).\(reference.month)."),
            URLQueryItem(name: "isArr", value: "false"),
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "callback", value: "idosCallback"),
        ]

        let data = try await data(from: components.requiredURL)
        guard !data.isEmpty else {
            throw IDOSError.dateLimitsUnavailable
        }
        let json = try IDOSJSONP.decodePayload(from: data)
        guard let response = try JSONSerialization.jsonObject(with: json) as? [String: Any],
              let script = response["result"] as? String,
              let limits = IDOSServiceDateLimitsParser.parse(script: script)
        else {
            throw IDOSError.dateLimitsUnavailable
        }
        return limits
    }

    private func data(from url: URL) async throws -> Data {
        let request = URLRequest(url: url)
        return try await data(for: request)
    }

    /// Loads the one connection encoded by a service share URL for native IDOS export operations.
    private func resultConnection(
        for service: IDOSServiceDetail,
        unavailableError: IDOSError
    ) async throws -> IDOSConnection {
        guard let value = service.shareURL, !value.isEmpty else {
            throw unavailableError
        }
        guard let url = URL(string: value, relativeTo: baseURL)?.absoluteURL,
              url.scheme?.lowercased() == baseURL.scheme?.lowercased(),
              url.host?.lowercased() == baseURL.host?.lowercased(),
              url.port == baseURL.port
        else {
            throw IDOSError.invalidURL
        }

        let data = try await data(from: url)
        guard let html = String(data: data, encoding: .utf8),
              let connection = IDOSConnectionParser.parse(
                  html: html,
                  timetable: service.timetable
              ).first
        else {
            throw IDOSError.invalidResponse
        }
        return connection
    }

    private func data(for request: URLRequest) async throws -> Data {
        var request = request
        request.setValue("kastan/0.1 (+local personal use)", forHTTPHeaderField: "User-Agent")

        return try await withCheckedThrowingContinuation { continuation in
            let task = URLSession.shared.dataTask(with: request) { data, response, error in
                if let error {
                    continuation.resume(throwing: IDOSError.networkUnavailable(error.localizedDescription))
                    return
                }

                guard let data,
                      let httpResponse = response as? HTTPURLResponse,
                      200..<300 ~= httpResponse.statusCode
                else {
                    continuation.resume(throwing: IDOSError.invalidResponse)
                    return
                }

                continuation.resume(returning: data)
            }

            task.resume()
        }
    }

    private static func formURLEncodedData(_ items: [URLQueryItem]) -> Data? {
        IDOSFormEncoding.data(items)
    }
}

/// An exact IDOS place selected from suggestions or represented by geographic coordinates.
///
/// Supplying this value with a request distinguishes a station or stop from a municipality
/// with the same visible name and lets IDOS route from, to, or via that exact object.
/// Endpoint selections can also represent the user's current location.
/// Omitting it keeps the corresponding request field as free text.
public struct IDOSPlaceSelection: Codable, Equatable, Sendable {
    /// The text IDOS places into the visible search field after selection.
    public var text: String
    /// The IDOS catalog or coordinate marker describing the selected place.
    public var listID: String
    /// The selected catalog object or coordinate mode identifier.
    public var itemID: String

    public init(text: String, listID: String, itemID: String) {
        self.text = text
        self.listID = listID
        self.itemID = itemID
    }

    public init?(suggestion: IDOSSuggestion) {
        guard let listID = suggestion.value,
              let itemID = suggestion.value2
        else {
            return nil
        }

        self.init(
            text: suggestion.selectedText ?? suggestion.text,
            listID: listID,
            itemID: itemID
        )
    }

    /// Builds IDOS's exact `My location` value from a WGS-84 coordinate.
    public static func currentLocation(
        text: String,
        latitude: Double,
        longitude: Double
    ) -> Self {
        Self(
            text: text,
            listID: "loc: \(coordinate(latitude)); \(coordinate(longitude))",
            itemID: "myPosition=true"
        )
    }

    fileprivate var formValue: String {
        // IDOS omits the visible label only for its coordinate-backed `My location` object.
        if itemID == "myPosition=true", listID.hasPrefix("loc:") {
            return "\(listID)%\(itemID)"
        }
        return "\(text)%\(listID)%\(itemID)"
    }

    private static func coordinate(_ value: Double) -> String {
        String(format: "%.6f", locale: Locale(identifier: "en_US_POSIX"), value)
    }
}

public struct IDOSDeparturesRequest: Codable, Equatable, Sendable {
    public var timetable: IDOSTimetable
    public var station: String
    /// An exact autocomplete choice, or `nil` when `station` should be interpreted as free text.
    public var stationSelection: IDOSPlaceSelection?
    public var date: String?
    public var time: String?
    public var isArrival: Bool

    public init(
        timetable: IDOSTimetable = .defaultTimetable,
        station: String,
        stationSelection: IDOSPlaceSelection? = nil,
        date: String? = nil,
        time: String? = nil,
        isArrival: Bool = false
    ) {
        self.timetable = timetable
        self.station = station
        self.stationSelection = stationSelection
        self.date = date
        self.time = time
        self.isArrival = isArrival
    }

    var formItems: [URLQueryItem] {
        var items = [
            URLQueryItem(name: "From", value: station),
            URLQueryItem(name: "FromHidden", value: stationSelection?.formValue ?? "%0"),
            URLQueryItem(name: "IsArr", value: isArrival ? "True" : "False"),
        ]

        if let date {
            items.append(URLQueryItem(name: "Date", value: date))
        }

        if let time {
            items.append(URLQueryItem(name: "Time", value: time))
        }

        items.append(URLQueryItem(name: "submit", value: "true"))
        return items
    }
}

/// Selects one municipality inside an IDOS Station Timetable catalog that contains several local networks.
public struct IDOSStationTimetableMunicipality: Codable, Equatable, Hashable, Sendable {
    /// Municipality name presented by IDOS.
    public var name: String
    /// Catalog index required by the IDOS line and stop suggestion endpoints.
    public var timetableIndex: Int
    /// Opaque municipality identifier carried by a permanent Station Timetable result URL.
    public var timetableName: String

    public init(name: String, timetableIndex: Int, timetableName: String) {
        self.name = name
        self.timetableIndex = timetableIndex
        self.timetableName = timetableName
    }

    /// Returns the municipalities published within a supported multi-municipality timetable.
    public static func available(for timetable: IDOSTimetable) -> [Self] {
        timetable.slug == "odis" ? odisMunicipalities : []
    }

    /// Returns the municipality selected initially by IDOS for the given timetable.
    public static func `default`(for timetable: IDOSTimetable) -> Self? {
        available(for: timetable).first { $0.timetableName == "ODIS" }
    }

    /// Resolves a displayed municipality name or its opaque IDOS identifier, defaulting like IDOS when omitted.
    public static func resolve(_ value: String?, timetable: IDOSTimetable) throws -> Self? {
        guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return Self.default(for: timetable)
        }

        let key = lookupKey(value)
        if let municipality = available(for: timetable).first(where: {
            lookupKey($0.name) == key || lookupKey($0.timetableName) == key
        }) {
            return municipality
        }
        throw IDOSError.invalidStationTimetableMunicipality(value, timetable: timetable)
    }

    private static func lookupKey(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .folding(
                options: [.diacriticInsensitive, .caseInsensitive],
                locale: Locale(identifier: "cs_CZ")
            )
            .filter { $0.isLetter || $0.isNumber }
    }

    /// Mirrors the complete municipality chooser currently published by the ODIS Station Timetable form.
    private static let odisMunicipalities: [Self] = [
        Self(name: "Bruntál", timetableIndex: 4, timetableName: "Bruntal"),
        Self(name: "Český Těšín", timetableIndex: 5, timetableName: "CesTes"),
        Self(name: "Frýdek-Místek", timetableIndex: 3, timetableName: "FM"),
        Self(name: "Havířov", timetableIndex: 6, timetableName: "Havirov"),
        Self(name: "Karviná", timetableIndex: 7, timetableName: "Karvina"),
        Self(name: "Krnov", timetableIndex: 8, timetableName: "Krnov"),
        Self(name: "Nový Jičín", timetableIndex: 9, timetableName: "NJ"),
        Self(name: "Opava", timetableIndex: 10, timetableName: "Opava"),
        Self(name: "Orlová", timetableIndex: 11, timetableName: "Orlova"),
        Self(name: "Ostrava", timetableIndex: 2, timetableName: "ODIS"),
        Self(name: "Studénka", timetableIndex: 12, timetableName: "Studenka"),
        Self(name: "Třinec", timetableIndex: 13, timetableName: "Trinec"),
    ]
}

/// A station-timetable query for one MHD or integrated-transport line and direction.
public struct IDOSStationTimetableRequest: Codable, Equatable, Sendable {
    public var timetable: IDOSTimetable
    /// Narrows a multi-municipality timetable such as ODIS to one local network.
    public var municipality: IDOSStationTimetableMunicipality?
    public var line: String
    public var from: String
    public var to: String
    public var date: String?
    public var wholeWeek: Bool

    public init(
        timetable: IDOSTimetable,
        municipality: IDOSStationTimetableMunicipality? = nil,
        line: String,
        from: String,
        to: String,
        date: String? = nil,
        wholeWeek: Bool = false
    ) {
        self.timetable = timetable
        self.municipality = municipality
        self.line = line
        self.from = from
        self.to = to
        self.date = date
        self.wholeWeek = wholeWeek
    }

    var isComplete: Bool {
        [line, from, to].allSatisfy {
            !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    var queryItems: [URLQueryItem] {
        var items = [
            URLQueryItem(name: "l", value: line.trimmingCharacters(in: .whitespacesAndNewlines)),
            URLQueryItem(name: "f", value: from.trimmingCharacters(in: .whitespacesAndNewlines)),
            URLQueryItem(name: "t", value: to.trimmingCharacters(in: .whitespacesAndNewlines)),
        ]
        if let municipality = effectiveMunicipality {
            items.append(URLQueryItem(name: "ttn", value: municipality.timetableName))
        }
        if let date, !date.isEmpty {
            items.insert(URLQueryItem(name: "date", value: date), at: 0)
        }
        if wholeWeek {
            items.append(URLQueryItem(name: "wholeweek", value: "true"))
        }
        items.append(URLQueryItem(name: "submit", value: "true"))
        return items
    }

    /// Applies the same initial municipality as IDOS when a multi-municipality timetable omits one.
    var effectiveMunicipality: IDOSStationTimetableMunicipality? {
        municipality ?? IDOSStationTimetableMunicipality.default(for: timetable)
    }
}

/// A complete IDOS station timetable with its route, hourly departures, keyed explanations, and notes.
public struct IDOSStationTimetable: Codable, Equatable, Sendable {
    public var timetable: IDOSTimetable
    /// Identifies the local network selected inside a multi-municipality timetable.
    public var municipality: IDOSStationTimetableMunicipality?
    public var lineName: String
    public var transportMode: IDOSTransportMode?
    public var fromStop: String
    public var toStop: String
    public var stops: [IDOSStationTimetableStop]
    public var schedules: [IDOSStationTimetableSchedule]
    /// Explains markers such as `A` that IDOS appends to individual departures.
    public var explanations: [String]
    /// Preserves timetable-wide information that is not tied to an individual departure marker.
    public var notes: [String]
    /// Identifies a temporary lockout timetable marked by IDOS.
    public var isLockout: Bool
    public var shareURL: String?

    public init(
        timetable: IDOSTimetable,
        municipality: IDOSStationTimetableMunicipality? = nil,
        lineName: String,
        transportMode: IDOSTransportMode? = nil,
        fromStop: String,
        toStop: String,
        stops: [IDOSStationTimetableStop],
        schedules: [IDOSStationTimetableSchedule],
        explanations: [String] = [],
        notes: [String] = [],
        isLockout: Bool = false,
        shareURL: String? = nil
    ) {
        self.timetable = timetable
        self.municipality = municipality
        self.lineName = lineName
        self.transportMode = transportMode
        self.fromStop = fromStop
        self.toStop = toStop
        self.stops = stops
        self.schedules = schedules
        self.explanations = explanations
        self.notes = notes
        self.isLockout = isLockout
        self.shareURL = shareURL
    }

    public var selectedStop: IDOSStationTimetableStop? {
        stops.first(where: \.isSelected)
    }

    private enum CodingKeys: String, CodingKey {
        case timetable
        case municipality
        case lineName
        case transportMode
        case fromStop
        case toStop
        case stops
        case schedules
        case explanations
        case notes
        case isLockout
        case shareURL
    }

    /// Keeps previously encoded station timetables readable after explanations became a separate field.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            timetable: try container.decode(IDOSTimetable.self, forKey: .timetable),
            municipality: try container.decodeIfPresent(
                IDOSStationTimetableMunicipality.self,
                forKey: .municipality
            ),
            lineName: try container.decode(String.self, forKey: .lineName),
            transportMode: try container.decodeIfPresent(
                IDOSTransportMode.self,
                forKey: .transportMode
            ),
            fromStop: try container.decode(String.self, forKey: .fromStop),
            toStop: try container.decode(String.self, forKey: .toStop),
            stops: try container.decode([IDOSStationTimetableStop].self, forKey: .stops),
            schedules: try container.decode(
                [IDOSStationTimetableSchedule].self,
                forKey: .schedules
            ),
            explanations: try container.decodeIfPresent(
                [String].self,
                forKey: .explanations
            ) ?? [],
            notes: try container.decode([String].self, forKey: .notes),
            isLockout: try container.decode(Bool.self, forKey: .isLockout),
            shareURL: try container.decodeIfPresent(String.self, forKey: .shareURL)
        )
    }
}

/// One stop on a station timetable's selected line and direction.
public struct IDOSStationTimetableStop: Codable, Equatable, Sendable {
    public var name: String
    public var minuteOffset: Int?
    /// Preserves the fare-zone label when the selected timetable publishes one.
    public var tariffZone: String?
    /// Preserves the platform or stand number printed beside this stop by IDOS.
    public var platform: String?
    public var isSelected: Bool
    public var notes: [String]

    public init(
        name: String,
        minuteOffset: Int? = nil,
        tariffZone: String? = nil,
        platform: String? = nil,
        isSelected: Bool = false,
        notes: [String] = []
    ) {
        self.name = name
        self.minuteOffset = minuteOffset
        self.tariffZone = tariffZone
        self.platform = platform
        self.isSelected = isSelected
        self.notes = notes
    }
}

/// One date or service-day group in a station timetable.
public struct IDOSStationTimetableSchedule: Codable, Equatable, Sendable {
    public var label: String
    public var hours: [IDOSStationTimetableHour]

    public init(label: String, hours: [IDOSStationTimetableHour]) {
        self.label = label
        self.hours = hours
    }
}

/// Every minute marker supplied by IDOS for one hour, including attached note symbols.
public struct IDOSStationTimetableHour: Codable, Equatable, Sendable {
    public var hour: String
    public var departures: [String]

    public init(hour: String, departures: [String]) {
        self.hour = hour
        self.departures = departures
    }
}

public struct IDOSConnectionRequest: Codable, Equatable, Sendable {
    private static let defaultMaxTransfers = 4
    private static let defaultMinimumTransferTime = -1
    private static let defaultMaximumTransferTime = 240
    private static let defaultMaximumWalkingTime = 60
    private static let defaultMaximumCityWalkingTime = 10
    private static let defaultTransportTypeIDs = [
        150, 151, 152, 153, 154, 155, 156,
        200, 201, 202,
        300, 301, 303, 306,
    ]

    public var timetable: IDOSTimetable
    public var from: String
    public var to: String
    /// An exact autocomplete choice, or `nil` when `from` should be interpreted as free text.
    public var fromSelection: IDOSPlaceSelection?
    /// An exact autocomplete choice, or `nil` when `to` should be interpreted as free text.
    public var toSelection: IDOSPlaceSelection?
    public var date: String?
    public var time: String?
    public var isArrival: Bool
    public var onlyDirect: Bool
    public var via: [String]
    /// Exact autocomplete choices aligned with `via`, with `nil` entries retaining free-text interpretation.
    public var viaSelections: [IDOSPlaceSelection?]?
    public var maxTransfers: Int?
    public var minimumTransferTime: Int?
    public var resultLimit: Int?

    public init(
        timetable: IDOSTimetable = .defaultTimetable,
        from: String,
        to: String,
        fromSelection: IDOSPlaceSelection? = nil,
        toSelection: IDOSPlaceSelection? = nil,
        date: String? = nil,
        time: String? = nil,
        isArrival: Bool = false,
        onlyDirect: Bool = false,
        via: [String] = [],
        viaSelections: [IDOSPlaceSelection?]? = nil,
        maxTransfers: Int? = nil,
        minimumTransferTime: Int? = nil,
        resultLimit: Int? = nil
    ) {
        self.timetable = timetable
        self.from = from
        self.to = to
        self.fromSelection = fromSelection
        self.toSelection = toSelection
        self.date = date
        self.time = time
        self.isArrival = isArrival
        self.onlyDirect = onlyDirect
        self.via = via
        self.viaSelections = viaSelections
        self.maxTransfers = maxTransfers
        self.minimumTransferTime = minimumTransferTime
        self.resultLimit = resultLimit
    }

    var formItems: [URLQueryItem] {
        var items = [
            URLQueryItem(name: "From", value: from),
            URLQueryItem(name: "FromHidden", value: fromSelection?.formValue ?? "%0"),
            URLQueryItem(name: "To", value: to),
            URLQueryItem(name: "ToHidden", value: toSelection?.formValue ?? "%0"),
            URLQueryItem(name: "IsArr", value: isArrival ? "True" : "False"),
        ]

        if let date {
            items.append(URLQueryItem(name: "Date", value: date))
        }

        if let time {
            items.append(URLQueryItem(name: "Time", value: time))
        }

        if onlyDirect {
            items.append(URLQueryItem(name: "OnlyDirect", value: "true"))
        }

        if hasAdvancedOptions {
            items.append(URLQueryItem(name: "AdvancedForm.AdvancedFormIsOpen", value: "True"))

            for (index, place) in via.enumerated() {
                items.append(URLQueryItem(name: "AdvancedForm.Via[\(index)]", value: place))
                let selection = viaSelections.flatMap { selections in
                    selections.indices.contains(index) ? selections[index] : nil
                }
                items.append(URLQueryItem(
                    name: "AdvancedForm.ViaHidden[\(index)]",
                    value: selection?.formValue ?? ""
                ))
            }

            items.append(URLQueryItem(
                name: "AdvancedForm.MaxChange",
                value: String(maxTransfers ?? Self.defaultMaxTransfers)
            ))
            items.append(URLQueryItem(
                name: "AdvancedForm.MinTime",
                value: String(minimumTransferTime ?? Self.defaultMinimumTransferTime)
            ))
            items.append(URLQueryItem(name: "AdvancedForm.MaxTime", value: String(Self.defaultMaximumTransferTime)))
            items.append(URLQueryItem(name: "AdvancedForm.MaxArcLength", value: String(Self.defaultMaximumWalkingTime)))
            items.append(URLQueryItem(
                name: "AdvancedForm.MaxArcLengthCity",
                value: String(Self.defaultMaximumCityWalkingTime)
            ))

            for transportTypeID in Self.defaultTransportTypeIDs {
                let value = String(transportTypeID)
                items.append(URLQueryItem(name: "trTypeId[\(value)]", value: value))
            }
        }

        items.append(URLQueryItem(name: "submit", value: "true"))
        return items
    }

    private var hasAdvancedOptions: Bool {
        !via.isEmpty || maxTransfers != nil || minimumTransferTime != nil
    }
}

public struct IDOSTimetable: Codable, Equatable, Sendable {
    public var slug: String
    public var displayName: String

    public init(slug: String, displayName: String) {
        self.slug = slug
        self.displayName = displayName
    }

    public static let defaultTimetable = IDOSTimetable(slug: "vlakyautobusymhdvse", displayName: "All timetables")

    public static var known: [IDOSTimetable] {
        baseTimetables + mhdNames
            .filter { !unsupportedMHDNames.contains($0) }
            .map { name in
                IDOSTimetable(
                    slug: mhdSlugOverrides[name] ?? slugify(name),
                    displayName: "Urban Public Transport \(name)"
                )
            }
    }

    private static let baseTimetables: [IDOSTimetable] = [
        .defaultTimetable,
        IDOSTimetable(slug: "vlakyautobusymhd", displayName: "Trains + Buses + Urban Public Transport"),
        IDOSTimetable(slug: "vlaky", displayName: "Trains"),
        IDOSTimetable(slug: "autobusy", displayName: "Buses"),
        IDOSTimetable(slug: "vlakyautobusy", displayName: "Trains + Buses"),
        IDOSTimetable(slug: "pid", displayName: "Prague + PID"),
        IDOSTimetable(slug: "idsjmk", displayName: "IDS JMK / Brno"),
        IDOSTimetable(slug: "odis", displayName: "ODIS"),
        IDOSTimetable(slug: "idol", displayName: "IDOL"),
        IDOSTimetable(slug: "iredo", displayName: "IREDO"),
    ]

    public static func resolve(_ value: String?) throws -> IDOSTimetable {
        guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .defaultTimetable
        }

        let lookup = lookupKey(value)
        if let timetable = aliases()[lookup] {
            return timetable
        }

        guard let customSlug = slugCandidate(value) else {
            throw IDOSError.invalidTimetable(value)
        }

        return IDOSTimetable(slug: customSlug, displayName: customSlug)
    }

    private static func aliases() -> [String: IDOSTimetable] {
        var aliases: [String: IDOSTimetable] = [
            "all": .defaultTimetable,
            "default": .defaultTimetable,
            "vlakyautobusymhdvse": .defaultTimetable,
            "vlakyautobusymhd": known.first { $0.slug == "vlakyautobusymhd" }!,
            "train": known.first { $0.slug == "vlaky" }!,
            "trains": known.first { $0.slug == "vlaky" }!,
            "bus": known.first { $0.slug == "autobusy" }!,
            "buses": known.first { $0.slug == "autobusy" }!,
            "trainbus": known.first { $0.slug == "vlakyautobusy" }!,
            "prahapid": known.first { $0.slug == "pid" }!,
            "brno": known.first { $0.slug == "idsjmk" }!,
            "jmk": known.first { $0.slug == "idsjmk" }!,
            "idsjmk": known.first { $0.slug == "idsjmk" }!,
            "libereckykraj": known.first { $0.slug == "idol" }!,
        ]

        for timetable in known {
            aliases[lookupKey(timetable.slug)] = timetable
            aliases[lookupKey(timetable.displayName)] = timetable

            if timetable.displayName.hasPrefix("Urban Public Transport ") {
                aliases[lookupKey(String(timetable.displayName.dropFirst("Urban Public Transport ".count)))] = timetable
            }
        }

        return aliases
    }

    private static func lookupKey(_ value: String) -> String {
        ascii(value).filter { $0.isLetter || $0.isNumber }
    }

    private static func slugCandidate(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.range(of: #"^[A-Za-z0-9-]+$"#, options: .regularExpression) != nil {
            return trimmed.lowercased()
        }

        return nil
    }

    private static func slugify(_ value: String) -> String {
        let compact = ascii(value)
        let withoutUrbanPublicTransport = compact.hasPrefix("urbanpublictransport")
            ? String(compact.dropFirst("urbanpublictransport".count))
            : compact

        return withoutUrbanPublicTransport.filter { $0.isLetter || $0.isNumber }
    }

    private static func ascii(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "cs_CZ"))
    }

    private static let mhdSlugOverrides: [String: String] = [
        "Brandýs n.L.-St.Bol.": "brandys",
        "Bystřice nad Pernštejnem": "bystrice",
        "Most a Litvínov": "most",
        "Zlín a Otrokovice": "zlin",
    ]

    private static let unsupportedMHDNames: Set<String> = [
        "Beroun",
        "Čáslav",
        "Dačice",
        "Dvůr Králové n. L.",
        "Hořice",
        "Jablonec nad Nisou",
        "Kralupy nad Vltavou",
        "Mělník",
        "Mikulov",
        "Neratovice",
        "Nymburk",
        "Přeštice",
        "Roudnice nad Labem",
        "Rychnov nad Kněžnou",
        "Štětí",
        "Žamberk",
    ]

    private static let mhdNames = [
        "Praha",
        "Ostrava",
        "Adamov",
        "Aš",
        "Benešov",
        "Beroun",
        "Bílina",
        "Blansko",
        "Brandýs n.L.-St.Bol.",
        "Bruntál",
        "Bystřice nad Pernštejnem",
        "Břeclav",
        "Čáslav",
        "Česká Lípa",
        "České Budějovice",
        "Český Těšín",
        "Dačice",
        "Děčín",
        "Domažlice",
        "Duchcov",
        "Dvůr Králové n. L.",
        "Frýdek-Místek",
        "Havířov",
        "Havlíčkův Brod",
        "Hodonín",
        "Hořice",
        "Hradec Králové",
        "Hranice",
        "Cheb",
        "Chomutov",
        "Chrudim",
        "Jablonec nad Nisou",
        "Jáchymov",
        "Jičín",
        "Jihlava",
        "Jindřichův Hradec",
        "Kadaň",
        "Karlovy Vary",
        "Karviná",
        "Kladno",
        "Klášterec nad Ohří",
        "Klatovy",
        "Kolín",
        "Kralupy nad Vltavou",
        "Krnov",
        "Kroměříž",
        "Kutná Hora",
        "Kyjov",
        "Liberec",
        "Litoměřice",
        "Litomyšl",
        "Louny",
        "Lovosice",
        "Mariánské Lázně",
        "Mělník",
        "Mikulov",
        "Mladá Boleslav",
        "Most a Litvínov",
        "Náchod",
        "Neratovice",
        "Nový Jičín",
        "Nymburk",
        "Olomouc",
        "Opava",
        "Orlová",
        "Ostrov",
        "Pardubice",
        "Pelhřimov",
        "Písek",
        "Plzeň",
        "Polička",
        "Prostějov",
        "Přelouč",
        "Přerov",
        "Přeštice",
        "Příbram",
        "Rokycany",
        "Roudnice nad Labem",
        "Rychnov nad Kněžnou",
        "Slaný",
        "Sokolov",
        "Strakonice",
        "Stříbro",
        "Studénka",
        "Špindlerův Mlýn",
        "Šumperk",
        "Tábor",
        "Tachov",
        "Teplice",
        "Trutnov",
        "Třebíč",
        "Třinec",
        "Turnov",
        "Týniště nad Orlicí",
        "Uherské Hradiště",
        "Ústí nad Labem",
        "Valašské Meziříčí",
        "Velké Meziříčí",
        "Vlašim",
        "Vrchlabí",
        "Vsetín",
        "Vyškov",
        "Zábřeh",
        "Zlín a Otrokovice",
        "Znojmo",
        "Žatec",
        "Žďár nad Sázavou",
    ]
}

/// The inclusive first and last service dates published by an IDOS timetable search form.
public struct IDOSTimetableValidity: Codable, Equatable, Sendable {
    public var validFrom: Date
    public var validThrough: Date

    public init(validFrom: Date, validThrough: Date) {
        self.validFrom = validFrom
        self.validThrough = validThrough
    }
}

/// Exact operating states returned by IDOS's native date-restriction calendar for one service.
public struct IDOSServiceDateLimits: Codable, Equatable, Sendable {
    /// Mirrors the three meanings shown by IDOS without inferring missing days from prose.
    public enum DayStatus: Int, Codable, Equatable, Sendable {
        case doesNotRun = 0
        case runs = 1
        case informationUnavailable = 2
    }

    /// Associates one civil service date with the state published by IDOS.
    public struct Day: Codable, Equatable, Sendable {
        public var date: Date
        public var status: DayStatus

        public init(date: Date, status: DayStatus) {
            self.date = date
            self.status = status
        }
    }

    /// The reference day with which IDOS anchors the first returned calendar month.
    public var referenceDate: Date
    /// Every day supplied by IDOS, ordered chronologically across its returned months.
    public var days: [Day]

    public init(referenceDate: Date, days: [Day]) {
        let calendar = Self.serviceCalendar
        self.referenceDate = calendar.startOfDay(for: referenceDate)
        self.days = days
            .map { Day(date: calendar.startOfDay(for: $0.date), status: $0.status) }
            .sorted { $0.date < $1.date }
    }

    /// The first civil date for which IDOS returned a state.
    public var firstDate: Date? {
        days.first?.date
    }

    /// The last civil date for which IDOS returned a state.
    public var lastDate: Date? {
        days.last?.date
    }

    /// Returns only a state explicitly supplied by IDOS; dates outside the response remain absent.
    public func status(on date: Date) -> DayStatus? {
        let date = Self.serviceCalendar.startOfDay(for: date)
        return days.first(where: { $0.date == date })?.status
    }

    private static var serviceCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = TimeZone(identifier: "Europe/Prague")!
        return calendar
    }
}

public struct IDOSSuggestion: Codable, Equatable, Sendable {
    public var selectedText: String?
    public var text: String
    public var description: String?
    public var region: String?
    public var value: String?
    public var value2: String?
    public var iconId: Int?
    public var coorX: Double?
    public var coorY: Double?
    /// First terminal supplied for a station-timetable line suggestion.
    public var from: String?
    /// Opposite terminal supplied for a station-timetable line suggestion.
    public var to: String?

    public init(
        selectedText: String? = nil,
        text: String,
        description: String? = nil,
        region: String? = nil,
        value: String? = nil,
        value2: String? = nil,
        iconId: Int? = nil,
        coorX: Double? = nil,
        coorY: Double? = nil,
        from: String? = nil,
        to: String? = nil
    ) {
        self.selectedText = selectedText
        self.text = text
        self.description = description
        self.region = region
        self.value = value
        self.value2 = value2
        self.iconId = iconId
        self.coorX = coorX
        self.coorY = coorY
        self.from = from
        self.to = to
    }
}

/// Describes the editable message and generated attachments IDOS will send for one connection.
public struct IDOSConnectionEmailDraft: Codable, Equatable, Sendable {
    public var message: String
    public var description: String
    public var attachmentFileNames: [String]

    public init(
        message: String,
        description: String,
        attachmentFileNames: [String]
    ) {
        self.message = message
        self.description = description
        self.attachmentFileNames = attachmentFileNames
    }
}

public struct IDOSConnection: Codable, Equatable, Sendable {
    public var id: String
    public var departureTime: String
    public var departureStation: String
    public var arrivalTime: String
    public var arrivalStation: String
    public var duration: String
    public var legs: [IDOSConnectionLeg]
    public var shareURL: String?
    var calendarModel: String?

    /// Adapts IDOS's per-connection calendar model to the PDF sharing model used by its website.
    var pdfModel: String? {
        guard let calendarModel,
              let source = calendarModel.data(using: .utf8),
              var model = try? JSONSerialization.jsonObject(with: source) as? [String: Any],
              var connectionData = model["jsConnData"] as? [String: Any]
        else {
            return nil
        }

        connectionData.removeValue(forKey: "permanentUrl")
        model["jsConnData"] = connectionData
        model["context"] = 2

        guard JSONSerialization.isValidJSONObject(model),
              let data = try? JSONSerialization.data(withJSONObject: model),
              let value = String(data: data, encoding: .utf8)
        else {
            return nil
        }
        return value
    }

    public init(
        id: String,
        departureTime: String,
        departureStation: String,
        arrivalTime: String,
        arrivalStation: String,
        duration: String,
        legs: [IDOSConnectionLeg],
        shareURL: String? = nil
    ) {
        self.init(
            id: id,
            departureTime: departureTime,
            departureStation: departureStation,
            arrivalTime: arrivalTime,
            arrivalStation: arrivalStation,
            duration: duration,
            legs: legs,
            shareURL: shareURL,
            calendarModel: nil
        )
    }

    init(
        id: String,
        departureTime: String,
        departureStation: String,
        arrivalTime: String,
        arrivalStation: String,
        duration: String,
        legs: [IDOSConnectionLeg],
        shareURL: String? = nil,
        calendarModel: String? = nil
    ) {
        self.id = id
        self.departureTime = departureTime
        self.departureStation = departureStation
        self.arrivalTime = arrivalTime
        self.arrivalStation = arrivalStation
        self.duration = duration
        self.legs = legs
        self.shareURL = shareURL
        self.calendarModel = calendarModel
    }

    enum CodingKeys: String, CodingKey {
        case id
        case departureTime
        case departureStation
        case arrivalTime
        case arrivalStation
        case duration
        case legs
        case shareURL
    }

    public func summaryLine(number: Int, includeDetails: Bool = true) -> String {
        var result = "\(number). \(TerminalStyle.bold(departureTime)) \(departureStation) → \(TerminalStyle.bold(arrivalTime)) \(arrivalStation)"

        if !duration.isEmpty {
            result += " (\(duration))"
        }

        if !legs.isEmpty {
            let legSummary = legs.map { leg in
                let line = [
                    leg.displayName,
                    includeDetails ? leg.fromStationDisplay : leg.fromStation,
                    TerminalStyle.bold(leg.departureTime),
                    "→",
                    TerminalStyle.bold(leg.arrivalTime),
                    includeDetails ? leg.toStationDisplay : leg.toStation,
                ]
                    .filter { !$0.isEmpty }
                    .joined(separator: " ")
                let details = includeDetails ? [leg.carrier, leg.delay]
                    .compactMap(\.self)
                    .filter { !$0.isEmpty }
                    .map { "      \($0)" }
                    .joined(separator: "\n") : ""

                return details.isEmpty ? line : "\(line)\n\(details)"
            }.map { "   \($0)" }
                .joined(separator: "\n")
            result += "\n\(legSummary)"
        }

        return result
    }
}

public struct IDOSConnectionLeg: Codable, Equatable, Sendable {
    public var name: String
    /// Opaque ID shared with the matching departure result for future service-route lookups.
    public var id: String?
    public var color: String?
    public var transportMode: IDOSTransportMode?
    public var departureTime: String
    public var fromStation: String
    public var fromTariffZone: String?
    public var fromPlatform: String?
    public var arrivalTime: String
    public var toStation: String
    public var toTariffZone: String?
    public var toPlatform: String?
    public var carrier: String?
    public var delay: String?
    /// Passenger facilities and restrictions printed beside this service by IDOS.
    public var serviceInformation: [IDOSServiceInformation]

    public init(
        name: String,
        id: String? = nil,
        color: String? = nil,
        transportMode: IDOSTransportMode? = nil,
        departureTime: String,
        fromStation: String,
        fromTariffZone: String? = nil,
        fromPlatform: String? = nil,
        arrivalTime: String,
        toStation: String,
        toTariffZone: String? = nil,
        toPlatform: String? = nil,
        carrier: String? = nil,
        delay: String? = nil,
        serviceInformation: [IDOSServiceInformation] = []
    ) {
        self.name = name
        self.id = id
        self.color = color
        self.transportMode = transportMode
        self.departureTime = departureTime
        self.fromStation = fromStation
        self.fromTariffZone = fromTariffZone
        self.fromPlatform = fromPlatform
        self.arrivalTime = arrivalTime
        self.toStation = toStation
        self.toTariffZone = toTariffZone
        self.toPlatform = toPlatform
        self.carrier = carrier
        self.delay = delay
        self.serviceInformation = serviceInformation
    }

    enum CodingKeys: String, CodingKey {
        case name
        case id
        case color
        case transportMode
        case departureTime
        case fromStation
        case fromTariffZone
        case fromPlatform
        case arrivalTime
        case toStation
        case toTariffZone
        case toPlatform
        case carrier
        case delay
        case serviceInformation
    }

    /// Keeps previously encoded service rows decodable after passenger information was added.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            name: try container.decode(String.self, forKey: .name),
            id: try container.decodeIfPresent(String.self, forKey: .id),
            color: try container.decodeIfPresent(String.self, forKey: .color),
            transportMode: try container.decodeIfPresent(IDOSTransportMode.self, forKey: .transportMode),
            departureTime: try container.decode(String.self, forKey: .departureTime),
            fromStation: try container.decode(String.self, forKey: .fromStation),
            fromTariffZone: try container.decodeIfPresent(String.self, forKey: .fromTariffZone),
            fromPlatform: try container.decodeIfPresent(String.self, forKey: .fromPlatform),
            arrivalTime: try container.decode(String.self, forKey: .arrivalTime),
            toStation: try container.decode(String.self, forKey: .toStation),
            toTariffZone: try container.decodeIfPresent(String.self, forKey: .toTariffZone),
            toPlatform: try container.decodeIfPresent(String.self, forKey: .toPlatform),
            carrier: try container.decodeIfPresent(String.self, forKey: .carrier),
            delay: try container.decodeIfPresent(String.self, forKey: .delay),
            serviceInformation: try container.decodeIfPresent(
                [IDOSServiceInformation].self,
                forKey: .serviceInformation
            ) ?? []
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encodeIfPresent(id, forKey: .id)
        try container.encodeIfPresent(color, forKey: .color)
        try container.encodeIfPresent(transportMode, forKey: .transportMode)
        try container.encode(departureTime, forKey: .departureTime)
        try container.encode(fromStation, forKey: .fromStation)
        try container.encodeIfPresent(fromTariffZone, forKey: .fromTariffZone)
        try container.encodeIfPresent(fromPlatform, forKey: .fromPlatform)
        try container.encode(arrivalTime, forKey: .arrivalTime)
        try container.encode(toStation, forKey: .toStation)
        try container.encodeIfPresent(toTariffZone, forKey: .toTariffZone)
        try container.encodeIfPresent(toPlatform, forKey: .toPlatform)
        try container.encodeIfPresent(carrier, forKey: .carrier)
        try container.encodeIfPresent(delay, forKey: .delay)
        if !serviceInformation.isEmpty {
            try container.encode(serviceInformation, forKey: .serviceInformation)
        }
    }

    public var displayName: String {
        [transportMode?.emoji, coloredName]
            .compactMap(\.self)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    var coloredName: String {
        TerminalColor.color(name, htmlColor: color)
    }

    public var fromStationDisplay: String {
        stationDisplay(name: fromStation, tariffZone: fromTariffZone, platform: fromPlatform)
    }

    public var toStationDisplay: String {
        stationDisplay(name: toStation, tariffZone: toTariffZone, platform: toPlatform)
    }

    private func stationDisplay(name: String, tariffZone: String?, platform: String?) -> String {
        var parts = [name]
        if let tariffZone, !tariffZone.isEmpty {
            parts.append("tariff zone \(tariffZone)")
        }
        if let platform, !platform.isEmpty {
            parts.append(platformDescription(platform))
        }
        return parts.joined(separator: " · ")
    }

    /// Expands the railway platform/track pair carried by connection HTML without changing
    /// ordinary platform or stand identifiers used by other transport modes.
    private func platformDescription(_ value: String) -> String {
        guard transportMode == .train else { return "platform \(value)" }
        let parts = value.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 2 else { return "platform \(value)" }

        let platform = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
        let track = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
        guard !platform.isEmpty, !track.isEmpty else { return "platform \(value)" }
        return "platform \(platform) track \(track)"
    }
}

public struct IDOSDeparture: Codable, Equatable, Sendable {
    public var id: String
    public var stationName: String?
    public var time: String
    public var lineName: String
    public var lineColor: String?
    public var transportMode: IDOSTransportMode?
    public var destination: String
    public var tariffZone: String?
    public var platform: String?
    public var via: String?
    public var carrier: String?
    public var delay: String?
    /// Passenger facilities and restrictions printed beside this service by IDOS.
    public var serviceInformation: [IDOSServiceInformation]

    public init(
        id: String,
        stationName: String? = nil,
        time: String,
        lineName: String,
        lineColor: String? = nil,
        transportMode: IDOSTransportMode? = nil,
        destination: String,
        tariffZone: String? = nil,
        platform: String? = nil,
        via: String? = nil,
        carrier: String? = nil,
        delay: String? = nil,
        serviceInformation: [IDOSServiceInformation] = []
    ) {
        self.id = id
        self.stationName = stationName
        self.time = time
        self.lineName = lineName
        self.lineColor = lineColor
        self.transportMode = transportMode
        self.destination = destination
        self.tariffZone = tariffZone
        self.platform = platform
        self.via = via
        self.carrier = carrier
        self.delay = delay
        self.serviceInformation = serviceInformation
    }

    enum CodingKeys: String, CodingKey {
        case id
        case stationName
        case time
        case lineName
        case lineColor
        case transportMode
        case destination
        case tariffZone
        case platform
        case via
        case carrier
        case delay
        case serviceInformation
    }

    /// Keeps previously encoded station-board rows decodable after passenger information was added.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decode(String.self, forKey: .id),
            stationName: try container.decodeIfPresent(String.self, forKey: .stationName),
            time: try container.decode(String.self, forKey: .time),
            lineName: try container.decode(String.self, forKey: .lineName),
            lineColor: try container.decodeIfPresent(String.self, forKey: .lineColor),
            transportMode: try container.decodeIfPresent(IDOSTransportMode.self, forKey: .transportMode),
            destination: try container.decode(String.self, forKey: .destination),
            tariffZone: try container.decodeIfPresent(String.self, forKey: .tariffZone),
            platform: try container.decodeIfPresent(String.self, forKey: .platform),
            via: try container.decodeIfPresent(String.self, forKey: .via),
            carrier: try container.decodeIfPresent(String.self, forKey: .carrier),
            delay: try container.decodeIfPresent(String.self, forKey: .delay),
            serviceInformation: try container.decodeIfPresent(
                [IDOSServiceInformation].self,
                forKey: .serviceInformation
            ) ?? []
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encodeIfPresent(stationName, forKey: .stationName)
        try container.encode(time, forKey: .time)
        try container.encode(lineName, forKey: .lineName)
        try container.encodeIfPresent(lineColor, forKey: .lineColor)
        try container.encodeIfPresent(transportMode, forKey: .transportMode)
        try container.encode(destination, forKey: .destination)
        try container.encodeIfPresent(tariffZone, forKey: .tariffZone)
        try container.encodeIfPresent(platform, forKey: .platform)
        try container.encodeIfPresent(via, forKey: .via)
        try container.encodeIfPresent(carrier, forKey: .carrier)
        try container.encodeIfPresent(delay, forKey: .delay)
        if !serviceInformation.isEmpty {
            try container.encode(serviceInformation, forKey: .serviceInformation)
        }
    }

    public var displayLineName: String {
        [transportMode?.emoji, coloredLineName]
            .compactMap(\.self)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    public func summaryLine(number: Int, includeDetails: Bool = true) -> String {
        var result = "\(number). \(TerminalStyle.bold(time)) \(displayLineName) → \(destination)"

        if includeDetails {
            if let tariffZone, !tariffZone.isEmpty {
                result += " · tariff zone \(tariffZone)"
            }

            if let platform, !platform.isEmpty {
                result += " · platform \(platform)"
            }
        }

        var details: [String] = []
        if let via, !via.isEmpty {
            details.append("via \(via)")
        }
        if includeDetails {
            if let carrier, !carrier.isEmpty {
                details.append(carrier)
            }
            if let delay, !delay.isEmpty {
                details.append(delay)
            }
        }

        if !details.isEmpty {
            result += "\n   \(details.joined(separator: "\n   "))"
        }

        return result
    }

    var coloredLineName: String {
        TerminalColor.color(lineName, htmlColor: lineColor)
    }
}

/// Complete route and product information for one dated public-transport service.
public struct IDOSServiceDetail: Codable, Equatable, Sendable {
    public var id: String
    public var timetable: IDOSTimetable
    public var name: String
    public var color: String?
    public var transportMode: IDOSTransportMode?
    public var date: String?
    public var stops: [IDOSServiceStop]
    public var information: [String]
    public var shareURL: String?

    public init(
        id: String,
        timetable: IDOSTimetable = .defaultTimetable,
        name: String,
        color: String? = nil,
        transportMode: IDOSTransportMode? = nil,
        date: String? = nil,
        stops: [IDOSServiceStop],
        information: [String] = [],
        shareURL: String? = nil
    ) {
        self.id = id
        self.timetable = timetable
        self.name = name
        self.color = color
        self.transportMode = transportMode
        self.date = date
        self.stops = stops
        self.information = information
        self.shareURL = shareURL
    }

    /// Combines the transport emoji with the IDOS line color without replacing the service name.
    public var displayName: String {
        [transportMode?.emoji, TerminalColor.color(name, htmlColor: color)]
            .compactMap(\.self)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}

/// One calling point on a service's complete route as supplied by IDOS.
public struct IDOSServiceStop: Codable, Equatable, Sendable {
    public var name: String
    public var arrivalTime: String?
    public var departureTime: String?
    public var tariffZone: String?
    public var platform: String?
    public var track: String?
    public var platformTrack: String?
    public var distance: String?
    public var notes: [String]

    public init(
        name: String,
        arrivalTime: String? = nil,
        departureTime: String? = nil,
        tariffZone: String? = nil,
        platform: String? = nil,
        track: String? = nil,
        platformTrack: String? = nil,
        distance: String? = nil,
        notes: [String] = []
    ) {
        self.name = name
        self.arrivalTime = arrivalTime
        self.departureTime = departureTime
        self.tariffZone = tariffZone
        self.platform = platform
        self.track = track
        self.platformTrack = platformTrack
        self.distance = distance
        self.notes = notes
    }
}

public enum IDOSTransportMode: String, Codable, Equatable, Sendable {
    case train
    case bus
    case tram
    case metro
    case trolleybus
    case ferry
    case cableCar
    case plane
    case walk

    public var emoji: String {
        switch self {
        case .train:
            return "🚆"
        case .bus:
            return "🚌"
        case .tram:
            return "🚋"
        case .metro:
            return "🚇"
        case .trolleybus:
            return "🚎"
        case .ferry:
            return "⛴️"
        case .cableCar:
            return "🚠"
        case .plane:
            return "✈️"
        case .walk:
            return "🚶"
        }
    }

    static func infer(from text: String) -> IDOSTransportMode? {
        let normalized = text
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .lowercased()

        if normalized.contains("trolleybus") {
            return .trolleybus
        }

        if normalized.contains("cable car") || normalized.contains("cableway") || normalized.contains("funicular") {
            return .cableCar
        }

        if normalized.contains("train") ||
            normalized.contains("rail") ||
            normalized.range(of: #"\b(rj|r|rx|ex|ic|ec|sc|en|nj|os|sp|le)\s*[0-9]"#, options: .regularExpression) != nil
        {
            return .train
        }

        if normalized.contains("metro") || normalized.contains("subway") || normalized.contains("underground") {
            return .metro
        }

        if normalized.contains("tram") || normalized.contains("streetcar") {
            return .tram
        }

        if normalized.contains("bus") || normalized.hasPrefix("bus ") {
            return .bus
        }

        if normalized.contains("ferry") || normalized.contains("boat") || normalized.contains("ship") {
            return .ferry
        }

        if normalized.contains("plane") || normalized.contains("airplane") || normalized.contains("flight") {
            return .plane
        }

        if normalized.contains("walk") || normalized.contains("foot") {
            return .walk
        }

        return nil
    }
}

/// Mirrors the small JSON document returned while IDOS prepares its email attachments.
private struct IDOSShareLabelsResponse: Decodable {
    let filename: String?
    let filename2: String?
    let message: String?
    let description: String?
    let error: String?
}

/// Mirrors the delivery result returned by IDOS after an explicit send request.
private struct IDOSEmailSendResponse: Decodable {
    let errors: [String]?
}

public enum IDOSError: LocalizedError, Sendable {
    case invalidResponse
    case invalidURL
    case invalidJSONP
    case invalidTimetable(String)
    case invalidStationTimetableMunicipality(String, timetable: IDOSTimetable)
    case networkUnavailable(String)
    case emailUnavailable
    case emailSendingFailed(String)
    case calendarUnavailable
    case dateLimitsUnavailable
    case pdfUnavailable
    case stationTimetableUnavailable
    case invalidServiceIdentifier(String)
    case serviceDetailUnavailable(String)

    public var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "IDOS returned an unexpected response."
        case .invalidURL:
            return "Could not build the IDOS URL."
        case .invalidJSONP:
            return "IDOS returned an unexpected JSONP format."
        case .invalidTimetable(let value):
            return "Invalid timetable: \(value). Use an alias or a URL slug without slashes."
        case .invalidStationTimetableMunicipality(let value, let timetable):
            let available = IDOSStationTimetableMunicipality.available(for: timetable)
                .map(\.name)
                .joined(separator: ", ")
            guard !available.isEmpty else {
                return "Timetable \(timetable.displayName) does not offer a municipality choice."
            }
            return "Invalid municipality: \(value). Available for \(timetable.displayName): \(available)."
        case .networkUnavailable(let detail):
            let detail = detail.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !detail.isEmpty else {
                return "Network request failed. Check your internet connection."
            }

            return "Network request failed. Check your internet connection. \(detail)"
        case .emailUnavailable:
            return "IDOS did not provide email data for this connection."
        case .emailSendingFailed(let detail):
            let detail = detail.trimmingCharacters(in: .whitespacesAndNewlines)
            return detail.isEmpty
                ? "IDOS could not send the connection by email."
                : "IDOS could not send the connection by email. \(detail)"
        case .calendarUnavailable:
            return "IDOS did not provide calendar export data for this connection."
        case .dateLimitsUnavailable:
            return "IDOS did not provide operating-day data for this service."
        case .pdfUnavailable:
            return "IDOS did not provide PDF export data for this connection."
        case .stationTimetableUnavailable:
            return "IDOS could not generate a station timetable for this line, direction, and date."
        case .invalidServiceIdentifier(let value):
            return "Invalid service ID: \(value). Copy the complete ID from verbose connection or departure output."
        case .serviceDetailUnavailable(let detail):
            let detail = detail.trimmingCharacters(in: .whitespacesAndNewlines)
            return detail.isEmpty
                ? "IDOS could not load this service detail."
                : "IDOS could not load this service detail. \(detail)"
        }
    }
}

/// Encodes nested IDOS sharing models with the bracketed field names used by its website.
enum IDOSFormEncoding {
    static func nestedData(rootName: String, value: Any) -> Data? {
        var items: [URLQueryItem] = []
        append(value, name: rootName, to: &items)
        return data(items)
    }

    static func data(_ items: [URLQueryItem]) -> Data? {
        items.map { item in
            "\(encode(item.name))=\(encode(item.value ?? ""))"
        }
        .joined(separator: "&")
        .data(using: .utf8)
    }

    private static func append(_ value: Any, name: String, to items: inout [URLQueryItem]) {
        if let dictionary = value as? [String: Any] {
            for key in dictionary.keys.sorted() {
                guard let child = dictionary[key] else { continue }
                append(child, name: "\(name)[\(key)]", to: &items)
            }
        } else if let array = value as? [Any] {
            for (index, child) in array.enumerated() {
                append(child, name: "\(name)[\(index)]", to: &items)
            }
        } else if value is NSNull {
            items.append(URLQueryItem(name: name, value: ""))
        } else if let string = value as? String {
            items.append(URLQueryItem(name: name, value: string))
        } else if let number = value as? NSNumber {
            items.append(URLQueryItem(name: name, value: scalarString(from: number)))
        }
    }

    private static func scalarString(from number: NSNumber) -> String {
        #if canImport(CoreFoundation)
        if CFGetTypeID(number) == CFBooleanGetTypeID() {
            return number.boolValue ? "true" : "false"
        }
        #endif
        return number.stringValue
    }

    private static func encode(_ value: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }
}

private extension URLComponents {
    var requiredURL: URL {
        get throws {
            guard let url else {
                throw IDOSError.invalidURL
            }
            return url
        }
    }
}

enum IDOSJSONP {
    static func decodePayload(from data: Data) throws -> Data {
        guard let text = String(data: data, encoding: .utf8) else {
            throw IDOSError.invalidJSONP
        }

        guard let open = text.firstIndex(of: "("),
              let close = text.lastIndex(of: ")"),
              open < close
        else {
            throw IDOSError.invalidJSONP
        }

        return Data(text[text.index(after: open)..<close].utf8)
    }
}

struct IDOSConnectionPagingContext: Sendable {
    var handle: Int
    var searchDate: String
    var arrivalThere: String
    var from: String?
    var to: String?
    var searchItem: Data
    var allowPrevious: Bool
    var allowNext: Bool
    var timetable: IDOSTimetable
    var language: IDOSLanguage
    var listedIDs: [Int]
}

struct IDOSDeparturePagingContext: Sendable {
    var request: IDOSDeparturesRequest
    var language: IDOSLanguage
    var earliestCursor: Date
    var latestCursor: Date
    var listedIDs: Set<String>
}

/// Converts the complete wording behind IDOS result symbols into the shared product model.
private enum IDOSServiceInformationHTMLParser {
    static func parseTitles(in html: String) -> [IDOSServiceInformation] {
        RegexSupport.captures(
            pattern: #"\btitle="([^"]+)""#,
            in: html
        )
        .compactMap(\.first)
        .map(HTMLText.decodeEntities)
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
        .map { IDOSServiceInformation(text: $0) }
    }
}

enum IDOSConnectionParser {
    static func parse(
        html: String,
        timetable: IDOSTimetable = .defaultTimetable
    ) -> [IDOSConnection] {
        parse(html: html, result: connectionResult(from: html), timetable: timetable)
    }

    static func parse(
        html: String,
        result: [String: Any]?,
        timetable: IDOSTimetable = .defaultTimetable
    ) -> [IDOSConnection] {
        let calendarModels = calendarModels(in: html, result: result)
        let legIdentifiers = legIdentifiersByConnectionID(in: result, timetable: timetable)
        let starts = RegexSupport.matches(
            pattern: #"<div id="connectionBox-([0-9]+)""#,
            in: html
        )
        let source = html as NSString

        return starts.indices.compactMap { index in
            let start = starts[index].range.location
            let end = index + 1 < starts.count ? starts[index + 1].range.location : source.length
            let block = source.substring(with: NSRange(location: start, length: end - start))
            let id = RegexSupport.capture(pattern: #"<div id="connectionBox-([0-9]+)""#, in: block) ?? ""
            return parseConnection(
                id: id,
                block: block,
                legIdentifiers: legIdentifiers[id] ?? [],
                calendarModel: calendarModels[id]
            )
        }
    }

    static func pagingContext(html: String) -> IDOSConnectionPagingContext? {
        guard let result = connectionResult(from: html),
              let handle = integer(result["handle"]),
              let searchItem = result["searchItem"] as? [String: Any],
              let connection = searchItem["oConn"] as? [String: Any],
              let input = connection["oUserInput"] as? [String: Any],
              let searchDate = input["dtSearchDate"] as? String,
              JSONSerialization.isValidJSONObject(searchItem),
              let searchItemData = try? JSONSerialization.data(withJSONObject: searchItem)
        else {
            return nil
        }

        let from = (input["oFrom"] as? [String: Any]).flatMap(placeName)
        let to = (input["oTo"] as? [String: Any]).flatMap(placeName)
        let arrivalThere = result["arrivalThere"] as? String ?? "0001-01-01T00:00:00"

        return IDOSConnectionPagingContext(
            handle: handle,
            searchDate: searchDate,
            arrivalThere: arrivalThere,
            from: from,
            to: to,
            searchItem: searchItemData,
            allowPrevious: result["allowPrev"] as? Bool ?? true,
            allowNext: result["allowNext"] as? Bool ?? true,
            timetable: .defaultTimetable,
            language: .english,
            listedIDs: []
        )
    }

    private static func parseConnection(
        id: String,
        block: String,
        legIdentifiers: [String?],
        calendarModel: String?
    ) -> IDOSConnection? {
        let stationRows = RegexSupport.captures(
            pattern: #"<p class="reset time[^"]*"[^>]*>(.*?)</p>\s*<p class="station">(.*?)</p>"#,
            in: block,
            options: [.dotMatchesLineSeparators]
        ).map { row in
            let stationHTML = row[1]
            return (
                time: HTMLText.clean(row[0]),
                station: HTMLText.clean(RegexSupport.capture(
                    pattern: #"<strong class="name[^"]*">(.*?)</strong>"#,
                    in: stationHTML,
                    options: [.dotMatchesLineSeparators]
                ) ?? ""),
                tariffZone: titledValue(["tariff zone", "tarifní pásmo", "tarifni pasmo"], in: stationHTML),
                platform: titledValue([
                    "platform", "track", "platform/track",
                    "nástupiště", "kolej", "nástupiště/kolej", "nastupiste/kolej",
                ], in: stationHTML)
            )
        }

        guard let first = stationRows.first, let last = stationRows.last else {
            return nil
        }

        let lines = lineDetails(in: block)

        let legs = lines.indices.compactMap { index -> IDOSConnectionLeg? in
            let departureIndex = index * 2
            let arrivalIndex = departureIndex + 1

            guard stationRows.indices.contains(departureIndex),
                  stationRows.indices.contains(arrivalIndex)
            else {
                return nil
            }

            let departure = stationRows[departureIndex]
            let arrival = stationRows[arrivalIndex]
            return IDOSConnectionLeg(
                name: lines[index].name,
                id: legIdentifiers.indices.contains(index) ? legIdentifiers[index] : nil,
                color: lines[index].color,
                transportMode: lines[index].transportMode,
                departureTime: departure.time,
                fromStation: departure.station,
                fromTariffZone: departure.tariffZone,
                fromPlatform: departure.platform,
                arrivalTime: arrival.time,
                toStation: arrival.station,
                toTariffZone: arrival.tariffZone,
                toPlatform: arrival.platform,
                carrier: lines[index].carrier,
                delay: lines[index].delay,
                serviceInformation: lines[index].serviceInformation
            )
        }

        return IDOSConnection(
            id: id,
            departureTime: first.time,
            departureStation: first.station,
            arrivalTime: last.time,
            arrivalStation: last.station,
            duration: HTMLText.clean(RegexSupport.capture(
                pattern: #"(?:Overall time|Celkový čas)\s*<strong>(.*?)</strong>"#,
                in: block,
                options: [.dotMatchesLineSeparators]
            ) ?? ""),
            legs: legs,
            shareURL: HTMLText.decodeEntities(RegexSupport.capture(
                pattern: #"data-share-url="([^"]+)""#,
                in: block
            ) ?? ""),
            calendarModel: calendarModel
        )
    }

    /// Builds the same opaque service identifier that departure results expose for a specific run.
    private static func legIdentifiersByConnectionID(
        in result: [String: Any]?,
        timetable: IDOSTimetable
    ) -> [String: [String?]] {
        guard let connectionData = result?["connData"] as? [[String: Any]] else {
            return [:]
        }

        var identifiers: [String: [String?]] = [:]
        for connection in connectionData {
            guard let connectionID = connectionID(from: connection),
                  let trains = connection["trains"] as? [[String: Any]]
            else {
                continue
            }

            identifiers[connectionID] = trains.map { serviceIdentifier(from: $0, timetable: timetable) }
        }
        return identifiers
    }

    private static func serviceIdentifier(
        from train: [String: Any],
        timetable: IDOSTimetable
    ) -> String? {
        guard let timetableIndex = integer(train["ttIndex"]),
              let trainID = integer(train["train"]),
              let date = train["dateFromValue"] as? String,
              let time = train["timeFrom"] as? String,
              let dateParts = RegexSupport.captures(
                pattern: #"^(\d{4})-(\d{1,2})-(\d{1,2})"#,
                in: date
              ).first,
              let timeParts = RegexSupport.captures(
                pattern: #"^(\d{1,2}):(\d{2})(?::(\d{2}))?"#,
                in: time
              ).first,
              let year = Int(dateParts[0]),
              let month = Int(dateParts[1]),
              let day = Int(dateParts[2]),
              let hour = Int(timeParts[0]),
              let minute = Int(timeParts[1])
        else {
            return nil
        }

        let second = timeParts.indices.contains(2) ? Int(timeParts[2]) ?? 0 : 0
        let dateTime = String(
            format: "%02d.%02d.%04d %02d:%02d:%02d",
            day,
            month,
            year,
            hour,
            minute,
            second
        )
        return "\(timetable.slug):\(timetableIndex)-\(trainID)-\(dateTime)"
    }

    private static func calendarModels(in html: String, result: [String: Any]?) -> [String: String] {
        guard let result,
              let connectionData = result["connData"] as? [[String: Any]],
              let searchItem = result["searchItem"]
        else {
            return [:]
        }

        let shareURLs = shareURLsByConnectionID(in: html)
        var models: [String: String] = [:]

        for var connection in connectionData {
            guard let id = connectionID(from: connection),
                  let shareURL = shareURLs[id], !shareURL.isEmpty
            else {
                continue
            }

            connection["priceOffer"] = NSNull()
            var jsConnectionData: [String: Any] = [
                "connData": [connection],
                "searchItem": searchItem,
                "permanentUrl": shareURL,
            ]

            if let handle = result["handle"] {
                jsConnectionData["handle"] = handle
            }

            let model: [String: Any] = ["jsConnData": jsConnectionData]
            guard JSONSerialization.isValidJSONObject(model),
                  let data = try? JSONSerialization.data(withJSONObject: model, options: []),
                  let json = String(data: data, encoding: .utf8)
            else {
                continue
            }

            models[id] = json
        }

        return models
    }

    private static func connectionResult(from html: String) -> [String: Any]? {
        guard let markerRange = html.range(of: "var connResult = new Conn.ConnResult"),
              let objectStart = html[markerRange.upperBound...].firstIndex(of: "{"),
              let objectEnd = matchingBrace(in: html, startingAt: objectStart)
        else {
            return nil
        }

        let object = String(html[objectStart...objectEnd])
        guard let data = object.data(using: .utf8),
              let result = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return nil
        }

        return result
    }

    private static func matchingBrace(in text: String, startingAt start: String.Index) -> String.Index? {
        var index = start
        var depth = 0
        var quote: Character?
        var isEscaped = false

        while index < text.endIndex {
            let character = text[index]

            if let activeQuote = quote {
                if isEscaped {
                    isEscaped = false
                } else if character == "\\" {
                    isEscaped = true
                } else if character == activeQuote {
                    quote = nil
                }
            } else if character == "\"" || character == "'" {
                quote = character
            } else if character == "{" {
                depth += 1
            } else if character == "}" {
                depth -= 1
                if depth == 0 {
                    return index
                }
            }

            index = text.index(after: index)
        }

        return nil
    }

    private static func shareURLsByConnectionID(in html: String) -> [String: String] {
        let matches = RegexSupport.captures(
            pattern: #"<div id="connectionBox-([0-9]+)"[^>]*data-share-url="([^"]+)""#,
            in: html,
            options: [.dotMatchesLineSeparators]
        )

        return Dictionary(uniqueKeysWithValues: matches.map { match in
            (match[0], HTMLText.decodeEntities(match[1]))
        })
    }

    private static func connectionID(from connection: [String: Any]) -> String? {
        if let id = connection["connId"] as? Int {
            return String(id)
        }

        if let id = connection["connId"] as? String {
            return id
        }

        return nil
    }

    private static func integer(_ value: Any?) -> Int? {
        if let value = value as? Int {
            return value
        }

        if let value = value as? NSNumber {
            return value.intValue
        }

        if let value = value as? String {
            return Int(value)
        }

        return nil
    }

    private static func placeName(_ value: [String: Any]) -> String? {
        for key in ["sName", "sAdvancedName"] {
            if let name = value[key] as? String, !name.isEmpty {
                return name
            }
        }

        return nil
    }

    private static func lineDetails(in block: String) -> [(
        name: String,
        color: String?,
        transportMode: IDOSTransportMode?,
        carrier: String?,
        delay: String?,
        serviceInformation: [IDOSServiceInformation]
    )] {
        let lineBlocks = RegexSupport.matches(
            pattern: #"<div class="line-item">.*?(?=<div class="line-item">|<div class="connection-expand">|</div>\s*$)"#,
            in: block,
            options: [.dotMatchesLineSeparators]
        ).compactMap { match -> String? in
            guard let range = Range(match.range, in: block) else {
                return nil
            }

            return String(block[range])
        }
        let headingCount = RegexSupport.matches(
            pattern: #"<h3\b.*?</h3>"#,
            in: block,
            options: [.dotMatchesLineSeparators]
        ).count
        let sources = lineBlocks.count == headingCount ? lineBlocks : headingBlocks(in: block)

        return sources.compactMap { lineBlock in
            guard let heading = RegexSupport.matches(
                pattern: #"<h3\b.*?</h3>"#,
                in: lineBlock,
                options: [.dotMatchesLineSeparators]
            ).first.flatMap({ match -> String? in
                guard let range = Range(match.range, in: lineBlock) else {
                    return nil
                }
                return String(lineBlock[range])
            }) else {
                return nil
            }

            let name = RegexSupport.captures(
                pattern: #"<span>(.*?)</span>"#,
                in: heading,
                options: [.dotMatchesLineSeparators]
            )
            .last
            .map { HTMLText.clean($0[0]) }

            guard let name else {
                return nil
            }

            let title = RegexSupport.capture(
                pattern: #"\btitle="([^"]*)""#,
                in: heading
            ).map(HTMLText.decodeEntities) ?? ""

            return (
                name: name,
                color: HTMLStyle.color(from: heading),
                transportMode: IDOSTransportMode.infer(from: "\(title) \(name)"),
                carrier: carrier(in: lineBlock),
                delay: delay(in: lineBlock),
                serviceInformation: serviceInformation(in: lineBlock)
            )
        }
    }

    /// Reads only the service symbols beside a line title, excluding action, carrier, and stop tooltips.
    private static func serviceInformation(in html: String) -> [IDOSServiceInformation] {
        guard let specifications = RegexSupport.capture(
            pattern: #"<p\b[^>]*\bclass="[^"]*\bspecs\b[^"]*"[^>]*>(.*?)</p>"#,
            in: html,
            options: [.dotMatchesLineSeparators]
        ) else {
            return []
        }

        return IDOSServiceInformationHTMLParser.parseTitles(in: specifications)
    }

    private static func headingBlocks(in block: String) -> [String] {
        let headings = RegexSupport.matches(
            pattern: #"<h3\b.*?</h3>"#,
            in: block,
            options: [.dotMatchesLineSeparators]
        )
        let source = block as NSString

        return headings.indices.map { index in
            let start = headings[index].range.location
            let end = index + 1 < headings.count ? headings[index + 1].range.location : source.length
            return source.substring(with: NSRange(location: start, length: end - start))
        }
    }

    private static func carrier(in html: String) -> String? {
        RegexSupport.capture(
            pattern: #"<span class="(?:owner|operator)"><span>(.*?)</span></span>"#,
            in: html,
            options: [.dotMatchesLineSeparators]
        ).map(HTMLText.clean).flatMap(nonEmpty)
    }

    private static func delay(in html: String) -> String? {
        RegexSupport.capture(
            pattern: #"<[^>]*\bclass="[^"]*\bdelay-bubble\b[^"]*"[^>]*>(.*?)</[^>]+>"#,
            in: html,
            options: [.dotMatchesLineSeparators]
        ).map(HTMLText.clean).flatMap(nonEmpty)
    }

    private static func titledValue(_ titles: [String], in html: String) -> String? {
        for title in titles {
            if let value = RegexSupport.capture(
                pattern: #"<span\b[^>]*\btitle="\#(NSRegularExpression.escapedPattern(for: title))"[^>]*>(.*?)</span>"#,
                in: html,
                options: [.dotMatchesLineSeparators]
            ).map(HTMLText.clean), !value.isEmpty {
                return value
            }
        }

        return nil
    }

    private static func nonEmpty(_ value: String) -> String? {
        let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}

enum IDOSTimetableValidityParser {
    /// Reads the two JavaScript dates used by IDOS to constrain the selected timetable's search form.
    static func parse(html: String) -> IDOSTimetableValidity? {
        guard let values = RegexSupport.captures(
            pattern: #"Conn\.ConnFormParams\s*\(\s*new Date\([\"'](\d{1,2})/(\d{1,2})/(\d{4})[\"']\)\s*,\s*new Date\([\"'](\d{1,2})/(\d{1,2})/(\d{4})[\"']\)"#,
            in: html
        ).first,
              values.count == 6,
              let validFrom = date(month: values[0], day: values[1], year: values[2]),
              let validThrough = date(month: values[3], day: values[4], year: values[5]),
              validFrom <= validThrough
        else {
            return nil
        }

        return IDOSTimetableValidity(validFrom: validFrom, validThrough: validThrough)
    }

    private static func date(month: String, day: String, year: String) -> Date? {
        guard let month = Int(month), let day = Int(day), let year = Int(year) else {
            return nil
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Prague")!
        let components = DateComponents(
            timeZone: calendar.timeZone,
            year: year,
            month: month,
            day: day
        )
        guard let date = calendar.date(from: components) else { return nil }
        let parsed = calendar.dateComponents([.year, .month, .day], from: date)
        guard parsed.year == year, parsed.month == month, parsed.day == day else { return nil }
        return calendar.startOfDay(for: date)
    }
}

enum IDOSConnectionFormParser {
    /// Reads the timetable-combination identifier passed to IDOS's connection form JavaScript.
    static func combinationID(in html: String) -> String? {
        guard let value = RegexSupport.capture(
            pattern: #"new\s+Conn\.ConnFormParams\s*\(.*?\},\s*\d+\s*,\s*[\"'][^\"']*[\"']\s*,\s*[\"']([^\"']+)[\"']\s*,\s*[\"'][^\"']*[\"']"#,
            in: html,
            options: [.dotMatchesLineSeparators]
        ) else {
            return nil
        }
        let identifier = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return identifier.isEmpty ? nil : identifier
    }
}

enum IDOSServiceDateLimitsParser {
    /// Converts the JavaScript assignments returned by IDOS's date-restriction endpoint into civil dates.
    static func parse(script: String) -> IDOSServiceDateLimits? {
        guard let referenceValues = RegexSupport.captures(
            pattern: #"_startDay\.setFullYear\s*\(\s*(\d{4})\s*,\s*(\d{1,2})\s*,\s*(\d{1,2})\s*\)"#,
            in: script
        ).first,
              referenceValues.count == 3,
              let year = Int(referenceValues[0]),
              let zeroBasedMonth = Int(referenceValues[1]),
              let day = Int(referenceValues[2]),
              (0...11).contains(zeroBasedMonth),
              let referenceDate = date(year: year, month: zeroBasedMonth + 1, day: day),
              let monthSource = RegexSupport.capture(
                  pattern: #"_aiDateLim\s*=\s*new\s+Array\s*\((.*?)\)\s*;"#,
                  in: script,
                  options: [.dotMatchesLineSeparators]
              )
        else {
            return nil
        }

        let rawMonths = RegexSupport.captures(
            pattern: #"new\s+Array\s*\(([^()]*)\)"#,
            in: monthSource,
            options: [.dotMatchesLineSeparators]
        ).compactMap(\.first)
        guard !rawMonths.isEmpty else { return nil }

        let calendar = serviceCalendar
        guard let firstMonth = calendar.date(from: DateComponents(
            timeZone: calendar.timeZone,
            year: year,
            month: zeroBasedMonth + 1,
            day: 1
        )) else {
            return nil
        }

        var days: [IDOSServiceDateLimits.Day] = []
        for (monthOffset, rawMonth) in rawMonths.enumerated() {
            guard let month = calendar.date(byAdding: .month, value: monthOffset, to: firstMonth),
                  let dayRange = calendar.range(of: .day, in: .month, for: month)
            else {
                return nil
            }

            let rawStatuses = rawMonth.split(
                separator: ",",
                omittingEmptySubsequences: false
            )
            guard rawStatuses.count == dayRange.count else { return nil }
            let statuses = rawStatuses.compactMap { value -> IDOSServiceDateLimits.DayStatus? in
                Int(value.trimmingCharacters(in: .whitespacesAndNewlines))
                    .flatMap(IDOSServiceDateLimits.DayStatus.init(rawValue:))
            }
            guard statuses.count == rawStatuses.count else { return nil }

            for (index, status) in statuses.enumerated() {
                guard let date = calendar.date(bySetting: .day, value: index + 1, of: month) else {
                    return nil
                }
                days.append(IDOSServiceDateLimits.Day(date: date, status: status))
            }
        }

        return IDOSServiceDateLimits(referenceDate: referenceDate, days: days)
    }

    private static func date(year: Int, month: Int, day: Int) -> Date? {
        let calendar = serviceCalendar
        let components = DateComponents(
            timeZone: calendar.timeZone,
            year: year,
            month: month,
            day: day
        )
        guard let date = calendar.date(from: components) else { return nil }
        let parsed = calendar.dateComponents([.year, .month, .day], from: date)
        guard parsed.year == year, parsed.month == month, parsed.day == day else { return nil }
        return calendar.startOfDay(for: date)
    }

    private static var serviceCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = TimeZone(identifier: "Europe/Prague")!
        return calendar
    }
}

enum IDOSStationTimetableParser {
    static func parse(
        html: String,
        request: IDOSStationTimetableRequest,
        shareURL: String? = nil
    ) -> IDOSStationTimetable? {
        guard let routeHTML = RegexSupport.capture(
            pattern: #"<div class="zjr-stations">(.*?</table>)\s*</div>"#,
            in: html,
            options: [.dotMatchesLineSeparators]
        ) else {
            return nil
        }

        let stops = stopRows(in: routeHTML)
        let schedules = scheduleTables(in: html)
        guard !stops.isEmpty, !schedules.isEmpty else {
            return nil
        }

        let rawLineName = RegexSupport.capture(
            pattern: #"departures__title.*?<span[^>]*>(.*?)</span>"#,
            in: html,
            options: [.dotMatchesLineSeparators]
        ).map(HTMLText.clean) ?? request.line
        let lineName = removingLineLabel(from: rawLineName)
        let remarks = timetableRemarks(in: html, schedules: schedules)

        return IDOSStationTimetable(
            timetable: request.timetable,
            municipality: request.effectiveMunicipality,
            lineName: lineName,
            transportMode: IDOSTransportMode.infer(from: lineName),
            fromStop: request.from.trimmingCharacters(in: .whitespacesAndNewlines),
            toStop: request.to.trimmingCharacters(in: .whitespacesAndNewlines),
            stops: stops,
            schedules: schedules,
            explanations: remarks.explanations,
            notes: remarks.notes,
            isLockout: html.range(of: #"class="exception""#) != nil,
            shareURL: shareURL
        )
    }

    private static func stopRows(in html: String) -> [IDOSStationTimetableStop] {
        RegexSupport.captures(
            pattern: #"<tr\b[^>]*>(.*?)</tr>"#,
            in: html,
            options: [.dotMatchesLineSeparators]
        ).compactMap { captures in
            guard let row = captures.first else { return nil }
            let selectedName = RegexSupport.capture(
                pattern: #"<span class="bold">(.*?)</span>"#,
                in: row,
                options: [.dotMatchesLineSeparators]
            )
            let linkedName = RegexSupport.capture(
                pattern: #"<a class="fromStation"[^>]*>(.*?)</a>"#,
                in: row,
                options: [.dotMatchesLineSeparators]
            )
            guard let name = (selectedName ?? linkedName).map(HTMLText.clean), !name.isEmpty else {
                return nil
            }

            let minuteOffset = RegexSupport.capture(
                pattern: #"zjr-table__time[^>]*>(.*?)</td>"#,
                in: row,
                options: [.dotMatchesLineSeparators]
            ).map(HTMLText.clean).flatMap(Int.init)
            let tariffZone = RegexSupport.capture(
                pattern: #"<td\b[^>]*class="[^"]*\btarif\b[^"]*"[^>]*>(.*?)</td>"#,
                in: row,
                options: [.dotMatchesLineSeparators]
            ).map(HTMLText.clean).flatMap { $0.isEmpty ? nil : $0 }
            let platform = RegexSupport.capture(
                pattern: #"<span\b[^>]*\btitle="(?:platform|stanoviště)"[^>]*>(.*?)</span>"#,
                in: row,
                options: [.caseInsensitive, .dotMatchesLineSeparators]
            ).map(HTMLText.clean).map {
                $0.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines
                    .union(CharacterSet(charactersIn: "()")))
            }.flatMap { $0.isEmpty ? nil : $0 }
            let notes = RegexSupport.captures(pattern: #"\btitle="([^"]+)""#, in: row)
                .compactMap(\.first)
                .map(HTMLText.decodeEntities)
                .filter { value in
                    let normalized = value
                        .folding(
                            options: [.diacriticInsensitive, .caseInsensitive],
                            locale: Locale(identifier: "cs_CZ")
                        )
                        .lowercased()
                    return !normalized.contains("search from the station") &&
                        !normalized.contains("vyhledat ze zastavky") &&
                        normalized != "platform" &&
                        normalized != "stanoviste"
                }

            return IDOSStationTimetableStop(
                name: name,
                minuteOffset: minuteOffset,
                tariffZone: tariffZone,
                platform: platform,
                isSelected: selectedName != nil,
                notes: unique(notes)
            )
        }
    }

    private static func scheduleTables(in html: String) -> [IDOSStationTimetableSchedule] {
        RegexSupport.captures(
            pattern: #"<div class="zjr-table-container[^"]*"[^>]*>(.*?</table>)\s*</div>"#,
            in: html,
            options: [.dotMatchesLineSeparators]
        ).compactMap { captures in
            guard let table = captures.first,
                  let label = RegexSupport.capture(
                      pattern: #"<thead>.*?<th[^>]*>\s*</th>\s*<th[^>]*>(.*?)</th>"#,
                      in: table,
                      options: [.dotMatchesLineSeparators]
                  ).map(HTMLText.clean),
                  !label.isEmpty
            else {
                return nil
            }

            let hours = RegexSupport.captures(
                pattern: #"<tr\b[^>]*>\s*<td[^>]*zjr-table__date[^>]*>(.*?)</td>\s*<td[^>]*>(.*?)</td>\s*</tr>"#,
                in: table,
                options: [.dotMatchesLineSeparators]
            ).compactMap { row -> IDOSStationTimetableHour? in
                guard row.count == 2 else { return nil }
                let hour = HTMLText.clean(row[0])
                guard !hour.isEmpty else { return nil }
                let departures = HTMLText.clean(row[1])
                    .split(whereSeparator: \.isWhitespace)
                    .map(String.init)
                return IDOSStationTimetableHour(hour: hour, departures: departures)
            }
            return IDOSStationTimetableSchedule(label: label, hours: hours)
        }
    }

    private struct TimetableRemarks {
        let explanations: [String]
        let notes: [String]
    }

    /// Separates keyed explanations only when their marker occurs beside a concrete departure.
    private static func timetableRemarks(
        in html: String,
        schedules: [IDOSStationTimetableSchedule]
    ) -> TimetableRemarks {
        guard let list = RegexSupport.capture(
            pattern: #"<ul class="remarks-list">(.*?)</ul>"#,
            in: html,
            options: [.dotMatchesLineSeparators]
        ) else {
            return TimetableRemarks(explanations: [], notes: [])
        }
        let values = unique(
            RegexSupport.captures(
                pattern: #"<li\b[^>]*remarks-list__item[^>]*>(.*?)</li>"#,
                in: list,
                options: [.dotMatchesLineSeparators]
            ).compactMap { $0.first.map(HTMLText.clean) }
                .map(removingOrphanNoteSeparator)
                .filter { !$0.isEmpty }
                .filter { !isPlatformLegend($0) }
        )
        let markers = departureExplanationMarkers(in: schedules)
        var explanations: [String] = []
        var notes: [String] = []
        for value in values {
            if isDepartureExplanation(value, matching: markers) {
                explanations.append(value)
            } else {
                notes.append(value)
            }
        }
        return TimetableRemarks(explanations: explanations, notes: notes)
    }

    /// Returns every non-numeric suffix attached to a minute value, such as `A` in `35A`.
    private static func departureExplanationMarkers(
        in schedules: [IDOSStationTimetableSchedule]
    ) -> Set<String> {
        Set(
            schedules
                .flatMap(\.hours)
                .flatMap(\.departures)
                .compactMap { departure in
                    let suffix = departure.drop(while: \.isNumber)
                    let marker = String(suffix)
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    return marker.isEmpty ? nil : marker
                }
        )
    }

    /// Matches the key before a colon against annotations actually printed beside departures.
    private static func isDepartureExplanation(
        _ value: String,
        matching departureMarkers: Set<String>
    ) -> Bool {
        guard let separator = value.firstIndex(of: ":") else { return false }
        let key = value[..<separator].trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty, !key.contains(where: \.isWhitespace) else { return false }
        return departureMarkers.contains { marker in
            marker == key || marker.contains(key)
        }
    }

    /// Removes punctuation left behind when IDOS publishes a note without a visible marker.
    private static func removingOrphanNoteSeparator(_ value: String) -> String {
        value.replacingOccurrences(
            of: #"^\s*:\s*"#,
            with: "",
            options: .regularExpression
        )
    }

    /// Hides the duplicated platform legend after its number has been attached to every route stop.
    private static func isPlatformLegend(_ value: String) -> Bool {
        let normalized = value
            .folding(
                options: [.diacriticInsensitive, .caseInsensitive],
                locale: Locale(identifier: "cs_CZ")
            )
            .lowercased()
        return normalized.range(
            of: #"^\s*[^:]+:\s*(?:platform|stanoviste)\s*$"#,
            options: .regularExpression
        ) != nil
    }

    private static func removingLineLabel(from value: String) -> String {
        for prefix in ["Line ", "Linka "] where value.hasPrefix(prefix) {
            return String(value.dropFirst(prefix.count))
        }
        return value
    }

    private static func unique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.filter { seen.insert($0).inserted }
    }
}

enum IDOSDepartureParser {
    /// Recovers the full scheduled timestamp retained in every parsed departure identifier.
    static func scheduledDate(for departure: IDOSDeparture) -> Date? {
        guard let parts = RegexSupport.captures(
            pattern: #"-(\d{2})\.(\d{2})\.(\d{4}) (\d{2}):(\d{2}):(\d{2})$"#,
            in: departure.id
        ).first,
              parts.count == 6,
              let day = Int(parts[0]),
              let month = Int(parts[1]),
              let year = Int(parts[2]),
              let hour = Int(parts[3]),
              let minute = Int(parts[4]),
              let second = Int(parts[5])
        else {
            return nil
        }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Prague")!
        return calendar.date(
            from: DateComponents(
                year: year,
                month: month,
                day: day,
                hour: hour,
                minute: minute,
                second: second
            )
        )
    }

    static func parse(
        html: String,
        timetable: IDOSTimetable = .defaultTimetable
    ) -> [IDOSDeparture] {
        let stationName = resolvedStationName(in: html)

        return RegexSupport.captures(
            pattern: #"<tr class="dep-row dep-row-first"([^>]*)>(.*?)</tr>\s*<tr class="dep-row dep-row-second"[^>]*>(.*?)</tr>"#,
            in: html,
            options: [.dotMatchesLineSeparators]
        ).compactMap { row in
            parseDeparture(
                attributes: row[0],
                firstRow: row[1],
                secondRow: row[2],
                stationName: stationName,
                timetable: timetable
            )
        }
    }

    private static func parseDeparture(
        attributes: String,
        firstRow: String,
        secondRow: String,
        stationName: String?,
        timetable: IDOSTimetable
    ) -> IDOSDeparture? {
        let headings = RegexSupport.captures(
            pattern: #"<h3\b[^>]*>(.*?)</h3>"#,
            in: firstRow,
            options: [.dotMatchesLineSeparators]
        ).map { HTMLText.clean($0[0]) }

        let destination = attribute("data-stationname", in: attributes) ?? headings.first ?? ""
        let lineHTML = RegexSupport.matches(
            pattern: #"<h3\b[^>]*>.*?</h3>"#,
            in: firstRow,
            options: [.dotMatchesLineSeparators]
        ).compactMap { match -> String? in
            guard let range = Range(match.range, in: firstRow) else {
                return nil
            }

            let heading = String(firstRow[range])
            return HTMLStyle.color(from: heading) == nil ? nil : heading
        }.last ?? ""
        let lineName = lineHTML.isEmpty ? (headings.count > 1 ? headings[1] : "") : HTMLText.clean(lineHTML)
        let time = attribute("data-datetime", in: attributes)
            .flatMap(timeFromDateTime)
            ?? (headings.count > 2 ? headings[2] : "")
        let timetableIndex = attribute("data-ttindex", in: attributes)
        let trainID = attribute("data-train", in: attributes)
        let dateTime = attribute("data-datetime", in: attributes)

        guard !time.isEmpty, !lineName.isEmpty, !destination.isEmpty,
              let timetableIndex, !timetableIndex.isEmpty,
              let trainID, !trainID.isEmpty,
              let dateTime, !dateTime.isEmpty
        else {
            return nil
        }

        let platform = RegexSupport.capture(
            pattern: #"<span title="(?:platform|track|platform/track|nástupiště|kolej|nástupiště/kolej)"[^>]*>(.*?)</span>"#,
            in: firstRow,
            options: [.dotMatchesLineSeparators]
        ).map(HTMLText.clean)
        let tariffZone = detail(title: "tariff zone", in: firstRow)
            ?? detail(title: "tarifní pásmo", in: firstRow)
            ?? detail(title: "tarifni pasmo", in: firstRow)
        let via = (
            detail(title: "pass via", in: secondRow) ??
                detail(title: "projíždí přes", in: secondRow) ??
                detail(title: "projizdi pres", in: secondRow)
        ).map { value in
            for prefix in ["via ", "přes "] where value.hasPrefix(prefix) {
                return String(value.dropFirst(prefix.count))
            }
            return value
        }
        let carrier = detail(title: "dopravce", in: secondRow) ?? detail(title: "carrier", in: secondRow)
        let delay = RegexSupport.capture(
            pattern: #"<a\b[^>]*class="delay-bubble"[^>]*>(.*?)</a>"#,
            in: secondRow,
            options: [.dotMatchesLineSeparators]
        ).map(HTMLText.clean)
        let serviceInformation = serviceInformation(in: firstRow)

        return IDOSDeparture(
            id: "\(timetable.slug):\(timetableIndex)-\(trainID)-\(dateTime)",
            stationName: stationName,
            time: time,
            lineName: lineName,
            lineColor: HTMLStyle.color(from: lineHTML),
            transportMode: IDOSTransportMode.infer(from: lineName),
            destination: destination,
            tariffZone: tariffZone,
            platform: platform,
            via: via,
            carrier: carrier,
            delay: delay,
            serviceInformation: serviceInformation
        )
    }

    /// Isolates the service cell so station, platform, and destination tooltips cannot become facilities.
    private static func serviceInformation(in html: String) -> [IDOSServiceInformation] {
        guard let serviceCell = RegexSupport.capture(
            pattern: #"<span\b[^>]*\bclass="[^"]*\bdesc\b[^"]*"[^>]*>(.*?)</td>"#,
            in: html,
            options: [.dotMatchesLineSeparators]
        ) else {
            return []
        }

        return IDOSServiceInformationHTMLParser.parseTitles(in: serviceCell)
    }

    private static func resolvedStationName(in html: String) -> String? {
        if let title = RegexSupport.capture(
            pattern: #"<h2\b[^>]*class="[^"]*\bdepTitlePage\b[^"]*"[^>]*>(.*?)</h2>"#,
            in: html,
            options: [.dotMatchesLineSeparators]
        ).map(HTMLText.clean) {
            for prefix in ["Departures from ", "Arrivals to ", "Odjezdy z ", "Příjezdy do "]
                where title.hasPrefix(prefix)
            {
                let value = String(title.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
                if !value.isEmpty {
                    return value
                }
            }
        }

        return RegexSupport.capture(
            pattern: #"<input\b[^>]*\bid="From"[^>]*\bvalue="([^"]*)""#,
            in: html,
            options: [.dotMatchesLineSeparators]
        ).map(HTMLText.clean)
    }

    private static func attribute(_ name: String, in html: String) -> String? {
        RegexSupport.capture(
            pattern: #"\#(name)="([^"]*)""#,
            in: html
        ).map { HTMLText.clean($0) }
    }

    private static func detail(title: String, in html: String) -> String? {
        RegexSupport.capture(
            pattern: #"<span title="\#(title)"[^>]*>(.*?)</span>"#,
            in: html,
            options: [.dotMatchesLineSeparators]
        ).map(HTMLText.clean)
    }

    private static func timeFromDateTime(_ value: String) -> String? {
        RegexSupport.capture(pattern: #"([0-9]{1,2}:[0-9]{2})(?::[0-9]{2})?$"#, in: value)
    }
}

/// Resolves current self-contained IDs and upgrades legacy IDs with caller-supplied timetable context.
struct IDOSServiceReference {
    let id: String
    let timetable: IDOSTimetable
    let timetableIndex: Int
    let trainID: Int
    let year: Int
    let month: Int
    let day: Int
    let hour: Int
    let minute: Int

    init(id: String, fallbackTimetable: IDOSTimetable) throws {
        let value = id.trimmingCharacters(in: .whitespacesAndNewlines)
        let prefixed = RegexSupport.captures(
            pattern: #"^([A-Za-z0-9-]+):(.*)$"#,
            in: value
        ).first
        let legacyID: String
        let timetable: IDOSTimetable
        if let prefixed, prefixed.count == 2,
           let embeddedTimetable = try? IDOSTimetable.resolve(prefixed[0])
        {
            timetable = embeddedTimetable
            legacyID = prefixed[1]
        } else if prefixed == nil {
            timetable = fallbackTimetable
            legacyID = value
        } else {
            throw IDOSError.invalidServiceIdentifier(value)
        }

        guard let parts = RegexSupport.captures(
            pattern: #"^(\d+)-(\d+)-(\d{2})\.(\d{2})\.(\d{4}) (\d{2}):(\d{2}):(\d{2})$"#,
            in: legacyID
        ).first,
              parts.count == 8,
              let timetableIndex = Int(parts[0]),
              let trainID = Int(parts[1]),
              let day = Int(parts[2]),
              let month = Int(parts[3]),
              let year = Int(parts[4]),
              let hour = Int(parts[5]),
              let minute = Int(parts[6]),
              let second = Int(parts[7]),
              (0...23).contains(hour),
              (0...59).contains(minute),
              (0...59).contains(second),
              Calendar(identifier: .gregorian).date(
                from: DateComponents(year: year, month: month, day: day)
              ) != nil
        else {
            throw IDOSError.invalidServiceIdentifier(value)
        }

        self.id = "\(timetable.slug):\(legacyID)"
        self.timetable = timetable
        self.timetableIndex = timetableIndex
        self.trainID = trainID
        self.year = year
        self.month = month
        self.day = day
        self.hour = hour
        self.minute = minute
    }

    var formItems: [URLQueryItem] {
        [
            URLQueryItem(name: "ttIndex", value: String(timetableIndex)),
            URLQueryItem(name: "train", value: String(trainID)),
            URLQueryItem(name: "dateFrom", value: "\(day).\(month)."),
            URLQueryItem(
                name: "dateFromValue",
                value: String(format: "%04d-%02d-%02dT00:00:00", year, month, day)
            ),
            URLQueryItem(name: "timeFrom", value: String(format: "%02d:%02d", hour, minute)),
            URLQueryItem(name: "isDep", value: "true"),
        ]
    }
}

enum IDOSServiceDetailParser {
    static func parse(
        html: String,
        id: String,
        timetable: IDOSTimetable = .defaultTimetable,
        language: IDOSLanguage? = nil
    ) -> IDOSServiceDetail? {
        guard let heading = RegexSupport.capture(
            pattern: #"(<h1\b.*?</h1>)"#,
            in: html,
            options: [.dotMatchesLineSeparators]
        ),
              let name = RegexSupport.capture(
                pattern: #"<span>(.*?)</span>"#,
                in: heading,
                options: [.dotMatchesLineSeparators]
              ).map(HTMLText.clean).flatMap(nonEmpty)
        else {
            return nil
        }

        let stops = RegexSupport.captures(
            pattern: #"<li class="item([^"]*)"([^>]*)>(.*?)</li>"#,
            in: html,
            options: [.dotMatchesLineSeparators]
        ).compactMap { row -> IDOSServiceStop? in
            let attributes = row[1]
            let block = row[2]
            guard let stopName = RegexSupport.capture(
                pattern: #"<strong class="name">(.*?)</strong>"#,
                in: block,
                options: [.dotMatchesLineSeparators]
            ).map(HTMLText.clean).flatMap(nonEmpty) else {
                return nil
            }

            let tariffZoneTitles = [
                "tariff zone", "tarifní pásmo", "tarifní zóna", "tar. pásmo",
            ]
            let platformTitles = ["platform", "nástupiště", "stanoviště"]
            let trackTitles = ["track", "kolej"]
            let platformTrackTitles = ["platform/track", "nástupiště/kolej"]
            let knownTitles = Set(
                tariffZoneTitles + platformTitles + trackTitles + platformTrackTitles
            )
            var notes = RegexSupport.captures(
                pattern: #"\btitle="([^"]*)""#,
                in: block
            )
            .compactMap { $0.first.map(HTMLText.decodeEntities) }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter {
                !$0.isEmpty &&
                    !knownTitles.contains($0.lowercased()) &&
                    !isInteractiveVehiclePositionTitle($0)
            }

            if let title = attribute("title", in: attributes),
               !title.isEmpty,
               !isInteractiveVehiclePositionTitle(title)
            {
                notes.insert(title, at: 0)
            }

            return IDOSServiceStop(
                name: stopName,
                arrivalTime: time(className: "arrival", in: block),
                departureTime: time(className: "departure", in: block),
                tariffZone: titledValue(tariffZoneTitles, in: block),
                platform: titledValue(platformTitles, in: block),
                track: titledValue(trackTitles, in: block),
                platformTrack: titledValue(platformTrackTitles, in: block),
                distance: time(className: "distance", in: block),
                notes: unique(notes)
            )
        }

        guard !stops.isEmpty else {
            return nil
        }

        let headingTitle = attribute("title", in: heading) ?? ""
        return IDOSServiceDetail(
            id: id,
            timetable: timetable,
            name: name,
            color: HTMLStyle.color(from: heading),
            transportMode: IDOSTransportMode.infer(from: "\(headingTitle) \(name)"),
            date: RegexSupport.capture(
                pattern: #"line-top-date.*?<strong>(.*?)</strong>"#,
                in: html,
                options: [.dotMatchesLineSeparators]
            ).map(HTMLText.clean).flatMap(nonEmpty),
            stops: stops,
            information: localizedInformation(information(in: html), language: language),
            shareURL: RegexSupport.capture(
                pattern: #"\bdata-share-url="([^"]+)""#,
                in: html
            ).map(HTMLText.decodeEntities).flatMap(nonEmpty)
        )
    }

    /// Rejects IDOS tooltips for interactive vehicle tracking controls because they are not stop notes.
    private static func isInteractiveVehiclePositionTitle(_ title: String) -> Bool {
        let title = title.lowercased()
        let describesPosition = title.contains("poloha") ||
            title.contains("position") ||
            title.contains("location")
        let describesVehicle = title.contains("spoj") ||
            title.contains("vozidl") ||
            title.contains("service") ||
            title.contains("vehicle") ||
            title.contains("train")
        let describesInteraction = title.contains("klik") ||
            title.contains("aktualiz") ||
            title.contains("click") ||
            title.contains("update") ||
            title.contains("refresh")
        return describesPosition && describesVehicle && describesInteraction
    }

    private static func time(className: String, in html: String) -> String? {
        RegexSupport.capture(
            pattern: #"<span class="\#(className)">\s*<span\b[^>]*>.*?</span>\s*([^<]*?)\s*</span>"#,
            in: html,
            options: [.dotMatchesLineSeparators]
        ).map(HTMLText.clean).flatMap(nonEmpty)
    }

    private static func titledValue(_ titles: [String], in html: String) -> String? {
        titles.lazy.compactMap { title in
            RegexSupport.capture(
                pattern: #"<span\b[^>]*\btitle="\#(NSRegularExpression.escapedPattern(for: title))"[^>]*>(.*?)</span>"#,
                in: html,
                options: [.dotMatchesLineSeparators]
            ).map(HTMLText.clean).flatMap(nonEmpty)
        }.first
    }

    private static func information(in html: String) -> [String] {
        guard let start = html.range(of: #"<ul class="reset messages">"#),
              let end = html.range(of: #"<ul class="reset line-share">"#, range: start.upperBound..<html.endIndex)
        else {
            return []
        }

        let source = String(html[start.lowerBound..<end.lowerBound])
        let remarks = RegexSupport.captures(
            pattern: #"<li\b[^>]*class="[^"]*remarks-list__item[^"]*"[^>]*>(.*?)</li>"#,
            in: source,
            options: [.dotMatchesLineSeparators]
        ).compactMap { $0.first.map(HTMLText.clean).flatMap(nonEmpty) }
        let plainItems = RegexSupport.captures(
            pattern: #"<li>\s*(?!<h3\b)(.*?)</li>"#,
            in: source,
            options: [.dotMatchesLineSeparators]
        ).compactMap { $0.first.map(HTMLText.clean).flatMap(nonEmpty) }

        return unique(plainItems + remarks)
    }

    /// Prefers the requested language only when IDOS supplied a recognized Czech-English pair.
    private static func localizedInformation(
        _ values: [String],
        language: IDOSLanguage?
    ) -> [String] {
        guard let language else { return values }
        let variants = values.map(localizedInformationVariant)

        return zip(values, variants).compactMap { value, variant in
            guard let variant else { return value }
            let hasRequestedVariant = variants.contains {
                $0?.kind == variant.kind && $0?.language == language
            }
            let hasOtherVariant = variants.contains {
                $0?.kind == variant.kind && $0?.language != language
            }
            guard hasRequestedVariant && hasOtherVariant else { return value }
            return variant.language == language ? value : nil
        }
    }

    /// Recognizes equivalent carrier messages without discarding unrelated single-language information.
    private static func localizedInformationVariant(
        _ value: String
    ) -> LocalizedInformationVariant? {
        let normalized = value
            .folding(
                options: [.diacriticInsensitive, .caseInsensitive],
                locale: Locale(identifier: "en_US_POSIX")
            )
            .lowercased()

        if normalized.contains("veskere informace") {
            return LocalizedInformationVariant(kind: .generalInformation, language: .czech)
        }
        if normalized.contains("all information") {
            return LocalizedInformationVariant(kind: .generalInformation, language: .english)
        }
        if normalized.contains("povinna rezervace") && normalized.contains("tarif") {
            return LocalizedInformationVariant(kind: .reservationAndTariff, language: .czech)
        }
        if (normalized.contains("reservation required") ||
            normalized.contains("required reservation")) &&
            (normalized.contains("tariff") || normalized.contains("fare"))
        {
            return LocalizedInformationVariant(kind: .reservationAndTariff, language: .english)
        }
        return nil
    }

    private struct LocalizedInformationVariant {
        let kind: LocalizedInformationKind
        let language: IDOSLanguage
    }

    private enum LocalizedInformationKind: Equatable {
        case generalInformation
        case reservationAndTariff
    }

    private static func attribute(_ name: String, in html: String) -> String? {
        RegexSupport.capture(
            pattern: #"\#(name)="([^"]*)""#,
            in: html
        ).map(HTMLText.decodeEntities).flatMap(nonEmpty)
    }

    private static func unique(_ values: [String]) -> [String] {
        var seen: Set<String> = []
        return values.filter { seen.insert($0).inserted }
    }

    private static func nonEmpty(_ value: String) -> String? {
        let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}

private enum HTMLStyle {
    static func color(from html: String) -> String? {
        RegexSupport.capture(
            pattern: #"(?i)\bcolor\s*:\s*([^;"']+)"#,
            in: html
        )?
        .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private enum TerminalColor {
    private static let reset = "\u{001B}[0m"

    static func color(_ text: String, htmlColor: String?) -> String {
        guard !text.isEmpty,
              let htmlColor,
              let rgb = rgb(from: htmlColor)
        else {
            return text
        }

        return "\u{001B}[38;2;\(rgb.red);\(rgb.green);\(rgb.blue)m\(text)\(reset)"
    }

    private static func rgb(from htmlColor: String) -> (red: Int, green: Int, blue: Int)? {
        let color = htmlColor
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        if color.hasPrefix("#") {
            return rgbFromHex(String(color.dropFirst()))
        }

        if color.hasPrefix("rgb") {
            let components = RegexSupport.captures(
                pattern: #"rgba?\(\s*([0-9]{1,3})\s*,\s*([0-9]{1,3})\s*,\s*([0-9]{1,3})"#,
                in: color
            ).first

            guard let components,
                  components.count == 3,
                  let red = clampedColorComponent(components[0]),
                  let green = clampedColorComponent(components[1]),
                  let blue = clampedColorComponent(components[2])
            else {
                return nil
            }

            return (red, green, blue)
        }

        return nil
    }

    private static func rgbFromHex(_ hex: String) -> (red: Int, green: Int, blue: Int)? {
        switch hex.count {
        case 3:
            let expanded = hex.map { String(repeating: String($0), count: 2) }.joined()
            return rgbFromHex(expanded)
        case 6:
            guard let value = Int(hex, radix: 16) else {
                return nil
            }
            return (
                red: (value >> 16) & 0xFF,
                green: (value >> 8) & 0xFF,
                blue: value & 0xFF
            )
        default:
            return nil
        }
    }

    private static func clampedColorComponent(_ value: String) -> Int? {
        guard let component = Int(value), (0...255).contains(component) else {
            return nil
        }
        return component
    }
}

private enum TerminalStyle {
    private static let boldCode = "\u{001B}[1m"
    private static let resetCode = "\u{001B}[0m"

    static func bold(_ text: String) -> String {
        guard !text.isEmpty else {
            return text
        }

        return "\(boldCode)\(text)\(resetCode)"
    }
}

/// Normalizes typographic symbols in human-readable IDOS text without altering identifiers or URLs.
enum IDOSPresentationText {
    static func normalize(_ value: String) -> String {
        value.replacingOccurrences(of: "->", with: "→")
    }

    /// Normalizes only the labels and descriptions that can be presented from an IDOS suggestion.
    static func normalize(_ suggestion: IDOSSuggestion) -> IDOSSuggestion {
        var suggestion = suggestion
        suggestion.selectedText = suggestion.selectedText.map(normalize)
        suggestion.text = normalize(suggestion.text)
        suggestion.description = suggestion.description.map(normalize)
        suggestion.region = suggestion.region.map(normalize)
        suggestion.from = suggestion.from.map(normalize)
        suggestion.to = suggestion.to.map(normalize)
        return suggestion
    }
}

private enum HTMLText {
    static func clean(_ value: String) -> String {
        IDOSPresentationText.normalize(normalizeWhitespace(stripTags(decodeEntities(value))))
    }

    static func decodeEntities(_ value: String) -> String {
        var result = value
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&raquo;", with: "»")

        let matches = RegexSupport.matches(pattern: #"&#(x?[0-9A-Fa-f]+);"#, in: result)
        for match in matches.reversed() {
            guard match.numberOfRanges == 2,
                  let range = Range(match.range(at: 1), in: result)
            else {
                continue
            }

            let raw = String(result[range])
            let radix = raw.lowercased().hasPrefix("x") ? 16 : 10
            let digits = radix == 16 ? String(raw.dropFirst()) : raw

            guard let codepoint = UInt32(digits, radix: radix),
                  let scalar = UnicodeScalar(codepoint)
            else {
                continue
            }

            if let fullRange = Range(match.range, in: result) {
                result.replaceSubrange(fullRange, with: String(Character(scalar)))
            }
        }

        return result
    }

    private static func stripTags(_ value: String) -> String {
        RegexSupport.replace(pattern: #"<[^>]+>"#, in: value, with: "")
    }

    private static func normalizeWhitespace(_ value: String) -> String {
        RegexSupport.replace(pattern: #"\s+"#, in: value, with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private enum RegexSupport {
    static func matches(
        pattern: String,
        in text: String,
        options: NSRegularExpression.Options = []
    ) -> [NSTextCheckingResult] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else {
            return []
        }

        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
    }

    static func capture(
        pattern: String,
        in text: String,
        options: NSRegularExpression.Options = []
    ) -> String? {
        captures(pattern: pattern, in: text, options: options).first?.first
    }

    static func captures(
        pattern: String,
        in text: String,
        options: NSRegularExpression.Options = []
    ) -> [[String]] {
        matches(pattern: pattern, in: text, options: options).map { match in
            (1..<match.numberOfRanges).compactMap { index in
                guard let range = Range(match.range(at: index), in: text) else {
                    return nil
                }
                return String(text[range])
            }
        }
    }

    static func replace(pattern: String, in text: String, with replacement: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return text
        }

        return regex.stringByReplacingMatches(
            in: text,
            range: NSRange(text.startIndex..., in: text),
            withTemplate: replacement
        )
    }
}
