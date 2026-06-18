import Foundation
import Testing
@testable import jizdni_nerady

@Test func defaultOutputNamesApplication() async {
    let output = await CommandRunner(client: MockIDOSClient()).output(for: [])

    #expect(output.contains("Jízdní neřády"))
}

@Test func helpOutputShowsUsage() async {
    let output = await CommandRunner(client: MockIDOSClient()).output(for: ["--help"])

    #expect(output.contains("Použití:"))
    #expect(output.contains("connections"))
    #expect(output.contains("timetables"))
    #expect(output.contains("--timetable"))
    #expect(!output.contains("--jr"))
    #expect(output.contains("--version"))
}

@Test func versionOutputShowsCurrentVersion() async {
    let output = await CommandRunner(client: MockIDOSClient()).output(for: ["--version"])

    #expect(output == "0.1.0")
}

@Test func suggestCommandPrintsSuggestions() async {
    let output = await CommandRunner(client: MockIDOSClient()).output(for: ["suggest", "Praha", "--timetable", "pid"])

    #expect(output.contains("Praha + PID"))
    #expect(output.contains("Praha hl.n."))
    #expect(output.contains("stanice"))
}

@Test func connectionCommandPrintsConnections() async {
    let output = await CommandRunner(client: MockIDOSClient()).output(
        for: ["connections", "--from", "Praha", "--to", "Brno", "--timetable", "vlaky", "--limit", "1"]
    )

    #expect(output.contains("Spojení Praha -> Brno (Vlaky)"))
    #expect(output.contains("12:04 Praha hl.n. -> 15:44 Brno hl.n."))
    #expect(output.contains("R9"))
}

@Test func timetablesCommandPrintsCommonAliases() async {
    let output = await CommandRunner(client: MockIDOSClient()).output(for: ["timetables"])

    #expect(output.contains("vlakyautobusymhdvse"))
    #expect(output.contains("pid"))
    #expect(output.contains("frydekmistek"))
    #expect(output.contains("odis"))
    #expect(output.contains("karlovyvary"))
    #expect(output.contains("zlin"))
}

@Test func timetableResolverAcceptsKnownAliasesAndCustomSlugs() throws {
    #expect(try IDOSTimetable.resolve("vše").slug == "vlakyautobusymhdvse")
    #expect(try IDOSTimetable.resolve("Praha + PID").slug == "pid")
    #expect(try IDOSTimetable.resolve("Frýdek-Místek").slug == "frydekmistek")
    #expect(try IDOSTimetable.resolve("MHD Karlovy Vary").slug == "karlovyvary")
    #expect(try IDOSTimetable.resolve("Zlín a Otrokovice").slug == "zlin")
    #expect(try IDOSTimetable.resolve("karlovyvary").slug == "karlovyvary")
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
      <p class="reset total">Celkový čas <strong>3 hod 40 min</strong></p>
      <h3 title="rychlík"><span>R9 (R 981 Vysočina)</span></h3>
      <p class="reset time  " title="">12:04</p><p class="station"><strong class="name ">Praha hl.n.</strong></p>
      <p class="reset time  " title="">15:44</p><p class="station"><strong class="name ">Brno hl.n.</strong></p>
    </div>
    """

    let connections = IDOSConnectionParser.parse(html: html)

    #expect(connections.count == 1)
    #expect(connections.first?.id == "396829589")
    #expect(connections.first?.duration == "3 hod 40 min")
    #expect(connections.first?.legs.first?.name == "R9 (R 981 Vysočina)")
}

@Test func connectionParserKeepsHtmlOutsideLineNames() {
    let html = """
    <div id="connectionBox-1122672429" class="box connection">
      <p class="reset total">Celkový čas <strong>38 min</strong></p>
      <h3 title="autobus (Nové Dvory,Frýdecká skládka >> Místek,Riviéra)" style="color: #0000FF;"><span>Bus 302</span></h3>
      <p class="reset time" title="">11:53</p><p class="station"><strong class="name ">Frýdek,Na Veselé</strong></p>
      <p class="reset time" title="">12:06</p><p class="station"><strong class="name ">Místek,Anenská</strong></p>
      <span class="operator"><span>Transdev Slezsko a.s.</span></span>
      <span class="delay-bubble">Aktuálně bez zpoždění</span>
      <h3 title="místní autobus (Frenštát p.Radh.,,u škol >> Ostrava,Mor.Ostrava,Náměstí Republiky)" style="color: #0000FF;"><span>Bus 980</span></h3>
      <p class="reset time" title="">12:13</p><p class="station"><strong class="name ">Frýdek-Místek,Místek,Anenská</strong></p>
      <p class="reset time" title="">12:31</p><p class="station"><strong class="name ">Ostrava,Hrabůvka,Benzina</strong></p>
    </div>
    """

    let connection = IDOSConnectionParser.parse(html: html).first

    #expect(connection?.legs.map(\.name) == ["Bus 302", "Bus 980"])
    #expect(connection?.summaryLine(number: 1).contains("style=") == false)
    #expect(connection?.summaryLine(number: 1).contains("Transdev") == false)
}

private struct MockIDOSClient: IDOSClienting {
    func suggest(prefix: String, limit: Int, timetable: IDOSTimetable) async throws -> [IDOSSuggestion] {
        #expect(timetable.slug == "pid")

        return [
            IDOSSuggestion(
                selectedText: "Praha hl.n.",
                text: "Praha hl.n.",
                description: "stanice, okres Praha, vlaky, MHD",
                region: "okres Praha",
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
