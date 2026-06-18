import Foundation
@testable import JizdniNerady
import Testing
@testable import jizdni_nerady

@Test func defaultOutputNamesApplication() async {
    let output = await CommandRunner(client: MockIDOSClient()).output(for: [])

    #expect(output.contains("🚆 jizdni-nerady"))
    #expect(output.contains("Search occasional IDOS connections"))
}

@Test func helpOutputShowsUsage() async {
    let output = await CommandRunner(client: MockIDOSClient()).output(for: ["--help"])

    #expect(output.contains("🚆 Usage:"))
    #expect(output.contains("connections"))
    #expect(output.contains("timetables"))
    #expect(output.contains("--timetable"))
    #expect(output.contains("--arrival"))
    #expect(output.contains("--departure"))
    #expect(output.contains("--direct"))
    #expect(output.contains("--max-transfers"))
    #expect(output.contains("--format"))
    #expect(output.contains("Direct connections only"))
    #expect(!output.contains("--jr"))
    #expect(output.contains("--version"))
}

@Test func versionOutputShowsCurrentVersion() async {
    let output = await CommandRunner(client: MockIDOSClient()).output(for: ["--version"])

    #expect(output == "0.1.0")
}

@Test func suggestCommandPrintsSuggestions() async {
    let output = await CommandRunner(client: MockIDOSClient()).output(for: ["suggest", "Praha", "--timetable", "pid"])

    #expect(output.contains("🔎 Suggested places (Prague + PID)"))
    #expect(output.contains("Praha hl.n."))
    #expect(output.contains("station"))
}

@Test func suggestCommandPrintsJSON() async throws {
    let output = await CommandRunner(client: MockIDOSClient()).output(
        for: ["suggest", "Praha", "--timetable", "pid", "--format", "json"]
    )
    let json = try jsonDictionary(output)

    #expect((json["query"] as? String) == "Praha")
    #expect((json["timetable"] as? [String: Any])?["displayName"] as? String == "Prague + PID")
    #expect((json["suggestions"] as? [[String: Any]])?.first?["text"] as? String == "Praha hl.n.")
}

@Test func connectionCommandPrintsConnections() async {
    let output = await CommandRunner(client: MockIDOSClient()).output(
        for: ["connections", "--from", "Praha", "--to", "Brno", "--timetable", "vlaky", "--limit", "1"]
    )

    #expect(output.contains("🧭 Connections Praha → Brno (Trains)"))
    #expect(output.contains("12:04 Praha hl.n. → 15:44 Brno hl.n."))
    #expect(output.contains("R9"))
}

@Test func connectionCommandPrintsMarkdown() async {
    let output = await CommandRunner(client: MockIDOSClient()).output(
        for: ["connections", "--from", "Praha", "--to", "Brno", "--timetable", "vlaky", "--format", "markdown", "--limit", "1"]
    )

    #expect(output.contains("## 🧭 Connections"))
    #expect(output.contains("| Line | From | Departure | To | Arrival |"))
    #expect(output.contains(#"<span style="color: #008000">R9 (R 981 Vysočina)</span>"#))
}

@Test func connectionCommandPrintsJSONWithMaximumTransfers() async throws {
    let output = await CommandRunner(client: MockIDOSClient(expectedIsArrival: true, expectedMaxTransfers: 0)).output(
        for: [
            "connections", "--from", "Praha", "--to", "Brno", "--timetable", "vlaky",
            "--arrival", "--max-transfers", "0", "--format", "json", "--limit", "1",
        ]
    )
    let json = try jsonDictionary(output)
    let request = json["request"] as? [String: Any]

    #expect(request?["isArrival"] as? Bool == true)
    #expect(request?["maxTransfers"] as? Int == 0)
    #expect((json["connections"] as? [[String: Any]])?.first?["id"] as? String == "396829589")
}

@Test func connectionCommandRequestsDirectConnections() async {
    let output = await CommandRunner(client: MockIDOSClient(expectedOnlyDirect: true)).output(
        for: ["connections", "--from", "Praha", "--to", "Brno", "--timetable", "vlaky", "--direct", "--limit", "1"]
    )

    #expect(output.contains("🧭 Connections Praha → Brno (Trains)"))
    #expect(output.contains("R9"))
}

@Test func connectionCommandRequestsArrivalTime() async {
    let output = await CommandRunner(client: MockIDOSClient(expectedIsArrival: true)).output(
        for: ["connections", "--from", "Praha", "--to", "Brno", "--timetable", "vlaky", "--time", "15:00", "--arrival", "--limit", "1"]
    )

    #expect(output.contains("🧭 Connections Praha → Brno (Trains)"))
    #expect(output.contains("R9"))
}

@Test func connectionCommandRequestsDepartureTime() async {
    let output = await CommandRunner(client: MockIDOSClient(expectedIsArrival: false)).output(
        for: ["connections", "--from", "Praha", "--to", "Brno", "--timetable", "vlaky", "--time", "15:00", "--departure", "--limit", "1"]
    )

    #expect(output.contains("🧭 Connections Praha → Brno (Trains)"))
    #expect(output.contains("R9"))
}

@Test func connectionCommandRejectsConflictingTimeModes() async {
    let output = await CommandRunner(client: MockIDOSClient()).output(
        for: ["connections", "--from", "Praha", "--to", "Brno", "--timetable", "vlaky", "--time", "15:00", "--arrival", "--departure"]
    )

    #expect(output.contains("❌ Error: Conflicting options: --arrival and --departure. Use only one."))
}

@Test func connectionCommandLimitsMaximumTransfers() async {
    let output = await CommandRunner(client: MockIDOSClient(expectedMaxTransfers: 0)).output(
        for: ["connections", "--from", "Praha", "--to", "Brno", "--timetable", "vlaky", "--max-transfers", "0", "--limit", "1"]
    )

    #expect(output.contains("🧭 Connections Praha → Brno (Trains)"))
    #expect(output.contains("R9"))
}

@Test func connectionCommandRejectsNegativeMaximumTransfers() async {
    let output = await CommandRunner(client: MockIDOSClient()).output(
        for: ["connections", "--from", "Praha", "--to", "Brno", "--timetable", "vlaky", "--max-transfers", "-1"]
    )

    #expect(output.contains("❌ Error: Invalid --max-transfers: -1. Use a non-negative integer."))
}

@Test func timetablesCommandPrintsCommonAliases() async {
    let output = await CommandRunner(client: MockIDOSClient()).output(for: ["timetables"])

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
    let output = await CommandRunner(client: MockIDOSClient()).output(for: ["timetables", "--format=json"])
    let json = try jsonDictionary(output)
    let timetables = json["timetables"] as? [[String: Any]]

    #expect(timetables?.contains { $0["slug"] as? String == "vlakyautobusymhdvse" } == true)
    #expect(timetables?.contains { $0["displayName"] as? String == "All timetables" } == true)
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

@Test func connectionRequestUsesIDOSMaximumTransfersParameter() {
    let limitedRequest = IDOSConnectionRequest(from: "Praha", to: "Brno", maxTransfers: 0)
    let normalRequest = IDOSConnectionRequest(from: "Praha", to: "Brno")

    #expect(limitedRequest.formItems.contains(URLQueryItem(name: "AdvancedForm.MaxChange", value: "0")))
    #expect(!normalRequest.formItems.contains { $0.name == "AdvancedForm.MaxChange" })
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

@Test func connectionParserReadsBasicResultHtml() {
    let html = """
    <div id="connectionBox-396829589" class="box connection" data-share-url="https://idos.cz/detail">
      <p class="reset total">Overall time <strong>3 h 40 min</strong></p>
      <h3 title="fast train" style="color: #FF0000;"><span>R9 (R 981 Vysocina)</span></h3>
      <p class="reset time  " title="">12:04</p><p class="station"><strong class="name ">Praha hl.n.</strong></p>
      <p class="reset time  " title="">15:44</p><p class="station"><strong class="name ">Brno hl.n.</strong></p>
    </div>
    """

    let connections = IDOSConnectionParser.parse(html: html)

    #expect(connections.count == 1)
    #expect(connections.first?.id == "396829589")
    #expect(connections.first?.duration == "3 h 40 min")
    #expect(connections.first?.legs.first?.name == "R9 (R 981 Vysocina)")
    #expect(connections.first?.legs.first?.color == "#FF0000")
    #expect(connections.first?.summaryLine(number: 1).contains("\u{001B}[38;2;255;0;0mR9") == true)
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

    #expect(connection?.legs.map(\.name) == ["Bus 302", "Bus 980"])
    #expect(connection?.legs.map(\.color) == ["#0000FF", "#0000FF"])
    #expect(connection?.summaryLine(number: 1).contains("\u{001B}[38;2;0;0;255mBus 302") == true)
    #expect(connection?.summaryLine(number: 1).contains("style=") == false)
    #expect(connection?.summaryLine(number: 1).contains("Transdev") == false)
}

private struct MockIDOSClient: IDOSClienting {
    var expectedIsArrival = false
    var expectedOnlyDirect = false
    var expectedMaxTransfers: Int? = nil

    func suggest(prefix: String, limit: Int, timetable: IDOSTimetable) async throws -> [IDOSSuggestion] {
        #expect(timetable.slug == "pid")

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
        #expect(request.timetable.slug == "vlaky")
        #expect(request.isArrival == expectedIsArrival)
        #expect(request.onlyDirect == expectedOnlyDirect)
        #expect(request.maxTransfers == expectedMaxTransfers)

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
                        color: "#008000",
                        departureTime: "12:04",
                        fromStation: "Praha hl.n.",
                        arrivalTime: "15:44",
                        toStation: "Brno hl.n."
                    )
                ],
                shareURL: "https://idos.cz/detail"
            )
        ]
    }
}

private func jsonDictionary(_ output: String) throws -> [String: Any] {
    let object = try JSONSerialization.jsonObject(with: Data(output.utf8))
    return try #require(object as? [String: Any])
}
