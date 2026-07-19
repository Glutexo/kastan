import Foundation
@testable import Kastan
import Testing
@testable import KastanCLI

@Test func defaultOutputNamesApplication() async {
    let output = await englishCommandRunner(client: MockIDOSClient()).output(for: [])

    #expect(output.contains("🌰 Kaštan"))
    #expect(output.contains("Search IDOS connections, departures, station timetables, stations, service routes"))
}

@Test func helpOutputShowsUsage() async {
    let output = await englishCommandRunner(client: MockIDOSClient()).output(for: ["--help"])

    #expect(output.contains("🌰 Usage:"))
    #expect(output.contains("connections"))
    #expect(output.contains("departures"))
    #expect(output.contains("station-timetables"))
    #expect(output.contains("timetables"))
    #expect(output.contains("aliases"))
    #expect(output.contains("stations"))
    #expect(output.contains("--timetable"))
    #expect(output.contains("--station"))
    #expect(output.contains("--arrival"))
    #expect(output.contains("--departure"))
    #expect(output.contains("--whole-week"))
    #expect(output.contains("--line"))
    #expect(output.contains("--via"))
    #expect(output.contains("--direct"))
    #expect(output.contains("--add-to-calendar"))
    #expect(output.contains("--verbose"))
    #expect(output.contains("--max-transfers"))
    #expect(output.contains("--min-transfer-time"))
    #expect(output.contains("--format"))
    #expect(output.contains("-T, --timetable"))
    #expect(output.contains("-o, --format"))
    #expect(output.contains("-v, --verbose"))
    #expect(output.contains("Show result and service IDs"))
    #expect(output.contains("kastan service <service-id> [-o text|markdown|json]"))
    #expect(output.contains("Direct connections only"))
    #expect(!output.contains("--jr"))
    #expect(output.contains("--version"))
}

@Test func systemLanguageSelectsFirstSupportedLocalization() async {
    let output = await CommandRunner(
        client: MockIDOSClient(),
        preferredLanguageIdentifiers: ["it-CZ", "cs-CZ"],
        environment: [:]
    ).output(for: ["--help"])
    let fallback = await CommandRunner(
        client: MockIDOSClient(),
        preferredLanguageIdentifiers: ["de-DE"],
        environment: ["LANG": "C.UTF-8"]
    ).output(for: ["--help"])

    #expect(output.contains("🌰 Použití:"))
    #expect(output.contains("⚙️ Možnosti:"))
    #expect(output.contains("--language, --lang"))
    #expect(fallback.contains("🌰 Usage:"))
}

@Test func posixLocaleSelectsCzechLocalization() async {
    let output = await CommandRunner(
        client: MockIDOSClient(),
        preferredLanguageIdentifiers: ["de-DE"],
        environment: ["LC_ALL": "cs_CZ.UTF-8"]
    ).output(for: [])

    #expect(output.contains("Vyhledávání spojení"))
    #expect(output.contains("Nápovědu zobrazíte"))
}

@Test func explicitLanguageOverridesSystemLanguage() async {
    let runner = CommandRunner(
        client: MockIDOSClient(),
        preferredLanguageIdentifiers: ["cs-CZ"],
        environment: [:]
    )
    let english = await runner.output(for: ["--lang=en", "--help"])
    let czech = await runner.output(for: ["--language", "cs", "--help"])

    #expect(english.contains("🌰 Usage:"))
    #expect(english.contains("Output language: en or cs"))
    #expect(czech.contains("🌰 Použití:"))
    #expect(czech.contains("Jazyk výstupu: en nebo cs"))
}

@Test func czechLanguageLocalizesConnectionText() async {
    let output = await englishCommandRunner(client: MockIDOSClient()).output(
        for: [
            "connections", "--from", "Praha", "--to", "Brno", "--timetable", "vlaky",
            "--verbose", "--limit", "1", "--language", "cs",
        ]
    )

    #expect(output.contains("🧭 Spojení Praha → Brno (Vlaky)"))
    #expect(output.contains("➡️  Přímý · ⚡ Nejrychlejší"))
    #expect(output.contains("ID: 396829589"))
    #expect(output.contains("ID spoje: vlaky:0-74552-18.06.2026 12:04:00"))
    #expect(output.contains("tarifní zóna P · nástupiště 4"))
}

@Test func czechLanguageLocalizesMarkdownAndErrors() async {
    let runner = englishCommandRunner(client: MockIDOSClient())
    let markdown = await runner.output(
        for: [
            "departures", "--station", "Ostrava,Hrabůvka,Benzina", "--timetable", "odis",
            "--format", "markdown", "--verbose", "--limit", "1", "--lang", "cs",
        ]
    )
    let error = await runner.output(for: ["stations", "Praha", "--unknown", "--language", "cs"])

    #expect(markdown.contains("## 🚏 Odjezdy"))
    #expect(markdown.contains("| # | Čas | Linka | Cíl | Tarifní zóna | Nástupiště | Přes | Dopravce | Zpoždění | ID |"))
    #expect(markdown.contains("`odis:1-4286-18.06.2026 16:03:00`"))
    #expect(error.contains("❌ Chyba: Neznámá volba: --unknown."))
}

@Test func localizedOutputKeepsJSONSchemaAndValuesStable() async throws {
    let output = await englishCommandRunner(client: MockIDOSClient()).output(
        for: ["timetables", "--format", "json", "--language", "cs"]
    )
    let json = try jsonDictionary(output)
    let timetables = try #require(json["timetables"] as? [[String: Any]])

    #expect(timetables.contains {
        $0["slug"] as? String == "vlaky" && $0["displayName"] as? String == "Trains"
    })
}

@Test func unsupportedAndMissingLanguagesReturnLocalizedErrors() async {
    let runner = CommandRunner(
        client: MockIDOSClient(),
        preferredLanguageIdentifiers: ["cs-CZ"],
        environment: [:]
    )
    let unsupported = await runner.output(for: ["--language", "de", "--format", "json"])
    let missing = await runner.output(for: ["--lang"])
    let unsupportedJSON = try? jsonDictionary(unsupported)

    #expect(unsupportedJSON?["error"] as? String == "Nepodporovaný jazyk: de. Použijte en nebo cs.")
    #expect(missing == "❌ Chyba: Chybí hodnota pro --lang. Použijte en nebo cs.")
}

@Test func everyLocalizationKeyExistsInBothLanguages() {
    for language in AppLanguage.allCases {
        let localization = Localization(language: language)
        for key in LocalizationKey.allCases {
            #expect(localization.text(key) != key.rawValue, "Missing \(key.rawValue) for \(language.rawValue)")
        }
    }
}

@Test func versionOutputShowsCurrentVersion() async {
    let output = await englishCommandRunner(client: MockIDOSClient()).output(for: ["--version"])

    #expect(output == "0.1.0")
}

@Test func suggestCommandPrintsSuggestions() async {
    let output = await englishCommandRunner(client: MockIDOSClient()).output(for: ["suggest", "Praha", "--timetable", "pid"])

    #expect(output.contains("🔎 Suggested places (Prague + PID)"))
    #expect(output.contains("Praha hl.n."))
    #expect(output.contains("station"))
}

@Test func suggestCommandPrintsJSON() async throws {
    let output = await englishCommandRunner(client: MockIDOSClient()).output(
        for: ["suggest", "Praha", "--timetable", "pid", "--format", "json"]
    )
    let json = try jsonDictionary(output)

    #expect((json["query"] as? String) == "Praha")
    #expect((json["timetable"] as? [String: Any])?["displayName"] as? String == "Prague + PID")
    #expect((json["suggestions"] as? [[String: Any]])?.first?["text"] as? String == "Praha hl.n.")
}

@Test func suggestCommandAcceptsShortOptions() async throws {
    let output = await englishCommandRunner(client: MockIDOSClient()).output(
        for: ["suggest", "Praha", "-T", "pid", "-o", "json", "-l", "1"]
    )
    let json = try jsonDictionary(output)

    #expect((json["query"] as? String) == "Praha")
    #expect((json["timetable"] as? [String: Any])?["displayName"] as? String == "Prague + PID")
}

@Test func suggestCommandRejectsUnknownOptions() async {
    let output = await englishCommandRunner(client: MockIDOSClient()).output(for: ["suggest", "Praha", "--unknown"])

    #expect(output.contains("❌ Error: Unknown option: --unknown."))
}

@Test func stationsCommandPrintsStations() async {
    let output = await englishCommandRunner(client: MockIDOSClient()).output(for: ["stations", "Praha", "--timetable", "pid"])

    #expect(output.contains("🚏 Stations (Prague + PID):"))
    #expect(output.contains("Praha hl.n."))
    #expect(output.contains("station"))
}

@Test func stationsCommandPrintsJSON() async throws {
    let output = await englishCommandRunner(client: MockIDOSClient()).output(
        for: ["stations", "Praha", "-T", "pid", "-o", "json", "-l", "1"]
    )
    let json = try jsonDictionary(output)

    #expect((json["query"] as? String) == "Praha")
    #expect((json["timetable"] as? [String: Any])?["displayName"] as? String == "Prague + PID")
    #expect((json["stations"] as? [[String: Any]])?.first?["text"] as? String == "Praha hl.n.")
    #expect(json["suggestions"] == nil)
}

@Test func stationsCommandRejectsUnknownOptions() async {
    let output = await englishCommandRunner(client: MockIDOSClient()).output(for: ["stations", "Praha", "--unknown"])

    #expect(output.contains("❌ Error: Unknown option: --unknown."))
}

@Test func connectionCommandPrintsConnections() async {
    let output = await englishCommandRunner(client: MockIDOSClient()).output(
        for: ["connections", "--from", "Praha", "--to", "Brno", "--timetable", "vlaky", "--limit", "1"]
    )

    #expect(output.contains("🧭 Connections Praha → Brno (Trains)"))
    #expect(output.contains("1. ➡️  Direct · ⚡ Shortest —"))
    #expect(output.contains("\u{001B}[1m12:04\u{001B}[0m Praha hl.n. → \u{001B}[1m15:44\u{001B}[0m Brno hl.n."))
    #expect(output.contains("🚆"))
    #expect(output.contains("R9"))
    #expect(!output.contains("ID: 396829589"))
    #expect(!output.contains("Service ID:"))
    #expect(!output.contains("tariff zone P · platform 4"))
    #expect(!output.contains("Currently no delay"))
}

@Test func connectionCommandHighlightsDirectAndShortestResultsIndependently() async {
    let output = await englishCommandRunner(
        client: MockIDOSClient(connectionResults: [
            connectionResult(id: "1", duration: "3 h 40 min", legNames: ["R 1"]),
            connectionResult(id: "2", duration: "3 h 15 min", legNames: ["R 2", "R 3"]),
            connectionResult(id: "3", duration: "3 h 50 min", legNames: ["R 4", "R 5"]),
        ])
    ).output(
        for: ["connections", "--from", "Praha", "--to", "Brno", "--timetable", "vlaky", "--limit", "3"]
    )
    let lines = output.split(separator: "\n")
    let first = lines.first { $0.hasPrefix("1. ") }
    let second = lines.first { $0.hasPrefix("2. ") }
    let third = lines.first { $0.hasPrefix("3. ") }

    #expect(first?.contains("➡️  Direct") == true)
    #expect(first?.contains("⚡ Shortest") == false)
    #expect(second?.contains("➡️  Direct") == false)
    #expect(second?.contains("⚡ Shortest") == true)
    #expect(third?.contains("➡️  Direct") == false)
    #expect(third?.contains("⚡ Shortest") == false)
}

@Test func connectionCommandHighlightsAllResultsTiedForShortestDuration() async {
    let output = await englishCommandRunner(
        client: MockIDOSClient(connectionResults: [
            connectionResult(id: "1", duration: "2 h 5 min", legNames: ["R 1"]),
            connectionResult(id: "2", duration: "125 min", legNames: ["R 2", "R 3"]),
        ])
    ).output(
        for: ["connections", "--from", "Praha", "--to", "Brno", "--timetable", "vlaky", "--limit", "2"]
    )
    let resultHeadings = output.split(separator: "\n").filter { $0.hasPrefix("1. ") || $0.hasPrefix("2. ") }

    #expect(resultHeadings.count == 2)
    #expect(resultHeadings.allSatisfy { $0.contains("⚡ Shortest") })
}

@Test func connectionCommandPassesLimitToIDOSRequest() async {
    let output = await englishCommandRunner(
        client: MockIDOSClient(
            expectedConnectionResultLimit: 12,
            validatesConnectionResultLimit: true
        )
    ).output(
        for: ["connections", "--from", "Praha", "--to", "Brno", "--timetable", "vlaky", "--limit", "12"]
    )

    #expect(output.contains("🧭 Connections Praha → Brno (Trains)"))
}

@Test func connectionCommandPrintsVerboseConnections() async {
    let output = await englishCommandRunner(client: MockIDOSClient()).output(
        for: ["connections", "--from", "Praha", "--to", "Brno", "--timetable", "vlaky", "--limit", "1", "--verbose"]
    )

    #expect(output.contains("tariff zone P · platform 4"))
    #expect(output.contains("ID: 396829589"))
    #expect(output.contains("Service ID: vlaky:0-74552-18.06.2026 12:04:00"))
    #expect(output.contains("České dráhy, a.s."))
    #expect(output.contains("Currently no delay"))
}

@Test func connectionCommandRequestsViaPlaces() async {
    let output = await englishCommandRunner(client: MockIDOSClient(expectedVia: ["Pardubice", "Olomouc"])).output(
        for: [
            "connections", "--from", "Praha", "--to", "Brno", "--timetable", "vlaky",
            "--via", "Pardubice", "--via=Olomouc", "--limit", "1",
        ]
    )

    #expect(output.contains("🧭 Connections Praha → Brno via Pardubice, Olomouc (Trains)"))
    #expect(output.contains("R9"))
}

@Test func connectionCommandAcceptsShortOptions() async {
    let output = await englishCommandRunner(
        client: MockIDOSClient(
            expectedIsArrival: true,
            expectedOnlyDirect: true,
            expectedVia: ["Pardubice"],
            expectedMaxTransfers: 0,
            expectedMinimumTransferTime: 10
        )
    ).output(
        for: [
            "connections", "-f", "Praha", "-t", "Brno", "-T", "vlaky", "-d", "18.6.2026",
            "-m", "15:00", "-a", "-x", "-V", "Pardubice", "-X", "0", "-M", "10", "-v", "-l", "1",
        ]
    )

    #expect(output.contains("🧭 Connections Praha → Brno via Pardubice (Trains)"))
    #expect(output.contains("tariff zone P · platform 4"))
}

@Test func connectionCommandAcceptsCombinedShortFlags() async {
    let output = await englishCommandRunner(
        client: MockIDOSClient(expectedOnlyDirect: true)
    ).output(
        for: ["connections", "-vx", "-f", "Praha", "-t", "Brno", "-T", "vlaky", "-l", "1"]
    )

    #expect(output.contains("🧭 Connections Praha → Brno (Trains)"))
    #expect(output.contains("tariff zone P · platform 4"))
}

@Test func rootCommandAcceptsCombinedShortFlagsBeforeRoute() async {
    let output = await englishCommandRunner(
        client: MockIDOSClient(expectedOnlyDirect: true)
    ).output(
        for: ["-vx", "Praha", "Brno", "-T", "vlaky", "-l", "1"]
    )

    #expect(output.contains("🧭 Connections Praha → Brno (Trains)"))
    #expect(output.contains("tariff zone P · platform 4"))
}

@Test func rootCommandAcceptsCombinedShortFlagsWithValueOptionAtEnd() async {
    let output = await englishCommandRunner(
        client: MockIDOSClient(expectedOnlyDirect: true)
    ).output(
        for: ["-vxT", "vlaky", "Praha", "Brno", "-l", "1"]
    )

    #expect(output.contains("🧭 Connections Praha → Brno (Trains)"))
    #expect(output.contains("tariff zone P · platform 4"))
}

@Test func connectionCommandAcceptsHyphenRouteExpression() async {
    let output = await englishCommandRunner(client: MockIDOSClient()).output(
        for: ["connections", "Praha-Brno", "--timetable", "vlaky", "--limit", "1"]
    )

    #expect(output.contains("🧭 Connections Praha → Brno (Trains)"))
    #expect(output.contains("R9"))
}

@Test func rootCommandAcceptsHyphenRouteExpression() async {
    let output = await englishCommandRunner(client: MockIDOSClient()).output(
        for: ["Praha-Brno", "--timetable", "vlaky", "--limit", "1"]
    )

    #expect(output.contains("🧭 Connections Praha → Brno (Trains)"))
    #expect(output.contains("R9"))
}

@Test func connectionCommandAcceptsTwoPositionalPlaces() async {
    let output = await englishCommandRunner(client: MockIDOSClient()).output(
        for: ["connections", "Praha", "Brno", "--timetable", "vlaky", "--limit", "1"]
    )

    #expect(output.contains("🧭 Connections Praha → Brno (Trains)"))
    #expect(output.contains("R9"))
}

@Test func rootCommandAcceptsTwoPositionalPlaces() async {
    let output = await englishCommandRunner(client: MockIDOSClient()).output(
        for: ["Praha", "Brno", "--timetable", "vlaky", "--limit", "1"]
    )

    #expect(output.contains("🧭 Connections Praha → Brno (Trains)"))
    #expect(output.contains("R9"))
}

@Test func connectionCommandAcceptsAsciiArrowRouteExpression() async {
    let output = await englishCommandRunner(client: MockIDOSClient()).output(
        for: ["connections", "Praha->Brno", "--timetable", "vlaky", "--limit", "1"]
    )

    #expect(output.contains("🧭 Connections Praha → Brno (Trains)"))
    #expect(output.contains("R9"))
}

@Test func rootCommandAcceptsAsciiArrowRouteExpression() async {
    let output = await englishCommandRunner(client: MockIDOSClient()).output(
        for: ["Praha->Brno", "--timetable", "vlaky", "--limit", "1"]
    )

    #expect(output.contains("🧭 Connections Praha → Brno (Trains)"))
    #expect(output.contains("R9"))
}

@Test func connectionCommandAcceptsUnicodeArrowRouteExpression() async {
    let output = await englishCommandRunner(client: MockIDOSClient()).output(
        for: ["connections", "Praha→Brno", "--timetable", "vlaky", "--limit", "1"]
    )

    #expect(output.contains("🧭 Connections Praha → Brno (Trains)"))
    #expect(output.contains("R9"))
}

@Test func rootCommandAcceptsUnicodeArrowRouteExpression() async {
    let output = await englishCommandRunner(client: MockIDOSClient()).output(
        for: ["Praha→Brno", "--timetable", "vlaky", "--limit", "1"]
    )

    #expect(output.contains("🧭 Connections Praha → Brno (Trains)"))
    #expect(output.contains("R9"))
}

@Test func connectionCommandPrintsMarkdown() async {
    let output = await englishCommandRunner(client: MockIDOSClient()).output(
        for: ["connections", "--from", "Praha", "--to", "Brno", "--timetable", "vlaky", "--format", "markdown", "--limit", "1"]
    )

    #expect(output.contains("## 🧭 Connections"))
    #expect(output.contains("### 1. ➡️  Direct · ⚡ Shortest — **12:04** Praha hl.n. → **15:44** Brno hl.n."))
    #expect(output.contains("| Line | From | Departure | To | Arrival |"))
    #expect(output.contains("| 🚆 <span style=\"color: #008000\">R9 (R 981 Vysočina)</span> | Praha hl.n. | **12:04** | Brno hl.n. | **15:44** |"))
    #expect(output.contains(#"🚆 <span style="color: #008000">R9 (R 981 Vysočina)</span>"#))
    #expect(!output.contains("**ID:**"))
    #expect(!output.contains("From Tariff Zone"))
    #expect(!output.contains("Currently no delay"))
}

@Test func connectionCommandPrintsVerboseMarkdown() async {
    let output = await englishCommandRunner(client: MockIDOSClient()).output(
        for: [
            "connections", "--from", "Praha", "--to", "Brno", "--timetable", "vlaky",
            "--format", "markdown", "--limit", "1", "--verbose",
        ]
    )

    #expect(output.contains("| Line | Service ID | From | From Tariff Zone | From Platform | Departure | To | To Tariff Zone | To Platform | Arrival | Carrier | Delay |"))
    #expect(output.contains("| 🚆 <span style=\"color: #008000\">R9 (R 981 Vysočina)</span> | `vlaky:0-74552-18.06.2026 12:04:00` | Praha hl.n. | P | 4 | **12:04** | Brno hl.n. | 100 |  | **15:44** | České dráhy, a.s. | Currently no delay |"))
    #expect(output.contains("**ID:** `396829589`"))
}

@Test func connectionCommandPrintsMarkdownWithVia() async {
    let output = await englishCommandRunner(client: MockIDOSClient(expectedVia: ["Pardubice"])).output(
        for: [
            "connections", "--from", "Praha", "--to", "Brno", "--via", "Pardubice",
            "--timetable", "vlaky", "--format", "markdown", "--limit", "1",
        ]
    )

    #expect(output.contains("**Via:** Pardubice"))
}

@Test func connectionCommandPrintsJSONWithTransferLimits() async throws {
    let output = await englishCommandRunner(
        client: MockIDOSClient(expectedIsArrival: true, expectedMaxTransfers: 0, expectedMinimumTransferTime: 10)
    ).output(
        for: [
            "connections", "--from", "Praha", "--to", "Brno", "--timetable", "vlaky",
            "--arrival", "--max-transfers", "0", "--min-transfer-time", "10", "--format", "json", "--limit", "1",
        ]
    )
    let json = try jsonDictionary(output)
    let request = json["request"] as? [String: Any]

    #expect(request?["isArrival"] as? Bool == true)
    #expect(request?["maxTransfers"] as? Int == 0)
    #expect(request?["minimumTransferTime"] as? Int == 10)
    let connection = (json["connections"] as? [[String: Any]])?.first
    #expect(connection?["id"] as? String == "396829589")
    let leg = (connection?["legs"] as? [[String: Any]])?.first
    #expect(leg?["id"] as? String == "vlaky:0-74552-18.06.2026 12:04:00")
    #expect(connection?["isDirect"] as? Bool == true)
    #expect(connection?["isShortest"] as? Bool == true)
}

@Test func connectionCommandPrintsIDOSCalendar() async {
    let output = await englishCommandRunner(client: MockIDOSClient()).output(
        for: ["connections", "--from", "Praha", "--to", "Brno", "--timetable", "vlaky", "--format", "ics"]
    )

    #expect(output.contains("BEGIN:VCALENDAR"))
    #expect(output.contains("SUMMARY:Connection Praha hl.n. >> Brno hl.n."))
    #expect(output.contains("END:VCALENDAR"))
}

@Test func connectionCommandAddsIDOSCalendar() async {
    let output = await englishCommandRunner(
        client: MockIDOSClient(),
        calendarImporter: MockCalendarImporter(path: "/tmp/kastan-test.ics")
    ).output(
        for: ["connections", "--from", "Praha", "--to", "Brno", "--timetable", "vlaky", "--add-to-calendar"]
    )

    #expect(output.contains("📅 Opened calendar import for Praha → Brno"))
    #expect(output.contains("/tmp/kastan-test.ics"))
}

@Test func connectionCommandAddsIDOSCalendarAsJSON() async throws {
    let output = await englishCommandRunner(
        client: MockIDOSClient(),
        calendarImporter: MockCalendarImporter(path: "/tmp/kastan-test.ics")
    ).output(
        for: [
            "connections", "--from", "Praha", "--to", "Brno", "--timetable", "vlaky",
            "--add-to-calendar", "--format", "json",
        ]
    )
    let json = try jsonDictionary(output)

    #expect(json["path"] as? String == "/tmp/kastan-test.ics")
    #expect((json["connection"] as? [String: Any])?["id"] as? String == "396829589")
}

@Test func connectionCommandRejectsCalendarImportWithICSOutput() async {
    let output = await englishCommandRunner(client: MockIDOSClient()).output(
        for: [
            "connections", "--from", "Praha", "--to", "Brno", "--timetable", "vlaky",
            "--add-to-calendar", "--format", "ics",
        ]
    )

    #expect(output.contains("Conflicting options: --add-to-calendar and --format ics"))
}

@Test func connectionCommandPrintsJSONWithVia() async throws {
    let output = await englishCommandRunner(client: MockIDOSClient(expectedVia: ["Pardubice"])).output(
        for: [
            "connections", "--from", "Praha", "--to", "Brno", "--via", "Pardubice",
            "--timetable", "vlaky", "--format", "json", "--limit", "1",
        ]
    )
    let json = try jsonDictionary(output)
    let request = json["request"] as? [String: Any]

    #expect(request?["via"] as? [String] == ["Pardubice"])
}

@Test func connectionCommandRequestsDirectConnections() async {
    let output = await englishCommandRunner(client: MockIDOSClient(expectedOnlyDirect: true)).output(
        for: ["connections", "--from", "Praha", "--to", "Brno", "--timetable", "vlaky", "--direct", "--limit", "1"]
    )

    #expect(output.contains("🧭 Connections Praha → Brno (Trains)"))
    #expect(output.contains("R9"))
}

@Test func connectionCommandRequestsArrivalTime() async {
    let output = await englishCommandRunner(client: MockIDOSClient(expectedIsArrival: true)).output(
        for: ["connections", "--from", "Praha", "--to", "Brno", "--timetable", "vlaky", "--time", "15:00", "--arrival", "--limit", "1"]
    )

    #expect(output.contains("🧭 Connections Praha → Brno (Trains)"))
    #expect(output.contains("R9"))
}

@Test func connectionCommandRequestsDepartureTime() async {
    let output = await englishCommandRunner(client: MockIDOSClient(expectedIsArrival: false)).output(
        for: ["connections", "--from", "Praha", "--to", "Brno", "--timetable", "vlaky", "--time", "15:00", "--departure", "--limit", "1"]
    )

    #expect(output.contains("🧭 Connections Praha → Brno (Trains)"))
    #expect(output.contains("R9"))
}

@Test func connectionCommandRejectsConflictingTimeModes() async {
    let output = await englishCommandRunner(client: MockIDOSClient()).output(
        for: ["connections", "--from", "Praha", "--to", "Brno", "--timetable", "vlaky", "--time", "15:00", "--arrival", "--departure"]
    )

    #expect(output.contains("❌ Error: Conflicting options: --arrival and --departure. Use only one."))
}

@Test func connectionCommandRejectsUnknownOptions() async {
    let output = await englishCommandRunner(client: MockIDOSClient()).output(
        for: ["connections", "--from", "Praha", "--to", "Brno", "--timetable", "vlaky", "--unknown"]
    )

    #expect(output.contains("❌ Error: Unknown option: --unknown."))
}

@Test func connectionCommandRejectsUnknownOptionsAsJSON() async throws {
    let output = await englishCommandRunner(client: MockIDOSClient()).output(
        for: ["connections", "--from", "Praha", "--to", "Brno", "--format", "json", "--unknown"]
    )
    let json = try jsonDictionary(output)

    #expect(json["error"] as? String == "Unknown option: --unknown.")
}

@Test func connectionCommandPrintsNetworkErrors() async {
    let output = await englishCommandRunner(client: MockIDOSClient(failConnectionsWithNetworkError: true)).output(
        for: ["connections", "--from", "Praha", "--to", "Brno", "--timetable", "vlaky"]
    )

    #expect(output.contains("❌ Error: Network request failed. Check your internet connection."))
}

@Test func connectionCommandReportsAmbiguousPlaceNames() async {
    let output = await englishCommandRunner(
        client: MockIDOSClient(suggestionResultsByPrefix: ["sí pe": ambiguousPIDStationSuggestions()])
    ).output(
        for: ["connections", "Santoška", "sí pe", "--timetable", "pid"]
    )

    #expect(output.contains("❌ Error: Ambiguous place name: sí pe (Prague + PID)."))
    #expect(output.contains("1. Sídliště Petrovice - stop (Praha)"))
    #expect(output.contains("2. Sídliště Petřiny - stop (Praha)"))
}

@Test func connectionCommandLimitsMaximumTransfers() async {
    let output = await englishCommandRunner(client: MockIDOSClient(expectedMaxTransfers: 0)).output(
        for: ["connections", "--from", "Praha", "--to", "Brno", "--timetable", "vlaky", "--max-transfers", "0", "--limit", "1"]
    )

    #expect(output.contains("🧭 Connections Praha → Brno (Trains)"))
    #expect(output.contains("R9"))
}

@Test func connectionCommandSetsMinimumTransferTime() async {
    let output = await englishCommandRunner(client: MockIDOSClient(expectedMinimumTransferTime: 10)).output(
        for: ["connections", "--from", "Praha", "--to", "Brno", "--timetable", "vlaky", "--min-transfer-time", "10", "--limit", "1"]
    )

    #expect(output.contains("🧭 Connections Praha → Brno (Trains)"))
    #expect(output.contains("R9"))
}

@Test func connectionCommandRejectsNegativeMaximumTransfers() async {
    let output = await englishCommandRunner(client: MockIDOSClient()).output(
        for: ["connections", "--from", "Praha", "--to", "Brno", "--timetable", "vlaky", "--max-transfers", "-1"]
    )

    #expect(output.contains("❌ Error: Invalid --max-transfers: -1. Use a non-negative integer."))
}

@Test func connectionCommandRejectsNegativeShortMaximumTransfers() async {
    let output = await englishCommandRunner(client: MockIDOSClient()).output(
        for: ["connections", "-f", "Praha", "-t", "Brno", "-T", "vlaky", "-X", "-1"]
    )

    #expect(output.contains("❌ Error: Invalid -X: -1. Use a non-negative integer."))
}

@Test func connectionCommandRejectsNegativeMinimumTransferTime() async {
    let output = await englishCommandRunner(client: MockIDOSClient()).output(
        for: ["connections", "--from", "Praha", "--to", "Brno", "--timetable", "vlaky", "--min-transfer-time", "-1"]
    )

    #expect(output.contains("❌ Error: Invalid --min-transfer-time: -1. Use a non-negative integer."))
}

@Test func departuresCommandPrintsDepartures() async {
    let output = await englishCommandRunner(client: MockIDOSClient()).output(
        for: ["departures", "--station", "Ostrava,Hrabůvka,Benzina", "--timetable", "odis", "--time", "16:00", "--limit", "1"]
    )

    #expect(output.contains("🚏 Departures Ostrava,Hrabůvka,Benzina (ODIS)"))
    #expect(output.contains("\u{001B}[1m16:03\u{001B}[0m"))
    #expect(output.contains("🚌"))
    #expect(output.contains("Bus 980"))
    #expect(output.contains("Rožnov p.Radh.,,aut.st."))
    #expect(output.contains("via Frýdek-Místek,Místek,Anenská"))
    #expect(!output.contains("ID: odis:1-4286-18.06.2026 16:03:00"))
    #expect(!output.contains("tariff zone 70 · platform 1"))
    #expect(!output.contains("Currently no delay"))
}

@Test func departuresCommandPrintsVerboseDepartures() async {
    let output = await englishCommandRunner(client: MockIDOSClient()).output(
        for: [
            "departures", "--station", "Ostrava,Hrabůvka,Benzina", "--timetable", "odis",
            "--time", "16:00", "--limit", "1", "--verbose",
        ]
    )

    #expect(output.contains("tariff zone 70 · platform 1"))
    #expect(output.contains("ID: odis:1-4286-18.06.2026 16:03:00"))
    #expect(output.contains("Transdev Slezsko a.s."))
    #expect(output.contains("Currently no delay"))
}

@Test func stationTimetablesCommandPrintsCompleteMHDStationTimetable() async {
    let output = await englishCommandRunner(client: MockIDOSClient()).output(
        for: [
            "station-timetables", "--line", "Bus 154", "--from", "Strašnická",
            "--to", "Sídliště Libuš", "--timetable", "pid", "--date", "17.7.2026", "--whole-week",
        ]
    )

    #expect(output.contains("🗓️ Station Timetable 🚌 Bus 154 · Strašnická → Sídliště Libuš (Prague + PID)"))
    #expect(output.contains("🚧 Lockout timetable"))
    #expect(output.contains("🛤️ Route:"))
    #expect(output.contains("1. 📍 Strašnická · +0 min · tariff zone 0 · platform 1 · Selected · request stop"))
    #expect(output.contains("2. 🚏 Na Hroudě · +1 min · tariff zone B · platform 2 · wheelchair accessible stop"))
    #expect(output.contains("🕒 17.7.2026 Friday:"))
    #expect(output.contains("\u{001B}[1m5\u{001B}[0m: 13 35A 55"))
    #expect(output.contains("ℹ️ Notes:"))
    #expect(output.contains("A: runs only to stop Háje"))
}

@Test func stationTimetablesCommandAcceptsShortOptionsAndPrintsMarkdown() async {
    let output = await englishCommandRunner(client: MockIDOSClient()).output(
        for: [
            "station-timetables", "-wL", "Bus 154", "-f", "Strašnická", "-t", "Sídliště Libuš",
            "-T", "pid", "-d", "17.7.2026", "-o", "markdown",
        ]
    )

    #expect(output.contains("## 🗓️ Station Timetable"))
    #expect(output.contains("**Line:** 🚌 Bus 154"))
    #expect(output.contains("| # | Station | Minutes | Tariff Zone | Platform | Selected | Notes |"))
    #expect(output.contains("| 1 | Strašnická | 0 | 0 | 1 | Yes | request stop |"))
    #expect(output.contains("### 🕒 17.7.2026 Friday"))
    #expect(output.contains("| **5** | 13 35A 55 |"))
}

@Test func stationTimetablesCommandPrintsStableJSON() async throws {
    let output = await englishCommandRunner(client: MockIDOSClient()).output(
        for: [
            "station-timetable", "-L", "Bus 154", "-f", "Strašnická", "-t", "Sídliště Libuš",
            "-T", "pid", "-d", "17.7.2026", "-w", "-o", "json",
        ]
    )
    let json = try jsonDictionary(output)
    let request = try #require(json["request"] as? [String: Any])
    let result = try #require(json["stationTimetable"] as? [String: Any])
    let stops = try #require(result["stops"] as? [[String: Any]])

    #expect(request["line"] as? String == "Bus 154")
    #expect(request["wholeWeek"] as? Bool == true)
    #expect(result["lineName"] as? String == "Bus 154")
    #expect(stops.first?["isSelected"] as? Bool == true)
    #expect(stops.first?["platform"] as? String == "1")
    #expect((result["schedules"] as? [[String: Any]])?.count == 1)
}

@Test func stationTimetablesCommandLocalizesCzechOutputAndIDOSRequest() async {
    let output = await englishCommandRunner(
        client: MockIDOSClient(expectedStationTimetableLanguage: .czech)
    ).output(
        for: [
            "station-timetables", "-L", "Bus 154", "-f", "Strašnická", "-t", "Sídliště Libuš",
            "-T", "pid", "-d", "17.7.2026", "-w", "--language", "cs",
        ]
    )

    #expect(output.contains("🗓️ Zastávkový jízdní řád"))
    #expect(output.contains("🚧 Výlukový jízdní řád"))
    #expect(output.contains("🛤️ Trasa:"))
    #expect(output.contains("tarifní zóna 0 · stanoviště 1 · Vybraná"))
    #expect(output.contains("ℹ️ Poznámky:"))
}

@Test func stationTimetablesCommandRequiresLineAndDirectionAndRejectsUnknownOptions() async {
    let runner = englishCommandRunner(client: MockIDOSClient())
    let missing = await runner.output(for: ["station-timetables", "--line", "Bus 154"])
    let unknown = await runner.output(
        for: [
            "station-timetables", "-L", "Bus 154", "-f", "Strašnická", "-t", "Sídliště Libuš",
            "--unknown",
        ]
    )

    #expect(missing.contains("Usage: kastan station-timetables"))
    #expect(unknown.contains("❌ Error: Unknown option: --unknown."))
}

@Test func serviceCommandPrintsCompleteRoute() async {
    let output = await englishCommandRunner(client: MockIDOSClient()).output(
        for: ["service", "vlaky:0-74552-18.06.2026 12:04:00"]
    )

    #expect(output.contains("🚆 \u{001B}[38;2;0;128;0mRJ 1051 RegioJet\u{001B}[0m · Service (Trains)"))
    #expect(output.contains("Service ID: vlaky:0-74552-18.06.2026 12:04:00"))
    #expect(output.contains("🛤️ Route:"))
    #expect(output.contains("1. 📍 Praha-Zahradní Město — Departure \u{001B}[1m11:45\u{001B}[0m · track 3 · 0 km"))
    #expect(output.contains("🚧 Traffic restrictions"))
    #expect(output.contains("2. 📍 Praha hl.n. — Arrival \u{001B}[1m11:53\u{001B}[0m · Departure \u{001B}[1m12:04\u{001B}[0m"))
    #expect(output.contains("🚇 transfer to the undeground"))
    #expect(output.contains("♿ wheelchair accessible station"))
    #expect(output.contains("🚉 rail station"))
    #expect(output.contains("ℹ️ Information:"))
    #expect(output.contains("České dráhy, a.s."))
}

@Test func serviceCommandPrintsMarkdown() async {
    let output = await englishCommandRunner(client: MockIDOSClient()).output(
        for: [
            "service", "vlaky:0-74552-18.06.2026 12:04:00", "--format", "markdown",
        ]
    )

    #expect(output.contains("## 🚆 <span style=\"color: #008000\">RJ 1051 RegioJet</span> · Service"))
    #expect(output.contains("**Service ID:** `vlaky:0-74552-18.06.2026 12:04:00`"))
    #expect(output.contains("| # | Station | Arrival | Departure | Tariff Zone | Platform | Track | Platform/Track | Distance | Notes |"))
    #expect(output.contains("| 2 | Praha hl.n. | **11:53** | **12:04** | P |  |  |  | 7 km | 🚇 transfer to the undeground |"))
    #expect(output.contains("| 3 | Brno hl.n. | **15:44** |  |  |  |  | 3/1 | 262 km | ♿ wheelchair accessible station<br>🚉 rail station |"))
}

@Test func serviceCommandPrintsJSON() async throws {
    let output = await englishCommandRunner(client: MockIDOSClient()).output(
        for: ["service", "vlaky:0-74552-18.06.2026 12:04:00", "-o", "json"]
    )
    let json = try jsonDictionary(output)
    let service = json["service"] as? [String: Any]
    let stops = service?["stops"] as? [[String: Any]]

    #expect((service?["timetable"] as? [String: Any])?["slug"] as? String == "vlaky")
    #expect(service?["id"] as? String == "vlaky:0-74552-18.06.2026 12:04:00")
    #expect(stops?.count == 3)
    #expect(stops?[2]["notes"] as? [String] == ["wheelchair accessible station", "rail station"])
}

@Test func serviceCommandLocalizesCzechOutput() async {
    let output = await englishCommandRunner(
        client: MockIDOSClient(expectedServiceLanguage: .czech)
    ).output(
        for: ["service", "vlaky:0-74552-18.06.2026 12:04:00", "--language", "cs"]
    )

    #expect(output.contains("· Spoj (Vlaky)"))
    #expect(output.contains("ID spoje: vlaky:0-74552-18.06.2026 12:04:00"))
    #expect(output.contains("🛤️ Trasa:"))
    #expect(output.contains("Příjezd \u{001B}[1m11:53\u{001B}[0m · Odjezd \u{001B}[1m12:04\u{001B}[0m"))
    #expect(output.contains("🚧 Omezení provozu"))
    #expect(output.contains("🚇 přestup na Metro"))
    #expect(output.contains("♿ bezbariérově přístupná stanice"))
    #expect(output.contains("🚉 zastávka s možností přestupu na železniční dopravu"))
}

@Test func serviceCommandRequiresIdentifier() async {
    let output = await englishCommandRunner(client: MockIDOSClient()).output(for: ["service", "--timetable", "vlaky"])

    #expect(output.contains("Usage: kastan service <service-id>"))
}

@Test func serviceCommandRejectsInvalidIdentifierBeforeNetworkRequest() async {
    let client = IDOSClient(baseURL: URL(string: "http://127.0.0.1:9")!)
    let output = await englishCommandRunner(client: client).output(
        for: ["service", "not-an-id", "--timetable", "vlaky"]
    )

    #expect(output.contains("Invalid service ID: not-an-id."))
    #expect(!output.contains("Network request failed"))
}

@Test func departuresCommandAcceptsShortOptions() async {
    let output = await englishCommandRunner(client: MockIDOSClient()).output(
        for: ["departures", "-s", "Ostrava,Hrabůvka,Benzina", "-T", "odis", "-m", "16:00", "-v", "-l", "1"]
    )

    #expect(output.contains("🚏 Departures Ostrava,Hrabůvka,Benzina (ODIS)"))
    #expect(output.contains("tariff zone 70 · platform 1"))
}

@Test func departuresCommandPrintsResolvedStationName() async {
    let output = await englishCommandRunner(
        client: MockIDOSClient(
            expectedStation: "Frýdek,sportovní",
            resolvedStationName: "Frýdek,Sportovní hala Polárka"
        )
    ).output(
        for: ["departures", "--from", "Frýdek,sportovní", "--timetable", "odis", "--time", "16:00", "--limit", "1"]
    )

    #expect(output.contains("🚏 Departures Frýdek,Sportovní hala Polárka (ODIS)"))
    #expect(!output.contains("🚏 Departures Frýdek,sportovní (ODIS)"))
}

@Test func departuresCommandAcceptsFromOption() async {
    let output = await englishCommandRunner(client: MockIDOSClient()).output(
        for: ["departures", "--from", "Ostrava,Hrabůvka,Benzina", "--timetable", "odis", "--time", "16:00", "--limit", "1"]
    )

    #expect(output.contains("🚏 Departures Ostrava,Hrabůvka,Benzina (ODIS)"))
    #expect(output.contains("\u{001B}[1m16:03\u{001B}[0m"))
}

@Test func rootCommandWithOnePlacePrintsDepartures() async {
    let output = await englishCommandRunner(client: MockIDOSClient()).output(
        for: ["Ostrava,Hrabůvka,Benzina", "--timetable", "odis", "--time", "16:00", "--limit", "1"]
    )

    #expect(output.contains("🚏 Departures Ostrava,Hrabůvka,Benzina (ODIS)"))
    #expect(output.contains("\u{001B}[1m16:03\u{001B}[0m"))
}

@Test func departuresCommandPrintsJSON() async throws {
    let output = await englishCommandRunner(client: MockIDOSClient(expectedDepartureIsArrival: true)).output(
        for: [
            "departures", "--station", "Ostrava,Hrabůvka,Benzina", "--timetable", "odis",
            "--time", "16:00", "--arrival", "--format", "json", "--limit", "1",
        ]
    )
    let json = try jsonDictionary(output)
    let request = json["request"] as? [String: Any]

    #expect(request?["station"] as? String == "Ostrava,Hrabůvka,Benzina")
    #expect(request?["isArrival"] as? Bool == true)
    #expect((json["departures"] as? [[String: Any]])?.first?["lineName"] as? String == "Bus 980")
}

@Test func departuresCommandPrintsMarkdown() async {
    let output = await englishCommandRunner(client: MockIDOSClient()).output(
        for: [
            "departures", "--station", "Ostrava,Hrabůvka,Benzina", "--timetable", "odis",
            "--format", "markdown", "--limit", "1",
        ]
    )

    #expect(output.contains("## 🚏 Departures"))
    #expect(output.contains("| # | Time | Line | Destination | Via |"))
    #expect(output.contains("| 1 | **16:03** | 🚌 <span style=\"color: #0000FF\">Bus 980</span> | Rožnov p.Radh.,,aut.st. | Frýdek-Místek,Místek,Anenská |"))
    #expect(output.contains(#"🚌 <span style="color: #0000FF">Bus 980</span>"#))
    #expect(!output.contains("| ID |"))
    #expect(!output.contains("Tariff Zone"))
    #expect(!output.contains("Currently no delay"))
}

@Test func departuresCommandPrintsVerboseMarkdown() async {
    let output = await englishCommandRunner(client: MockIDOSClient()).output(
        for: [
            "departures", "--station", "Ostrava,Hrabůvka,Benzina", "--timetable", "odis",
            "--format", "markdown", "--limit", "1", "--verbose",
        ]
    )

    #expect(output.contains("| # | Time | Line | Destination | Tariff Zone | Platform | Via | Carrier | Delay | ID |"))
    #expect(output.contains("| 1 | **16:03** | 🚌 <span style=\"color: #0000FF\">Bus 980</span> | Rožnov p.Radh.,,aut.st. | 70 | 1 | Frýdek-Místek,Místek,Anenská | Transdev Slezsko a.s. | Currently no delay | `odis:1-4286-18.06.2026 16:03:00` |"))
}

@Test func departuresCommandRejectsUnknownOptions() async {
    let output = await englishCommandRunner(client: MockIDOSClient()).output(
        for: ["departures", "--station", "Ostrava,Hrabůvka,Benzina", "--unknown"]
    )

    #expect(output.contains("❌ Error: Unknown option: --unknown."))
}

@Test func departuresCommandReportsAmbiguousStationNames() async {
    let output = await englishCommandRunner(
        client: MockIDOSClient(stationResultsByPrefix: ["sí pe": ambiguousPIDStationSuggestions()])
    ).output(
        for: ["departures", "sí pe", "--timetable", "pid"]
    )

    #expect(output.contains("❌ Error: Ambiguous station name: sí pe (Prague + PID)."))
    #expect(output.contains("1. Sídliště Petrovice - stop (Praha)"))
    #expect(output.contains("2. Sídliště Petřiny - stop (Praha)"))
}

@Test func timetablesCommandPrintsCommonAliases() async {
    let output = await englishCommandRunner(client: MockIDOSClient()).output(for: ["timetables"])

    #expect(output.contains("🗂 Timetables:"))
    #expect(output.contains("vlakyautobusymhdvse"))
    #expect(output.contains("All timetables"))
    #expect(output.contains("pid"))
    #expect(output.contains("frydekmistek"))
    #expect(output.contains("odis"))
    #expect(output.contains("karlovyvary"))
    #expect(output.contains("zlin"))
}

@Test func timetablesCommandPrintsJSON() async throws {
    let output = await englishCommandRunner(client: MockIDOSClient()).output(for: ["timetables", "-o=json"])
    let json = try jsonDictionary(output)
    let timetables = json["timetables"] as? [[String: Any]]

    #expect(timetables?.contains { $0["slug"] as? String == "vlakyautobusymhdvse" } == true)
    #expect(timetables?.contains { $0["displayName"] as? String == "All timetables" } == true)
}

@Test func timetablesCommandRejectsUnknownOptions() async {
    let output = await englishCommandRunner(client: MockIDOSClient()).output(for: ["timetables", "--unknown"])

    #expect(output.contains("❌ Error: Unknown option: --unknown."))
}

@Test func aliasesCommandAddsListsAndRemovesStopAliases() async throws {
    let aliasFile = temporaryAliasFile()
    let runner = englishCommandRunner(client: MockIDOSClient(), aliasFile: aliasFile)

    let addOutput = await runner.output(for: [
        "aliases", "add", "home", "-s", "Frýdek,Na Veselé", "-T", "odis",
    ])
    #expect(addOutput.contains("🌰 Alias added: home → Frýdek,Na Veselé (ODIS)"))

    let listOutput = await runner.output(for: ["aliases", "list"])
    #expect(listOutput.contains("🌰 Stop aliases:"))
    #expect(listOutput.contains("home → Frýdek,Na Veselé (ODIS)"))

    let jsonOutput = await runner.output(for: ["aliases", "list", "-o", "json"])
    let json = try jsonDictionary(jsonOutput)
    let aliases = try #require(json["aliases"] as? [[String: Any]])
    #expect(aliases.first?["name"] as? String == "home")
    #expect(aliases.first?["station"] as? String == "Frýdek,Na Veselé")
    #expect((aliases.first?["timetable"] as? [String: Any])?["slug"] as? String == "odis")

    let removeOutput = await runner.output(for: ["aliases", "remove", "home"])
    #expect(removeOutput.contains("🌰 Alias removed: home → Frýdek,Na Veselé (ODIS)"))

    let emptyOutput = await runner.output(for: ["aliases", "list"])
    #expect(emptyOutput.contains("🌰 No stop aliases saved."))
}

@Test func aliasesCommandAddsStopAliasWithPositionalStation() async throws {
    let aliasFile = temporaryAliasFile()
    let runner = englishCommandRunner(client: MockIDOSClient(), aliasFile: aliasFile)

    let addOutput = await runner.output(for: [
        "aliases", "add", "s", "Sídliště Petrovice", "--timetable", "pid",
    ])

    #expect(addOutput.contains("🌰 Alias added: s → Sídliště Petrovice (Prague + PID)"))

    let listOutput = await runner.output(for: ["aliases", "list"])
    #expect(listOutput.contains("s → Sídliště Petrovice (Prague + PID)"))
}

@Test func aliasesCommandRejectsAmbiguousStationNames() async {
    let aliasFile = temporaryAliasFile()
    let runner = englishCommandRunner(
        client: MockIDOSClient(stationResultsByPrefix: ["sí pe": ambiguousPIDStationSuggestions()]),
        aliasFile: aliasFile
    )

    let output = await runner.output(for: [
        "aliases", "add", "s", "sí pe", "--timetable", "pid",
    ])

    #expect(output.contains("❌ Error: Ambiguous station name: sí pe (Prague + PID)."))
    #expect(output.contains("1. Sídliště Petrovice - stop (Praha)"))
    #expect(output.contains("2. Sídliště Petřiny - stop (Praha)"))
}

@Test func aliasesCommandPrintsDatabasePath() async {
    let aliasFile = temporaryAliasFile()
    let output = await englishCommandRunner(client: MockIDOSClient(), aliasFile: aliasFile).output(for: ["aliases", "path"])

    #expect(output.contains("🌰 Alias database:"))
    #expect(output.contains(aliasFile.fileURL.path))
}

@Test func connectionCommandUsesStopAliasesAndInferredTimetable() async throws {
    let aliasFile = temporaryAliasFile()
    var database = StopAliasDatabase()
    try database.upsert(StopAlias(name: "home", station: "Frýdek,Na Veselé", timetable: try IDOSTimetable.resolve("odis")))
    try database.upsert(StopAlias(name: "work", station: "Ostrava,Hrabůvka,Benzina", timetable: try IDOSTimetable.resolve("odis")))
    try aliasFile.save(database)

    let output = await englishCommandRunner(
        client: MockIDOSClient(
            expectedConnectionTimetable: "odis",
            expectedFrom: "Frýdek,Na Veselé",
            expectedTo: "Ostrava,Hrabůvka,Benzina"
        ),
        aliasFile: aliasFile
    ).output(for: ["connections", "--from", "home", "--to", "work", "--limit", "1"])

    #expect(output.contains("🧭 Connections Frýdek,Na Veselé → Ostrava,Hrabůvka,Benzina (ODIS)"))
}

@Test func connectionCommandUsesStopAliasesInRouteExpression() async throws {
    let aliasFile = temporaryAliasFile()
    var database = StopAliasDatabase()
    try database.upsert(StopAlias(name: "home", station: "Frýdek,Na Veselé", timetable: try IDOSTimetable.resolve("odis")))
    try database.upsert(StopAlias(name: "work", station: "Ostrava,Hrabůvka,Benzina", timetable: try IDOSTimetable.resolve("odis")))
    try aliasFile.save(database)

    let output = await englishCommandRunner(
        client: MockIDOSClient(
            expectedConnectionTimetable: "odis",
            expectedFrom: "Frýdek,Na Veselé",
            expectedTo: "Ostrava,Hrabůvka,Benzina"
        ),
        aliasFile: aliasFile
    ).output(for: ["connections", "home→work", "--limit", "1"])

    #expect(output.contains("🧭 Connections Frýdek,Na Veselé → Ostrava,Hrabůvka,Benzina (ODIS)"))
}

@Test func connectionCommandUsesStopAliasesAsTwoPositionalPlaces() async throws {
    let aliasFile = temporaryAliasFile()
    var database = StopAliasDatabase()
    try database.upsert(StopAlias(name: "home", station: "Frýdek,Na Veselé", timetable: try IDOSTimetable.resolve("odis")))
    try database.upsert(StopAlias(name: "work", station: "Ostrava,Hrabůvka,Benzina", timetable: try IDOSTimetable.resolve("odis")))
    try aliasFile.save(database)

    let output = await englishCommandRunner(
        client: MockIDOSClient(
            expectedConnectionTimetable: "odis",
            expectedFrom: "Frýdek,Na Veselé",
            expectedTo: "Ostrava,Hrabůvka,Benzina"
        ),
        aliasFile: aliasFile
    ).output(for: ["connections", "home", "work", "--limit", "1"])

    #expect(output.contains("🧭 Connections Frýdek,Na Veselé → Ostrava,Hrabůvka,Benzina (ODIS)"))
}

@Test func rootCommandUsesStopAliasesAsTwoPositionalPlaces() async throws {
    let aliasFile = temporaryAliasFile()
    var database = StopAliasDatabase()
    try database.upsert(StopAlias(name: "home", station: "Frýdek,Na Veselé", timetable: try IDOSTimetable.resolve("odis")))
    try database.upsert(StopAlias(name: "work", station: "Ostrava,Hrabůvka,Benzina", timetable: try IDOSTimetable.resolve("odis")))
    try aliasFile.save(database)

    let output = await englishCommandRunner(
        client: MockIDOSClient(
            expectedConnectionTimetable: "odis",
            expectedFrom: "Frýdek,Na Veselé",
            expectedTo: "Ostrava,Hrabůvka,Benzina"
        ),
        aliasFile: aliasFile
    ).output(for: ["home", "work", "--limit", "1"])

    #expect(output.contains("🧭 Connections Frýdek,Na Veselé → Ostrava,Hrabůvka,Benzina (ODIS)"))
}

@Test func departuresCommandUsesStopAliasAndInferredTimetable() async throws {
    let aliasFile = temporaryAliasFile()
    var database = StopAliasDatabase()
    try database.upsert(StopAlias(
        name: "benzina",
        station: "Ostrava,Hrabůvka,Benzina",
        timetable: try IDOSTimetable.resolve("odis")
    ))
    try aliasFile.save(database)

    let output = await englishCommandRunner(client: MockIDOSClient(), aliasFile: aliasFile).output(
        for: ["departures", "--station", "benzina", "--limit", "1"]
    )

    #expect(output.contains("🚏 Departures Ostrava,Hrabůvka,Benzina (ODIS)"))
}

@Test func rootCommandUsesStopAliasAsDepartureStation() async throws {
    let aliasFile = temporaryAliasFile()
    var database = StopAliasDatabase()
    try database.upsert(StopAlias(
        name: "work",
        station: "Ostrava,Hrabůvka,Benzina",
        timetable: try IDOSTimetable.resolve("odis")
    ))
    try aliasFile.save(database)

    let output = await englishCommandRunner(client: MockIDOSClient(), aliasFile: aliasFile).output(
        for: ["work", "--limit", "1"]
    )

    #expect(output.contains("🚏 Departures Ostrava,Hrabůvka,Benzina (ODIS)"))
}

@Test func connectionCommandRejectsConflictingStopAliasTimetables() async throws {
    let aliasFile = temporaryAliasFile()
    var database = StopAliasDatabase()
    try database.upsert(StopAlias(name: "home", station: "Frýdek,Na Veselé", timetable: try IDOSTimetable.resolve("odis")))
    try database.upsert(StopAlias(name: "main", station: "Praha hl.n.", timetable: try IDOSTimetable.resolve("vlaky")))
    try aliasFile.save(database)

    let output = await englishCommandRunner(client: MockIDOSClient(), aliasFile: aliasFile).output(
        for: ["connections", "--from", "home", "--to", "main"]
    )

    #expect(output.contains("❌ Error: Stop aliases use conflicting timetables: ODIS and Trains."))
}

@Test func timetableResolverAcceptsKnownAliasesAndCustomSlugs() throws {
    #expect(try IDOSTimetable.resolve("all timetables").slug == "vlakyautobusymhdvse")
    #expect(try IDOSTimetable.resolve("Prague + PID").slug == "pid")
    #expect(try IDOSTimetable.resolve("Frýdek-Místek").slug == "frydekmistek")
    #expect(try IDOSTimetable.resolve("Urban Public Transport Karlovy Vary").slug == "karlovyvary")
    #expect(try IDOSTimetable.resolve("Zlín a Otrokovice").slug == "zlin")
    #expect(try IDOSTimetable.resolve("karlovyvary").slug == "karlovyvary")
}

@Test func timetableResolverRejectsUnknownNonSlugNames() throws {
    do {
        _ = try IDOSTimetable.resolve("MHD Karlovy Vary")
        Issue.record("Expected invalid timetable error.")
    } catch IDOSError.invalidTimetable(let value) {
        #expect(value == "MHD Karlovy Vary")
    } catch {
        Issue.record("Unexpected error: \(error).")
    }
}

@Test func directConnectionRequestUsesIDOSOnlyDirectParameter() {
    let directRequest = IDOSConnectionRequest(from: "Praha", to: "Brno", onlyDirect: true)
    let normalRequest = IDOSConnectionRequest(from: "Praha", to: "Brno")

    #expect(directRequest.formItems.contains(URLQueryItem(name: "OnlyDirect", value: "true")))
    #expect(!normalRequest.formItems.contains { $0.name == "OnlyDirect" })
}

@Test func connectionRequestUsesIDOSArrivalTimeParameter() {
    let arrivalRequest = IDOSConnectionRequest(from: "Praha", to: "Brno", isArrival: true)
    let departureRequest = IDOSConnectionRequest(from: "Praha", to: "Brno")

    #expect(arrivalRequest.formItems.contains(URLQueryItem(name: "IsArr", value: "True")))
    #expect(departureRequest.formItems.contains(URLQueryItem(name: "IsArr", value: "False")))
}

@Test func connectionRequestDistinguishesSelectedStationFromFreeText() throws {
    let suggestion = IDOSSuggestion(
        selectedText: "Frýdek-Místek",
        text: "Frýdek-Místek",
        description: "station, district Frýdek-Místek, trains",
        value: "100003",
        value2: "10357"
    )
    let selection = try #require(IDOSPlaceSelection(suggestion: suggestion))
    let destination = IDOSPlaceSelection(text: "Ostrava", listID: "1", itemID: "10278")
    let selectedRequest = IDOSConnectionRequest(
        from: "Frýdek-Místek",
        to: "Ostrava",
        fromSelection: selection,
        toSelection: destination
    )
    let freeTextRequest = IDOSConnectionRequest(from: "Frýdek-Místek", to: "Ostrava")

    #expect(selection.text == "Frýdek-Místek")
    #expect(selectedRequest.formItems.contains(URLQueryItem(
        name: "FromHidden",
        value: "Frýdek-Místek%100003%10357"
    )))
    #expect(selectedRequest.formItems.contains(URLQueryItem(
        name: "ToHidden",
        value: "Ostrava%1%10278"
    )))
    #expect(freeTextRequest.formItems.contains(URLQueryItem(name: "FromHidden", value: "%0")))
    #expect(freeTextRequest.formItems.contains(URLQueryItem(name: "ToHidden", value: "%0")))
}

@Test func connectionRequestUsesIDOSMaximumTransfersParameter() {
    let limitedRequest = IDOSConnectionRequest(from: "Praha", to: "Brno", maxTransfers: 0)
    let normalRequest = IDOSConnectionRequest(from: "Praha", to: "Brno")

    #expect(limitedRequest.formItems.contains(URLQueryItem(name: "AdvancedForm.AdvancedFormIsOpen", value: "True")))
    #expect(limitedRequest.formItems.contains(URLQueryItem(name: "AdvancedForm.MaxChange", value: "0")))
    #expect(limitedRequest.formItems.contains(URLQueryItem(name: "AdvancedForm.MinTime", value: "-1")))
    #expect(limitedRequest.formItems.contains(URLQueryItem(name: "AdvancedForm.MaxTime", value: "240")))
    #expect(limitedRequest.formItems.contains(URLQueryItem(name: "trTypeId[154]", value: "154")))
    #expect(!normalRequest.formItems.contains { $0.name == "AdvancedForm.AdvancedFormIsOpen" })
    #expect(!normalRequest.formItems.contains { $0.name == "AdvancedForm.MaxChange" })
}

@Test func connectionRequestUsesIDOSMinimumTransferTimeParameter() {
    let limitedRequest = IDOSConnectionRequest(from: "Praha", to: "Brno", minimumTransferTime: 10)
    let normalRequest = IDOSConnectionRequest(from: "Praha", to: "Brno")

    #expect(limitedRequest.formItems.contains(URLQueryItem(name: "AdvancedForm.AdvancedFormIsOpen", value: "True")))
    #expect(limitedRequest.formItems.contains(URLQueryItem(name: "AdvancedForm.MaxChange", value: "4")))
    #expect(limitedRequest.formItems.contains(URLQueryItem(name: "AdvancedForm.MinTime", value: "10")))
    #expect(limitedRequest.formItems.contains(URLQueryItem(name: "AdvancedForm.MaxTime", value: "240")))
    #expect(limitedRequest.formItems.contains(URLQueryItem(name: "AdvancedForm.MaxArcLength", value: "60")))
    #expect(limitedRequest.formItems.contains(URLQueryItem(name: "AdvancedForm.MaxArcLengthCity", value: "10")))
    #expect(limitedRequest.formItems.contains(URLQueryItem(name: "trTypeId[301]", value: "301")))
    #expect(!normalRequest.formItems.contains { $0.name == "AdvancedForm.AdvancedFormIsOpen" })
    #expect(!normalRequest.formItems.contains { $0.name == "AdvancedForm.MinTime" })
}

@Test func connectionRequestUsesIDOSViaParameters() {
    let viaRequest = IDOSConnectionRequest(from: "Praha", to: "Brno", via: ["Pardubice", "Olomouc"])
    let normalRequest = IDOSConnectionRequest(from: "Praha", to: "Brno")

    #expect(viaRequest.formItems.contains(URLQueryItem(name: "AdvancedForm.AdvancedFormIsOpen", value: "True")))
    #expect(viaRequest.formItems.contains(URLQueryItem(name: "AdvancedForm.Via[0]", value: "Pardubice")))
    #expect(viaRequest.formItems.contains(URLQueryItem(name: "AdvancedForm.Via[1]", value: "Olomouc")))
    #expect(viaRequest.formItems.contains(URLQueryItem(name: "AdvancedForm.MaxChange", value: "4")))
    #expect(viaRequest.formItems.contains(URLQueryItem(name: "trTypeId[301]", value: "301")))
    #expect(!normalRequest.formItems.contains { $0.name.hasPrefix("AdvancedForm.Via[") })
}

@Test func connectionRequestCarriesResultLimit() {
    let request = IDOSConnectionRequest(from: "Praha", to: "Brno", resultLimit: 12)

    #expect(request.resultLimit == 12)
    #expect(!request.formItems.contains { $0.name == "resultLimit" })
}

@Test func departuresRequestUsesIDOSParameters() {
    let selection = IDOSPlaceSelection(
        text: "Ostrava,Hrabůvka,Benzina",
        listID: "200003",
        itemID: "85812"
    )
    let request = IDOSDeparturesRequest(
        station: "Ostrava,Hrabůvka,Benzina",
        stationSelection: selection,
        date: "18.6.2026",
        time: "16:00",
        isArrival: true
    )

    #expect(request.formItems.contains(URLQueryItem(name: "From", value: "Ostrava,Hrabůvka,Benzina")))
    #expect(request.formItems.contains(URLQueryItem(
        name: "FromHidden",
        value: "Ostrava,Hrabůvka,Benzina%200003%85812"
    )))
    #expect(request.formItems.contains(URLQueryItem(name: "Date", value: "18.6.2026")))
    #expect(request.formItems.contains(URLQueryItem(name: "Time", value: "16:00")))
    #expect(request.formItems.contains(URLQueryItem(name: "IsArr", value: "True")))
    #expect(request.formItems.contains(URLQueryItem(name: "submit", value: "true")))
}

@Test func stationTimetableRequestUsesIDOSParameters() {
    let request = IDOSStationTimetableRequest(
        timetable: IDOSTimetable(slug: "pid", displayName: "Prague + PID"),
        line: " Bus 154 ",
        from: " Strašnická ",
        to: " Sídliště Libuš ",
        date: "17.7.2026",
        wholeWeek: true
    )
    let values = Dictionary(uniqueKeysWithValues: request.queryItems.map { ($0.name, $0.value) })

    #expect(request.isComplete)
    #expect(values["date"] == "17.7.2026")
    #expect(values["l"] == "Bus 154")
    #expect(values["f"] == "Strašnická")
    #expect(values["t"] == "Sídliště Libuš")
    #expect(values["wholeweek"] == "true")
    #expect(values["submit"] == "true")
}

@Test func stationTimetableLineSuggestionKeepsDirectionTerminals() throws {
    let data = Data(
        #"[{"text":"Bus 154","description":"Strašnická-Sídliště Libuš","from":"Strašnická","to":"Sídliště Libuš"}]"#.utf8
    )
    let suggestions = try JSONDecoder().decode([IDOSSuggestion].self, from: data)

    #expect(suggestions.first?.text == "Bus 154")
    #expect(suggestions.first?.from == "Strašnická")
    #expect(suggestions.first?.to == "Sídliště Libuš")
}

@Test func jsonpParserDecodesCallbackPayload() throws {
    let data = Data(#"cb([{"text":"Praha"}]);"#.utf8)
    let payload = try IDOSJSONP.decodePayload(from: data)
    let suggestions = try JSONDecoder().decode([IDOSSuggestion].self, from: payload)

    #expect(suggestions == [IDOSSuggestion(
        selectedText: nil,
        text: "Praha",
        description: nil,
        region: nil,
        value: nil,
        value2: nil,
        iconId: nil,
        coorX: nil,
        coorY: nil
    )])
}

@Test func stationTimetableParserReadsRouteSchedulesAndNotes() throws {
    let html = """
    <div class="connection-head relative zjr-panel">
      <h2 class="reset departures__title">
        <img src="/images/vyluka64.png" class="exception" title="Lockout timetable" />
        <span>Line Bus 154</span>
      </h2>
    </div>
    <div class="zjr-stations">
      <table class="zjr-table">
        <tbody>
          <tr>
            <td class="zjr-table__time right valign-top bold">0</td>
            <td class="zjr-table__station_name">
              <span class="bold">Strašnick&#225;</span>
              <span title="platform">(1)</span>
              <span title="request stop">(x)</span>
            </td>
            <td class="tarif">0</td>
          </tr>
          <tr>
            <td class="zjr-table__time right valign-top bold">1</td>
            <td class="zjr-table__station_name">
              <a class="fromStation" href="javascript:;" title="search from the station">Na Hroudě</a>
              <span title="stanoviště">(2)</span>
              <span title="wheelchair accessible stop">#</span>
            </td>
            <td class="tarif">B</td>
          </tr>
        </tbody>
      </table>
    </div>
    <div class="zjr-table-container zjrBorderBottom ">
      <table class="zjr-table times">
        <thead>
          <tr><th class="zjr-table__date right"></th><th>17.7.2026 Friday</th></tr>
        </thead>
        <tbody>
          <tr><td class="zjr-table__date right bold valign-top">5</td><td>13 35A <span>55</span></td></tr>
          <tr><td class="zjr-table__date right bold valign-top">6</td><td></td></tr>
        </tbody>
      </table>
    </div>
    <ul class="remarks-list">
      <li class="remarks-list__item"><img title="Line description" /> valid from 1.7.2026</li>
      <li class="remarks-list__item"><img title="Information note" /> 1: stanoviště</li>
      <li class="remarks-list__item"><img title="Information note" /> A: runs only to stop Háje</li>
      <li class="remarks-list__item"><img title="Information note" /> : Board through the front door</li>
    </ul>
    """
    let request = IDOSStationTimetableRequest(
        timetable: IDOSTimetable(slug: "pid", displayName: "Prague + PID"),
        line: "Bus 154",
        from: "Strašnická",
        to: "Sídliště Libuš"
    )
    let timetable = try #require(IDOSStationTimetableParser.parse(
        html: html,
        request: request,
        shareURL: "https://idos.cz/en/pid/zjr/?l=154"
    ))

    #expect(timetable.lineName == "Bus 154")
    #expect(timetable.transportMode == .bus)
    #expect(timetable.fromStop == "Strašnická")
    #expect(timetable.toStop == "Sídliště Libuš")
    #expect(timetable.isLockout)
    #expect(timetable.shareURL == "https://idos.cz/en/pid/zjr/?l=154")
    #expect(timetable.stops.map(\.name) == ["Strašnická", "Na Hroudě"])
    #expect(timetable.stops.map(\.minuteOffset) == [0, 1])
    #expect(timetable.stops.map(\.tariffZone) == ["0", "B"])
    #expect(timetable.stops.map(\.platform) == ["1", "2"])
    #expect(timetable.selectedStop?.name == "Strašnická")
    #expect(timetable.stops[0].notes == ["request stop"])
    #expect(timetable.stops[1].notes == ["wheelchair accessible stop"])
    #expect(timetable.schedules == [
        IDOSStationTimetableSchedule(
            label: "17.7.2026 Friday",
            hours: [
                IDOSStationTimetableHour(hour: "5", departures: ["13", "35A", "55"]),
                IDOSStationTimetableHour(hour: "6", departures: []),
            ]
        )
    ])
    #expect(timetable.notes == [
        "valid from 1.7.2026",
        "A: runs only to stop Háje",
        "Board through the front door",
    ])
}

@Test func connectionParserReadsBasicResultHtml() {
    let html = """
    <div id="connectionBox-396829589" class="box connection" data-share-url="https://idos.cz/detail">
      <p class="reset total">Overall time <strong>3 h 40 min</strong></p>
      <h3 title="fast train" style="color: #FF0000;"><span>R9 (R 981 Vysocina)</span></h3>
      <p class="reset time  " title="">12:04</p><p class="station"><strong class="name ">Praha hl.n.</strong> <span><span title="tariff zone" class="color-lightgrey">P</span> <span title="platform" class="color-green">4</span></span></p>
      <p class="reset time  " title="">15:44</p><p class="station"><strong class="name ">Brno hl.n.</strong> <span><span title="tariff zone" class="color-lightgrey">100</span></span></p>
    </div>
    <script>
    var connResult = new Conn.ConnResult(params, null, {"connData":[{"connId":396829589,"trains":[{"ttIndex":0,"train":74552,"dateFromValue":"2026-06-18T00:00:00","timeFrom":"12:04"}]}]});
    </script>
    """

    let connections = IDOSConnectionParser.parse(
        html: html,
        timetable: IDOSTimetable(slug: "vlaky", displayName: "Trains")
    )

    #expect(connections.count == 1)
    #expect(connections.first?.id == "396829589")
    #expect(connections.first?.duration == "3 h 40 min")
    #expect(connections.first?.legs.first?.name == "R9 (R 981 Vysocina)")
    #expect(connections.first?.legs.first?.id == "vlaky:0-74552-18.06.2026 12:04:00")
    #expect(connections.first?.legs.first?.color == "#FF0000")
    #expect(connections.first?.legs.first?.transportMode == .train)
    #expect(connections.first?.legs.first?.fromTariffZone == "P")
    #expect(connections.first?.legs.first?.fromPlatform == "4")
    #expect(connections.first?.legs.first?.toTariffZone == "100")
    #expect(connections.first?.summaryLine(number: 1).contains("🚆") == true)
    #expect(connections.first?.summaryLine(number: 1).contains("tariff zone P · platform 4") == true)
    #expect(connections.first?.summaryLine(number: 1).contains("\u{001B}[38;2;255;0;0mR9") == true)
}

@Test func connectionParserBuildsCalendarModelFromResultHtml() throws {
    let html = """
    <div id="connectionBox-396829589" class="box connection" data-share-url="https://idos.cz/en/vlaky/spojeni/prehled/?p=abc">
      <p class="reset total">Overall time <strong>3 h 40 min</strong></p>
      <h3 title="fast train"><span>R9 (R 981 Vysocina)</span></h3>
      <p class="reset time" title="">12:04</p><p class="station"><strong class="name ">Praha hl.n.</strong></p>
      <p class="reset time" title="">15:44</p><p class="station"><strong class="name ">Brno hl.n.</strong></p>
    </div>
    <script>
    var connResult = new Conn.ConnResult(params, null, {"handle":123,"connData":[{"connId":396829589,"trains":[]}],"searchItem":{"sCombName":"Trains"}});
    </script>
    """

    let connection = try #require(IDOSConnectionParser.parse(html: html).first)
    let model = try #require(connection.calendarModel)
    let data = try #require(model.data(using: .utf8))
    let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    let jsConnData = try #require(json["jsConnData"] as? [String: Any])
    let connData = try #require(jsConnData["connData"] as? [[String: Any]])

    #expect(jsConnData["handle"] as? Int == 123)
    #expect(jsConnData["permanentUrl"] as? String == "https://idos.cz/en/vlaky/spojeni/prehled/?p=abc")
    #expect(connData.first?["connId"] as? Int == 396829589)
    #expect(connData.first?["priceOffer"] is NSNull)

    let pdfModel = try #require(connection.pdfModel)
    let pdfData = try #require(pdfModel.data(using: .utf8))
    let pdfJSON = try #require(JSONSerialization.jsonObject(with: pdfData) as? [String: Any])
    let pdfConnectionData = try #require(pdfJSON["jsConnData"] as? [String: Any])

    #expect(pdfJSON["context"] as? Int == 2)
    #expect(pdfConnectionData["permanentUrl"] == nil)
}

@Test func connectionParserReadsPagingContextFromResultHtml() throws {
    let html = """
    <script>
    var connResult = new Conn.ConnResult(params, null, {
      "handle":123,
      "arrivalThere":"0001-01-01T00:00:00",
      "connData":[],
      "searchItem":{
        "oConn":{
          "oUserInput":{
            "dtSearchDate":"2026-06-21T12:00:00+02:00",
            "oFrom":{"sName":"Praha","sAdvancedName":"Praha"},
            "oTo":{"sName":"Brno","sAdvancedName":"Brno"}
          }
        }
      }
    });
    </script>
    """

    let context = try #require(IDOSConnectionParser.pagingContext(html: html))

    #expect(context.handle == 123)
    #expect(context.searchDate == "2026-06-21T12:00:00+02:00")
    #expect(context.arrivalThere == "0001-01-01T00:00:00")
    #expect(context.from == "Praha")
    #expect(context.to == "Brno")
    #expect(context.allowPrevious == true)
    #expect(context.allowNext == true)
}

@Test func connectionParserKeepsHtmlOutsideLineNames() {
    let html = """
    <div id="connectionBox-1122672429" class="box connection">
      <p class="reset total">Overall time <strong>38 min</strong></p>
      <h3 title="bus (Nove Dvory,Frydecka skladka >> Mistek,Riviera)" style="color: #0000FF;"><span>Bus 302</span></h3>
      <p class="reset time" title="">11:53</p><p class="station"><strong class="name ">Frýdek,Na Veselé</strong></p>
      <p class="reset time" title="">12:06</p><p class="station"><strong class="name ">Místek,Anenská</strong></p>
      <span class="operator"><span>Transdev Slezsko a.s.</span></span>
      <span class="delay-bubble">Currently no delay</span>
      <h3 title="local bus (Frenstat p.Radh.,,u skol >> Ostrava,Mor.Ostrava,Namesti Republiky)" style="color: #0000FF;"><span>Bus 980</span></h3>
      <p class="reset time" title="">12:13</p><p class="station"><strong class="name ">Frýdek-Místek,Místek,Anenská</strong></p>
      <p class="reset time" title="">12:31</p><p class="station"><strong class="name ">Ostrava,Hrabůvka,Benzina</strong></p>
    </div>
    """

    let connection = IDOSConnectionParser.parse(html: html).first
    let summary = connection?.summaryLine(number: 1)

    #expect(connection?.legs.map(\.name) == ["Bus 302", "Bus 980"])
    #expect(connection?.legs.map(\.color) == ["#0000FF", "#0000FF"])
    #expect(connection?.legs.map(\.transportMode) == [.bus, .bus])
    #expect(connection?.legs.first?.carrier == "Transdev Slezsko a.s.")
    #expect(connection?.legs.first?.delay == "Currently no delay")
    #expect(summary?.contains("🚌") == true)
    #expect(summary?.contains("\u{001B}[38;2;0;0;255mBus 302") == true)
    #expect(summary?.contains("\n   🚌 \u{001B}[38;2;0;0;255mBus 980") == true)
    #expect(summary?.contains("; 🚌") == false)
    #expect(summary?.contains("style=") == false)
    #expect(summary?.contains("Transdev Slezsko a.s.") == true)
    #expect(summary?.contains("Currently no delay") == true)
}

@Test func connectionParserReadsMultipleHeadingsInsideSingleLineItem() {
    let html = """
    <div id="connectionBox-1" class="box connection">
      <p class="reset total">Overall time <strong>16 min</strong></p>
      <div class="line-item">
        <h3 title="bus (Řepiště,,U kříže >> Místek,Riviéra)" style="color: #0000FF;"><span>Bus 311</span></h3>
        <p class="reset time " title="" >10:10</p><p class="station"><strong class="name ">Frýdek,Sportovní hala Polárka</strong></p>
        <p class="reset time " title="" >10:13</p><p class="station"><strong class="name ">Místek,poliklinika</strong></p>
        <h3 title="bus (Místek,poliklinika >> Místek,poliklinika)" style="color: #0000FF;"><span>Bus 310</span></h3>
        <p class="reset time " title="" >10:15</p><p class="station"><strong class="name ">Místek,poliklinika</strong></p>
        <p class="reset time " title="" >10:26</p><p class="station"><strong class="name ">Frýdek,magistrát</strong></p>
      </div>
    </div>
    """

    let connection = IDOSConnectionParser.parse(html: html).first
    let summary = connection?.summaryLine(number: 1)

    #expect(connection?.legs.map(\.name) == ["Bus 311", "Bus 310"])
    #expect(connection?.legs.map(\.fromStation) == ["Frýdek,Sportovní hala Polárka", "Místek,poliklinika"])
    #expect(connection?.legs.map(\.toStation) == ["Místek,poliklinika", "Frýdek,magistrát"])
    #expect(summary?.contains("Bus 311") == true)
    #expect(summary?.contains("Bus 310") == true)
}

@Test func connectionParserInfersTrainFromRailLinePrefix() {
    let html = """
    <div id="connectionBox-401439022" class="box connection">
      <p class="reset total">Overall time <strong>2 h 39 min</strong></p>
      <h3 title="" style="color: #008000;"><span>RJ 1045 RegioJet</span></h3>
      <p class="reset time" title="">15:01</p><p class="station"><strong class="name ">Praha hl.n.</strong></p>
      <p class="reset time" title="">17:40</p><p class="station"><strong class="name ">Brno hl.n.</strong></p>
    </div>
    """

    let connection = IDOSConnectionParser.parse(html: html).first

    #expect(connection?.legs.first?.transportMode == .train)
    #expect(connection?.summaryLine(number: 1).contains("🚆") == true)
}

@Test func connectionParserKeepsMetropolitanTrainAsTrain() {
    let html = """
    <div id="connectionBox-1" class="box connection">
      <p class="reset total">Overall time <strong>2 h 37 min</strong></p>
      <h3 title="Eurocity (Praha hl.n. >> Budapest-Nyugati pu)"><span>Ex3 (EC 281 Metropolitan)</span></h3>
      <p class="reset time" title="">13:37</p><p class="station"><strong class="name ">Praha hl.n.</strong></p>
      <p class="reset time" title="">16:14</p><p class="station"><strong class="name ">Brno hl.n.</strong></p>
    </div>
    """

    let connection = IDOSConnectionParser.parse(html: html).first

    #expect(connection?.legs.first?.transportMode == .train)
    #expect(connection?.summaryLine(number: 1).contains("🚆") == true)
}

@Test func departureParserReadsDeparturesTableRows() throws {
    let html = """
    <h2 class="depTitlePage">Departures from Fr&#253;dek,Sportovn&#237; hala Pol&#225;rka</h2>
    <tr class="dep-row dep-row-first" data-ttindex="1" data-train="4286" data-datetime="18.06.2026 16:03:00" data-stationname="Rožnov p.Radh.,,aut.st.">
      <td class="departures-table__cell departures-table__cell--height-collapse" title="Arrival station"><h3>Rožnov p.Radh.,,aut.st.</h3></td>
      <td class="departures-table__cell departures-table__cell--height-collapse">
        <span class="wwwtt tt-icon-dep" style="color:#0000FF">&#247;</span>
        <span class="desc"><span class="code"><h3 style="color:#0000FF; display:inline">Bus 980</h3></span></span>
      </td>
      <td class="departures-table__cell"><h3>16:03</h3></td>
      <td class="departures-table__cell"><span title="tariff zone" class="color-lightgrey">70</span> <span title="platform" class="color-lightgrey">1</span></td>
    </tr>
    <tr class="dep-row dep-row-second" data-ttindex="1" data-train="4286" data-datetime="18.06.2026 16:03:00">
      <td class="departures-table__cell small"><span title="pass via" class="color-lightgrey">via Frýdek-Místek,Místek,Anenská</span></td>
      <td class="departures-table__cell small"><span title="dopravce" class="color-lightgrey">Transdev Slezsko a.s.</span></td>
      <td class="departures-table__cell cell-delay" colspan="2"><a href="javascript:;" class="delay-bubble">Currently no delay</a></td>
    </tr>
    """

    let departure = IDOSDepartureParser.parse(
        html: html,
        timetable: IDOSTimetable(slug: "odis", displayName: "ODIS")
    ).first

    #expect(departure?.id == "odis:1-4286-18.06.2026 16:03:00")
    #expect(departure?.stationName == "Frýdek,Sportovní hala Polárka")
    #expect(departure?.time == "16:03")
    #expect(departure?.lineName == "Bus 980")
    #expect(departure?.lineColor == "#0000FF")
    #expect(departure?.transportMode == .bus)
    #expect(departure?.destination == "Rožnov p.Radh.,,aut.st.")
    #expect(departure?.tariffZone == "70")
    #expect(departure?.platform == "1")
    #expect(departure?.via == "Frýdek-Místek,Místek,Anenská")
    #expect(departure?.carrier == "Transdev Slezsko a.s.")
    #expect(departure?.delay == "Currently no delay")
    #expect(departure?.summaryLine(number: 1).contains("🚌") == true)
    #expect(departure?.summaryLine(number: 1).contains("tariff zone 70 · platform 1") == true)
    let scheduledDate = try #require(departure.flatMap { IDOSDepartureParser.scheduledDate(for: $0) })
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Prague")!
    let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: scheduledDate)
    #expect(components.year == 2026)
    #expect(components.month == 6)
    #expect(components.day == 18)
    #expect(components.hour == 16)
    #expect(components.minute == 3)
}

@Test func serviceDetailParserReadsCompleteRouteAndInformation() throws {
    let html = """
    <div id="train-detail-151" data-share-url="https://idos.cz/service">
      <p class="line-top-date print-only">Departure from the initial station <strong>18.6.2026</strong></p>
      <h1 title="fast train" style="color: #008000;"><span>RJ 1051 RegioJet</span></h1>
      <ul class="reset line-itinerary">
        <li class="item inactive" title="Traffic restrictions">
          <span class="arrival"><span class="label out"></span></span>
          <span class="departure"><span class="label out"></span>11:45</span>
          <strong class="name">Praha-Zahradn&#237; Město</strong>
          <span class="fixed-codes"><span title="track">3</span></span>
          <span class="distance"><span class="label out"></span>0 km</span>
        </li>
        <li class="item" title="Click to refresh the current service position.">
          <span class="arrival"><span class="label out"></span>11:53</span>
          <span class="departure"><span class="label out"></span>12:04</span>
          <strong class="name">Praha hl.n.</strong>
          <span title="transfer to the undeground">#</span>
          <button title="Click to update the vehicle position."></button>
          <span class="fixed-codes"><span title="tariff zone">P</span></span>
          <span class="distance"><span class="label out"></span>7 km</span>
        </li>
        <li class="item" title="">
          <span class="arrival"><span class="label out"></span>15:44</span>
          <span class="departure"><span class="label out"></span></span>
          <strong class="name">Brno hl.n.</strong>
          <span class="fixed-codes"><span title="platform/track">3/1</span></span>
          <span class="distance"><span class="label out"></span>262 km</span>
        </li>
      </ul>
      <ul class="reset messages">
        <li class="message-red"><h3>Important information</h3><ul>
          <li>There is a planned traffic restriction.</li>
          <li class="remarks-list__item">České dráhy, a.s.</li>
        </ul></li>
      </ul>
      <ul class="reset line-share"></ul>
    </div>
    """

    let detail = try #require(IDOSServiceDetailParser.parse(
        html: html,
        id: "vlaky:0-74552-18.06.2026 12:04:00",
        timetable: IDOSTimetable(slug: "vlaky", displayName: "Trains")
    ))

    #expect(detail.name == "RJ 1051 RegioJet")
    #expect(detail.timetable.slug == "vlaky")
    #expect(detail.color == "#008000")
    #expect(detail.transportMode == .train)
    #expect(detail.date == "18.6.2026")
    #expect(detail.stops.count == 3)
    #expect(detail.stops[0].name == "Praha-Zahradní Město")
    #expect(detail.stops[0].track == "3")
    #expect(detail.stops[0].notes == ["Traffic restrictions"])
    #expect(detail.stops[1].arrivalTime == "11:53")
    #expect(detail.stops[1].departureTime == "12:04")
    #expect(detail.stops[1].tariffZone == "P")
    #expect(detail.stops[1].notes == ["transfer to the undeground"])
    #expect(detail.stops[2].platformTrack == "3/1")
    #expect(detail.stops[2].notes.isEmpty)
    #expect(detail.information == ["There is a planned traffic restriction.", "České dráhy, a.s."])
    #expect(detail.shareURL == "https://idos.cz/service")
}

@Test func serviceReferenceUsesEmbeddedTimetableAndCanonicalizesLegacyIDs() throws {
    let fallback = IDOSTimetable(slug: "odis", displayName: "ODIS")
    let selfContained = try IDOSServiceReference(
        id: "vlaky:0-74552-18.06.2026 12:04:00",
        fallbackTimetable: fallback
    )
    let legacy = try IDOSServiceReference(
        id: "1-4286-18.06.2026 16:03:00",
        fallbackTimetable: fallback
    )

    #expect(selfContained.timetable.slug == "vlaky")
    #expect(selfContained.id == "vlaky:0-74552-18.06.2026 12:04:00")
    #expect(legacy.timetable.slug == "odis")
    #expect(legacy.id == "odis:1-4286-18.06.2026 16:03:00")
}

@Test func idosLanguageBuildsLocalizedServiceDetailPaths() {
    let timetable = IDOSTimetable(slug: "vlaky", displayName: "Trains")

    #expect(IDOSLanguage.english.path(
        timetable: timetable,
        endpoint: "Ajax/TrainDetail"
    ) == "/en/vlaky/Ajax/TrainDetail")
    #expect(IDOSLanguage.czech.path(
        timetable: timetable,
        endpoint: "Ajax/TrainDetail"
    ) == "/vlaky/Ajax/TrainDetail")
}

@Test func timetableValidityParserReadsInclusiveIDOSSearchRange() throws {
    let html = """
    <script>
    var params = new Conn.ConnFormParams(new Date('12/14/2025'), new Date('12/12/2026'), '/vlaky/Ajax/');
    </script>
    """
    let validity = try #require(IDOSTimetableValidityParser.parse(html: html))
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Prague")!

    #expect(calendar.dateComponents([.year, .month, .day], from: validity.validFrom) == DateComponents(
        year: 2025,
        month: 12,
        day: 14
    ))
    #expect(calendar.dateComponents([.year, .month, .day], from: validity.validThrough) == DateComponents(
        year: 2026,
        month: 12,
        day: 12
    ))
}

@Test func serviceDetailParserReadsCzechStopMetadata() throws {
    let html = """
    <div id="train-detail-151">
      <p class="line-top-date print-only">Odjezd z výchozí stanice <strong>18.6.2026</strong></p>
      <h1 title="vlak"><span>RJ 1051 RegioJet</span></h1>
      <ul class="reset line-itinerary">
        <li class="item" title="Omezen&#237; provozu">
          <span class="arrival"><span class="label out"></span>11:53</span>
          <span class="departure"><span class="label out"></span>12:04</span>
          <strong class="name">Praha hl.n.</strong>
          <span title="přestup na Metro">#</span>
          <button title="Kliknutím se aktualizuje poloha spoje."></button>
          <span class="fixed-codes">
            <span title="tar. pásmo">1,2</span>
            <span title="stanoviště">2</span>
            <span title="kolej">4</span>
            <span title="nástupiště/kolej">2/4</span>
          </span>
          <span class="distance"><span class="label out"></span>7 km</span>
        </li>
      </ul>
      <ul class="reset messages"></ul>
      <ul class="reset line-share"></ul>
    </div>
    """

    let detail = try #require(IDOSServiceDetailParser.parse(
        html: html,
        id: "vlaky:0-74552-18.06.2026 12:04:00",
        timetable: IDOSTimetable(slug: "vlaky", displayName: "Trains")
    ))
    let stop = try #require(detail.stops.first)

    #expect(stop.tariffZone == "1,2")
    #expect(stop.platform == "2")
    #expect(stop.track == "4")
    #expect(stop.platformTrack == "2/4")
    #expect(stop.notes == ["Omezení provozu", "přestup na Metro"])
}

/// Keeps legacy output assertions deterministic regardless of the developer machine's locale.
private func englishCommandRunner(
    client: IDOSClienting = IDOSClient(),
    aliasFile: StopAliasFile = StopAliasFile(),
    calendarImporter: CalendarImporting = SystemCalendarImporter()
) -> CommandRunner {
    CommandRunner(
        client: client,
        aliasFile: aliasFile,
        calendarImporter: calendarImporter,
        preferredLanguageIdentifiers: ["en"],
        environment: [:]
    )
}

private struct MockIDOSClient: IDOSClienting {
    var expectedConnectionTimetable = "vlaky"
    var expectedFrom = "Praha"
    var expectedTo = "Brno"
    var expectedIsArrival = false
    var expectedOnlyDirect = false
    var expectedVia: [String] = []
    var expectedMaxTransfers: Int? = nil
    var expectedMinimumTransferTime: Int? = nil
    var expectedConnectionResultLimit: Int? = nil
    var validatesConnectionResultLimit = false
    var failConnectionsWithNetworkError = false
    var connectionResults: [IDOSConnection]? = nil
    var expectedDepartureTimetable = "odis"
    var expectedStation = "Ostrava,Hrabůvka,Benzina"
    var resolvedStationName: String? = nil
    var expectedDepartureIsArrival = false
    var departureResults: [IDOSDeparture]? = nil
    var suggestionResultsByPrefix: [String: [IDOSSuggestion]] = [:]
    var stationResultsByPrefix: [String: [IDOSSuggestion]] = [:]
    var expectedServiceLanguage: IDOSLanguage = .english
    var expectedStationTimetableLanguage: IDOSLanguage = .english

    func suggest(prefix: String, limit: Int, timetable: IDOSTimetable) async throws -> [IDOSSuggestion] {
        if let suggestions = suggestionResultsByPrefix[prefix] {
            return Array(suggestions.prefix(limit))
        }

        return prefix == "Praha" ? Array(stationSuggestions.prefix(limit)) : []
    }

    func searchStations(prefix: String, limit: Int, timetable: IDOSTimetable) async throws -> [IDOSSuggestion] {
        if let stations = stationResultsByPrefix[prefix] {
            return Array(stations.prefix(limit))
        }

        return prefix == "Praha" ? Array(stationSuggestions.prefix(limit)) : []
    }

    private var stationSuggestions: [IDOSSuggestion] {
        return [
            IDOSSuggestion(
                selectedText: "Praha hl.n.",
                text: "Praha hl.n.",
                description: "station, district Praha, trains, urban public transport",
                region: "district Praha",
                value: "100003",
                value2: "25948",
                iconId: 14,
                coorX: 50.082979,
                coorY: 14.43595
            )
        ]
    }

    func findConnections(request: IDOSConnectionRequest) async throws -> [IDOSConnection] {
        #expect(request.timetable.slug == expectedConnectionTimetable)
        #expect(request.from == expectedFrom)
        #expect(request.to == expectedTo)
        #expect(request.isArrival == expectedIsArrival)
        #expect(request.onlyDirect == expectedOnlyDirect)
        #expect(request.via == expectedVia)
        #expect(request.maxTransfers == expectedMaxTransfers)
        #expect(request.minimumTransferTime == expectedMinimumTransferTime)
        if validatesConnectionResultLimit {
            #expect(request.resultLimit == expectedConnectionResultLimit)
        }

        if failConnectionsWithNetworkError {
            throw IDOSError.networkUnavailable("")
        }

        if let connectionResults {
            return connectionResults
        }

        return [
            IDOSConnection(
                id: "396829589",
                departureTime: "12:04",
                departureStation: "Praha hl.n.",
                arrivalTime: "15:44",
                arrivalStation: "Brno hl.n.",
                duration: "3 hod 40 min",
                legs: [
                    IDOSConnectionLeg(
                        name: "R9 (R 981 Vysočina)",
                        id: "vlaky:0-74552-18.06.2026 12:04:00",
                        color: "#008000",
                        transportMode: .train,
                        departureTime: "12:04",
                        fromStation: "Praha hl.n.",
                        fromTariffZone: "P",
                        fromPlatform: "4",
                        arrivalTime: "15:44",
                        toStation: "Brno hl.n.",
                        toTariffZone: "100",
                        carrier: "České dráhy, a.s.",
                        delay: "Currently no delay"
                    )
                ],
                shareURL: "https://idos.cz/detail",
                calendarModel: #"{"jsConnData":{"connData":[],"searchItem":{},"permanentUrl":"https://idos.cz/detail"}}"#
            )
        ]
    }

    func connectionCalendar(for connection: IDOSConnection, timetable: IDOSTimetable) async throws -> String {
        #expect(timetable.slug == expectedConnectionTimetable)
        #expect(connection.id == "396829589")

        return """
        BEGIN:VCALENDAR
        VERSION:2.0
        SUMMARY:Connection Praha hl.n. >> Brno hl.n.
        END:VCALENDAR
        """
    }

    func findDepartures(request: IDOSDeparturesRequest) async throws -> [IDOSDeparture] {
        #expect(request.timetable.slug == expectedDepartureTimetable)
        #expect(request.station == expectedStation)
        #expect(request.isArrival == expectedDepartureIsArrival)

        if let departureResults {
            return departureResults
        }

        return [
            IDOSDeparture(
                id: "odis:1-4286-18.06.2026 16:03:00",
                stationName: resolvedStationName,
                time: "16:03",
                lineName: "Bus 980",
                lineColor: "#0000FF",
                transportMode: .bus,
                destination: "Rožnov p.Radh.,,aut.st.",
                tariffZone: "70",
                platform: "1",
                via: "Frýdek-Místek,Místek,Anenská",
                carrier: "Transdev Slezsko a.s.",
                delay: "Currently no delay"
            )
        ]
    }

    func findStationTimetable(
        request: IDOSStationTimetableRequest,
        language: IDOSLanguage
    ) async throws -> IDOSStationTimetable {
        #expect(request.timetable.slug == "pid")
        #expect(request.line == "Bus 154")
        #expect(request.from == "Strašnická")
        #expect(request.to == "Sídliště Libuš")
        #expect(request.date == "17.7.2026")
        #expect(request.wholeWeek)
        #expect(language == expectedStationTimetableLanguage)

        return IDOSStationTimetable(
            timetable: request.timetable,
            lineName: request.line,
            transportMode: .bus,
            fromStop: request.from,
            toStop: request.to,
            stops: [
                IDOSStationTimetableStop(
                    name: request.from,
                    minuteOffset: 0,
                    tariffZone: "0",
                    platform: "1",
                    isSelected: true,
                    notes: ["request stop"]
                ),
                IDOSStationTimetableStop(
                    name: "Na Hroudě",
                    minuteOffset: 1,
                    tariffZone: "B",
                    platform: "2",
                    notes: ["wheelchair accessible stop"]
                ),
            ],
            schedules: [
                IDOSStationTimetableSchedule(
                    label: "17.7.2026 Friday",
                    hours: [
                        IDOSStationTimetableHour(hour: "5", departures: ["13", "35A", "55"]),
                        IDOSStationTimetableHour(hour: "6", departures: []),
                    ]
                ),
            ],
            notes: ["valid from 1.7.2026", "A: runs only to stop Háje"],
            isLockout: true,
            shareURL: "https://idos.cz/en/pid/zjr/?l=154"
        )
    }

    func serviceDetail(id: String, timetable: IDOSTimetable) async throws -> IDOSServiceDetail {
        #expect(id == "vlaky:0-74552-18.06.2026 12:04:00")
        #expect(timetable.slug == IDOSTimetable.defaultTimetable.slug)
        return mockServiceDetail(id: id)
    }

    func serviceDetail(
        id: String,
        timetable: IDOSTimetable,
        language: IDOSLanguage
    ) async throws -> IDOSServiceDetail {
        #expect(id == "vlaky:0-74552-18.06.2026 12:04:00")
        #expect(timetable.slug == IDOSTimetable.defaultTimetable.slug)
        #expect(language == expectedServiceLanguage)
        return mockServiceDetail(id: id, language: language)
    }
}

private func mockServiceDetail(
    id: String,
    language: IDOSLanguage = .english
) -> IDOSServiceDetail {
    let isCzech = language == .czech
    return IDOSServiceDetail(
        id: id,
        timetable: IDOSTimetable(slug: "vlaky", displayName: "Trains"),
        name: "RJ 1051 RegioJet",
        color: "#008000",
        transportMode: .train,
        date: "18.6.2026",
        stops: [
            IDOSServiceStop(
                name: "Praha-Zahradní Město",
                departureTime: "11:45",
                track: "3",
                distance: "0 km",
                notes: [isCzech ? "Omezení provozu" : "Traffic restrictions"]
            ),
            IDOSServiceStop(
                name: "Praha hl.n.",
                arrivalTime: "11:53",
                departureTime: "12:04",
                tariffZone: "P",
                distance: "7 km",
                notes: [isCzech ? "přestup na Metro" : "transfer to the undeground"]
            ),
            IDOSServiceStop(
                name: "Brno hl.n.",
                arrivalTime: "15:44",
                platformTrack: "3/1",
                distance: "262 km",
                notes: isCzech
                    ? [
                        "bezbariérově přístupná stanice",
                        "zastávka s možností přestupu na železniční dopravu",
                    ]
                    : ["wheelchair accessible station", "rail station"]
            ),
        ],
        information: [
            isCzech ? "Plánované omezení provozu" : "Planned traffic restriction",
            "České dráhy, a.s.",
        ],
        shareURL: "https://idos.cz/service"
    )
}

private struct MockCalendarImporter: CalendarImporting {
    var path: String

    func add(calendar: String, fileName: String) throws -> URL {
        #expect(calendar.contains("BEGIN:VCALENDAR"))
        #expect(fileName == "kastan-396829589.ics")

        return URL(fileURLWithPath: path)
    }
}

private func connectionResult(id: String, duration: String, legNames: [String]) -> IDOSConnection {
    IDOSConnection(
        id: id,
        departureTime: "12:00",
        departureStation: "Praha hl.n.",
        arrivalTime: "16:00",
        arrivalStation: "Brno hl.n.",
        duration: duration,
        legs: legNames.enumerated().map { index, name in
            IDOSConnectionLeg(
                name: name,
                transportMode: .train,
                departureTime: "1\(index + 2):00",
                fromStation: index == 0 ? "Praha hl.n." : "Pardubice hl.n.",
                arrivalTime: "1\(index + 3):00",
                toStation: index == legNames.count - 1 ? "Brno hl.n." : "Pardubice hl.n."
            )
        }
    )
}

private func ambiguousPIDStationSuggestions() -> [IDOSSuggestion] {
    [
        IDOSSuggestion(
            selectedText: "Sídliště Petrovice",
            text: "Sídliště Petrovice",
            description: "stop (Praha)",
            value: "301003",
            value2: "6362",
            iconId: 4
        ),
        IDOSSuggestion(
            selectedText: "Sídliště Petřiny",
            text: "Sídliště Petřiny",
            description: "stop (Praha)",
            value: "301003",
            value2: "6363",
            iconId: 15
        ),
    ]
}

private func jsonDictionary(_ output: String) throws -> [String: Any] {
    let object = try JSONSerialization.jsonObject(with: Data(output.utf8))
    return try #require(object as? [String: Any])
}

private func temporaryAliasFile() -> StopAliasFile {
    StopAliasFile(fileURL: FileManager.default.temporaryDirectory
        .appendingPathComponent("kastan-tests-\(UUID().uuidString)")
        .appendingPathComponent("aliases.json"))
}
