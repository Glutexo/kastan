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

    func testCzechRunsOnlyNoteIsScopedToCurrentTimetableValidity() throws {
        let note = "jede 19.VII."
        let serviceCalendar = try XCTUnwrap(StationTimetableServiceCalendar(
            note: note,
            allNotes: ["platí od 1.7.2026 do 26.7.2026", note]
        ))

        XCTAssertEqual(serviceCalendar.rule.recurrence, .none)
        XCTAssertEqual(serviceCalendar.validityStart, serviceDate(2026, 7, 1))
        XCTAssertEqual(serviceCalendar.validityEnd, serviceDate(2026, 7, 26))
        XCTAssertEqual(serviceCalendar.listedDates, [serviceDate(2026, 7, 19)])
        XCTAssertEqual(serviceCalendar.status(on: serviceDate(2026, 7, 18)), .doesNotRun)
        XCTAssertEqual(serviceCalendar.status(on: serviceDate(2026, 7, 19)), .runs)
        XCTAssertEqual(serviceCalendar.status(on: serviceDate(2026, 6, 30)), .outsideTimetableValidity)
        XCTAssertEqual(serviceCalendar.status(on: serviceDate(2026, 7, 27)), .outsideTimetableValidity)
    }

    func testEnglishDoesNotRunRangeExpandsOnlyInsideCurrentTimetable() throws {
        let note = "A: does not run 19.VII.–21.VII."
        let serviceCalendar = try XCTUnwrap(StationTimetableServiceCalendar(
            note: note,
            allNotes: ["valid from 1.7.2026 to 31.7.2026", note]
        ))

        XCTAssertEqual(serviceCalendar.rule.recurrence, .everyDay)
        XCTAssertEqual(
            serviceCalendar.listedDates,
            [serviceDate(2026, 7, 19), serviceDate(2026, 7, 20), serviceDate(2026, 7, 21)]
        )
        XCTAssertEqual(serviceCalendar.status(on: serviceDate(2026, 7, 18)), .runs)
        XCTAssertEqual(serviceCalendar.status(on: serviceDate(2026, 7, 20)), .doesNotRun)
    }

    func testAbbreviatedDoesNotRunRangeInServiceInformationUsesTimetableValidity() throws {
        let note = "nejede od 17. do 20.VIII."
        let serviceCalendar = try XCTUnwrap(StationTimetableServiceCalendar(
            note: note,
            validityStart: serviceDate(2025, 12, 14),
            validityEnd: serviceDate(2026, 12, 12)
        ))

        XCTAssertEqual(serviceCalendar.rule.recurrence, .everyDay)
        XCTAssertEqual(
            serviceCalendar.listedDates,
            (17...20).map { serviceDate(2026, 8, $0) }
        )
        XCTAssertEqual(
            serviceCalendar.recognizedDateRanges,
            [serviceDate(2026, 8, 17)...serviceDate(2026, 8, 20)]
        )
        XCTAssertEqual(serviceCalendar.status(on: serviceDate(2026, 8, 16)), .runs)
        XCTAssertEqual(serviceCalendar.status(on: serviceDate(2026, 8, 17)), .doesNotRun)
        XCTAssertEqual(serviceCalendar.status(on: serviceDate(2026, 8, 20)), .doesNotRun)
        XCTAssertEqual(serviceCalendar.status(on: serviceDate(2026, 8, 21)), .runs)
    }

    func testAbbreviatedDateListInheritsTheFollowingMonth() throws {
        let note = "nejede 23.VII.,18.,19.IX.,26.XI.,10.XII."
        let serviceCalendar = try XCTUnwrap(StationTimetableServiceCalendar(
            note: note,
            validityStart: serviceDate(2025, 12, 14),
            validityEnd: serviceDate(2026, 12, 12)
        ))

        XCTAssertEqual(serviceCalendar.rule.recurrence, .everyDay)
        XCTAssertEqual(serviceCalendar.listedDates, [
            serviceDate(2026, 7, 23),
            serviceDate(2026, 9, 18),
            serviceDate(2026, 9, 19),
            serviceDate(2026, 11, 26),
            serviceDate(2026, 12, 10),
        ])
        XCTAssertEqual(serviceCalendar.recognizedDateRanges, [
            serviceDate(2026, 7, 23)...serviceDate(2026, 7, 23),
            serviceDate(2026, 9, 18)...serviceDate(2026, 9, 18),
            serviceDate(2026, 9, 19)...serviceDate(2026, 9, 19),
            serviceDate(2026, 11, 26)...serviceDate(2026, 11, 26),
            serviceDate(2026, 12, 10)...serviceDate(2026, 12, 10),
        ])
        XCTAssertEqual(serviceCalendar.status(on: serviceDate(2026, 9, 17)), .runs)
        XCTAssertEqual(serviceCalendar.status(on: serviceDate(2026, 9, 18)), .doesNotRun)
        XCTAssertEqual(serviceCalendar.status(on: serviceDate(2026, 9, 19)), .doesNotRun)
    }

    func testWorkingDayRuleCombinesWithDatedExceptionAndCzechHolidays() throws {
        let note = "jede v X.,nejede od 18. do 23.VIII."
        let serviceCalendar = try XCTUnwrap(StationTimetableServiceCalendar(
            note: note,
            validityStart: serviceDate(2025, 12, 14),
            validityEnd: serviceDate(2026, 12, 12)
        ))

        XCTAssertEqual(serviceCalendar.rule.recurrence, .workingDays)
        XCTAssertEqual(
            serviceCalendar.listedDates,
            (18...23).map { serviceDate(2026, 8, $0) }
        )
        XCTAssertEqual(serviceCalendar.status(on: serviceDate(2026, 8, 17)), .runs)
        XCTAssertEqual(serviceCalendar.status(on: serviceDate(2026, 8, 18)), .doesNotRun)
        XCTAssertEqual(serviceCalendar.status(on: serviceDate(2026, 8, 21)), .doesNotRun)
        XCTAssertEqual(serviceCalendar.status(on: serviceDate(2026, 8, 22)), .doesNotRun)
        XCTAssertEqual(serviceCalendar.status(on: serviceDate(2026, 8, 23)), .doesNotRun)
        XCTAssertEqual(serviceCalendar.status(on: serviceDate(2026, 8, 24)), .runs)
        XCTAssertEqual(serviceCalendar.status(on: serviceDate(2026, 8, 29)), .doesNotRun)
        XCTAssertEqual(serviceCalendar.status(on: serviceDate(2026, 4, 3)), .doesNotRun)
        XCTAssertEqual(serviceCalendar.status(on: serviceDate(2026, 4, 6)), .doesNotRun)
        XCTAssertEqual(serviceCalendar.status(on: serviceDate(2026, 4, 7)), .runs)
        XCTAssertEqual(serviceCalendar.status(on: serviceDate(2026, 9, 28)), .doesNotRun)
    }

    func testSingleDateRangesExpandToTheNamedTimetableBoundary() throws {
        let validityStart = serviceDate(2025, 12, 14)
        let validityEnd = serviceDate(2026, 12, 12)
        let runsUntil = try XCTUnwrap(StationTimetableServiceCalendar(
            note: "jede do 3.XII.",
            validityStart: validityStart,
            validityEnd: validityEnd
        ))
        let doesNotRunFrom = try XCTUnwrap(StationTimetableServiceCalendar(
            note: "does not run from 3.XII.",
            validityStart: validityStart,
            validityEnd: validityEnd
        ))

        XCTAssertEqual(runsUntil.listedDates.first, validityStart)
        XCTAssertEqual(runsUntil.listedDates.last, serviceDate(2026, 12, 3))
        XCTAssertEqual(
            runsUntil.recognizedDateRanges,
            [validityStart...serviceDate(2026, 12, 3)]
        )
        XCTAssertEqual(runsUntil.status(on: serviceDate(2026, 12, 2)), .runs)
        XCTAssertEqual(runsUntil.status(on: serviceDate(2026, 12, 3)), .runs)
        XCTAssertEqual(runsUntil.status(on: serviceDate(2026, 12, 4)), .doesNotRun)

        XCTAssertEqual(doesNotRunFrom.listedDates.first, serviceDate(2026, 12, 3))
        XCTAssertEqual(doesNotRunFrom.listedDates.last, validityEnd)
        XCTAssertEqual(
            doesNotRunFrom.recognizedDateRanges,
            [serviceDate(2026, 12, 3)...validityEnd]
        )
        XCTAssertEqual(doesNotRunFrom.status(on: serviceDate(2026, 12, 2)), .runs)
        XCTAssertEqual(doesNotRunFrom.status(on: serviceDate(2026, 12, 3)), .doesNotRun)
        XCTAssertEqual(doesNotRunFrom.status(on: serviceDate(2026, 12, 4)), .doesNotRun)
    }

    func testRunsUntilRangeIsRestrictedToNumberedWeekendDays() throws {
        let validityStart = serviceDate(2025, 12, 14)
        let serviceCalendar = try XCTUnwrap(StationTimetableServiceCalendar(
            note: "jede do 29.VIII. v 6,7",
            validityStart: validityStart,
            validityEnd: serviceDate(2026, 12, 12)
        ))

        XCTAssertEqual(serviceCalendar.rule.recurrence, .selectedWeekdays(Set([6, 7])))
        XCTAssertEqual(serviceCalendar.listedDates.first, validityStart)
        XCTAssertEqual(serviceCalendar.listedDates.last, serviceDate(2026, 8, 29))
        XCTAssertEqual(serviceCalendar.status(on: validityStart), .runs)
        XCTAssertEqual(serviceCalendar.status(on: serviceDate(2026, 8, 28)), .doesNotRun)
        XCTAssertEqual(serviceCalendar.status(on: serviceDate(2026, 8, 29)), .runs)
        XCTAssertEqual(serviceCalendar.status(on: serviceDate(2026, 8, 30)), .doesNotRun)
        XCTAssertEqual(serviceCalendar.status(on: serviceDate(2026, 9, 5)), .doesNotRun)
    }

    func testNumberedWeekdayRangeComposesWithPositiveAndNegativeExceptions() throws {
        let validityStart = serviceDate(2025, 12, 14)
        let serviceCalendar = try XCTUnwrap(StationTimetableServiceCalendar(
            note: "jede do 3.XI. v 1-6,27.IX.,nejede 28.IX.",
            validityStart: validityStart,
            validityEnd: serviceDate(2026, 12, 12)
        ))

        XCTAssertEqual(serviceCalendar.rule.recurrence, .selectedWeekdays(Set(1...6)))
        XCTAssertEqual(serviceCalendar.rule.operatingRange, validityStart...serviceDate(2026, 11, 3))
        XCTAssertEqual(
            serviceCalendar.rule.additionalRunningRanges,
            [serviceDate(2026, 9, 27)...serviceDate(2026, 9, 27)]
        )
        XCTAssertEqual(
            serviceCalendar.rule.nonRunningRanges,
            [serviceDate(2026, 9, 28)...serviceDate(2026, 9, 28)]
        )
        XCTAssertEqual(serviceCalendar.recognizedDateRanges, [
            validityStart...serviceDate(2026, 11, 3),
            serviceDate(2026, 9, 27)...serviceDate(2026, 9, 27),
            serviceDate(2026, 9, 28)...serviceDate(2026, 9, 28),
        ])
        XCTAssertEqual(serviceCalendar.status(on: serviceDate(2026, 9, 26)), .runs)
        XCTAssertEqual(serviceCalendar.status(on: serviceDate(2026, 9, 27)), .runs)
        XCTAssertEqual(serviceCalendar.status(on: serviceDate(2026, 9, 28)), .doesNotRun)
        XCTAssertEqual(serviceCalendar.status(on: serviceDate(2026, 9, 29)), .runs)
        XCTAssertEqual(serviceCalendar.status(on: serviceDate(2026, 11, 3)), .runs)
        XCTAssertEqual(serviceCalendar.status(on: serviceDate(2026, 11, 4)), .doesNotRun)
    }

    func testWeekdayHyphenDoesNotConsumeALaterPositiveException() throws {
        let serviceCalendar = try XCTUnwrap(StationTimetableServiceCalendar(
            note: "jede do 29.VIII. v 1-6,6.IX.",
            validityStart: serviceDate(2025, 12, 14),
            validityEnd: serviceDate(2026, 12, 12)
        ))

        XCTAssertEqual(serviceCalendar.rule.recurrence, .selectedWeekdays(Set(1...6)))
        XCTAssertEqual(
            serviceCalendar.rule.additionalRunningRanges,
            [serviceDate(2026, 9, 6)...serviceDate(2026, 9, 6)]
        )
        XCTAssertEqual(serviceCalendar.status(on: serviceDate(2026, 9, 5)), .doesNotRun)
        XCTAssertEqual(serviceCalendar.status(on: serviceDate(2026, 9, 6)), .runs)
        XCTAssertEqual(serviceCalendar.status(on: serviceDate(2026, 9, 7)), .doesNotRun)
    }

    func testStandaloneNumberedWeekdaysOfferANoteApplicabilityCalendar() throws {
        let serviceCalendar = try XCTUnwrap(StationTimetableServiceCalendar(
            note: "občerstvení (roznášková služba nebo samoobslužný automat) v 1-5,7",
            validityStart: serviceDate(2025, 12, 14),
            validityEnd: serviceDate(2026, 12, 12)
        ))

        XCTAssertEqual(serviceCalendar.rule.subject, .noteApplicability)
        XCTAssertEqual(serviceCalendar.rule.recurrence, .selectedWeekdays(Set([1, 2, 3, 4, 5, 7])))
        XCTAssertTrue(serviceCalendar.listedDates.isEmpty)
        let linkedContent = StationTimetableServiceCalendarButton.noteApplicabilityContent(
            for: serviceCalendar
        )
        let linkedRuns = linkedContent.runs.filter { $0.link != nil }
        XCTAssertEqual(String(linkedContent.characters), serviceCalendar.note)
        XCTAssertEqual(linkedRuns.count, 1)
        XCTAssertEqual(String(linkedContent[linkedRuns[0].range].characters), "v 1-5,7")
        XCTAssertEqual(linkedRuns[0].link, StationTimetableServiceCalendarButton.noteCalendarDestination)
        XCTAssertEqual(serviceCalendar.status(on: serviceDate(2026, 7, 20)), .runs)
        XCTAssertEqual(serviceCalendar.status(on: serviceDate(2026, 7, 25)), .doesNotRun)
        XCTAssertEqual(serviceCalendar.status(on: serviceDate(2026, 7, 26)), .runs)
        XCTAssertEqual(
            serviceCalendar.status(on: serviceDate(2025, 12, 13)),
            .outsideTimetableValidity
        )
    }

    func testServiceCalendarInitiallyShowsCurrentOrNearestValidityMonth() throws {
        let serviceCalendar = try XCTUnwrap(StationTimetableServiceCalendar(
            note: "nejede 24.XII.",
            validityStart: serviceDate(2025, 12, 14),
            validityEnd: serviceDate(2026, 12, 12)
        ))

        XCTAssertEqual(
            serviceCalendar.initialVisibleMonth(on: serviceDate(2026, 7, 19)),
            serviceDate(2026, 7, 1)
        )
        XCTAssertEqual(
            serviceCalendar.initialVisibleMonth(on: serviceDate(2025, 11, 30)),
            serviceDate(2025, 12, 1)
        )
        XCTAssertEqual(
            serviceCalendar.initialVisibleMonth(on: serviceDate(2027, 1, 1)),
            serviceDate(2026, 12, 1)
        )
    }

    func testOptionClickRequestsRecognizedCalendarConditions() {
        XCTAssertTrue(ServiceCalendarOpeningOptions.showsRecognizedConditions(for: [.option]))
        XCTAssertTrue(ServiceCalendarOpeningOptions.showsRecognizedConditions(for: [.option, .shift]))
        XCTAssertFalse(ServiceCalendarOpeningOptions.showsRecognizedConditions(for: []))
        XCTAssertFalse(ServiceCalendarOpeningOptions.showsRecognizedConditions(for: [.command]))
    }

    func testServiceNotesReceiveSemanticEmoji() {
        XCTAssertEqual(
            ServiceNoteEmoji.symbol(for: "Na trase spojení je toto plánované omezení provozu."),
            "🚧"
        )
        XCTAssertEqual(ServiceNoteEmoji.symbol(for: "Háje - Letňany"), "🛤️")
        XCTAssertEqual(ServiceNoteEmoji.symbol(for: "Dopravní podnik hl. m. Prahy, a.s."), "🏢")
        XCTAssertEqual(ServiceNoteEmoji.symbol(for: "jede v 1-5", presentsCalendar: true), "📅")
        XCTAssertEqual(ServiceNoteEmoji.symbol(for: "Doplňující informace"), "ℹ️")
    }

    func testNonDatedAndOutOfValidityNotesDoNotOfferServiceCalendars() {
        XCTAssertNil(StationTimetableServiceCalendar(
            note: "A: jede jen do zastávky Háje",
            allNotes: ["platí od 1.7.2026 do 26.7.2026", "A: jede jen do zastávky Háje"]
        ))
        XCTAssertNil(StationTimetableServiceCalendar(
            note: "jede 19.VIII.",
            allNotes: ["platí od 1.7.2026 do 26.7.2026", "jede 19.VIII."]
        ))
        XCTAssertNil(StationTimetableServiceCalendar(
            note: "jede 19.VII.",
            allNotes: ["jede 19.VII."]
        ))
    }

    func testNoteTextTurnsPhoneNumbersIntoTelLinksWithoutChangingTheNote() {
        let value = "Informace: +420 123 456 789 nebo 800 123 456."
        let content = NoteText.linkedContent(value)

        XCTAssertEqual(String(content.characters), value)
        XCTAssertEqual(
            content.runs.compactMap { $0.link?.absoluteString },
            ["tel:+420123456789", "tel:800123456"]
        )
    }

    func testNoteTextDoesNotInterpretTimetableDatesAsPhoneNumbers() {
        let value = "platí od 1.7.2026 do 26.7.2026 · jede 19.VII."
        let content = NoteText.linkedContent(value)

        XCTAssertEqual(String(content.characters), value)
        XCTAssertTrue(content.runs.compactMap { $0.link }.isEmpty)
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

    private func serviceDate(_ year: Int, _ month: Int, _ day: Int) -> Date {
        StationTimetableServiceCalendar.serviceCalendar.date(from: DateComponents(
            timeZone: StationTimetableServiceCalendar.serviceCalendar.timeZone,
            year: year,
            month: month,
            day: day
        ))!
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

    func testConnectionDetailToolbarOffersEveryAvailableActionSeparately() {
        XCTAssertEqual(
            ConnectionDetailToolbarAction.allCases,
            [.addToCalendar, .saveAsPDF, .shareLink, .openInIDOS]
        )
        XCTAssertEqual(
            ConnectionDetailToolbarAction.allCases.map(\.systemImage),
            ["calendar.badge.plus", "arrow.down.doc", "square.and.arrow.up", "arrow.up.right.square"]
        )
        XCTAssertEqual(
            ConnectionDetailToolbarAction.availableActions(hasPermanentLink: true),
            ConnectionDetailToolbarAction.allCases
        )
        XCTAssertEqual(
            ConnectionDetailToolbarAction.availableActions(hasPermanentLink: false),
            [.addToCalendar, .saveAsPDF]
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
        XCTAssertEqual(JourneySearchControls.timetableFavoriteSpacing(usesStackedLayout: true), -4)
        XCTAssertEqual(JourneySearchControls.timetableFavoriteSpacing(usesStackedLayout: false), 0)
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
        XCTAssertEqual(AppWindow.connectionDetail, "connection-detail")
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
        XCTAssertEqual(municipality.kind, .municipality)
        XCTAssertEqual(station.emoji, "🚆")
        XCTAssertEqual(station.kind, .train)
        XCTAssertEqual(busStop.kind, .bus)
        XCTAssertEqual(station.detail?.components(separatedBy: " · ").count, 3)
        XCTAssertEqual(
            station.detail?.components(separatedBy: " · ").filter { $0.contains("Frýdek-Místek") }.count,
            1
        )
        XCTAssertEqual(busStop.emoji, "🚌")
        XCTAssertEqual(busStop.detail?.components(separatedBy: " · ").count, 4)
        XCTAssertEqual(romanianMunicipality.detail, "Rumunsko")
    }

    func testExactSuggestionSelectionCarriesALocalizedVisibleType() throws {
        let selection = try XCTUnwrap(PlaceFieldSelection(suggestion: IDOSSuggestion(
            selectedText: "Frýdek-Místek",
            text: "Frýdek-Místek",
            description: "station, district Frýdek-Místek, trains",
            value: "100003",
            value2: "10357"
        )))
        let czech = try XCTUnwrap(localizationBundle(languageCode: "cs"))
        let english = try XCTUnwrap(localizationBundle(languageCode: "en"))

        XCTAssertEqual(selection.idosSelection.text, "Frýdek-Místek")
        XCTAssertEqual(selection.kind, .train)
        let keys = ["municipality", "train", "bus"]
        XCTAssertEqual(
            keys.map { czech.localizedString(forKey: $0, value: nil, table: nil) },
            ["obec", "vlak", "autobus"]
        )
        XCTAssertEqual(
            keys.map { english.localizedString(forKey: $0, value: nil, table: nil) },
            ["municipality", "train", "bus"]
        )
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

    func testDelayPresentationLocalizesKnownStateAndPreservesCarrierDetail() throws {
        XCTAssertEqual(
            ResultMetadata.delay(" Currently no delay "),
            AppLocalization.string("Currently no delay")
        )
        XCTAssertEqual(
            ResultMetadata.delay("Departure tends to be on time"),
            AppLocalization.string("Departure tends to be on time")
        )
        XCTAssertEqual(ResultMetadata.delay("Delay 12 min"), "Delay 12 min")
        XCTAssertNil(ResultMetadata.delay("  "))

        let czech = try XCTUnwrap(localizationBundle(languageCode: "cs"))
        let english = try XCTUnwrap(localizationBundle(languageCode: "en"))
        let key = "Departure tends to be on time"
        XCTAssertEqual(czech.localizedString(forKey: key, value: nil, table: nil), "Odjezd bývá včas")
        XCTAssertEqual(english.localizedString(forKey: key, value: nil, table: nil), key)
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
        XCTAssertEqual(
            ServiceRouteHighlight(fromStop: "Frýdek-Místek,Frýdek,magistrát").departureIndex(in: stops),
            2
        )
        XCTAssertNil(ServiceRouteHighlight(toStop: "Frýdek,T.G.Masaryka").departureIndex(in: stops))
    }

    func testServiceSelectionRoundTripsThroughWindowState() throws {
        let selection = ServiceSelection(
            id: "service-301",
            highlight: ServiceRouteHighlight(fromStop: "Frýdlant n. O.", toStop: "Ostravice")
        )

        let data = try JSONEncoder().encode(selection)

        XCTAssertEqual(try JSONDecoder().decode(ServiceSelection.self, from: data), selection)
    }

    func testServiceDateMovesIntoWindowTitleOnlyAfterScrollingOutOfView() {
        let service = IDOSServiceDetail(
            id: "tram-4",
            name: "Tram 4",
            transportMode: .tram,
            date: "19.7.2026",
            stops: []
        )

        XCTAssertEqual(
            ServiceWindowTitlePresentation.title(for: service, dateIsUnderTitle: false),
            "🚋 Tram 4"
        )
        XCTAssertEqual(
            ServiceWindowTitlePresentation.title(for: service, dateIsUnderTitle: true),
            "🚋 Tram 4 · 19.7.2026"
        )
        XCTAssertFalse(
            ServiceWindowTitlePresentation.dateIsUnderTitle(
                frame: CGRect(x: 0, y: -18, width: 80, height: 19)
            )
        )
        XCTAssertTrue(
            ServiceWindowTitlePresentation.dateIsUnderTitle(
                frame: CGRect(x: 0, y: -19, width: 80, height: 19)
            )
        )
    }

    func testConnectionTimeMovesIntoWindowTitleOnlyAfterScrollingOutOfView() {
        let connection = connection(id: "connection-title")

        XCTAssertEqual(
            ConnectionWindowTitlePresentation.title(for: connection, timeIsUnderTitle: false),
            "Praha hl.n. → Brno hl.n."
        )
        XCTAssertEqual(
            ConnectionWindowTitlePresentation.title(for: connection, timeIsUnderTitle: true),
            "Praha hl.n. → Brno hl.n. · 12:00 → 14:30"
        )
        XCTAssertFalse(
            ConnectionWindowTitlePresentation.timeIsUnderTitle(
                frame: CGRect(x: 0, y: -27, width: 150, height: 28)
            )
        )
        XCTAssertTrue(
            ConnectionWindowTitlePresentation.timeIsUnderTitle(
                frame: CGRect(x: 0, y: -28, width: 150, height: 28)
            )
        )
    }

    func testCompleteConnectionRoundTripsThroughWindowState() throws {
        let selection = ConnectionSelection(
            connection: connection(id: "connection-window"),
            timetable: IDOSTimetable(slug: "vlaky", displayName: "Trains")
        )

        let data = try JSONEncoder().encode(selection)
        let decoded = try JSONDecoder().decode(ConnectionSelection.self, from: data)

        XCTAssertEqual(decoded, selection)
        XCTAssertEqual(decoded.id, "vlaky:connection-window")
        XCTAssertEqual(Set([decoded, selection]).count, 1)

        let czech = try XCTUnwrap(localizationBundle(languageCode: "cs"))
        XCTAssertEqual(
            czech.localizedString(
                forKey: "Open connection in new window",
                value: nil,
                table: nil
            ),
            "Otevřít spojení v novém okně"
        )
    }

    func testCompleteConnectionDetailRendersInAnIndependentWindow() {
        let selection = ConnectionSelection(
            connection: connection(id: "connection-detail"),
            timetable: IDOSTimetable(slug: "vlaky", displayName: "Trains")
        )
        let hostingView = NSHostingView(
            rootView: ConnectionDetailView(selection: selection, client: MockIDOSClient())
                .frame(width: 700, height: 500)
        )
        hostingView.frame = NSRect(x: 0, y: 0, width: 700, height: 500)
        let window = NSWindow(
            contentRect: hostingView.frame,
            styleMask: .titled,
            backing: .buffered,
            defer: false
        )
        window.contentView = hostingView
        window.makeKeyAndOrderFront(nil)
        hostingView.layoutSubtreeIfNeeded()
        defer { window.orderOut(nil) }

        XCTAssertEqual(hostingView.frame.size, NSSize(width: 700, height: 500))
        XCTAssertGreaterThan(hostingView.fittingSize.height, 0)
    }

    func testConnectionSearchBuildsCompleteIDOSRequest() async {
        let client = MockIDOSClient()
        let model = ConnectionsViewModel(client: client, calendarImporter: RecordingCalendarImporter())
        model.from = "Praha"
        model.to = " Brno "
        model.timetable = IDOSTimetable(slug: "vlaky", displayName: "Trains")
        let fromSelection = PlaceFieldSelection(
            idosSelection: IDOSPlaceSelection(text: "Praha", listID: "100003", itemID: "5457076"),
            kind: .train
        )
        model.fromSelection = fromSelection
        model.journeyOptions = [
            JourneyOptionEntry(viaPlace: " Pardubice "),
            JourneyOptionEntry(viaPlace: ""),
            JourneyOptionEntry(viaPlace: "Olomouc"),
            JourneyOptionEntry(kind: .maximumTransfers, maximumTransfers: 2),
        ]
        model.isArrival = true

        await model.search()

        let request = await client.lastConnectionRequest
        XCTAssertEqual(request?.from, "Praha")
        XCTAssertEqual(request?.to, "Brno")
        XCTAssertEqual(request?.fromSelection, fromSelection.idosSelection)
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
        let station = PlaceFieldSelection(
            idosSelection: IDOSPlaceSelection(text: "Frýdek-Místek", listID: "100003", itemID: "10357"),
            kind: .train
        )
        let municipality = PlaceFieldSelection(
            idosSelection: IDOSPlaceSelection(text: "Ostrava", listID: "1", itemID: "10278"),
            kind: .municipality
        )
        model.from = station.text
        model.fromSelection = station
        model.to = municipality.text
        model.toSelection = municipality

        model.swapEndpoints()

        XCTAssertEqual(model.from, municipality.text)
        XCTAssertEqual(model.fromSelection, municipality)
        XCTAssertEqual(model.fromSelection?.kind, .municipality)
        XCTAssertEqual(model.to, station.text)
        XCTAssertEqual(model.toSelection, station)
        XCTAssertEqual(model.toSelection?.kind, .train)

        model.to = "Frýdek-Místek,Frýdek,aut.nádr."

        XCTAssertNil(model.toSelection)

        model.fromSelection = municipality
        model.timetable = IDOSTimetable(slug: "vlaky", displayName: "Trains")

        XCTAssertNil(model.fromSelection)
    }

    func testJourneyOptionRowsCanBeAddedAndRemovedWithoutDroppingTheLastField() {
        let model = ConnectionsViewModel(client: MockIDOSClient(), calendarImporter: RecordingCalendarImporter())
        let firstID = model.journeyOptions[0].id

        model.addJourneyOption(after: firstID)
        XCTAssertEqual(model.journeyOptions.count, 2)

        let secondID = model.journeyOptions[1].id
        model.journeyOptions[1].viaPlace = "Olomouc"
        model.removeJourneyOption(id: firstID)
        XCTAssertEqual(model.viaPlaceNames, ["Olomouc"])

        model.removeJourneyOption(id: secondID)
        XCTAssertEqual(model.journeyOptions, [JourneyOptionEntry(id: secondID)])
    }

    func testJourneyOptionPickerKeepsSingletonConditionsUnique() {
        let model = ConnectionsViewModel(client: MockIDOSClient(), calendarImporter: RecordingCalendarImporter())
        let firstID = model.journeyOptions[0].id

        XCTAssertEqual(model.availableJourneyOptionKinds(for: firstID), [.via, .maximumTransfers])

        model.journeyOptions[0].kind = .maximumTransfers
        model.addJourneyOption(after: firstID)
        let secondID = model.journeyOptions[1].id

        XCTAssertEqual(model.availableJourneyOptionKinds(for: firstID), [.via, .maximumTransfers])
        XCTAssertEqual(model.availableJourneyOptionKinds(for: secondID), [.via])

        model.removeJourneyOption(id: firstID)

        XCTAssertEqual(model.availableJourneyOptionKinds(for: secondID), [.via, .maximumTransfers])
    }

    func testJourneyOptionValuePlaceholderDiffersFromViaConditionName() throws {
        let czech = try XCTUnwrap(localizationBundle(languageCode: "cs"))
        let english = try XCTUnwrap(localizationBundle(languageCode: "en"))

        XCTAssertEqual(czech.localizedString(forKey: "Via place", value: nil, table: nil), "Místo přes")
        XCTAssertEqual(english.localizedString(forKey: "Via place", value: nil, table: nil), "Via place")
    }

    func testJourneyOptionPickerUsesCompactStableCatalogWidthWhenOnlyViaIsAvailable() throws {
        let picker = JourneyOptionKindPicker(
            selection: .constant(.via),
            availableKinds: [.via]
        )
        let hostingView = NSHostingView(rootView: picker.fixedSize(horizontal: true, vertical: false))
        hostingView.frame = NSRect(x: 0, y: 0, width: 1_000, height: 30)

        hostingView.layoutSubtreeIfNeeded()

        let popupButton = try XCTUnwrap(
            ([hostingView] + hostingView.allDescendantViews)
            .compactMap { $0 as? StableWidthPopUpButton }
            .first
        )
        let catalogWidth = popupButton.intrinsicContentSize.width
        let nativeCatalogButton = NSPopUpButton(frame: .zero, pullsDown: false)
        nativeCatalogButton.controlSize = .regular
        nativeCatalogButton.addItems(withTitles: JourneyOptionKind.allCases.map(\.localizedTitle))

        XCTAssertEqual(popupButton.sizingTitles, JourneyOptionKind.allCases.map(\.localizedTitle))
        XCTAssertEqual(catalogWidth, nativeCatalogButton.intrinsicContentSize.width, accuracy: 0.5)
        XCTAssertEqual(popupButton.frame.width, catalogWidth, accuracy: 0.5)

        popupButton.sizingTitles = [JourneyOptionKind.via.localizedTitle]
        XCTAssertGreaterThan(catalogWidth, popupButton.intrinsicContentSize.width)
    }

    func testZeroTransferLimitRequestsAndLabelsDirectConnections() async {
        let client = MockIDOSClient()
        let model = ConnectionsViewModel(client: client, calendarImporter: RecordingCalendarImporter())
        model.from = "Praha"
        model.to = "Brno"
        model.journeyOptions = [
            JourneyOptionEntry(kind: .maximumTransfers, maximumTransfers: 0),
        ]

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
        let stationSelection = PlaceFieldSelection(
            idosSelection: IDOSPlaceSelection(
                text: "Ostrava-Svinov",
                listID: "100003",
                itemID: "10288"
            ),
            kind: .train
        )
        model.stationSelection = stationSelection
        model.isArrival = true

        await model.search()

        let request = await client.lastDeparturesRequest
        XCTAssertEqual(request?.station, "Ostrava-Svinov")
        XCTAssertEqual(request?.stationSelection, stationSelection.idosSelection)
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

    func testServiceDetailLoadsItsTimetableValidityForInformationCalendars() async {
        let model = ServiceDetailViewModel(id: "service-1", client: MockIDOSClient())

        await model.load()

        XCTAssertEqual(model.timetableValidity?.validFrom, serviceDate(2025, 12, 14))
        XCTAssertEqual(model.timetableValidity?.validThrough, serviceDate(2026, 12, 12))
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

    func timetableValidity(
        for timetable: IDOSTimetable,
        language: IDOSLanguage
    ) async throws -> IDOSTimetableValidity {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Prague")!
        return IDOSTimetableValidity(
            validFrom: calendar.date(from: DateComponents(year: 2025, month: 12, day: 14))!,
            validThrough: calendar.date(from: DateComponents(year: 2026, month: 12, day: 12))!
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

private extension NSView {
    var allDescendantViews: [NSView] {
        subviews + subviews.flatMap(\.allDescendantViews)
    }
}
