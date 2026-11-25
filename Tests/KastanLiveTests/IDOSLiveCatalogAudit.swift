import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import Kastan

enum IDOSLiveCatalogAudit {
    static func failures(for source: IDOSDataSource) async -> [String] {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 30
        let session = URLSession(configuration: configuration, delegate: RefuseRedirects(), delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }

        let languages: [TransitLanguage] = [.czech, .english]
        let requests = languages.flatMap { language in
            source.timetables.map { (timetable: $0, language: language) }
        }
        let batchSize = 5
        var failures: [String] = []
        for offset in stride(from: 0, to: requests.count, by: batchSize) {
            let batch = requests.dropFirst(offset).prefix(batchSize)
            let batchFailures = await withTaskGroup(of: [String].self) { group in
                for (timetable, language) in batch {
                    group.addTask {
                        await check(timetable, language: language, baseURL: source.baseURL, session: session)
                    }
                }
                var results: [String] = []
                for await problems in group {
                    results.append(contentsOf: problems)
                }
                return results
            }
            failures.append(contentsOf: batchFailures.sorted())
        }
        return failures
    }

    private static func check(
        _ timetable: TransitTimetable,
        language: TransitLanguage,
        baseURL: URL,
        session: URLSession
    ) async -> [String] {
        let path = language.path(timetable: timetable, endpoint: "spojeni/")
        guard let url = URL(string: path, relativeTo: baseURL)?.absoluteURL else {
            return ["Could not build the connection form URL for \(path)."]
        }
        var request = URLRequest(url: url)
        request.setValue(IDOSDataSource.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                return ["\(url): expected an HTTP response."]
            }
            guard http.statusCode == 200, http.url == url else {
                let location = http.value(forHTTPHeaderField: "Location") ?? http.url?.absoluteString ?? "unknown"
                return ["\(url): expected HTTP 200 at the original address, got HTTP \(http.statusCode) (\(location))."]
            }
            guard let html = String(data: data, encoding: .utf8),
                  let contract = IDOSConnectionFormParser.contract(in: html)
            else {
                return ["\(url): Kaštan could not parse the connection form."]
            }
            return PublishedControls(html: html).differences(from: contract.searchOptions).map { "\(url): \($0)" }
        } catch {
            return ["\(url): \(error.localizedDescription)"]
        }
    }

    private final class RefuseRedirects: NSObject, URLSessionTaskDelegate {
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
}

/// Reads the browser controls independently of the Kaštan parser, including previously unknown choices.
private struct PublishedControls {
    private static let fields: [TransitConnectionOption: Set<String>] = [
        .onlyDirect: ["OnlyDirect"],
        .via: ["AdvancedForm.Via[0]"],
        .carrierFilter: ["AdvancedForm.OwnerMaskNames", "AdvancedForm.OwnerMaskExcludeInclude"],
        .lineFilter: ["AdvancedForm.Num1MaskNames", "AdvancedForm.Num1MaskExcludeInclude"],
        .maximumTransfers: ["AdvancedForm.MaxChange"],
        .minimumTransferTime: ["AdvancedForm.MinTime"],
        .maximumTransferTime: ["AdvancedForm.MaxTime"],
        .maximumWalkingTime: ["AdvancedForm.MaxArcLength"],
        .maximumCityWalkingTime: ["AdvancedForm.MaxArcLengthCity"],
        .walkToNearbyStops: ["AdvancedForm.MaxArcLengthFrom"],
        .sameNameWalkingTransfersOnly: ["AdvancedForm.LimitWalkArcs"],
        .wheelchairAccessibleConnectionsOnly: ["AdvancedForm.LowDeckConn"],
        .lowFloorConnectionsOnly: ["AdvancedForm.LowDeckConnTr"],
        .preferTrainsOverBuses: ["AdvancedForm.PrefereTrains"],
        .trainConnectionsForWheelchairPassengers: ["AdvancedForm.WheelChair"],
        .trainConnectionsForPassengersWithChildren: ["AdvancedForm.Children"],
        .connectionsForPassengersWithBicycles: ["AdvancedForm.Bicycle"],
        .preferBusyRoutes: ["AdvancedForm.AutoStrategy"],
        .bedOrCouchettePreference: ["AdvancedForm.UseBeds"],
        .trainsWithoutCompulsoryReservationOnly: ["AdvancedForm.BigTrain"],
    ]
    private static let knownFields = Set(fields.values.flatMap { $0 })
    // Keep the expected browser IDs independent of Kaštan's mapping so swapped modes are detectable.
    private static let modes: [String: TransitConnectionTransportMode] = [
        "150": .highestQualityTrain, "151": .higherQualityTrain, "152": .interregionalTrain, "153": .regionalTrain,
        "154": .bus, "155": .ship, "156": .other,
        "200": .localBus, "201": .longDistanceBus, "202": .internationalBus,
        "300": .cityTram, "301": .cityBus, "302": .cityMetro, "303": .cityCableway,
        "304": .cityRegionalBus, "305": .cityAccessibleLine, "306": .cityTrolleybus, "307": .cityShip,
        "308": .cityNightBus, "309": .cityNightTram, "310": .cityReplacementBus, "311": .citySchoolBus,
        "312": .cityContractBus, "314": .cityRailReplacement, "315": .cityTrain, "317": .cityReplacementTram,
        "318": .cityRegionalNightBus, "319": .cityOther, "321": .cityDemandResponsive,
    ]
    // The zero-transfer choice in the app is represented by IDOS's separate OnlyDirect checkbox.
    private static let pickerValues: [String: Set<String>] = [
        "AdvancedForm.MaxChange": Set((1...10).map(String.init)),
        "AdvancedForm.MinTime": ["-1", "0", "1", "2", "3", "4", "5", "10", "20", "30", "60"],
        "AdvancedForm.MaxTime": ["10", "20", "30", "45", "60", "120", "240", "360", "480", "720", "1080"],
        "AdvancedForm.MaxArcLength": ["0", "5", "10", "20", "30", "45", "60"],
        "AdvancedForm.MaxArcLengthCity": ["0", "5", "10", "20", "30", "45", "60"],
        "AdvancedForm.UseBeds": ["0", "1", "2"],
        "AdvancedForm.OwnerMaskExcludeInclude": ["True", "False"],
        "AdvancedForm.Num1MaskExcludeInclude": ["True", "False"],
    ]

    private static let tags = try! NSRegularExpression(
        pattern: #"<(/?)(input|select|option)\b((?:[^>"']|"[^"]*"|'[^']*')*)>"#,
        options: .caseInsensitive
    )
    private static let attributes = try! NSRegularExpression(
        pattern: #"(?:^|\s)([^\s=/>]+)(?:\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s>]+)))?"#
    )

    private var values: [String: Set<String>] = [:]
    private var modeIDs: Set<String> = []

    init(html: String) {
        var activeSelect: String?
        for tag in Self.captures(Self.tags, in: html) {
            let attributes = Dictionary(
                Self.captures(Self.attributes, in: tag[3]).map { attribute in
                    let name = attribute[1].lowercased()
                    let value = attribute[2...4].first(where: { !$0.isEmpty }) ?? ""
                    return (name, value)
                },
                uniquingKeysWith: { first, _ in first }
            )
            let name = attributes["name", default: ""]
            switch tag[2].lowercased() {
            case "input" where attributes["disabled"] == nil && attributes["type"]?.lowercased() != "hidden":
                if name.hasPrefix("trTypeId["), name.hasSuffix("]"), attributes["type"]?.lowercased() == "checkbox" {
                    modeIDs.insert(String(name.dropFirst("trTypeId[".count).dropLast()))
                } else if name == "OnlyDirect" || name.hasPrefix("AdvancedForm.") {
                    values[name, default: []].insert(attributes["value", default: ""])
                }
            case "select":
                activeSelect = tag[1].isEmpty && attributes["disabled"] == nil && name.hasPrefix("AdvancedForm.")
                    ? name : nil
            case "option" where tag[1].isEmpty && attributes["disabled"] == nil:
                if let activeSelect, let value = attributes["value"] {
                    values[activeSelect, default: []].insert(value)
                }
            default:
                break
            }
        }
    }

    func differences(from actual: TransitConnectionSearchOptions) -> [String] {
        let publishedFields = Set(values.keys)
        let publishedModes = Set(modeIDs.compactMap { Self.modes[$0] })
        var publishedOptions = Set(Self.fields.compactMap { option, fields in
            fields.isSubset(of: publishedFields) ? option : nil
        })
        if !modeIDs.isEmpty { publishedOptions.insert(.transportModeFilters) }

        var problems: [String] = []
        func compare(_ name: String, published: Set<String>, expected: Set<String>) {
            guard published != expected else { return }
            let missing = published.subtracting(expected).sorted()
            let extra = expected.subtracting(published).sorted()
            problems.append("\(name): only in IDOS \(missing), only in Kaštan \(extra).")
        }
        compare("advanced fields", published: publishedFields, expected: publishedFields.intersection(Self.knownFields))
        compare("transport IDs", published: modeIDs, expected: modeIDs.intersection(Self.modes.keys))
        compare(
            "filters",
            published: Set(publishedOptions.map(\.rawValue)),
            expected: Set(actual.options.map(\.rawValue))
        )
        compare(
            "transport modes",
            published: Set(publishedModes.map(\.rawValue)),
            expected: Set(actual.transportModes.map(\.rawValue))
        )
        for (name, expected) in Self.pickerValues {
            if let published = values[name] {
                compare(name, published: published, expected: expected)
            }
        }
        return problems
    }

    private static func captures(_ regex: NSRegularExpression, in text: String) -> [[String]] {
        regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).map { match in
            (0..<match.numberOfRanges).map { index in
                Range(match.range(at: index), in: text).map { String(text[$0]) } ?? ""
            }
        }
    }
}
