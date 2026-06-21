import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public protocol IDOSClienting: Sendable {
    func suggest(prefix: String, limit: Int, timetable: IDOSTimetable) async throws -> [IDOSSuggestion]
    func searchStations(prefix: String, limit: Int, timetable: IDOSTimetable) async throws -> [IDOSSuggestion]
    func findConnections(request: IDOSConnectionRequest) async throws -> [IDOSConnection]
    func connectionCalendar(for connection: IDOSConnection, timetable: IDOSTimetable) async throws -> String
    func findDepartures(request: IDOSDeparturesRequest) async throws -> [IDOSDeparture]
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
        let json = try IDOSJSONP.decodePayload(from: data)
        return try JSONDecoder().decode([IDOSSuggestion].self, from: json)
    }

    public func findConnections(request: IDOSConnectionRequest) async throws -> [IDOSConnection] {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
        components.path = "/en/\(request.timetable.slug)/spojeni/"

        var urlRequest = URLRequest(url: try components.requiredURL)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        urlRequest.httpBody = Self.formURLEncodedData(request.formItems)

        let data = try await data(for: urlRequest)
        guard let html = String(data: data, encoding: .utf8) else {
            throw IDOSError.invalidResponse
        }

        var connections = IDOSConnectionParser.parse(html: html)
        guard let limit = request.resultLimit, connections.count < limit,
              var paging = IDOSConnectionParser.pagingContext(html: html)
        else {
            return connections
        }

        while connections.count < limit, paging.allowNext {
            let page = try await nextConnectionsPage(
                request: request,
                paging: paging,
                listedIDs: connections.compactMap { Int($0.id) }
            )

            guard !page.connections.isEmpty else {
                break
            }

            let knownIDs = Set(connections.map(\.id))
            let newConnections = page.connections.filter { !knownIDs.contains($0.id) }
            guard !newConnections.isEmpty else {
                break
            }

            connections.append(contentsOf: newConnections)
            paging.allowNext = page.allowNext
        }

        return Array(connections.prefix(limit))
    }

    private func nextConnectionsPage(
        request: IDOSConnectionRequest,
        paging: IDOSConnectionPagingContext,
        listedIDs: [Int]
    ) async throws -> (connections: [IDOSConnection], allowNext: Bool) {
        guard let lastID = listedIDs.last else {
            return ([], false)
        }

        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
        components.path = "/en/\(request.timetable.slug)/Ajax/ConnPaging"
        components.queryItems = [URLQueryItem(name: "callback", value: "idosCallback")]

        var urlRequest = URLRequest(url: try components.requiredURL)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/x-www-form-urlencoded; charset=UTF-8", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
        urlRequest.setValue("\(baseURL.absoluteString)/en/\(request.timetable.slug)/spojeni/", forHTTPHeaderField: "Referer")

        var items = listedIDs.map { URLQueryItem(name: "listedIds[]", value: String($0)) }
        items.append(contentsOf: [
            URLQueryItem(name: "isPrev", value: "false"),
            URLQueryItem(name: "handle", value: String(paging.handle)),
            URLQueryItem(name: "searchDate", value: paging.searchDate),
            URLQueryItem(name: "connId", value: String(lastID)),
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
        let result: [String: Any] = [
            "handle": paging.handle,
            "connData": object["connData"] as? [[String: Any]] ?? [],
            "searchItem": paging.searchItem,
        ]
        let allowNext = object["allowNext"] as? Bool ?? false
        return (IDOSConnectionParser.parse(html: html, result: result), allowNext)
    }

    public func connectionCalendar(for connection: IDOSConnection, timetable: IDOSTimetable = .defaultTimetable) async throws -> String {
        guard let model = connection.calendarModel, !model.isEmpty else {
            throw IDOSError.calendarUnavailable
        }

        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
        components.path = "/en/\(timetable.slug)/spojeni/kalendar"

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

    public func findDepartures(request: IDOSDeparturesRequest) async throws -> [IDOSDeparture] {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
        components.path = "/en/\(request.timetable.slug)/odjezdy/"

        var urlRequest = URLRequest(url: try components.requiredURL)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        urlRequest.httpBody = Self.formURLEncodedData(request.formItems)

        let data = try await data(for: urlRequest)
        guard let html = String(data: data, encoding: .utf8) else {
            throw IDOSError.invalidResponse
        }

        return IDOSDepartureParser.parse(html: html)
    }

    private func data(from url: URL) async throws -> Data {
        let request = URLRequest(url: url)
        return try await data(for: request)
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
        items.map { item in
            "\(formEncode(item.name))=\(formEncode(item.value ?? ""))"
        }
        .joined(separator: "&")
        .data(using: .utf8)
    }

    private static func formEncode(_ value: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }
}

public struct IDOSDeparturesRequest: Codable, Equatable, Sendable {
    public var timetable: IDOSTimetable
    public var station: String
    public var date: String?
    public var time: String?
    public var isArrival: Bool

    public init(
        timetable: IDOSTimetable = .defaultTimetable,
        station: String,
        date: String? = nil,
        time: String? = nil,
        isArrival: Bool = false
    ) {
        self.timetable = timetable
        self.station = station
        self.date = date
        self.time = time
        self.isArrival = isArrival
    }

    var formItems: [URLQueryItem] {
        var items = [
            URLQueryItem(name: "From", value: station),
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
    public var date: String?
    public var time: String?
    public var isArrival: Bool
    public var onlyDirect: Bool
    public var via: [String]
    public var maxTransfers: Int?
    public var minimumTransferTime: Int?
    public var resultLimit: Int?

    public init(
        timetable: IDOSTimetable = .defaultTimetable,
        from: String,
        to: String,
        date: String? = nil,
        time: String? = nil,
        isArrival: Bool = false,
        onlyDirect: Bool = false,
        via: [String] = [],
        maxTransfers: Int? = nil,
        minimumTransferTime: Int? = nil,
        resultLimit: Int? = nil
    ) {
        self.timetable = timetable
        self.from = from
        self.to = to
        self.date = date
        self.time = time
        self.isArrival = isArrival
        self.onlyDirect = onlyDirect
        self.via = via
        self.maxTransfers = maxTransfers
        self.minimumTransferTime = minimumTransferTime
        self.resultLimit = resultLimit
    }

    var formItems: [URLQueryItem] {
        var items = [
            URLQueryItem(name: "From", value: from),
            URLQueryItem(name: "To", value: to),
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

    public init(
        selectedText: String? = nil,
        text: String,
        description: String? = nil,
        region: String? = nil,
        value: String? = nil,
        value2: String? = nil,
        iconId: Int? = nil,
        coorX: Double? = nil,
        coorY: Double? = nil
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

    public init(
        name: String,
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
        delay: String? = nil
    ) {
        self.name = name
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
            parts.append("platform \(platform)")
        }
        return parts.joined(separator: " · ")
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
        delay: String? = nil
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

public enum IDOSError: LocalizedError, Sendable {
    case invalidResponse
    case invalidURL
    case invalidJSONP
    case invalidTimetable(String)
    case networkUnavailable(String)
    case calendarUnavailable

    public var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "IDOS returned an unexpected response."
        case .invalidURL:
            return "Could not build the IDOS URL."
        case .invalidJSONP:
            return "IDOS suggestions returned an unexpected JSONP format."
        case .invalidTimetable(let value):
            return "Invalid timetable: \(value). Use an alias or a URL slug without slashes."
        case .networkUnavailable(let detail):
            let detail = detail.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !detail.isEmpty else {
                return "Network request failed. Check your internet connection."
            }

            return "Network request failed. Check your internet connection. \(detail)"
        case .calendarUnavailable:
            return "IDOS did not provide calendar export data for this connection."
        }
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

struct IDOSConnectionPagingContext {
    var handle: Int
    var searchDate: String
    var arrivalThere: String
    var from: String?
    var to: String?
    var searchItem: [String: Any]
    var allowNext: Bool
}

enum IDOSConnectionParser {
    static func parse(html: String) -> [IDOSConnection] {
        parse(html: html, result: connectionResult(from: html))
    }

    static func parse(html: String, result: [String: Any]?) -> [IDOSConnection] {
        let calendarModels = calendarModels(in: html, result: result)
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
            return parseConnection(id: id, block: block, calendarModel: calendarModels[id])
        }
    }

    static func pagingContext(html: String) -> IDOSConnectionPagingContext? {
        guard let result = connectionResult(from: html),
              let handle = integer(result["handle"]),
              let searchItem = result["searchItem"] as? [String: Any],
              let connection = searchItem["oConn"] as? [String: Any],
              let input = connection["oUserInput"] as? [String: Any],
              let searchDate = input["dtSearchDate"] as? String
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
            searchItem: searchItem,
            allowNext: result["allowNext"] as? Bool ?? true
        )
    }

    private static func parseConnection(id: String, block: String, calendarModel: String?) -> IDOSConnection? {
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
                platform: titledValue(["platform", "nástupiště", "nastupiste"], in: stationHTML)
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
                delay: lines[index].delay
            )
        }

        return IDOSConnection(
            id: id,
            departureTime: first.time,
            departureStation: first.station,
            arrivalTime: last.time,
            arrivalStation: last.station,
            duration: HTMLText.clean(RegexSupport.capture(
                pattern: #"Overall time\s*<strong>(.*?)</strong>"#,
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

    private static func lineDetails(in block: String) -> [(name: String, color: String?, transportMode: IDOSTransportMode?, carrier: String?, delay: String?)] {
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
        let sources = lineBlocks.isEmpty ? headingBlocks(in: block) : lineBlocks

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
                delay: delay(in: lineBlock)
            )
        }
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

enum IDOSDepartureParser {
    static func parse(html: String) -> [IDOSDeparture] {
        let stationName = resolvedStationName(in: html)

        return RegexSupport.captures(
            pattern: #"<tr class="dep-row dep-row-first"([^>]*)>(.*?)</tr>\s*<tr class="dep-row dep-row-second"[^>]*>(.*?)</tr>"#,
            in: html,
            options: [.dotMatchesLineSeparators]
        ).compactMap { row in
            parseDeparture(attributes: row[0], firstRow: row[1], secondRow: row[2], stationName: stationName)
        }
    }

    private static func parseDeparture(
        attributes: String,
        firstRow: String,
        secondRow: String,
        stationName: String?
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

        guard !time.isEmpty, !lineName.isEmpty, !destination.isEmpty else {
            return nil
        }

        let platform = RegexSupport.capture(
            pattern: #"<span title="(?:platform|nástupiště)"[^>]*>(.*?)</span>"#,
            in: firstRow,
            options: [.dotMatchesLineSeparators]
        ).map(HTMLText.clean)
        let tariffZone = detail(title: "tariff zone", in: firstRow)
            ?? detail(title: "tarifní pásmo", in: firstRow)
            ?? detail(title: "tarifni pasmo", in: firstRow)
        let via = detail(title: "pass via", in: secondRow).map { value in
            value.hasPrefix("via ") ? String(value.dropFirst(4)) : value
        }
        let carrier = detail(title: "dopravce", in: secondRow) ?? detail(title: "carrier", in: secondRow)
        let delay = RegexSupport.capture(
            pattern: #"<a\b[^>]*class="delay-bubble"[^>]*>(.*?)</a>"#,
            in: secondRow,
            options: [.dotMatchesLineSeparators]
        ).map(HTMLText.clean)

        return IDOSDeparture(
            id: [
                attribute("data-ttindex", in: attributes),
                attribute("data-train", in: attributes),
                attribute("data-datetime", in: attributes),
            ].compactMap(\.self).joined(separator: "-"),
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
            delay: delay
        )
    }

    private static func resolvedStationName(in html: String) -> String? {
        if let title = RegexSupport.capture(
            pattern: #"<h2\b[^>]*class="[^"]*\bdepTitlePage\b[^"]*"[^>]*>(.*?)</h2>"#,
            in: html,
            options: [.dotMatchesLineSeparators]
        ).map(HTMLText.clean) {
            for prefix in ["Departures from ", "Arrivals to "] where title.hasPrefix(prefix) {
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

private enum HTMLText {
    static func clean(_ value: String) -> String {
        normalizeWhitespace(stripTags(decodeEntities(value)))
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
