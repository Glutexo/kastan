import AppKit
import Foundation
@testable import KastanApp
import Kastan
import SwiftUI
import XCTest

private final class FlippedScrollDocumentView: NSView {
    override var isFlipped: Bool { true }
}

private final class ElasticTestClipView: NSClipView {
    override func constrainBoundsRect(_ proposedBounds: NSRect) -> NSRect {
        proposedBounds
    }
}

@MainActor
final class KastanAppTests: XCTestCase {
    func testCloseWindowTargetsEveryTabInTheSelectedWindow() {
        XCTAssertEqual(
            AppWindowActions.closeTargets(selected: "selected", tabGroup: ["first", "selected"]),
            ["first", "selected"]
        )
        XCTAssertEqual(
            AppWindowActions.closeTargets(selected: "selected", tabGroup: nil),
            ["selected"]
        )
    }

    func testAppInformationCommandIsRemovedOnlyFromTheWindowMenu() {
        let title = AppLocalization.string("About Kaštan")

        XCTAssertTrue(
            ApplicationMainMenu.isRedundantAppInformationItem(title: title, isWindowsMenu: true)
        )
        XCTAssertFalse(
            ApplicationMainMenu.isRedundantAppInformationItem(title: title, isWindowsMenu: false)
        )
        XCTAssertFalse(
            ApplicationMainMenu.isRedundantAppInformationItem(title: "Other window", isWindowsMenu: true)
        )
    }

    func testAppInformationLinksUseLocalizedOfficialIDOSPages() {
        let czech = AppInformationLinks(languageCode: "cs")
        let english = AppInformationLinks(languageCode: "en")

        XCTAssertEqual(czech.idosWebsite.absoluteString, "https://idos.cz/")
        XCTAssertEqual(czech.idosTerms.absoluteString, "https://idos.cz/smluvni-podminky/")
        XCTAssertEqual(english.idosWebsite.absoluteString, "https://idos.cz/en/")
        XCTAssertEqual(english.idosTerms.absoluteString, "https://idos.cz/en/smluvni-podminky/")
        XCTAssertEqual(english.projectWebsite.absoluteString, "https://github.com/Glutexo/kastan")
        XCTAssertEqual(
            czech.destinations.map(\.id),
            [.idosWebsite, .idosTerms, .projectWebsite]
        )
        XCTAssertEqual(
            czech.destinations.map(\.url),
            [czech.idosWebsite, czech.idosTerms, czech.projectWebsite]
        )
    }

    func testPermanentIDOSLinksFollowTheAppLanguage() {
        let englishURL = "https://idos.cz/en/vlaky/spojeni/prehled/?p=abc%20123#connection"
        let czechURL = "https://idos.cz/vlaky/spojeni/prehled/?p=abc%20123#connection"

        XCTAssertEqual(
            AppLanguagePreference.localizedIDOSURL(from: englishURL, language: .czech)?.absoluteString,
            czechURL
        )
        XCTAssertEqual(
            AppLanguagePreference.localizedIDOSURL(from: czechURL, language: .english)?.absoluteString,
            englishURL
        )
        XCTAssertEqual(
            AppLanguagePreference.localizedIDOSURL(from: englishURL, language: .english)?.absoluteString,
            englishURL
        )
    }

    func testEnglishCountryNamesFollowTheAppLanguage() {
        XCTAssertEqual(
            AppLanguagePreference.localizedCountryName(fromEnglishName: "Romania", language: .czech),
            "Rumunsko"
        )
        XCTAssertEqual(
            AppLanguagePreference.localizedCountryName(fromEnglishName: "Romania", language: .english),
            "Romania"
        )
        XCTAssertNil(
            AppLanguagePreference.localizedCountryName(fromEnglishName: "okres Vsetín", language: .czech)
        )
    }

    func testServiceDetailToolbarOffersFourSeparateLocalizedActions() throws {
        let czech = try XCTUnwrap(localizationBundle(languageCode: "cs"))
        let english = try XCTUnwrap(localizationBundle(languageCode: "en"))

        XCTAssertEqual(
            ServiceDetailToolbarAction.allCases,
            [.addToCalendar, .saveAsPDF, .shareLink, .openInIDOS]
        )
        let keys = ["Add to Calendar", "Save as PDF", "Share Link", "Open in IDOS"]
        XCTAssertEqual(
            keys.map { czech.localizedString(forKey: $0, value: nil, table: nil) },
            ["Přidat do Kalendáře", "Uložit jako PDF", "Sdílet odkaz", "Otevřít v IDOSu"]
        )
        XCTAssertEqual(
            keys.map { english.localizedString(forKey: $0, value: nil, table: nil) },
            keys
        )
    }

    func testDetailLayoutStacksControlsAtCompactWidths() {
        let layout = DetailLayout(availableWidth: 510)

        XCTAssertEqual(layout.containerWidth, 510)
        XCTAssertEqual(layout.horizontalPadding, 16)
        XCTAssertTrue(layout.usesStackedSearchControls)
    }

    func testMainWindowSupportsCompactSearchWorkspaceWidth() {
        let layout = DetailLayout(availableWidth: KastanApp.minimumMainWindowWidth)

        XCTAssertEqual(KastanApp.minimumMainWindowWidth, 522)
        XCTAssertEqual(layout.contentWidth, 490)
        XCTAssertTrue(layout.usesStackedSearchControls)
        XCTAssertEqual(JourneySearchControls.searchButtonContentWidth(usesStackedLayout: true), 120)
        XCTAssertEqual(JourneySearchControls.searchButtonContentWidth(usesStackedLayout: false), 140)
    }

    func testDetailLayoutUsesHorizontalControlsWhenEnoughSpaceIsAvailable() {
        let layout = DetailLayout(availableWidth: 900)

        XCTAssertEqual(layout.containerWidth, 900)
        XCTAssertEqual(layout.horizontalPadding, 24)
        XCTAssertFalse(layout.usesStackedSearchControls)
    }

    func testDetailLayoutUsesTheEntireDetailWidth() {
        let layout = DetailLayout(availableWidth: 1400)

        XCTAssertEqual(layout.containerWidth, 1400)
        XCTAssertEqual(layout.contentWidth, 1352)
    }

    func testResultPullTriggerLoadsEachScrollableEdgeOncePerGesture() {
        var trigger = SearchResultPullTrigger()
        let documentFrame = CGRect(x: 0, y: 0, width: 700, height: 1_000)
        let topPull = SearchResultScrollMetrics(
            visibleBounds: CGRect(x: 0, y: -48, width: 700, height: 500),
            documentFrame: documentFrame,
            documentIsFlipped: true
        )
        let resting = SearchResultScrollMetrics(
            visibleBounds: CGRect(x: 0, y: 0, width: 700, height: 500),
            documentFrame: documentFrame,
            documentIsFlipped: true
        )
        let bottomPull = SearchResultScrollMetrics(
            visibleBounds: CGRect(x: 0, y: 548, width: 700, height: 500),
            documentFrame: documentFrame,
            documentIsFlipped: true
        )

        XCTAssertEqual(
            trigger.edgeToLoad(
                metrics: topPull,
                canLoadEarlier: true,
                canLoadLater: true,
                isLoadingEarlier: false,
                isLoadingLater: false
            ),
            .earlier
        )
        XCTAssertNil(
            trigger.edgeToLoad(
                metrics: topPull,
                canLoadEarlier: true,
                canLoadLater: true,
                isLoadingEarlier: false,
                isLoadingLater: false
            )
        )
        XCTAssertNil(
            trigger.edgeToLoad(
                metrics: resting,
                canLoadEarlier: true,
                canLoadLater: true,
                isLoadingEarlier: false,
                isLoadingLater: false
            )
        )
        XCTAssertEqual(
            trigger.edgeToLoad(
                metrics: bottomPull,
                canLoadEarlier: true,
                canLoadLater: true,
                isLoadingEarlier: false,
                isLoadingLater: false
            ),
            .later
        )
        XCTAssertNil(
            trigger.edgeToLoad(
                metrics: SearchResultScrollMetrics(
                    visibleBounds: CGRect(x: 0, y: -48, width: 700, height: 500),
                    documentFrame: CGRect(x: 0, y: 0, width: 700, height: 300),
                    documentIsFlipped: true
                ),
                canLoadEarlier: true,
                canLoadLater: true,
                isLoadingEarlier: false,
                isLoadingLater: false
            )
        )
    }

    func testNativePullMonitorObservesElasticScrollBoundsAtBothEdges() {
        let scrollView = NSScrollView(frame: CGRect(x: 0, y: 0, width: 700, height: 500))
        scrollView.contentView = ElasticTestClipView(
            frame: CGRect(x: 0, y: 0, width: 700, height: 500)
        )
        scrollView.documentView = FlippedScrollDocumentView(
            frame: CGRect(x: 0, y: 0, width: 700, height: 1_000)
        )
        var loadedEdges: [SearchResultPagingEdge] = []
        let monitor = SearchResultPullMonitor(
            canLoadEarlier: true,
            canLoadLater: true,
            isLoadingEarlier: false,
            isLoadingLater: false,
            load: { loadedEdges.append($0) }
        )
        let coordinator = monitor.makeCoordinator()
        coordinator.attach(to: scrollView)

        scrollView.contentView.bounds.origin.y = -SearchResultPullTrigger.activationDistance
        NotificationCenter.default.post(
            name: NSView.boundsDidChangeNotification,
            object: scrollView.contentView
        )
        scrollView.contentView.bounds.origin.y = 0
        coordinator.evaluateCurrentPosition()
        scrollView.contentView.bounds.origin.y = 548
        NotificationCenter.default.post(
            name: NSView.boundsDidChangeNotification,
            object: scrollView.contentView
        )

        XCTAssertEqual(loadedEdges, [.earlier, .later])
        XCTAssertEqual(scrollView.verticalScrollElasticity, .allowed)
        coordinator.detach()
    }

    func testResultPagingProgressLabelsAreLocalized() throws {
        let czech = try XCTUnwrap(localizationBundle(languageCode: "cs"))
        let english = try XCTUnwrap(localizationBundle(languageCode: "en"))
        let keys = ["Loading earlier results…", "Loading later results…"]

        XCTAssertEqual(
            keys.map { czech.localizedString(forKey: $0, value: nil, table: nil) },
            ["Načítání dřívějších výsledků…", "Načítání následujících výsledků…"]
        )
        XCTAssertEqual(
            keys.map { english.localizedString(forKey: $0, value: nil, table: nil) },
            keys
        )
    }

    func testCollapsedSearchSummariesPreserveSubmittedQueryContext() {
        let connection = SearchSummaryPresentation.connection(
            from: " Praha ",
            to: " Brno ",
            timetable: "Vlaky",
            date: "16.7.2026",
            time: "14:30",
            mode: "Odjezd",
            via: ["", "Jihlava"],
            transferLimit: "Jen přímé"
        )
        let departures = SearchSummaryPresentation.station(
            name: " Ostrava-Svinov ",
            timetable: "ODIS",
            date: "16.7.2026",
            time: "15:00",
            mode: "Odjezdy"
        )

        XCTAssertEqual(connection.title, "Praha → Brno")
        XCTAssertEqual(
            connection.details,
            ["Vlaky", "16.7.2026 14:30", "Odjezd", AppLocalization.string("via %@", "Jihlava"), "Jen přímé"]
        )
        XCTAssertEqual(departures.title, "Ostrava-Svinov")
        XCTAssertEqual(departures.detailText, "ODIS · 16.7.2026 15:00 · Odjezdy")
    }

    func testToolbarOffersExactlyTheThreeIDOSSearchModes() {
        XCTAssertEqual(AppSection.allCases, [.connections, .departures, .stationTimetables])
        XCTAssertEqual(AppWindow.favoriteTimetables, "favorite-timetables")
    }

    func testNativeToolbarKeepsTheModePickerAheadOfOverflowActions() throws {
        var selection = AppSection.connections
        let coordinator = MainWindowToolbarInstaller.Coordinator(
            selection: Binding(
                get: { selection },
                set: { selection = $0 }
            ),
            openFavoriteTimetables: {},
            openAppInformation: {}
        )

        XCTAssertEqual(coordinator.toolbar.identifier, .kastanMainWindow)
        XCTAssertEqual(coordinator.toolbar.centeredItemIdentifiers, [.searchMode])
        XCTAssertEqual(
            coordinator.toolbarDefaultItemIdentifiers(coordinator.toolbar),
            [.flexibleSpace, .searchMode, .flexibleSpace, .favoriteTimetables, .appInformation]
        )

        let modeItem = try XCTUnwrap(
            coordinator.toolbar(
                coordinator.toolbar,
                itemForItemIdentifier: .searchMode,
                willBeInsertedIntoToolbar: true
            )
        )
        let favoriteItem = try XCTUnwrap(
            coordinator.toolbar(
                coordinator.toolbar,
                itemForItemIdentifier: .favoriteTimetables,
                willBeInsertedIntoToolbar: false
            )
        )

        XCTAssertEqual(modeItem.visibilityPriority, .user)
        XCTAssertEqual(favoriteItem.visibilityPriority, .standard)
        XCTAssertNotNil(favoriteItem.menuFormRepresentation)

        let modeControl = try XCTUnwrap(modeItem.view as? NSSegmentedControl)
        XCTAssertEqual(modeControl.segmentCount, AppSection.allCases.count)
        XCTAssertEqual(modeControl.frame.width, modeControl.fittingSize.width, accuracy: 0.5)

        modeControl.selectedSegment = 1
        modeControl.sendAction(modeControl.action, to: modeControl.target)
        XCTAssertEqual(selection, .departures)
    }

    func testAppInformationToolbarTitleNamesItsContentWithoutAnActionVerb() throws {
        let czech = try XCTUnwrap(localizationBundle(languageCode: "cs"))
        let english = try XCTUnwrap(localizationBundle(languageCode: "en"))
        let key = "App and data source information"

        XCTAssertEqual(
            czech.localizedString(forKey: key, value: nil, table: nil),
            "Informace o aplikaci a zdroji dat"
        )
        XCTAssertEqual(english.localizedString(forKey: key, value: nil, table: nil), key)
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
        XCTAssertEqual(
            AppTimetableGroup.stationTimetables.prefix(4).map(\.slug),
            ["pid", "idsjmk", "odis", "idol"]
        )
        XCTAssertTrue(
            AppTimetableGroup.stationTimetables.dropFirst(4).allSatisfy {
                $0.displayName.hasPrefix("Urban Public Transport ")
            }
        )
    }

    func testFavoriteTimetablesPersistKnownUniqueSlugsInOrder() {
        var favorites = TimetableFavorites(slugs: ["vlaky", "unknown", "vlaky", "odis"])

        XCTAssertEqual(favorites.slugs, ["vlaky", "odis"])
        XCTAssertEqual(favorites.timetables.map(\.slug), ["vlaky", "odis"])

        favorites.toggle(IDOSTimetable(slug: "vlaky", displayName: "Trains"))
        favorites.toggle(IDOSTimetable(slug: "pid", displayName: "Prague + PID"))

        XCTAssertEqual(favorites.slugs, ["odis", "pid"])
        XCTAssertEqual(TimetableFavorites(serialized: favorites.serialized), favorites)
    }

    func testFavoriteTimetablesRemainInTheirCatalogSections() {
        let options = AppTimetablePickerOptions(favoriteSlugs: ["vlaky", "odis"])

        XCTAssertTrue(options.catalogTimetables(in: .general).contains { $0.slug == "vlaky" })
        XCTAssertTrue(options.catalogTimetables(in: .integratedSystems).contains { $0.slug == "odis" })
    }

    func testFavoriteManagerKeepsEveryTimetableInItsCatalogGroup() {
        let favorites = TimetableFavorites(slugs: ["vlaky", "odis"])
        let groupedTimetables = AppTimetableGroup.allCases.flatMap(\.timetables)

        XCTAssertEqual(groupedTimetables.count, IDOSTimetable.known.count)
        XCTAssertEqual(Set(groupedTimetables.map(\.slug)), Set(IDOSTimetable.known.map(\.slug)))
        XCTAssertTrue(favorites.contains(groupedTimetables.first { $0.slug == "vlaky" }!))
        XCTAssertTrue(favorites.contains(groupedTimetables.first { $0.slug == "odis" }!))
        XCTAssertFalse(favorites.contains(groupedTimetables.first { $0.slug == "pid" }!))
    }

    func testSuggestionPresentationLocalizesMetadataAndRemovesRepeatedRegion() {
        let municipality = PlaceSuggestionPresentation(
            suggestion: IDOSSuggestion(
                text: "Frýdek-Místek",
                description: "municipality, district Frýdek-Místek, trains, buses, urban public transport"
            )
        )
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
        let romanianMunicipality = PlaceSuggestionPresentation(
            suggestion: IDOSSuggestion(text: "Roznov", description: "Romania"),
            countryLanguage: .czech
        )

        XCTAssertEqual(municipality.emoji, "🏘️")
        XCTAssertEqual(station.emoji, "🚆")
        XCTAssertEqual(station.detail?.components(separatedBy: " · ").count, 3)
        XCTAssertEqual(
            station.detail?.components(separatedBy: " · ").filter { $0.contains("Frýdek-Místek") }.count,
            1
        )
        XCTAssertEqual(busStop.emoji, "🚌")
        XCTAssertEqual(busStop.detail?.components(separatedBy: " · ").count, 4)
        XCTAssertEqual(romanianMunicipality.detail, "Rumunsko")
    }

    func testSuggestionButtonAcceptsClicksAcrossTheFullRow() {
        var didSelect = false
        let row = PlaceSuggestionButton(
            suggestion: IDOSSuggestion(
                text: "Rožnov pod Radhoštěm",
                description: "municipality, district Vsetín"
            ),
            action: { didSelect = true }
        )
        .frame(width: 320)
        let hostingView = NSHostingView(rootView: row)
        hostingView.frame = NSRect(x: 0, y: 0, width: 320, height: 56)

        let window = NSWindow(
            contentRect: hostingView.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.contentView = hostingView
        window.makeKeyAndOrderFront(nil)
        hostingView.layoutSubtreeIfNeeded()
        defer { window.orderOut(nil) }

        let location = NSPoint(x: 300, y: hostingView.bounds.midY)
        for eventType in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            let event = NSEvent.mouseEvent(
                with: eventType,
                location: location,
                modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber,
                context: nil,
                eventNumber: 0,
                clickCount: 1,
                pressure: eventType == .leftMouseDown ? 1 : 0
            )
            if let event {
                window.sendEvent(event)
            }
        }

        XCTAssertTrue(didSelect)
    }

    func testDelayPresentationLocalizesKnownStateAndPreservesCarrierDetail() {
        XCTAssertEqual(
            ResultMetadata.delay(" Currently no delay "),
            AppLocalization.string("Currently no delay")
        )
        XCTAssertEqual(ResultMetadata.delay("Delay 12 min"), "Delay 12 min")
        XCTAssertNil(ResultMetadata.delay("  "))
    }

    func testServiceRouteHighlightMatchesSearchStopsAndDirection() {
        let stops = [
            IDOSServiceStop(name: "Frýdek,Dobrovského"),
            IDOSServiceStop(name: "Frýdek,T.G.Masaryka"),
            IDOSServiceStop(name: "Frýdek,magistrát"),
            IDOSServiceStop(name: "Místek,Anenská")
        ]

        XCTAssertEqual(
            ServiceRouteHighlight(fromStop: "Frýdek-Místek,Frýdek,magistrát").range(in: stops),
            2...3
        )
        XCTAssertEqual(
            ServiceRouteHighlight(
                fromStop: "Frýdek,T.G.Masaryka",
                toStop: "Frýdek,magistrát"
            ).range(in: stops),
            1...2
        )
        XCTAssertEqual(
            ServiceRouteHighlight(toStop: "Frýdek,T.G.Masaryka").range(in: stops),
            0...1
        )
    }

    func testServiceSelectionRoundTripsThroughWindowState() throws {
        let selection = ServiceSelection(
            id: "service-301",
            highlight: ServiceRouteHighlight(fromStop: "Frýdlant n. O.", toStop: "Ostravice")
        )

        let data = try JSONEncoder().encode(selection)

        XCTAssertEqual(try JSONDecoder().decode(ServiceSelection.self, from: data), selection)
    }

    func testConnectionSearchBuildsCompleteIDOSRequest() async {
        let client = MockIDOSClient()
        let model = ConnectionsViewModel(client: client, calendarImporter: RecordingCalendarImporter())
        model.from = "Praha"
        model.to = " Brno "
        model.fromSelection = IDOSPlaceSelection(text: "Praha", listID: "100003", itemID: "5457076")
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
        XCTAssertEqual(request?.fromSelection, model.fromSelection)
        XCTAssertNil(request?.toSelection)
        XCTAssertEqual(request?.via, ["Pardubice", "Olomouc"])
        XCTAssertEqual(request?.timetable.slug, "vlaky")
        XCTAssertEqual(request?.isArrival, true)
        XCTAssertEqual(request?.maxTransfers, 2)
        XCTAssertEqual(request?.resultLimit, 10)
        XCTAssertEqual(model.connections.first?.id, "connection-1")
        XCTAssertNil(model.errorMessage)
    }

    func testConnectionPlaceSelectionsFollowSwapAndClearAfterEditing() {
        let model = ConnectionsViewModel(client: MockIDOSClient(), calendarImporter: RecordingCalendarImporter())
        let station = IDOSPlaceSelection(text: "Frýdek-Místek", listID: "100003", itemID: "10357")
        let municipality = IDOSPlaceSelection(text: "Ostrava", listID: "1", itemID: "10278")
        model.from = station.text
        model.fromSelection = station
        model.to = municipality.text
        model.toSelection = municipality

        model.swapEndpoints()

        XCTAssertEqual(model.from, municipality.text)
        XCTAssertEqual(model.fromSelection, municipality)
        XCTAssertEqual(model.to, station.text)
        XCTAssertEqual(model.toSelection, station)

        model.to = "Frýdek-Místek,Frýdek,aut.nádr."

        XCTAssertNil(model.toSelection)

        model.fromSelection = municipality
        model.timetable = IDOSTimetable(slug: "vlaky", displayName: "Trains")

        XCTAssertNil(model.fromSelection)
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

    func testZeroTransferLimitRequestsAndLabelsDirectConnections() async {
        let client = MockIDOSClient()
        let model = ConnectionsViewModel(client: client, calendarImporter: RecordingCalendarImporter())
        model.from = "Praha"
        model.to = "Brno"
        model.maximumTransfers = 0

        XCTAssertEqual(model.transferLimitLabel, AppLocalization.string("Direct only"))

        await model.search()

        let request = await client.lastConnectionRequest
        XCTAssertEqual(request?.onlyDirect, true)
        XCTAssertEqual(request?.maxTransfers, 0)
    }

    func testTransferLimitUsesLocaleAwarePluralForms() throws {
        let czech = try XCTUnwrap(localizationBundle(languageCode: "cs"))
        let english = try XCTUnwrap(localizationBundle(languageCode: "en"))

        XCTAssertEqual(AppLocalization.plural("Up to %lld transfers", count: 1, bundle: czech), "Nejvýše 1 přestup")
        XCTAssertEqual(AppLocalization.plural("Up to %lld transfers", count: 2, bundle: czech), "Nejvýše 2 přestupy")
        XCTAssertEqual(AppLocalization.plural("Up to %lld transfers", count: 4, bundle: czech), "Nejvýše 4 přestupy")
        XCTAssertEqual(AppLocalization.plural("Up to %lld transfers", count: 5, bundle: czech), "Nejvýše 5 přestupů")
        XCTAssertEqual(AppLocalization.plural("Up to %lld transfers", count: 1, bundle: english), "Up to 1 transfer")
        XCTAssertEqual(AppLocalization.plural("Up to %lld transfers", count: 2, bundle: english), "Up to 2 transfers")
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
        model.station = "Ostrava-Svinov"
        model.stationSelection = IDOSPlaceSelection(
            text: "Ostrava-Svinov",
            listID: "100003",
            itemID: "10288"
        )
        model.isArrival = true

        await model.search()

        let request = await client.lastDeparturesRequest
        XCTAssertEqual(request?.station, "Ostrava-Svinov")
        XCTAssertEqual(request?.stationSelection, model.stationSelection)
        XCTAssertEqual(request?.isArrival, true)
        XCTAssertEqual(model.departures.count, 20)
    }

    func testConnectionPagingPrependsAndAppendsUniqueResults() async {
        let client = MockIDOSClient()
        await client.configureConnectionPages(
            earlier: [connection(id: "connection-0"), connection(id: "connection-1")],
            later: [connection(id: "connection-1"), connection(id: "connection-2")]
        )
        let model = ConnectionsViewModel(client: client)
        model.from = "Praha"
        model.to = "Brno"

        await model.search()
        await model.loadMore(.earlier)
        await model.loadMore(.later)

        XCTAssertEqual(model.connections.map(\.id), ["connection-0", "connection-1", "connection-2"])
        let directions = await client.connectionPageDirections
        XCTAssertEqual(directions, [.earlier, .later])
    }

    func testDeparturePagingPrependsAndAppendsUniqueResults() async {
        let client = MockIDOSClient()
        await client.configureDeparturePages(
            earlier: [departure(id: "departure-0"), departure(id: "departure-1")],
            later: [departure(id: "departure-20"), departure(id: "departure-21")]
        )
        let model = DeparturesViewModel(client: client)
        model.station = "Ostrava-Svinov"

        await model.search()
        await model.loadMore(.earlier)
        await model.loadMore(.later)

        XCTAssertEqual(model.departures.first?.id, "departure-0")
        XCTAssertEqual(model.departures.last?.id, "departure-21")
        XCTAssertEqual(Set(model.departures.map(\.id)).count, model.departures.count)
        let directions = await client.departurePageDirections
        XCTAssertEqual(directions, [.earlier, .later])
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

    func testServiceCalendarImportUsesCalendarReturnedByIDOS() async {
        let client = MockIDOSClient()
        let importer = RecordingCalendarImporter()
        let model = ServiceDetailViewModel(
            id: "service-1",
            client: client,
            calendarImporter: importer
        )

        await model.load()
        await model.addToCalendar()

        XCTAssertEqual(importer.calendarText, "BEGIN:VCALENDAR\nEND:VCALENDAR")
        let serviceID = await client.lastCalendarServiceID
        XCTAssertEqual(serviceID, "service-1")
        XCTAssertFalse(model.isAddingToCalendar)
        XCTAssertNil(model.actionErrorMessage)
    }

    func testServicePDFExportUsesDocumentReturnedByIDOS() async {
        let client = MockIDOSClient()
        let exporter = RecordingPDFExporter()
        let model = ServiceDetailViewModel(
            id: "service-1",
            client: client,
            pdfExporter: exporter
        )

        await model.load()
        await model.saveAsPDF()

        XCTAssertEqual(exporter.pdfData, Data("%PDF-1.4\nKaštan".utf8))
        XCTAssertTrue(exporter.suggestedFileName?.contains("Ostrava-Svinov") == true)
        XCTAssertTrue(exporter.suggestedFileName?.hasSuffix(".pdf") == true)
        let serviceID = await client.lastPDFServiceID
        let language = await client.lastServicePDFLanguage
        XCTAssertEqual(serviceID, "service-1")
        XCTAssertEqual(language, AppLanguagePreference.idosLanguage)
        XCTAssertFalse(model.isSavingPDF)
        XCTAssertNil(model.actionErrorMessage)
    }

    func testPDFExportUsesDocumentReturnedByIDOSAndRouteFileName() async {
        let client = MockIDOSClient()
        let exporter = RecordingPDFExporter()
        let model = ConnectionsViewModel(client: client, pdfExporter: exporter)
        let connection = IDOSConnection(
            id: "connection-1",
            departureTime: "12:00",
            departureStation: "Praha / centrum",
            arrivalTime: "14:30",
            arrivalStation: "Brno: hlavní",
            duration: "2 h 30 min",
            legs: []
        )

        await model.saveAsPDF(connection)

        XCTAssertEqual(exporter.pdfData, Data("%PDF-1.4\nKaštan".utf8))
        XCTAssertTrue(exporter.suggestedFileName?.contains("Praha") == true)
        XCTAssertTrue(exporter.suggestedFileName?.contains("Brno") == true)
        XCTAssertTrue(exporter.suggestedFileName?.hasSuffix(".pdf") == true)
        XCTAssertFalse(exporter.suggestedFileName?.contains("/") == true)
        XCTAssertFalse(exporter.suggestedFileName?.contains(":") == true)
        XCTAssertFalse(exporter.suggestedFileName?.hasSuffix("..pdf") == true)
        let exportedLanguage = await client.lastPDFLanguage
        XCTAssertEqual(exportedLanguage, AppLanguagePreference.idosLanguage)
        XCTAssertNil(model.errorMessage)
        XCTAssertNil(model.exportingPDFConnectionID)
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

    func testStationTimetableSearchUsesSelectedLineDirectionAndWeekMode() async {
        let client = MockIDOSClient()
        let model = StationTimetablesViewModel(client: client)
        model.selectLineSuggestion(IDOSSuggestion(
            text: "Bus 154",
            from: "Strašnická",
            to: "Sídliště Libuš"
        ))
        model.wholeWeek = true

        await model.search()

        let request = await client.lastStationTimetableRequest
        let language = await client.lastStationTimetableLanguage
        XCTAssertEqual(request?.timetable.slug, "pid")
        XCTAssertEqual(request?.line, "Bus 154")
        XCTAssertEqual(request?.from, "Strašnická")
        XCTAssertEqual(request?.to, "Sídliště Libuš")
        XCTAssertEqual(request?.wholeWeek, true)
        XCTAssertEqual(request?.date, IDOSRequestFormatting.date(from: model.date))
        XCTAssertEqual(language, AppLanguagePreference.idosLanguage)
        XCTAssertEqual(model.result?.selectedStop?.name, "Strašnická")
        XCTAssertNil(model.errorMessage)
    }

    func testStationTimetableStopSelectionStartsAtThatStop() async {
        let client = MockIDOSClient()
        let model = StationTimetablesViewModel(client: client)
        model.selectLineSuggestion(IDOSSuggestion(
            text: "Bus 154",
            from: "Strašnická",
            to: "Sídliště Libuš"
        ))
        await model.search()

        await model.selectStop(at: 1)

        let request = await client.lastStationTimetableRequest
        XCTAssertEqual(model.from, "Na Hroudě")
        XCTAssertEqual(request?.from, "Na Hroudě")
        XCTAssertEqual(request?.to, "Sídliště Libuš")
        XCTAssertEqual(model.result?.selectedStop?.name, "Na Hroudě")
    }

    func testLocalizedErrorPresentationPreservesNetworkDetail() {
        let message = AppErrorPresentation.message(
            for: IDOSError.networkUnavailable("The connection was reset.")
        )

        XCTAssertTrue(message.contains("The connection was reset."))
        XCTAssertTrue(AppLocalization.string("Connection %lld", 3).contains("3"))
    }
}

private func connection(id: String) -> IDOSConnection {
    IDOSConnection(
        id: id,
        departureTime: "12:00",
        departureStation: "Praha hl.n.",
        arrivalTime: "14:30",
        arrivalStation: "Brno hl.n.",
        duration: "2 h 30 min",
        legs: []
    )
}

private func departure(id: String) -> IDOSDeparture {
    IDOSDeparture(
        id: id,
        time: "16:00",
        lineName: "S2",
        destination: "Opava"
    )
}

private func localizationBundle(languageCode: String) -> Bundle? {
    guard let url = Bundle.main.url(forResource: languageCode, withExtension: "lproj") else {
        return nil
    }
    return Bundle(url: url)
}

@MainActor
private final class RecordingCalendarImporter: CalendarImporting {
    private(set) var calendarText: String?

    func open(calendarText: String) throws {
        self.calendarText = calendarText
    }
}

@MainActor
private final class RecordingPDFExporter: PDFExporting {
    private(set) var pdfData: Data?
    private(set) var suggestedFileName: String?

    func save(pdfData: Data, suggestedFileName: String) async throws {
        self.pdfData = pdfData
        self.suggestedFileName = suggestedFileName
    }
}

private actor MockIDOSClient: IDOSClienting {
    var lastConnectionRequest: IDOSConnectionRequest?
    var lastDeparturesRequest: IDOSDeparturesRequest?
    var lastSuggestionQuery: SuggestionQuery?
    var lastPDFLanguage: IDOSLanguage?
    var lastCalendarServiceID: String?
    var lastPDFServiceID: String?
    var lastServicePDFLanguage: IDOSLanguage?
    var lastStationTimetableRequest: IDOSStationTimetableRequest?
    var lastStationTimetableLanguage: IDOSLanguage?
    var connectionPageDirections: [IDOSPageDirection] = []
    var departurePageDirections: [IDOSPageDirection] = []
    private var connectionPages: [IDOSPageDirection: [IDOSConnection]] = [:]
    private var departurePages: [IDOSPageDirection: [IDOSDeparture]] = [:]

    func configureConnectionPages(
        earlier: [IDOSConnection],
        later: [IDOSConnection]
    ) {
        connectionPages = [.earlier: earlier, .later: later]
    }

    func configureDeparturePages(
        earlier: [IDOSDeparture],
        later: [IDOSDeparture]
    ) {
        departurePages = [.earlier: earlier, .later: later]
    }

    func suggest(prefix: String, limit: Int, timetable: IDOSTimetable) async throws -> [IDOSSuggestion] {
        lastSuggestionQuery = SuggestionQuery(prefix: prefix, timetableSlug: timetable.slug)
        return [IDOSSuggestion(text: "Praha hl.n.")]
    }

    func searchStations(prefix: String, limit: Int, timetable: IDOSTimetable) async throws -> [IDOSSuggestion] {
        [IDOSSuggestion(text: "Ostrava-Svinov")]
    }

    func searchStationTimetableLines(
        prefix: String,
        limit: Int,
        timetable: IDOSTimetable
    ) async throws -> [IDOSSuggestion] {
        [IDOSSuggestion(text: "Bus 154", from: "Strašnická", to: "Sídliště Libuš")]
    }

    func searchStationTimetableStops(
        prefix: String,
        line: String,
        limit: Int,
        timetable: IDOSTimetable
    ) async throws -> [IDOSSuggestion] {
        [IDOSSuggestion(text: "Strašnická")]
    }

    func findStationTimetable(
        request: IDOSStationTimetableRequest,
        language: IDOSLanguage
    ) async throws -> IDOSStationTimetable {
        lastStationTimetableRequest = request
        lastStationTimetableLanguage = language
        return IDOSStationTimetable(
            timetable: request.timetable,
            lineName: request.line,
            transportMode: .bus,
            fromStop: request.from,
            toStop: request.to,
            stops: [
                IDOSStationTimetableStop(name: request.from, minuteOffset: 0, platform: "1", isSelected: true),
                IDOSStationTimetableStop(name: "Na Hroudě", minuteOffset: 1, platform: "2"),
                IDOSStationTimetableStop(name: request.to, minuteOffset: 42, platform: "4"),
            ],
            schedules: [
                IDOSStationTimetableSchedule(
                    label: "Friday",
                    hours: [IDOSStationTimetableHour(hour: "5", departures: ["13", "35"])]
                )
            ]
        )
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

    func findConnectionsPage(request: IDOSConnectionRequest) async throws -> IDOSConnectionPage {
        IDOSConnectionPage(
            connections: try await findConnections(request: request),
            canLoadEarlier: connectionPages[.earlier] != nil,
            canLoadLater: connectionPages[.later] != nil
        )
    }

    func findConnectionsPage(
        from page: IDOSConnectionPage,
        direction: IDOSPageDirection
    ) async throws -> IDOSConnectionPage {
        connectionPageDirections.append(direction)
        return IDOSConnectionPage(
            connections: connectionPages[direction] ?? [],
            canLoadEarlier: connectionPages[.earlier] != nil,
            canLoadLater: connectionPages[.later] != nil
        )
    }

    func connectionCalendar(for connection: IDOSConnection, timetable: IDOSTimetable) async throws -> String {
        "BEGIN:VCALENDAR\nEND:VCALENDAR"
    }

    func serviceCalendar(for service: IDOSServiceDetail) async throws -> String {
        lastCalendarServiceID = service.id
        return "BEGIN:VCALENDAR\nEND:VCALENDAR"
    }

    func servicePDF(for service: IDOSServiceDetail, language: IDOSLanguage) async throws -> Data {
        lastPDFServiceID = service.id
        lastServicePDFLanguage = language
        return Data("%PDF-1.4\nKaštan".utf8)
    }

    func connectionPDF(
        for connection: IDOSConnection,
        timetable: IDOSTimetable,
        language: IDOSLanguage
    ) async throws -> Data {
        lastPDFLanguage = language
        return Data("%PDF-1.4\nKaštan".utf8)
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

    func findDeparturesPage(request: IDOSDeparturesRequest) async throws -> IDOSDeparturePage {
        IDOSDeparturePage(
            departures: Array(try await findDepartures(request: request).prefix(20)),
            canLoadEarlier: departurePages[.earlier] != nil,
            canLoadLater: departurePages[.later] != nil
        )
    }

    func findDeparturesPage(
        from page: IDOSDeparturePage,
        direction: IDOSPageDirection
    ) async throws -> IDOSDeparturePage {
        departurePageDirections.append(direction)
        return IDOSDeparturePage(
            departures: departurePages[direction] ?? [],
            canLoadEarlier: departurePages[.earlier] != nil,
            canLoadLater: departurePages[.later] != nil
        )
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
