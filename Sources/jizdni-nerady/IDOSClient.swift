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

    static let common: [IDOSTimetable] = [
        .defaultTimetable,
        IDOSTimetable(slug: "vlaky", displayName: "Vlaky"),
        IDOSTimetable(slug: "autobusy", displayName: "Autobusy"),
        IDOSTimetable(slug: "vlakyautobusy", displayName: "Vlaky + autobusy"),
        IDOSTimetable(slug: "pid", displayName: "Praha + PID"),
        IDOSTimetable(slug: "praha", displayName: "Praha"),
        IDOSTimetable(slug: "frydekmistek", displayName: "Frýdek-Místek"),
        IDOSTimetable(slug: "ostrava", displayName: "Ostrava"),
        IDOSTimetable(slug: "odis", displayName: "ODIS"),
    ]

    static func resolve(_ value: String?) throws -> IDOSTimetable {
        guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .defaultTimetable
        }

        let normalized = normalize(value)
        let aliases: [String: IDOSTimetable] = [
            "vse": .defaultTimetable,
            "all": .defaultTimetable,
            "default": .defaultTimetable,
            "vlaky-autobusy-mhd-vse": .defaultTimetable,
            "vlakyautobusymhd": .defaultTimetable,
            "vlakyautobusymhdvse": .defaultTimetable,
            "vlaky": common[1],
            "vlak": common[1],
            "train": common[1],
            "trains": common[1],
            "autobusy": common[2],
            "autobus": common[2],
            "bus": common[2],
            "buses": common[2],
            "vlakyautobusy": common[3],
            "vlaky-autobusy": common[3],
            "vlaky+autobusy": common[3],
            "vlak-bus": common[3],
            "train-bus": common[3],
            "pid": common[4],
            "praha-pid": common[4],
            "praha+pid": common[4],
            "praha": common[5],
            "frýdek-místek": common[6],
            "frydek-mistek": common[6],
            "frydekmistek": common[6],
            "ostrava": common[7],
            "odis": common[8],
        ]

        if let timetable = aliases[normalized] {
            return timetable
        }

        guard normalized.range(of: #"^[a-z0-9-]+$"#, options: .regularExpression) != nil else {
            throw IDOSError.invalidTimetable(value)
        }

        return IDOSTimetable(slug: normalized, displayName: normalized)
    }

    private static func normalize(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "cs_CZ"))
            .replacingOccurrences(of: "_", with: "-")
            .replacingOccurrences(of: #"[\s-]*\+[\s-]*"#, with: "+", options: .regularExpression)
            .replacingOccurrences(of: " ", with: "-")
    }
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
