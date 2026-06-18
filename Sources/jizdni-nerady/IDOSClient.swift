import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

protocol IDOSClienting {
    func suggest(prefix: String, limit: Int, timetable: IDOSTimetable) async throws -> [IDOSSuggestion]
    func findConnections(request: IDOSConnectionRequest) async throws -> [IDOSConnection]
}

struct IDOSClient: IDOSClienting {
    var baseURL = URL(string: "https://idos.cz")!

    func suggest(prefix: String, limit: Int, timetable: IDOSTimetable) async throws -> [IDOSSuggestion] {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
        components.path = "/\(timetable.slug)/Ajax/SearchTimetableObjects/"
        components.queryItems = [
            URLQueryItem(name: "count", value: String(limit)),
            URLQueryItem(name: "prefixText", value: prefix),
            URLQueryItem(name: "positionAccuracy", value: "0"),
            URLQueryItem(name: "searchByPosition", value: "false"),
            URLQueryItem(name: "onlyStation", value: "false"),
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "bindTtIndex", value: ""),
            URLQueryItem(name: "callback", value: "idosCallback"),
        ]

        let data = try await data(from: components.requiredURL)
        let json = try IDOSJSONP.decodePayload(from: data)
        return try JSONDecoder().decode([IDOSSuggestion].self, from: json)
    }

    func findConnections(request: IDOSConnectionRequest) async throws -> [IDOSConnection] {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
        components.path = "/\(request.timetable.slug)/spojeni/"
        components.queryItems = request.queryItems

        let data = try await data(from: components.requiredURL)
        guard let html = String(data: data, encoding: .utf8) else {
            throw IDOSError.invalidResponse
        }

        return IDOSConnectionParser.parse(html: html)
    }

    private func data(from url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.setValue("jizdni-nerady/0.1 (+local personal use)", forHTTPHeaderField: "User-Agent")

        return try await withCheckedThrowingContinuation { continuation in
            let task = URLSession.shared.dataTask(with: request) { data, response, error in
                if let error {
                    continuation.resume(throwing: error)
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
}

struct IDOSConnectionRequest: Equatable {
    var timetable: IDOSTimetable
    var from: String
    var to: String
    var date: String?
    var time: String?

    var queryItems: [URLQueryItem] {
        [
            URLQueryItem(name: "f", value: from),
            URLQueryItem(name: "t", value: to),
            date.map { URLQueryItem(name: "date", value: $0) },
            time.map { URLQueryItem(name: "time", value: $0) },
            URLQueryItem(name: "submit", value: "true"),
        ].compactMap(\.self)
    }
}

struct IDOSTimetable: Equatable {
    var slug: String
    var displayName: String

    static let defaultTimetable = IDOSTimetable(slug: "vlakyautobusymhdvse", displayName: "Vše")

    static var known: [IDOSTimetable] {
        baseTimetables + mhdNames
            .filter { !unsupportedMHDNames.contains($0) }
            .map { name in
                IDOSTimetable(
                    slug: mhdSlugOverrides[name] ?? slugify(name),
                    displayName: "MHD \(name)"
                )
            }
    }

    private static let baseTimetables: [IDOSTimetable] = [
        .defaultTimetable,
        IDOSTimetable(slug: "vlakyautobusymhd", displayName: "Vlaky + autobusy + MHD"),
        IDOSTimetable(slug: "vlaky", displayName: "Vlaky"),
        IDOSTimetable(slug: "autobusy", displayName: "Autobusy"),
        IDOSTimetable(slug: "vlakyautobusy", displayName: "Vlaky + autobusy"),
        IDOSTimetable(slug: "pid", displayName: "Praha + PID"),
        IDOSTimetable(slug: "idsjmk", displayName: "IDS JMK / Brno"),
        IDOSTimetable(slug: "odis", displayName: "ODIS"),
        IDOSTimetable(slug: "idol", displayName: "IDOL"),
    ]

    static func resolve(_ value: String?) throws -> IDOSTimetable {
        guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .defaultTimetable
        }

        let lookup = lookupKey(value)
        if let timetable = aliases()[lookup] {
            return timetable
        }

        let customSlug = slugCandidate(value)
        guard customSlug.range(of: #"^[a-z0-9-]+$"#, options: .regularExpression) != nil else {
            throw IDOSError.invalidTimetable(value)
        }

        return IDOSTimetable(slug: customSlug, displayName: customSlug)
    }

    private static func aliases() -> [String: IDOSTimetable] {
        var aliases: [String: IDOSTimetable] = [
            "vse": .defaultTimetable,
            "all": .defaultTimetable,
            "default": .defaultTimetable,
            "vlakyautobusymhdvse": .defaultTimetable,
            "vlakyautobusymhd": known.first { $0.slug == "vlakyautobusymhd" }!,
            "vlak": known.first { $0.slug == "vlaky" }!,
            "train": known.first { $0.slug == "vlaky" }!,
            "trains": known.first { $0.slug == "vlaky" }!,
            "autobus": known.first { $0.slug == "autobusy" }!,
            "bus": known.first { $0.slug == "autobusy" }!,
            "buses": known.first { $0.slug == "autobusy" }!,
            "vlakbus": known.first { $0.slug == "vlakyautobusy" }!,
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

            if timetable.displayName.hasPrefix("MHD ") {
                aliases[lookupKey(String(timetable.displayName.dropFirst(4)))] = timetable
            }
        }

        return aliases
    }

    private static func lookupKey(_ value: String) -> String {
        ascii(value).filter { $0.isLetter || $0.isNumber }
    }

    private static func slugCandidate(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.range(of: #"^[A-Za-z0-9-]+$"#, options: .regularExpression) != nil {
            return trimmed.lowercased()
        }

        return slugify(trimmed)
    }

    private static func slugify(_ value: String) -> String {
        let compact = ascii(value)
        let withoutMHD = compact.hasPrefix("mhd") ? String(compact.dropFirst(3)) : compact

        return withoutMHD.filter { $0.isLetter || $0.isNumber }
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

struct IDOSSuggestion: Codable, Equatable {
    var selectedText: String?
    var text: String
    var description: String?
    var region: String?
    var value: String?
    var value2: String?
    var iconId: Int?
    var coorX: Double?
    var coorY: Double?
}

struct IDOSConnection: Equatable {
    var id: String
    var departureTime: String
    var departureStation: String
    var arrivalTime: String
    var arrivalStation: String
    var duration: String
    var legs: [IDOSConnectionLeg]
    var shareURL: String?

    func summaryLine(number: Int) -> String {
        var result = "\(number). \(departureTime) \(departureStation) -> \(arrivalTime) \(arrivalStation)"

        if !duration.isEmpty {
            result += " (\(duration))"
        }

        if !legs.isEmpty {
            let legSummary = legs.map { leg in
                [leg.name, leg.fromStation, leg.departureTime, "->", leg.arrivalTime, leg.toStation]
                    .filter { !$0.isEmpty }
                    .joined(separator: " ")
            }.joined(separator: "; ")
            result += "\n   \(legSummary)"
        }

        return result
    }
}

struct IDOSConnectionLeg: Equatable {
    var name: String
    var departureTime: String
    var fromStation: String
    var arrivalTime: String
    var toStation: String
}

enum IDOSError: LocalizedError {
    case invalidResponse
    case invalidURL
    case invalidJSONP
    case invalidTimetable(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "IDOS vrátil neočekávanou odpověď."
        case .invalidURL:
            return "Nepodařilo se sestavit URL pro IDOS."
        case .invalidJSONP:
            return "Našeptávač IDOS vrátil neočekávaný JSONP formát."
        case .invalidTimetable(let value):
            return "Neplatný jízdní řád: \(value). Použijte alias nebo URL slug bez lomítek."
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

enum IDOSConnectionParser {
    static func parse(html: String) -> [IDOSConnection] {
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
            return parseConnection(id: id, block: block)
        }
    }

    private static func parseConnection(id: String, block: String) -> IDOSConnection? {
        let stationRows = RegexSupport.captures(
            pattern: #"<p class="reset time[^"]*"[^>]*>(.*?)</p>\s*<p class="station"><strong class="name[^"]*">(.*?)</strong>"#,
            in: block,
            options: [.dotMatchesLineSeparators]
        ).map { row in
            (
                time: HTMLText.clean(row[0]),
                station: HTMLText.clean(row[1])
            )
        }

        guard let first = stationRows.first, let last = stationRows.last else {
            return nil
        }

        let names = RegexSupport.captures(
            pattern: #"<span>(.*?)</span>\s*</h3>"#,
            in: block,
            options: [.dotMatchesLineSeparators]
        ).map { HTMLText.clean($0[0]) }

        let legs = names.indices.compactMap { index -> IDOSConnectionLeg? in
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
                name: names[index],
                departureTime: departure.time,
                fromStation: departure.station,
                arrivalTime: arrival.time,
                toStation: arrival.station
            )
        }

        return IDOSConnection(
            id: id,
            departureTime: first.time,
            departureStation: first.station,
            arrivalTime: last.time,
            arrivalStation: last.station,
            duration: HTMLText.clean(RegexSupport.capture(
                pattern: #"Celkový čas\s*<strong>(.*?)</strong>"#,
                in: block,
                options: [.dotMatchesLineSeparators]
            ) ?? ""),
            legs: legs,
            shareURL: HTMLText.decodeEntities(RegexSupport.capture(
                pattern: #"data-share-url="([^"]+)""#,
                in: block
            ) ?? "")
        )
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
