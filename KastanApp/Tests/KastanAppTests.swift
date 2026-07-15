import Foundation
@testable import KastanApp
import Kastan
import XCTest

@MainActor
final class KastanAppTests: XCTestCase {
    func testAppInformationLinksUseLocalizedOfficialIDOSPages() {
        let czech = AppInformationLinks(languageCode: "cs")
        let english = AppInformationLinks(languageCode: "en")

        XCTAssertEqual(czech.idosWebsite.absoluteString, "https://idos.cz/")
        XCTAssertEqual(czech.idosTerms.absoluteString, "https://idos.cz/smluvni-podminky/")
        XCTAssertEqual(english.idosWebsite.absoluteString, "https://idos.cz/en/")
        XCTAssertEqual(english.idosTerms.absoluteString, "https://idos.cz/en/smluvni-podminky/")
        XCTAssertEqual(english.projectWebsite.absoluteString, "https://github.com/Glutexo/kastan")
    }

    func testDetailLayoutStacksControlsAtCompactWidths() {
        let layout = DetailLayout(availableWidth: 510)

        XCTAssertEqual(layout.containerWidth, 510)
        XCTAssertEqual(layout.horizontalPadding, 16)
        XCTAssertTrue(layout.usesStackedEndpoints)
        XCTAssertTrue(layout.usesStackedOptions)
        XCTAssertTrue(layout.usesStackedSearchControls)
    }

    func testDetailLayoutUsesHorizontalControlsWhenEnoughSpaceIsAvailable() {
        let layout = DetailLayout(availableWidth: 900)

        XCTAssertEqual(layout.containerWidth, 900)
        XCTAssertEqual(layout.horizontalPadding, 24)
        XCTAssertFalse(layout.usesStackedEndpoints)
        XCTAssertFalse(layout.usesStackedOptions)
        XCTAssertFalse(layout.usesStackedSearchControls)
    }

    func testDetailLayoutUsesTheEntireDetailWidth() {
        let layout = DetailLayout(availableWidth: 1400)

        XCTAssertEqual(layout.containerWidth, 1400)
        XCTAssertEqual(layout.contentWidth, 1352)
    }

    func testTimetableCatalogIsSplitIntoGeneralIntegratedAndCityGroups() {
        XCTAssertEqual(
            AppTimetableGroup.general.timetables.map(\.slug),
            ["vlakyautobusymhdvse", "vlakyautobusymhd", "vlaky", "autobusy", "vlakyautobusy"]
        )
        XCTAssertEqual(
            AppTimetableGroup.integratedSystems.timetables.map(\.slug),
            ["pid", "idsjmk", "odis", "idol"]
        )
        XCTAssertTrue(
            AppTimetableGroup.cityTransport.timetables.allSatisfy {
                $0.displayName.hasPrefix("Urban Public Transport ")
            }
        )
        XCTAssertEqual(
            AppTimetableGroup.cityTransport.timetables.first { $0.slug == "karlovyvary" }?.appDisplayName,
            "Karlovy Vary"
        )

        let groupedSlugs = Set(AppTimetableGroup.allCases.flatMap { $0.timetables.map(\.slug) })
        XCTAssertEqual(groupedSlugs, Set(IDOSTimetable.known.map(\.slug)))
    }

    func testSuggestionPresentationLocalizesMetadataAndRemovesRepeatedRegion() {
        let station = PlaceSuggestionPresentation(
            suggestion: IDOSSuggestion(
                text: "Frýdek-Místek",
                description: "station, district Frýdek-Místek, trains",
                region: "district Frýdek-Místek"
            )
        )
        let busStop = PlaceSuggestionPresentation(
            suggestion: IDOSSuggestion(
                text: "Frýdek-Místek,Frýdek,magistrát",
                description: "stop, district Frýdek-Místek, buses, PT",
                region: "district Frýdek-Místek"
            )
        )

        XCTAssertEqual(station.emoji, "🚆")
        XCTAssertEqual(station.detail?.components(separatedBy: " · ").count, 3)
        XCTAssertEqual(
            station.detail?.components(separatedBy: " · ").filter { $0.contains("Frýdek-Místek") }.count,
            1
        )
        XCTAssertEqual(busStop.emoji, "🚌")
        XCTAssertEqual(busStop.detail?.components(separatedBy: " · ").count, 4)
    }

    func testConnectionSearchBuildsCompleteIDOSRequest() async {
        let client = MockIDOSClient()
        let model = ConnectionsViewModel(client: client, calendarImporter: RecordingCalendarImporter())
        model.from = " Praha "
        model.to = " Brno "
        model.viaPlaces = [
            ViaPlaceEntry(name: " Pardubice "),
            ViaPlaceEntry(name: ""),
            ViaPlaceEntry(name: "Olomouc")
        ]
        model.timetable = IDOSTimetable(slug: "vlaky", displayName: "Trains")
        model.isArrival = true
        model.maximumTransfers = 2

        await model.search()

        let request = await client.lastConnectionRequest
        XCTAssertEqual(request?.from, "Praha")
        XCTAssertEqual(request?.to, "Brno")
        XCTAssertEqual(request?.via, ["Pardubice", "Olomouc"])
        XCTAssertEqual(request?.timetable.slug, "vlaky")
        XCTAssertEqual(request?.isArrival, true)
        XCTAssertEqual(request?.maxTransfers, 2)
        XCTAssertEqual(request?.resultLimit, 10)
        XCTAssertEqual(model.connections.first?.id, "connection-1")
        XCTAssertNil(model.errorMessage)
    }

    func testConnectionViaRowsCanBeAddedAndRemovedWithoutDroppingTheLastField() {
        let model = ConnectionsViewModel(client: MockIDOSClient(), calendarImporter: RecordingCalendarImporter())
        let firstID = model.viaPlaces[0].id

        model.addViaPlace(after: firstID)
        XCTAssertEqual(model.viaPlaces.count, 2)

        let secondID = model.viaPlaces[1].id
        model.viaPlaces[1].name = "Olomouc"
        model.removeViaPlace(id: firstID)
        XCTAssertEqual(model.viaPlaces.map(\.name), ["Olomouc"])

        model.removeViaPlace(id: secondID)
        XCTAssertEqual(model.viaPlaces.map(\.name), [""])
    }

    func testConnectionSearchRejectsMissingEndpointWithoutCallingIDOS() async {
        let client = MockIDOSClient()
        let model = ConnectionsViewModel(client: client, calendarImporter: RecordingCalendarImporter())
        model.from = "Praha"

        await model.search()

        XCTAssertNotNil(model.errorMessage)
        let request = await client.lastConnectionRequest
        XCTAssertNil(request)
    }

    func testDepartureSearchBuildsStationBoardRequestAndLimitsResults() async {
        let client = MockIDOSClient()
        let model = DeparturesViewModel(client: client)
        model.station = " Ostrava-Svinov "
        model.isArrival = true

        await model.search()

        let request = await client.lastDeparturesRequest
        XCTAssertEqual(request?.station, "Ostrava-Svinov")
        XCTAssertEqual(request?.isArrival, true)
        XCTAssertEqual(model.departures.count, 20)
    }

    func testCalendarImportUsesCalendarReturnedByIDOS() async {
        let client = MockIDOSClient()
        let importer = RecordingCalendarImporter()
        let model = ConnectionsViewModel(client: client, calendarImporter: importer)
        let connection = IDOSConnection(
            id: "connection-1",
            departureTime: "12:00",
            departureStation: "Praha",
            arrivalTime: "14:30",
            arrivalStation: "Brno",
            duration: "2 h 30 min",
            legs: []
        )

        await model.addToCalendar(connection)

        XCTAssertEqual(importer.calendarText, "BEGIN:VCALENDAR\nEND:VCALENDAR")
        XCTAssertNil(model.errorMessage)
    }

    func testPlaceSuggestionsAreDebouncedAndUseSelectedTimetable() async throws {
        let client = MockIDOSClient()
        let model = PlaceSuggestionsModel(client: client, scope: .places)
        let timetable = try IDOSTimetable.resolve("pid")

        model.update(query: "Pr", timetable: timetable)
        model.update(query: "Praha", timetable: timetable)
        try await Task.sleep(nanoseconds: 350_000_000)

        XCTAssertEqual(model.suggestions.map(\.text), ["Praha hl.n."])
        let query = await client.lastSuggestionQuery
        XCTAssertEqual(query?.prefix, "Praha")
        XCTAssertEqual(query?.timetableSlug, "pid")
    }

    func testLocalizedErrorPresentationPreservesNetworkDetail() {
        let message = AppErrorPresentation.message(
            for: IDOSError.networkUnavailable("The connection was reset.")
        )

        XCTAssertTrue(message.contains("The connection was reset."))
        XCTAssertTrue(AppLocalization.string("Connection %lld", 3).contains("3"))
    }
}

@MainActor
private final class RecordingCalendarImporter: CalendarImporting {
    private(set) var calendarText: String?

    func open(calendarText: String) throws {
        self.calendarText = calendarText
    }
}

private actor MockIDOSClient: IDOSClienting {
    var lastConnectionRequest: IDOSConnectionRequest?
    var lastDeparturesRequest: IDOSDeparturesRequest?
    var lastSuggestionQuery: SuggestionQuery?

    func suggest(prefix: String, limit: Int, timetable: IDOSTimetable) async throws -> [IDOSSuggestion] {
        lastSuggestionQuery = SuggestionQuery(prefix: prefix, timetableSlug: timetable.slug)
        return [IDOSSuggestion(text: "Praha hl.n.")]
    }

    func searchStations(prefix: String, limit: Int, timetable: IDOSTimetable) async throws -> [IDOSSuggestion] {
        [IDOSSuggestion(text: "Ostrava-Svinov")]
    }

    func findConnections(request: IDOSConnectionRequest) async throws -> [IDOSConnection] {
        lastConnectionRequest = request
        return [
            IDOSConnection(
                id: "connection-1",
                departureTime: "12:00",
                departureStation: "Praha hl.n.",
                arrivalTime: "14:30",
                arrivalStation: "Brno hl.n.",
                duration: "2 h 30 min",
                legs: []
            ),
        ]
    }

    func connectionCalendar(for connection: IDOSConnection, timetable: IDOSTimetable) async throws -> String {
        "BEGIN:VCALENDAR\nEND:VCALENDAR"
    }

    func findDepartures(request: IDOSDeparturesRequest) async throws -> [IDOSDeparture] {
        lastDeparturesRequest = request
        return (1...25).map { index in
            IDOSDeparture(
                id: "departure-\(index)",
                time: "16:\(String(format: "%02d", index))",
                lineName: "S2",
                destination: "Opava"
            )
        }
    }

    func serviceDetail(id: String, timetable: IDOSTimetable) async throws -> IDOSServiceDetail {
        IDOSServiceDetail(
            id: id,
            timetable: timetable,
            name: "S2",
            stops: [IDOSServiceStop(name: "Ostrava-Svinov")]
        )
    }
}

private struct SuggestionQuery: Sendable {
    let prefix: String
    let timetableSlug: String
}
