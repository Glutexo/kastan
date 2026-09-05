import Foundation
#if canImport(CoreFoundation)
import CoreFoundation
#endif
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// A language requested for human-readable names, notes, and messages supplied by a transit data source.
public enum TransitLanguage: String, Codable, Equatable, Sendable {
    case english = "en"
    case czech = "cs"

    /// Builds an IDOS endpoint path; Czech is the site's unprefixed default language.
    func path(timetable: TransitTimetable, endpoint: String) -> String {
        let languagePrefix = self == .english ? "/en" : ""
        return "\(languagePrefix)/\(timetable.slug)/\(endpoint)"
    }
}

/// Selects the chronological edge extended by a transit result-page request.
public enum TransitPageDirection: String, Codable, Equatable, Hashable, Sendable {
    case earlier
    case later
}

/// Carries one connection batch together with source-owned continuation state for both chronological edges.
public struct TransitConnectionPage: Sendable {
    public let connections: [TransitConnection]
    public let canLoadEarlier: Bool
    public let canLoadLater: Bool
    public let dataSourceID: TransitDataSourceID
    public let continuation: TransitPageContinuation?

    public init(
        connections: [TransitConnection],
        canLoadEarlier: Bool = false,
        canLoadLater: Bool = false,
        dataSourceID: TransitDataSourceID = .idos
    ) {
        self.connections = connections
        self.canLoadEarlier = canLoadEarlier
        self.canLoadLater = canLoadLater
        self.dataSourceID = dataSourceID
        continuation = nil
    }

    /// Retains a provider-defined continuation value without exposing it to other data sources.
    public init<Continuation: Sendable>(
        connections: [TransitConnection],
        canLoadEarlier: Bool,
        canLoadLater: Bool,
        dataSourceID: TransitDataSourceID,
        continuation: Continuation
    ) {
        self.connections = connections
        self.canLoadEarlier = canLoadEarlier
        self.canLoadLater = canLoadLater
        self.dataSourceID = dataSourceID
        self.continuation = TransitPageContinuation(continuation)
    }

    init(connections: [TransitConnection], pagingContext: IDOSConnectionPagingContext?) {
        self.connections = connections
        canLoadEarlier = pagingContext?.allowPrevious ?? false
        canLoadLater = pagingContext?.allowNext ?? false
        dataSourceID = .idos
        continuation = pagingContext.map(TransitPageContinuation.init)
    }

    var pagingContext: IDOSConnectionPagingContext? {
        continuation?.value(as: IDOSConnectionPagingContext.self)
    }
}

/// Carries one station-board batch together with source-owned continuation state for both chronological edges.
public struct TransitDeparturePage: Sendable {
    public let departures: [TransitDeparture]
    public let canLoadEarlier: Bool
    public let canLoadLater: Bool
    public let dataSourceID: TransitDataSourceID
    public let continuation: TransitPageContinuation?

    public init(
        departures: [TransitDeparture],
        canLoadEarlier: Bool = false,
        canLoadLater: Bool = false,
        dataSourceID: TransitDataSourceID = .idos
    ) {
        self.departures = departures
        self.canLoadEarlier = canLoadEarlier
        self.canLoadLater = canLoadLater
        self.dataSourceID = dataSourceID
        continuation = nil
    }

    /// Retains a provider-defined continuation value without exposing it to other data sources.
    public init<Continuation: Sendable>(
        departures: [TransitDeparture],
        canLoadEarlier: Bool,
        canLoadLater: Bool,
        dataSourceID: TransitDataSourceID,
        continuation: Continuation
    ) {
        self.departures = departures
        self.canLoadEarlier = canLoadEarlier
        self.canLoadLater = canLoadLater
        self.dataSourceID = dataSourceID
        self.continuation = TransitPageContinuation(continuation)
    }

    init(departures: [TransitDeparture], pagingContext: IDOSDeparturePagingContext?) {
        self.departures = departures
        canLoadEarlier = pagingContext != nil
        canLoadLater = pagingContext != nil
        dataSourceID = .idos
        continuation = pagingContext.map(TransitPageContinuation.init)
    }

    var pagingContext: IDOSDeparturePagingContext? {
        continuation?.value(as: IDOSDeparturePagingContext.self)
    }
}

public struct IDOSDataSource: IDOSClienting {
    public static let descriptor = TransitDataSourceDescriptor.idos
    public static let serviceTimeZone = TimeZone(identifier: "Europe/Prague")!

    public var baseURL: URL

    public var descriptor: TransitDataSourceDescriptor {
        Self.descriptor
    }

    public var serviceTimeZone: TimeZone? {
        Self.serviceTimeZone
    }

    public init(baseURL: URL = URL(string: "https://idos.cz")!) {
        self.baseURL = baseURL
    }

    /// Rejects provider-scoped values before they can be interpreted as IDOS URL identifiers.
    private func validateOwnership(of timetable: TransitTimetable) throws {
        guard timetable.dataSourceID == descriptor.id else {
            throw TransitDataSourceError.valueBelongsToDifferentSource(
                expected: descriptor.id,
                actual: timetable.dataSourceID
            )
        }
    }

    private func validateOwnership(
        of selection: TransitPlaceSelection?,
        timetable: TransitTimetable
    ) throws {
        guard let selection else { return }
        try validateOwnership(of: selection.dataSourceID)
        if let actualTimetable = selection.timetableIdentifier,
           actualTimetable != timetable.identifier {
            throw TransitDataSourceError.valueBelongsToDifferentTimetable(
                expected: timetable.identifier,
                actual: actualTimetable,
                source: descriptor.id
            )
        }
        guard IDOSPlaceIdentity.components(from: selection.identifier) != nil else {
            throw TransitDataSourceError.invalidDataSourceValue(source: descriptor)
        }
    }

    private func validateOwnership(
        of municipality: TransitStationTimetableMunicipality?,
        timetable: TransitTimetable
    ) throws {
        guard let municipality else { return }
        try validateOwnership(of: municipality.dataSourceID)
        guard municipality.timetableIdentifier == timetable.identifier else {
            throw TransitDataSourceError.valueBelongsToDifferentTimetable(
                expected: timetable.identifier,
                actual: municipality.timetableIdentifier,
                source: descriptor.id
            )
        }
        guard IDOSMunicipalityIdentity.components(from: municipality.identifier) != nil else {
            throw TransitDataSourceError.invalidDataSourceValue(source: descriptor)
        }
    }

    private func validateOwnership(
        of connection: TransitConnection,
        timetable: TransitTimetable
    ) throws {
        try validateOwnership(of: connection.dataSourceID)
        guard !connection.hasExplicitTimetableIdentifier ||
                connection.timetableIdentifier == timetable.identifier
        else {
            throw TransitDataSourceError.valueBelongsToDifferentTimetable(
                expected: timetable.identifier,
                actual: connection.timetableIdentifier,
                source: descriptor.id
            )
        }
    }

    private func validateOwnership(of departure: TransitDeparture) throws {
        try validateOwnership(of: departure.dataSourceID)
    }

    private func validateOwnership(of sourceID: TransitDataSourceID) throws {
        guard sourceID == descriptor.id else {
            throw TransitDataSourceError.valueBelongsToDifferentSource(
                expected: descriptor.id,
                actual: sourceID
            )
        }
    }

    public func suggest(prefix: String, limit: Int = 8, timetable: TransitTimetable = .defaultTimetable) async throws -> [TransitSuggestion] {
        try await searchTimetableObjects(prefix: prefix, limit: limit, timetable: timetable, onlyStation: false)
    }

    public func searchStations(prefix: String, limit: Int = 8, timetable: TransitTimetable = .defaultTimetable) async throws -> [TransitSuggestion] {
        try await searchTimetableObjects(prefix: prefix, limit: limit, timetable: timetable, onlyStation: true)
    }

    /// Suggests MHD or integrated-transport lines and includes each available terminal pair.
    public func searchStationTimetableLines(
        prefix: String,
        limit: Int = 8,
        timetable: TransitTimetable
    ) async throws -> [TransitSuggestion] {
        try await searchStationTimetableLines(
            prefix: prefix,
            limit: limit,
            timetable: timetable,
            municipality: TransitStationTimetableMunicipality.default(for: timetable)
        )
    }

    /// Suggests line directions within the municipality selected by a multi-municipality IDOS catalog.
    public func searchStationTimetableLines(
        prefix: String,
        limit: Int = 8,
        timetable: TransitTimetable,
        municipality: TransitStationTimetableMunicipality?
    ) async throws -> [TransitSuggestion] {
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
        timetable: TransitTimetable
    ) async throws -> [TransitSuggestion] {
        try await searchStationTimetableStops(
            prefix: prefix,
            line: line,
            limit: limit,
            timetable: timetable,
            municipality: TransitStationTimetableMunicipality.default(for: timetable)
        )
    }

    /// Suggests line stops within the municipality selected by a multi-municipality IDOS catalog.
    public func searchStationTimetableStops(
        prefix: String,
        line: String,
        limit: Int = 8,
        timetable: TransitTimetable,
        municipality: TransitStationTimetableMunicipality?
    ) async throws -> [TransitSuggestion] {
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
        timetable: TransitTimetable,
        onlyStation: Bool
    ) async throws -> [TransitSuggestion] {
        try validateOwnership(of: timetable)
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
        return try decodedSuggestions(from: data, timetable: timetable)
    }

    private func searchStationTimetableObjects(
        endpoint: String,
        prefix: String,
        line: String?,
        limit: Int,
        timetable: TransitTimetable,
        municipality: TransitStationTimetableMunicipality?,
        onlyStation: Bool
    ) async throws -> [TransitSuggestion] {
        try validateOwnership(of: timetable)
        try validateOwnership(of: municipality, timetable: timetable)
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
        return try decodedSuggestions(from: data, timetable: timetable)
    }

    /// Builds the municipality-aware query shared by both Station Timetable suggestion endpoints.
    static func stationTimetableSuggestionQueryItems(
        prefix: String,
        limit: Int,
        municipality: TransitStationTimetableMunicipality?,
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
    private func decodedSuggestions(
        from data: Data,
        timetable: TransitTimetable
    ) throws -> [TransitSuggestion] {
        let json = try IDOSJSONP.decodePayload(from: data)
        return try JSONDecoder().decode([TransitSuggestion].self, from: json)
            .map(IDOSPresentationText.normalize)
            .map { suggestion in
                var suggestion = suggestion
                suggestion.dataSourceID = descriptor.id
                suggestion.timetableIdentifier = timetable.identifier
                return suggestion
            }
    }

    /// Loads one IDOS station timetable for an MHD or integrated-transport line and direction.
    public func findStationTimetable(
        request: TransitStationTimetableRequest,
        language: TransitLanguage = .english
    ) async throws -> TransitStationTimetable {
        try validateOwnership(of: request.timetable)
        try validateOwnership(of: request.effectiveMunicipality, timetable: request.timetable)
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

    /// Resolves IDOS's presentation-only timetable value through the corresponding station-board query.
    public func resolveStationTimetableDeparture(
        request: TransitStationTimetableDepartureResolutionRequest,
        language: TransitLanguage = .english
    ) async throws -> TransitStationTimetableDepartureResolution? {
        let stationTimetable = request.stationTimetable
        try validateOwnership(of: stationTimetable.timetable)
        guard let selectedStop = stationTimetable.selectedStop,
              let reference = IDOSStationTimetableDepartureReference(request: request)
        else {
            return nil
        }

        for candidateDate in IDOSStationTimetableDepartureResolver.candidateServiceDates(
            for: reference.scheduleLabel,
            searchDate: request.serviceDate,
            wholeWeek: request.wholeWeek
        ) {
            guard let serviceDate = IDOSStationTimetableDepartureResolver.addingDays(
                reference.dayOffset,
                to: candidateDate
            ) else {
                continue
            }
            let departureRequest = TransitDeparturesRequest(
                timetable: stationTimetable.timetable,
                station: selectedStop.name,
                serviceDate: serviceDate,
                serviceTime: reference.serviceTime,
                isArrival: false
            )
            let page = try await findDeparturesPage(request: departureRequest, language: language)
            guard let departure = IDOSStationTimetableDepartureResolver.matchingDeparture(
                in: page.departures,
                reference: reference,
                timetable: stationTimetable
            ) else {
                continue
            }
            return TransitStationTimetableDepartureResolution(
                departure: departure,
                request: departureRequest,
                page: page,
                serviceDate: serviceDate,
                serviceTime: reference.serviceTime
            )
        }
        return nil
    }

    /// Loads the exact inclusive date range embedded in the selected IDOS search form.
    public func timetableValidity(
        for timetable: TransitTimetable,
        language: TransitLanguage = .english
    ) async throws -> TransitTimetableValidity {
        try validateOwnership(of: timetable)
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

    public func findConnections(request: TransitConnectionRequest) async throws -> [TransitConnection] {
        try await findConnectionsPage(request: request).connections
    }

    public func findConnectionsPage(request: TransitConnectionRequest) async throws -> TransitConnectionPage {
        try await findConnectionsPage(request: request, language: .english)
    }

    public func findConnectionsPage(
        request: TransitConnectionRequest,
        language: TransitLanguage
    ) async throws -> TransitConnectionPage {
        try validateOwnership(of: request.timetable)
        try validateOwnership(of: request.fromSelection, timetable: request.timetable)
        try validateOwnership(of: request.toSelection, timetable: request.timetable)
        for selection in request.viaSelections ?? [] {
            try validateOwnership(of: selection, timetable: request.timetable)
        }
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
            return TransitConnectionPage(connections: connections)
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

        return TransitConnectionPage(connections: connections, pagingContext: paging)
    }

    public func findConnectionsPage(
        from page: TransitConnectionPage,
        direction: TransitPageDirection
    ) async throws -> TransitConnectionPage {
        guard page.dataSourceID == descriptor.id else {
            throw TransitDataSourceError.pageBelongsToDifferentSource(
                expected: descriptor.id,
                actual: page.dataSourceID
            )
        }
        guard let paging = page.pagingContext else {
            return TransitConnectionPage(connections: [])
        }
        return try await connectionPage(paging: paging, direction: direction)
    }

    private func connectionPage(
        paging: IDOSConnectionPagingContext,
        direction: TransitPageDirection
    ) async throws -> TransitConnectionPage {
        let isPrevious = direction == .earlier
        guard let connectionID = isPrevious ? paging.listedIDs.first : paging.listedIDs.last else {
            return TransitConnectionPage(connections: [])
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

        return TransitConnectionPage(connections: connections, pagingContext: updatedPaging)
    }

    /// Loads the wording and attachment names IDOS will use for one connection email.
    public func connectionEmailDraft(
        for connection: TransitConnection,
        timetable: TransitTimetable = .defaultTimetable,
        language: TransitLanguage = .english
    ) async throws -> TransitConnectionEmailDraft {
        try validateOwnership(of: timetable)
        try validateOwnership(of: connection, timetable: timetable)
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
    static func connectionEmailDraft(from data: Data) throws -> TransitConnectionEmailDraft {
        guard let response = try? JSONDecoder().decode(IDOSShareLabelsResponse.self, from: data),
              response.error?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false,
              let pdfFileName = response.filename?.trimmingCharacters(in: .whitespacesAndNewlines),
              !pdfFileName.isEmpty
        else {
            throw IDOSError.emailUnavailable
        }

        let calendarFileName = response.filename2?.trimmingCharacters(in: .whitespacesAndNewlines)
        return TransitConnectionEmailDraft(
            message: response.message ?? "",
            description: response.description ?? "",
            attachmentFileNames: [pdfFileName, calendarFileName]
                .compactMap { $0 }
                .filter { !$0.isEmpty }
        )
    }

    /// Asks IDOS to deliver one connection as the same PDF and calendar attachments as its website.
    public func sendConnectionByEmail(
        _ connection: TransitConnection,
        to recipient: String,
        message: String,
        timetable: TransitTimetable = .defaultTimetable,
        language: TransitLanguage = .english
    ) async throws {
        try validateOwnership(of: timetable)
        try validateOwnership(of: connection, timetable: timetable)
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
        for connection: TransitConnection,
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
        for connection: TransitConnection,
        timetable: TransitTimetable = .defaultTimetable
    ) async throws -> String {
        try await connectionCalendar(for: connection, timetable: timetable, language: .english)
    }

    /// Loads IDOS's native calendar export with human-readable text in the selected language.
    public func connectionCalendar(
        for connection: TransitConnection,
        timetable: TransitTimetable = .defaultTimetable,
        language: TransitLanguage
    ) async throws -> String {
        try validateOwnership(of: timetable)
        try validateOwnership(of: connection, timetable: timetable)
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
    public func serviceCalendar(for service: TransitServiceDetail) async throws -> String {
        try await serviceCalendar(for: service, language: .english)
    }

    /// Resolves a dated service's permanent result and returns IDOS's calendar export in the selected language.
    public func serviceCalendar(
        for service: TransitServiceDetail,
        language: TransitLanguage
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
        for service: TransitServiceDetail,
        language: TransitLanguage = .english
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
        for connection: TransitConnection,
        timetable: TransitTimetable = .defaultTimetable,
        language: TransitLanguage = .english
    ) async throws -> Data {
        try validateOwnership(of: timetable)
        try validateOwnership(of: connection, timetable: timetable)
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

    public func findDepartures(request: TransitDeparturesRequest) async throws -> [TransitDeparture] {
        try await departureResults(request: request, language: .english)
    }

    public func findDeparturesPage(request: TransitDeparturesRequest) async throws -> TransitDeparturePage {
        try await findDeparturesPage(request: request, language: .english)
    }

    public func findDeparturesPage(
        request: TransitDeparturesRequest,
        language: TransitLanguage
    ) async throws -> TransitDeparturePage {
        try validateOwnership(of: request.timetable)
        try validateOwnership(of: request.stationSelection, timetable: request.timetable)
        let departures = Array(
            try await departureResults(request: request, language: language).prefix(20)
        )
        let dates = departures.compactMap { IDOSDepartureParser.scheduledDate(for: $0) }
        guard let earliest = dates.min(), let latest = dates.max() else {
            return TransitDeparturePage(departures: departures)
        }

        let paging = IDOSDeparturePagingContext(
            request: request,
            language: language,
            earliestCursor: earliest,
            latestCursor: latest,
            listedIDs: Set(departures.map(\.id))
        )
        return TransitDeparturePage(departures: departures, pagingContext: paging)
    }

    public func findDeparturesPage(
        from page: TransitDeparturePage,
        direction: TransitPageDirection
    ) async throws -> TransitDeparturePage {
        guard page.dataSourceID == descriptor.id else {
            throw TransitDataSourceError.pageBelongsToDifferentSource(
                expected: descriptor.id,
                actual: page.dataSourceID
            )
        }
        guard var paging = page.pagingContext else {
            return TransitDeparturePage(departures: [])
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

        return TransitDeparturePage(departures: departures, pagingContext: paging)
    }

    private func departureResults(
        request: TransitDeparturesRequest,
        language: TransitLanguage
    ) async throws -> [TransitDeparture] {
        try validateOwnership(of: request.timetable)
        try validateOwnership(of: request.stationSelection, timetable: request.timetable)
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
        _ original: TransitDeparturesRequest,
        at date: Date
    ) -> TransitDeparturesRequest {
        var request = original
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Prague")!
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        request.serviceDate = TransitDate(
            year: components.year ?? 1,
            month: components.month ?? 1,
            day: components.day ?? 1
        )
        request.serviceTime = TransitTime(
            hour: components.hour ?? 0,
            minute: components.minute ?? 0
        )
        return request
    }

    /// Loads a complete route; `timetable` is used only when a legacy ID lacks embedded context.
    public func serviceDetail(
        id: String,
        timetable: TransitTimetable = .defaultTimetable
    ) async throws -> TransitServiceDetail {
        try await serviceDetail(id: id, timetable: timetable, language: .english)
    }

    /// Loads a complete route in the selected IDOS language; `timetable` is only a legacy-ID fallback.
    public func serviceDetail(
        id: String,
        timetable: TransitTimetable = .defaultTimetable,
        language: TransitLanguage
    ) async throws -> TransitServiceDetail {
        try validateOwnership(of: timetable)
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
        for service: TransitServiceDetail,
        language: TransitLanguage = .english
    ) async throws -> TransitServiceDateLimits {
        try validateOwnership(of: service.timetable)
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
        for service: TransitServiceDetail,
        unavailableError: IDOSError
    ) async throws -> TransitConnection {
        try validateOwnership(of: service.timetable)
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

/// An exact provider-owned place selected from suggestions or represented by geographic coordinates.
///
/// The opaque identifier is interpreted only by the data source that created it. Supplying this
/// value with a request distinguishes an exact stop or place from free text without exposing the
/// provider's transport representation to application code.
public struct TransitPlaceSelection: Codable, Equatable, Sendable {
    /// The provider that owns `identifier`.
    public var dataSourceID: TransitDataSourceID
    /// The provider-owned timetable in which this exact selection can be used, when known.
    public var timetableIdentifier: String?
    /// An opaque identifier meaningful only to `dataSourceID`.
    public var identifier: String
    /// Text placed into the visible search field after selection.
    public var text: String
    /// Whether this selection follows the user's live location across timetable changes.
    public var isCurrentLocation: Bool

    /// Builds a provider-neutral exact selection without imposing IDOS wire fields.
    public init(
        dataSourceID: TransitDataSourceID,
        timetableIdentifier: String? = nil,
        identifier: String,
        text: String,
        isCurrentLocation: Bool = false
    ) {
        self.dataSourceID = dataSourceID
        self.timetableIdentifier = timetableIdentifier
        self.identifier = identifier
        self.text = text
        self.isCurrentLocation = isCurrentLocation
    }

    /// Preserves the historical IDOS initializer.
    public init(text: String, listID: String, itemID: String) {
        self.init(
            dataSourceID: .idos,
            identifier: IDOSPlaceIdentity.identifier(listID: listID, itemID: itemID),
            text: text,
            isCurrentLocation: itemID == "myPosition=true" && listID.hasPrefix("loc:")
        )
    }

    public init?(suggestion: TransitSuggestion) {
        guard let identifier = suggestion.identifier else {
            return nil
        }

        self.init(
            dataSourceID: suggestion.dataSourceID,
            timetableIdentifier: suggestion.hasExplicitTimetableIdentifier
                ? suggestion.timetableIdentifier
                : nil,
            identifier: identifier,
            text: suggestion.selectedText ?? suggestion.text
        )
    }

    /// Historical IDOS convenience retained for source compatibility.
    ///
    /// Provider-neutral callers use `TransitDataSource.coordinatePlaceSelection` so the selected source owns
    /// coordinate encoding and can explicitly advertise whether it supports this operation.
    public static func currentLocation(
        text: String,
        latitude: Double,
        longitude: Double,
        timetableIdentifier: String? = nil
    ) -> Self {
        Self(
            dataSourceID: .idos,
            timetableIdentifier: timetableIdentifier,
            identifier: IDOSPlaceIdentity.identifier(
                listID: "loc: \(coordinate(latitude)); \(coordinate(longitude))",
                itemID: "myPosition=true"
            ),
            text: text,
            isCurrentLocation: true
        )
    }

    /// The historical IDOS catalog marker, retained for source compatibility.
    public var listID: String {
        get {
            IDOSPlaceIdentity.components(from: identifier)?.listID ?? ""
        }
        set {
            let itemID = self.itemID
            dataSourceID = .idos
            identifier = IDOSPlaceIdentity.identifier(listID: newValue, itemID: itemID)
            isCurrentLocation = itemID == "myPosition=true" && newValue.hasPrefix("loc:")
        }
    }

    /// The historical IDOS item marker, retained for source compatibility.
    public var itemID: String {
        get {
            IDOSPlaceIdentity.components(from: identifier)?.itemID ?? ""
        }
        set {
            let listID = self.listID
            dataSourceID = .idos
            identifier = IDOSPlaceIdentity.identifier(listID: listID, itemID: newValue)
            isCurrentLocation = newValue == "myPosition=true" && listID.hasPrefix("loc:")
        }
    }

    private static func coordinate(_ value: Double) -> String {
        String(format: "%.6f", locale: Locale(identifier: "en_US_POSIX"), value)
    }

    private enum CodingKeys: String, CodingKey {
        case dataSourceID
        case timetableIdentifier
        case identifier
        case text
        case isCurrentLocation
        case listID
        case itemID
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let text = try container.decode(String.self, forKey: .text)
        let dataSourceID = try container.decodeIfPresent(TransitDataSourceID.self, forKey: .dataSourceID) ?? .idos
        let timetableIdentifier = try container.decodeIfPresent(String.self, forKey: .timetableIdentifier)
        if let identifier = try container.decodeIfPresent(String.self, forKey: .identifier) {
            self.init(
                dataSourceID: dataSourceID,
                timetableIdentifier: timetableIdentifier,
                identifier: identifier,
                text: text,
                isCurrentLocation: try container.decodeIfPresent(Bool.self, forKey: .isCurrentLocation) ?? false
            )
        } else {
            self.init(
                text: text,
                listID: try container.decode(String.self, forKey: .listID),
                itemID: try container.decode(String.self, forKey: .itemID)
            )
            self.timetableIdentifier = timetableIdentifier
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(text, forKey: .text)
        try container.encodeIfPresent(timetableIdentifier, forKey: .timetableIdentifier)
        if dataSourceID == .idos, let components = IDOSPlaceIdentity.components(from: identifier) {
            try container.encode(components.listID, forKey: .listID)
            try container.encode(components.itemID, forKey: .itemID)
        } else {
            try container.encode(dataSourceID, forKey: .dataSourceID)
            try container.encode(identifier, forKey: .identifier)
            try container.encode(isCurrentLocation, forKey: .isCurrentLocation)
        }
    }
}

private enum IDOSPlaceIdentity {
    private static let separator = "\u{1F}"

    static func identifier(listID: String, itemID: String) -> String {
        listID + separator + itemID
    }

    static func components(from identifier: String) -> (listID: String, itemID: String)? {
        guard let separatorIndex = identifier.firstIndex(of: Character(separator)) else { return nil }
        return (
            String(identifier[..<separatorIndex]),
            String(identifier[identifier.index(after: separatorIndex)...])
        )
    }

    static func formValue(for selection: TransitPlaceSelection) -> String? {
        guard selection.dataSourceID == .idos,
              let components = components(from: selection.identifier)
        else { return nil }
        // IDOS omits the visible label only for its coordinate-backed `My location` object.
        if selection.isCurrentLocation {
            return "\(components.listID)%\(components.itemID)"
        }
        return "\(selection.text)%\(components.listID)%\(components.itemID)"
    }
}

private extension TransitDate {
    /// Translates a provider-neutral civil date only at the IDOS transport boundary.
    var idosRequestValue: String {
        String(format: "%d.%d.%04d", day, month, year)
    }
}

private extension TransitTime {
    /// Translates a provider-neutral local time only at the IDOS transport boundary.
    var idosRequestValue: String {
        String(format: "%02d:%02d", hour, minute)
    }
}

public struct TransitDeparturesRequest: Codable, Equatable, Sendable {
    public var timetable: TransitTimetable
    public var station: String
    /// An exact autocomplete choice, or `nil` when `station` should be interpreted as free text.
    public var stationSelection: TransitPlaceSelection?
    /// An IDOS-formatted date retained for source compatibility; new providers should use `serviceDate`.
    public var date: String?
    /// An IDOS-formatted time retained for source compatibility; new providers should use `serviceTime`.
    public var time: String?
    /// The provider-neutral civil date requested by the caller.
    public var serviceDate: TransitDate?
    /// The provider-neutral local time requested by the caller.
    public var serviceTime: TransitTime?
    public var isArrival: Bool

    public init(
        timetable: TransitTimetable = .defaultTimetable,
        station: String,
        stationSelection: TransitPlaceSelection? = nil,
        date: String? = nil,
        time: String? = nil,
        serviceDate: TransitDate? = nil,
        serviceTime: TransitTime? = nil,
        isArrival: Bool = false
    ) {
        self.timetable = timetable
        self.station = station
        self.stationSelection = stationSelection
        self.date = date
        self.time = time
        self.serviceDate = serviceDate
        self.serviceTime = serviceTime
        self.isArrival = isArrival
    }

    var formItems: [URLQueryItem] {
        var items = [
            URLQueryItem(name: "From", value: station),
            URLQueryItem(name: "FromHidden", value: stationSelection.flatMap(IDOSPlaceIdentity.formValue) ?? "%0"),
            URLQueryItem(name: "IsArr", value: isArrival ? "True" : "False"),
        ]

        if let date = serviceDate?.idosRequestValue ?? date {
            items.append(URLQueryItem(name: "Date", value: date))
        }

        if let time = serviceTime?.idosRequestValue ?? time {
            items.append(URLQueryItem(name: "Time", value: time))
        }

        items.append(URLQueryItem(name: "submit", value: "true"))
        return items
    }
}

/// Selects one provider-owned municipality inside a Station Timetable catalog.
public struct TransitStationTimetableMunicipality: Codable, Equatable, Hashable, Sendable {
    public var dataSourceID: TransitDataSourceID
    /// The provider-owned timetable in which this municipality can be used.
    public var timetableIdentifier: String
    /// Opaque municipality identifier interpreted only by `dataSourceID`.
    public var identifier: String
    /// Municipality name presented to the user.
    public var name: String

    public init(
        dataSourceID: TransitDataSourceID,
        timetableIdentifier: String,
        identifier: String,
        name: String
    ) {
        self.dataSourceID = dataSourceID
        self.timetableIdentifier = timetableIdentifier
        self.identifier = identifier
        self.name = name
    }

    /// Preserves the historical IDOS initializer.
    public init(name: String, timetableIndex: Int, timetableName: String) {
        self.init(
            dataSourceID: .idos,
            timetableIdentifier: IDOSMunicipalityIdentity.timetableIdentifier(for: timetableName)
                ?? TransitTimetable.defaultTimetable.identifier,
            identifier: IDOSMunicipalityIdentity.identifier(index: timetableIndex, name: timetableName),
            name: name
        )
    }

    /// The historical IDOS catalog index, retained for source compatibility.
    public var timetableIndex: Int {
        get {
            IDOSMunicipalityIdentity.components(from: identifier)?.index ?? 0
        }
        set {
            let timetableName = self.timetableName
            dataSourceID = .idos
            identifier = IDOSMunicipalityIdentity.identifier(index: newValue, name: timetableName)
        }
    }

    /// The historical IDOS URL identifier, retained for source compatibility.
    public var timetableName: String {
        get {
            IDOSMunicipalityIdentity.components(from: identifier)?.name ?? identifier
        }
        set {
            let timetableIndex = self.timetableIndex
            dataSourceID = .idos
            timetableIdentifier = IDOSMunicipalityIdentity.timetableIdentifier(for: newValue)
                ?? TransitTimetable.defaultTimetable.identifier
            identifier = IDOSMunicipalityIdentity.identifier(index: timetableIndex, name: newValue)
        }
    }

    /// Returns the municipalities published within a supported multi-municipality timetable.
    public static func available(for timetable: TransitTimetable) -> [Self] {
        guard timetable.dataSourceID == .idos else { return [] }
        return switch timetable.slug {
        case "odis":
            odisMunicipalities
        case "iredo":
            iredoMunicipalities
        case "idol":
            idolMunicipalities
        case "idsok":
            idsokMunicipalities
        case "duk":
            dukMunicipalities
        case "idpk":
            idpkMunicipalities
        case "idzk":
            idzkMunicipalities
        case "ideska":
            ideskaMunicipalities
        default:
            []
        }
    }

    /// Returns the municipality selected initially by IDOS for the given timetable.
    public static func `default`(for timetable: TransitTimetable) -> Self? {
        let timetableName: String
        switch timetable.slug {
        case "odis":
            timetableName = "ODIS"
        case "iredo":
            timetableName = "DvurKral"
        case "idol":
            timetableName = "CeskaLipa"
        case "idsok":
            timetableName = "Hranice"
        case "duk":
            timetableName = "UL"
        case "idpk":
            timetableName = "Plzen"
        case "idzk":
            timetableName = "UherskeHradiste"
        case "ideska":
            timetableName = "CesBud"
        default:
            return nil
        }
        return available(for: timetable).first { $0.timetableName == timetableName }
    }

    /// Resolves a displayed municipality name or its opaque IDOS identifier, defaulting like IDOS when omitted.
    public static func resolve(_ value: String?, timetable: TransitTimetable) throws -> Self? {
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

    private enum CodingKeys: String, CodingKey {
        case dataSourceID
        case timetableIdentifier
        case identifier
        case name
        case timetableIndex
        case timetableName
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let name = try container.decode(String.self, forKey: .name)
        let sourceID = try container.decodeIfPresent(TransitDataSourceID.self, forKey: .dataSourceID) ?? .idos
        let timetableIdentifier = try container.decodeIfPresent(String.self, forKey: .timetableIdentifier)
        if let identifier = try container.decodeIfPresent(String.self, forKey: .identifier) {
            guard let timetableIdentifier = timetableIdentifier ?? (sourceID == .idos
                ? TransitTimetable.defaultTimetable.identifier
                : nil)
            else {
                throw DecodingError.keyNotFound(
                    CodingKeys.timetableIdentifier,
                    DecodingError.Context(
                        codingPath: container.codingPath,
                        debugDescription: "A provider-owned municipality requires its timetable identifier."
                    )
                )
            }
            self.init(
                dataSourceID: sourceID,
                timetableIdentifier: timetableIdentifier,
                identifier: identifier,
                name: name
            )
        } else {
            self.init(
                name: name,
                timetableIndex: try container.decode(Int.self, forKey: .timetableIndex),
                timetableName: try container.decode(String.self, forKey: .timetableName)
            )
            if let timetableIdentifier {
                self.timetableIdentifier = timetableIdentifier
            }
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        if dataSourceID == .idos, let components = IDOSMunicipalityIdentity.components(from: identifier) {
            try container.encode(components.index, forKey: .timetableIndex)
            try container.encode(components.name, forKey: .timetableName)
            if timetableIdentifier != IDOSMunicipalityIdentity.timetableIdentifier(for: components.name) {
                try container.encode(timetableIdentifier, forKey: .timetableIdentifier)
            }
        } else {
            try container.encode(dataSourceID, forKey: .dataSourceID)
            try container.encode(timetableIdentifier, forKey: .timetableIdentifier)
            try container.encode(identifier, forKey: .identifier)
        }
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

    /// Mirrors the complete municipality chooser currently published by the IREDO Station Timetable form.
    private static let iredoMunicipalities: [Self] = [
        Self(name: "Dvůr Králové nad Labem", timetableIndex: 2, timetableName: "DvurKral"),
        Self(name: "Chrudim", timetableIndex: 3, timetableName: "Chrudim"),
        Self(name: "Náchod", timetableIndex: 4, timetableName: "Nachod"),
        Self(name: "Přelouč", timetableIndex: 5, timetableName: "Prelouc"),
        Self(name: "Rychnov nad Kněžnou", timetableIndex: 6, timetableName: "RychnovNadKneznou"),
        Self(name: "Týniště nad Orlicí", timetableIndex: 7, timetableName: "TynisteNadOrlici"),
        Self(name: "Vrchlabí", timetableIndex: 8, timetableName: "Vrchlabi"),
    ]

    /// Mirrors the complete municipality chooser currently published by the IDOL Station Timetable form.
    private static let idolMunicipalities: [Self] = [
        Self(name: "Česká Lípa", timetableIndex: 2, timetableName: "CeskaLipa"),
        Self(name: "Jablonec nad Nisou", timetableIndex: 3, timetableName: "Jablonec"),
        Self(name: "Liberec", timetableIndex: 4, timetableName: "Liberec"),
        Self(name: "Turnov", timetableIndex: 5, timetableName: "Turnov"),
    ]

    /// Mirrors the complete municipality chooser currently published by the IDSOK Station Timetable form.
    private static let idsokMunicipalities: [Self] = [
        Self(name: "Hranice", timetableIndex: 2, timetableName: "Hranice"),
        Self(name: "Olomouc", timetableIndex: 3, timetableName: "Olomouc"),
        Self(name: "Prostějov", timetableIndex: 5, timetableName: "Prostej"),
        Self(name: "Přerov", timetableIndex: 4, timetableName: "Prerov"),
        Self(name: "Šumperk", timetableIndex: 6, timetableName: "Sumperk"),
        Self(name: "Zábřeh", timetableIndex: 7, timetableName: "Zabreh"),
    ]

    /// Mirrors the complete municipality chooser currently published by the DÚK Station Timetable form.
    private static let dukMunicipalities: [Self] = [
        Self(name: "Bílina", timetableIndex: 8, timetableName: "Bilina"),
        Self(name: "Děčín", timetableIndex: 5, timetableName: "DC"),
        Self(name: "Chomutov", timetableIndex: 3, timetableName: "Chomutov"),
        Self(name: "Klášterec nad Ohří", timetableIndex: 9, timetableName: "KlasterecNadOhri"),
        Self(name: "Most-Litvínov", timetableIndex: 6, timetableName: "Most"),
        Self(name: "Roudnice nad Labem", timetableIndex: 7, timetableName: "RoudniceNadLabem"),
        Self(name: "Teplice", timetableIndex: 4, timetableName: "Teplice"),
        Self(name: "Ústí nad Labem", timetableIndex: 2, timetableName: "UL"),
        Self(name: "Varnsdorf", timetableIndex: 10, timetableName: "Varnsdorf"),
    ]

    /// Mirrors the complete municipality chooser currently published by the IDPK Station Timetable form.
    private static let idpkMunicipalities: [Self] = [
        Self(name: "Domažlice", timetableIndex: 3, timetableName: "DO"),
        Self(name: "Klatovy", timetableIndex: 4, timetableName: "KT"),
        Self(name: "Plzeň", timetableIndex: 2, timetableName: "Plzen"),
        Self(name: "Rokycany", timetableIndex: 5, timetableName: "Rokycany"),
        Self(name: "Stříbro", timetableIndex: 6, timetableName: "Stribro"),
        Self(name: "Tachov", timetableIndex: 7, timetableName: "Tachov"),
    ]

    /// Mirrors the complete municipality chooser currently published by the IDZK Station Timetable form.
    private static let idzkMunicipalities: [Self] = [
        Self(name: "Uherské Hradiště", timetableIndex: 2, timetableName: "UherskeHradiste"),
        Self(name: "Vsetín", timetableIndex: 3, timetableName: "Vsetin"),
    ]

    /// Mirrors the complete municipality chooser currently published by the IDESKA Station Timetable form.
    private static let ideskaMunicipalities: [Self] = [
        Self(name: "České Budějovice", timetableIndex: 2, timetableName: "CesBud"),
        Self(name: "Český Krumlov", timetableIndex: 3, timetableName: "CeskyKrumlov"),
        Self(name: "Jindřichův Hradec", timetableIndex: 4, timetableName: "JinHrad"),
        Self(name: "Milevsko", timetableIndex: 5, timetableName: "Milevsko"),
        Self(name: "Písek", timetableIndex: 6, timetableName: "Pisek"),
        Self(name: "Strakonice", timetableIndex: 7, timetableName: "Strakon"),
        Self(name: "Tábor", timetableIndex: 8, timetableName: "Tabor"),
        Self(name: "Vimperk", timetableIndex: 9, timetableName: "Vimperk"),
    ]
}

private enum IDOSMunicipalityIdentity {
    private static let separator = "\u{1F}"

    static func identifier(index: Int, name: String) -> String {
        String(index) + separator + name
    }

    static func components(from identifier: String) -> (index: Int, name: String)? {
        guard let separatorIndex = identifier.firstIndex(of: Character(separator)),
              let index = Int(identifier[..<separatorIndex])
        else { return nil }
        return (index, String(identifier[identifier.index(after: separatorIndex)...]))
    }

    /// Recovers the owning catalog from the historical IDOS municipality name stored in persisted values.
    static func timetableIdentifier(for municipalityName: String) -> String? {
        switch municipalityName {
        case "Bruntal", "CesTes", "FM", "Havirov", "Karvina", "Krnov", "NJ", "Opava",
             "Orlova", "ODIS", "Studenka", "Trinec":
            "odis"
        case "DvurKral", "Chrudim", "Nachod", "Prelouc", "RychnovNadKneznou",
             "TynisteNadOrlici", "Vrchlabi":
            "iredo"
        case "CeskaLipa", "Jablonec", "Liberec", "Turnov":
            "idol"
        case "Hranice", "Olomouc", "Prostej", "Prerov", "Sumperk", "Zabreh":
            "idsok"
        case "Bilina", "DC", "Chomutov", "KlasterecNadOhri", "Most", "RoudniceNadLabem",
             "Teplice", "UL", "Varnsdorf":
            "duk"
        case "DO", "KT", "Plzen", "Rokycany", "Stribro", "Tachov":
            "idpk"
        case "UherskeHradiste", "Vsetin":
            "idzk"
        case "CesBud", "CeskyKrumlov", "JinHrad", "Milevsko", "Pisek", "Strakon", "Tabor",
             "Vimperk":
            "ideska"
        default:
            nil
        }
    }
}

/// A station-timetable query for one MHD or integrated-transport line and direction.
public struct TransitStationTimetableRequest: Codable, Equatable, Sendable {
    public var timetable: TransitTimetable
    /// Narrows a multi-municipality integrated timetable to one local network.
    public var municipality: TransitStationTimetableMunicipality?
    public var line: String
    public var from: String
    public var to: String
    /// An IDOS-formatted date retained for source compatibility; new providers should use `serviceDate`.
    public var date: String?
    /// The provider-neutral civil date requested by the caller.
    public var serviceDate: TransitDate?
    public var wholeWeek: Bool

    public init(
        timetable: TransitTimetable,
        municipality: TransitStationTimetableMunicipality? = nil,
        line: String,
        from: String,
        to: String,
        date: String? = nil,
        serviceDate: TransitDate? = nil,
        wholeWeek: Bool = false
    ) {
        self.timetable = timetable
        self.municipality = municipality
        self.line = line
        self.from = from
        self.to = to
        self.date = date
        self.serviceDate = serviceDate
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
        if let date = serviceDate?.idosRequestValue ?? date, !date.isEmpty {
            items.insert(URLQueryItem(name: "date", value: date), at: 0)
        }
        if wholeWeek {
            items.append(URLQueryItem(name: "wholeweek", value: "true"))
        }
        items.append(URLQueryItem(name: "submit", value: "true"))
        return items
    }

    /// Applies the same initial municipality as IDOS when a multi-municipality timetable omits one.
    var effectiveMunicipality: TransitStationTimetableMunicipality? {
        municipality ?? TransitStationTimetableMunicipality.default(for: timetable)
    }
}

/// A complete IDOS station timetable with its route, hourly departures, keyed explanations, and notes.
public struct TransitStationTimetable: Codable, Equatable, Sendable {
    public var timetable: TransitTimetable
    /// Identifies the local network selected inside a multi-municipality timetable.
    public var municipality: TransitStationTimetableMunicipality?
    public var lineName: String
    public var transportMode: TransitTransportMode?
    public var fromStop: String
    public var toStop: String
    public var stops: [TransitStationTimetableStop]
    public var schedules: [TransitStationTimetableSchedule]
    /// Explains markers such as `A` that IDOS appends to individual departures.
    public var explanations: [String]
    /// Preserves timetable-wide information that is not tied to an individual departure marker.
    public var notes: [String]
    /// Identifies a temporary lockout timetable marked by IDOS.
    public var isLockout: Bool
    public var shareURL: String?

    public init(
        timetable: TransitTimetable,
        municipality: TransitStationTimetableMunicipality? = nil,
        lineName: String,
        transportMode: TransitTransportMode? = nil,
        fromStop: String,
        toStop: String,
        stops: [TransitStationTimetableStop],
        schedules: [TransitStationTimetableSchedule],
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

    public var selectedStop: TransitStationTimetableStop? {
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
            timetable: try container.decode(TransitTimetable.self, forKey: .timetable),
            municipality: try container.decodeIfPresent(
                TransitStationTimetableMunicipality.self,
                forKey: .municipality
            ),
            lineName: try container.decode(String.self, forKey: .lineName),
            transportMode: try container.decodeIfPresent(
                TransitTransportMode.self,
                forKey: .transportMode
            ),
            fromStop: try container.decode(String.self, forKey: .fromStop),
            toStop: try container.decode(String.self, forKey: .toStop),
            stops: try container.decode([TransitStationTimetableStop].self, forKey: .stops),
            schedules: try container.decode(
                [TransitStationTimetableSchedule].self,
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
public struct TransitStationTimetableStop: Codable, Equatable, Sendable {
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
public struct TransitStationTimetableSchedule: Codable, Equatable, Sendable {
    public var label: String
    public var hours: [TransitStationTimetableHour]

    public init(label: String, hours: [TransitStationTimetableHour]) {
        self.label = label
        self.hours = hours
    }
}

/// Every minute marker supplied by IDOS for one hour, including attached note symbols.
public struct TransitStationTimetableHour: Codable, Equatable, Sendable {
    public var hour: String
    public var departures: [String]

    public init(hour: String, departures: [String]) {
        self.hour = hour
        self.departures = departures
    }
}

/// Retains the IDOS-specific meaning encoded in one rendered station-timetable value.
struct IDOSStationTimetableDepartureReference {
    let scheduleLabel: String
    let serviceTime: TransitTime
    let dayOffset: Int
    let occurrence: Int

    init?(request: TransitStationTimetableDepartureResolutionRequest) {
        let timetable = request.stationTimetable
        guard timetable.schedules.indices.contains(request.scheduleIndex) else { return nil }
        let schedule = timetable.schedules[request.scheduleIndex]
        guard schedule.hours.indices.contains(request.hourIndex),
              schedule.hours[request.hourIndex].departures.indices.contains(request.departureIndex),
              let hour = Int(schedule.hours[request.hourIndex].hour),
              (0...23).contains(hour)
        else {
            return nil
        }

        let value = schedule.hours[request.hourIndex].departures[request.departureIndex]
        let minuteText = value.prefix(while: \.isNumber)
        guard let minute = Int(minuteText), (0...59).contains(minute) else { return nil }

        scheduleLabel = schedule.label
        serviceTime = TransitTime(hour: hour, minute: minute)
        dayOffset = Self.dayOffset(forHourAt: request.hourIndex, in: schedule.hours)
        occurrence = schedule.hours[request.hourIndex].departures[..<request.departureIndex].filter {
            Int($0.prefix(while: \.isNumber)) == minute
        }.count
    }

    /// Treats a decreasing IDOS hour sequence as the following day of the same service timetable.
    private static func dayOffset(
        forHourAt requestedIndex: Int,
        in hours: [TransitStationTimetableHour]
    ) -> Int {
        var previousHour: Int?
        var offset = 0
        for hour in hours.prefix(requestedIndex + 1).compactMap({ Int($0.hour) }) {
            if let previousHour, hour < previousHour {
                offset += 1
            }
            previousHour = hour
        }
        return offset
    }
}

/// Contains the IDOS text and matching heuristics behind its opt-in resolution capability.
enum IDOSStationTimetableDepartureResolver {
    private static var civilCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_GB")
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        calendar.firstWeekday = 2
        calendar.minimumDaysInFirstWeek = 4
        return calendar
    }

    static func addingDays(_ days: Int, to date: TransitDate) -> TransitDate? {
        let calendar = civilCalendar
        guard let value = date.date(in: calendar),
              let result = calendar.date(byAdding: .day, value: days, to: value)
        else {
            return nil
        }
        return TransitDate(result, calendar: calendar)
    }

    /// Chooses the searched day directly, or the nearest IDOS weekday group inside its Monday-first week.
    static func candidateServiceDates(
        for scheduleLabel: String,
        searchDate: TransitDate,
        wholeWeek: Bool
    ) -> [TransitDate] {
        let calendar = civilCalendar
        guard let searchDay = searchDate.date(in: calendar) else { return [] }
        guard wholeWeek,
              let week = calendar.dateInterval(of: .weekOfYear, for: searchDay)
        else {
            return [searchDate]
        }

        let allowedWeekdays = weekdays(in: scheduleLabel)
        return (0..<7).compactMap { offset -> Date? in
            guard let date = calendar.date(byAdding: .day, value: offset, to: week.start),
                  allowedWeekdays?.contains(calendar.component(.weekday, from: date)) ?? true
            else {
                return nil
            }
            return date
        }.sorted { lhs, rhs in
            let lhsDistance = abs(calendar.dateComponents([.day], from: searchDay, to: lhs).day ?? 0)
            let rhsDistance = abs(calendar.dateComponents([.day], from: searchDay, to: rhs).day ?? 0)
            if lhsDistance != rhsDistance {
                return lhsDistance < rhsDistance
            }
            return lhs >= searchDay && rhs < searchDay
        }.map { TransitDate($0, calendar: calendar) }
    }

    /// Applies IDOS's line, direction, time, and duplicate-order rules to station-board results.
    static func matchingDeparture(
        in departures: [TransitDeparture],
        reference: IDOSStationTimetableDepartureReference,
        timetable: TransitStationTimetable
    ) -> TransitDeparture? {
        let line = normalizedLineName(timetable.lineName)
        let candidates = departures.filter { departure in
            guard let time = normalizedTime(departure.time) else { return false }
            return departure.dataSourceID == timetable.timetable.dataSourceID &&
                departure.timetableIdentifier == timetable.timetable.identifier &&
                time == reference.serviceTime &&
                normalizedLineName(departure.lineName) == line
        }
        guard !candidates.isEmpty else { return nil }

        let destination = normalizedStopName(timetable.toStop)
        let directedCandidates = candidates.filter { departure in
            let candidateDestination = normalizedStopName(departure.destination)
            let candidateVia = normalizedStopName(departure.via ?? "")
            return candidateDestination == destination ||
                (!destination.isEmpty && candidateVia.contains(destination))
        }
        let preferred = directedCandidates.isEmpty ? candidates : directedCandidates
        if preferred.count == 1 {
            return preferred[0]
        }
        guard preferred.indices.contains(reference.occurrence) else { return nil }
        return preferred[reference.occurrence]
    }

    private static let weekdayNames: [(weekday: Int, names: [String])] = [
        (2, ["monday", "pondeli"]),
        (3, ["tuesday", "utery"]),
        (4, ["wednesday", "streda"]),
        (5, ["thursday", "ctvrtek"]),
        (6, ["friday", "patek"]),
        (7, ["saturday", "sobota"]),
        (1, ["sunday", "nedele"]),
    ]

    private static func weekdays(in label: String) -> Set<Int>? {
        let value = normalizedText(label)
        if ["workday", "workdays", "working day", "working days", "pracovni den", "pracovni dny"]
            .contains(where: value.contains)
        {
            return [2, 3, 4, 5, 6]
        }

        let matches = weekdayNames.compactMap { weekday, names -> (Int, String.Index)? in
            names.compactMap { value.range(of: $0)?.lowerBound }.min().map { (weekday, $0) }
        }.sorted { $0.1 < $1.1 }
        guard !matches.isEmpty else { return nil }

        if matches.count == 2 {
            let separator = value[matches[0].1..<matches[1].1]
            if separator.contains("-") || separator.contains("–") || separator.contains("—") ||
                separator.contains(" to ") || separator.contains(" az ")
            {
                var weekdays = Set<Int>()
                var weekday = matches[0].0
                for _ in 0..<7 {
                    weekdays.insert(weekday)
                    if weekday == matches[1].0 { break }
                    weekday = weekday == 7 ? 1 : weekday + 1
                }
                return weekdays
            }
        }
        return Set(matches.map(\.0))
    }

    private static func normalizedTime(_ value: String) -> TransitTime? {
        let parts = value.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count >= 2,
              let hour = Int(parts[0]),
              let minute = Int(parts[1]),
              (0...23).contains(hour),
              (0...59).contains(minute)
        else {
            return nil
        }
        return TransitTime(hour: hour, minute: minute)
    }

    private static func normalizedLineName(_ value: String) -> String {
        var normalized = normalizedText(value)
        for prefix in ["line ", "linka "] where normalized.hasPrefix(prefix) {
            normalized.removeFirst(prefix.count)
        }
        return normalized.filter { $0.isLetter || $0.isNumber }
    }

    private static func normalizedStopName(_ value: String) -> String {
        normalizedText(value).filter { $0.isLetter || $0.isNumber }
    }

    private static func normalizedText(_ value: String) -> String {
        value
            .folding(
                options: [.diacriticInsensitive, .caseInsensitive],
                locale: Locale(identifier: "cs_CZ")
            )
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

public struct TransitConnectionRequest: Codable, Equatable, Sendable {
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

    public var timetable: TransitTimetable
    public var from: String
    public var to: String
    /// An exact autocomplete choice, or `nil` when `from` should be interpreted as free text.
    public var fromSelection: TransitPlaceSelection?
    /// An exact autocomplete choice, or `nil` when `to` should be interpreted as free text.
    public var toSelection: TransitPlaceSelection?
    /// An IDOS-formatted date retained for source compatibility; new providers should use `serviceDate`.
    public var date: String?
    /// An IDOS-formatted time retained for source compatibility; new providers should use `serviceTime`.
    public var time: String?
    /// The provider-neutral civil date requested by the caller.
    public var serviceDate: TransitDate?
    /// The provider-neutral local time requested by the caller.
    public var serviceTime: TransitTime?
    public var isArrival: Bool
    public var onlyDirect: Bool
    public var via: [String]
    /// Exact autocomplete choices aligned with `via`, with `nil` entries retaining free-text interpretation.
    public var viaSelections: [TransitPlaceSelection?]?
    /// The maximum number of transfers permitted, including zero, or `nil` for the IDOS default.
    public var maxTransfers: Int?
    /// The minimum transfer time in minutes, with `-1` selecting the timetable's standard transfer time.
    public var minimumTransferTime: Int?
    /// The maximum transfer time in minutes, or `nil` for the IDOS default.
    public var maximumTransferTime: Int?
    /// The maximum walking-transfer duration in minutes, or `nil` for the IDOS default.
    public var maximumWalkingTime: Int?
    /// The maximum walking-transfer duration when Urban Public Transport is available, in minutes.
    public var maximumCityWalkingTime: Int?
    /// Whether a journey may begin or end at a nearby stop reached on foot.
    public var walkToNearbyStops: Bool?
    /// Whether walking transfers are limited to stops with the same name.
    public var sameNameWalkingTransfersOnly: Bool?
    /// Whether results are limited to connections advertised as wheelchair accessible.
    public var wheelchairAccessibleConnectionsOnly: Bool?
    /// Whether results are limited to connections served by low-floor vehicles.
    public var lowFloorConnectionsOnly: Bool?
    /// Whether train connections are preferred over bus alternatives.
    public var preferTrainsOverBuses: Bool?
    /// Whether train results are limited to connections suitable for wheelchair passengers.
    public var trainConnectionsForWheelchairPassengers: Bool?
    /// Whether train results are limited to connections suitable for passengers with children.
    public var trainConnectionsForPassengersWithChildren: Bool?
    /// Whether train and bus results are limited to connections that carry bicycles.
    public var connectionsForPassengersWithBicycles: Bool?
    /// Whether routes served more frequently are preferred.
    public var preferBusyRoutes: Bool?
    public var resultLimit: Int?

    public init(
        timetable: TransitTimetable = .defaultTimetable,
        from: String,
        to: String,
        fromSelection: TransitPlaceSelection? = nil,
        toSelection: TransitPlaceSelection? = nil,
        date: String? = nil,
        time: String? = nil,
        serviceDate: TransitDate? = nil,
        serviceTime: TransitTime? = nil,
        isArrival: Bool = false,
        onlyDirect: Bool = false,
        via: [String] = [],
        viaSelections: [TransitPlaceSelection?]? = nil,
        maxTransfers: Int? = nil,
        minimumTransferTime: Int? = nil,
        maximumTransferTime: Int? = nil,
        maximumWalkingTime: Int? = nil,
        maximumCityWalkingTime: Int? = nil,
        walkToNearbyStops: Bool? = nil,
        sameNameWalkingTransfersOnly: Bool? = nil,
        wheelchairAccessibleConnectionsOnly: Bool? = nil,
        lowFloorConnectionsOnly: Bool? = nil,
        preferTrainsOverBuses: Bool? = nil,
        trainConnectionsForWheelchairPassengers: Bool? = nil,
        trainConnectionsForPassengersWithChildren: Bool? = nil,
        connectionsForPassengersWithBicycles: Bool? = nil,
        preferBusyRoutes: Bool? = nil,
        resultLimit: Int? = nil
    ) {
        self.timetable = timetable
        self.from = from
        self.to = to
        self.fromSelection = fromSelection
        self.toSelection = toSelection
        self.date = date
        self.time = time
        self.serviceDate = serviceDate
        self.serviceTime = serviceTime
        self.isArrival = isArrival
        self.onlyDirect = onlyDirect
        self.via = via
        self.viaSelections = viaSelections
        self.maxTransfers = maxTransfers
        self.minimumTransferTime = minimumTransferTime
        self.maximumTransferTime = maximumTransferTime
        self.maximumWalkingTime = maximumWalkingTime
        self.maximumCityWalkingTime = maximumCityWalkingTime
        self.walkToNearbyStops = walkToNearbyStops
        self.sameNameWalkingTransfersOnly = sameNameWalkingTransfersOnly
        self.wheelchairAccessibleConnectionsOnly = wheelchairAccessibleConnectionsOnly
        self.lowFloorConnectionsOnly = lowFloorConnectionsOnly
        self.preferTrainsOverBuses = preferTrainsOverBuses
        self.trainConnectionsForWheelchairPassengers = trainConnectionsForWheelchairPassengers
        self.trainConnectionsForPassengersWithChildren = trainConnectionsForPassengersWithChildren
        self.connectionsForPassengersWithBicycles = connectionsForPassengersWithBicycles
        self.preferBusyRoutes = preferBusyRoutes
        self.resultLimit = resultLimit
    }

    var formItems: [URLQueryItem] {
        var items = [
            URLQueryItem(name: "From", value: from),
            URLQueryItem(name: "FromHidden", value: fromSelection.flatMap(IDOSPlaceIdentity.formValue) ?? "%0"),
            URLQueryItem(name: "To", value: to),
            URLQueryItem(name: "ToHidden", value: toSelection.flatMap(IDOSPlaceIdentity.formValue) ?? "%0"),
            URLQueryItem(name: "IsArr", value: isArrival ? "True" : "False"),
        ]

        if let date = serviceDate?.idosRequestValue ?? date {
            items.append(URLQueryItem(name: "Date", value: date))
        }

        if let time = serviceTime?.idosRequestValue ?? time {
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
                    value: selection.flatMap(IDOSPlaceIdentity.formValue) ?? ""
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
            items.append(URLQueryItem(
                name: "AdvancedForm.MaxTime",
                value: String(maximumTransferTime ?? Self.defaultMaximumTransferTime)
            ))
            items.append(URLQueryItem(
                name: "AdvancedForm.MaxArcLength",
                value: String(maximumWalkingTime ?? Self.defaultMaximumWalkingTime)
            ))
            items.append(URLQueryItem(
                name: "AdvancedForm.MaxArcLengthCity",
                value: String(maximumCityWalkingTime ?? Self.defaultMaximumCityWalkingTime)
            ))

            if let walkToNearbyStops {
                items.append(URLQueryItem(
                    name: "AdvancedForm.MaxArcLengthFrom",
                    value: String(walkToNearbyStops)
                ))
            }

            if let sameNameWalkingTransfersOnly {
                items.append(URLQueryItem(
                    name: "AdvancedForm.LimitWalkArcs",
                    value: String(sameNameWalkingTransfersOnly)
                ))
            }

            if let wheelchairAccessibleConnectionsOnly {
                items.append(URLQueryItem(
                    name: "AdvancedForm.LowDeckConn",
                    value: String(wheelchairAccessibleConnectionsOnly)
                ))
            }

            if let lowFloorConnectionsOnly {
                items.append(URLQueryItem(
                    name: "AdvancedForm.LowDeckConnTr",
                    value: String(lowFloorConnectionsOnly)
                ))
            }

            if let preferTrainsOverBuses {
                items.append(URLQueryItem(
                    name: "AdvancedForm.PrefereTrains",
                    value: String(preferTrainsOverBuses)
                ))
            }

            if let trainConnectionsForWheelchairPassengers {
                items.append(URLQueryItem(
                    name: "AdvancedForm.WheelChair",
                    value: String(trainConnectionsForWheelchairPassengers)
                ))
            }

            if let trainConnectionsForPassengersWithChildren {
                items.append(URLQueryItem(
                    name: "AdvancedForm.Children",
                    value: String(trainConnectionsForPassengersWithChildren)
                ))
            }

            if let connectionsForPassengersWithBicycles {
                items.append(URLQueryItem(
                    name: "AdvancedForm.Bicycle",
                    value: String(connectionsForPassengersWithBicycles)
                ))
            }

            if let preferBusyRoutes {
                items.append(URLQueryItem(
                    name: "AdvancedForm.AutoStrategy",
                    value: String(preferBusyRoutes)
                ))
            }

            for transportTypeID in Self.defaultTransportTypeIDs {
                let value = String(transportTypeID)
                items.append(URLQueryItem(name: "trTypeId[\(value)]", value: value))
            }
        }

        items.append(URLQueryItem(name: "submit", value: "true"))
        return items
    }

    private var hasAdvancedOptions: Bool {
        !via.isEmpty || maxTransfers != nil || minimumTransferTime != nil ||
            maximumTransferTime != nil || maximumWalkingTime != nil ||
            maximumCityWalkingTime != nil || walkToNearbyStops != nil ||
            sameNameWalkingTransfersOnly != nil ||
            wheelchairAccessibleConnectionsOnly != nil ||
            lowFloorConnectionsOnly != nil || preferTrainsOverBuses != nil ||
            trainConnectionsForWheelchairPassengers != nil ||
            trainConnectionsForPassengersWithChildren != nil ||
            connectionsForPassengersWithBicycles != nil || preferBusyRoutes != nil
    }
}

/// Identifies one provider-owned timetable catalog without assuming how its identifier is transported.
public struct TransitTimetable: Codable, Equatable, Sendable {
    public var dataSourceID: TransitDataSourceID
    public var slug: String
    public var displayName: String

    /// Provider-neutral spelling of the legacy IDOS `slug` property.
    public var identifier: String {
        get { slug }
        set { slug = newValue }
    }

    /// Preserves the historical IDOS initializer and its encoded representation.
    public init(slug: String, displayName: String) {
        dataSourceID = .idos
        self.slug = slug
        self.displayName = displayName
    }

    public init(
        dataSourceID: TransitDataSourceID,
        identifier: String,
        displayName: String
    ) {
        self.dataSourceID = dataSourceID
        slug = identifier
        self.displayName = displayName
    }

    private enum CodingKeys: String, CodingKey {
        case dataSourceID
        case slug
        case displayName
    }

    /// Treats values encoded before multi-source support as IDOS-owned.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            dataSourceID: try container.decodeIfPresent(
                TransitDataSourceID.self,
                forKey: .dataSourceID
            ) ?? .idos,
            identifier: try container.decode(String.self, forKey: .slug),
            displayName: try container.decode(String.self, forKey: .displayName)
        )
    }

    /// Keeps existing IDOS JSON byte-for-byte compatible while namespacing other providers.
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        if dataSourceID != .idos {
            try container.encode(dataSourceID, forKey: .dataSourceID)
        }
        try container.encode(slug, forKey: .slug)
        try container.encode(displayName, forKey: .displayName)
    }

    public static let defaultTimetable = TransitTimetable(slug: "vlakyautobusymhdvse", displayName: "All timetables")

    public static var known: [TransitTimetable] {
        baseTimetables + mhdNames
            .map { name in
                TransitTimetable(
                    slug: mhdSlugOverrides[name] ?? slugify(name),
                    displayName: "Urban Public Transport \(name)"
                )
            }
    }

    private static let baseTimetables: [TransitTimetable] = [
        .defaultTimetable,
        TransitTimetable(slug: "vlakyautobusymhd", displayName: "Trains + Buses + Urban Public Transport"),
        TransitTimetable(slug: "vlaky", displayName: "Trains"),
        TransitTimetable(slug: "autobusy", displayName: "Buses"),
        TransitTimetable(slug: "vlakyautobusy", displayName: "Trains + Buses"),
        TransitTimetable(slug: "pid", displayName: "Prague + PID"),
        TransitTimetable(slug: "idsjmk", displayName: "IDS JMK / Brno"),
        TransitTimetable(slug: "odis", displayName: "ODIS"),
        TransitTimetable(slug: "idol", displayName: "IDOL"),
        TransitTimetable(slug: "idsok", displayName: "IDSOK"),
        TransitTimetable(slug: "iredo", displayName: "IREDO"),
        TransitTimetable(slug: "duk", displayName: "DÚK"),
        TransitTimetable(slug: "idpk", displayName: "IDPK"),
        TransitTimetable(slug: "idzk", displayName: "IDZK"),
        TransitTimetable(slug: "ideska", displayName: "IDESKA"),
    ]

    public static func resolve(_ value: String?) throws -> TransitTimetable {
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

        return TransitTimetable(slug: customSlug, displayName: customSlug)
    }

    private static func aliases() -> [String: TransitTimetable] {
        var aliases: [String: TransitTimetable] = [
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

    /// Preserves the shorter URL slugs published by IDOS when they cannot be derived from the visible city name.
    private static let mhdSlugOverrides: [String: String] = [
        "Brandýs n.L.-St.Bol.": "brandys",
        "Bystřice nad Pernštejnem": "bystrice",
        "Dvůr Králové n. L.": "dvurkralove",
        "Jablonec nad Nisou": "jablonec",
        "Kralupy nad Vltavou": "kralupy",
        "Most a Litvínov": "most",
        "Roudnice nad Labem": "roudnice",
        "Rychnov nad Kněžnou": "rychnov",
        "Zlín a Otrokovice": "zlin",
    ]

    /// Mirrors the complete standalone Urban Public Transport catalog currently published by IDOS.
    private static let mhdNames = [
        "Ostrava",
        "Adamov",
        "Aš",
        "Benešov",
        "Bílina",
        "Blansko",
        "Brandýs n.L.-St.Bol.",
        "Bruntál",
        "Bystřice nad Pernštejnem",
        "Břeclav",
        "Česká Lípa",
        "České Budějovice",
        "Český Krumlov",
        "Český Těšín",
        "Děčín",
        "Domažlice",
        "Duchcov",
        "Dvůr Králové n. L.",
        "Frýdek-Místek",
        "Havířov",
        "Havlíčkův Brod",
        "Hodonín",
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
        "Kostelec nad Orlicí",
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
        "Milevsko",
        "Mladá Boleslav",
        "Mníšek pod Brdy",
        "Most a Litvínov",
        "Náchod",
        "Nové Město na Moravě",
        "Nový Jičín",
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
        "Příbram",
        "Rokycany",
        "Roudnice nad Labem",
        "Rychnov nad Kněžnou",
        "Říčany",
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
        "Ústí nad Orlicí",
        "Valašské Meziříčí",
        "Varnsdorf",
        "Velké Meziříčí",
        "Vimperk",
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

/// The inclusive first and last civil service dates published by a transit timetable.
public struct TransitTimetableValidity: Codable, Equatable, Sendable {
    public var validFrom: Date
    public var validThrough: Date
    /// The provider zone in which the absolute compatibility dates represent civil service days.
    public var timeZoneIdentifier: String?

    /// Retains the original absolute-date initializer for source compatibility.
    public init(validFrom: Date, validThrough: Date) {
        self.validFrom = validFrom
        self.validThrough = validThrough
        timeZoneIdentifier = IDOSDataSource.serviceTimeZone.identifier
    }

    /// Associates the compatibility dates with the provider's civil service-day zone.
    public init(validFrom: Date, validThrough: Date, timeZone: TimeZone) {
        self.validFrom = validFrom
        self.validThrough = validThrough
        timeZoneIdentifier = timeZone.identifier
    }

    public var timeZone: TimeZone? {
        timeZoneIdentifier.flatMap(TimeZone.init(identifier:))
    }

    public var validFromServiceDate: TransitDate {
        TransitDate(validFrom, calendar: serviceCalendar)
    }

    public var validThroughServiceDate: TransitDate {
        TransitDate(validThrough, calendar: serviceCalendar)
    }

    private var serviceCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone ?? .current
        return calendar
    }

    private enum CodingKeys: String, CodingKey {
        case validFrom
        case validThrough
        case timeZoneIdentifier
    }

    /// Treats payloads written before provider zones existed as historical IDOS values.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let timeZone: TimeZone
        if let identifier = try container.decodeIfPresent(String.self, forKey: .timeZoneIdentifier) {
            guard let decodedTimeZone = TimeZone(identifier: identifier) else {
                throw DecodingError.dataCorruptedError(
                    forKey: .timeZoneIdentifier,
                    in: container,
                    debugDescription: "Invalid transit service time-zone identifier: \(identifier)"
                )
            }
            timeZone = decodedTimeZone
        } else {
            timeZone = IDOSDataSource.serviceTimeZone
        }
        self.init(
            validFrom: try container.decode(Date.self, forKey: .validFrom),
            validThrough: try container.decode(Date.self, forKey: .validThrough),
            timeZone: timeZone
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(validFrom, forKey: .validFrom)
        try container.encode(validThrough, forKey: .validThrough)
        if timeZoneIdentifier != IDOSDataSource.serviceTimeZone.identifier {
            try container.encode(timeZoneIdentifier, forKey: .timeZoneIdentifier)
        }
    }
}

/// Exact operating states returned by a data source for one service.
public struct TransitServiceDateLimits: Codable, Equatable, Sendable {
    /// Preserves the provider's three-state answer without inferring missing days from prose.
    public enum DayStatus: Int, Codable, Equatable, Sendable {
        case doesNotRun = 0
        case runs = 1
        case informationUnavailable = 2
    }

    /// Associates one civil service date with the state published by the provider.
    public struct Day: Codable, Equatable, Sendable {
        public var date: Date
        public var status: DayStatus

        public init(date: Date, status: DayStatus) {
            self.date = date
            self.status = status
        }
    }

    /// The reference day with which the provider anchors its returned calendar interval.
    public var referenceDate: Date
    /// Every day supplied by the provider, ordered chronologically.
    public var days: [Day]
    /// The provider zone in which the absolute compatibility dates represent civil service days.
    public var timeZoneIdentifier: String?

    /// Retains the historical IDOS initializer and its Prague civil-day normalization.
    public init(referenceDate: Date, days: [Day]) {
        self.init(
            referenceDate: referenceDate,
            days: days,
            timeZone: IDOSDataSource.serviceTimeZone
        )
    }

    /// Normalizes absolute compatibility dates in the provider's explicit civil service-day zone.
    public init(referenceDate: Date, days: [Day], timeZone: TimeZone) {
        timeZoneIdentifier = timeZone.identifier
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = timeZone
        self.referenceDate = calendar.startOfDay(for: referenceDate)
        self.days = days
            .map { Day(date: calendar.startOfDay(for: $0.date), status: $0.status) }
            .sorted { $0.date < $1.date }
    }

    public var timeZone: TimeZone? {
        timeZoneIdentifier.flatMap(TimeZone.init(identifier:))
    }

    public var referenceServiceDate: TransitDate {
        TransitDate(referenceDate, calendar: serviceCalendar)
    }

    /// The first civil date for which the provider returned a state.
    public var firstDate: Date? {
        days.first?.date
    }

    /// The last civil date for which the provider returned a state.
    public var lastDate: Date? {
        days.last?.date
    }

    public var firstServiceDate: TransitDate? {
        firstDate.map { TransitDate($0, calendar: serviceCalendar) }
    }

    public var lastServiceDate: TransitDate? {
        lastDate.map { TransitDate($0, calendar: serviceCalendar) }
    }

    /// Returns only a state explicitly supplied by the provider; dates outside the response remain absent.
    public func status(on date: Date) -> DayStatus? {
        let date = serviceCalendar.startOfDay(for: date)
        return days.first(where: { $0.date == date })?.status
    }

    /// Looks up a civil service date without first interpreting it in the device time zone.
    public func status(on serviceDate: TransitDate) -> DayStatus? {
        guard let date = serviceDate.date(in: serviceCalendar) else { return nil }
        return status(on: date)
    }

    private var serviceCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = timeZone ?? .current
        return calendar
    }

    private enum CodingKeys: String, CodingKey {
        case referenceDate
        case days
        case timeZoneIdentifier
    }

    /// Treats payloads written before provider zones existed as historical IDOS values.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let referenceDate = try container.decode(Date.self, forKey: .referenceDate)
        let days = try container.decode([Day].self, forKey: .days)
        let decodedIdentifier = try container.decodeIfPresent(String.self, forKey: .timeZoneIdentifier)
        let timeZone: TimeZone
        if let decodedIdentifier {
            guard let decodedTimeZone = TimeZone(identifier: decodedIdentifier) else {
                throw DecodingError.dataCorruptedError(
                    forKey: .timeZoneIdentifier,
                    in: container,
                    debugDescription: "Invalid transit service time-zone identifier: \(decodedIdentifier)"
                )
            }
            timeZone = decodedTimeZone
        } else {
            timeZone = IDOSDataSource.serviceTimeZone
        }
        self.init(referenceDate: referenceDate, days: days, timeZone: timeZone)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(referenceDate, forKey: .referenceDate)
        try container.encode(days, forKey: .days)
        if timeZoneIdentifier != IDOSDataSource.serviceTimeZone.identifier {
            try container.encode(timeZoneIdentifier, forKey: .timeZoneIdentifier)
        }
    }
}

/// Tracks whether a timetable namespace came from persisted data without changing public value equality.
private struct TransitTimetableIdentityScope: Equatable, Sendable {
    let isExplicit: Bool

    static let explicit = Self(isExplicit: true)
    static let legacyUnscoped = Self(isExplicit: false)

    static func == (lhs: Self, rhs: Self) -> Bool {
        true
    }
}

/// Accepts an absent timetable namespace only for historical IDOS payloads, which had no source field either.
private func decodedTimetableIdentifier<Key: CodingKey>(
    _ identifier: String?,
    dataSourceID: TransitDataSourceID,
    key: Key,
    codingPath: [any CodingKey]
) throws -> String {
    if let identifier {
        return identifier
    }
    guard dataSourceID == .idos else {
        throw DecodingError.keyNotFound(
            key,
            DecodingError.Context(
                codingPath: codingPath,
                debugDescription: "A provider-owned transit value requires its timetable identifier."
            )
        )
    }
    return TransitTimetable.defaultTimetable.identifier
}

public struct TransitSuggestion: Codable, Equatable, Sendable {
    /// The provider that owns `identifier`.
    public var dataSourceID: TransitDataSourceID
    /// The provider-owned timetable in which the suggestion can be used.
    public var timetableIdentifier: String {
        didSet { timetableIdentityScope = .explicit }
    }
    private var timetableIdentityScope: TransitTimetableIdentityScope
    var hasExplicitTimetableIdentifier: Bool { timetableIdentityScope.isExplicit }
    /// An opaque exact-selection identifier, or `nil` for informational suggestions.
    public var identifier: String?
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
        dataSourceID: TransitDataSourceID = .idos,
        timetableIdentifier: String = TransitTimetable.defaultTimetable.identifier,
        identifier: String? = nil,
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
        self.dataSourceID = dataSourceID
        self.timetableIdentifier = timetableIdentifier
        timetableIdentityScope = .explicit
        self.identifier = identifier ?? {
            guard dataSourceID == .idos, let value, let value2 else { return nil }
            return IDOSPlaceIdentity.identifier(listID: value, itemID: value2)
        }()
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

    private enum CodingKeys: String, CodingKey {
        case dataSourceID
        case timetableIdentifier
        case identifier
        case selectedText
        case text
        case description
        case region
        case value
        case value2
        case iconId
        case coorX
        case coorY
        case from
        case to
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let dataSourceID = try container.decodeIfPresent(TransitDataSourceID.self, forKey: .dataSourceID) ?? .idos
        let timetableIdentifier = try container.decodeIfPresent(String.self, forKey: .timetableIdentifier)
        self.init(
            dataSourceID: dataSourceID,
            timetableIdentifier: try decodedTimetableIdentifier(
                timetableIdentifier,
                dataSourceID: dataSourceID,
                key: CodingKeys.timetableIdentifier,
                codingPath: container.codingPath
            ),
            identifier: try container.decodeIfPresent(String.self, forKey: .identifier),
            selectedText: try container.decodeIfPresent(String.self, forKey: .selectedText),
            text: try container.decode(String.self, forKey: .text),
            description: try container.decodeIfPresent(String.self, forKey: .description),
            region: try container.decodeIfPresent(String.self, forKey: .region),
            value: try container.decodeIfPresent(String.self, forKey: .value),
            value2: try container.decodeIfPresent(String.self, forKey: .value2),
            iconId: try container.decodeIfPresent(Int.self, forKey: .iconId),
            coorX: try container.decodeIfPresent(Double.self, forKey: .coorX),
            coorY: try container.decodeIfPresent(Double.self, forKey: .coorY),
            from: try container.decodeIfPresent(String.self, forKey: .from),
            to: try container.decodeIfPresent(String.self, forKey: .to)
        )
        timetableIdentityScope = timetableIdentifier == nil ? .legacyUnscoped : .explicit
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        if dataSourceID != .idos {
            try container.encode(dataSourceID, forKey: .dataSourceID)
            try container.encode(timetableIdentifier, forKey: .timetableIdentifier)
            try container.encodeIfPresent(identifier, forKey: .identifier)
        } else if timetableIdentifier != TransitTimetable.defaultTimetable.identifier {
            try container.encode(timetableIdentifier, forKey: .timetableIdentifier)
        }
        try container.encodeIfPresent(selectedText, forKey: .selectedText)
        try container.encode(text, forKey: .text)
        try container.encodeIfPresent(description, forKey: .description)
        try container.encodeIfPresent(region, forKey: .region)
        if dataSourceID == .idos {
            try container.encodeIfPresent(value, forKey: .value)
            try container.encodeIfPresent(value2, forKey: .value2)
        }
        try container.encodeIfPresent(iconId, forKey: .iconId)
        try container.encodeIfPresent(coorX, forKey: .coorX)
        try container.encodeIfPresent(coorY, forKey: .coorY)
        try container.encodeIfPresent(from, forKey: .from)
        try container.encodeIfPresent(to, forKey: .to)
    }
}

/// Describes the editable message and generated attachments IDOS will send for one connection.
public struct TransitConnectionEmailDraft: Codable, Equatable, Sendable {
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

public struct TransitConnection: Codable, Equatable, Sendable {
    /// The provider that owns this result and its opaque `id`.
    public var dataSourceID: TransitDataSourceID
    /// The provider-owned timetable in which this result was found.
    public var timetableIdentifier: String {
        didSet { timetableIdentityScope = .explicit }
    }
    private var timetableIdentityScope: TransitTimetableIdentityScope
    var hasExplicitTimetableIdentifier: Bool { timetableIdentityScope.isExplicit }
    public var id: String
    public var departureTime: String
    public var departureStation: String
    public var arrivalTime: String
    public var arrivalStation: String
    public var duration: String
    public var legs: [TransitConnectionLeg]
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
        dataSourceID: TransitDataSourceID = .idos,
        timetableIdentifier: String = TransitTimetable.defaultTimetable.identifier,
        id: String,
        departureTime: String,
        departureStation: String,
        arrivalTime: String,
        arrivalStation: String,
        duration: String,
        legs: [TransitConnectionLeg],
        shareURL: String? = nil
    ) {
        self.init(
            dataSourceID: dataSourceID,
            timetableIdentifier: timetableIdentifier,
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
        dataSourceID: TransitDataSourceID = .idos,
        timetableIdentifier: String = TransitTimetable.defaultTimetable.identifier,
        id: String,
        departureTime: String,
        departureStation: String,
        arrivalTime: String,
        arrivalStation: String,
        duration: String,
        legs: [TransitConnectionLeg],
        shareURL: String? = nil,
        calendarModel: String? = nil
    ) {
        self.dataSourceID = dataSourceID
        self.timetableIdentifier = timetableIdentifier
        timetableIdentityScope = .explicit
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
        case dataSourceID
        case timetableIdentifier
        case id
        case departureTime
        case departureStation
        case arrivalTime
        case arrivalStation
        case duration
        case legs
        case shareURL
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let dataSourceID = try container.decodeIfPresent(TransitDataSourceID.self, forKey: .dataSourceID) ?? .idos
        let timetableIdentifier = try container.decodeIfPresent(String.self, forKey: .timetableIdentifier)
        self.init(
            dataSourceID: dataSourceID,
            timetableIdentifier: try decodedTimetableIdentifier(
                timetableIdentifier,
                dataSourceID: dataSourceID,
                key: CodingKeys.timetableIdentifier,
                codingPath: container.codingPath
            ),
            id: try container.decode(String.self, forKey: .id),
            departureTime: try container.decode(String.self, forKey: .departureTime),
            departureStation: try container.decode(String.self, forKey: .departureStation),
            arrivalTime: try container.decode(String.self, forKey: .arrivalTime),
            arrivalStation: try container.decode(String.self, forKey: .arrivalStation),
            duration: try container.decode(String.self, forKey: .duration),
            legs: try container.decode([TransitConnectionLeg].self, forKey: .legs),
            shareURL: try container.decodeIfPresent(String.self, forKey: .shareURL)
        )
        timetableIdentityScope = timetableIdentifier == nil ? .legacyUnscoped : .explicit
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        if dataSourceID != .idos {
            try container.encode(dataSourceID, forKey: .dataSourceID)
            try container.encode(timetableIdentifier, forKey: .timetableIdentifier)
        } else if timetableIdentifier != TransitTimetable.defaultTimetable.identifier {
            try container.encode(timetableIdentifier, forKey: .timetableIdentifier)
        }
        try container.encode(id, forKey: .id)
        try container.encode(departureTime, forKey: .departureTime)
        try container.encode(departureStation, forKey: .departureStation)
        try container.encode(arrivalTime, forKey: .arrivalTime)
        try container.encode(arrivalStation, forKey: .arrivalStation)
        try container.encode(duration, forKey: .duration)
        try container.encode(legs, forKey: .legs)
        try container.encodeIfPresent(shareURL, forKey: .shareURL)
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

public struct TransitConnectionLeg: Codable, Equatable, Sendable {
    public var name: String
    /// Opaque ID shared with the matching departure result for future service-route lookups.
    public var id: String?
    public var color: String?
    public var transportMode: TransitTransportMode?
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
    public var serviceInformation: [TransitServiceInformation]

    public init(
        name: String,
        id: String? = nil,
        color: String? = nil,
        transportMode: TransitTransportMode? = nil,
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
        serviceInformation: [TransitServiceInformation] = []
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
            transportMode: try container.decodeIfPresent(TransitTransportMode.self, forKey: .transportMode),
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
                [TransitServiceInformation].self,
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

public struct TransitDeparture: Codable, Equatable, Sendable {
    /// The provider that owns this result and its opaque `id`.
    public var dataSourceID: TransitDataSourceID
    /// The provider-owned timetable in which this result was found.
    public var timetableIdentifier: String
    public var id: String
    public var stationName: String?
    public var time: String
    public var lineName: String
    public var lineColor: String?
    public var transportMode: TransitTransportMode?
    public var destination: String
    public var tariffZone: String?
    public var platform: String?
    public var via: String?
    public var carrier: String?
    public var delay: String?
    /// Passenger facilities and restrictions printed beside this service by IDOS.
    public var serviceInformation: [TransitServiceInformation]

    public init(
        dataSourceID: TransitDataSourceID = .idos,
        timetableIdentifier: String = TransitTimetable.defaultTimetable.identifier,
        id: String,
        stationName: String? = nil,
        time: String,
        lineName: String,
        lineColor: String? = nil,
        transportMode: TransitTransportMode? = nil,
        destination: String,
        tariffZone: String? = nil,
        platform: String? = nil,
        via: String? = nil,
        carrier: String? = nil,
        delay: String? = nil,
        serviceInformation: [TransitServiceInformation] = []
    ) {
        self.dataSourceID = dataSourceID
        self.timetableIdentifier = timetableIdentifier
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
        case dataSourceID
        case timetableIdentifier
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
        let dataSourceID = try container.decodeIfPresent(TransitDataSourceID.self, forKey: .dataSourceID) ?? .idos
        let timetableIdentifier = try container.decodeIfPresent(String.self, forKey: .timetableIdentifier)
        self.init(
            dataSourceID: dataSourceID,
            timetableIdentifier: try decodedTimetableIdentifier(
                timetableIdentifier,
                dataSourceID: dataSourceID,
                key: CodingKeys.timetableIdentifier,
                codingPath: container.codingPath
            ),
            id: try container.decode(String.self, forKey: .id),
            stationName: try container.decodeIfPresent(String.self, forKey: .stationName),
            time: try container.decode(String.self, forKey: .time),
            lineName: try container.decode(String.self, forKey: .lineName),
            lineColor: try container.decodeIfPresent(String.self, forKey: .lineColor),
            transportMode: try container.decodeIfPresent(TransitTransportMode.self, forKey: .transportMode),
            destination: try container.decode(String.self, forKey: .destination),
            tariffZone: try container.decodeIfPresent(String.self, forKey: .tariffZone),
            platform: try container.decodeIfPresent(String.self, forKey: .platform),
            via: try container.decodeIfPresent(String.self, forKey: .via),
            carrier: try container.decodeIfPresent(String.self, forKey: .carrier),
            delay: try container.decodeIfPresent(String.self, forKey: .delay),
            serviceInformation: try container.decodeIfPresent(
                [TransitServiceInformation].self,
                forKey: .serviceInformation
            ) ?? []
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        if dataSourceID != .idos {
            try container.encode(dataSourceID, forKey: .dataSourceID)
            try container.encode(timetableIdentifier, forKey: .timetableIdentifier)
        } else if timetableIdentifier != TransitTimetable.defaultTimetable.identifier {
            try container.encode(timetableIdentifier, forKey: .timetableIdentifier)
        }
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
public struct TransitServiceDetail: Codable, Equatable, Sendable {
    public var id: String
    public var timetable: TransitTimetable
    public var name: String
    public var color: String?
    public var transportMode: TransitTransportMode?
    public var date: String?
    public var stops: [TransitServiceStop]
    /// Canonical provider-supplied passenger meanings in their original order.
    public var serviceInformation: [TransitServiceInformation]
    /// Historical raw-text surface retained as a writable compatibility view.
    public var information: [String] {
        get { serviceInformation.map(\.text) }
        set { serviceInformation = newValue.map { TransitServiceInformation(text: $0) } }
    }
    public var shareURL: String?

    public init(
        id: String,
        timetable: TransitTimetable = .defaultTimetable,
        name: String,
        color: String? = nil,
        transportMode: TransitTransportMode? = nil,
        date: String? = nil,
        stops: [TransitServiceStop],
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
        serviceInformation = information.map { TransitServiceInformation(text: $0) }
        self.shareURL = shareURL
    }

    /// Builds service details from categories supplied directly by a structured provider.
    public init(
        id: String,
        timetable: TransitTimetable = .defaultTimetable,
        name: String,
        color: String? = nil,
        transportMode: TransitTransportMode? = nil,
        date: String? = nil,
        stops: [TransitServiceStop],
        serviceInformation: [TransitServiceInformation],
        shareURL: String? = nil
    ) {
        self.id = id
        self.timetable = timetable
        self.name = name
        self.color = color
        self.transportMode = transportMode
        self.date = date
        self.stops = stops
        self.serviceInformation = serviceInformation
        self.shareURL = shareURL
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case timetable
        case name
        case color
        case transportMode
        case date
        case stops
        case information
        case serviceInformation
        case shareURL
    }

    /// Reads historical raw information while preferring categories persisted by a structured provider.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let information = try container.decodeIfPresent([String].self, forKey: .information) ?? []
        self.init(
            id: try container.decode(String.self, forKey: .id),
            timetable: try container.decode(TransitTimetable.self, forKey: .timetable),
            name: try container.decode(String.self, forKey: .name),
            color: try container.decodeIfPresent(String.self, forKey: .color),
            transportMode: try container.decodeIfPresent(TransitTransportMode.self, forKey: .transportMode),
            date: try container.decodeIfPresent(String.self, forKey: .date),
            stops: try container.decode([TransitServiceStop].self, forKey: .stops),
            serviceInformation: try container.decodeIfPresent(
                [TransitServiceInformation].self,
                forKey: .serviceInformation
            ) ?? information.map { TransitServiceInformation(text: $0) },
            shareURL: try container.decodeIfPresent(String.self, forKey: .shareURL)
        )
    }

    /// Keeps the historical raw field and adds structured categories only when text classification cannot recover them.
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(timetable, forKey: .timetable)
        try container.encode(name, forKey: .name)
        try container.encodeIfPresent(color, forKey: .color)
        try container.encodeIfPresent(transportMode, forKey: .transportMode)
        try container.encodeIfPresent(date, forKey: .date)
        try container.encode(stops, forKey: .stops)
        try container.encode(information, forKey: .information)
        let inferred = information.map { TransitServiceInformation(text: $0) }
        if serviceInformation != inferred {
            try container.encode(serviceInformation, forKey: .serviceInformation)
        }
        try container.encodeIfPresent(shareURL, forKey: .shareURL)
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
public struct TransitServiceStop: Codable, Equatable, Sendable {
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

public enum TransitTransportMode: String, Codable, Equatable, Sendable {
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

    static func infer(from text: String) -> TransitTransportMode? {
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
    case invalidStationTimetableMunicipality(String, timetable: TransitTimetable)
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
            let available = TransitStationTimetableMunicipality.available(for: timetable)
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
    var timetable: TransitTimetable
    var language: TransitLanguage
    var listedIDs: [Int]
}

struct IDOSDeparturePagingContext: Sendable {
    var request: TransitDeparturesRequest
    var language: TransitLanguage
    var earliestCursor: Date
    var latestCursor: Date
    var listedIDs: Set<String>
}

/// Converts the complete wording behind IDOS result symbols into the shared product model.
private enum IDOSServiceInformationHTMLParser {
    static func parseTitles(in html: String) -> [TransitServiceInformation] {
        RegexSupport.captures(
            pattern: #"\btitle="([^"]+)""#,
            in: html
        )
        .compactMap(\.first)
        .map(HTMLText.decodeEntities)
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
        .map { TransitServiceInformation(text: $0) }
    }
}

enum IDOSConnectionParser {
    static func parse(
        html: String,
        timetable: TransitTimetable = .defaultTimetable
    ) -> [TransitConnection] {
        parse(html: html, result: connectionResult(from: html), timetable: timetable)
    }

    static func parse(
        html: String,
        result: [String: Any]?,
        timetable: TransitTimetable = .defaultTimetable
    ) -> [TransitConnection] {
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
                calendarModel: calendarModels[id],
                timetable: timetable
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
        calendarModel: String?,
        timetable: TransitTimetable
    ) -> TransitConnection? {
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

        let legs = lines.indices.compactMap { index -> TransitConnectionLeg? in
            let departureIndex = index * 2
            let arrivalIndex = departureIndex + 1

            guard stationRows.indices.contains(departureIndex),
                  stationRows.indices.contains(arrivalIndex)
            else {
                return nil
            }

            let departure = stationRows[departureIndex]
            let arrival = stationRows[arrivalIndex]
            return TransitConnectionLeg(
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

        return TransitConnection(
            dataSourceID: .idos,
            timetableIdentifier: timetable.identifier,
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
        timetable: TransitTimetable
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
        timetable: TransitTimetable
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
        transportMode: TransitTransportMode?,
        carrier: String?,
        delay: String?,
        serviceInformation: [TransitServiceInformation]
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
                transportMode: TransitTransportMode.infer(from: "\(title) \(name)"),
                carrier: carrier(in: lineBlock),
                delay: delay(in: lineBlock),
                serviceInformation: serviceInformation(in: lineBlock)
            )
        }
    }

    /// Reads only the service symbols beside a line title, excluding action, carrier, and stop tooltips.
    private static func serviceInformation(in html: String) -> [TransitServiceInformation] {
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
    static func parse(html: String) -> TransitTimetableValidity? {
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

        return TransitTimetableValidity(
            validFrom: validFrom,
            validThrough: validThrough,
            timeZone: IDOSDataSource.serviceTimeZone
        )
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
    static func parse(script: String) -> TransitServiceDateLimits? {
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

        var days: [TransitServiceDateLimits.Day] = []
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
            let statuses = rawStatuses.compactMap { value -> TransitServiceDateLimits.DayStatus? in
                Int(value.trimmingCharacters(in: .whitespacesAndNewlines))
                    .flatMap(TransitServiceDateLimits.DayStatus.init(rawValue:))
            }
            guard statuses.count == rawStatuses.count else { return nil }

            for (index, status) in statuses.enumerated() {
                guard let date = calendar.date(bySetting: .day, value: index + 1, of: month) else {
                    return nil
                }
                days.append(TransitServiceDateLimits.Day(date: date, status: status))
            }
        }

        return TransitServiceDateLimits(
            referenceDate: referenceDate,
            days: days,
            timeZone: IDOSDataSource.serviceTimeZone
        )
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
        request: TransitStationTimetableRequest,
        shareURL: String? = nil
    ) -> TransitStationTimetable? {
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

        return TransitStationTimetable(
            timetable: request.timetable,
            municipality: request.effectiveMunicipality,
            lineName: lineName,
            transportMode: TransitTransportMode.infer(from: lineName),
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

    private static func stopRows(in html: String) -> [TransitStationTimetableStop] {
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

            return TransitStationTimetableStop(
                name: name,
                minuteOffset: minuteOffset,
                tariffZone: tariffZone,
                platform: platform,
                isSelected: selectedName != nil,
                notes: unique(notes)
            )
        }
    }

    private static func scheduleTables(in html: String) -> [TransitStationTimetableSchedule] {
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
            ).compactMap { row -> TransitStationTimetableHour? in
                guard row.count == 2 else { return nil }
                let hour = HTMLText.clean(row[0])
                guard !hour.isEmpty else { return nil }
                let departures = HTMLText.clean(row[1])
                    .split(whereSeparator: \.isWhitespace)
                    .map(String.init)
                return TransitStationTimetableHour(hour: hour, departures: departures)
            }
            return TransitStationTimetableSchedule(label: label, hours: hours)
        }
    }

    private struct TimetableRemarks {
        let explanations: [String]
        let notes: [String]
    }

    /// Separates keyed explanations only when their marker occurs beside a concrete departure.
    private static func timetableRemarks(
        in html: String,
        schedules: [TransitStationTimetableSchedule]
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
        in schedules: [TransitStationTimetableSchedule]
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
    static func scheduledDate(for departure: TransitDeparture) -> Date? {
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
        timetable: TransitTimetable = .defaultTimetable
    ) -> [TransitDeparture] {
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
        timetable: TransitTimetable
    ) -> TransitDeparture? {
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
            .flatMap(canonicalServiceDateTime)

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

        return TransitDeparture(
            dataSourceID: .idos,
            timetableIdentifier: timetable.identifier,
            id: "\(timetable.slug):\(timetableIndex)-\(trainID)-\(dateTime)",
            stationName: stationName,
            time: time,
            lineName: lineName,
            lineColor: HTMLStyle.color(from: lineHTML),
            transportMode: TransitTransportMode.infer(from: lineName),
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
    private static func serviceInformation(in html: String) -> [TransitServiceInformation] {
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

    /// Canonicalizes the HTML timestamp IDOS occasionally leaves unpadded so its ID can load a service detail.
    private static func canonicalServiceDateTime(_ value: String) -> String? {
        guard let parts = RegexSupport.captures(
            pattern: #"^(\d{1,2})\.(\d{1,2})\.(\d{4}) (\d{1,2}):(\d{1,2}):(\d{1,2})$"#,
            in: value
        ).first,
              parts.count == 6,
              let day = Int(parts[0]),
              let month = Int(parts[1]),
              let year = Int(parts[2]),
              let hour = Int(parts[3]),
              let minute = Int(parts[4]),
              let second = Int(parts[5]),
              (0...23).contains(hour),
              (0...59).contains(minute),
              (0...59).contains(second),
              Calendar(identifier: .gregorian).date(
                from: DateComponents(year: year, month: month, day: day)
              ) != nil
        else {
            return nil
        }

        return String(
            format: "%02d.%02d.%04d %02d:%02d:%02d",
            day,
            month,
            year,
            hour,
            minute,
            second
        )
    }
}

/// Resolves current self-contained IDs and upgrades legacy IDs with caller-supplied timetable context.
struct IDOSServiceReference {
    let id: String
    let timetable: TransitTimetable
    let timetableIndex: Int
    let trainID: Int
    let year: Int
    let month: Int
    let day: Int
    let hour: Int
    let minute: Int

    init(id: String, fallbackTimetable: TransitTimetable) throws {
        let value = id.trimmingCharacters(in: .whitespacesAndNewlines)
        let prefixed = RegexSupport.captures(
            pattern: #"^([A-Za-z0-9-]+):(.*)$"#,
            in: value
        ).first
        let legacyID: String
        let timetable: TransitTimetable
        if let prefixed, prefixed.count == 2,
           let embeddedTimetable = try? TransitTimetable.resolve(prefixed[0])
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
        timetable: TransitTimetable = .defaultTimetable,
        language: TransitLanguage? = nil
    ) -> TransitServiceDetail? {
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
        ).compactMap { row -> TransitServiceStop? in
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

            return TransitServiceStop(
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
        return TransitServiceDetail(
            id: id,
            timetable: timetable,
            name: name,
            color: HTMLStyle.color(from: heading),
            transportMode: TransitTransportMode.infer(from: "\(headingTitle) \(name)"),
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
        language: TransitLanguage?
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
        let language: TransitLanguage
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
    static func normalize(_ suggestion: TransitSuggestion) -> TransitSuggestion {
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
