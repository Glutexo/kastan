import AppKit
import Foundation
@testable import Kastan
@testable import KastanApp
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
    func testSystemSurfacesUseBundleIcon() throws {
        let bundleIcon = try XCTUnwrap(NSApplication.shared.applicationIconImage)

        XCTAssertIdentical(ApplicationArtwork.icon, bundleIcon)
        XCTAssertNil(
            NSApplication.shared.dockTile.contentView,
            "The Dock and app switcher must not override the bundle icon used by Finder"
        )
    }

    func testProductMenuActionsAppearOnlyOnce() throws {
        let mainMenu = try XCTUnwrap(NSApplication.shared.mainMenu)
        let menuItems = mainMenu.items.compactMap(\.submenu).flatMap(\.items)
        let actionKeys = [
            "Send by Email",
            "Compose in Mail",
            "Add to Calendar",
            "Download ICS File",
            "Open PDF in Preview",
            "Download PDF File",
            "Share Link",
            "Share Text",
            "Favorite timetables",
        ]

        for key in actionKeys {
            let title = AppLocalization.string(key)
            XCTAssertEqual(
                menuItems.filter { $0.title == title }.count,
                1,
                "Expected exactly one \(title) command in the application menu"
            )
        }

        for key in ["Compose in Mail", "Download ICS File", "Download PDF File", "Share Text"] {
            let alternateItem = try XCTUnwrap(
                menuItems.first { $0.title == AppLocalization.string(key) }
            )
            XCTAssertTrue(alternateItem.isAlternate)
            XCTAssertTrue(alternateItem.keyEquivalentModifierMask.contains(.option))
        }

        XCTAssertFalse(
            menuItems.contains { $0.title == AppLocalization.string("Open Link") },
            "Opening a result link belongs inside the sharing picker instead of the application menu"
        )
    }

    func testViewMenuOffersPersistentResultPresentationSettings() throws {
        let badgeTitle = AppLocalization.string("Show connection badges")
        let detailsTitle = AppLocalization.string("Show item details")
        let alternatingRowsTitle = AppLocalization.string("Show alternating row backgrounds")
        let symbolTextTitle = AppLocalization.string("Replace symbols with text")
        let menus = try XCTUnwrap(NSApplication.shared.mainMenu).items
            .compactMap(\.submenu)
            .filter { menu in
                menu.items.contains { $0.title == badgeTitle } &&
                    menu.items.contains { $0.title == detailsTitle } &&
                    menu.items.contains { $0.title == alternatingRowsTitle } &&
                    menu.items.contains { $0.title == symbolTextTitle }
            }

        XCTAssertEqual(menus.count, 1)
        let badgeItem = try XCTUnwrap(menus[0].items.first { $0.title == badgeTitle })
        let detailsItem = try XCTUnwrap(menus[0].items.first { $0.title == detailsTitle })
        let alternatingRowsItem = try XCTUnwrap(
            menus[0].items.first { $0.title == alternatingRowsTitle }
        )
        let symbolTextItem = try XCTUnwrap(
            menus[0].items.first { $0.title == symbolTextTitle }
        )
        let storedBadgeValue = UserDefaults.standard.object(
            forKey: ConnectionBadgePreference.storageKey
        ) as? Bool
        let storedDetailsValue = UserDefaults.standard.object(
            forKey: ResultItemDetailsPreference.storageKey
        ) as? Bool
        let storedAlternatingRowsValue = UserDefaults.standard.object(
            forKey: AlternatingRowBackgroundPreference.storageKey
        ) as? Bool
        let storedSymbolTextValue = UserDefaults.standard.object(
            forKey: SymbolTextPreference.storageKey
        ) as? Bool
        let badgesAreShown = storedBadgeValue ?? ConnectionBadgePreference.defaultValue
        let detailsAreShown = storedDetailsValue ?? ResultItemDetailsPreference.defaultValue
        let alternatingRowsAreShown = storedAlternatingRowsValue ??
            AlternatingRowBackgroundPreference.defaultValue
        let symbolsAreShownAsText = storedSymbolTextValue ?? SymbolTextPreference.defaultValue
        XCTAssertEqual(badgeItem.state, badgesAreShown ? .on : .off)
        XCTAssertEqual(detailsItem.state, detailsAreShown ? .on : .off)
        XCTAssertEqual(alternatingRowsItem.state, alternatingRowsAreShown ? .on : .off)
        XCTAssertEqual(symbolTextItem.state, symbolsAreShownAsText ? .on : .off)
        XCTAssertNotNil(badgeItem.image)
        XCTAssertNotNil(detailsItem.image)
        XCTAssertNotNil(alternatingRowsItem.image)
        XCTAssertNotNil(symbolTextItem.image)
        XCTAssertFalse(ConnectionBadgePreference.defaultValue)
        XCTAssertFalse(ResultItemDetailsPreference.defaultValue)
        XCTAssertTrue(AlternatingRowBackgroundPreference.defaultValue)
        XCTAssertFalse(SymbolTextPreference.defaultValue)

        let czech = try XCTUnwrap(localizationBundle(languageCode: "cs"))
        let english = try XCTUnwrap(localizationBundle(languageCode: "en"))
        XCTAssertEqual(
            [
                "Show alternating row backgrounds",
                "Show connection badges",
                "Show item details",
                "Replace symbols with text",
            ].map {
                czech.localizedString(forKey: $0, value: nil, table: nil)
            },
            [
                "Střídat barvy pozadí řádků",
                "Zobrazit štítky spojení",
                "Zobrazit podrobnosti položek",
                "Nahradit symboly textem",
            ]
        )
        XCTAssertEqual(
            [
                "Show alternating row backgrounds",
                "Show connection badges",
                "Show item details",
                "Replace symbols with text",
            ].map {
                english.localizedString(forKey: $0, value: nil, table: nil)
            },
            [
                "Show alternating row backgrounds",
                "Show connection badges",
                "Show item details",
                "Replace symbols with text",
            ]
        )
    }

    func testViewMenuOffersPersistentPlaceSuggestionSettings() throws {
        let submenuTitle = AppLocalization.string("Place suggestions")
        let optionKeys = ["Addresses", "Boroughs", "Municipalities"]
        let optionTitles = optionKeys.map { AppLocalization.string($0) }
        let menuItems = try XCTUnwrap(NSApplication.shared.mainMenu).items
            .compactMap(\.submenu)
            .flatMap(\.items)
        let submenuItem = try XCTUnwrap(menuItems.first { $0.title == submenuTitle })
        let submenu = try XCTUnwrap(submenuItem.submenu)
        let storageKeys = [
            PlaceSuggestionVisibilityPreference.addressesStorageKey,
            PlaceSuggestionVisibilityPreference.boroughsStorageKey,
            PlaceSuggestionVisibilityPreference.municipalitiesStorageKey,
        ]

        XCTAssertNotNil(submenuItem.image)
        XCTAssertEqual(submenu.items.map(\.title), optionTitles)
        for (title, storageKey) in zip(optionTitles, storageKeys) {
            let item = try XCTUnwrap(submenu.items.first { $0.title == title })
            let storedValue = UserDefaults.standard.object(forKey: storageKey) as? Bool
            XCTAssertEqual(
                item.state,
                (storedValue ?? PlaceSuggestionVisibilityPreference.defaultValue)
                    ? NSControl.StateValue.on
                    : NSControl.StateValue.off
            )
        }
        XCTAssertTrue(PlaceSuggestionVisibilityPreference.defaultValue)

        let czech = try XCTUnwrap(localizationBundle(languageCode: "cs"))
        let english = try XCTUnwrap(localizationBundle(languageCode: "en"))
        XCTAssertEqual(
            (["Place suggestions"] + optionKeys).map {
                czech.localizedString(forKey: $0, value: nil, table: nil)
            },
            ["Našeptávání míst", "Adresy", "Čtvrti", "Obce"]
        )
        XCTAssertEqual(
            (["Place suggestions"] + optionKeys).map {
                english.localizedString(forKey: $0, value: nil, table: nil)
            },
            ["Place suggestions", "Addresses", "Boroughs", "Municipalities"]
        )
    }

    func testSymbolTextPreferenceMigratesEitherLegacyChoiceWithoutOverwritingTheNewValue() throws {
        let suiteName = "KastanAppTests.SymbolTextPreference.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let legacyKeys = SymbolTextPreference.legacyStorageKeys

        for (serviceText, stopText, expected) in [
            (false, false, false),
            (true, false, true),
            (false, true, true),
            (true, true, true),
        ] {
            defaults.removeObject(forKey: SymbolTextPreference.storageKey)
            defaults.set(serviceText, forKey: legacyKeys[0])
            defaults.set(stopText, forKey: legacyKeys[1])

            SymbolTextPreference.migrateLegacyValues(in: defaults)

            XCTAssertEqual(defaults.bool(forKey: SymbolTextPreference.storageKey), expected)
        }

        defaults.set(false, forKey: SymbolTextPreference.storageKey)
        defaults.set(true, forKey: legacyKeys[0])
        defaults.set(true, forKey: legacyKeys[1])

        SymbolTextPreference.migrateLegacyValues(in: defaults)

        XCTAssertFalse(defaults.bool(forKey: SymbolTextPreference.storageKey))
    }

    func testAlternatingRowBackgroundsCanBeDisabledWithoutChangingRowOrder() {
        XCTAssertEqual(
            AlternatingRowBackgroundPresentation.menuSystemImage,
            "rectangle.split.1x2"
        )
        XCTAssertNotNil(
            NSImage(
                systemSymbolName: AlternatingRowBackgroundPresentation.menuSystemImage,
                accessibilityDescription: nil
            )
        )
        XCTAssertEqual(
            (0..<4).map {
                AlternatingRowBackgroundPresentation.isTinted(rowAt: $0, isEnabled: true)
            },
            [false, true, false, true]
        )
        XCTAssertFalse(
            (0..<4).contains {
                AlternatingRowBackgroundPresentation.isTinted(rowAt: $0, isEnabled: false)
            }
        )
    }

    func testEditMenuSeparatesFillCurrentFromRouteSwapping() throws {
        let mainMenu = try XCTUnwrap(NSApplication.shared.mainMenu)
        let fillCurrentTitle = AppLocalization.string("Fill Current")
        let swapTitle = AppLocalization.string("Swap From and To")
        XCTAssertFalse(mainMenu.items.contains { $0.title == fillCurrentTitle })

        let editMenu = try XCTUnwrap(
            mainMenu.items.compactMap(\.submenu).first { menu in
                menu.items.contains { $0.title == fillCurrentTitle }
            }
        )
        XCTAssertTrue(
            editMenu.items.contains { $0.action == Selector(("paste:")) },
            "Search commands must live in the standard Edit menu"
        )
        let fillCurrentItem = try XCTUnwrap(
            editMenu.items.first { $0.title == fillCurrentTitle }
        )
        let fillCurrentMenu = try XCTUnwrap(fillCurrentItem.submenu)
        let requestedTitles = [
            "From Place",
            "To Place",
            "|",
            "Date and time",
            "Date",
            "Time",
        ].map { key in
            key == "|" ? key : AppLocalization.string(key)
        }

        XCTAssertEqual(
            fillCurrentMenu.items.map { item in item.isSeparatorItem ? "|" : item.title },
            requestedTitles
        )
        XCTAssertFalse(fillCurrentMenu.items.contains { $0.title == swapTitle })

        let fillCurrentIndex = try XCTUnwrap(editMenu.items.firstIndex { $0 === fillCurrentItem })
        XCTAssertGreaterThanOrEqual(fillCurrentIndex, 2)
        XCTAssertTrue(editMenu.items[fillCurrentIndex - 1].isSeparatorItem)
        XCTAssertEqual(editMenu.items[fillCurrentIndex - 2].action, Selector(("selectAll:")))

        let swapIndex = try XCTUnwrap(editMenu.items.firstIndex { $0.title == swapTitle })
        XCTAssertEqual(swapIndex, fillCurrentIndex + 1)
        XCTAssertNil(editMenu.items[swapIndex].submenu)

        XCTAssertEqual(FillCurrentAction.placeActions, [.fromPlace, .toPlace])
        XCTAssertEqual(FillCurrentAction.temporalActions, [.dateAndTime, .date, .time])
        XCTAssertEqual(
            FillCurrentAction.supportedActions(for: .connections),
            Set(FillCurrentAction.allCases)
        )
        XCTAssertEqual(
            FillCurrentAction.supportedActions(for: .departures),
            Set(FillCurrentAction.temporalActions)
        )
        XCTAssertEqual(FillCurrentAction.supportedActions(for: .stationTimetables), [.date])

        let czech = try XCTUnwrap(localizationBundle(languageCode: "cs"))
        XCTAssertEqual(
            ["Fill Current", "From Place", "To Place", "Swap From and To"].map {
                czech.localizedString(forKey: $0, value: nil, table: nil)
            },
            ["Vyplnit aktuální", "Místo odkud", "Místo kam", "Prohodit odkud a kam"]
        )
    }

    func testFavoriteTimetablesWindowCommandUsesAnIcon() throws {
        let title = AppLocalization.string("Favorite timetables")
        let command = try XCTUnwrap(
            NSApplication.shared.windowsMenu?.items.first { $0.title == title }
        )

        XCTAssertNotNil(command.image)
    }

    func testResultDetailMenuActionsStayInOneGroup() throws {
        let expectedTitles = [
            "Send by Email",
            "Compose in Mail",
            "Add to Calendar",
            "Download ICS File",
            "Open PDF in Preview",
            "Download PDF File",
            "Share Link",
            "Share Text",
        ].map { AppLocalization.string($0) }
        let fileMenu = try XCTUnwrap(
            NSApplication.shared.mainMenu?.items
                .compactMap(\.submenu)
                .first { menu in menu.items.contains { $0.title == expectedTitles[0] } }
        )
        let firstActionIndex = try XCTUnwrap(
            fileMenu.items.firstIndex { $0.title == expectedTitles[0] }
        )

        XCTAssertEqual(
            Array(fileMenu.items.dropFirst(firstActionIndex).prefix(expectedTitles.count).map(\.title)),
            expectedTitles
        )
    }

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

    func testNewTabOpensAWindowWhenThereIsNoActiveWindowToAttachTo() {
        var openCount = 0

        AppWindowActions.newTab(sourceWindow: nil) {
            openCount += 1
        }

        XCTAssertEqual(openCount, 1)
    }

    func testFileMenuOffersDirectCreationCommandsAndOptionOnlyMockAlternatesWithOneRegularSource() async throws {
        // SwiftUI assembles commands from every declared scene after the app finishes launching.
        try await Task.sleep(for: .milliseconds(250))

        let newWindowTitle = AppLocalization.string("New Window")
        let newTabTitle = AppLocalization.string("New Tab")
        let newMockWindowTitle = AppLocalization.string("New Mock Window")
        let newMockTabTitle = AppLocalization.string("New Mock Tab")
        let fileMenu = try XCTUnwrap(
            NSApplication.shared.mainMenu?.items
                .compactMap(\.submenu)
                .first { menu in menu.items.contains { $0.title == newTabTitle } }
        )
        let newWindowItems = fileMenu.items.filter { $0.title == newWindowTitle }
        let newWindowItem = try XCTUnwrap(newWindowItems.first)

        XCTAssertEqual(newWindowItems.count, 1)
        XCTAssertNil(
            newWindowItem.submenu,
            "New Window must be a direct command rather than a submenu of internal scenes"
        )
        XCTAssertEqual(newWindowItem.keyEquivalent, "n")
        XCTAssertTrue(newWindowItem.keyEquivalentModifierMask.contains(.command))
        XCTAssertFalse(newWindowItem.keyEquivalentModifierMask.contains(.option))
        XCTAssertFalse(newWindowItem.keyEquivalentModifierMask.contains(.shift))
        XCTAssertFalse(newWindowItem.keyEquivalentModifierMask.contains(.control))

        let newTabItem = try XCTUnwrap(fileMenu.items.first { $0.title == newTabTitle })
        XCTAssertNil(newTabItem.submenu)
        XCTAssertEqual(newTabItem.keyEquivalent, "t")
        XCTAssertTrue(newTabItem.keyEquivalentModifierMask.contains(.command))
        XCTAssertFalse(newTabItem.keyEquivalentModifierMask.contains(.option))

        for (title, shortcut) in [(newMockWindowTitle, "n"), (newMockTabTitle, "t")] {
            let alternate = try XCTUnwrap(fileMenu.items.first { $0.title == title })
            XCTAssertTrue(alternate.isAlternate)
            XCTAssertEqual(alternate.keyEquivalent, shortcut)
            XCTAssertTrue(alternate.keyEquivalentModifierMask.contains(.command))
            XCTAssertTrue(alternate.keyEquivalentModifierMask.contains(.option))
        }

        let czech = try XCTUnwrap(localizationBundle(languageCode: "cs"))
        let english = try XCTUnwrap(localizationBundle(languageCode: "en"))
        XCTAssertEqual(
            czech.localizedString(forKey: "New Window", value: nil, table: nil),
            "Nové okno"
        )
        XCTAssertEqual(
            english.localizedString(forKey: "New Window", value: nil, table: nil),
            "New Window"
        )
        XCTAssertEqual(
            czech.localizedString(forKey: "New Mock Window", value: nil, table: nil),
            "Nové mockové okno"
        )
        XCTAssertEqual(
            english.localizedString(forKey: "New Mock Tab", value: nil, table: nil),
            "New Mock Tab"
        )
    }

    func testNestedProviderMenusKeepMockChoicesAsOptionAlternates() {
        let mainMenu = NSMenu(title: "Main")
        let fileMenu = NSMenu(title: "File")
        let fileItem = NSMenuItem(title: "File", action: nil, keyEquivalent: "")
        fileItem.submenu = fileMenu
        mainMenu.addItem(fileItem)

        let newWindowMenu = NSMenu(title: "New Window")
        let newWindowItem = NSMenuItem(title: "New Window", action: nil, keyEquivalent: "")
        newWindowItem.submenu = newWindowMenu
        fileMenu.addItem(newWindowItem)

        let regular = NSMenuItem(title: "IDOS", action: nil, keyEquivalent: "n")
        regular.keyEquivalentModifierMask = [.command]
        let mock = NSMenuItem(title: "Kaštan Mock", action: nil, keyEquivalent: "n")
        mock.keyEquivalentModifierMask = [.command]
        newWindowMenu.addItem(regular)
        newWindowMenu.addItem(mock)

        XCTAssertTrue(ApplicationMainMenu.menu(newWindowMenu, belongsTo: mainMenu))
        ApplicationMainMenu.configureMockDataSourceAlternates(
            in: fileMenu,
            mockDataSourceDisplayName: "Kaštan Mock"
        )

        XCTAssertFalse(regular.isAlternate)
        XCTAssertTrue(mock.isAlternate)
        XCTAssertTrue(mock.keyEquivalentModifierMask.contains(.command))
        XCTAssertTrue(mock.keyEquivalentModifierMask.contains(.option))
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

    func testDoesNotRunRangesCanEachBeRestrictedToNumberedWeekdays() throws {
        let serviceCalendar = try XCTUnwrap(StationTimetableServiceCalendar(
            note: "nejede od 22. do 29.VII. v 2,3,30.VII.,od 10. do 17.VIII. v 1,6,7,18.,19.,28.VIII.,10.IX.",
            validityStart: serviceDate(2025, 12, 14),
            validityEnd: serviceDate(2027, 1, 14)
        ))

        XCTAssertEqual(serviceCalendar.rule.nonRunningConditions, [
            .selectedDays(
                weekdays: Set([2, 3]),
                includesSundaysAndPublicHolidays: false,
                within: serviceDate(2026, 7, 22)...serviceDate(2026, 7, 29)
            ),
            .dates(serviceDate(2026, 7, 30)...serviceDate(2026, 7, 30)),
            .selectedDays(
                weekdays: Set([1, 6, 7]),
                includesSundaysAndPublicHolidays: false,
                within: serviceDate(2026, 8, 10)...serviceDate(2026, 8, 17)
            ),
            .dates(serviceDate(2026, 8, 18)...serviceDate(2026, 8, 18)),
            .dates(serviceDate(2026, 8, 19)...serviceDate(2026, 8, 19)),
            .dates(serviceDate(2026, 8, 28)...serviceDate(2026, 8, 28)),
            .dates(serviceDate(2026, 9, 10)...serviceDate(2026, 9, 10)),
        ])
        XCTAssertEqual(serviceCalendar.status(on: serviceDate(2026, 7, 22)), .doesNotRun)
        XCTAssertEqual(serviceCalendar.status(on: serviceDate(2026, 7, 23)), .runs)
        XCTAssertEqual(serviceCalendar.status(on: serviceDate(2026, 7, 28)), .doesNotRun)
        XCTAssertEqual(serviceCalendar.status(on: serviceDate(2026, 7, 29)), .doesNotRun)
        XCTAssertEqual(serviceCalendar.status(on: serviceDate(2026, 7, 30)), .doesNotRun)
        XCTAssertEqual(serviceCalendar.status(on: serviceDate(2026, 7, 31)), .runs)
        XCTAssertEqual(serviceCalendar.status(on: serviceDate(2026, 8, 10)), .doesNotRun)
        XCTAssertEqual(serviceCalendar.status(on: serviceDate(2026, 8, 11)), .runs)
        XCTAssertEqual(serviceCalendar.status(on: serviceDate(2026, 8, 15)), .doesNotRun)
        XCTAssertEqual(serviceCalendar.status(on: serviceDate(2026, 8, 16)), .doesNotRun)
        XCTAssertEqual(serviceCalendar.status(on: serviceDate(2026, 8, 17)), .doesNotRun)
        XCTAssertEqual(serviceCalendar.status(on: serviceDate(2026, 8, 18)), .doesNotRun)
        XCTAssertEqual(serviceCalendar.status(on: serviceDate(2026, 8, 19)), .doesNotRun)
        XCTAssertEqual(serviceCalendar.status(on: serviceDate(2026, 8, 28)), .doesNotRun)
        XCTAssertEqual(serviceCalendar.status(on: serviceDate(2026, 9, 10)), .doesNotRun)
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

    func testSaturdaySundayAndPublicHolidayRuleCombinesWithNonRunningRange() throws {
        let serviceCalendar = try XCTUnwrap(StationTimetableServiceCalendar(
            note: "jede v 6,+,nejede od 10.VIII. do 4.IX.",
            validityStart: serviceDate(2025, 12, 14),
            validityEnd: serviceDate(2026, 12, 12)
        ))

        XCTAssertEqual(
            serviceCalendar.rule.recurrence,
            .selectedDays(weekdays: Set([6]), includesSundaysAndPublicHolidays: true)
        )
        XCTAssertEqual(
            serviceCalendar.rule.nonRunningRanges,
            [serviceDate(2026, 8, 10)...serviceDate(2026, 9, 4)]
        )
        XCTAssertEqual(serviceCalendar.status(on: serviceDate(2026, 8, 8)), .runs)
        XCTAssertEqual(serviceCalendar.status(on: serviceDate(2026, 8, 9)), .runs)
        XCTAssertEqual(serviceCalendar.status(on: serviceDate(2026, 8, 15)), .doesNotRun)
        XCTAssertEqual(serviceCalendar.status(on: serviceDate(2026, 8, 16)), .doesNotRun)
        XCTAssertEqual(serviceCalendar.status(on: serviceDate(2026, 9, 5)), .runs)
        XCTAssertEqual(serviceCalendar.status(on: serviceDate(2026, 9, 6)), .runs)
        XCTAssertEqual(serviceCalendar.status(on: serviceDate(2026, 9, 7)), .doesNotRun)
        XCTAssertEqual(serviceCalendar.status(on: serviceDate(2026, 9, 28)), .runs)
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

    func testOneSidedRangeExpandsAlongsideIndividualDateExceptions() throws {
        let validityEnd = serviceDate(2026, 12, 12)
        let serviceCalendar = try XCTUnwrap(StationTimetableServiceCalendar(
            note: "nejede 1.,9.,18.VIII. a od 2.X.",
            validityStart: serviceDate(2025, 12, 14),
            validityEnd: validityEnd
        ))

        XCTAssertEqual(serviceCalendar.rule.nonRunningRanges, [
            serviceDate(2026, 8, 1)...serviceDate(2026, 8, 1),
            serviceDate(2026, 8, 9)...serviceDate(2026, 8, 9),
            serviceDate(2026, 8, 18)...serviceDate(2026, 8, 18),
            serviceDate(2026, 10, 2)...validityEnd,
        ])
        XCTAssertEqual(serviceCalendar.status(on: serviceDate(2026, 8, 1)), .doesNotRun)
        XCTAssertEqual(serviceCalendar.status(on: serviceDate(2026, 8, 2)), .runs)
        XCTAssertEqual(serviceCalendar.status(on: serviceDate(2026, 10, 1)), .runs)
        XCTAssertEqual(serviceCalendar.status(on: serviceDate(2026, 10, 2)), .doesNotRun)
        XCTAssertEqual(serviceCalendar.status(on: validityEnd), .doesNotRun)
    }

    func testRunsUntilRangeIsRestrictedToNumberedWeekendDays() throws {
        let validityStart = serviceDate(2025, 12, 14)
        let serviceCalendar = try XCTUnwrap(StationTimetableServiceCalendar(
            note: "jede do 29.VIII. v 6,7",
            validityStart: validityStart,
            validityEnd: serviceDate(2026, 12, 12)
        ))

        XCTAssertEqual(
            serviceCalendar.rule.recurrence,
            .selectedDays(weekdays: Set([6, 7]), includesSundaysAndPublicHolidays: false)
        )
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

        XCTAssertEqual(
            serviceCalendar.rule.recurrence,
            .selectedDays(weekdays: Set(1...6), includesSundaysAndPublicHolidays: false)
        )
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

        XCTAssertEqual(
            serviceCalendar.rule.recurrence,
            .selectedDays(weekdays: Set(1...6), includesSundaysAndPublicHolidays: false)
        )
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
        XCTAssertEqual(
            serviceCalendar.rule.recurrence,
            .selectedDays(
                weekdays: Set([1, 2, 3, 4, 5, 7]),
                includesSundaysAndPublicHolidays: false
            )
        )
        XCTAssertTrue(serviceCalendar.listedDates.isEmpty)
        let destination = ServiceNotesView.calendarDestination(for: 0)
        let linkedContent = ServiceCalendarLink.noteApplicabilityContent(
            for: serviceCalendar,
            destination: destination
        )
        let linkedRuns = linkedContent.runs.filter { $0.link != nil }
        XCTAssertEqual(String(linkedContent.characters), serviceCalendar.note)
        XCTAssertEqual(linkedRuns.count, 1)
        XCTAssertEqual(String(linkedContent[linkedRuns[0].range].characters), "v 1-5,7")
        XCTAssertEqual(linkedRuns[0].link, destination)
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

    func testExactIDOSOperatingDaysOverrideTheInterpretedServiceNote() throws {
        let dateLimits = IDOSServiceDateLimits(
            referenceDate: idosServiceDate(2026, 7, 18),
            days: [
                .init(date: idosServiceDate(2026, 7, 18), status: .doesNotRun),
                .init(date: idosServiceDate(2026, 7, 19), status: .informationUnavailable),
                .init(date: idosServiceDate(2026, 7, 20), status: .runs),
            ]
        )
        let serviceCalendar = try XCTUnwrap(StationTimetableServiceCalendar(
            note: "jede 19.VII.",
            validityStart: idosServiceDate(2026, 7, 1),
            validityEnd: idosServiceDate(2026, 7, 31),
            dateLimits: dateLimits
        ))

        XCTAssertTrue(serviceCalendar.usesExactOperatingDays)
        XCTAssertEqual(serviceCalendar.calendarStart, idosServiceDate(2026, 7, 18))
        XCTAssertEqual(serviceCalendar.calendarEnd, idosServiceDate(2026, 7, 20))
        XCTAssertEqual(serviceCalendar.status(on: idosServiceDate(2026, 7, 18)), .doesNotRun)
        XCTAssertEqual(
            serviceCalendar.status(on: idosServiceDate(2026, 7, 19)),
            .informationUnavailable
        )
        XCTAssertEqual(serviceCalendar.status(on: idosServiceDate(2026, 7, 20)), .runs)
    }

    func testExactOperatingDaysUseTheProviderCivilTimeZone() throws {
        let providerTimeZone = try XCTUnwrap(TimeZone(identifier: "America/Los_Angeles"))
        var providerCalendar = Calendar(identifier: .gregorian)
        providerCalendar.timeZone = providerTimeZone
        let providerDate = try XCTUnwrap(providerCalendar.date(from: DateComponents(
            year: 2026,
            month: 9,
            day: 7,
            hour: 23
        )))
        let limits = TransitServiceDateLimits(
            referenceDate: providerDate,
            days: [.init(date: providerDate, status: .runs)],
            timeZone: providerTimeZone
        )
        let validityStart = try XCTUnwrap(
            providerCalendar.date(byAdding: .day, value: -7, to: providerDate)
        )
        let validityEnd = try XCTUnwrap(
            providerCalendar.date(byAdding: .day, value: 7, to: providerDate)
        )
        let serviceCalendar = try XCTUnwrap(StationTimetableServiceCalendar(
            note: "jede 7.IX.",
            validityStart: validityStart,
            validityEnd: validityEnd,
            dateLimits: limits,
            timeZone: try XCTUnwrap(TimeZone(identifier: "Asia/Tokyo"))
        ))

        XCTAssertEqual(serviceCalendar.calendar.timeZone.identifier, providerTimeZone.identifier)
        XCTAssertEqual(serviceCalendar.status(on: providerDate), .runs)
    }

    func testExactServiceDaysDoNotReplaceASeparateNoteApplicabilityRule() throws {
        let dateLimits = IDOSServiceDateLimits(
            referenceDate: serviceDate(2026, 7, 25),
            days: [.init(date: serviceDate(2026, 7, 25), status: .runs)]
        )
        let noteCalendar = try XCTUnwrap(StationTimetableServiceCalendar(
            note: "občerstvení v 1-5",
            validityStart: serviceDate(2026, 7, 1),
            validityEnd: serviceDate(2026, 7, 31),
            dateLimits: dateLimits
        ))

        XCTAssertFalse(noteCalendar.usesExactOperatingDays)
        XCTAssertEqual(noteCalendar.rule.subject, .noteApplicability)
        XCTAssertEqual(noteCalendar.status(on: serviceDate(2026, 7, 25)), .doesNotRun)
    }

    func testServiceDetailNotesDoNotInferOperatingDaysWhenExactIDOSDataIsAbsent() {
        let note = "jede 19.VII."
        let validity = IDOSTimetableValidity(
            validFrom: serviceDate(2026, 7, 1),
            validThrough: serviceDate(2026, 7, 31)
        )
        let withoutExactData = ServiceNotesView(
            notes: [note],
            timetableValidity: validity,
            requiresExactServiceOperatingDays: true
        )
        let dateLimits = IDOSServiceDateLimits(
            referenceDate: serviceDate(2026, 7, 19),
            days: [.init(date: serviceDate(2026, 7, 19), status: .runs)]
        )
        let withExactData = ServiceNotesView(
            notes: [note],
            timetableValidity: validity,
            serviceDateLimits: dateLimits,
            requiresExactServiceOperatingDays: true
        )
        let destination = ServiceNotesView.calendarDestination(for: 0)

        XCTAssertFalse(withoutExactData.linkedContent.runs.compactMap(\.link).contains(destination))
        XCTAssertTrue(withExactData.linkedContent.runs.compactMap(\.link).contains(destination))
    }

    func testStructuredProviderOperatingCalendarDoesNotRequireIDOSWording() {
        let information = TransitServiceInformation(
            text: "Operating dates",
            category: .operatingCalendar
        )
        let dateLimits = TransitServiceDateLimits(
            referenceDate: serviceDate(2026, 7, 19),
            days: [.init(date: serviceDate(2026, 7, 19), status: .runs)]
        )
        let validity = TransitTimetableValidity(
            validFrom: serviceDate(2026, 7, 1),
            validThrough: serviceDate(2026, 7, 31)
        )
        let notes = ServiceNotesView(
            notes: [information.text],
            serviceInformation: [information],
            timetableValidity: validity,
            serviceDateLimits: dateLimits,
            requiresExactServiceOperatingDays: true
        )

        XCTAssertTrue(
            notes.linkedContent.runs.compactMap(\.link).contains(
                ServiceNotesView.calendarDestination(for: 0)
            )
        )
    }

    func testStructuredProviderOperatingCalendarUsesExactDatesWithoutTimetableValidity() {
        let information = TransitServiceInformation(
            text: "Operating dates",
            category: .operatingCalendar
        )
        let dateLimits = TransitServiceDateLimits(
            referenceDate: serviceDate(2026, 7, 19),
            days: [.init(date: serviceDate(2026, 7, 19), status: .runs)]
        )
        let notes = ServiceNotesView(
            notes: [information.text],
            serviceInformation: [information],
            serviceDateLimits: dateLimits,
            requiresExactServiceOperatingDays: true
        )

        XCTAssertTrue(
            notes.linkedContent.runs.compactMap(\.link).contains(
                ServiceNotesView.calendarDestination(for: 0)
            )
        )
    }

    func testOptionClickRequestsRecognizedCalendarConditions() {
        XCTAssertTrue(ServiceCalendarOpeningOptions.showsRecognizedConditions(for: [.option]))
        XCTAssertTrue(ServiceCalendarOpeningOptions.showsRecognizedConditions(for: [.option, .shift]))
        XCTAssertFalse(ServiceCalendarOpeningOptions.showsRecognizedConditions(for: []))
        XCTAssertFalse(ServiceCalendarOpeningOptions.showsRecognizedConditions(for: [.command]))
    }

    func testServiceNotesCombineRowsIntoOneSelectableTextFlow() throws {
        let notes = [
            "Na trase spojení je toto plánované omezení provozu.",
            "Háje - Letňany",
            "A: vynechá zastávky Místek,Frýdlantská, Místek,Riviéra a Místek,Beskydská",
            "Dopravní podnik hl. m. Prahy, a.s.",
        ]
        let content = ServiceNotesView(notes: notes).linkedContent

        XCTAssertEqual(
            String(content.characters),
            "🚧 \(notes[0])\n🛤️ \(notes[1])\n🛤️ \(notes[2])\n🏢 \(notes[3])"
        )
        for index in notes.indices {
            let destination = ServiceInformationRuleLink.destination(for: index)
            let symbolRun = try XCTUnwrap(content.runs.first { $0.link == destination })
            XCTAssertEqual(
                String(content[symbolRun.range].characters),
                IDOSServiceInformation(text: notes[index]).symbol
            )
            XCTAssertEqual(ServiceInformationRuleLink.noteIndex(from: destination), index)
        }
        XCTAssertTrue(ServiceInformationRuleLink.shouldOpen(for: [.option]))
        XCTAssertTrue(ServiceInformationRuleLink.shouldOpen(for: [.option, .shift]))
        XCTAssertFalse(ServiceInformationRuleLink.shouldOpen(for: []))
        XCTAssertFalse(ServiceInformationRuleLink.shouldOpen(for: [.command]))
        XCTAssertEqual(ServiceNotesView.informationLineSpacing, 8)
    }

    func testServiceNotesRetainAnExactStructuredProviderCategory() {
        let information = TransitServiceInformation(
            text: "Bistro car",
            category: .wheelchair
        )
        let content = ServiceNotesView(
            notes: [information.text],
            serviceInformation: [information]
        ).linkedContent

        XCTAssertEqual(String(content.characters), "\(information.symbol) \(information.text)")
        XCTAssertNotEqual(information.symbol, TransitServiceInformation(text: information.text).symbol)
    }

    func testServiceInformationStaysHiddenUntilDisclosureExpands() throws {
        let note = "Wi-Fi connection is available on board."
        func renderedHeight(isExpanded: Bool) -> CGFloat {
            let hostingView = NSHostingView(
                rootView: ServiceInformationDisclosure(
                    notes: [note],
                    isExpanded: .constant(isExpanded)
                )
                .frame(width: 400, alignment: .topLeading)
            )
            hostingView.layoutSubtreeIfNeeded()
            return hostingView.fittingSize.height
        }

        let collapsedHeight = renderedHeight(isExpanded: false)
        let expandedHeight = renderedHeight(isExpanded: true)
        XCTAssertGreaterThan(expandedHeight, collapsedHeight)

        var isExpanded = false
        let disclosure = ServiceInformationDisclosure(
            notes: [note],
            isExpanded: Binding(
                get: { isExpanded },
                set: { isExpanded = $0 }
            )
        )
            .frame(width: 400, height: 28, alignment: .leading)
        let hostingView = NSHostingView(rootView: disclosure)
        hostingView.frame = NSRect(x: 0, y: 0, width: 400, height: 28)
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

        for eventType in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            let event = NSEvent.mouseEvent(
                with: eventType,
                location: NSPoint(x: 200, y: hostingView.bounds.midY),
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

        XCTAssertTrue(isExpanded)
    }

    func testStationTimetableRemarkDisclosuresStayHiddenUntilExpanded() {
        let note = "jede v pracovní dny"
        func renderedHeight(title: LocalizedStringKey, isExpanded: Bool) -> CGFloat {
            let hostingView = NSHostingView(
                rootView: StationTimetableRemarksDisclosure(
                    title: title,
                    systemImage: "info.circle",
                    values: [note],
                    calendarContext: [note],
                    isExpanded: .constant(isExpanded)
                )
                .frame(width: 400, alignment: .topLeading)
            )
            hostingView.layoutSubtreeIfNeeded()
            return hostingView.fittingSize.height
        }

        for title in [LocalizedStringKey("Notes"), LocalizedStringKey("Explanations")] {
            let collapsedHeight = renderedHeight(title: title, isExpanded: false)
            let expandedHeight = renderedHeight(title: title, isExpanded: true)

            XCTAssertGreaterThan(expandedHeight, collapsedHeight)
        }
    }

    func testSeparatedExplanationRetainsTimetableNoteCalendarContext() {
        let explanation = "A: jede 19.VII."
        let view = ServiceNotesView(
            notes: [explanation],
            calendarContext: ["platí od 1.7.2026 do 26.7.2026", explanation]
        )

        XCTAssertTrue(
            view.linkedContent.runs.compactMap(\.link).contains(
                ServiceNotesView.calendarDestination(for: 0)
            )
        )
    }

    func testStationTimetableDepartureMarkersExplainTheirMinutes() {
        let marked = StationTimetableDeparturePresentation(
            value: "16AB",
            explanations: [
                "A: jede jen do zastávky Háje",
                "B: nejede o prázdninách",
                "platí od 1.7.2026",
            ]
        )
        let unmarked = StationTimetableDeparturePresentation(
            value: "47",
            explanations: ["A: jede jen do zastávky Háje"]
        )

        XCTAssertEqual(marked.minute, "16")
        XCTAssertEqual(marked.marker, "AB")
        XCTAssertEqual(
            marked.explanation,
            "A: jede jen do zastávky Háje\nB: nejede o prázdninách"
        )
        XCTAssertEqual(unmarked.minute, "47")
        XCTAssertNil(unmarked.marker)
        XCTAssertNil(unmarked.explanation)
    }

    func testStationTimetableDepartureReferenceDoesNotInterpretProviderDisplayText() throws {
        let schedule = IDOSStationTimetableSchedule(
            label: "market days",
            hours: [IDOSStationTimetableHour(hour: "morning", departures: ["quarter past"])]
        )
        let reference = try XCTUnwrap(StationTimetableDepartureReference(
            scheduleIndex: 0,
            schedule: schedule,
            hourIndex: 0,
            departureIndex: 0
        ))

        XCTAssertEqual(reference.scheduleIndex, 0)
        XCTAssertEqual(reference.hourIndex, 0)
        XCTAssertEqual(reference.departureIndex, 0)
        XCTAssertEqual(reference.value, "quarter past")
    }

    func testResolvedSemanticDateAndTimePreserveTheSelectedDateAcrossTimeZones() throws {
        var tokyoCalendar = Calendar(identifier: .gregorian)
        tokyoCalendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Tokyo"))
        let serviceDate = TransitDate(year: 2026, month: 8, day: 31)
        let displayedDateAndTime = try XCTUnwrap(serviceDate.date(
            in: tokyoCalendar,
            at: TransitTime(hour: 5, minute: 13)
        ))
        let displayedComponents = tokyoCalendar.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: displayedDateAndTime
        )
        XCTAssertEqual(displayedComponents.year, 2026)
        XCTAssertEqual(displayedComponents.month, 8)
        XCTAssertEqual(displayedComponents.day, 31)
        XCTAssertEqual(displayedComponents.hour, 5)
        XCTAssertEqual(displayedComponents.minute, 13)
    }

    func testStationTimetableTimesBecomeButtonsWhenTheyCanOpenServices() {
        var selectedIndex: Int?
        let departures = StationTimetableDepartureTimes(
            values: ["13", "35A"],
            explanations: ["A: runs only to stop Háje"],
            hour: "5",
            selectDeparture: { selectedIndex = $0 }
        )
        let hostingView = NSHostingView(
            rootView: departures.frame(width: 90, height: 30, alignment: .topLeading)
        )
        hostingView.frame = NSRect(x: 0, y: 0, width: 90, height: 30)
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

        let secondDeparture = NSPoint(x: 60, y: hostingView.bounds.midY)
        for eventType in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            let event = NSEvent.mouseEvent(
                with: eventType,
                location: secondDeparture,
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

        XCTAssertEqual(selectedIndex, 1)
    }

    func testOptionClickingStationTimetableTimeRequestsItsDepartureSearch() throws {
        var searchedIndex: Int?
        let departures = StationTimetableDepartureTimes(
            values: ["13", "35A"],
            explanations: ["A: runs only to stop Háje"],
            hour: "5",
            selectDeparture: { _ in XCTFail("Option-click must not perform the ordinary action.") },
            searchDeparture: { searchedIndex = $0 }
        )
        let hostingView = NSHostingView(
            rootView: departures.frame(width: 90, height: 30, alignment: .topLeading)
        )
        hostingView.frame = NSRect(x: 0, y: 0, width: 90, height: 30)
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

        let clickViews = hostingView.allDescendantViews.compactMap {
            $0 as? OptionClickCaptureView
        }
        XCTAssertEqual(clickViews.count, 2)
        let firstClickView = try XCTUnwrap(clickViews.min { lhs, rhs in
            hostingView.convert(lhs.bounds, from: lhs).midX <
                hostingView.convert(rhs.bounds, from: rhs).midX
        })
        let optionClick = try XCTUnwrap(NSEvent.mouseEvent(
            with: .leftMouseDown,
            location: firstClickView.convert(
                NSPoint(x: firstClickView.bounds.midX, y: firstClickView.bounds.midY),
                to: nil
            ),
            modifierFlags: [.option],
            timestamp: 0,
            windowNumber: window.windowNumber,
            context: nil,
            eventNumber: 1,
            clickCount: 1,
            pressure: 1
        ))

        XCTAssertNil(firstClickView.process(optionClick))
        XCTAssertEqual(searchedIndex, 0)

        let czech = try XCTUnwrap(localizationBundle(languageCode: "cs"))
        XCTAssertEqual(
            czech.localizedString(
                forKey: "Hold Option and click to find this service in Departures.",
                value: nil,
                table: nil
            ),
            "Podržte Option a kliknutím vyhledejte tento spoj v Odjezdech."
        )
    }

    func testClickableStationTimetableMinuteKeepsItsPlainAppearance() throws {
        func renderedDeparture(selectDeparture: ((Int) -> Void)?) throws -> Data {
            let departures = StationTimetableDepartureTimes(
                values: ["23A"],
                explanations: ["A: runs only to stop Háje"],
                hour: "5",
                selectDeparture: selectDeparture
            )
            .frame(width: 45, height: 24, alignment: .topLeading)
            .background(Color.white)
            .environment(\.colorScheme, .light)
            let hostingView = NSHostingView(rootView: departures)
            hostingView.frame = NSRect(x: 0, y: 0, width: 45, height: 24)
            hostingView.layoutSubtreeIfNeeded()

            let bitmap = try XCTUnwrap(
                hostingView.bitmapImageRepForCachingDisplay(in: hostingView.bounds)
            )
            hostingView.cacheDisplay(in: hostingView.bounds, to: bitmap)
            let bitmapData = try XCTUnwrap(bitmap.bitmapData)
            return Data(bytes: bitmapData, count: bitmap.bytesPerRow * bitmap.pixelsHigh)
        }

        let plainDeparture = try renderedDeparture(selectDeparture: nil)
        let clickableDeparture = try renderedDeparture(selectDeparture: { _ in })

        XCTAssertEqual(clickableDeparture, plainDeparture)
    }

    func testStationTimetableTimesRegisterForceClickPreviewsForResolvableServices() async throws {
        let client = MockIDOSClient()
        let departures = StationTimetableDepartureTimes(
            values: ["13", "35A"],
            explanations: ["A: runs only to stop Háje"],
            hour: "5",
            selectDeparture: { _ in },
            previewDeparture: { index in
                StationTimetableDeparturePreviewConfiguration(
                    client: client,
                    showsItemDetails: true,
                    showsStopNoteText: false,
                    resolveSelection: { ServiceSelection(id: "service-\(index)") }
                )
            }
        )
        let hostingView = NSHostingView(
            rootView: departures.frame(width: 90, height: 30, alignment: .topLeading)
        )
        hostingView.frame = NSRect(x: 0, y: 0, width: 90, height: 30)
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

        XCTAssertEqual(forceClickPreviewAttachmentCount(in: hostingView), 2)
        XCTAssertEqual(
            ResultPreviewLayout.serviceSize,
            CGSize(width: 400, height: 560)
        )
        let secondPreview = try XCTUnwrap(departures.previewDeparture?(1))
        let selection = await secondPreview.resolveSelection()
        XCTAssertEqual(
            selection?.id,
            AppTransitValueIdentity(
                dataSourceID: .idos,
                timetableIdentifier: TransitTimetable.defaultTimetable.identifier,
                valueIdentifier: "service-1"
            )
        )
        XCTAssertTrue(secondPreview.showsItemDetails)
        XCTAssertFalse(secondPreview.showsStopNoteText)
    }

    func testStationTimetableDepartureMarkersStayAttachedWhenTimesWrap() {
        let values = ["05A", "15B", "25C", "35A", "45B", "55C"]
        let explanations = ["A: první", "B: druhá", "C: třetí"]
        let departures = StationTimetableDepartureTimes(
            values: values,
            explanations: explanations
        )

        XCTAssertEqual(
            departures.presentations.map(\.minute),
            ["05", "15", "25", "35", "45", "55"]
        )
        XCTAssertEqual(
            departures.presentations.compactMap(\.marker),
            ["A", "B", "C", "A", "B", "C"]
        )

        let wide = NSHostingView(rootView: departures.frame(width: 280, alignment: .leading))
        let narrow = NSHostingView(rootView: departures.frame(width: 80, alignment: .leading))
        wide.layoutSubtreeIfNeeded()
        narrow.layoutSubtreeIfNeeded()

        XCTAssertGreaterThan(narrow.fittingSize.height, wide.fittingSize.height)
    }

    func testStationTimetableDepartureColumnsStayAlignedWithMarkers() {
        func renderedWidth(values: [String]) -> CGFloat {
            let departures = StationTimetableDepartureTimes(
                values: values,
                explanations: ["A: první", "BC: druhá"]
            )
            let hostingView = NSHostingView(rootView: departures)
            hostingView.layoutSubtreeIfNeeded()
            return hostingView.fittingSize.width
        }

        let expectedWidth = (3 * StationTimetableDepartureLayout.columnWidth)
            + (2 * StationTimetableDepartureLayout.columnSpacing)
        XCTAssertEqual(renderedWidth(values: ["05", "15", "25"]), expectedWidth, accuracy: 1)
        XCTAssertEqual(renderedWidth(values: ["05A", "15BC", "25"]), expectedWidth, accuracy: 1)
    }

    func testRouteStopMarkerIsAnOutlinedCircleWithAnOptionalCenter() throws {
        func centerBrightness(showsCenter: Bool) throws -> CGFloat {
            let marker = RouteStopMarker(
                color: .black,
                isEmphasized: showsCenter,
                showsCenter: showsCenter
            )
            .background(Color.white)
            .environment(\.colorScheme, .light)
            let hostingView = NSHostingView(rootView: marker)
            hostingView.frame = NSRect(
                x: 0,
                y: 0,
                width: RouteStopMarker.diameter,
                height: RouteStopMarker.diameter
            )
            hostingView.layoutSubtreeIfNeeded()

            let bitmap = try XCTUnwrap(
                hostingView.bitmapImageRepForCachingDisplay(in: hostingView.bounds)
            )
            hostingView.cacheDisplay(in: hostingView.bounds, to: bitmap)
            let color = try XCTUnwrap(
                bitmap.colorAt(x: bitmap.pixelsWide / 2, y: bitmap.pixelsHigh / 2)?
                    .usingColorSpace(.deviceRGB)
            )
            return (color.redComponent + color.greenComponent + color.blueComponent) / 3
        }

        XCTAssertGreaterThan(try centerBrightness(showsCenter: false), 0.9)
        XCTAssertLessThan(try centerBrightness(showsCenter: true), 0.1)
    }

    func testStationTimetableTimelineHighlightsFromTheSelectedStopToTheEnd() {
        let presentations = (0..<5).map {
            StationTimetableStopTimelinePresentation(
                index: $0,
                stopCount: 5,
                selectedStopIndex: 2
            )
        }

        XCTAssertEqual(
            presentations.map(\.markerIsHighlighted),
            [false, false, true, true, true]
        )
        XCTAssertEqual(
            presentations.map(\.markerIsEmphasized),
            [false, false, true, false, false]
        )
        XCTAssertEqual(
            presentations.map(\.showsMarkerCenter),
            [true, false, true, false, true]
        )
        XCTAssertEqual(
            presentations.map(\.topConnectorIsHighlighted),
            [false, false, false, true, true]
        )
        XCTAssertEqual(
            presentations.map(\.bottomConnectorIsHighlighted),
            [false, false, true, true, false]
        )
    }

    func testStationTimetableStopNotesShareTheStopTextLeadingEdge() {
        XCTAssertEqual(
            StationTimetableStopTimelineLayout.textLeadingPadding,
            StationTimetableStopTimelineLayout.rowHorizontalPadding
                + StationTimetableStopTimelineLayout.minuteWidth
                + (2 * StationTimetableStopTimelineLayout.columnSpacing)
                + RouteStopMarker.diameter
        )
    }

    func testSelectedStationTimetableStopKeepsMetadataAndNoteColorsAligned() throws {
        let width: CGFloat = 80
        let rowHeight: CGFloat = 20
        func renderedColors(in colorScheme: ColorScheme) throws -> (NSColor, NSColor) {
            let view = VStack(spacing: 0) {
                Button {} label: {
                    Color.secondary.frame(width: width, height: rowHeight)
                }
                .buttonStyle(StationTimetableStopButtonStyle())
                .disabled(true)

                Color.secondary.frame(width: width, height: rowHeight)
            }
            .frame(width: width, height: rowHeight * 2)
            .background(colorScheme == .dark ? Color.black : Color.white)
            .environment(\.colorScheme, colorScheme)
            let hostingView = NSHostingView(rootView: view)
            hostingView.frame = NSRect(x: 0, y: 0, width: width, height: rowHeight * 2)
            hostingView.layoutSubtreeIfNeeded()

            let bitmap = try XCTUnwrap(
                hostingView.bitmapImageRepForCachingDisplay(in: hostingView.bounds)
            )
            hostingView.cacheDisplay(in: hostingView.bounds, to: bitmap)
            let x = bitmap.pixelsWide / 2
            return (
                try XCTUnwrap(
                    bitmap.colorAt(x: x, y: bitmap.pixelsHigh / 4)?
                        .usingColorSpace(.deviceRGB)
                ),
                try XCTUnwrap(
                    bitmap.colorAt(x: x, y: (bitmap.pixelsHigh * 3) / 4)?
                        .usingColorSpace(.deviceRGB)
                )
            )
        }

        for colorScheme in [ColorScheme.light, .dark] {
            let (metadataColor, noteColor) = try renderedColors(in: colorScheme)
            XCTAssertEqual(metadataColor.redComponent, noteColor.redComponent, accuracy: 0.01)
            XCTAssertEqual(metadataColor.greenComponent, noteColor.greenComponent, accuracy: 0.01)
            XCTAssertEqual(metadataColor.blueComponent, noteColor.blueComponent, accuracy: 0.01)
            XCTAssertEqual(metadataColor.alphaComponent, noteColor.alphaComponent, accuracy: 0.01)
        }
    }

    func testRenderedStationTimetableTimelineConnectsAcrossAMiddleRow() throws {
        let width: CGFloat = 100
        let height: CGFloat = 50
        let timeline = StationTimetableStopTimeline(
            presentation: StationTimetableStopTimelinePresentation(
                index: 3,
                stopCount: 5,
                selectedStopIndex: 2
            )
        )
        .frame(width: width, height: height)
        .background(Color.white)
        .environment(\.colorScheme, .light)
        let hostingView = NSHostingView(rootView: timeline)
        hostingView.frame = NSRect(x: 0, y: 0, width: width, height: height)
        hostingView.layoutSubtreeIfNeeded()

        let bitmap = try XCTUnwrap(
            hostingView.bitmapImageRepForCachingDisplay(in: hostingView.bounds)
        )
        hostingView.cacheDisplay(in: hostingView.bounds, to: bitmap)
        let scale = CGFloat(bitmap.pixelsWide) / hostingView.bounds.width
        let connectorBounds = try XCTUnwrap(
            inkBounds(
                in: bitmap,
                xRange: Int(
                    (StationTimetableStopTimelineLayout.markerCenterX - 1) * scale
                )..<Int(
                    (StationTimetableStopTimelineLayout.markerCenterX + 1) * scale
                ),
                maximumBrightness: 0.9
            )
        )

        XCTAssertEqual(connectorBounds.minY, 0, accuracy: 1)
        XCTAssertEqual(connectorBounds.maxY, CGFloat(bitmap.pixelsHigh), accuracy: 1)
    }

    func testWrappedStationTimetableRouteCentersBesideLineName() throws {
        let width: CGFloat = 320
        let heading = StationTimetableRouteHeading(
            lineTitle: "🚌 Bus 302",
            route: "Nové Dvory,Frýdecká skládka → Místek,Tesco",
            isLockout: false
        )
        .frame(width: width, alignment: .leading)
        .background(Color.white)
        .environment(\.colorScheme, .light)
        let hostingView = NSHostingView(rootView: heading)
        hostingView.frame = NSRect(origin: .zero, size: hostingView.fittingSize)
        hostingView.layoutSubtreeIfNeeded()

        let bitmap = try XCTUnwrap(
            hostingView.bitmapImageRepForCachingDisplay(in: hostingView.bounds)
        )
        hostingView.cacheDisplay(in: hostingView.bounds, to: bitmap)
        let scale = CGFloat(bitmap.pixelsWide) / hostingView.bounds.width
        let lineTitleBounds = try XCTUnwrap(
            inkBounds(
                in: bitmap,
                xRange: 0..<Int(108 * scale),
                maximumBrightness: 0.9
            )
        )
        let routeBounds = try XCTUnwrap(
            inkBounds(
                in: bitmap,
                xRange: Int(112 * scale)..<bitmap.pixelsWide,
                maximumBrightness: 0.9
            )
        )

        XCTAssertGreaterThan(routeBounds.height, lineTitleBounds.height)
        XCTAssertEqual(lineTitleBounds.midY, routeBounds.midY, accuracy: 2 * scale)
    }

    func testSelectableServiceNoteFlowRetainsCalendarPhoneAndWebLinks() {
        let view = ServiceNotesView(
            notes: ["jede v 1-5", "Informace: +420 123 456 789", "Web: www.KODIS.cz"],
            timetableValidity: IDOSTimetableValidity(
                validFrom: serviceDate(2026, 1, 1),
                validThrough: serviceDate(2026, 12, 31)
            )
        )
        let links = view.linkedContent.runs.compactMap(\.link)

        XCTAssertTrue(links.contains(ServiceNotesView.calendarDestination(for: 0)))
        XCTAssertTrue(links.contains(URL(string: "tel:+420123456789")!))
        XCTAssertTrue(links.contains(URL(string: "http://www.KODIS.cz")!))
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

    func testNoteTextTurnsWebAddressesIntoLinksWithoutChangingTheNote() {
        let value = "Více na www.KODIS.cz nebo https://idos.cz/en/."
        let content = NoteText.linkedContent(value)

        XCTAssertEqual(String(content.characters), value)
        XCTAssertEqual(
            content.runs.compactMap { $0.link?.absoluteString },
            ["http://www.KODIS.cz", "https://idos.cz/en/"]
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

    /// Creates compatibility IDOS values in the provider's civil zone, independently of the test Mac's zone.
    private func idosServiceDate(_ year: Int, _ month: Int, _ day: Int) -> Date {
        let calendar = StationTimetableServiceCalendar.serviceCalendar(
            timeZone: IDOSDataSource.serviceTimeZone
        )
        return calendar.date(from: DateComponents(
            timeZone: calendar.timeZone,
            year: year,
            month: month,
            day: day
        ))!
    }

    func testResultDetailToolbarAndFileMenuShareFourPrimaryActions() throws {
        let czech = try XCTUnwrap(localizationBundle(languageCode: "cs"))
        let english = try XCTUnwrap(localizationBundle(languageCode: "en"))

        XCTAssertEqual(
            ResultDetailAction.allCases,
            [.sendByEmail, .addToCalendar, .openPDF, .share]
        )
        let keys = [
            "Send by Email",
            "Add to Calendar",
            "Open PDF in Preview",
            "Share Link",
        ]
        XCTAssertEqual(
            keys.map { czech.localizedString(forKey: $0, value: nil, table: nil) },
            [
                "Poslat na e-mail",
                "Přidat do Kalendáře",
                "Otevřít PDF v Náhledu",
                "Sdílet odkaz",
            ]
        )
        XCTAssertEqual(
            keys.map { english.localizedString(forKey: $0, value: nil, table: nil) },
            keys
        )
        XCTAssertEqual(
            czech.localizedString(forKey: "Compose in Mail", value: nil, table: nil),
            "Napsat v Mailu"
        )
        XCTAssertEqual(
            english.localizedString(forKey: "Compose in Mail", value: nil, table: nil),
            "Compose in Mail"
        )
        XCTAssertEqual(
            czech.localizedString(forKey: "Share Text", value: nil, table: nil),
            "Sdílet text"
        )
        XCTAssertEqual(
            english.localizedString(forKey: "Share Text", value: nil, table: nil),
            "Share Text"
        )
        XCTAssertEqual(
            czech.localizedString(forKey: "Open Link", value: nil, table: nil),
            "Otevřít odkaz"
        )
        XCTAssertEqual(
            english.localizedString(forKey: "Open Link", value: nil, table: nil),
            "Open Link"
        )
        XCTAssertEqual(
            czech.localizedString(forKey: "Download ICS File", value: nil, table: nil),
            "Stáhnout soubor ICS"
        )
        XCTAssertEqual(
            english.localizedString(forKey: "Download ICS File", value: nil, table: nil),
            "Download ICS File"
        )
        XCTAssertEqual(
            czech.localizedString(forKey: "Download PDF File", value: nil, table: nil),
            "Stáhnout soubor PDF"
        )
        XCTAssertEqual(
            english.localizedString(forKey: "Download PDF File", value: nil, table: nil),
            "Download PDF File"
        )
        XCTAssertEqual(
            czech.localizedString(forKey: "Refresh connections", value: nil, table: nil),
            "Obnovit spojení"
        )
        XCTAssertEqual(
            english.localizedString(forKey: "Refresh connections", value: nil, table: nil),
            "Refresh connections"
        )
    }

    func testConnectionEmailPlaceholderUsesLocaleAppropriateExampleAddress() throws {
        let czech = try XCTUnwrap(localizationBundle(languageCode: "cs"))
        let english = try XCTUnwrap(localizationBundle(languageCode: "en"))

        XCTAssertEqual(
            czech.localizedString(forKey: "name@example.com", value: nil, table: nil),
            "jmeno@priklad.cz"
        )
        XCTAssertEqual(
            english.localizedString(forKey: "name@example.com", value: nil, table: nil),
            "name@example.com"
        )
    }

    func testConnectionEmailMessageCreditsKastanInLocalizedIDOSFooter() throws {
        let czech = try XCTUnwrap(localizationBundle(languageCode: "cs"))
        let english = try XCTUnwrap(localizationBundle(languageCode: "en"))
        let projectWebsite = ConnectionEmailMessage.projectWebsite.absoluteString
        let czechAttribution = String(
            format: czech.localizedString(forKey: "using the Kaštan app %@", value: nil, table: nil),
            projectWebsite
        )
        let englishAttribution = String(
            format: english.localizedString(forKey: "using the Kaštan app %@", value: nil, table: nil),
            projectWebsite
        )

        let czechMessage = ConnectionEmailMessage.creditingKastan(
            in: "Vyhledáno na webu https://idos.cz",
            attribution: czechAttribution
        )
        XCTAssertEqual(
            czechMessage,
            "Vyhledáno na webu https://idos.cz pomocí aplikace Kaštan \(projectWebsite)"
        )
        XCTAssertEqual(
            ConnectionEmailMessage.creditingKastan(
                in: "Searched on the website https://idos.cz",
                attribution: englishAttribution
            ),
            "Searched on the website https://idos.cz using the Kaštan app \(projectWebsite)"
        )
        XCTAssertEqual(
            ConnectionEmailMessage.creditingKastan(in: czechMessage, attribution: czechAttribution),
            czechMessage
        )
        XCTAssertEqual(
            ConnectionEmailMessage.creditingKastan(in: "Prepared by IDOS", attribution: englishAttribution),
            "Prepared by IDOS"
        )
    }

    func testConnectionDetailToolbarOffersEveryAvailableActionSeparately() {
        XCTAssertEqual(
            ResultDetailAction.allCases.map(\.systemImage),
            [
                "envelope",
                "calendar.badge.plus",
                "doc.text.magnifyingglass",
                "square.and.arrow.up",
            ]
        )
        XCTAssertEqual(
            ResultDetailAction.availableActions(canSendByEmail: true),
            ResultDetailAction.allCases
        )
        XCTAssertEqual(
            ResultDetailAction.availableActions(canSendByEmail: false),
            [.addToCalendar, .openPDF, .share]
        )
    }

    func testResultActionsFollowProviderExportCapabilities() {
        let descriptor = TransitDataSourceDescriptor(
            id: "calendar-only",
            displayName: "Calendar Transit",
            capabilities: [.connections, .connectionCalendarExport]
        )
        let connectionAvailability = ResultDetailActionAvailability.connection(descriptor)
        let serviceAvailability = ResultDetailActionAvailability.service(descriptor)

        XCTAssertEqual(
            connectionAvailability,
            ResultDetailActionAvailability(
                canSendByEmail: false,
                canAddToCalendar: true,
                canOpenPDF: false
            )
        )
        XCTAssertEqual(
            ResultDetailAction.availableActions(
                canSendByEmail: connectionAvailability.canSendByEmail,
                canAddToCalendar: connectionAvailability.canAddToCalendar,
                canOpenPDF: connectionAvailability.canOpenPDF
            ),
            [.addToCalendar, .share]
        )
        XCTAssertFalse(connectionAvailability.canComposeConnectionEmailInMail)
        XCTAssertFalse(serviceAvailability.canAddToCalendar)
        XCTAssertFalse(serviceAvailability.canOpenPDF)

        let emailWithOneAttachment = ResultDetailActionAvailability.connection(
            TransitDataSourceDescriptor(
                id: "email-pdf",
                displayName: "Email PDF Transit",
                capabilities: [.connectionEmail, .connectionPDFExport]
            )
        )
        XCTAssertTrue(emailWithOneAttachment.canComposeConnectionEmailInMail)
    }

    func testOptionChangesIDOSConnectionEmailToMailComposition() {
        XCTAssertEqual(ConnectionEmailAction.preferred(for: []), .sendViaIDOS)
        XCTAssertEqual(ConnectionEmailAction.preferred(for: [.command]), .sendViaIDOS)
        XCTAssertEqual(ConnectionEmailAction.preferred(for: [.option]), .composeInMail)
        XCTAssertEqual(
            ConnectionEmailAction.preferred(for: [.option, .shift]),
            .composeInMail
        )
        XCTAssertEqual(ConnectionEmailAction.sendViaIDOS.systemImage, "envelope")
        XCTAssertEqual(ConnectionEmailAction.composeInMail.systemImage, "envelope.open")
        XCTAssertEqual(
            ResultDetailAction.sendByEmail.systemImage(emailAction: .composeInMail),
            ConnectionEmailAction.composeInMail.systemImage
        )
    }

    func testEmailToolbarKeepsItsWidthWhenOptionChangesDestination() {
        let idos = NSHostingView(
            rootView: OptionAlternateButtonLabel(
                primaryAction: ConnectionEmailAction.sendViaIDOS,
                alternateAction: ConnectionEmailAction.composeInMail,
                presentedAction: .sendViaIDOS,
                reservesAlternateWidth: true
            ) { action in
                Label(action.title, systemImage: action.systemImage)
                    .labelStyle(.iconOnly)
            }
        )
        let mail = NSHostingView(
            rootView: OptionAlternateButtonLabel(
                primaryAction: ConnectionEmailAction.sendViaIDOS,
                alternateAction: ConnectionEmailAction.composeInMail,
                presentedAction: .composeInMail,
                reservesAlternateWidth: true
            ) { action in
                Label(action.title, systemImage: action.systemImage)
                    .labelStyle(.iconOnly)
            }
        )

        XCTAssertEqual(idos.fittingSize, mail.fittingSize)
    }

    func testOptionChangesLinkSharingToPortableText() {
        XCTAssertEqual(ResultSharingAction.preferred(for: []), .link)
        XCTAssertEqual(ResultSharingAction.preferred(for: [.command]), .link)
        XCTAssertEqual(ResultSharingAction.preferred(for: [.option]), .text)
        XCTAssertEqual(
            ResultSharingAction.preferred(for: [.option, .shift]),
            .text
        )
        XCTAssertEqual(ResultSharingAction.link.systemImage, "square.and.arrow.up")
        XCTAssertEqual(ResultSharingAction.text.systemImage, "doc.plaintext")
        XCTAssertEqual(
            ResultDetailAction.share.systemImage(sharingAction: .text),
            ResultSharingAction.text.systemImage
        )
    }

    func testShareToolbarKeepsItsWidthWhenOptionChangesRepresentation() {
        let link = NSHostingView(
            rootView: OptionAlternateButtonLabel(
                primaryAction: ResultSharingAction.link,
                alternateAction: ResultSharingAction.text,
                presentedAction: .link,
                reservesAlternateWidth: true
            ) { action in
                Label(action.title, systemImage: action.systemImage)
                    .labelStyle(.iconOnly)
            }
        )
        let text = NSHostingView(
            rootView: OptionAlternateButtonLabel(
                primaryAction: ResultSharingAction.link,
                alternateAction: ResultSharingAction.text,
                presentedAction: .text,
                reservesAlternateWidth: true
            ) { action in
                Label(action.title, systemImage: action.systemImage)
                    .labelStyle(.iconOnly)
            }
        )

        XCTAssertEqual(link.fittingSize, text.fittingSize)
    }

    func testOptionChangesAddToCalendarToICSDownload() {
        XCTAssertTrue(OptionAlternateButtonPlacement.menu.usesNativeAlternateWhenAvailable)
        XCTAssertFalse(OptionAlternateButtonPlacement.toolbar.usesNativeAlternateWhenAvailable)
        XCTAssertFalse(OptionAlternateButtonPlacement.menu.reservesAlternateLabelWidth)
        XCTAssertTrue(OptionAlternateButtonPlacement.toolbar.reservesAlternateLabelWidth)
        XCTAssertEqual(CalendarExportAction.preferred(for: []), .addToCalendar)
        XCTAssertEqual(CalendarExportAction.preferred(for: [.command]), .addToCalendar)
        XCTAssertEqual(CalendarExportAction.preferred(for: [.option]), .download)
        XCTAssertEqual(
            CalendarExportAction.preferred(for: [.option, .shift]),
            .download
        )
        XCTAssertEqual(CalendarExportAction.addToCalendar.systemImage, "calendar.badge.plus")
        XCTAssertEqual(CalendarExportAction.download.systemImage, "arrow.down.to.line")
        XCTAssertEqual(
            ResultDetailAction.addToCalendar.systemImage(calendarExportAction: .download),
            CalendarExportAction.download.systemImage
        )
    }

    func testCalendarToolbarKeepsItsWidthWhenOptionChangesAction() {
        let addToCalendar = NSHostingView(
            rootView: OptionAlternateButtonLabel(
                primaryAction: CalendarExportAction.addToCalendar,
                alternateAction: CalendarExportAction.download,
                presentedAction: .addToCalendar,
                reservesAlternateWidth: true
            ) { action in
                Label(action.title, systemImage: action.systemImage)
                    .labelStyle(.iconOnly)
            }
        )
        let download = NSHostingView(
            rootView: OptionAlternateButtonLabel(
                primaryAction: CalendarExportAction.addToCalendar,
                alternateAction: CalendarExportAction.download,
                presentedAction: .download,
                reservesAlternateWidth: true
            ) { action in
                Label(action.title, systemImage: action.systemImage)
                    .labelStyle(.iconOnly)
            }
        )

        XCTAssertEqual(addToCalendar.fittingSize, download.fittingSize)
    }

    func testOptionChangesPDFOpeningToDownload() {
        XCTAssertEqual(PDFExportAction.preferred(for: []), .openInPreview)
        XCTAssertEqual(PDFExportAction.preferred(for: [.command]), .openInPreview)
        XCTAssertEqual(PDFExportAction.preferred(for: [.option]), .download)
        XCTAssertEqual(PDFExportAction.openInPreview.systemImage, "doc.text.magnifyingglass")
        XCTAssertEqual(PDFExportAction.download.systemImage, "arrow.down.doc")
        XCTAssertEqual(
            ResultDetailAction.openPDF.systemImage(pdfExportAction: .download),
            PDFExportAction.download.systemImage
        )
    }

    func testPDFToolbarKeepsItsWidthWhenOptionChangesAction() {
        let openInPreview = NSHostingView(
            rootView: OptionAlternateButtonLabel(
                primaryAction: PDFExportAction.openInPreview,
                alternateAction: PDFExportAction.download,
                presentedAction: .openInPreview,
                reservesAlternateWidth: true
            ) { action in
                Label(action.title, systemImage: action.systemImage)
                    .labelStyle(.iconOnly)
            }
        )
        let download = NSHostingView(
            rootView: OptionAlternateButtonLabel(
                primaryAction: PDFExportAction.openInPreview,
                alternateAction: PDFExportAction.download,
                presentedAction: .download,
                reservesAlternateWidth: true
            ) { action in
                Label(action.title, systemImage: action.systemImage)
                    .labelStyle(.iconOnly)
            }
        )

        XCTAssertEqual(openInPreview.fittingSize, download.fittingSize)
    }

    func testResultContextMenusKeepConnectionAndServiceActionsDistinct() throws {
        XCTAssertEqual(
            ResultContextAction.availableActions(for: .connection),
            [
                .openInNewWindow,
                .separator,
                .detail(.sendByEmail),
                .detail(.addToCalendar),
                .detail(.openPDF),
                .detail(.share),
            ]
        )
        XCTAssertEqual(
            ResultContextAction.availableActions(
                for: .connection,
                availability: ResultDetailActionAvailability(
                    canSendByEmail: false,
                    canAddToCalendar: true,
                    canOpenPDF: true
                )
            ),
            [
                .openInNewWindow,
                .separator,
                .detail(.addToCalendar),
                .detail(.openPDF),
                .detail(.share),
            ]
        )
        XCTAssertEqual(
            ResultContextAction.availableActions(for: .service),
            [
                .preview,
                .openInNewWindow,
                .separator,
                .detail(.addToCalendar),
                .detail(.openPDF),
                .detail(.share),
            ]
        )

        let czech = try XCTUnwrap(localizationBundle(languageCode: "cs"))
        let english = try XCTUnwrap(localizationBundle(languageCode: "en"))
        let keys = [
            ResultContextTarget.connection.openInNewWindowTitleKey,
            "Preview service",
            ResultContextTarget.service.openInNewWindowTitleKey,
        ]
        XCTAssertEqual(
            keys.map { czech.localizedString(forKey: $0, value: nil, table: nil) },
            ["Otevřít spojení v novém okně", "Náhled spoje", "Otevřít spoj v novém okně"]
        )
        XCTAssertEqual(
            keys.map { english.localizedString(forKey: $0, value: nil, table: nil) },
            keys
        )
    }

    func testServiceContextMenuKeepsDetailActionsAvailableBeforeServiceLoads() async {
        let client = MockIDOSClient()
        let model = ServiceDetailViewModel(id: "service-context-menu", client: client)
        let menu = ServiceContextMenuContent(
            model: model,
            showPreview: {},
            openInNewWindow: {}
        )

        XCTAssertNil(model.service)
        XCTAssertFalse(menu.detailActionsAreDisabled)
        let requestCount = await client.serviceDetailRequestCount
        XCTAssertEqual(requestCount, 0)
    }

    func testDeferredServiceShareLinkLoadsAndLocalizesItsPermanentURL() async {
        let sourceURL = "https://idos.cz/en/vlaky/spojeni/prehled/?p=context-menu"
        let client = MockIDOSClient()
        await client.configureServiceShareURL(sourceURL)
        let model = ServiceDetailViewModel(id: "service-share", client: client)

        let url = await model.localizedPermanentLink()

        XCTAssertEqual(
            url,
            AppLanguagePreference.localizedIDOSURL(from: sourceURL)
        )
        let requestCount = await client.serviceDetailRequestCount
        XCTAssertEqual(requestCount, 1)
    }

    func testDeferredServiceTextSharingLoadsTheCompletePlainTextResult() async {
        let client = MockIDOSClient()
        let model = ServiceDetailViewModel(id: "service-text-share", client: client)

        let text = await model.localizedShareText()

        XCTAssertEqual(text, model.service.map(CLIPlainTextPresentation().service))
        XCTAssertFalse(text?.isEmpty ?? true)
        let requestCount = await client.serviceDetailRequestCount
        XCTAssertEqual(requestCount, 1)
    }

    func testSharingPickerKeepsSystemServicesAndAddsOpeningTheProviderLink() throws {
        let url = try XCTUnwrap(URL(string: "https://idos.cz/en/vlaky/spojeni/prehled/?p=share"))
        var openedURL: URL?
        let presenter = ResultSharingServicePickerPresenter { openedURL = $0 }
        let nativeService = NSSharingService(
            title: "Native service",
            image: NSImage(size: NSSize(width: 18, height: 18)),
            alternateImage: nil,
            handler: {}
        )
        let picker = NSSharingServicePicker(items: [url])

        let services = presenter.sharingServicePicker(
            picker,
            sharingServicesForItems: [url],
            proposedSharingServices: [nativeService]
        )

        XCTAssertEqual(services.count, 2)
        XCTAssertIdentical(services.first, nativeService)
        let openService = try XCTUnwrap(services.last)
        XCTAssertEqual(openService.title, AppLocalization.string("Open Link"))
        XCTAssertEqual(openService.menuItemTitle, AppLocalization.string("Open Link"))

        openService.perform(withItems: [url])

        XCTAssertEqual(openedURL, url)
    }

    func testTextSharingKeepsSystemServicesWithoutOfferingLinkOpening() {
        let presenter = ResultSharingServicePickerPresenter()
        let nativeService = NSSharingService(
            title: "Native service",
            image: NSImage(size: NSSize(width: 18, height: 18)),
            alternateImage: nil,
            handler: {}
        )
        let picker = NSSharingServicePicker(items: ["Portable result"])

        let services = presenter.sharingServicePicker(
            picker,
            sharingServicesForItems: ["Portable result"],
            proposedSharingServices: [nativeService]
        )

        XCTAssertEqual(services.count, 1)
        XCTAssertIdentical(services.first, nativeService)
    }

    func testResultDetailCommandsFollowTheFocusedWindowState() {
        let ready = ResultDetailCommandContext(
            hasLoadedResult: true,
            isPerformingAction: false,
            permanentLink: URL(string: "https://idos.cz/"),
            shareText: "Portable result",
            performEmailAction: { _ in },
            performCalendarAction: { _ in },
            performPDFAction: { _ in }
        )
        let loading = ResultDetailCommandContext(
            hasLoadedResult: false,
            isPerformingAction: false,
            permanentLink: nil,
            shareText: nil,
            performCalendarAction: { _ in },
            performPDFAction: { _ in }
        )
        let exporting = ResultDetailCommandContext(
            hasLoadedResult: true,
            isPerformingAction: true,
            permanentLink: URL(string: "https://idos.cz/"),
            shareText: "Portable result",
            performCalendarAction: { _ in },
            performPDFAction: { _ in }
        )
        let textOnly = ResultDetailCommandContext(
            hasLoadedResult: true,
            isPerformingAction: false,
            permanentLink: nil,
            shareText: "Portable result",
            performCalendarAction: { _ in },
            performPDFAction: { _ in }
        )
        let unsupportedExports = ResultDetailCommandContext(
            hasLoadedResult: true,
            isPerformingAction: false,
            permanentLink: URL(string: "https://example.com/connection"),
            shareText: "Portable result",
            availability: ResultDetailActionAvailability(
                canSendByEmail: false,
                canAddToCalendar: false,
                canOpenPDF: false
            ),
            performEmailAction: { _ in },
            performCalendarAction: { _ in },
            performPDFAction: { _ in }
        )

        XCTAssertTrue(ResultDetailAction.allCases.allSatisfy(ready.isEnabled))
        XCTAssertTrue(ResultDetailAction.allCases.allSatisfy { !loading.isEnabled($0) })
        XCTAssertTrue(ResultDetailAction.allCases.allSatisfy { !exporting.isEnabled($0) })
        XCTAssertTrue(textOnly.isEnabled(.share))
        XCTAssertFalse(textOnly.isEnabled(.sendByEmail))
        XCTAssertFalse(unsupportedExports.isEnabled(.sendByEmail))
        XCTAssertFalse(unsupportedExports.isEnabled(.addToCalendar))
        XCTAssertFalse(unsupportedExports.isEnabled(.openPDF))
        XCTAssertTrue(unsupportedExports.isEnabled(.share))
    }

    func testConnectionSharedTextMatchesTheLocalizedPlainCLIShape() throws {
        let english = try XCTUnwrap(localizationBundle(languageCode: "en"))
        let czech = try XCTUnwrap(localizationBundle(languageCode: "cs"))
        let connection = IDOSConnection(
            id: "connection-1",
            departureTime: "12:00",
            departureStation: "Praha hl.n.",
            arrivalTime: "14:30",
            arrivalStation: "Brno hl.n.",
            duration: "2 h 30 min",
            legs: [
                IDOSConnectionLeg(
                    name: "R 879 Svitava",
                    transportMode: .train,
                    departureTime: "12:00",
                    fromStation: "Praha hl.n.",
                    arrivalTime: "14:30",
                    toStation: "Brno hl.n."
                ),
            ]
        )
        let timetable = IDOSTimetable(slug: "vlaky", displayName: "Trains")

        let englishText = CLIPlainTextPresentation(bundle: english).connection(
            connection,
            timetable: timetable
        )
        let czechText = CLIPlainTextPresentation(bundle: czech).connection(
            connection,
            timetable: timetable
        )

        XCTAssertEqual(
            englishText,
            """
            🧭 Connections Praha hl.n. → Brno hl.n. (Trains):
            1. ➡️  Direct · ⚡ Shortest — 🕒 12:00 Praha hl.n. → 14:30 Brno hl.n. (2 h 30 min)
               🚆 R 879 Svitava Praha hl.n. 12:00 → 14:30 Brno hl.n.
            """
        )
        XCTAssertTrue(czechText.hasPrefix("🧭 Spojení Praha hl.n. → Brno hl.n. (Vlaky):"))
        XCTAssertTrue(czechText.contains("➡️  Přímý · ⚡ Nejrychlejší"))
        XCTAssertFalse(englishText.contains("\u{001B}"))
        XCTAssertFalse(englishText.contains(connection.id))
    }

    func testConnectionSharedTextPreservesAnotherProvidersTimetableName() throws {
        let english = try XCTUnwrap(localizationBundle(languageCode: "en"))
        let timetable = TransitTimetable(
            dataSourceID: "municipal",
            identifier: "vlaky",
            displayName: "City Network"
        )
        let connection = TransitConnection(
            dataSourceID: "municipal",
            timetableIdentifier: "vlaky",
            id: "connection-1",
            departureTime: "12:00",
            departureStation: "Market",
            arrivalTime: "12:10",
            arrivalStation: "Museum",
            duration: "10 min",
            legs: []
        )

        let text = CLIPlainTextPresentation(bundle: english).connection(
            connection,
            timetable: timetable
        )

        XCTAssertTrue(text.contains("(City Network)"))
        XCTAssertFalse(text.contains("(Trains)"))
    }

    func testConnectionHTMLForMailEscapesIDOSAndIntroductoryContent() throws {
        let english = try XCTUnwrap(localizationBundle(languageCode: "en"))
        let connection = IDOSConnection(
            id: "connection-unsafe",
            departureTime: "12:00",
            departureStation: "Praha <script>alert(1)</script>",
            arrivalTime: "14:30",
            arrivalStation: "Brno & okolí",
            duration: "2 h 30 min",
            legs: [
                IDOSConnectionLeg(
                    name: "R <script>alert(2)</script>",
                    color: "red; background: url(unsafe)",
                    transportMode: .train,
                    departureTime: "12:00",
                    fromStation: "Praha <hl.n.>",
                    arrivalTime: "14:30",
                    toStation: "Brno & okolí"
                ),
            ]
        )

        let html = CLIPlainTextPresentation(bundle: english).connectionHTML(
            connection,
            timetable: IDOSTimetable(slug: "vlaky", displayName: "Trains"),
            introductoryText: "Prepared <strong>by IDOS</strong> & Kaštan"
        )

        XCTAssertTrue(html.hasPrefix("<!doctype html>"))
        XCTAssertTrue(html.contains("Prepared &lt;strong&gt;by IDOS&lt;/strong&gt; &amp; Kaštan"))
        XCTAssertTrue(html.contains("Praha &lt;script&gt;alert(1)&lt;/script&gt;"))
        XCTAssertTrue(html.contains("Brno &amp; okolí"))
        XCTAssertTrue(html.contains("R &lt;script&gt;alert(2)&lt;/script&gt;"))
        XCTAssertTrue(html.contains("<table class=\"route-summary\">"))
        XCTAssertTrue(
            html.contains(
                "<th scope=\"row\">From</th><td>Praha &lt;script&gt;alert(1)&lt;/script&gt;</td>"
            )
        )
        XCTAssertFalse(html.contains("<dl>"))
        XCTAssertFalse(html.contains("<script>"))
        XCTAssertFalse(html.contains("background: url(unsafe)"))
    }

    func testServiceSharedTextIncludesTheCompleteCLIStyleRoute() throws {
        let english = try XCTUnwrap(localizationBundle(languageCode: "en"))
        let service = IDOSServiceDetail(
            id: "vlaky:service-1",
            timetable: IDOSTimetable(slug: "vlaky", displayName: "Trains"),
            name: "R 879 Svitava",
            transportMode: .train,
            date: "24.7.2026",
            stops: [
                IDOSServiceStop(
                    name: "Praha hl.n.",
                    departureTime: "12:00",
                    tariffZone: "P",
                    platform: "4",
                    track: "2",
                    distance: "0 km",
                    notes: ["wheelchair accessible station"]
                ),
                IDOSServiceStop(
                    name: "Brno hl.n.",
                    arrivalTime: "14:30",
                    platformTrack: "3/1",
                    distance: "255 km",
                    notes: ["request stop"]
                ),
            ],
            information: ["České dráhy, a.s."]
        )

        let text = CLIPlainTextPresentation(bundle: english).service(service)

        XCTAssertEqual(
            text,
            """
            🚆 R 879 Svitava · Service (Trains)
               🆔 Service ID: vlaky:service-1
               📅 Date: 24.7.2026
            🛤️ Route:
            1. 📍 Praha hl.n. — Departure 12:00 · tariff zone P · platform 4 track 2 · 0 km
                  ♿ wheelchair accessible station
            2. 📍 Brno hl.n. — Arrival 14:30 · platform 3 track 1 · 255 km
                  🔔 request stop

            ℹ️ Information:
               🏢 České dráhy, a.s.
            """
        )
        XCTAssertFalse(text.contains("\u{001B}"))
    }

    func testDetailLayoutStacksControlsAtCompactWidths() {
        let layout = DetailLayout(availableWidth: 510)

        XCTAssertEqual(layout.containerWidth, 510)
        XCTAssertEqual(layout.horizontalPadding, 16)
        XCTAssertTrue(layout.usesStackedSearchControls)
    }

    func testStationTimetableResultLayoutSplitsWideResultsInHalf() {
        let layout = StationTimetableResultLayout(availableWidth: 1_218)

        XCTAssertFalse(layout.usesSectionPicker)
        XCTAssertEqual(layout.columnWidth, 600)
        XCTAssertEqual(
            (2 * layout.columnWidth) + StationTimetableResultLayout.columnSpacing,
            layout.availableWidth
        )
    }

    func testStationTimetableResultLayoutUsesPickerBelowReadableColumnWidth() {
        let minimumTwoColumnWidth =
            (2 * StationTimetableResultLayout.minimumColumnWidth) +
            StationTimetableResultLayout.columnSpacing
        let fittedLayout = StationTimetableResultLayout(availableWidth: minimumTwoColumnWidth)
        let compactLayout = StationTimetableResultLayout(
            availableWidth: minimumTwoColumnWidth - 1
        )

        XCTAssertFalse(fittedLayout.usesSectionPicker)
        XCTAssertTrue(compactLayout.usesSectionPicker)
    }

    func testStationTimetableResultSectionPickerSelectsLocalizedContent() throws {
        var selection = StationTimetableResultSection.stops
        let picker = StationTimetableResultSectionPicker(selection: Binding(
            get: { selection },
            set: { selection = $0 }
        ))
        let hostingView = NSHostingView(rootView: picker)
        hostingView.frame = NSRect(x: 0, y: 0, width: 280, height: 40)
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

        let control = try XCTUnwrap(
            hostingView.allDescendantViews.compactMap { $0 as? NSSegmentedControl }.first
        )
        XCTAssertEqual(control.segmentCount, 2)
        XCTAssertEqual(control.label(forSegment: 0), AppLocalization.string("Stops"))
        XCTAssertEqual(control.label(forSegment: 1), AppLocalization.string("Timetable"))
        XCTAssertEqual(selection, .stops)

        control.selectedSegment = 1
        control.sendAction(control.action, to: control.target)

        XCTAssertEqual(selection, .timetable)
    }

    func testSharedSearchActionUsesStationTimetableWidth() {
        XCTAssertEqual(SearchActionButton.contentWidth, 140)
    }

    func testMainWindowDefaultsToFullyReadableLocalizedSearchWorkspaceWidth() {
        let layout = DetailLayout(availableWidth: KastanApp.minimumMainWindowWidth)

        XCTAssertGreaterThanOrEqual(
            KastanApp.minimumMainWindowWidth,
            KastanApp.baselineMainWindowWidth
        )
        XCTAssertEqual(KastanApp.defaultMainWindowWidth, KastanApp.minimumMainWindowWidth)
        XCTAssertGreaterThanOrEqual(
            layout.contentWidth,
            JourneyOptionRowLayout.minimumContentWidth
        )
        XCTAssertEqual(SearchTimetablePicker.favoriteSpacing(usesCompactLayout: true), 0)
        XCTAssertEqual(SearchTimetablePicker.favoriteSpacing(usesCompactLayout: false), 8)
        XCTAssertEqual(SearchTimetablePicker.pickerWidth, 236)
        let endpointFieldWidth = ConnectionEndpointLayout.fieldWidth(contentWidth: layout.contentWidth)
        XCTAssertEqual(
            (2 * endpointFieldWidth) + ConnectionEndpointLayout.swapButtonWidth +
                (2 * ConnectionEndpointLayout.spacing),
            layout.contentWidth
        )
    }

    func testWidestJourneyOptionRowFitsLocalizedMinimumWithoutCompression() throws {
        let contentWidth = DetailLayout(
            availableWidth: KastanApp.minimumMainWindowWidth
        ).contentWidth
        let row = HStack(spacing: JourneyOptionRowLayout.spacing) {
            JourneyOptionKindPicker(
                selection: .constant(.walkingDistances),
                availableKinds: JourneyOptionKind.allCases
            )
            .fixedSize(horizontal: true, vertical: false)

            Picker(selection: .constant(JourneyWalkingDistanceConstraint.maximumCityWalkingTime)) {
                ForEach(JourneyWalkingDistanceConstraint.allCases) { constraint in
                    Text(verbatim: constraint.localizedTitle).tag(constraint)
                }
            } label: {
                Text(verbatim: JourneyOptionKind.walkingDistances.localizedTitle)
            }
            .labelsHidden()
            .fixedSize()

            Picker(selection: .constant(60)) {
                ForEach(JourneyDurationChoice.maximumWalkingTimes) { choice in
                    Text(verbatim: choice.localizedTitle()).tag(choice.minutes)
                }
            } label: {
                Text(verbatim: JourneyWalkingDistanceConstraint.maximumCityWalkingTime.localizedTitle)
            }
            .labelsHidden()
            .fixedSize()

            Spacer(minLength: 0)

            Button {} label: {
                Label("Remove journey option", systemImage: "minus")
                    .labelStyle(.iconOnly)
                    .frame(width: JourneyOptionRowLayout.actionIconWidth, height: 14)
            }
            .buttonStyle(.bordered)
            .fixedSize()
            .background(SearchSupplementLayoutProbe(name: "remove-action"))

            Button {} label: {
                Label("Add journey option", systemImage: "plus")
                    .labelStyle(.iconOnly)
                    .frame(width: JourneyOptionRowLayout.actionIconWidth, height: 14)
            }
            .buttonStyle(.bordered)
            .fixedSize()
            .background(SearchSupplementLayoutProbe(name: "add-action"))
        }
        .frame(width: contentWidth, height: 28, alignment: .leading)
        let hostingView = NSHostingView(rootView: row)
        hostingView.frame = NSRect(x: 0, y: 0, width: contentWidth, height: 28)
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

        let visibleControls = hostingView.allDescendantViews
            .compactMap { $0 as? NSControl }
            .filter { !$0.isHidden && $0.alphaValue > 0 && !$0.visibleRect.isEmpty }
        let popupButtons = visibleControls.compactMap { $0 as? NSPopUpButton }
        let probes = hostingView.allDescendantViews
            .compactMap { $0 as? SearchSupplementLayoutProbeView }
        let actionProbes = try ["remove-action", "add-action"].map { name in
            try XCTUnwrap(probes.first { $0.name == name })
        }

        XCTAssertEqual(popupButtons.count, 3)
        for control in visibleControls {
            let frame = hostingView.convert(control.bounds, from: control)
            XCTAssertGreaterThanOrEqual(frame.minX, -1)
            XCTAssertLessThanOrEqual(frame.maxX, contentWidth + 1)
        }
        for popupButton in popupButtons {
            XCTAssertGreaterThanOrEqual(
                popupButton.frame.width,
                popupButton.intrinsicContentSize.width - 0.5
            )
        }
        for actionProbe in actionProbes {
            let frame = hostingView.convert(actionProbe.bounds, from: actionProbe)
            XCTAssertEqual(
                frame.width,
                JourneyOptionRowLayout.actionButtonWidth,
                accuracy: 0.5
            )
        }
    }

    func testCompactConnectionFormKeepsNativeControlsInsideWindow() {
        let width = KastanApp.minimumMainWindowWidth
        func assertControlsStayInsideWindow(
            model: ConnectionsViewModel,
            client: MockIDOSClient,
            context: String
        ) {
            let hostingView = NSHostingView(
                rootView: ConnectionsView(
                    model: model,
                    client: client,
                    showsConnectionBadges: false,
                    showsItemDetails: false,
                    showsServiceInformationText: false,
                    showsStopNoteText: false
                )
                    .frame(width: width, height: 600)
            )
            hostingView.frame = NSRect(x: 0, y: 0, width: width, height: 600)
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

            let visibleControls = hostingView.allDescendantViews
                .compactMap { $0 as? NSControl }
                .filter { !$0.isHidden && $0.alphaValue > 0 && !$0.visibleRect.isEmpty }

            XCTAssertFalse(visibleControls.isEmpty, context)
            for control in visibleControls {
                let frame = hostingView.convert(control.bounds, from: control)
                XCTAssertGreaterThanOrEqual(
                    frame.minX,
                    -1,
                    "\(context): \(type(of: control)) exceeds the left edge"
                )
                XCTAssertLessThanOrEqual(
                    frame.maxX,
                    width + 1,
                    "\(context): \(type(of: control)) exceeds the right edge"
                )
            }
        }

        let currentClient = MockIDOSClient()
        assertControlsStayInsideWindow(
            model: ConnectionsViewModel(client: currentClient),
            client: currentClient,
            context: "Current instant"
        )

        let customClient = MockIDOSClient()
        let customModel = ConnectionsViewModel(client: customClient)
        customModel.date = serviceDate(2026, 12, 31)
        customModel.time = serviceDate(2026, 12, 31).addingTimeInterval(23 * 60 * 60 + 59 * 60)
        assertControlsStayInsideWindow(
            model: customModel,
            client: customClient,
            context: "Custom instant"
        )
    }

    func testTimetableFavoriteButtonDoesNotOverlapItsPicker() throws {
        for usesCompactLayout in [true, false] {
            let picker = SearchTimetablePicker(
                timetable: .constant(IDOSTimetable(slug: "vlaky", displayName: "Trains")),
                usesCompactLayout: usesCompactLayout
            )
            let hostingView = NSHostingView(
                rootView: picker.frame(width: 320, height: 64, alignment: .topLeading)
            )
            hostingView.frame = NSRect(x: 0, y: 0, width: 320, height: 64)
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

            let descendants = hostingView.allDescendantViews
            let timetablePicker = try XCTUnwrap(
                descendants.compactMap { $0 as? NSPopUpButton }.first
            )
            let favoriteButton = try XCTUnwrap(
                descendants.compactMap { $0 as? NSButton }.first { !($0 is NSPopUpButton) }
            )
            let timetableFrame = hostingView.convert(timetablePicker.bounds, from: timetablePicker)
            let favoriteFrame = hostingView.convert(favoriteButton.bounds, from: favoriteButton)
            let renderedGap = favoriteFrame.minX - timetableFrame.maxX

            XCTAssertGreaterThanOrEqual(
                renderedGap,
                SearchTimetablePicker.favoriteSpacing(usesCompactLayout: usesCompactLayout)
            )
            XCTAssertGreaterThanOrEqual(renderedGap, 0)
        }
    }

    func testPlaceInputSwapButtonUsesBorderlessStationTimetableStyle() throws {
        var didSwap = false
        let hostingView = NSHostingView(rootView: PlaceInputSwapButton(
            accessibilityLabel: "Swap departure and arrival",
            action: { didSwap = true }
        ))
        hostingView.frame = NSRect(x: 0, y: 0, width: 48, height: 48)
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

        let button = try XCTUnwrap(
            hostingView.allDescendantViews.compactMap { $0 as? NSButton }.first
        )
        XCTAssertEqual(PlaceInputSwapButton.iconSize, 24)
        XCTAssertFalse(button.isBordered)

        button.performClick(nil)

        XCTAssertTrue(didSwap)
    }

    func testSearchActionAlignsWithTheTrailingSearchEdge() throws {
        func assertTrailingAlignment(
            controls: JourneySearchControls,
            width: CGFloat,
            context: String
        ) throws {
            let hostingView = NSHostingView(
                rootView: controls.frame(width: width, height: 100, alignment: .topLeading)
            )
            hostingView.frame = NSRect(x: 0, y: 0, width: width, height: 100)
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

            let renderedTrailingEdge = try XCTUnwrap(
                hostingView.allDescendantViews
                    .map { hostingView.convert($0.bounds, from: $0).maxX }
                    .max(),
                context
            )

            XCTAssertEqual(
                renderedTrailingEdge,
                width + SearchActionButton.trailingVisualOffset,
                accuracy: 0.1,
                context
            )
        }

        for width in [490.0, 880.0] {
            try assertTrailingAlignment(
                controls: JourneySearchControls(
                    isSearching: false,
                    canSearch: true,
                    search: {}
                ),
                width: width,
                context: "Search-only row at \(width) points"
            )
            try assertTrailingAlignment(
                controls: JourneySearchControls(
                    isSearching: false,
                    canSearch: true,
                    supplement: JourneySearchControlsSupplement(
                        leading: EmptyView(),
                        adjacent: EmptyView(),
                        details: EmptyView()
                    ),
                    search: {}
                ),
                width: width,
                context: "Supplemented row at \(width) points"
            )
        }
    }

    func testJourneySearchHeaderFitsTheMinimumPaddedContentWidth() {
        let client = MockIDOSClient()
        let model = ConnectionsViewModel(client: client)
        let layout = DetailLayout(availableWidth: KastanApp.minimumMainWindowWidth)
        let hostingView = NSHostingView(rootView: JourneySearchHeader(
            timetable: .constant(model.timetable),
            date: .constant(model.date),
            time: .constant(model.time),
            isArrival: .constant(model.isArrival),
            modeLabel: "Time means",
            departureLabel: "Departure",
            arrivalLabel: "Arrival",
            usesCurrentDateAndTime: model.usesCurrentDateAndTime,
            selectCurrentDateAndTime: {},
            showsCurrentDateAndTimeShortcut: false,
            usesCompactLayout: true
        ))

        hostingView.layoutSubtreeIfNeeded()

        XCTAssertLessThanOrEqual(hostingView.fittingSize.width, layout.contentWidth)
    }

    func testTimetablePickerAppearsAbovePrimaryInputInEverySearchMode() throws {
        let width = KastanApp.minimumMainWindowWidth
        func assertTimetablePrecedesInput<Content: View>(
            _ content: Content,
            prompts: [String],
            mode: String
        ) throws {
            let hostingView = NSHostingView(
                rootView: content.frame(width: width, height: 600)
            )
            hostingView.frame = NSRect(x: 0, y: 0, width: width, height: 600)
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

            let descendants = hostingView.allDescendantViews
            let timetablePicker = try XCTUnwrap(
                descendants.compactMap { $0 as? NSPopUpButton }.first,
                "\(mode) is missing its timetable picker"
            )
            let inputFields = try prompts.map { prompt in
                try XCTUnwrap(
                    descendants.compactMap { $0 as? NSTextField }.first {
                        $0.placeholderString == AppLocalization.string(prompt)
                    },
                    "\(mode) is missing its \(prompt) field"
                )
            }

            let timetableFrame = hostingView.convert(timetablePicker.bounds, from: timetablePicker)
            let inputFrames = inputFields.map { hostingView.convert($0.bounds, from: $0) }
            for inputFrame in inputFrames {
                if hostingView.isFlipped {
                    XCTAssertLessThan(timetableFrame.maxY, inputFrame.minY, mode)
                } else {
                    XCTAssertGreaterThan(timetableFrame.minY, inputFrame.maxY, mode)
                }
            }
        }

        let connectionsClient = MockIDOSClient()
        try assertTimetablePrecedesInput(
            ConnectionsView(
                model: ConnectionsViewModel(client: connectionsClient),
                client: connectionsClient,
                showsConnectionBadges: false,
                showsItemDetails: false,
                showsServiceInformationText: false,
                showsStopNoteText: false
            ),
            prompts: ["Departure place", "Arrival place"],
            mode: "Connections"
        )

        let departuresClient = MockIDOSClient()
        try assertTimetablePrecedesInput(
            DeparturesView(
                model: DeparturesViewModel(client: departuresClient),
                client: departuresClient,
                showsItemDetails: false,
                showsServiceInformationText: false,
                showsStopNoteText: false
            ),
            prompts: ["Station or stop"],
            mode: "Departures"
        )

        let stationTimetablesClient = MockIDOSClient()
        try assertTimetablePrecedesInput(
            StationTimetablesView(
                model: StationTimetablesViewModel(client: stationTimetablesClient),
                client: stationTimetablesClient,
                showsItemDetails: false,
                showsStopNoteText: false
            ),
            prompts: ["Line number or name", "Direction from", "Direction to"],
            mode: "Station Timetables"
        )
    }

    func testWideSearchControlsUseIntrinsicHeightAndKeepSupplementalControlsTogether() throws {
        let width: CGFloat = 880
        let controls = JourneySearchControls(
            isSearching: false,
            canSearch: true,
            supplement: JourneySearchControlsSupplement(
                leading: SearchSupplementLayoutProbe(name: "options")
                    .frame(width: 180, height: 22),
                adjacent: SearchSupplementLayoutProbe(name: "shortcut")
                    .frame(width: 150, height: 22),
                details: SearchSupplementLayoutProbe(name: "details")
                    .frame(height: 0)
            ),
            search: {}
        )
        .background(SearchSupplementLayoutProbe(name: "controls"))
        .frame(width: width, height: 420, alignment: .topLeading)
        let hostingView = NSHostingView(rootView: controls)
        hostingView.frame = NSRect(x: 0, y: 0, width: width, height: 420)
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

        let descendants = hostingView.allDescendantViews
        let probes = descendants.compactMap { $0 as? SearchSupplementLayoutProbeView }
        let controlsProbe = try XCTUnwrap(probes.first { $0.name == "controls" })
        let options = try XCTUnwrap(probes.first { $0.name == "options" })
        let shortcut = try XCTUnwrap(probes.first { $0.name == "shortcut" })

        let controlsFrame = hostingView.convert(controlsProbe.bounds, from: controlsProbe)
        let optionsFrame = hostingView.convert(options.bounds, from: options)
        let shortcutFrame = hostingView.convert(shortcut.bounds, from: shortcut)

        XCTAssertLessThan(controlsFrame.height, 120)
        XCTAssertEqual(shortcutFrame.minX - optionsFrame.maxX, 12, accuracy: 1)
        XCTAssertEqual(optionsFrame.midY, shortcutFrame.midY, accuracy: 1)
    }

    func testSearchWidthKeepsSupplementalControlsClustered() throws {
        struct Frames {
            let options: CGRect
            let directOnly: CGRect
        }

        func renderedFrames(width: CGFloat) throws -> Frames {
            let controls = JourneySearchControls(
                isSearching: false,
                canSearch: true,
                supplement: JourneySearchControlsSupplement(
                    leading: JourneyOptionsDisclosureHeader(isExpanded: .constant(false))
                        .background(SearchSupplementLayoutProbe(name: "options")),
                    adjacent: SearchSupplementLayoutProbe(name: "direct-only")
                        .frame(width: 150, height: 22),
                    details: EmptyView()
                ),
                search: {}
            )
            .frame(width: width, height: 140, alignment: .topLeading)
            let hostingView = NSHostingView(rootView: controls)
            hostingView.frame = NSRect(x: 0, y: 0, width: width, height: 140)
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

            let descendants = hostingView.allDescendantViews
            let probes = descendants.compactMap { $0 as? SearchSupplementLayoutProbeView }
            let options = try XCTUnwrap(probes.first { $0.name == "options" })
            let directOnly = try XCTUnwrap(probes.first { $0.name == "direct-only" })
            XCTAssertTrue(descendants.compactMap { $0 as? NSSegmentedControl }.isEmpty)

            return Frames(
                options: hostingView.convert(options.bounds, from: options),
                directOnly: hostingView.convert(directOnly.bounds, from: directOnly)
            )
        }

        let frames = try [
            renderedFrames(width: 490),
            renderedFrames(width: 880),
            renderedFrames(width: 1_200),
        ]
        let baseline = try XCTUnwrap(frames.first)

        for current in frames {
            XCTAssertEqual(current.options.minX, baseline.options.minX, accuracy: 1)
            XCTAssertEqual(current.directOnly.minX, baseline.directOnly.minX, accuracy: 1)
            XCTAssertEqual(current.directOnly.minX - current.options.maxX, 12, accuracy: 1)
        }
    }

    func testExpandedSearchSupplementRevealsShortcutWithoutMovingHeading() throws {
        struct Frames {
            let options: CGRect
            let shortcut: CGRect?
            let details: CGRect
        }

        func renderedFrames(width: CGFloat, isExpanded: Bool) throws -> Frames {
            let controls = JourneySearchControls(
                isSearching: false,
                canSearch: true,
                supplement: JourneySearchControlsSupplement(
                    leading: SearchSupplementLayoutProbe(name: "options")
                        .frame(width: 180, height: 22),
                    adjacent: Group {
                        if isExpanded {
                            SearchSupplementLayoutProbe(name: "shortcut")
                                .frame(width: 150, height: 22)
                        }
                    },
                    details: SearchSupplementLayoutProbe(name: "details")
                        .frame(height: isExpanded ? 120 : 0)
                        .frame(maxWidth: .infinity, alignment: .leading)
                ),
                search: {}
            )
            .frame(width: width, height: 420, alignment: .topLeading)
            let hostingView = NSHostingView(rootView: controls)
            hostingView.frame = NSRect(x: 0, y: 0, width: width, height: 420)
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

            let descendants = hostingView.allDescendantViews
            let probes = descendants.compactMap { $0 as? SearchSupplementLayoutProbeView }
            let options = try XCTUnwrap(probes.first { $0.name == "options" })
            let details = try XCTUnwrap(probes.first { $0.name == "details" })

            return Frames(
                options: hostingView.convert(options.bounds, from: options),
                shortcut: probes.first { $0.name == "shortcut" }.map {
                    hostingView.convert($0.bounds, from: $0)
                },
                details: hostingView.convert(details.bounds, from: details)
            )
        }

        let widths = [
            DetailLayout(availableWidth: 652).contentWidth,
            DetailLayout(availableWidth: KastanApp.minimumMainWindowWidth).contentWidth,
        ]
        for width in widths {
            let collapsed = try renderedFrames(width: width, isExpanded: false)
            let expanded = try renderedFrames(width: width, isExpanded: true)
            let expandedShortcut = try XCTUnwrap(expanded.shortcut)

            XCTAssertEqual(collapsed.options.minX, expanded.options.minX, accuracy: 1)
            XCTAssertNil(collapsed.shortcut)
            XCTAssertEqual(expanded.options.midY, expandedShortcut.midY, accuracy: 1)
            XCTAssertEqual(expandedShortcut.minX - expanded.options.maxX, 12, accuracy: 1)
            XCTAssertLessThanOrEqual(expanded.details.maxX, width + 1)
        }
    }

    func testJourneyOptionsHeadingTogglesDisclosureAwayFromArrow() {
        var isExpanded = false
        let header = JourneyOptionsDisclosureHeader(isExpanded: Binding(
            get: { isExpanded },
            set: { isExpanded = $0 }
        ))
        .frame(width: 300, height: 28, alignment: .leading)
        let hostingView = NSHostingView(rootView: header)
        hostingView.frame = NSRect(x: 0, y: 0, width: 300, height: 28)
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

        for eventType in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            let event = NSEvent.mouseEvent(
                with: eventType,
                location: NSPoint(x: 180, y: hostingView.bounds.midY),
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

        XCTAssertTrue(isExpanded)
    }

    func testSearchFieldShortcutsFollowTheOptionModifier() {
        XCTAssertTrue(SearchShortcutPresentation.isVisible(for: [.option]))
        XCTAssertTrue(SearchShortcutPresentation.isVisible(for: [.option, .shift]))
        XCTAssertFalse(SearchShortcutPresentation.isVisible(for: []))
        XCTAssertFalse(SearchShortcutPresentation.isVisible(for: [.command]))
    }

    func testDirectConnectionsShortcutAppearsForContextAndSticksAfterUse() {
        XCTAssertFalse(DirectConnectionsShortcutPresentation.isVisible(
            journeyOptionsAreExpanded: false,
            optionIsPressed: false,
            hasBeenUsed: false
        ))
        XCTAssertTrue(DirectConnectionsShortcutPresentation.isVisible(
            journeyOptionsAreExpanded: true,
            optionIsPressed: false,
            hasBeenUsed: false
        ))
        XCTAssertTrue(DirectConnectionsShortcutPresentation.isVisible(
            journeyOptionsAreExpanded: false,
            optionIsPressed: true,
            hasBeenUsed: false
        ))
        XCTAssertTrue(DirectConnectionsShortcutPresentation.isVisible(
            journeyOptionsAreExpanded: false,
            optionIsPressed: false,
            hasBeenUsed: true
        ))
    }

    func testSearchDateTimePresentationCombinesTheChosenDateAndTime() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let date = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026,
            month: 8,
            day: 2,
            hour: 7,
            minute: 15
        )))
        let time = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2001,
            month: 1,
            day: 1,
            hour: 16,
            minute: 45
        )))

        let combined = JourneyDateTimePresentation.combinedValue(
            date: date,
            time: time,
            calendar: calendar
        )
        let components = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: combined
        )

        XCTAssertEqual(components.year, 2026)
        XCTAssertEqual(components.month, 8)
        XCTAssertEqual(components.day, 2)
        XCTAssertEqual(components.hour, 16)
        XCTAssertEqual(components.minute, 45)
        XCTAssertEqual(components.second, 0)
        XCTAssertEqual(
            JourneyDateTimePresentation.title(
                date: date,
                time: time,
                usesCurrentDateAndTime: true,
                locale: Locale(identifier: "en_GB"),
                calendar: calendar
            ),
            AppLocalization.string("Now")
        )

        let selectedTitle = JourneyDateTimePresentation.title(
            date: date,
            time: time,
            usesCurrentDateAndTime: false,
            locale: Locale(identifier: "en_GB"),
            calendar: calendar
        )
        XCTAssertTrue(selectedTitle.contains("02/08/2026"))
        XCTAssertTrue(selectedTitle.contains("16:45"))
    }

    func testFillCurrentDateAndTimeActionsPreserveUnselectedComponents() {
        let original = serviceDate(2026, 8, 1).addingTimeInterval(21 * 60 * 60)
        let current = serviceDate(2026, 8, 2).addingTimeInterval(10 * 60 * 60)

        let connections = ConnectionsViewModel(
            client: MockIDOSClient(),
            calendarImporter: RecordingCalendarImporter()
        )
        connections.selectCurrentDateAndTime(now: original)
        connections.selectCurrentDate(now: current)
        XCTAssertEqual(connections.date, current)
        XCTAssertEqual(connections.time, original)
        XCTAssertFalse(connections.usesCurrentDateAndTime)

        connections.selectCurrentDateAndTime(now: original)
        connections.selectCurrentTime(now: current)
        XCTAssertEqual(connections.date, original)
        XCTAssertEqual(connections.time, current)
        XCTAssertFalse(connections.usesCurrentDateAndTime)

        let departures = DeparturesViewModel(client: MockIDOSClient())
        departures.selectCurrentDateAndTime(now: original)
        departures.selectCurrentDate(now: current)
        XCTAssertEqual(departures.date, current)
        XCTAssertEqual(departures.time, original)
        XCTAssertFalse(departures.usesCurrentDateAndTime)

        departures.selectCurrentDateAndTime(now: original)
        departures.selectCurrentTime(now: current)
        XCTAssertEqual(departures.date, original)
        XCTAssertEqual(departures.time, current)
        XCTAssertFalse(departures.usesCurrentDateAndTime)

        let stationTimetables = StationTimetablesViewModel(client: MockIDOSClient())
        stationTimetables.date = original
        stationTimetables.selectCurrentDate(now: current)
        XCTAssertEqual(stationTimetables.date, current)
    }

    func testEditMenuSwapSupportsConnectionAndStationTimetableRoutes() {
        let connections = ConnectionsViewModel(
            client: MockIDOSClient(),
            calendarImporter: RecordingCalendarImporter()
        )
        connections.from = "Praha"
        connections.to = "Brno"
        connections.swapEndpoints()

        XCTAssertEqual(connections.from, "Brno")
        XCTAssertEqual(connections.to, "Praha")

        let stationTimetables = StationTimetablesViewModel(client: MockIDOSClient())
        stationTimetables.from = "Výchozí zastávka"
        stationTimetables.to = "Cílová zastávka"
        stationTimetables.swapDirectionStops()

        XCTAssertEqual(stationTimetables.from, "Cílová zastávka")
        XCTAssertEqual(stationTimetables.to, "Výchozí zastávka")
    }

    func testStationTimetableDepartureLinksRequireAdvertisedCapabilities() {
        struct LimitedSource: TransitDataSource {
            let descriptor: TransitDataSourceDescriptor
        }

        func model(_ capabilities: Set<TransitDataSourceCapability>) -> StationTimetablesViewModel {
            StationTimetablesViewModel(client: LimitedSource(
                descriptor: TransitDataSourceDescriptor(
                    id: "limited",
                    displayName: "Limited Transit",
                    capabilities: capabilities
                )
            ))
        }

        let timetableOnly = model([.stationTimetables])
        XCTAssertFalse(timetableOnly.canFindDepartureResults)
        XCTAssertFalse(timetableOnly.canOpenDepartureServices)

        let departuresWithoutResolution = model([.stationTimetables, .departures])
        XCTAssertFalse(departuresWithoutResolution.canFindDepartureResults)
        XCTAssertFalse(departuresWithoutResolution.canOpenDepartureServices)

        let departures = model([
            .stationTimetables,
            .stationTimetableDepartureResolution,
            .departures,
        ])
        XCTAssertTrue(departures.canFindDepartureResults)
        XCTAssertFalse(departures.canOpenDepartureServices)

        let services = model([
            .stationTimetables,
            .stationTimetableDepartureResolution,
            .departures,
            .serviceDetails,
        ])
        XCTAssertTrue(services.canFindDepartureResults)
        XCTAssertTrue(services.canOpenDepartureServices)
    }

    func testClosedSearchDateTimePickerShowsModeWithoutEagerEditors() {
        let fixedDate = Date(timeIntervalSinceReferenceDate: 0)

        func assertClosedPicker(isArrival: Bool) {
            let hostingView = NSHostingView(rootView: JourneyDateTimePicker(
                date: .constant(fixedDate),
                time: .constant(fixedDate),
                isArrival: .constant(isArrival),
                modeLabel: "Time means",
                departureLabel: "Departure",
                arrivalLabel: "Arrival",
                usesCurrentDateAndTime: true,
                selectCurrentDateAndTime: {}
            ))
            hostingView.frame = NSRect(x: 0, y: 0, width: 240, height: 40)
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

            XCTAssertTrue(hostingView.allDescendantViews.compactMap { $0 as? NSDatePicker }.isEmpty)
            XCTAssertTrue(
                hostingView.allDescendantViews.compactMap { $0 as? NSSegmentedControl }.isEmpty
            )
            XCTAssertLessThanOrEqual(hostingView.fittingSize.height, 30)
        }

        assertClosedPicker(isArrival: false)
        assertClosedPicker(isArrival: true)
        let currentInstant = AppLocalization.string("Now").lowercased(with: .current)
        XCTAssertEqual(
            JourneyDateTimePresentation.closedTitle(
                date: fixedDate,
                time: fixedDate,
                isArrival: false,
                departureLabel: "Departure",
                arrivalLabel: "Arrival",
                usesCurrentDateAndTime: true
            ),
            "\(AppLocalization.string("Departure")) \(currentInstant)"
        )
        XCTAssertEqual(
            JourneyDateTimePresentation.closedTitle(
                date: fixedDate,
                time: fixedDate,
                isArrival: true,
                departureLabel: "Departure",
                arrivalLabel: "Arrival",
                usesCurrentDateAndTime: true
            ),
            "\(AppLocalization.string("Arrival")) \(currentInstant)"
        )
        XCTAssertEqual(SearchDatePickerLayout.buttonContentWidth, 190)
    }

    func testStationTimetableUsesTheCompactDateControlWithoutUnsupportedTime() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let date = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026,
            month: 8,
            day: 2,
            hour: 16,
            minute: 45
        )))
        let title = StationTimetableDatePresentation.title(
            date: date,
            wholeWeek: false,
            locale: Locale(identifier: "en_GB"),
            calendar: calendar
        )
        XCTAssertTrue(title.contains("02/08/2026"))
        XCTAssertFalse(title.contains("16:45"))
        let wholeWeekTitle = StationTimetableDatePresentation.title(
            date: date,
            wholeWeek: true,
            locale: Locale(identifier: "en_GB"),
            calendar: calendar
        )
        XCTAssertTrue(wholeWeekTitle.contains("02/08/2026"))
        let localizedWholeWeek = AppLocalization.string("Whole week")
        let inlineWholeWeek = String(try XCTUnwrap(localizedWholeWeek.first))
            .lowercased(with: Locale(identifier: "en_GB")) + String(localizedWholeWeek.dropFirst())
        XCTAssertEqual(wholeWeekTitle, "\(title) \(inlineWholeWeek)")
        XCTAssertFalse(wholeWeekTitle.contains("·"))

        let closedPicker = NSHostingView(rootView: StationTimetableDatePicker(
            date: .constant(date),
            wholeWeek: .constant(true)
        ))
        closedPicker.frame = NSRect(x: 0, y: 0, width: 240, height: 40)
        closedPicker.layoutSubtreeIfNeeded()
        XCTAssertTrue(closedPicker.allDescendantViews.compactMap { $0 as? NSDatePicker }.isEmpty)
        XCTAssertLessThanOrEqual(closedPicker.fittingSize.height, 30)

        let editor = NSHostingView(rootView: StationTimetableDateEditor(
            date: .constant(date),
            wholeWeek: .constant(false)
        ))
        editor.layoutSubtreeIfNeeded()
        XCTAssertEqual(editor.allDescendantViews.compactMap { $0 as? NSDatePicker }.count, 1)
    }

    func testStationTimetableScheduleHeadingUsesTheLanguageWeekdayCapitalization() {
        XCTAssertEqual(
            StationTimetableScheduleLabelPresentation.title(
                "5.8.2026 Středa",
                locale: Locale(identifier: "cs_CZ")
            ),
            "5.8.2026 středa"
        )
        XCTAssertEqual(
            StationTimetableScheduleLabelPresentation.title(
                "17.7.2026 friday",
                locale: Locale(identifier: "en_GB")
            ),
            "17.7.2026 Friday"
        )
        XCTAssertEqual(
            StationTimetableScheduleLabelPresentation.title(
                "6.8.2026 Mercredi",
                locale: Locale(identifier: "fr_FR")
            ),
            "6.8.2026 mercredi"
        )
        XCTAssertEqual(
            StationTimetableScheduleLabelPresentation.title(
                "7.8.2026 mittwoch",
                locale: Locale(identifier: "de_DE")
            ),
            "7.8.2026 Mittwoch"
        )
        XCTAssertEqual(
            StationTimetableScheduleLabelPresentation.title(
                "8.8.2026 土曜日",
                locale: Locale(identifier: "ja_JP")
            ),
            "8.8.2026 土曜日"
        )
    }

    func testStationTimetableSearchHeaderFitsTheMinimumPaddedContentWidth() {
        let model = StationTimetablesViewModel(client: MockIDOSClient())
        let layout = DetailLayout(availableWidth: KastanApp.minimumMainWindowWidth)
        let header = StationTimetableSearchHeader(
            timetable: .constant(model.timetable),
            date: .constant(model.date),
            wholeWeek: .constant(model.wholeWeek),
            usesCompactLayout: true
        )
        let hostingView = NSHostingView(rootView: header)

        hostingView.layoutSubtreeIfNeeded()

        XCTAssertLessThanOrEqual(hostingView.fittingSize.width, layout.contentWidth)
    }

    func testODISMunicipalityAndLineMatchHeaderColumnsAtCompactAndWideWidths() throws {
        func assertFieldsMatchHeaderColumns(width: CGFloat) throws -> CGFloat {
            let client = MockIDOSClient()
            let model = StationTimetablesViewModel(client: client)
            model.selectTimetable(slug: "odis")
            let hostingView = NSHostingView(rootView: StationTimetablesView(
                model: model,
                client: client,
                showsItemDetails: false,
                showsStopNoteText: false
            ).frame(width: width, height: 600))
            hostingView.frame = NSRect(x: 0, y: 0, width: width, height: 600)
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

            let descendants = hostingView.allDescendantViews
            let municipalityNames = model.municipalities.map(\.name)
            let municipalityPicker = try XCTUnwrap(
                descendants.compactMap { $0 as? NSPopUpButton }.first {
                    $0.itemTitles == municipalityNames
                }
            )
            let timetablePicker = try XCTUnwrap(
                descendants.compactMap { $0 as? NSPopUpButton }.first {
                    $0 !== municipalityPicker
                }
            )
            let lineField = try XCTUnwrap(
                descendants.compactMap { $0 as? NSTextField }.first {
                    $0.placeholderString == AppLocalization.string("Line number or name")
                }
            )
            let timetableFrame = hostingView.convert(timetablePicker.bounds, from: timetablePicker)
            let municipalityFrame = hostingView.convert(
                municipalityPicker.bounds,
                from: municipalityPicker
            )
            let lineFrame = hostingView.convert(lineField.bounds, from: lineField)
            let layout = DetailLayout(availableWidth: width)
            let dateControl = NSHostingView(rootView: StationTimetableDateSearchControl(
                date: .constant(model.date),
                wholeWeek: .constant(model.wholeWeek)
            ))
            dateControl.layoutSubtreeIfNeeded()

            XCTAssertEqual(model.municipalities.count, 12)
            XCTAssertEqual(model.municipality?.name, "Ostrava")
            XCTAssertEqual(municipalityFrame.minX, timetableFrame.minX, accuracy: 1)
            XCTAssertEqual(municipalityFrame.width, timetableFrame.width, accuracy: 1)
            XCTAssertEqual(lineFrame.width, dateControl.fittingSize.width, accuracy: 1)
            XCTAssertEqual(
                lineFrame.maxX,
                width - layout.horizontalPadding,
                accuracy: 1
            )
            XCTAssertLessThan(municipalityFrame.maxX, lineFrame.minX)
            XCTAssertEqual(municipalityFrame.midY, lineFrame.midY, accuracy: 2)

            let municipalityIndex = try XCTUnwrap(
                model.municipalities.firstIndex(where: { $0.name == "Havířov" })
            )
            municipalityPicker.selectItem(at: municipalityIndex)
            municipalityPicker.sendAction(
                municipalityPicker.action,
                to: municipalityPicker.target
            )
            XCTAssertEqual(model.municipality?.name, "Havířov")
            return lineFrame.width
        }

        let compactLineWidth = try assertFieldsMatchHeaderColumns(
            width: KastanApp.minimumMainWindowWidth
        )
        let wideLineWidth = try assertFieldsMatchHeaderColumns(width: 900)
        XCTAssertEqual(compactLineWidth, wideLineWidth, accuracy: 1)
    }

    func testIREDOOffersItsPublishedMunicipalityPicker() throws {
        let client = MockIDOSClient()
        let model = StationTimetablesViewModel(client: client)
        model.selectTimetable(slug: "iredo")
        let municipalityNames = [
            "Dvůr Králové nad Labem", "Chrudim", "Náchod", "Přelouč",
            "Rychnov nad Kněžnou", "Týniště nad Orlicí", "Vrchlabí",
        ]
        let width = KastanApp.minimumMainWindowWidth
        let hostingView = NSHostingView(rootView: StationTimetablesView(
            model: model,
            client: client,
            showsItemDetails: false,
            showsStopNoteText: false
        ).frame(width: width, height: 600))
        hostingView.frame = NSRect(x: 0, y: 0, width: width, height: 600)
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

        XCTAssertEqual(model.municipalities.map(\.name), municipalityNames)
        XCTAssertEqual(model.municipality?.name, "Dvůr Králové nad Labem")
        let municipalityPicker = try XCTUnwrap(
            hostingView.allDescendantViews.compactMap { $0 as? NSPopUpButton }.first {
                $0.itemTitles == municipalityNames
            }
        )
        let chrudimIndex = try XCTUnwrap(
            model.municipalities.firstIndex(where: { $0.name == "Chrudim" })
        )

        municipalityPicker.selectItem(at: chrudimIndex)
        municipalityPicker.sendAction(
            municipalityPicker.action,
            to: municipalityPicker.target
        )

        XCTAssertEqual(model.municipality?.name, "Chrudim")
    }

    func testIDOLOffersItsPublishedMunicipalityPicker() throws {
        let client = MockIDOSClient()
        let model = StationTimetablesViewModel(client: client)
        model.selectTimetable(slug: "idol")
        let municipalityNames = [
            "Česká Lípa", "Jablonec nad Nisou", "Liberec", "Turnov",
        ]
        let width = KastanApp.minimumMainWindowWidth
        let hostingView = NSHostingView(rootView: StationTimetablesView(
            model: model,
            client: client,
            showsItemDetails: false,
            showsStopNoteText: false
        ).frame(width: width, height: 600))
        hostingView.frame = NSRect(x: 0, y: 0, width: width, height: 600)
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

        XCTAssertEqual(model.municipalities.map(\.name), municipalityNames)
        XCTAssertEqual(model.municipality?.name, "Česká Lípa")
        let municipalityPicker = try XCTUnwrap(
            hostingView.allDescendantViews.compactMap { $0 as? NSPopUpButton }.first {
                $0.itemTitles == municipalityNames
            }
        )
        let liberecIndex = try XCTUnwrap(
            model.municipalities.firstIndex(where: { $0.name == "Liberec" })
        )

        municipalityPicker.selectItem(at: liberecIndex)
        municipalityPicker.sendAction(
            municipalityPicker.action,
            to: municipalityPicker.target
        )

        XCTAssertEqual(model.municipality?.name, "Liberec")
    }

    func testAdditionalIntegratedSystemsOfferTheirPublishedMunicipalities() {
        let cases: [(slug: String, names: [String], defaultName: String)] = [
            (
                "idsok",
                ["Hranice", "Olomouc", "Prostějov", "Přerov", "Šumperk", "Zábřeh"],
                "Hranice"
            ),
            (
                "duk",
                [
                    "Bílina", "Děčín", "Chomutov", "Klášterec nad Ohří", "Most-Litvínov",
                    "Roudnice nad Labem", "Teplice", "Ústí nad Labem", "Varnsdorf",
                ],
                "Ústí nad Labem"
            ),
            (
                "idpk",
                ["Domažlice", "Klatovy", "Plzeň", "Rokycany", "Stříbro", "Tachov"],
                "Plzeň"
            ),
            ("idzk", ["Uherské Hradiště", "Vsetín"], "Uherské Hradiště"),
            (
                "ideska",
                [
                    "České Budějovice", "Český Krumlov", "Jindřichův Hradec", "Milevsko",
                    "Písek", "Strakonice", "Tábor", "Vimperk",
                ],
                "České Budějovice"
            ),
        ]
        let model = StationTimetablesViewModel(client: MockIDOSClient())

        for item in cases {
            model.selectTimetable(slug: item.slug)

            XCTAssertEqual(model.municipalities.map(\.name), item.names, item.slug)
            XCTAssertEqual(model.municipality?.name, item.defaultName, item.slug)
        }
    }

    func testStationTimetableSearchHeaderMatchesJourneyHeaderHeight() {
        let fixedDate = Date(timeIntervalSinceReferenceDate: 0)
        let stationHeader = NSHostingView(rootView: StationTimetableSearchHeader(
            timetable: .constant(AppTimetableDefaults.search),
            date: .constant(fixedDate),
            wholeWeek: .constant(false),
            usesCompactLayout: true
        ))
        let journeyHeader = NSHostingView(rootView: JourneySearchHeader(
            timetable: .constant(AppTimetableDefaults.search),
            date: .constant(fixedDate),
            time: .constant(fixedDate),
            isArrival: .constant(false),
            modeLabel: "Time means",
            departureLabel: "Departure",
            arrivalLabel: "Arrival",
            usesCurrentDateAndTime: true,
            selectCurrentDateAndTime: {},
            showsCurrentDateAndTimeShortcut: false,
            usesCompactLayout: true
        ))

        stationHeader.layoutSubtreeIfNeeded()
        journeyHeader.layoutSubtreeIfNeeded()

        XCTAssertEqual(
            stationHeader.fittingSize.height,
            journeyHeader.fittingSize.height,
            accuracy: 0.5
        )
    }

    func testTimeModeHeadsContentSizedDateTimePopoverWithoutActions() throws {
        let fixedDate = Date(timeIntervalSinceReferenceDate: 0)
        var isArrival = false
        let editor = JourneyDateTimeEditor(
            date: .constant(fixedDate),
            time: .constant(fixedDate),
            isArrival: Binding(
                get: { isArrival },
                set: { isArrival = $0 }
            ),
            modeLabel: "Time means",
            departureLabel: "Departure",
            arrivalLabel: "Arrival"
        )
        let hostingView = NSHostingView(rootView: editor)
        hostingView.frame = NSRect(x: 0, y: 0, width: 360, height: 240)
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

        XCTAssertLessThanOrEqual(hostingView.fittingSize.width, 200)
        let descendants = hostingView.allDescendantViews
        XCTAssertEqual(descendants.compactMap { $0 as? NSDatePicker }.count, 2)
        let visibleLabels = descendants.compactMap { $0 as? NSTextField }.map(\.stringValue)
        XCTAssertFalse(visibleLabels.contains(AppLocalization.string("Date and time")))
        XCTAssertFalse(visibleLabels.contains(AppLocalization.string("Time means")))
        XCTAssertFalse(visibleLabels.contains(AppLocalization.string("Now")))
        XCTAssertFalse(visibleLabels.contains(AppLocalization.string("Done")))
        let buttonTitles = descendants.compactMap { $0 as? NSButton }.map(\.title)
        XCTAssertFalse(buttonTitles.contains(AppLocalization.string("Now")))
        XCTAssertFalse(buttonTitles.contains(AppLocalization.string("Done")))

        let mode = try XCTUnwrap(descendants.compactMap { $0 as? NSSegmentedControl }.first)
        XCTAssertEqual(mode.segmentCount, 2)
        XCTAssertEqual(mode.label(forSegment: 0), AppLocalization.string("Departure"))
        XCTAssertEqual(mode.label(forSegment: 1), AppLocalization.string("Arrival"))

        mode.selectedSegment = 1
        mode.sendAction(mode.action, to: mode.target)
        XCTAssertTrue(isArrival)
    }

    func testDateTimeNowShortcutDoesNotResizeItsHeader() {
        let hiddenHeader = NSHostingView(rootView: SearchFieldHeader(
            title: "Date and time",
            shortcutTitle: "Now",
            showsShortcut: false,
            action: {}
        ))
        let visibleHeader = NSHostingView(rootView: SearchFieldHeader(
            title: "Date and time",
            shortcutTitle: "Now",
            showsShortcut: true,
            action: {}
        ))

        XCTAssertEqual(hiddenHeader.fittingSize.width, visibleHeader.fittingSize.width, accuracy: 0.5)
        XCTAssertEqual(hiddenHeader.fittingSize.height, visibleHeader.fittingSize.height, accuracy: 0.5)
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

    func testFreshConnectionSearchReplacesExistingResultsWithProgress() {
        XCTAssertEqual(
            ConnectionResultsPresentation.resolve(
                isSearching: true,
                hasCompletedSearch: false,
                hasConnections: true,
                hasError: false
            ),
            .searching
        )
        XCTAssertEqual(
            ConnectionResultsPresentation.resolve(
                isSearching: false,
                hasCompletedSearch: true,
                hasConnections: true,
                hasError: false
            ),
            .connections
        )
        XCTAssertEqual(
            ConnectionResultsPresentation.resolve(
                isSearching: false,
                hasCompletedSearch: false,
                hasConnections: false,
                hasError: false
            ),
            .empty
        )
        XCTAssertEqual(
            ConnectionResultsPresentation.resolve(
                isSearching: false,
                hasCompletedSearch: true,
                hasConnections: false,
                hasError: false
            ),
            .noResults
        )
    }

    func testConnectionNoResultsGuidanceIsLocalized() throws {
        let czech = try XCTUnwrap(localizationBundle(languageCode: "cs"))
        let english = try XCTUnwrap(localizationBundle(languageCode: "en"))
        let keys = ["No connections found", "Try a different time, route, or timetable."]

        XCTAssertEqual(
            keys.map { czech.localizedString(forKey: $0, value: nil, table: nil) },
            ["Žádné spojení nenalezeno", "Zkuste jiný čas, trasu nebo jízdní řád."]
        )
        XCTAssertEqual(
            keys.map { english.localizedString(forKey: $0, value: nil, table: nil) },
            keys
        )
    }

    func testFastestConnectionBadgesMirrorCLIDurationComparison() {
        let connections = [
            connection(id: "slower", duration: "3 h 40 min"),
            connection(id: "fastest-hours", duration: "3 hod 15 min"),
            connection(id: "fastest-minutes", duration: "195 min"),
            connection(id: "unknown", duration: "unknown"),
        ]

        XCTAssertEqual(
            ConnectionResultsPresentation.shortestConnectionIDs(in: connections),
            Set(["fastest-hours", "fastest-minutes"])
        )
        XCTAssertTrue(
            ConnectionResultsPresentation.shortestConnectionIDs(
                in: [connection(id: "unknown", duration: "unknown")]
            ).isEmpty
        )
    }

    func testConnectionBadgeTitlesUseConsistentSemanticEmoji() throws {
        let english = try XCTUnwrap(localizationBundle(languageCode: "en"))
        let czech = try XCTUnwrap(localizationBundle(languageCode: "cs"))

        XCTAssertEqual(ConnectionBadgeKind.direct.symbol, "➡️")
        XCTAssertEqual(ConnectionBadgeKind.shortest.symbol, "⚡")
        XCTAssertEqual(ConnectionBadgeKind.direct.label(bundle: czech), "Přímé")
        XCTAssertEqual(ConnectionBadgeKind.shortest.label(bundle: czech), "Nejrychlejší")
        XCTAssertEqual(ConnectionBadgePresentation.direct(bundle: english), "➡️ Direct")
        XCTAssertEqual(ConnectionBadgePresentation.shortest(bundle: english), "⚡ Shortest")
        XCTAssertEqual(ConnectionBadgePresentation.direct(bundle: czech), "➡️ Přímé")
        XCTAssertEqual(ConnectionBadgePresentation.shortest(bundle: czech), "⚡ Nejrychlejší")
    }

    func testConnectionBadgesFollowTheGlobalVisibilityPreference() {
        XCTAssertEqual(
            ConnectionBadgePresentation.visibleKinds(
                showsBadges: false,
                isDirect: true,
                isShortest: true
            ),
            []
        )
        XCTAssertEqual(
            ConnectionBadgePresentation.visibleKinds(
                showsBadges: true,
                isDirect: true,
                isShortest: true
            ),
            [.direct, .shortest]
        )
        XCTAssertEqual(
            ConnectionBadgePresentation.visibleKinds(
                showsBadges: true,
                isDirect: false,
                isShortest: true
            ),
            [.shortest]
        )
    }

    func testItemDetailsFollowTheGlobalVisibilityPreference() {
        XCTAssertNil(
            ResultMetadata.visible(
                showsDetails: false,
                "Czech Railways",
                "Delay 12 min",
                "Zone P",
                "Track 2",
                "0 km"
            )
        )
        XCTAssertEqual(
            ResultMetadata.visible(
                showsDetails: true,
                "Czech Railways",
                "Delay 12 min",
                "Zone P",
                "Track 2",
                "0 km"
            ),
            "Czech Railways · Delay 12 min · Zone P · Track 2 · 0 km"
        )
    }

    func testCompactStopDetailsUseRawValuesAndLocalizedHelpInSymbolMode() throws {
        let czech = try XCTUnwrap(localizationBundle(languageCode: "cs"))
        let english = try XCTUnwrap(localizationBundle(languageCode: "en"))
        let czechValues = ResultMetadata.compactStation(
            tariffZone: " 50, 51 ",
            platform: "2",
            track: "3",
            platformTrack: " 2 / 3 ",
            bundle: czech
        )
        XCTAssertEqual(
            czechValues,
            [
                ResultMetadata.CompactItem(
                    text: "50,51",
                    helpText: "zóny 50 a\u{00A0}51"
                ),
                ResultMetadata.CompactItem(
                    text: "2/3",
                    helpText: "nástupiště 2, kolej 3"
                ),
            ]
        )
        XCTAssertEqual(
            ResultMetadata.compactStation(
                tariffZone: "50",
                platform: "2",
                track: "3",
                bundle: czech
            ),
            [
                ResultMetadata.CompactItem(text: "50", helpText: "zóna 50"),
                ResultMetadata.CompactItem(
                    text: "2/3",
                    helpText: "nástupiště 2, kolej 3"
                ),
            ]
        )
        XCTAssertEqual(
            ResultMetadata.compactStationTimetable(
                tariffZone: "50,51",
                platform: "1",
                bundle: czech
            ),
            [
                ResultMetadata.CompactItem(
                    text: "50,51",
                    helpText: "zóny 50 a\u{00A0}51"
                ),
                ResultMetadata.CompactItem(text: "1", helpText: "stanoviště 1"),
            ]
        )
        XCTAssertEqual(
            ResultMetadata.compactStation(
                tariffZone: "50,51",
                platform: nil,
                platformTrack: "2/3",
                bundle: english
            ),
            [
                ResultMetadata.CompactItem(
                    text: "50,51",
                    helpText: "Zones 50 and 51"
                ),
                ResultMetadata.CompactItem(
                    text: "2/3",
                    helpText: "Platform 2, track 3"
                ),
            ]
        )

        XCTAssertEqual(
            ResultMetadata.compactStopValues(
                showsDetails: true,
                showsSymbolsAsText: false,
                czechValues
            ),
            czechValues
        )
        XCTAssertTrue(ResultMetadata.compactStopValues(
            showsDetails: false,
            showsSymbolsAsText: false,
            czechValues
        ).isEmpty)
        XCTAssertTrue(ResultMetadata.compactStopValues(
            showsDetails: true,
            showsSymbolsAsText: true,
            czechValues
        ).isEmpty)
    }

    func testConnectionLegDetailsOmitTariffZonesAndTheCompactDeparturePlatform() throws {
        let czech = try XCTUnwrap(localizationBundle(languageCode: "cs"))
        let leg = IDOSConnectionLeg(
            name: "R 879 Svitava",
            transportMode: .train,
            departureTime: "12:00",
            fromStation: "Praha hl.n.",
            fromTariffZone: "ambiguous-from-zone",
            fromPlatform: "4",
            arrivalTime: "14:30",
            toStation: "Brno hl.n.",
            toTariffZone: "ambiguous-to-zone",
            carrier: "Czech Railways",
            delay: "Departure tends to be on time"
        )

        let metadata = ResultMetadata.connectionLeg(leg, showsDetails: true)

        XCTAssertEqual(
            metadata,
            [
                "Czech Railways",
                AppLocalization.string("Departure tends to be on time"),
            ].joined(separator: " · ")
        )
        XCTAssertFalse(metadata?.contains("ambiguous-from-zone") ?? true)
        XCTAssertFalse(metadata?.contains("ambiguous-to-zone") ?? true)
        XCTAssertEqual(
            ResultMetadata.compactConnectionPlatform(leg, bundle: czech),
            ResultMetadata.CompactItem(text: "4", helpText: "nástupiště 4")
        )
        XCTAssertNil(ResultMetadata.connectionLeg(leg, showsDetails: false))
    }

    func testConnectionLegPlatformsOfferCompleteLocalizedTextAndCompactFallback() throws {
        let czech = try XCTUnwrap(localizationBundle(languageCode: "cs"))
        let train = IDOSConnectionLeg(
            name: "S6",
            transportMode: .train,
            departureTime: "18:01",
            fromStation: "Frýdek-Místek",
            fromPlatform: " 2 / 3 ",
            arrivalTime: "18:29",
            toStation: "Ostrava-Stodolní"
        )
        var bus = train
        bus.transportMode = .bus
        bus.fromPlatform = "2/3"

        XCTAssertNil(ResultMetadata.connectionLeg(train, showsDetails: true))
        XCTAssertNil(ResultMetadata.connectionLeg(bus, showsDetails: true))
        XCTAssertEqual(
            ResultMetadata.compactConnectionPlatform(train, bundle: czech),
            ResultMetadata.CompactItem(
                text: "2/3",
                helpText: "nástupiště 2, kolej 3"
            )
        )
        XCTAssertEqual(
            ResultMetadata.compactConnectionPlatform(bus, bundle: czech),
            ResultMetadata.CompactItem(text: "2/3", helpText: "nástupiště 2/3")
        )
        XCTAssertEqual(
            ResultMetadata.platformTrackDescription("2/3/4"),
            AppLocalization.string("platform/track %@", "2/3/4")
        )
        XCTAssertEqual(
            ResultMetadata.station(
                tariffZone: nil,
                platform: "2",
                track: "3",
                platformTrack: "2/3"
            ),
            [
                AppLocalization.string("Platform %@", "2"),
                AppLocalization.string("track %@", "3"),
            ].joined(separator: " ")
        )
        XCTAssertEqual(
            ResultMetadata.station(
                tariffZone: nil,
                platform: "2",
                track: "3"
            ),
            [
                AppLocalization.string("Platform %@", "2"),
                AppLocalization.string("track %@", "3"),
            ].joined(separator: " ")
        )
    }

    func testAdaptiveConnectionPlatformPrefersFullTextAndKeepsAOneLineFallback() {
        let value = ResultMetadata.CompactItem(
            text: "2/3",
            helpText: "nástupiště 2, kolej 3"
        )
        let preferred = NSHostingView(
            rootView: AdaptiveConnectionPlatform(value: value)
                .fixedSize()
        )
        let constrained = NSHostingView(
            rootView: AdaptiveConnectionPlatform(value: value)
                .frame(width: 30)
        )
        let fullLabel = NSHostingView(
            rootView: Text(verbatim: value.helpText)
                .font(.caption)
                .fixedSize()
        )
        let compactLabel = NSHostingView(
            rootView: Text(verbatim: value.text)
                .font(.caption)
                .fixedSize()
        )

        XCTAssertEqual(
            preferred.fittingSize.width,
            fullLabel.fittingSize.width,
            accuracy: 0.5
        )
        XCTAssertGreaterThan(fullLabel.fittingSize.width, 30)
        XCTAssertLessThan(compactLabel.fittingSize.width, 30)
        XCTAssertEqual(
            constrained.fittingSize.height,
            preferred.fittingSize.height,
            accuracy: 0.5
        )
        XCTAssertLessThan(constrained.fittingSize.height, 24)
    }

    func testServiceInformationUsesSymbolsUntilTheSharedTextPreferenceIsEnabled() throws {
        let information = [
            IDOSServiceInformation(text: "Train also consists of 1st class coaches"),
            IDOSServiceInformation(text: "Carriage with a wireless internet connection"),
            IDOSServiceInformation(text: "Carriage of registered luggage (until full capacity)"),
            IDOSServiceInformation(text: "spoj je obsluhován nízkopodlažním vozidlem"),
        ]
        let presentation = ServiceInformationPresentation(values: information)

        XCTAssertEqual(
            presentation.content(showsText: SymbolTextPreference.defaultValue),
            "1️⃣ 🛜 🚲 ♿"
        )
        XCTAssertEqual(
            presentation.content(showsText: true),
            information.map(\.text).joined(separator: " · ")
        )
        XCTAssertEqual(presentation.accessibilityLabel, information.map(\.text).joined(separator: ". "))
        XCTAssertEqual(presentation.helpText, information.map(\.text).joined(separator: "\n"))

        let compactView = NSHostingView(
            rootView: ServiceInformationSummary(values: information, showsText: false)
        )
        compactView.frame = NSRect(x: 0, y: 0, width: 240, height: 40)
        compactView.layoutSubtreeIfNeeded()
        XCTAssertEqual(
            compactView.allDescendantViews.compactMap { $0 as? OptionClickCaptureView }.count,
            information.count
        )

        let accessibilityInformation = IDOSServiceInformation(text: "bezbariérový spoj")
        let rule = ServiceInformationRulePresentation(information: accessibilityInformation)
        let czech = try XCTUnwrap(localizationBundle(languageCode: "cs"))
        let english = try XCTUnwrap(localizationBundle(languageCode: "en"))
        XCTAssertEqual(
            rule.explanation(bundle: czech),
            "Použité pravidlo: obsahuje „bezbarierovy spoj“."
        )
        XCTAssertEqual(
            rule.explanation(bundle: english),
            "Matched rule: contains “bezbarierovy spoj”."
        )
    }

    func testStopNotesUseSymbolsUntilTheSharedTextPreferenceIsEnabled() throws {
        let notes = [
            "zastávka na znamení",
            "wheelchair accessible stop",
            "železniční stanice",
            "přestup na Metro",
            "Traffic restrictions",
            "Board using the front door",
        ]

        let compact = StopNotePresentation(
            notes: notes,
            showsText: SymbolTextPreference.defaultValue
        )
        XCTAssertEqual(
            compact.symbols.map(\.emoji),
            ["🔔", "♿", "🚉", "🚇", "🚧"]
        )
        XCTAssertEqual(compact.symbols.map(\.note), Array(notes.prefix(5)))
        XCTAssertEqual(
            compact.symbols.map(\.matchedRule),
            [
                "na znameni",
                "wheelchair accessible",
                "zeleznicni stanice",
                "metro",
                "traffic restriction",
            ]
        )
        XCTAssertEqual(compact.textNotes, ["Board using the front door"])

        let signalSymbol = try XCTUnwrap(compact.symbols.first)
        let czech = try XCTUnwrap(localizationBundle(languageCode: "cs"))
        let english = try XCTUnwrap(localizationBundle(languageCode: "en"))
        XCTAssertEqual(
            signalSymbol.ruleExplanation(bundle: czech),
            "Použité pravidlo: obsahuje „na znameni“."
        )
        XCTAssertEqual(
            signalSymbol.ruleExplanation(bundle: english),
            "Matched rule: contains “na znameni”."
        )

        let textual = StopNotePresentation(notes: notes, showsText: true)
        XCTAssertTrue(textual.symbols.isEmpty)
        XCTAssertEqual(textual.textNotes, notes)
    }

    func testRenderedStopNoteOptionClickOpensRulePopover() throws {
        let symbol = try XCTUnwrap(
            StopNotePresentation(notes: ["zastávka na znamení"], showsText: false).symbols.first
        )
        let hostingView = NSHostingView(
            rootView: StopNoteSymbols(values: [symbol])
        )
        hostingView.frame = NSRect(x: 0, y: 0, width: 120, height: 40)
        let window = NSWindow(
            contentRect: hostingView.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.contentView = hostingView
        window.makeKeyAndOrderFront(nil)
        defer {
            window.childWindows?.forEach { $0.close() }
            window.orderOut(nil)
        }
        hostingView.layoutSubtreeIfNeeded()
        let clickView = try XCTUnwrap(
            hostingView.allDescendantViews.compactMap { $0 as? OptionClickCaptureView }.first
        )
        let clickLocation = clickView.convert(
            NSPoint(x: clickView.bounds.midX, y: clickView.bounds.midY),
            to: nil
        )
        let ordinaryClick = try XCTUnwrap(NSEvent.mouseEvent(
            with: .leftMouseDown,
            location: clickLocation,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: window.windowNumber,
            context: nil,
            eventNumber: 1,
            clickCount: 1,
            pressure: 1
        ))
        let optionClick = try XCTUnwrap(NSEvent.mouseEvent(
            with: .leftMouseDown,
            location: clickLocation,
            modifierFlags: [.option],
            timestamp: 0,
            windowNumber: window.windowNumber,
            context: nil,
            eventNumber: 2,
            clickCount: 1,
            pressure: 1
        ))

        XCTAssertFalse(OptionClickCaptureView.handles(ordinaryClick))
        XCTAssertTrue(OptionClickCaptureView.handles(optionClick))
        XCTAssertGreaterThan(clickView.frame.width, 0)
        XCTAssertGreaterThan(clickView.frame.height, 0)
        XCTAssertFalse(clickView.captures(ordinaryClick))
        XCTAssertTrue(clickView.captures(optionClick))
        XCTAssertNil(clickView.hitTest(NSPoint(x: 1, y: 1)))

        XCTAssertIdentical(clickView.process(ordinaryClick), ordinaryClick)
        XCTAssertTrue(window.childWindows?.isEmpty ?? true)

        XCTAssertNil(clickView.process(optionClick))
        for _ in 0..<100 where window.childWindows?.isEmpty ?? true {
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
        }
        XCTAssertFalse(window.childWindows?.isEmpty ?? true)
    }

    func testLinkedServiceInformationPopoverUsesTheOptionClickLocationWithoutConsumingIt() throws {
        var capturedAnchor: UnitPoint?
        let anchorView = OptionClickCaptureView(consumesEvent: false) { anchor in
            capturedAnchor = anchor
        }
        anchorView.frame = NSRect(x: 0, y: 0, width: 200, height: 100)
        let window = NSWindow(
            contentRect: anchorView.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.contentView = anchorView
        window.makeKeyAndOrderFront(nil)
        defer { window.orderOut(nil) }

        let localClick = NSPoint(x: 30, y: 25)
        let click = try XCTUnwrap(NSEvent.mouseEvent(
            with: .leftMouseDown,
            location: anchorView.convert(localClick, to: nil),
            modifierFlags: [.option],
            timestamp: 0,
            windowNumber: window.windowNumber,
            context: nil,
            eventNumber: 1,
            clickCount: 1,
            pressure: 1
        ))

        XCTAssertIdentical(anchorView.process(click), click)
        let anchor = try XCTUnwrap(capturedAnchor)
        XCTAssertEqual(anchor.x, 0.15, accuracy: 0.000_001)
        XCTAssertEqual(anchor.y, 0.25, accuracy: 0.000_001)
    }

    func testRenderedServiceStopAlignsItsMarkerAndTitleWithoutDetails() throws {
        let row = ServiceStopRow(
            stop: IDOSServiceStop(name: "Ostrava střed", departureTime: "15:24"),
            isFirst: true,
            isLast: true,
            hasHighlight: false,
            isHighlighted: false,
            isHighlightBoundary: false,
            topIsHighlighted: false,
            bottomIsHighlighted: false,
            highlightedColor: .blue,
            showsItemDetails: false,
            showsStopNoteText: false
        )
        let hostingView = NSHostingView(
            rootView: row
                .frame(width: 320)
                .background(Color.white)
                .environment(\.colorScheme, .light)
        )
        hostingView.frame = NSRect(origin: .zero, size: hostingView.fittingSize)
        hostingView.layoutSubtreeIfNeeded()

        let bitmap = try XCTUnwrap(
            hostingView.bitmapImageRepForCachingDisplay(in: hostingView.bounds)
        )
        hostingView.cacheDisplay(in: hostingView.bounds, to: bitmap)
        let scale = CGFloat(bitmap.pixelsWide) / hostingView.bounds.width
        let markerBounds = try XCTUnwrap(
            inkBounds(
                in: bitmap,
                xRange: Int(8 * scale)..<Int(30 * scale),
                maximumBrightness: 0.9
            )
        )
        let titleBounds = try XCTUnwrap(
            inkBounds(
                in: bitmap,
                xRange: Int(34 * scale)..<Int(220 * scale),
                maximumBrightness: 0.6
            )
        )
        let completeInkBounds = try XCTUnwrap(
            inkBounds(
                in: bitmap,
                xRange: 0..<bitmap.pixelsWide,
                maximumBrightness: 0.9
            )
        )

        XCTAssertEqual(markerBounds.midY, titleBounds.midY, accuracy: 2 * scale)
        XCTAssertGreaterThanOrEqual(
            completeInkBounds.minX / scale,
            ServiceStopTimelineLayout.rowHorizontalPadding - 2
        )
        XCTAssertGreaterThanOrEqual(
            CGFloat(bitmap.pixelsWide - 1) / scale - completeInkBounds.maxX / scale,
            ServiceStopTimelineLayout.rowHorizontalPadding - 2
        )
        XCTAssertGreaterThanOrEqual(completeInkBounds.minY / scale, 4)
        XCTAssertGreaterThanOrEqual(
            CGFloat(bitmap.pixelsHigh - 1) / scale - completeInkBounds.maxY / scale,
            4
        )
    }

    func testServiceStopDetailsMoveInlineWhileSymbolsRemainCompact() {
        let stop = IDOSServiceStop(
            name: "Praha hl.n.",
            tariffZone: "P,0,B",
            platformTrack: "2/3"
        )
        func renderedHeight(showsDetails: Bool, showsSymbolsAsText: Bool) -> CGFloat {
            let row = ServiceStopRow(
                stop: stop,
                isFirst: true,
                isLast: true,
                hasHighlight: false,
                isHighlighted: false,
                isHighlightBoundary: false,
                topIsHighlighted: false,
                bottomIsHighlighted: false,
                highlightedColor: .blue,
                showsItemDetails: showsDetails,
                showsStopNoteText: showsSymbolsAsText
            )
            return NSHostingView(rootView: row.frame(width: 500)).fittingSize.height
        }

        let hiddenHeight = renderedHeight(showsDetails: false, showsSymbolsAsText: false)
        let compactHeight = renderedHeight(showsDetails: true, showsSymbolsAsText: false)
        let expandedHeight = renderedHeight(showsDetails: true, showsSymbolsAsText: true)

        XCTAssertEqual(compactHeight, hiddenHeight, accuracy: 1)
        XCTAssertGreaterThan(expandedHeight, compactHeight)
    }

    func testAdaptiveConnectionBadgeStaysOneLineAtCompactWidth() throws {
        let czech = try XCTUnwrap(localizationBundle(languageCode: "cs"))
        let full = NSHostingView(
            rootView: AdaptiveConnectionBadge(kind: .shortest, bundle: czech)
                .frame(width: 130)
        )
        let compact = NSHostingView(
            rootView: AdaptiveConnectionBadge(kind: .shortest, bundle: czech)
                .frame(width: 32)
        )

        XCTAssertEqual(compact.fittingSize.height, full.fittingSize.height, accuracy: 0.5)
        XCTAssertLessThan(compact.fittingSize.height, 30)
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

    func testSearchModesFollowTheActiveDataSourceCapabilities() {
        let descriptor = TransitDataSourceDescriptor(
            id: "limited",
            displayName: "Limited Transit",
            capabilities: [.departures, .stationTimetables]
        )

        XCTAssertEqual(
            AppSection.available(for: descriptor),
            [.departures, .stationTimetables]
        )
    }

    func testMainWindowSceneValueKeepsSameProviderWindowsDistinctAndRestorable() throws {
        let first = MainWindowSceneValue(
            id: UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!,
            dataSourceID: .idos
        )
        let second = MainWindowSceneValue(
            id: UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!,
            dataSourceID: .idos
        )

        XCTAssertNotEqual(first, second)
        XCTAssertEqual(first.dataSourceID, second.dataSourceID)
        XCTAssertEqual(
            try JSONDecoder().decode(
                MainWindowSceneValue.self,
                from: JSONEncoder().encode(first)
            ),
            first
        )
    }

    func testLastClosedMainWindowDataSourcePersistsMockAndRejectsRemovedSources() throws {
        let suiteName = "cz.glutexo.kastan.tests.last-closed.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.removePersistentDomain(forName: suiteName)

        let preference = LastClosedMainWindowDataSource(defaults: defaults)
        XCTAssertEqual(
            preference.resolvedDataSourceID(in: .builtIn),
            TransitDataSourceID.idos
        )

        preference.remember(.mock)
        XCTAssertEqual(preference.dataSourceID, .mock)
        XCTAssertEqual(
            LastClosedMainWindowDataSource(defaults: defaults)
                .resolvedDataSourceID(in: .builtIn),
            TransitDataSourceID.mock
        )

        defaults.set("removed-provider", forKey: LastClosedMainWindowDataSource.storageKey)
        XCTAssertEqual(
            LastClosedMainWindowDataSource(defaults: defaults)
                .resolvedDataSourceID(in: .builtIn),
            TransitDataSourceID.idos
        )
    }

    func testMainWindowCloseObserverRecordsOnlyItsWindowAtActualCloseTime() {
        let observedWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 240),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        let otherWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 240),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        var currentDataSourceID = TransitDataSourceID.idos
        var recordedDataSourceIDs: [TransitDataSourceID] = []
        let coordinator = MainWindowCloseObserver.Coordinator {
            recordedDataSourceIDs.append(currentDataSourceID)
        }
        coordinator.install(on: observedWindow)

        NotificationCenter.default.post(
            name: NSWindow.willCloseNotification,
            object: otherWindow
        )
        XCTAssertTrue(recordedDataSourceIDs.isEmpty)

        currentDataSourceID = .mock
        NotificationCenter.default.post(
            name: NSWindow.willCloseNotification,
            object: observedWindow
        )
        XCTAssertEqual(recordedDataSourceIDs, [.mock])

        coordinator.uninstall()
        NotificationCenter.default.post(
            name: NSWindow.willCloseNotification,
            object: observedWindow
        )
        XCTAssertEqual(recordedDataSourceIDs, [.mock])
    }

    func testWindowCommandPolicyCountsOnlyRegularSourcesAndKeepsShortcutsRegular() throws {
        let idos = AppSourceSelectionTestSource(
            id: .idos,
            name: "IDOS",
            timetableIdentifier: "idos",
            capabilities: [.timetables, .connections]
        )
        let municipal = AppSourceSelectionTestSource(
            id: "municipal",
            name: "Municipal Transit",
            timetableIdentifier: "municipal",
            capabilities: [.timetables, .departures]
        )
        let mock = AppSourceSelectionTestSource(
            id: .mock,
            name: "Kaštan Mock",
            timetableIdentifier: "mock",
            capabilities: [.timetables, .connections]
        )
        let singleRegularRegistry = try TransitDataSourceRegistry(
            dataSources: [idos],
            defaultDataSourceID: .idos,
            explicitDataSources: [mock]
        )
        let multipleRegularRegistry = try TransitDataSourceRegistry(
            dataSources: [municipal, idos],
            defaultDataSourceID: .idos,
            explicitDataSources: [mock]
        )
        let singlePolicy = AppWindowCommandPolicy(registry: singleRegularRegistry)
        let multiplePolicy = AppWindowCommandPolicy(registry: multipleRegularRegistry)

        XCTAssertFalse(singlePolicy.usesProviderSubmenus)
        XCTAssertEqual(singlePolicy.regularDataSources.map(\.id), [.idos])
        XCTAssertEqual(singlePolicy.mockDataSource?.id, .mock)
        XCTAssertTrue(multiplePolicy.usesProviderSubmenus)
        XCTAssertEqual(
            multiplePolicy.preferredRegularDataSourceID(
                focusedDataSourceID: "municipal",
                lastClosedDataSourceID: .idos
            ),
            "municipal"
        )
        XCTAssertEqual(
            multiplePolicy.preferredRegularDataSourceID(
                focusedDataSourceID: .mock,
                lastClosedDataSourceID: "municipal"
            ),
            "municipal"
        )
        XCTAssertEqual(
            multiplePolicy.preferredRegularDataSourceID(
                focusedDataSourceID: .mock,
                lastClosedDataSourceID: .mock
            ),
            TransitDataSourceID.idos
        )
    }

    func testExplicitMockCanInitializeAWindowButCannotEnterOrdinaryPickersOrFavorites() throws {
        let idos = AppSourceSelectionTestSource(
            id: .idos,
            name: "IDOS",
            timetableIdentifier: "idos",
            capabilities: [.timetables, .connections]
        )
        let municipal = AppSourceSelectionTestSource(
            id: "municipal",
            name: "Municipal Transit",
            timetableIdentifier: "municipal",
            capabilities: [.timetables, .departures]
        )
        let mock = AppSourceSelectionTestSource(
            id: .mock,
            name: "Kaštan Mock",
            timetableIdentifier: "mock",
            capabilities: [.timetables, .connections]
        )
        let registry = try TransitDataSourceRegistry(
            dataSources: [municipal, idos],
            defaultDataSourceID: .idos,
            explicitDataSources: [mock]
        )
        let selection = AppDataSourceSelection(
            registry: registry,
            initialDataSourceID: .mock
        )

        XCTAssertEqual(selection.selectedDataSourceID, .mock)
        XCTAssertFalse(selection.showsSourceSelector)
        XCTAssertEqual(Set(selection.timetables.map(\.dataSourceID)), [.idos, "municipal"])
        XCTAssertFalse(selection.selectDataSource(.mock))

        var section = AppSection.connections
        let coordinator = MainWindowToolbarInstaller.Coordinator(
            selection: Binding(get: { section }, set: { section = $0 }),
            dataSourceSelection: .constant(.mock),
            dataSourceDescriptors: registry.descriptors,
            allowsDataSourceSelection: selection.showsSourceSelector,
            openFavoriteTimetables: {},
            openAppInformation: {}
        )
        XCTAssertFalse(
            coordinator.toolbarDefaultItemIdentifiers(coordinator.toolbar).contains(.dataSource)
        )
        XCTAssertNil(coordinator.toolbar(
            coordinator.toolbar,
            itemForItemIdentifier: .dataSource,
            willBeInsertedIntoToolbar: true
        ))

        XCTAssertTrue(selection.selectDataSource("municipal"))
        XCTAssertEqual(selection.selectedDataSourceID, "municipal")
        XCTAssertFalse(selection.selectDataSource(.mock))
    }

    func testMainWindowDataSourceSelectionStartsAtRegistryDefaultAndRebuildsProviderState() throws {
        let idos = AppSourceSelectionTestSource(
            id: .idos,
            name: "IDOS",
            timetableIdentifier: "shared",
            capabilities: [.timetables, .connections]
        )
        let municipal = AppSourceSelectionTestSource(
            id: "municipal",
            name: "Municipal Transit",
            timetableIdentifier: "shared",
            capabilities: [.timetables, .departures]
        )
        let registry = try TransitDataSourceRegistry(
            dataSources: [municipal, idos],
            defaultDataSourceID: .idos
        )
        let selection = AppDataSourceSelection(registry: registry)
        let otherWindowSelection = AppDataSourceSelection(registry: registry)
        let idosWorkspace = selection.workspace
        idosWorkspace.connectionsModel.from = "Provider-owned state"

        XCTAssertEqual(selection.selectedDataSourceID, .idos)
        XCTAssertTrue(selection.showsSourceSelector)
        XCTAssertEqual(selection.timetables.map(\.identifier), ["shared", "shared"])
        XCTAssertEqual(Set(selection.timetables.map(\.appIdentity)).count, 2)
        XCTAssertTrue(selection.selectDataSource("municipal"))
        XCTAssertEqual(selection.selectedDataSourceID, "municipal")
        XCTAssertEqual(otherWindowSelection.selectedDataSourceID, .idos)
        XCTAssertNotIdentical(selection.workspace, otherWindowSelection.workspace)
        XCTAssertNotIdentical(selection.workspace, idosWorkspace)
        XCTAssertEqual(selection.workspace.availableSections, [.departures])
        XCTAssertEqual(selection.workspace.connectionsModel.from, "")

        let municipalWorkspace = selection.workspace
        XCTAssertFalse(selection.selectDataSource("missing"))
        XCTAssertIdentical(selection.workspace, municipalWorkspace)
        XCTAssertTrue(selection.selectDataSource(.idos))
        XCTAssertNotIdentical(selection.workspace, idosWorkspace)
        XCTAssertNotIdentical(selection.workspace, municipalWorkspace)
        XCTAssertEqual(selection.workspace.connectionsModel.from, "")
    }

    func testSingleSourceWindowOmitsSourceSelectorAndFavoritesNeedNoProviderSubtitle() throws {
        let idos = AppSourceSelectionTestSource(
            id: .idos,
            name: "IDOS",
            timetableIdentifier: "shared",
            capabilities: [.timetables, .connections]
        )
        let registry = try TransitDataSourceRegistry(
            dataSources: [idos],
            defaultDataSourceID: .idos
        )
        let selection = AppDataSourceSelection(registry: registry)
        let presentation = FavoriteTimetableSourcePresentation(
            descriptors: registry.descriptors
        )

        XCTAssertFalse(selection.showsSourceSelector)
        XCTAssertNil(presentation.sourceName(for: idos.defaultTimetable))

        var section = AppSection.connections
        let coordinator = MainWindowToolbarInstaller.Coordinator(
            selection: Binding(get: { section }, set: { section = $0 }),
            dataSourceDescriptors: registry.descriptors,
            openFavoriteTimetables: {},
            openAppInformation: {}
        )
        XCTAssertFalse(
            coordinator.toolbarDefaultItemIdentifiers(coordinator.toolbar).contains(.dataSource)
        )
        XCTAssertNil(coordinator.toolbar(
            coordinator.toolbar,
            itemForItemIdentifier: .dataSource,
            willBeInsertedIntoToolbar: true
        ))
    }

    func testMultiSourceToolbarSelectsProviderAndRefreshesSupportedModes() throws {
        let descriptors = [
            TransitDataSourceDescriptor(
                id: .idos,
                displayName: "IDOS",
                capabilities: [.connections]
            ),
            TransitDataSourceDescriptor(
                id: "municipal",
                displayName: "Municipal Transit",
                capabilities: [.departures]
            ),
        ]
        var sourceID = TransitDataSourceID.idos
        var section = AppSection.connections
        let coordinator = MainWindowToolbarInstaller.Coordinator(
            selection: Binding(get: { section }, set: { section = $0 }),
            sections: [.connections],
            dataSourceSelection: Binding(get: { sourceID }, set: { sourceID = $0 }),
            dataSourceDescriptors: descriptors,
            openFavoriteTimetables: {},
            openAppInformation: {}
        )

        XCTAssertEqual(
            coordinator.toolbarDefaultItemIdentifiers(coordinator.toolbar).first,
            .dataSource
        )
        let sourceItem = try XCTUnwrap(coordinator.toolbar(
            coordinator.toolbar,
            itemForItemIdentifier: .dataSource,
            willBeInsertedIntoToolbar: true
        ))
        let sourceControl = try XCTUnwrap(sourceItem.view as? NSPopUpButton)
        XCTAssertEqual(sourceControl.itemTitles, ["IDOS", "Municipal Transit"])

        sourceControl.selectItem(at: 1)
        sourceControl.sendAction(sourceControl.action, to: sourceControl.target)
        XCTAssertEqual(sourceID, "municipal")

        coordinator.toolbar.insertItem(withItemIdentifier: .searchMode, at: 0)
        section = .departures
        coordinator.update(
            selection: Binding(get: { section }, set: { section = $0 }),
            sections: [.departures],
            dataSourceSelection: Binding(get: { sourceID }, set: { sourceID = $0 }),
            dataSourceDescriptors: descriptors,
            openFavoriteTimetables: {},
            openAppInformation: {}
        )
        let modeControl = try XCTUnwrap(
            coordinator.toolbar.items.first { $0.itemIdentifier == .searchMode }?.view
                as? NSSegmentedControl
        )
        XCTAssertEqual(modeControl.segmentCount, 1)
        XCTAssertEqual(modeControl.label(forSegment: 0), AppLocalization.string("Departures"))

        let presentation = FavoriteTimetableSourcePresentation(descriptors: descriptors)
        let municipalTimetable = TransitTimetable(
            dataSourceID: "municipal",
            identifier: "shared",
            displayName: "Shared"
        )
        XCTAssertEqual(presentation.sourceName(for: municipalTimetable), "Municipal Transit")
    }

    func testConnectionOptionEditorsFollowTheProviderContract() {
        let limited = AppSourceSelectionTestSource(
            id: "limited",
            name: "Limited",
            timetableIdentifier: "network",
            capabilities: [.timetables, .connections],
            connectionOptions: [.via, .maximumWalkingTime]
        )
        let model = ConnectionsViewModel(client: limited)
        let firstID = model.journeyOptions[0].id

        XCTAssertEqual(model.supportedJourneyOptionKinds, [.via, .walkingDistances])
        XCTAssertEqual(model.supportedWalkingDistanceConstraints, [.maximumWalkingTime])
        XCTAssertEqual(
            model.availableJourneyOptionKinds(for: firstID),
            [.via, .walkingDistances]
        )
        XCTAssertFalse(model.supportsOnlyDirect)
        model.setOnlyDirect(true)
        XCTAssertFalse(model.onlyDirect)
        model.setJourneyOptionKind(.transfers, for: firstID)
        XCTAssertEqual(model.journeyOptions[0].kind, .via)
        XCTAssertTrue(model.transferLimitLabel.isEmpty)
        model.setJourneyOptionKind(.walkingDistances, for: firstID)
        XCTAssertEqual(model.journeyOptions[0].kind, .walkingDistances)
        XCTAssertEqual(model.journeyOptions[0].walkingDistanceConstraint, .maximumWalkingTime)
        model.setWalkingDistanceConstraint(.maximumCityWalkingTime, for: firstID)
        XCTAssertEqual(model.journeyOptions[0].walkingDistanceConstraint, .maximumWalkingTime)

        let requirementLimited = AppSourceSelectionTestSource(
            id: "requirements",
            name: "Requirements",
            timetableIdentifier: "network",
            capabilities: [.timetables, .connections],
            connectionOptions: [.lowFloorConnectionsOnly, .preferBusyRoutes]
        )
        let requirementModel = ConnectionsViewModel(client: requirementLimited)

        XCTAssertEqual(requirementModel.supportedJourneyOptionKinds, [.onlyConnections, .preference])
        XCTAssertEqual(requirementModel.supportedConnectionRequirements, [.lowFloorConnectionsOnly])
        XCTAssertEqual(requirementModel.supportedJourneyPreferences, [.busyRoutes])
        requirementModel.addJourneyOption()
        let requirementID = requirementModel.journeyOptions[0].id
        XCTAssertEqual(requirementModel.journeyOptions[0].kind, .onlyConnections)
        XCTAssertEqual(requirementModel.journeyOptions[0].connectionRequirement, .lowFloorConnectionsOnly)
        requirementModel.setConnectionRequirement(.trainConnectionsForPassengersWithChildren, for: requirementID)
        XCTAssertEqual(requirementModel.journeyOptions[0].connectionRequirement, .lowFloorConnectionsOnly)
        requirementModel.addJourneyOption(after: requirementID)
        let preferenceID = requirementModel.journeyOptions[1].id
        XCTAssertEqual(requirementModel.journeyOptions[1].kind, .preference)
        XCTAssertEqual(requirementModel.journeyOptions[1].preference, .busyRoutes)
        requirementModel.setJourneyPreference(.trainsOverBuses, for: preferenceID)
        XCTAssertEqual(requirementModel.journeyOptions[1].preference, .busyRoutes)

        let walkingLimited = AppSourceSelectionTestSource(
            id: "walking",
            name: "Walking",
            timetableIdentifier: "network",
            capabilities: [.timetables, .connections],
            connectionOptions: [.sameNameWalkingTransfersOnly]
        )
        let walkingModel = ConnectionsViewModel(client: walkingLimited)

        XCTAssertEqual(walkingModel.supportedJourneyOptionKinds, [.walkingTransfer])
        XCTAssertEqual(
            walkingModel.supportedWalkingTransferPolicies,
            [.sameNameWalkingTransfersOnly]
        )
        walkingModel.addJourneyOption()
        let walkingID = walkingModel.journeyOptions[0].id
        XCTAssertEqual(walkingModel.journeyOptions[0].kind, .walkingTransfer)
        XCTAssertEqual(
            walkingModel.journeyOptions[0].walkingTransferPolicy,
            .sameNameWalkingTransfersOnly
        )
        walkingModel.setWalkingTransferPolicy(.walkToNearbyStops, for: walkingID)
        XCTAssertEqual(
            walkingModel.journeyOptions[0].walkingTransferPolicy,
            .sameNameWalkingTransfersOnly
        )

        let unavailable = AppSourceSelectionTestSource(
            id: "plain",
            name: "Plain",
            timetableIdentifier: "network",
            capabilities: [.timetables, .connections]
        )
        let unavailableModel = ConnectionsViewModel(client: unavailable)
        XCTAssertTrue(unavailableModel.journeyOptions.isEmpty)
        XCTAssertFalse(unavailableModel.hasConfigurableConnectionOptions)
    }

    func testNonViaConnectionOptionStaysInactiveUntilExplicitlyAdded() async throws {
        let requestRecorder = AppConnectionRequestRecorder()
        let source = AppSourceSelectionTestSource(
            id: "limited",
            name: "Limited",
            timetableIdentifier: "network",
            capabilities: [.timetables, .connections],
            connectionOptions: [.maximumTransfers],
            connectionRequestRecorder: requestRecorder
        )
        let model = ConnectionsViewModel(client: source)
        model.from = "Praha"
        model.to = "Brno"

        XCTAssertTrue(model.journeyOptions.isEmpty)
        XCTAssertTrue(model.canAddJourneyOption)
        XCTAssertTrue(model.transferLimitLabel.isEmpty)

        await model.search()

        var request = await requestRecorder.lastRequest
        XCTAssertNil(request?.maxTransfers)

        model.addJourneyOption()
        let option = try XCTUnwrap(model.journeyOptions.first)
        XCTAssertEqual(option.kind, .transfers)
        XCTAssertEqual(option.transferConstraint, .maximumTransfers)
        XCTAssertEqual(option.maximumTransfers, 4)
        XCTAssertTrue(model.canRemoveJourneyOption(id: option.id))
        model.removeJourneyOption(id: option.id)
        XCTAssertTrue(model.journeyOptions.isEmpty)

        await model.search()

        request = await requestRecorder.lastRequest
        XCTAssertNil(request?.maxTransfers)
    }

    func testClearingDirectOnlyDoesNotReactivateAProviderDefaultConstraint() async {
        let requestRecorder = AppConnectionRequestRecorder()
        let source = AppSourceSelectionTestSource(
            id: "direct-and-limit",
            name: "Direct and limit",
            timetableIdentifier: "network",
            capabilities: [.timetables, .connections],
            connectionOptions: [.onlyDirect, .maximumTransfers],
            connectionRequestRecorder: requestRecorder
        )
        let model = ConnectionsViewModel(client: source)
        model.from = "Praha"
        model.to = "Brno"

        model.setOnlyDirect(true)
        XCTAssertEqual(model.journeyOptions.first?.maximumTransfers, 0)
        model.setOnlyDirect(false)
        XCTAssertTrue(model.journeyOptions.isEmpty)

        await model.search()

        let request = await requestRecorder.lastRequest
        XCTAssertEqual(request?.onlyDirect, false)
        XCTAssertNil(request?.maxTransfers)
    }

    func testDirectOnlyPreventsAddingASparseProviderTransferTimeCondition() {
        let source = AppSourceSelectionTestSource(
            id: "direct-and-transfer-time",
            name: "Direct and transfer time",
            timetableIdentifier: "network",
            capabilities: [.timetables, .connections],
            connectionOptions: [.onlyDirect, .minimumTransferTime]
        )
        let model = ConnectionsViewModel(client: source)

        XCTAssertTrue(model.canAddJourneyOption)
        model.setOnlyDirect(true)

        XCTAssertTrue(model.onlyDirect)
        XCTAssertTrue(model.journeyOptions.isEmpty)
        XCTAssertFalse(model.canAddJourneyOption)
    }

    func testZeroTransferLimitSuppressesTransferTimeWithoutUnsupportedDirectFlag() async throws {
        let requestRecorder = AppConnectionRequestRecorder()
        let source = AppSourceSelectionTestSource(
            id: "transfer-limits",
            name: "Transfer limits",
            timetableIdentifier: "network",
            capabilities: [.timetables, .connections],
            connectionOptions: [.maximumTransfers, .minimumTransferTime],
            connectionRequestRecorder: requestRecorder
        )
        let model = ConnectionsViewModel(client: source)
        model.from = "Praha"
        model.to = "Brno"
        model.addJourneyOption()
        let maximumTransfers = try XCTUnwrap(model.journeyOptions.first)
        model.addJourneyOption(after: maximumTransfers.id)
        model.journeyOptions[1].minimumTransferTime = 5

        model.setMaximumTransfers(0, for: maximumTransfers.id)

        XCTAssertTrue(model.hasNoTransfers)
        XCTAssertFalse(model.onlyDirect)
        XCTAssertEqual(model.journeyOptions.map(\.kind), [.transfers])
        XCTAssertEqual(model.journeyOptions.map(\.transferConstraint), [.maximumTransfers])
        XCTAssertFalse(model.canAddJourneyOption)
        XCTAssertFalse(
            model.availableTransferConstraints(for: maximumTransfers.id).contains(.minimumTransferTime)
        )

        await model.search()

        let request = await requestRecorder.lastRequest
        XCTAssertEqual(request?.onlyDirect, false)
        XCTAssertEqual(request?.maxTransfers, 0)
        XCTAssertNil(request?.minimumTransferTime)
    }

    func testDirectOnlyShortcutIsAlwaysVisibleWhenItIsTheProvidersOnlyOption() {
        XCTAssertTrue(DirectConnectionsShortcutPresentation.isVisible(
            journeyOptionsAreExpanded: false,
            optionIsPressed: false,
            hasBeenUsed: false,
            isOnlyConfigurableOption: true
        ))

        let directOnly = AppSourceSelectionTestSource(
            id: "direct",
            name: "Direct",
            timetableIdentifier: "network",
            capabilities: [.timetables, .connections],
            connectionOptions: [.onlyDirect]
        )
        let model = ConnectionsViewModel(client: directOnly)
        model.setOnlyDirect(true)

        XCTAssertTrue(model.supportsOnlyDirect)
        XCTAssertTrue(model.supportedJourneyOptionKinds.isEmpty)
        XCTAssertTrue(model.onlyDirect)
        XCTAssertTrue(model.journeyOptions.isEmpty)
    }

    func testForceClickPreviewPrefersTheSmallestLatestTargetUnderThePointer() throws {
        let connectionID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000001"))
        let serviceID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000002"))
        let newerEqualTargetID = try XCTUnwrap(
            UUID(uuidString: "00000000-0000-0000-0000-000000000003")
        )
        let targets = [
            ForceClickPreviewTargetFrame(
                id: connectionID,
                frame: CGRect(x: 0, y: 0, width: 500, height: 320),
                registrationOrder: 0,
                acceptsPressure: true
            ),
            ForceClickPreviewTargetFrame(
                id: serviceID,
                frame: CGRect(x: 24, y: 40, width: 452, height: 72),
                registrationOrder: 1,
                acceptsPressure: true
            ),
        ]

        XCTAssertEqual(
            ForceClickPreviewTargetResolver.targetID(at: CGPoint(x: 100, y: 70), in: targets),
            serviceID
        )
        XCTAssertEqual(
            ForceClickPreviewTargetResolver.targetID(at: CGPoint(x: 100, y: 220), in: targets),
            connectionID
        )
        XCTAssertNil(
            ForceClickPreviewTargetResolver.targetID(at: CGPoint(x: 600, y: 220), in: targets)
        )
        XCTAssertEqual(
            ForceClickPreviewTargetResolver.targetID(
                at: CGPoint(x: 100, y: 70),
                in: targets + [ForceClickPreviewTargetFrame(
                    id: newerEqualTargetID,
                    frame: CGRect(x: 24, y: 40, width: 452, height: 72),
                    registrationOrder: 2,
                    acceptsPressure: true
                )]
            ),
            newerEqualTargetID
        )
    }

    func testForceClickPreviewIgnoresTargetsOutsideHoveredContent() throws {
        let serviceID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000002"))
        XCTAssertNil(
            ForceClickPreviewTargetResolver.targetID(
                at: CGPoint(x: 100, y: 70),
                in: [ForceClickPreviewTargetFrame(
                    id: serviceID,
                    frame: CGRect(x: 0, y: 0, width: 500, height: 320),
                    registrationOrder: 0,
                    acceptsPressure: false
                )]
            )
        )
    }

    func testConnectionCardRegistersForceClickOnlyForItsServices() {
        var displayedConnection = connection(id: "connection-preview-targets")
        displayedConnection.legs = [
            IDOSConnectionLeg(
                name: "R 879 Svitava",
                id: "vlaky:service-preview",
                transportMode: .train,
                departureTime: "12:00",
                fromStation: "Praha hl.n.",
                arrivalTime: "14:30",
                toStation: "Brno hl.n."
            ),
        ]
        let card = ConnectionCard(
            number: 1,
            connection: displayedConnection,
            timetable: IDOSTimetable(slug: "vlaky", displayName: "Trains"),
            client: MockIDOSClient(),
            isShortest: true,
            showsConnectionBadges: false,
            showsItemDetails: false,
            showsServiceInformationText: false,
            showsStopNoteText: false,
            isPerformingAction: false,
            showsActionMenu: true,
            showsOpenConnectionButton: false,
            timeFrameCoordinateSpace: nil,
            openConnection: {},
            openService: { _ in },
            performEmailAction: { _ in },
            performCalendarAction: { _ in },
            performPDFAction: { _ in }
        )
        let hostingView = NSHostingView(rootView: card.frame(width: 700))
        hostingView.frame = NSRect(x: 0, y: 0, width: 700, height: 300)
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

        XCTAssertEqual(forceClickPreviewAttachmentCount(in: hostingView), 1)
        XCTAssertEqual(ResultPreviewLayout.serviceSize, CGSize(width: 400, height: 560))
    }

    func testDoubleClickingAnywhereInConnectionSummaryOpensItsWindow() {
        for showsConnectionBadges in [false, true] {
            XCTAssertEqual(
                connectionCardOpenCount(
                    afterDoubleClickAt: NSPoint(x: 300, y: 120),
                    showsConnectionBadges: showsConnectionBadges
                ),
                1
            )
            XCTAssertEqual(
                connectionCardOpenCount(
                    afterDoubleClickAt: NSPoint(x: 300, y: 90),
                    showsConnectionBadges: showsConnectionBadges
                ),
                1
            )
        }
    }

    func testConnectionHeaderOpenButtonAppearsOnlyWhileOptionIsPressed() {
        func openButtonCount(optionIsPressed: Bool) -> Int {
            let card = ConnectionCard(
                number: 1,
                connection: connection(id: "connection-open-button"),
                timetable: IDOSTimetable(slug: "vlaky", displayName: "Trains"),
                client: MockIDOSClient(),
                isShortest: false,
                showsConnectionBadges: false,
                showsItemDetails: false,
                showsServiceInformationText: false,
                showsStopNoteText: false,
                isPerformingAction: false,
                showsActionMenu: true,
                showsOpenConnectionButton: optionIsPressed,
                timeFrameCoordinateSpace: nil,
                openConnection: {},
                openService: { _ in },
                performEmailAction: { _ in },
                performCalendarAction: { _ in },
                performPDFAction: { _ in }
            )
            let hostingView = NSHostingView(rootView: card.frame(width: 700))
            hostingView.frame = NSRect(x: 0, y: 0, width: 700, height: 180)
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

            return hostingView.allDescendantViews.compactMap { $0 as? NSButton }.count
        }

        let hiddenButtonCount = openButtonCount(optionIsPressed: false)
        XCTAssertEqual(openButtonCount(optionIsPressed: true), hiddenButtonCount + 1)
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

    func testNativeToolbarIncludesOnlyProviderSupportedModes() throws {
        var selection = AppSection.departures
        let coordinator = MainWindowToolbarInstaller.Coordinator(
            selection: Binding(
                get: { selection },
                set: { selection = $0 }
            ),
            sections: [.departures],
            openFavoriteTimetables: {},
            openAppInformation: {}
        )
        let modeItem = try XCTUnwrap(
            coordinator.toolbar(
                coordinator.toolbar,
                itemForItemIdentifier: .searchMode,
                willBeInsertedIntoToolbar: true
            )
        )
        let modeControl = try XCTUnwrap(modeItem.view as? NSSegmentedControl)

        XCTAssertEqual(modeControl.segmentCount, 1)
        XCTAssertEqual(modeControl.label(forSegment: 0), AppLocalization.string("Departures"))

        modeControl.selectedSegment = 0
        modeControl.sendAction(modeControl.action, to: modeControl.target)
        XCTAssertEqual(selection, .departures)
    }

    func testMainWindowToolbarPreservesSavedWindowFrame() {
        var selection = AppSection.connections
        let coordinator = MainWindowToolbarInstaller.Coordinator(
            selection: Binding(
                get: { selection },
                set: { selection = $0 }
            ),
            openFavoriteTimetables: {},
            openAppInformation: {}
        )
        let window = NSWindow(
            contentRect: NSRect(x: 120, y: 80, width: 1_080, height: 720),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        let savedFrameName = "KastanAppTests-main-window-\(UUID().uuidString)"
        XCTAssertTrue(window.setFrameAutosaveName(savedFrameName))
        defer {
            coordinator.uninstall()
            NSWindow.removeFrame(usingName: savedFrameName)
        }

        coordinator.install(on: window)

        XCTAssertEqual(window.contentRect(forFrameRect: window.frame).width, 1_080, accuracy: 0.5)
        XCTAssertEqual(window.frameAutosaveName, savedFrameName)
    }

    func testMainWindowToolbarExpandsUnsupportedSavedNarrowFrame() {
        var selection = AppSection.connections
        let coordinator = MainWindowToolbarInstaller.Coordinator(
            selection: Binding(
                get: { selection },
                set: { selection = $0 }
            ),
            openFavoriteTimetables: {},
            openAppInformation: {}
        )
        let window = NSWindow(
            contentRect: NSRect(x: 120, y: 80, width: 390, height: 720),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        let openingTopLeft = NSPoint(x: window.frame.minX, y: window.frame.maxY)
        let savedFrameName = "KastanAppTests-main-window-\(UUID().uuidString)"
        XCTAssertTrue(window.setFrameAutosaveName(savedFrameName))
        defer {
            coordinator.uninstall()
            NSWindow.removeFrame(usingName: savedFrameName)
        }

        coordinator.install(on: window)

        XCTAssertEqual(
            window.contentRect(forFrameRect: window.frame).width,
            KastanApp.minimumMainWindowWidth,
            accuracy: 0.5
        )
        XCTAssertEqual(window.contentMinSize.width, KastanApp.minimumMainWindowWidth)
        XCTAssertEqual(window.frame.minX, openingTopLeft.x, accuracy: 0.5)
        XCTAssertEqual(window.frame.maxY, openingTopLeft.y, accuracy: 0.5)
        XCTAssertEqual(window.frameAutosaveName, savedFrameName)
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
            [
                "pid", "idsjmk", "odis", "idol", "idsok", "iredo", "duk", "idpk", "idzk",
                "ideska",
            ]
        )
        XCTAssertTrue(
            AppTimetableGroup.cityTransport.timetables.allSatisfy {
                $0.displayName.hasPrefix("Urban Public Transport ")
            }
        )
        let citySlugs = Set(AppTimetableGroup.cityTransport.timetables.map(\.slug))
        XCTAssertEqual(citySlugs.count, 106)
        XCTAssertTrue(
            Set([
                "ceskykrumlov", "milevsko", "vimperk", "novemestonamorave", "dvurkralove",
                "kostelecnadorlici", "rychnov", "jablonec", "ustinadorlici", "kralupy",
                "mnisekpodbrdy", "ricany", "roudnice", "varnsdorf",
            ]).isSubset(of: citySlugs)
        )
        XCTAssertFalse(citySlugs.contains("praha"))
        XCTAssertEqual(
            AppTimetableGroup.cityTransport.timetables.first { $0.slug == "karlovyvary" }?.appDisplayName,
            "Karlovy Vary"
        )
        let groupedSlugs = Set(AppTimetableGroup.allCases.flatMap { $0.timetables.map(\.slug) })
        XCTAssertEqual(groupedSlugs, Set(IDOSTimetable.known.map(\.slug)))
        XCTAssertEqual(
            AppTimetableGroup.stationTimetables.prefix(11).map(\.slug),
            [
                "vlaky", "pid", "idsjmk", "odis", "idol", "idsok", "iredo", "duk", "idpk",
                "idzk", "ideska",
            ]
        )
        XCTAssertTrue(
            AppTimetableGroup.stationTimetables.dropFirst(11).allSatisfy {
                $0.displayName.hasPrefix("Urban Public Transport ")
            }
        )
    }

    func testEverySearchModeDefaultsToTrains() {
        let client = MockIDOSClient()

        XCTAssertEqual(AppTimetableDefaults.search.slug, "vlaky")
        XCTAssertEqual(ConnectionsViewModel(client: client).timetable.slug, "vlaky")
        XCTAssertEqual(DeparturesViewModel(client: client).timetable.slug, "vlaky")
        XCTAssertEqual(StationTimetablesViewModel(client: client).timetable.slug, "vlaky")
        XCTAssertEqual(AppTimetableGroup.stationTimetables.first?.slug, "vlaky")
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

    func testFavoriteTimetablesKeepEqualIdentifiersFromDifferentSourcesDistinct() {
        let idos = TransitTimetable(
            dataSourceID: .idos,
            identifier: "shared",
            displayName: "IDOS Shared"
        )
        let municipal = TransitTimetable(
            dataSourceID: "municipal",
            identifier: "shared",
            displayName: "Municipal Shared"
        )
        let catalog = [idos, municipal]
        var favorites = TimetableFavorites(serialized: "[]", catalog: catalog)

        favorites.toggle(idos)
        favorites.toggle(municipal)

        let restored = TimetableFavorites(serialized: favorites.serialized, catalog: catalog)
        let pickerOptions = AppTimetablePickerOptions(
            favoriteTimetables: restored.timetables,
            allowedTimetables: catalog
        )
        XCTAssertTrue(restored.contains(idos))
        XCTAssertTrue(restored.contains(municipal))
        XCTAssertEqual(restored.timetables, catalog)
        XCTAssertEqual(pickerOptions.favoriteTimetables, catalog)
        XCTAssertNotEqual(idos.appIdentity, municipal.appIdentity)
    }

    func testFavoriteTimetablesRetainOtherProviderReferencesWhileOneCatalogIsActive() {
        let idos = TransitTimetable(
            dataSourceID: .idos,
            identifier: "vlaky",
            displayName: "Trains"
        )
        let municipal = TransitTimetable(
            dataSourceID: "municipal",
            identifier: "network",
            displayName: "Municipal Network"
        )
        var allFavorites = TimetableFavorites(serialized: "[]", catalog: [idos, municipal])
        allFavorites.toggle(idos)
        allFavorites.toggle(municipal)

        var idosFavorites = TimetableFavorites(
            serialized: allFavorites.serialized,
            catalog: [idos]
        )
        idosFavorites.toggle(idos)

        let restored = TimetableFavorites(
            serialized: idosFavorites.serialized,
            catalog: [idos, municipal]
        )
        XCTAssertFalse(restored.contains(idos))
        XCTAssertTrue(restored.contains(municipal))
    }

    func testFavoriteStarContextMenuOffersOnlyTheFavoritesManager() {
        XCTAssertEqual(TimetableFavoriteContextAction.allCases, [.openManager])
        XCTAssertEqual(
            AppLocalization.string(TimetableFavoriteContextAction.openManager.rawValue),
            AppLocalization.string("Favorite timetables")
        )
        XCTAssertEqual(TimetableFavoriteContextAction.openManager.systemImage, "star")

        var didOpenFavoriteTimetables = false
        let menu = TimetableFavoriteContextMenu(
            openFavoriteTimetables: { didOpenFavoriteTimetables = true }
        )

        menu.perform(.openManager)

        XCTAssertTrue(didOpenFavoriteTimetables)
    }

    func testFavoriteTimetablesRemainInTheirCatalogSections() {
        let options = AppTimetablePickerOptions(favoriteSlugs: ["vlaky", "odis"])

        XCTAssertTrue(options.catalogTimetables(in: .general).contains { $0.slug == "vlaky" })
        XCTAssertTrue(options.catalogTimetables(in: .integratedSystems).contains { $0.slug == "odis" })
    }

    func testFavoriteTimetablesWindowOpensAtNarrowWidth() {
        XCTAssertEqual(FavoriteTimetablesView.minimumWindowWidth, 320)
        XCTAssertEqual(
            FavoriteTimetablesView.defaultWindowWidth,
            FavoriteTimetablesView.minimumWindowWidth
        )
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
        let genericStation = PlaceSuggestionPresentation(
            suggestion: IDOSSuggestion(
                text: "Frýdek-Místek",
                description: "station, district Frýdek-Místek"
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
        let borough = PlaceSuggestionPresentation(
            suggestion: IDOSSuggestion(
                text: "Smíchov/Praha",
                description: "borough, district Praha, trains, buses, PT"
            )
        )
        let servedAddress = PlaceSuggestionPresentation(
            suggestion: IDOSSuggestion(
                text: "Aš, Sokolská",
                description: "address, district Cheb, buses"
            )
        )

        XCTAssertEqual(municipality.emoji, "🏘️")
        XCTAssertEqual(municipality.kind, .municipality)
        XCTAssertEqual(station.emoji, "🚆")
        XCTAssertEqual(station.kind, .train)
        XCTAssertEqual(genericStation.emoji, "🚉")
        XCTAssertEqual(genericStation.kind, .station)
        XCTAssertEqual(busStop.kind, .bus)
        XCTAssertEqual(station.detail?.components(separatedBy: " · ").count, 3)
        XCTAssertEqual(
            station.detail?.components(separatedBy: " · ").filter { $0.contains("Frýdek-Místek") }.count,
            1
        )
        XCTAssertEqual(busStop.emoji, "🚌")
        XCTAssertEqual(busStop.detail?.components(separatedBy: " · ").count, 4)
        XCTAssertEqual(romanianMunicipality.detail, "Rumunsko")
        XCTAssertEqual(borough.kind, .borough)
        XCTAssertEqual(borough.emoji, "🏙️")
        XCTAssertEqual(servedAddress.kind, .address)
    }

    func testStationTimetableLineSuggestionsUseTransportIconsInsteadOfAPlacePin() {
        let suggestions: [(text: String, iconID: Int?, emoji: String)] = [
            ("302", 4, "🚌"),
            ("A", 5, "🚇"),
            ("S2", 14, "🚆"),
            ("9", 15, "🚋"),
            ("Trolleybus 25", 4, "🚎"),
            ("Line X", nil, "🛣️"),
        ]

        for suggestion in suggestions {
            let presentation = PlaceSuggestionPresentation(
                suggestion: IDOSSuggestion(
                    text: suggestion.text,
                    description: "First terminal-Second terminal",
                    iconId: suggestion.iconID
                ),
                scope: .stationTimetableLines
            )

            XCTAssertEqual(presentation.emoji, suggestion.emoji)
            XCTAssertNotEqual(presentation.emoji, "📍")
        }
    }

    func testPlaceSuggestionVisibilityFiltersOnlyConfiguredIDOSPlaceTypes() {
        let suggestions = [
            IDOSSuggestion(text: "Aš, Sokolská", description: "address, district Cheb, buses"),
            IDOSSuggestion(text: "Smíchov/Praha", description: "borough, district Praha, trains, buses, PT"),
            IDOSSuggestion(text: "Praha", description: "municipality, district Praha, trains, buses, PT"),
            IDOSSuggestion(text: "Praha hl.n.", description: "station, district Praha, trains"),
            IDOSSuggestion(text: "Praha,,Anděl", description: "stop, district Praha, buses, PT"),
        ]
        let hidden = PlaceSuggestionVisibility(
            showsAddresses: false,
            showsBoroughs: false,
            showsMunicipalities: false
        )

        XCTAssertEqual(
            suggestions.filter(PlaceSuggestionVisibility.defaultValue.includes).map(\.text),
            suggestions.map(\.text)
        )
        XCTAssertEqual(
            suggestions.filter(hidden.includes).map(\.text),
            ["Praha hl.n.", "Praha,,Anděl"]
        )
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

    func testCurrentLocationFillsEitherConnectionEndpointAndClearsItsOpaqueValueAcrossTimetables() async {
        let provider = StubCurrentLocationProvider(result: .success(CurrentLocationCoordinate(
            latitude: 49.197391,
            longitude: 16.619124
        )))
        let client = MockIDOSClient()
        let model = ConnectionsViewModel(
            client: client,
            calendarImporter: RecordingCalendarImporter(),
            currentLocationProvider: provider
        )
        let locationText = AppLocalization.string("My location")

        await model.fillCurrentLocation(in: .from)

        XCTAssertEqual(model.from, locationText)
        XCTAssertTrue(model.fromSelection?.isCurrentLocation == true)
        XCTAssertNil(model.fromSelection?.kind)

        model.timetable = IDOSTimetable(slug: "pid", displayName: "Prague + PID")
        XCTAssertEqual(model.from, locationText)
        XCTAssertNil(model.fromSelection)

        model.from = "Praha"
        model.to = "Brno"
        await model.fillCurrentLocation(in: .to)
        await model.search()

        let request = await client.lastConnectionRequest
        XCTAssertEqual(model.to, locationText)
        XCTAssertTrue(model.toSelection?.isCurrentLocation == true)
        XCTAssertEqual(request?.toSelection, model.toSelection?.idosSelection)
        XCTAssertEqual(provider.requestCount, 2)
    }

    func testCurrentLocationIsReencodedForTheNewTimetableBeforeSearching() async throws {
        let provider = StubCurrentLocationProvider(result: .success(CurrentLocationCoordinate(
            latitude: 49.197391,
            longitude: 16.619124
        )))
        let client = MockIDOSClient()
        let model = ConnectionsViewModel(
            client: client,
            calendarImporter: RecordingCalendarImporter(),
            currentLocationProvider: provider
        )
        let locationText = AppLocalization.string("My location")

        await model.fillCurrentLocation(in: .from)
        model.to = "Brno"
        model.timetable = IDOSTimetable(slug: "pid", displayName: "Prague + PID")

        await model.search()

        let recordedRequest = await client.lastConnectionRequest
        let request = try XCTUnwrap(recordedRequest)
        XCTAssertEqual(model.from, locationText)
        XCTAssertEqual(request.fromSelection?.timetableIdentifier, "pid")
        XCTAssertEqual(request.fromSelection, model.fromSelection?.placeSelection)
        XCTAssertEqual(provider.requestCount, 2)
    }

    func testTypedCurrentLocationResolvesBeforeConnectionSearch() async {
        let provider = StubCurrentLocationProvider(result: .success(CurrentLocationCoordinate(
            latitude: 49.197391,
            longitude: 16.619124
        )))
        let client = MockIDOSClient()
        let model = ConnectionsViewModel(
            client: client,
            calendarImporter: RecordingCalendarImporter(),
            currentLocationProvider: provider
        )
        let locationText = AppLocalization.string("My location")
        model.from = "  \(locationText.uppercased())  "
        model.to = "Brno"

        await model.search()

        let request = await client.lastConnectionRequest
        XCTAssertEqual(model.from, locationText)
        XCTAssertEqual(model.to, "Brno")
        XCTAssertTrue(model.fromSelection?.isCurrentLocation == true)
        XCTAssertEqual(request?.fromSelection, model.fromSelection?.idosSelection)
        XCTAssertNil(request?.toSelection)
        XCTAssertEqual(provider.requestCount, 1)
    }

    func testTypedCurrentLocationFailureStopsTheConnectionSearch() async {
        let provider = StubCurrentLocationProvider(
            result: .failure(CurrentLocationError.permissionDenied)
        )
        let client = MockIDOSClient()
        let model = ConnectionsViewModel(
            client: client,
            calendarImporter: RecordingCalendarImporter(),
            currentLocationProvider: provider
        )
        model.from = AppLocalization.string("My location")
        model.to = "Brno"

        await model.search()

        let request = await client.lastConnectionRequest
        XCTAssertNil(request)
        XCTAssertNil(model.locatingEndpoint)
        XCTAssertFalse(model.isSearching)
        XCTAssertEqual(
            model.errorMessage,
            AppLocalization.string(
                "Location access was denied. Allow Kaštan to use your location in System Settings."
            )
        )
    }

    func testCurrentLocationPermissionFailureIsActionable() async {
        let provider = StubCurrentLocationProvider(
            result: .failure(CurrentLocationError.permissionDenied)
        )
        let model = ConnectionsViewModel(
            client: MockIDOSClient(),
            calendarImporter: RecordingCalendarImporter(),
            currentLocationProvider: provider
        )

        await model.fillCurrentLocation(in: .from)

        XCTAssertNil(model.fromSelection)
        XCTAssertNil(model.locatingEndpoint)
        XCTAssertEqual(
            model.errorMessage,
            AppLocalization.string(
                "Location access was denied. Allow Kaštan to use your location in System Settings."
            )
        )
    }

    func testCurrentLocationShortcutRequiresSourceCapability() async {
        struct LimitedSource: TransitDataSource {
            let descriptor = TransitDataSourceDescriptor(
                id: "limited",
                displayName: "Limited Transit",
                capabilities: [.connections]
            )
        }

        let provider = StubCurrentLocationProvider(result: .success(CurrentLocationCoordinate(
            latitude: 49.197391,
            longitude: 16.619124
        )))
        let model = ConnectionsViewModel(
            client: LimitedSource(),
            calendarImporter: RecordingCalendarImporter(),
            currentLocationProvider: provider
        )

        XCTAssertFalse(model.canFillCurrentLocation)
        await model.fillCurrentLocation(in: .from)
        XCTAssertEqual(provider.requestCount, 0)
        XCTAssertNil(model.fromSelection)
    }

    func testLocationPermissionPromptIsLocalized() throws {
        let czech = try XCTUnwrap(localizationBundle(languageCode: "cs"))
        let english = try XCTUnwrap(localizationBundle(languageCode: "en"))
        let key = "NSLocationWhenInUseUsageDescription"
        let configuredDescription = try XCTUnwrap(
            Bundle.main.object(forInfoDictionaryKey: key) as? String
        )

        XCTAssertFalse(configuredDescription.isEmpty)
        XCTAssertNotEqual(czech.localizedString(forKey: key, value: nil, table: "InfoPlist"), key)
        XCTAssertNotEqual(english.localizedString(forKey: key, value: nil, table: "InfoPlist"), key)
    }

    func testSelectedPlaceTypeMarkerStaysWithinACompactInput() {
        let fieldSize = CGSize(width: 160, height: 28)
        let marker = SelectedPlaceTypeMarker(
            text: "Frenštát pod Radhoštěm,,u škol",
            kind: .bus,
            fieldSize: fieldSize
        )
        let hostingView = NSHostingView(rootView: marker)

        XCTAssertEqual(hostingView.fittingSize.width, fieldSize.width, accuracy: 0.5)
        XCTAssertEqual(hostingView.fittingSize.height, fieldSize.height, accuracy: 0.5)
    }

    func testHeaderlessPlaceAutocompleteFitsTheJourneyOptionRow() {
        let field = PlaceAutocompleteField(
            prompt: "Via place",
            text: .constant(""),
            timetable: .defaultTimetable,
            scope: .places,
            client: MockIDOSClient()
        )
        .frame(width: 320)
        let hostingView = NSHostingView(rootView: field)

        XCTAssertGreaterThan(hostingView.fittingSize.height, 0)
        XCTAssertLessThanOrEqual(hostingView.fittingSize.height, 28)
    }

    func testPlaceFieldSelectionAcceptsProviderOwnedSuggestionWithoutIDOSValues() throws {
        let suggestion = TransitSuggestion(
            dataSourceID: "municipal",
            timetableIdentifier: "metro",
            identifier: "place:river-market",
            selectedText: "River Market",
            text: "River Market station",
            description: "metro station"
        )

        let selection = try XCTUnwrap(PlaceFieldSelection(suggestion: suggestion))

        XCTAssertEqual(selection.text, "River Market")
        XCTAssertEqual(selection.placeSelection.dataSourceID, "municipal")
        XCTAssertEqual(selection.placeSelection.identifier, "place:river-market")
        XCTAssertFalse(selection.isCurrentLocation)
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

    func testDelayPresentationLocalizesKnownStatesAndLiveMinuteCounts() throws {
        let knownStates: [(key: String, czechSource: String)] = [
            ("Currently no delay", "Aktuálně bez zpoždění"),
            ("Departure tends to be on time", "Odjezd bývá včas"),
            ("Arrival tends to be on time", "Příjezd bývá včas"),
            ("Departure tends to be delayed", "Odjezd bývá zpožděn"),
            ("Arrival tends to be delayed", "Příjezd bývá zpožděn"),
        ]
        for state in knownStates {
            let expected = AppLocalization.string(state.key)
            XCTAssertEqual(ResultMetadata.delay(" \(state.key) "), expected)
            XCTAssertEqual(ResultMetadata.delay(" \(state.czechSource) "), expected)
        }
        XCTAssertEqual(ResultMetadata.delay("Delay 12 min"), "Delay 12 min")
        XCTAssertNil(ResultMetadata.delay("  "))

        let czech = try XCTUnwrap(localizationBundle(languageCode: "cs"))
        let english = try XCTUnwrap(localizationBundle(languageCode: "en"))
        XCTAssertEqual(
            ResultMetadata.delay(" Current delay of 1 minute ", bundle: czech),
            "Aktuální zpoždění 1 minuta"
        )
        XCTAssertEqual(
            ResultMetadata.delay("Current delay of 4 minutes", bundle: czech),
            "Aktuální zpoždění 4 minuty"
        )
        XCTAssertEqual(
            ResultMetadata.delay("Current delay of 7 minutes", bundle: czech),
            "Aktuální zpoždění 7 minut"
        )
        XCTAssertEqual(
            ResultMetadata.delay("Aktuální zpoždění 1 minuta", bundle: english),
            "Current delay of 1 minute"
        )
        XCTAssertEqual(
            ResultMetadata.delay("Aktuální zpoždění 4 minuty", bundle: english),
            "Current delay of 4 minutes"
        )
        XCTAssertEqual(
            knownStates.map { czech.localizedString(forKey: $0.key, value: nil, table: nil) },
            [
                "Aktuálně bez zpoždění",
                "Odjezd bývá včas",
                "Příjezd bývá včas",
                "Odjezd bývá zpožděn",
                "Příjezd bývá zpožděn",
            ]
        )
        XCTAssertEqual(
            knownStates.map { english.localizedString(forKey: $0.key, value: nil, table: nil) },
            knownStates.map { $0.key }
        )
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

    func testServiceRouteInitialScrollWaitsForLoadedWindowLayout() async {
        var didScroll = false
        let scrollCompleted = expectation(description: "Initial route scroll was deferred")

        ServiceRouteInitialScroll.afterWindowLayout {
            didScroll = true
            scrollCompleted.fulfill()
        }

        XCTAssertFalse(didScroll)
        await fulfillment(of: [scrollCompleted])
        XCTAssertTrue(didScroll)
    }

    func testServiceRouteInitialScrollUsesNaturalContentBoundsAndSafeTopInset() {
        XCTAssertEqual(ServiceRouteInitialScroll.topClearance(for: .window), 16)
        XCTAssertEqual(ServiceRouteInitialScroll.topClearance(for: .preview), 20)
        XCTAssertFalse(ServiceRouteInitialScroll.needsPositioning(
            departureIndex: 0,
            viewportHeight: 520,
            routeBottom: 800
        ))
        XCTAssertFalse(ServiceRouteInitialScroll.needsPositioning(
            departureIndex: 2,
            viewportHeight: 520,
            routeBottom: 500
        ))
        XCTAssertTrue(ServiceRouteInitialScroll.needsPositioning(
            departureIndex: 2,
            viewportHeight: 520,
            routeBottom: 800
        ))
        XCTAssertEqual(
            ServiceRouteInitialScroll.anchor(
                viewportHeight: 520,
                departureHeight: 64,
                topClearance: 16
            ).y,
            16 / 456,
            accuracy: 0.000_001
        )
    }

    func testServicePreviewInitiallyScrollsToTheSearchedDepartureStop() async throws {
        let client = MockIDOSClient()
        let service = IDOSServiceDetail(
            id: "service-preview-scroll",
            timetable: IDOSTimetable(slug: "vlaky", displayName: "Trains"),
            name: "R 879 Svitava",
            transportMode: .train,
            date: "30.7.2026",
            stops: (0..<30).map { index in
                IDOSServiceStop(
                    name: "Stop \(index)",
                    departureTime: String(format: "12:%02d", index)
                )
            }
        )
        await client.configureServiceDetail(service)

        let hostingView = NSHostingView(rootView: PresentedServicePreviewTestHost(
            selection: ServiceSelection(
                id: service.id,
                highlight: ServiceRouteHighlight(fromStop: "Stop 10", toStop: "Stop 14")
            ),
            client: client
        ))
        hostingView.frame = NSRect(x: 0, y: 0, width: 180, height: 80)
        let window = NSWindow(
            contentRect: hostingView.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.contentView = hostingView
        window.makeKeyAndOrderFront(nil)
        defer {
            window.childWindows?.forEach { $0.close() }
            window.orderOut(nil)
        }

        let pendingScrollView = await waitForServicePreviewScrollView(in: window)
        let scrollView = try XCTUnwrap(pendingScrollView)
        defer { scrollView.window?.close() }
        let didReachDeparture = await waitForServicePreviewInitialScroll(in: scrollView)
        let requestCount = await client.serviceDetailRequestCount
        let documentHeight = try XCTUnwrap(scrollView.documentView).frame.height

        XCTAssertEqual(requestCount, 1)
        XCTAssertGreaterThan(documentHeight, scrollView.documentVisibleRect.height)
        XCTAssertTrue(
            didReachDeparture,
            "The preview should skip the route stops preceding the searched departure " +
                "(visible minY: \(scrollView.documentVisibleRect.minY), document height: \(documentHeight))."
        )
    }

    func testServicePreviewNearRouteEndKeepsTheNaturalDocumentHeight() async throws {
        let service = IDOSServiceDetail(
            id: "service-preview-natural-end",
            timetable: IDOSTimetable(slug: "vlaky", displayName: "Trains"),
            name: "R 879 Svitava",
            transportMode: .train,
            date: "30.7.2026",
            stops: (0..<18).map { index in
                IDOSServiceStop(
                    name: "Stop \(index)",
                    departureTime: String(format: "12:%02d", index)
                )
            }
        )

        func renderedDocumentHeight(highlight: ServiceRouteHighlight?) async throws -> CGFloat {
            let client = MockIDOSClient()
            await client.configureServiceDetail(service)
            let hostingView = NSHostingView(rootView: PresentedServicePreviewTestHost(
                selection: ServiceSelection(id: service.id, highlight: highlight),
                client: client
            ))
            hostingView.frame = NSRect(x: 0, y: 0, width: 180, height: 80)
            let window = NSWindow(
                contentRect: hostingView.frame,
                styleMask: .borderless,
                backing: .buffered,
                defer: false
            )
            window.contentView = hostingView
            window.makeKeyAndOrderFront(nil)
            defer {
                window.childWindows?.forEach { $0.close() }
                window.orderOut(nil)
            }

            let pendingScrollView = await waitForServicePreviewScrollView(in: window)
            let scrollView = try XCTUnwrap(pendingScrollView)
            defer { scrollView.window?.close() }
            let pendingDocumentHeight = await stableDocumentHeight(in: scrollView)
            return try XCTUnwrap(pendingDocumentHeight)
        }

        let naturalHeight = try await renderedDocumentHeight(highlight: nil)
        let positionedHeight = try await renderedDocumentHeight(
            highlight: ServiceRouteHighlight(fromStop: "Stop 16", toStop: "Stop 17")
        )

        XCTAssertEqual(positionedHeight, naturalHeight, accuracy: 1)
    }

    func testServiceSelectionRoundTripsThroughWindowState() throws {
        let timetable = IDOSTimetable(slug: "vlaky", displayName: "Trains")
        let selection = ServiceSelection(
            id: "service-301",
            timetable: timetable,
            highlight: ServiceRouteHighlight(fromStop: "Frýdlant n. O.", toStop: "Ostravice")
        )

        let data = try JSONEncoder().encode(selection)
        let decoded = try JSONDecoder().decode(ServiceSelection.self, from: data)

        XCTAssertEqual(decoded, selection)
        XCTAssertEqual(decoded.serviceID, "service-301")
        XCTAssertEqual(decoded.timetable, timetable)
        XCTAssertEqual(decoded.dataSourceID, .idos)
        XCTAssertEqual(
            decoded.id,
            AppTransitValueIdentity(
                dataSourceID: .idos,
                timetableIdentifier: "vlaky",
                valueIdentifier: "service-301"
            )
        )
    }

    func testServiceSelectionRestoresLegacyWindowStateAsIDOS() throws {
        let data = Data(#"{"id":"legacy-service"}"#.utf8)

        let decoded = try JSONDecoder().decode(ServiceSelection.self, from: data)

        XCTAssertEqual(decoded.serviceID, "legacy-service")
        XCTAssertEqual(decoded.timetable, .defaultTimetable)
        XCTAssertEqual(decoded.dataSourceID, .idos)
        XCTAssertEqual(
            decoded.id,
            AppTransitValueIdentity(
                dataSourceID: .idos,
                timetableIdentifier: TransitTimetable.defaultTimetable.identifier,
                valueIdentifier: "legacy-service"
            )
        )
    }

    func testServiceDetailLoadsUsingTheSelectionsExactTimetable() async {
        let client = MockIDOSClient()
        let timetable = IDOSTimetable(slug: "vlaky", displayName: "Trains")
        let model = ServiceDetailViewModel(
            id: "train-301",
            timetable: timetable,
            client: client
        )

        await model.load()

        let requestedTimetables = await client.serviceDetailRequestTimetables
        XCTAssertEqual(requestedTimetables, [timetable])
    }

    func testServiceDetailWindowLoadsARetargetedSelection() async {
        let client = MockIDOSClient()
        let selectionModel = ServiceDetailWindowSelectionTestModel(
            selection: ServiceSelection(id: "bus-13112")
        )
        let hostingView = NSHostingView(
            rootView: ServiceDetailWindowSelectionTestHost(
                selectionModel: selectionModel,
                client: client
            )
        )
        hostingView.frame = NSRect(x: 0, y: 0, width: 520, height: 640)
        let window = NSWindow(
            contentRect: hostingView.frame,
            styleMask: .titled,
            backing: .buffered,
            defer: false
        )
        window.contentView = hostingView
        window.makeKeyAndOrderFront(nil)
        defer { window.orderOut(nil) }

        let loadedInitialSelection = await waitForServiceDetailRequests(1, from: client)
        XCTAssertTrue(loadedInitialSelection)

        selectionModel.selection = ServiceSelection(id: "train-13104")

        let loadedRetargetedSelection = await waitForServiceDetailRequests(2, from: client)
        let requestIDs = await client.serviceDetailRequestIDs
        XCTAssertTrue(loadedRetargetedSelection)
        XCTAssertEqual(requestIDs, ["bus-13112", "train-13104"])
    }

    func testCompleteServiceDetailRendersAtCompactWindowWidth() {
        XCTAssertEqual(ServiceDetailView.defaultWindowWidth, 400)
        XCTAssertEqual(ServiceDetailView.minimumWindowWidth, 400)

        let hostingView = NSHostingView(
            rootView: ServiceDetailView(
                selection: ServiceSelection(id: "service-1"),
                client: MockIDOSClient(),
                showsItemDetails: false,
                showsStopNoteText: false
            )
            .frame(width: ServiceDetailView.minimumWindowWidth, height: 520)
        )
        hostingView.frame = NSRect(
            x: 0,
            y: 0,
            width: ServiceDetailView.minimumWindowWidth,
            height: 520
        )
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

        XCTAssertEqual(
            hostingView.frame.size,
            NSSize(width: ServiceDetailView.minimumWindowWidth, height: 520)
        )
        XCTAssertGreaterThan(hostingView.fittingSize.height, 0)
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
            connection: connection(id: "connection-window", timetableIdentifier: "vlaky"),
            timetable: IDOSTimetable(slug: "vlaky", displayName: "Trains")
        )

        let data = try JSONEncoder().encode(selection)
        let decoded = try JSONDecoder().decode(ConnectionSelection.self, from: data)

        XCTAssertEqual(decoded, selection)
        XCTAssertEqual(
            decoded.id,
            AppTransitValueIdentity(
                dataSourceID: .idos,
                timetableIdentifier: "vlaky",
                valueIdentifier: "connection-window"
            )
        )
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

    func testConnectionSelectionRestoresLegacyIDOSWindowTimetable() throws {
        struct LegacySelection: Encodable {
            let connection: TransitConnection
            let timetable: TransitTimetable
        }

        let timetable = IDOSTimetable(slug: "vlaky", displayName: "Trains")
        let data = try JSONEncoder().encode(
            LegacySelection(
                connection: connection(id: "legacy-connection"),
                timetable: timetable
            )
        )

        let decoded = try JSONDecoder().decode(ConnectionSelection.self, from: data)

        XCTAssertEqual(decoded.connection.dataSourceID, .idos)
        XCTAssertEqual(decoded.connection.timetableIdentifier, timetable.identifier)
        XCTAssertEqual(decoded.timetable, timetable)
    }

    func testConnectionSelectionCannotRouteThroughAnotherProvider() {
        let municipalConnection = TransitConnection(
            dataSourceID: "municipal",
            timetableIdentifier: "metro",
            id: "connection-42",
            departureTime: "08:00",
            departureStation: "River Market",
            arrivalTime: "08:10",
            arrivalStation: "Museum",
            duration: "10 min",
            legs: []
        )

        let selection = ConnectionSelection(
            connection: municipalConnection,
            timetable: IDOSTimetable(slug: "vlaky", displayName: "Trains")
        )

        XCTAssertEqual(selection.dataSourceID, TransitDataSourceID("municipal"))
        XCTAssertEqual(selection.timetable.dataSourceID, TransitDataSourceID("municipal"))
        XCTAssertEqual(selection.timetable.identifier, "metro")
    }

    func testResultOwnershipDoesNotFollowAMutableTimetablePicker() {
        let idos = TransitTimetable(
            dataSourceID: .idos,
            identifier: "shared",
            displayName: "IDOS Shared"
        )
        let municipal = TransitTimetable(
            dataSourceID: "municipal",
            identifier: "shared",
            displayName: "Municipal Shared"
        )
        let connection = TransitConnection(
            dataSourceID: municipal.dataSourceID,
            timetableIdentifier: municipal.identifier,
            id: "same-result-id",
            departureTime: "08:00",
            departureStation: "River Market",
            arrivalTime: "08:10",
            arrivalStation: "Museum",
            duration: "10 min",
            legs: []
        )
        let departure = TransitDeparture(
            dataSourceID: municipal.dataSourceID,
            timetableIdentifier: municipal.identifier,
            id: "same-result-id",
            time: "08:00",
            lineName: "M1",
            destination: "Museum"
        )

        XCTAssertEqual(connection.appTimetable(in: [idos, municipal]), municipal)
        XCTAssertEqual(departure.appTimetable(in: [idos, municipal]), municipal)
        let expectedIdentity = AppTransitValueIdentity(
            dataSourceID: "municipal",
            timetableIdentifier: "shared",
            valueIdentifier: "same-result-id"
        )
        XCTAssertEqual(connection.appIdentity, expectedIdentity)
        XCTAssertEqual(departure.appIdentity, expectedIdentity)

        XCTAssertNotEqual(
            AppTransitValueIdentity(
                dataSourceID: "municipal:shared",
                timetableIdentifier: "same",
                valueIdentifier: "result:id"
            ),
            AppTransitValueIdentity(
                dataSourceID: "municipal",
                timetableIdentifier: "shared:same",
                valueIdentifier: "result:id"
            )
        )
    }

    func testCompleteConnectionDetailRendersAtCompactWindowWidth() {
        XCTAssertEqual(ConnectionDetailView.defaultWindowWidth, 400)
        XCTAssertEqual(ConnectionDetailView.minimumWindowWidth, 400)
        let selection = ConnectionSelection(
            connection: connection(id: "connection-detail", timetableIdentifier: "vlaky"),
            timetable: IDOSTimetable(slug: "vlaky", displayName: "Trains")
        )
        let hostingView = NSHostingView(
            rootView: ConnectionDetailView(
                selection: selection,
                client: MockIDOSClient(),
                showsConnectionBadges: false,
                showsItemDetails: false,
                showsServiceInformationText: false,
                showsStopNoteText: false
            )
                .frame(width: ConnectionDetailView.minimumWindowWidth, height: 500)
        )
        hostingView.frame = NSRect(
            x: 0,
            y: 0,
            width: ConnectionDetailView.minimumWindowWidth,
            height: 500
        )
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

        XCTAssertEqual(
            hostingView.frame.size,
            NSSize(width: ConnectionDetailView.minimumWindowWidth, height: 500)
        )
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
        let viaSelection = PlaceFieldSelection(
            idosSelection: IDOSPlaceSelection(
                text: "Pardubice",
                listID: "100003",
                itemID: "5456463"
            ),
            kind: .train
        )
        model.fromSelection = fromSelection
        model.journeyOptions = [
            JourneyOptionEntry(viaPlace: " Pardubice ", viaSelection: viaSelection),
            JourneyOptionEntry(viaPlace: ""),
            JourneyOptionEntry(viaPlace: "Olomouc"),
            JourneyOptionEntry(
                kind: .transfers,
                transferConstraint: .maximumTransfers,
                maximumTransfers: 2
            ),
            JourneyOptionEntry(
                kind: .transfers,
                transferConstraint: .minimumTransferTime,
                minimumTransferTime: 5
            ),
            JourneyOptionEntry(
                kind: .transfers,
                transferConstraint: .maximumTransferTime,
                maximumTransferTime: 360
            ),
            JourneyOptionEntry(
                kind: .walkingDistances,
                walkingDistanceConstraint: .maximumWalkingTime,
                maximumWalkingTime: 45
            ),
            JourneyOptionEntry(
                kind: .walkingDistances,
                walkingDistanceConstraint: .maximumCityWalkingTime,
                maximumCityWalkingTime: 20
            ),
            JourneyOptionEntry(
                kind: .walkingTransfer,
                walkingTransferPolicy: .walkToNearbyStops,
                walkToNearbyStops: false
            ),
            JourneyOptionEntry(
                kind: .walkingTransfer,
                walkingTransferPolicy: .sameNameWalkingTransfersOnly,
                sameNameWalkingTransfersOnly: true
            ),
            JourneyOptionEntry(
                kind: .onlyConnections,
                connectionRequirement: .wheelchairAccessibleConnectionsOnly
            ),
            JourneyOptionEntry(
                kind: .onlyConnections,
                connectionRequirement: .lowFloorConnectionsOnly
            ),
            JourneyOptionEntry(
                kind: .onlyConnections,
                connectionRequirement: .trainConnectionsForWheelchairPassengers
            ),
            JourneyOptionEntry(
                kind: .onlyConnections,
                connectionRequirement: .trainConnectionsForPassengersWithChildren
            ),
            JourneyOptionEntry(
                kind: .onlyConnections,
                connectionRequirement: .connectionsForPassengersWithBicycles
            ),
            JourneyOptionEntry(kind: .preference, preference: .busyRoutes),
            JourneyOptionEntry(kind: .preference, preference: .trainsOverBuses),
            JourneyOptionEntry(
                kind: .bedOrCouchettePreference,
                bedOrCouchettePreference: .use
            ),
        ]
        model.isArrival = true

        await model.search()

        let request = await client.lastConnectionRequest
        XCTAssertEqual(request?.from, "Praha")
        XCTAssertEqual(request?.to, "Brno")
        XCTAssertEqual(request?.fromSelection, fromSelection.idosSelection)
        XCTAssertNil(request?.toSelection)
        XCTAssertEqual(request?.via, ["Pardubice", "Olomouc"])
        XCTAssertEqual(request?.viaSelections?.count, 2)
        XCTAssertEqual(request?.viaSelections?[0], viaSelection.idosSelection)
        XCTAssertNil(request?.viaSelections?[1])
        XCTAssertEqual(request?.timetable.slug, "vlaky")
        XCTAssertNil(request?.date)
        XCTAssertNil(request?.time)
        XCTAssertEqual(request?.serviceDate, TransitRequestFormatting.serviceDate(from: model.date))
        XCTAssertEqual(request?.serviceTime, TransitRequestFormatting.serviceTime(from: model.time))
        XCTAssertEqual(request?.isArrival, true)
        XCTAssertEqual(request?.maxTransfers, 2)
        XCTAssertEqual(request?.minimumTransferTime, 5)
        XCTAssertEqual(request?.maximumTransferTime, 360)
        XCTAssertEqual(request?.maximumWalkingTime, 45)
        XCTAssertEqual(request?.maximumCityWalkingTime, 20)
        XCTAssertEqual(request?.walkToNearbyStops, false)
        XCTAssertEqual(request?.sameNameWalkingTransfersOnly, true)
        XCTAssertEqual(request?.wheelchairAccessibleConnectionsOnly, true)
        XCTAssertEqual(request?.lowFloorConnectionsOnly, true)
        XCTAssertEqual(request?.preferTrainsOverBuses, true)
        XCTAssertEqual(request?.trainConnectionsForWheelchairPassengers, true)
        XCTAssertEqual(request?.trainConnectionsForPassengersWithChildren, true)
        XCTAssertEqual(request?.connectionsForPassengersWithBicycles, true)
        XCTAssertEqual(request?.preferBusyRoutes, true)
        XCTAssertEqual(request?.bedOrCouchettePreference, .use)
        XCTAssertEqual(request?.resultLimit, 10)
        let searchLanguage = await client.lastConnectionSearchLanguage
        XCTAssertEqual(searchLanguage, AppLanguagePreference.idosLanguage)
        XCTAssertEqual(model.connections.first?.id, "connection-1")
        XCTAssertTrue(model.hasCompletedSearch)
        XCTAssertNil(model.errorMessage)
    }

    func testUntouchedConnectionDateAndTimeStayCurrentUntilSearchOrEditing() async {
        let client = MockIDOSClient()
        let model = ConnectionsViewModel(client: client, calendarImporter: RecordingCalendarImporter())
        let firstNow = serviceDate(2026, 8, 1).addingTimeInterval(21 * 60 * 60)
        let nextMorning = serviceDate(2026, 8, 2).addingTimeInterval(10 * 60 * 60)

        model.refreshCurrentDateAndTime(now: firstNow)
        model.refreshCurrentDateAndTime(now: nextMorning)

        XCTAssertEqual(model.date, nextMorning)
        XCTAssertEqual(model.time, nextMorning)
        XCTAssertTrue(model.usesCurrentDateAndTime)

        model.from = "Praha"
        model.to = "Brno"
        await model.search()
        model.refreshCurrentDateAndTime(now: serviceDate(2026, 8, 3))

        XCTAssertEqual(model.date, nextMorning)
        XCTAssertEqual(model.time, nextMorning)
        XCTAssertFalse(model.usesCurrentDateAndTime)

        let editedModel = ConnectionsViewModel(
            client: MockIDOSClient(),
            calendarImporter: RecordingCalendarImporter()
        )
        editedModel.refreshCurrentDateAndTime(now: firstNow)
        editedModel.time = nextMorning
        editedModel.refreshCurrentDateAndTime(now: serviceDate(2026, 8, 3))

        XCTAssertEqual(editedModel.date, firstNow)
        XCTAssertEqual(editedModel.time, nextMorning)
        XCTAssertFalse(editedModel.usesCurrentDateAndTime)

        editedModel.selectCurrentDateAndTime(now: firstNow)

        XCTAssertEqual(editedModel.date, firstNow)
        XCTAssertEqual(editedModel.time, firstNow)
        XCTAssertTrue(editedModel.usesCurrentDateAndTime)
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
        model.timetable = IDOSTimetable(slug: "pid", displayName: "Prague + PID")

        XCTAssertNil(model.fromSelection)
    }

    func testViaPlaceSelectionsClearAfterEditingOrChangingTimetable() {
        let selection = PlaceFieldSelection(
            idosSelection: IDOSPlaceSelection(
                text: "Pardubice hl.n.",
                listID: "100003",
                itemID: "5456463"
            ),
            kind: .train
        )
        var entry = JourneyOptionEntry(
            viaPlace: selection.text,
            viaSelection: selection
        )

        entry.viaPlace = "Pardubice centrum"

        XCTAssertNil(entry.viaSelection)

        let model = ConnectionsViewModel(
            client: MockIDOSClient(),
            calendarImporter: RecordingCalendarImporter()
        )
        model.journeyOptions = [JourneyOptionEntry(
            viaPlace: selection.text,
            viaSelection: selection
        )]

        model.timetable = IDOSTimetable(slug: "pid", displayName: "Prague + PID")

        XCTAssertNil(model.journeyOptions[0].viaSelection)
    }

    func testBedOrCouchetteOptionFollowsTheSelectedTimetable() async {
        let client = MockIDOSClient()
        let model = ConnectionsViewModel(
            client: client,
            calendarImporter: RecordingCalendarImporter()
        )
        let option = JourneyOptionEntry(
            kind: .bedOrCouchettePreference,
            bedOrCouchettePreference: .use
        )
        model.journeyOptions = [option]

        XCTAssertTrue(model.supportedJourneyOptionKinds.contains(.bedOrCouchettePreference))

        model.timetable = IDOSTimetable(slug: "autobusy", displayName: "Buses")

        XCTAssertFalse(model.supportedJourneyOptionKinds.contains(.bedOrCouchettePreference))
        XCTAssertEqual(model.journeyOptions, [JourneyOptionEntry(id: option.id)])
        model.from = "Praha"
        model.to = "Brno"
        await model.search()
        let request = await client.lastConnectionRequest
        XCTAssertNil(request?.bedOrCouchettePreference)

        model.timetable = IDOSTimetable(slug: "vlakyautobusy", displayName: "Trains + Buses")

        XCTAssertTrue(model.supportedJourneyOptionKinds.contains(.bedOrCouchettePreference))
    }

    func testJourneyOptionRowsCanBeAddedAndRemovedWithoutDroppingTheLastField() {
        let model = ConnectionsViewModel(client: MockIDOSClient(), calendarImporter: RecordingCalendarImporter())
        let firstID = model.journeyOptions[0].id

        XCTAssertFalse(model.canRemoveJourneyOption(id: firstID))

        model.journeyOptions[0].viaPlace = "Pardubice"
        XCTAssertTrue(model.canRemoveJourneyOption(id: firstID))
        model.journeyOptions[0].viaPlace = ""
        XCTAssertFalse(model.canRemoveJourneyOption(id: firstID))

        model.addJourneyOption(after: firstID)
        XCTAssertEqual(model.journeyOptions.count, 2)
        XCTAssertTrue(model.canRemoveJourneyOption(id: firstID))

        let secondID = model.journeyOptions[1].id
        model.journeyOptions[1].viaPlace = "Olomouc"
        model.removeJourneyOption(id: firstID)
        XCTAssertEqual(model.viaPlaceNames, ["Olomouc"])
        XCTAssertTrue(model.canRemoveJourneyOption(id: secondID))

        model.removeJourneyOption(id: secondID)
        XCTAssertEqual(model.journeyOptions, [JourneyOptionEntry(id: secondID)])
        XCTAssertFalse(model.canRemoveJourneyOption(id: secondID))
    }

    func testJourneyOptionPickerKeepsSingletonConditionsUnique() {
        let model = ConnectionsViewModel(client: MockIDOSClient(), calendarImporter: RecordingCalendarImporter())
        let firstID = model.journeyOptions[0].id

        XCTAssertEqual(model.availableJourneyOptionKinds(for: firstID), JourneyOptionKind.allCases)

        model.setJourneyOptionKind(.bedOrCouchettePreference, for: firstID)
        model.addJourneyOption(after: firstID)
        let secondID = model.journeyOptions[1].id

        XCTAssertEqual(model.availableJourneyOptionKinds(for: firstID), JourneyOptionKind.allCases)
        XCTAssertEqual(
            model.availableJourneyOptionKinds(for: secondID),
            JourneyOptionKind.allCases.filter { $0 != .bedOrCouchettePreference }
        )

        model.removeJourneyOption(id: firstID)

        XCTAssertEqual(model.availableJourneyOptionKinds(for: secondID), JourneyOptionKind.allCases)
    }

    func testOnlyConnectionsCanRepeatWithDistinctRequirements() {
        let model = ConnectionsViewModel(client: MockIDOSClient(), calendarImporter: RecordingCalendarImporter())
        let firstID = model.journeyOptions[0].id

        model.setJourneyOptionKind(.onlyConnections, for: firstID)
        model.addJourneyOption(after: firstID)
        let secondID = model.journeyOptions[1].id
        model.setJourneyOptionKind(.onlyConnections, for: secondID)

        XCTAssertEqual(model.journeyOptions[0].connectionRequirement, .wheelchairAccessibleConnectionsOnly)
        XCTAssertEqual(model.journeyOptions[1].connectionRequirement, .lowFloorConnectionsOnly)
        XCTAssertTrue(model.availableJourneyOptionKinds(for: firstID).contains(.onlyConnections))
        XCTAssertTrue(model.availableJourneyOptionKinds(for: secondID).contains(.onlyConnections))
        XCTAssertTrue(
            model.availableConnectionRequirements(for: firstID)
                .contains(.wheelchairAccessibleConnectionsOnly)
        )
        XCTAssertFalse(
            model.availableConnectionRequirements(for: firstID)
                .contains(.lowFloorConnectionsOnly)
        )

        model.setConnectionRequirement(.lowFloorConnectionsOnly, for: firstID)
        XCTAssertEqual(model.journeyOptions[0].connectionRequirement, .wheelchairAccessibleConnectionsOnly)

        model.setConnectionRequirement(.trainConnectionsForWheelchairPassengers, for: firstID)
        XCTAssertEqual(model.journeyOptions[0].connectionRequirement, .trainConnectionsForWheelchairPassengers)
        XCTAssertTrue(
            model.availableConnectionRequirements(for: secondID)
                .contains(.wheelchairAccessibleConnectionsOnly)
        )
        XCTAssertFalse(
            model.availableConnectionRequirements(for: secondID)
                .contains(.trainConnectionsForWheelchairPassengers)
        )
    }

    func testPreferenceCanRepeatWithDistinctChoices() {
        let model = ConnectionsViewModel(client: MockIDOSClient(), calendarImporter: RecordingCalendarImporter())
        let firstID = model.journeyOptions[0].id

        model.setJourneyOptionKind(.preference, for: firstID)
        model.addJourneyOption(after: firstID)
        let secondID = model.journeyOptions[1].id
        model.setJourneyOptionKind(.preference, for: secondID)

        XCTAssertEqual(model.journeyOptions[0].preference, .busyRoutes)
        XCTAssertEqual(model.journeyOptions[1].preference, .trainsOverBuses)
        XCTAssertEqual(model.preferBusyRoutes, true)
        XCTAssertEqual(model.preferTrainsOverBuses, true)
        XCTAssertTrue(model.availableJourneyOptionKinds(for: firstID).contains(.preference))
        XCTAssertTrue(model.availableJourneyOptionKinds(for: secondID).contains(.preference))
        XCTAssertEqual(model.availableJourneyPreferences(for: firstID), [.busyRoutes])
        XCTAssertEqual(model.availableJourneyPreferences(for: secondID), [.trainsOverBuses])

        model.setJourneyPreference(.trainsOverBuses, for: firstID)
        XCTAssertEqual(model.journeyOptions[0].preference, .busyRoutes)

        model.removeJourneyOption(id: secondID)
        model.setJourneyPreference(.trainsOverBuses, for: firstID)
        XCTAssertEqual(model.journeyOptions[0].preference, .trainsOverBuses)
        XCTAssertNil(model.preferBusyRoutes)
        XCTAssertEqual(model.preferTrainsOverBuses, true)
    }

    func testWalkingDistancesCanRepeatWithDistinctConstraints() {
        let model = ConnectionsViewModel(client: MockIDOSClient(), calendarImporter: RecordingCalendarImporter())
        let firstID = model.journeyOptions[0].id

        model.setJourneyOptionKind(.walkingDistances, for: firstID)
        model.addJourneyOption(after: firstID)
        let secondID = model.journeyOptions[1].id
        model.setJourneyOptionKind(.walkingDistances, for: secondID)

        XCTAssertEqual(
            model.journeyOptions.map(\.walkingDistanceConstraint),
            [.maximumWalkingTime, .maximumCityWalkingTime]
        )
        XCTAssertEqual(model.maximumWalkingTime, 60)
        XCTAssertEqual(model.maximumCityWalkingTime, 10)
        XCTAssertTrue(model.availableJourneyOptionKinds(for: firstID).contains(.walkingDistances))
        XCTAssertTrue(model.availableJourneyOptionKinds(for: secondID).contains(.walkingDistances))
        XCTAssertEqual(
            model.availableWalkingDistanceConstraints(for: firstID),
            [.maximumWalkingTime]
        )
        XCTAssertEqual(
            model.availableWalkingDistanceConstraints(for: secondID),
            [.maximumCityWalkingTime]
        )

        model.setWalkingDistanceConstraint(.maximumCityWalkingTime, for: firstID)
        XCTAssertEqual(model.journeyOptions[0].walkingDistanceConstraint, .maximumWalkingTime)

        model.removeJourneyOption(id: secondID)
        model.setWalkingDistanceConstraint(.maximumCityWalkingTime, for: firstID)
        XCTAssertEqual(
            model.journeyOptions[0].walkingDistanceConstraint,
            .maximumCityWalkingTime
        )
        XCTAssertNil(model.maximumWalkingTime)
        XCTAssertEqual(model.maximumCityWalkingTime, 10)
    }

    func testWalkingTransferCanRepeatWithDistinctPolicies() {
        let model = ConnectionsViewModel(client: MockIDOSClient(), calendarImporter: RecordingCalendarImporter())
        let firstID = model.journeyOptions[0].id

        model.setJourneyOptionKind(.walkingTransfer, for: firstID)
        model.addJourneyOption(after: firstID)
        let secondID = model.journeyOptions[1].id
        model.setJourneyOptionKind(.walkingTransfer, for: secondID)

        XCTAssertEqual(
            model.journeyOptions.map(\.walkingTransferPolicy),
            [.walkToNearbyStops, .sameNameWalkingTransfersOnly]
        )
        XCTAssertEqual(model.walkToNearbyStops, true)
        XCTAssertEqual(model.sameNameWalkingTransfersOnly, false)
        XCTAssertTrue(model.availableJourneyOptionKinds(for: firstID).contains(.walkingTransfer))
        XCTAssertTrue(model.availableJourneyOptionKinds(for: secondID).contains(.walkingTransfer))
        XCTAssertEqual(
            model.availableWalkingTransferPolicies(for: firstID),
            [.walkToNearbyStops]
        )
        XCTAssertEqual(
            model.availableWalkingTransferPolicies(for: secondID),
            [.sameNameWalkingTransfersOnly]
        )

        model.setWalkingTransferPolicy(.sameNameWalkingTransfersOnly, for: firstID)
        XCTAssertEqual(model.journeyOptions[0].walkingTransferPolicy, .walkToNearbyStops)

        model.removeJourneyOption(id: secondID)
        model.setWalkingTransferPolicy(.sameNameWalkingTransfersOnly, for: firstID)
        XCTAssertEqual(
            model.journeyOptions[0].walkingTransferPolicy,
            .sameNameWalkingTransfersOnly
        )
        XCTAssertNil(model.walkToNearbyStops)
        XCTAssertEqual(model.sameNameWalkingTransfersOnly, false)
    }

    func testTransfersCanRepeatWithDistinctConstraints() {
        let model = ConnectionsViewModel(client: MockIDOSClient(), calendarImporter: RecordingCalendarImporter())
        let firstID = model.journeyOptions[0].id

        model.setJourneyOptionKind(.transfers, for: firstID)
        model.addJourneyOption(after: firstID)
        let secondID = model.journeyOptions[1].id
        model.setJourneyOptionKind(.transfers, for: secondID)
        model.addJourneyOption(after: secondID)
        let thirdID = model.journeyOptions[2].id
        model.setJourneyOptionKind(.transfers, for: thirdID)

        XCTAssertEqual(
            model.journeyOptions.map(\.transferConstraint),
            [.maximumTransfers, .minimumTransferTime, .maximumTransferTime]
        )
        XCTAssertTrue(model.availableJourneyOptionKinds(for: firstID).contains(.transfers))
        XCTAssertEqual(model.availableTransferConstraints(for: firstID), [.maximumTransfers])
        XCTAssertEqual(model.availableTransferConstraints(for: secondID), [.minimumTransferTime])
        XCTAssertEqual(model.availableTransferConstraints(for: thirdID), [.maximumTransferTime])

        model.setTransferConstraint(.minimumTransferTime, for: firstID)
        XCTAssertEqual(model.journeyOptions[0].transferConstraint, .maximumTransfers)

        model.removeJourneyOption(id: secondID)
        model.setTransferConstraint(.minimumTransferTime, for: firstID)
        XCTAssertEqual(model.journeyOptions[0].transferConstraint, .minimumTransferTime)
        XCTAssertNil(model.maximumTransfers)
        XCTAssertEqual(model.minimumTransferTime, -1)
    }

    func testDirectOnlyShortcutAddsVisibleZeroTransferCondition() {
        let model = ConnectionsViewModel(client: MockIDOSClient(), calendarImporter: RecordingCalendarImporter())
        let placeholder = model.journeyOptions[0]

        model.setOnlyDirect(true)

        XCTAssertTrue(model.onlyDirect)
        XCTAssertEqual(model.journeyOptions.count, 2)
        XCTAssertEqual(model.journeyOptions[0], placeholder)
        XCTAssertEqual(model.journeyOptions[1].kind, .transfers)
        XCTAssertEqual(model.journeyOptions[1].transferConstraint, .maximumTransfers)
        XCTAssertEqual(model.journeyOptions[1].maximumTransfers, 0)

        model.setOnlyDirect(false)

        XCTAssertFalse(model.onlyDirect)
        XCTAssertEqual(model.journeyOptions, [placeholder])

        model.setOnlyDirect(true)
        let directOptionID = model.journeyOptions[1].id
        model.setMaximumTransfers(1, for: directOptionID)

        XCTAssertFalse(model.onlyDirect)
        XCTAssertEqual(model.journeyOptions[1].kind, .transfers)
        XCTAssertEqual(model.journeyOptions[1].transferConstraint, .maximumTransfers)
        XCTAssertEqual(model.journeyOptions[1].maximumTransfers, 1)
    }

    func testDirectOnlyShortcutRemovesOnlyTransferTimeConditions() {
        let model = ConnectionsViewModel(client: MockIDOSClient(), calendarImporter: RecordingCalendarImporter())
        let viaOption = JourneyOptionEntry(viaPlace: "Pardubice")
        let transferOption = JourneyOptionEntry(
            kind: .transfers,
            transferConstraint: .maximumTransfers,
            maximumTransfers: 3
        )
        let walkingOption = JourneyOptionEntry(
            kind: .walkingDistances,
            walkingDistanceConstraint: .maximumWalkingTime,
            maximumWalkingTime: 45
        )
        model.journeyOptions = [
            viaOption,
            transferOption,
            JourneyOptionEntry(
                kind: .transfers,
                transferConstraint: .minimumTransferTime,
                minimumTransferTime: 5
            ),
            JourneyOptionEntry(
                kind: .transfers,
                transferConstraint: .maximumTransferTime,
                maximumTransferTime: 360
            ),
            walkingOption,
        ]

        XCTAssertFalse(model.onlyDirect)

        model.setOnlyDirect(true)
        model.setOnlyDirect(true)

        XCTAssertTrue(model.onlyDirect)
        XCTAssertEqual(model.journeyOptions.count, 3)
        XCTAssertEqual(model.journeyOptions.map(\.id), [viaOption.id, transferOption.id, walkingOption.id])
        XCTAssertEqual(model.maximumTransfers, 0)
        XCTAssertNil(model.minimumTransferTime)
        XCTAssertNil(model.maximumTransferTime)
        XCTAssertEqual(model.maximumWalkingTime, 45)
        XCTAssertEqual(model.availableTransferConstraints(for: transferOption.id), [.maximumTransfers])
        XCTAssertTrue(model.availableJourneyOptionKinds(for: transferOption.id).contains(.transfers))

        model.setOnlyDirect(false)

        XCTAssertFalse(model.onlyDirect)
        XCTAssertEqual(model.journeyOptions.map(\.id), [viaOption.id, walkingOption.id])
        XCTAssertTrue(
            model.availableJourneyOptionKinds(for: viaOption.id).contains(.transfers)
        )
        model.setJourneyOptionKind(.transfers, for: viaOption.id)
        XCTAssertEqual(model.journeyOptions[0].maximumTransfers, 3)
        model.setTransferConstraint(.minimumTransferTime, for: viaOption.id)
        XCTAssertEqual(model.journeyOptions[0].minimumTransferTime, 5)
    }

    func testZeroTransfersEnablesDirectOnlyAndRestoresRemovedTransferValuesWhenReadded() {
        let model = ConnectionsViewModel(client: MockIDOSClient(), calendarImporter: RecordingCalendarImporter())
        let transferOption = JourneyOptionEntry(
            kind: .transfers,
            transferConstraint: .maximumTransfers,
            maximumTransfers: 3
        )
        model.journeyOptions = [
            transferOption,
            JourneyOptionEntry(
                kind: .transfers,
                transferConstraint: .minimumTransferTime,
                minimumTransferTime: 5
            ),
            JourneyOptionEntry(
                kind: .transfers,
                transferConstraint: .maximumTransferTime,
                maximumTransferTime: 360
            ),
        ]

        model.setMaximumTransfers(0, for: transferOption.id)

        XCTAssertTrue(model.onlyDirect)
        XCTAssertEqual(model.journeyOptions.count, 1)
        XCTAssertEqual(model.journeyOptions[0].id, transferOption.id)
        XCTAssertEqual(model.journeyOptions[0].kind, .transfers)
        XCTAssertEqual(model.journeyOptions[0].transferConstraint, .maximumTransfers)
        XCTAssertEqual(model.journeyOptions[0].maximumTransfers, 0)

        model.setOnlyDirect(false)
        XCTAssertEqual(model.journeyOptions[0].kind, .via)
        model.setJourneyOptionKind(.transfers, for: transferOption.id)
        XCTAssertEqual(model.journeyOptions[0].maximumTransfers, 3)

        model.addJourneyOption(after: transferOption.id)
        let minimumTimeID = model.journeyOptions[1].id
        model.setJourneyOptionKind(.transfers, for: minimumTimeID)
        XCTAssertEqual(model.journeyOptions[1].transferConstraint, .minimumTransferTime)
        XCTAssertEqual(model.journeyOptions[1].minimumTransferTime, 5)

        model.addJourneyOption(after: minimumTimeID)
        let maximumTimeID = model.journeyOptions[2].id
        model.setJourneyOptionKind(.transfers, for: maximumTimeID)
        XCTAssertEqual(model.journeyOptions[2].transferConstraint, .maximumTransferTime)
        XCTAssertEqual(model.journeyOptions[2].maximumTransferTime, 360)
    }

    func testJourneyOptionValuePlaceholderDiffersFromViaConditionName() throws {
        let czech = try XCTUnwrap(localizationBundle(languageCode: "cs"))
        let english = try XCTUnwrap(localizationBundle(languageCode: "en"))

        XCTAssertEqual(czech.localizedString(forKey: "Via place", value: nil, table: nil), "Místo přes")
        XCTAssertEqual(english.localizedString(forKey: "Via place", value: nil, table: nil), "Via place")
        XCTAssertEqual(
            czech.localizedString(forKey: "Direct connections only", value: nil, table: nil),
            "Pouze přímá spojení"
        )
        XCTAssertEqual(
            english.localizedString(forKey: "Direct connections only", value: nil, table: nil),
            "Direct connections only"
        )
    }

    func testAdditionalJourneyOptionsUseLocalizedIDOSDurationsAndLabels() throws {
        let czech = try XCTUnwrap(localizationBundle(languageCode: "cs"))
        let english = try XCTUnwrap(localizationBundle(languageCode: "en"))

        XCTAssertEqual(
            czech.localizedString(forKey: "Maximum number", value: nil, table: nil),
            "Nejvyšší počet"
        )
        XCTAssertEqual(
            czech.localizedString(forKey: "Minimum time", value: nil, table: nil),
            "Nejnižší čas"
        )
        XCTAssertEqual(
            czech.localizedString(forKey: "Maximum time", value: nil, table: nil),
            "Nejvyšší čas"
        )
        XCTAssertEqual(
            english.localizedString(forKey: "Maximum number", value: nil, table: nil),
            "Maximum number"
        )
        XCTAssertEqual(
            english.localizedString(forKey: "Minimum time", value: nil, table: nil),
            "Minimum time"
        )
        XCTAssertEqual(
            english.localizedString(forKey: "Maximum time", value: nil, table: nil),
            "Maximum time"
        )
        XCTAssertEqual(
            JourneyTransferConstraint.localizedCatalogTitles,
            [
                AppLocalization.string("Maximum number"),
                AppLocalization.string("Minimum time"),
                AppLocalization.string("Maximum time")
            ]
        )
        XCTAssertEqual(
            czech.localizedString(forKey: "Maximum transfer time", value: nil, table: nil),
            "Nejvyšší čas na přestup"
        )
        XCTAssertEqual(
            czech.localizedString(forKey: "Minimum transfer time", value: nil, table: nil),
            "Nejnižší čas na přestup"
        )
        XCTAssertEqual(
            czech.localizedString(forKey: "Maximum distance to walk", value: nil, table: nil),
            "Nejvyšší délka přesunu"
        )
        XCTAssertEqual(
            czech.localizedString(
                forKey: "Maximum distance to walk, if there is Urban Public Transport available",
                value: nil,
                table: nil
            ),
            "Nejvyšší délka přesunu (MHD)"
        )
        XCTAssertEqual(
            czech.localizedString(forKey: "Walking distances", value: nil, table: nil),
            "Přesuny"
        )
        XCTAssertEqual(
            english.localizedString(forKey: "Walking distances", value: nil, table: nil),
            "Walking distances"
        )
        XCTAssertEqual(
            czech.localizedString(forKey: "Walking transfer", value: nil, table: nil),
            "Přesun"
        )
        XCTAssertEqual(
            english.localizedString(forKey: "Walking transfer", value: nil, table: nil),
            "Walking transfer"
        )
        XCTAssertEqual(
            czech.localizedString(forKey: "On foot between stops", value: nil, table: nil),
            "pěší mezi zastávkami"
        )
        XCTAssertEqual(
            czech.localizedString(forKey: "Between stops of the same name", value: nil, table: nil),
            "mezi zastávkami stejného jména"
        )
        XCTAssertEqual(
            czech.localizedString(forKey: "Also at the beginning/end of journey", value: nil, table: nil),
            "i na začátku/konci cesty"
        )
        XCTAssertEqual(
            czech.localizedString(forKey: "Only during transfers", value: nil, table: nil),
            "pouze při přestupu"
        )
        XCTAssertEqual(
            czech.localizedString(forKey: "Between any stops", value: nil, table: nil),
            "mezi libovolnými"
        )
        XCTAssertEqual(
            czech.localizedString(forKey: "Only stops of the same name", value: nil, table: nil),
            "pouze stejného jména"
        )
        XCTAssertEqual(
            english.localizedString(forKey: "Only during transfers", value: nil, table: nil),
            "only during transfers"
        )
        XCTAssertEqual(
            czech.localizedString(forKey: "Transfers", value: nil, table: nil),
            "Přestupy"
        )
        XCTAssertEqual(
            czech.localizedString(forKey: "Additional parameters", value: nil, table: nil),
            "Další možnosti"
        )
        XCTAssertEqual(
            czech.localizedString(forKey: "Only connections", value: nil, table: nil),
            "Pouze spojení"
        )
        XCTAssertEqual(
            english.localizedString(forKey: "Only connections", value: nil, table: nil),
            "Only connections"
        )
        XCTAssertEqual(
            czech.localizedString(forKey: "Prefer", value: nil, table: nil),
            "Upřednostňovat"
        )
        XCTAssertEqual(
            english.localizedString(forKey: "Prefer", value: nil, table: nil),
            "Prefer"
        )
        XCTAssertEqual(
            czech.localizedString(forKey: "Busy routes", value: nil, table: nil),
            "frekventované trasy"
        )
        XCTAssertEqual(
            czech.localizedString(forKey: "Trains instead of buses", value: nil, table: nil),
            "vlaky před autobusy"
        )
        XCTAssertEqual(
            czech.localizedString(
                forKey: "Wheelchair accessible connections only",
                value: nil,
                table: nil
            ),
            "Pouze bezbariérové"
        )
        XCTAssertEqual(
            czech.localizedString(forKey: "Low-floor lines only", value: nil, table: nil),
            "Pouze nízkopodlažní"
        )
        XCTAssertEqual(
            czech.localizedString(
                forKey: "Wheelchair accessible connections (trains)",
                value: nil,
                table: nil
            ),
            "Pro cestující na vozíku (vlaky)"
        )
        XCTAssertEqual(
            czech.localizedString(
                forKey: "Connections for passengers with children (trains)",
                value: nil,
                table: nil
            ),
            "Pro cestující s dětmi (vlaky)"
        )
        XCTAssertEqual(
            czech.localizedString(
                forKey: "Connections for passengers with bicycles (trains + buses)",
                value: nil,
                table: nil
            ),
            "Pro cestující s kolem (vlaky, autobusy)"
        )
        XCTAssertEqual(
            czech.localizedString(forKey: "Bed / Couchette", value: nil, table: nil),
            "Lůžka/Lehátka"
        )
        XCTAssertEqual(
            TransitBedOrCouchettePreference.noLimitation.localizedTitle(bundle: czech),
            "(bez omezení)"
        )
        XCTAssertEqual(
            TransitBedOrCouchettePreference.use.localizedTitle(bundle: czech),
            "použít"
        )
        XCTAssertEqual(
            TransitBedOrCouchettePreference.doNotUse.localizedTitle(bundle: czech),
            "nepoužít"
        )
        XCTAssertEqual(
            TransitBedOrCouchettePreference.noLimitation.localizedTitle(bundle: english),
            "(no limitation)"
        )
        XCTAssertEqual(
            TransitBedOrCouchettePreference.use.localizedTitle(bundle: english),
            "use"
        )
        XCTAssertEqual(
            TransitBedOrCouchettePreference.doNotUse.localizedTitle(bundle: english),
            "don't use"
        )
        XCTAssertEqual(czech.localizedString(forKey: "Yes", value: nil, table: nil), "Ano")
        XCTAssertEqual(czech.localizedString(forKey: "No", value: nil, table: nil), "Ne")
        XCTAssertEqual(
            JourneyOptionKind.allCases.filter { $0.group == .transfers },
            Array(JourneyOptionKind.allCases.prefix(4))
        )
        XCTAssertEqual(
            JourneyOptionKind.allCases.filter { $0.group == .additionalParameters },
            Array(JourneyOptionKind.allCases.suffix(3))
        )
        XCTAssertEqual(
            Set(JourneyOptionKind.allCases.flatMap(\.transitConnectionOptions)).union([.onlyDirect]),
            Set(TransitConnectionOption.allCases)
        )
        XCTAssertEqual(JourneyDurationChoice(minutes: -1).localizedTitle(bundle: czech), "Standardní")
        XCTAssertEqual(JourneyDurationChoice(minutes: 0).localizedTitle(bundle: czech), "0 minut")
        XCTAssertEqual(JourneyDurationChoice(minutes: 1).localizedTitle(bundle: czech), "1 minuta")
        XCTAssertEqual(JourneyDurationChoice(minutes: 2).localizedTitle(bundle: czech), "2 minuty")
        XCTAssertEqual(JourneyDurationChoice(minutes: 5).localizedTitle(bundle: czech), "5 minut")
        XCTAssertEqual(JourneyDurationChoice(minutes: 5).localizedTitle(bundle: english), "5 min")
        XCTAssertEqual(JourneyDurationChoice(minutes: 60).localizedTitle(bundle: czech), "1 hod")
        XCTAssertEqual(JourneyDurationChoice(minutes: 120).localizedTitle(bundle: english), "2 hr")
        XCTAssertEqual(
            JourneyDurationChoice.minimumTransferTimes.map(\.minutes),
            [-1, 0, 1, 2, 3, 4, 5, 10, 20, 30, 60]
        )
        XCTAssertEqual(
            JourneyDurationChoice.maximumTransferTimes.map(\.minutes),
            [10, 20, 30, 45, 60, 120, 240, 360, 480, 720, 1_080]
        )
        XCTAssertEqual(
            JourneyDurationChoice.maximumWalkingTimes.map(\.minutes),
            [0, 5, 10, 20, 30, 45, 60]
        )
    }

    func testJourneyOptionPickerUsesFullStableCatalogWidthWhenOnlyViaIsAvailable() throws {
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
        nativeCatalogButton.addItems(withTitles: JourneyOptionKind.localizedCatalogTitles)

        XCTAssertEqual(popupButton.sizingTitles, JourneyOptionKind.localizedCatalogTitles)
        XCTAssertEqual(
            popupButton.itemArray.filter { $0.representedObject == nil }.map(\.title),
            [JourneyOptionGroup.transfers.localizedTitle]
        )
        if #available(macOS 14.0, *) {
            XCTAssertTrue(popupButton.itemArray[0].isSectionHeader)
        } else {
            XCTAssertFalse(popupButton.itemArray[0].isEnabled)
        }
        XCTAssertEqual(popupButton.selectedItem?.representedObject as? String, JourneyOptionKind.via.rawValue)
        XCTAssertEqual(
            catalogWidth,
            nativeCatalogButton.intrinsicContentSize.width,
            accuracy: 0.5
        )
        XCTAssertEqual(popupButton.frame.width, catalogWidth, accuracy: 0.5)

        popupButton.sizingTitles = [JourneyOptionKind.via.localizedTitle]
        XCTAssertGreaterThan(catalogWidth, popupButton.intrinsicContentSize.width)
    }

    func testJourneyOptionPickerGroupsExistingAndNewConditions() throws {
        var selection = JourneyOptionKind.preference
        let picker = JourneyOptionKindPicker(
            selection: Binding(
                get: { selection },
                set: { selection = $0 }
            ),
            availableKinds: JourneyOptionKind.allCases
        )
        let hostingView = NSHostingView(rootView: picker)
        hostingView.frame = NSRect(x: 0, y: 0, width: 1_000, height: 30)
        hostingView.layoutSubtreeIfNeeded()

        let popupButton = try XCTUnwrap(
            ([hostingView] + hostingView.allDescendantViews)
                .compactMap { $0 as? StableWidthPopUpButton }
                .first
        )
        let headings = popupButton.itemArray.filter {
            !$0.isSeparatorItem && $0.representedObject == nil
        }
        let representedKinds = popupButton.itemArray.compactMap { item in
            (item.representedObject as? String).flatMap(JourneyOptionKind.init(rawValue:))
        }

        XCTAssertEqual(
            headings.map(\.title),
            JourneyOptionGroup.allCases.map(\.localizedTitle)
        )
        if #available(macOS 14.0, *) {
            XCTAssertTrue(headings.allSatisfy(\.isSectionHeader))
        } else {
            XCTAssertTrue(headings.allSatisfy { !$0.isEnabled })
            XCTAssertTrue(headings.allSatisfy { $0.attributedTitle != nil })
        }
        XCTAssertEqual(popupButton.itemArray.filter(\.isSeparatorItem).count, 1)
        XCTAssertEqual(representedKinds, JourneyOptionKind.allCases)
        XCTAssertEqual(
            popupButton.selectedItem?.representedObject as? String,
            JourneyOptionKind.preference.rawValue
        )

        let transfersItem = try XCTUnwrap(popupButton.itemArray.first {
            $0.representedObject as? String == JourneyOptionKind.transfers.rawValue
        })
        popupButton.select(transfersItem)
        popupButton.sendAction(popupButton.action, to: popupButton.target)

        XCTAssertEqual(selection, .transfers)
    }

    func testDirectOnlyRequestSetsZeroTransfersAndOmitsTransferTimes() async {
        let client = MockIDOSClient()
        let model = ConnectionsViewModel(client: client, calendarImporter: RecordingCalendarImporter())
        model.from = "Praha"
        model.to = "Brno"
        let transferOption = JourneyOptionEntry(
            kind: .transfers,
            transferConstraint: .maximumTransfers,
            maximumTransfers: 2
        )
        model.journeyOptions = [
            transferOption,
            JourneyOptionEntry(
                kind: .transfers,
                transferConstraint: .minimumTransferTime,
                minimumTransferTime: 5
            ),
            JourneyOptionEntry(
                kind: .transfers,
                transferConstraint: .maximumTransferTime,
                maximumTransferTime: 360
            ),
            JourneyOptionEntry(
                kind: .walkingDistances,
                walkingDistanceConstraint: .maximumWalkingTime,
                maximumWalkingTime: 45
            ),
        ]
        model.setMaximumTransfers(0, for: transferOption.id)

        XCTAssertEqual(model.transferLimitLabel, AppLocalization.string("Direct only"))

        await model.search()

        let request = await client.lastConnectionRequest
        XCTAssertEqual(request?.onlyDirect, true)
        XCTAssertEqual(request?.maxTransfers, 0)
        XCTAssertNil(request?.minimumTransferTime)
        XCTAssertNil(request?.maximumTransferTime)
        XCTAssertEqual(request?.maximumWalkingTime, 45)
    }

    func testTransferLimitUsesLocaleAwarePluralForms() throws {
        let czech = try XCTUnwrap(localizationBundle(languageCode: "cs"))
        let english = try XCTUnwrap(localizationBundle(languageCode: "en"))

        XCTAssertEqual(AppLocalization.locale(for: czech).identifier, "cs")
        XCTAssertEqual(AppLocalization.locale(for: english).identifier, "en")
        XCTAssertEqual(AppLocalization.pluralLocale(for: czech).identifier, "cs")
        XCTAssertEqual(AppLocalization.pluralLocale(for: english).identifier, "en")
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

    func testConnectionSearchRejectsMatchingFreeTextEndpointsWithoutCallingIDOS() async {
        let client = MockIDOSClient()
        let model = ConnectionsViewModel(client: client, calendarImporter: RecordingCalendarImporter())
        model.from = "  Frenštát pod Radhoštěm,,u škol  "
        model.to = "frenštát pod radhoštěm,,u škol"

        XCTAssertEqual(
            model.endpointValidationMessage,
            AppLocalization.string("Choose a different departure or arrival place.")
        )
        XCTAssertFalse(model.canSearch)

        await model.search()

        let request = await client.lastConnectionRequest
        XCTAssertNil(request)
        XCTAssertTrue(model.connections.isEmpty)
        XCTAssertEqual(
            model.errorMessage,
            AppLocalization.string("Choose a different departure or arrival place.")
        )
        XCTAssertFalse(model.showsRefreshActionForError)
    }

    func testConnectionSearchRejectsTheSameExactSelectedPlace() async {
        let client = MockIDOSClient()
        let model = ConnectionsViewModel(client: client, calendarImporter: RecordingCalendarImporter())
        let stop = PlaceFieldSelection(
            idosSelection: IDOSPlaceSelection(
                text: "Frenštát pod Radhoštěm,,u škol",
                listID: "100003",
                itemID: "5457076"
            ),
            kind: .bus
        )
        model.from = stop.text
        model.fromSelection = stop
        model.to = stop.text
        model.toSelection = stop

        XCTAssertEqual(
            model.endpointValidationMessage,
            AppLocalization.string("Choose a different departure or arrival place.")
        )
        XCTAssertFalse(model.canSearch)

        await model.search()

        let request = await client.lastConnectionRequest
        XCTAssertNil(request)
        XCTAssertEqual(
            model.errorMessage,
            AppLocalization.string("Choose a different departure or arrival place.")
        )
        XCTAssertFalse(model.showsRefreshActionForError)
    }

    func testConnectionSearchAllowsDifferentExactPlacesWithTheSameVisibleName() async {
        let client = MockIDOSClient()
        let model = ConnectionsViewModel(client: client, calendarImporter: RecordingCalendarImporter())
        let municipality = PlaceFieldSelection(
            idosSelection: IDOSPlaceSelection(text: "Ostrava", listID: "1", itemID: "10278"),
            kind: .municipality
        )
        let station = PlaceFieldSelection(
            idosSelection: IDOSPlaceSelection(text: "Ostrava", listID: "100003", itemID: "10288"),
            kind: .train
        )
        model.from = municipality.text
        model.fromSelection = municipality
        model.to = station.text
        model.toSelection = station

        XCTAssertNil(model.endpointValidationMessage)
        XCTAssertTrue(model.canSearch)

        await model.search()

        let request = await client.lastConnectionRequest
        XCTAssertEqual(request?.fromSelection, municipality.idosSelection)
        XCTAssertEqual(request?.toSelection, station.idosSelection)
        XCTAssertNil(model.errorMessage)
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
        XCTAssertNil(request?.date)
        XCTAssertNil(request?.time)
        XCTAssertEqual(request?.serviceDate, TransitRequestFormatting.serviceDate(from: model.date))
        XCTAssertEqual(request?.serviceTime, TransitRequestFormatting.serviceTime(from: model.time))
        XCTAssertEqual(request?.isArrival, true)
        let searchLanguage = await client.lastDepartureSearchLanguage
        XCTAssertEqual(searchLanguage, AppLanguagePreference.transitLanguage)
        XCTAssertEqual(model.departures.count, 20)
    }

    func testUntouchedDepartureDateAndTimeStayCurrentUntilSearchOrEditing() async {
        let client = MockIDOSClient()
        let model = DeparturesViewModel(client: client)
        let firstNow = serviceDate(2026, 8, 1).addingTimeInterval(21 * 60 * 60)
        let nextMorning = serviceDate(2026, 8, 2).addingTimeInterval(10 * 60 * 60)

        model.refreshCurrentDateAndTime(now: firstNow)
        model.refreshCurrentDateAndTime(now: nextMorning)

        XCTAssertEqual(model.date, nextMorning)
        XCTAssertEqual(model.time, nextMorning)
        XCTAssertTrue(model.usesCurrentDateAndTime)

        model.station = "Ostrava-Svinov"
        await model.search()
        model.refreshCurrentDateAndTime(now: serviceDate(2026, 8, 3))

        XCTAssertEqual(model.date, nextMorning)
        XCTAssertEqual(model.time, nextMorning)
        XCTAssertFalse(model.usesCurrentDateAndTime)

        let editedModel = DeparturesViewModel(client: MockIDOSClient())
        editedModel.refreshCurrentDateAndTime(now: firstNow)
        editedModel.date = nextMorning
        editedModel.refreshCurrentDateAndTime(now: serviceDate(2026, 8, 3))

        XCTAssertEqual(editedModel.date, nextMorning)
        XCTAssertEqual(editedModel.time, firstNow)
        XCTAssertFalse(editedModel.usesCurrentDateAndTime)

        editedModel.selectCurrentDateAndTime(now: nextMorning)

        XCTAssertEqual(editedModel.date, nextMorning)
        XCTAssertEqual(editedModel.time, nextMorning)
        XCTAssertTrue(editedModel.usesCurrentDateAndTime)
    }

    func testConnectionPagingPrependsAndAppendsUniqueResults() async {
        let client = MockIDOSClient()
        await client.configureConnectionPages(
            earlier: [
                connection(id: "connection-0", timetableIdentifier: "vlaky"),
                connection(id: "connection-1", timetableIdentifier: "vlaky"),
            ],
            later: [
                connection(id: "connection-1", timetableIdentifier: "vlaky"),
                connection(id: "connection-2", timetableIdentifier: "vlaky"),
            ]
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

    func testConnectionRefreshRecoversAnExpiredPagingSession() async {
        let client = MockIDOSClient()
        await client.configureConnectionPages(
            earlier: [connection(id: "connection-0")],
            later: []
        )
        let model = ConnectionsViewModel(client: client)
        model.from = "Praha"
        model.to = "Brno"

        await model.search()
        await client.expireConnectionPagingSession()
        await model.loadMore(.earlier)

        XCTAssertEqual(model.connections.map(\.id), ["connection-1"])
        XCTAssertNotNil(model.errorMessage)

        await model.refresh()

        XCTAssertNil(model.errorMessage)
        let searchCount = await client.connectionSearchCount
        XCTAssertEqual(searchCount, 2)
        XCTAssertTrue(model.canLoadEarlier)

        await model.loadMore(.earlier)

        XCTAssertEqual(model.connections.map(\.id), ["connection-0", "connection-1"])
    }

    func testDeparturePagingPrependsAndAppendsUniqueResults() async {
        let client = MockIDOSClient()
        await client.configureDeparturePages(
            earlier: [
                departure(id: "departure-0", timetableIdentifier: "vlaky"),
                departure(id: "departure-1", timetableIdentifier: "vlaky"),
            ],
            later: [
                departure(id: "departure-20", timetableIdentifier: "vlaky"),
                departure(id: "departure-21", timetableIdentifier: "vlaky"),
            ]
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
        let saver = RecordingCalendarSaver()
        let model = ConnectionsViewModel(
            client: client,
            calendarImporter: importer,
            calendarSaver: saver
        )
        let connection = IDOSConnection(
            id: "connection-1",
            departureTime: "12:00",
            departureStation: "Praha",
            arrivalTime: "14:30",
            arrivalStation: "Brno",
            duration: "2 h 30 min",
            legs: []
        )

        await model.performCalendarAction(.addToCalendar, for: connection)

        XCTAssertEqual(importer.calendarText, "BEGIN:VCALENDAR\nEND:VCALENDAR")
        XCTAssertNil(saver.calendarText)
        let language = await client.lastConnectionCalendarLanguage
        XCTAssertEqual(language, AppLanguagePreference.idosLanguage)
        XCTAssertNil(model.processingCalendarConnectionID)
        XCTAssertNil(model.errorMessage)
    }

    func testConnectionCalendarDownloadSavesICSWithoutOpeningCalendarApp() async {
        let client = MockIDOSClient()
        let importer = RecordingCalendarImporter()
        let saver = RecordingCalendarSaver()
        let model = ConnectionsViewModel(
            client: client,
            calendarImporter: importer,
            calendarSaver: saver
        )
        let connection = IDOSConnection(
            id: "connection-calendar-download",
            departureTime: "12:00",
            departureStation: "Praha / centrum",
            arrivalTime: "14:30",
            arrivalStation: "Brno: hlavní",
            duration: "2 h 30 min",
            legs: []
        )

        await model.performCalendarAction(.download, for: connection)

        XCTAssertNil(importer.calendarText)
        XCTAssertEqual(saver.calendarText, "BEGIN:VCALENDAR\nEND:VCALENDAR")
        XCTAssertTrue(saver.suggestedFileName?.contains("Praha") == true)
        XCTAssertTrue(saver.suggestedFileName?.contains("Brno") == true)
        XCTAssertTrue(saver.suggestedFileName?.hasSuffix(".ics") == true)
        XCTAssertFalse(saver.suggestedFileName?.contains("/") == true)
        XCTAssertFalse(saver.suggestedFileName?.contains(":") == true)
        XCTAssertNil(model.processingCalendarConnectionID)
        XCTAssertNil(model.errorMessage)
    }

    func testServiceCalendarImportUsesCalendarReturnedByIDOS() async {
        let client = MockIDOSClient()
        let importer = RecordingCalendarImporter()
        let saver = RecordingCalendarSaver()
        let model = ServiceDetailViewModel(
            id: "service-1",
            client: client,
            calendarImporter: importer,
            calendarSaver: saver
        )

        await model.performCalendarAction(.addToCalendar)

        XCTAssertEqual(importer.calendarText, "BEGIN:VCALENDAR\nEND:VCALENDAR")
        XCTAssertNil(saver.calendarText)
        let serviceID = await client.lastCalendarServiceID
        let language = await client.lastServiceCalendarLanguage
        XCTAssertEqual(serviceID, "service-1")
        XCTAssertEqual(language, AppLanguagePreference.idosLanguage)
        let requestCount = await client.serviceDetailRequestCount
        XCTAssertEqual(requestCount, 1)
        XCTAssertFalse(model.isProcessingCalendar)
        XCTAssertNil(model.actionErrorMessage)
    }

    func testServiceCalendarDownloadSavesICSWithoutOpeningCalendarApp() async {
        let client = MockIDOSClient()
        let importer = RecordingCalendarImporter()
        let saver = RecordingCalendarSaver()
        let model = ServiceDetailViewModel(
            id: "service-1",
            client: client,
            calendarImporter: importer,
            calendarSaver: saver
        )

        await model.performCalendarAction(.download)

        XCTAssertNil(importer.calendarText)
        XCTAssertEqual(saver.calendarText, "BEGIN:VCALENDAR\nEND:VCALENDAR")
        XCTAssertTrue(saver.suggestedFileName?.contains("Ostrava-Svinov") == true)
        XCTAssertTrue(saver.suggestedFileName?.hasSuffix(".ics") == true)
        let serviceID = await client.lastCalendarServiceID
        XCTAssertEqual(serviceID, "service-1")
        XCTAssertFalse(model.isProcessingCalendar)
        XCTAssertNil(model.actionErrorMessage)
    }

    func testServiceDetailLoadsExactOperatingDaysAndTimetableValidityForInformationCalendars() async {
        let client = MockIDOSClient()
        let model = ServiceDetailViewModel(id: "service-1", client: client)

        await model.load()

        XCTAssertEqual(model.timetableValidity?.validFrom, idosServiceDate(2025, 12, 14))
        XCTAssertEqual(model.timetableValidity?.validThrough, idosServiceDate(2026, 12, 12))
        XCTAssertEqual(
            model.serviceDateLimits?.status(on: idosServiceDate(2026, 8, 27)),
            .runs
        )
        let language = await client.lastServiceDateLimitsLanguage
        XCTAssertEqual(language, AppLanguagePreference.idosLanguage)
    }

    func testServicePDFOpensDocumentReturnedByIDOSInPreview() async {
        let client = MockIDOSClient()
        let opener = RecordingPDFOpener()
        let exporter = RecordingPDFExporter()
        let model = ServiceDetailViewModel(
            id: "service-1",
            client: client,
            pdfOpener: opener,
            pdfExporter: exporter
        )

        await model.performPDFAction(.openInPreview)

        XCTAssertEqual(opener.pdfData, Data("%PDF-1.4\nKaštan".utf8))
        XCTAssertTrue(opener.suggestedFileName?.contains("Ostrava-Svinov") == true)
        XCTAssertTrue(opener.suggestedFileName?.hasSuffix(".pdf") == true)
        XCTAssertNil(exporter.pdfData)
        let serviceID = await client.lastPDFServiceID
        let language = await client.lastServicePDFLanguage
        XCTAssertEqual(serviceID, "service-1")
        XCTAssertEqual(language, AppLanguagePreference.idosLanguage)
        XCTAssertFalse(model.isProcessingPDF)
        XCTAssertNil(model.actionErrorMessage)
    }

    func testServicePDFDownloadSavesWithoutOpeningPreview() async {
        let client = MockIDOSClient()
        let opener = RecordingPDFOpener()
        let exporter = RecordingPDFExporter()
        let model = ServiceDetailViewModel(
            id: "service-1",
            client: client,
            pdfOpener: opener,
            pdfExporter: exporter
        )

        await model.performPDFAction(.download)

        XCTAssertNil(opener.pdfData)
        XCTAssertEqual(exporter.pdfData, Data("%PDF-1.4\nKaštan".utf8))
        XCTAssertTrue(exporter.suggestedFileName?.contains("Ostrava-Svinov") == true)
        XCTAssertTrue(exporter.suggestedFileName?.hasSuffix(".pdf") == true)
        XCTAssertFalse(model.isProcessingPDF)
        XCTAssertNil(model.actionErrorMessage)
    }

    func testConnectionPDFOpensDocumentReturnedByIDOSInPreview() async {
        let client = MockIDOSClient()
        let opener = RecordingPDFOpener()
        let exporter = RecordingPDFExporter()
        let model = ConnectionsViewModel(
            client: client,
            pdfOpener: opener,
            pdfExporter: exporter
        )
        let connection = IDOSConnection(
            id: "connection-1",
            departureTime: "12:00",
            departureStation: "Praha / centrum",
            arrivalTime: "14:30",
            arrivalStation: "Brno: hlavní",
            duration: "2 h 30 min",
            legs: []
        )

        await model.performPDFAction(.openInPreview, for: connection)

        XCTAssertEqual(opener.pdfData, Data("%PDF-1.4\nKaštan".utf8))
        XCTAssertTrue(opener.suggestedFileName?.hasSuffix(".pdf") == true)
        XCTAssertNil(exporter.pdfData)
        let exportedLanguage = await client.lastPDFLanguage
        XCTAssertEqual(exportedLanguage, AppLanguagePreference.idosLanguage)
        XCTAssertNil(model.errorMessage)
        XCTAssertNil(model.processingPDFConnectionID)
    }

    func testConnectionPDFDownloadUsesRouteFileNameWithoutOpeningPreview() async {
        let client = MockIDOSClient()
        let opener = RecordingPDFOpener()
        let exporter = RecordingPDFExporter()
        let model = ConnectionsViewModel(
            client: client,
            pdfOpener: opener,
            pdfExporter: exporter
        )
        let connection = IDOSConnection(
            id: "connection-1",
            departureTime: "12:00",
            departureStation: "Praha / centrum",
            arrivalTime: "14:30",
            arrivalStation: "Brno: hlavní",
            duration: "2 h 30 min",
            legs: []
        )

        await model.performPDFAction(.download, for: connection)

        XCTAssertNil(opener.pdfData)
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
        XCTAssertNil(model.processingPDFConnectionID)
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

    func testPlaceSuggestionsDoNotStartWithoutTheAdvertisedCapability() {
        struct LimitedSource: TransitDataSource {
            let descriptor = TransitDataSourceDescriptor(
                id: "limited",
                displayName: "Limited Transit",
                capabilities: [.connections]
            )
        }

        let model = PlaceSuggestionsModel(client: LimitedSource(), scope: .places)
        model.update(
            query: "Market",
            timetable: TransitTimetable(
                dataSourceID: "limited",
                identifier: "network",
                displayName: "Network"
            )
        )

        XCTAssertFalse(model.isLoading)
        XCTAssertTrue(model.suggestions.isEmpty)
    }

    func testPlaceSuggestionVisibilityRefiltersTheLastResponseWithoutAnotherRequest() async throws {
        let client = MockIDOSClient()
        await client.configureSuggestions([
            IDOSSuggestion(text: "Praha", description: "municipality, district Praha"),
            IDOSSuggestion(text: "Smíchov/Praha", description: "borough, district Praha"),
            IDOSSuggestion(text: "Praha 1", description: "address, district Praha"),
            IDOSSuggestion(text: "Praha hl.n.", description: "station, district Praha, trains"),
        ])
        let model = PlaceSuggestionsModel(client: client, scope: .places)

        model.update(query: "Praha", timetable: .defaultTimetable)
        try await Task.sleep(nanoseconds: 350_000_000)
        model.updateVisibility(PlaceSuggestionVisibility(
            showsAddresses: false,
            showsBoroughs: false,
            showsMunicipalities: false
        ))

        XCTAssertEqual(model.suggestions.map(\.text), ["Praha hl.n."])
        let query = await client.lastSuggestionQuery
        let requestCount = await client.suggestionRequestCount
        XCTAssertEqual(query?.limit, 30)
        XCTAssertEqual(requestCount, 1)
    }

    func testStationTimetableSuggestionsUseSelectedODISMunicipality() async throws {
        let client = MockIDOSClient()
        let odis = try IDOSTimetable.resolve("odis")
        let municipality = try XCTUnwrap(
            IDOSStationTimetableMunicipality.resolve("Frýdek-Místek", timetable: odis)
        )
        let lines = PlaceSuggestionsModel(client: client, scope: .stationTimetableLines)
        let stops = PlaceSuggestionsModel(client: client, scope: .stationTimetableStops)

        lines.update(query: "301", timetable: odis, municipality: municipality)
        stops.update(
            query: "Ře",
            timetable: odis,
            line: "Bus 301",
            municipality: municipality
        )
        try await Task.sleep(nanoseconds: 350_000_000)

        let lineMunicipality = await client.lastStationTimetableLineMunicipality
        let stopMunicipality = await client.lastStationTimetableStopMunicipality
        XCTAssertEqual(lineMunicipality, municipality)
        XCTAssertEqual(stopMunicipality, municipality)
    }

    func testStationTimetableSearchUsesSelectedLineDirectionAndWeekMode() async {
        let client = MockIDOSClient()
        let model = StationTimetablesViewModel(client: client)
        model.selectTimetable(slug: "pid")
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
        XCTAssertNil(request?.date)
        XCTAssertEqual(request?.serviceDate, TransitRequestFormatting.serviceDate(from: model.date))
        XCTAssertEqual(language, AppLanguagePreference.transitLanguage)
        XCTAssertEqual(model.result?.selectedStop?.name, "Strašnická")
        XCTAssertNil(model.errorMessage)
    }

    func testStationTimetableMinuteResolvesAndOpensTheMatchingService() async throws {
        let client = MockIDOSClient()
        let model = StationTimetablesViewModel(client: client)
        model.date = try XCTUnwrap(Calendar.current.date(from: DateComponents(
            year: 2026,
            month: 8,
            day: 31
        )))
        model.selectTimetable(slug: "pid")
        model.selectLineSuggestion(IDOSSuggestion(
            text: "Bus 154",
            from: "Strašnická",
            to: "Sídliště Libuš"
        ))
        await client.configureDepartureResponses([
            "31.8.2026": [
                IDOSDeparture(
                    timetableIdentifier: "pid",
                    id: "pid:0-54986-31.08.2026 05:13:00",
                    stationName: "Strašnická",
                    time: "5:13",
                    lineName: "Bus 154",
                    destination: "Sídliště Libuš"
                ),
            ],
        ])

        await model.search()
        let result = try XCTUnwrap(model.result)
        let departure = try XCTUnwrap(StationTimetableDepartureReference(
            scheduleIndex: 0,
            schedule: result.schedules[0],
            hourIndex: 0,
            departureIndex: 0
        ))
        let selection = await model.serviceSelection(for: departure)
        let request = await client.lastDeparturesRequest

        XCTAssertEqual(
            selection?.id,
            AppTransitValueIdentity(
                dataSourceID: .idos,
                timetableIdentifier: "pid",
                valueIdentifier: "pid:0-54986-31.08.2026 05:13:00"
            )
        )
        XCTAssertEqual(
            selection?.highlight,
            ServiceRouteHighlight(fromStop: "Strašnická", toStop: "Sídliště Libuš")
        )
        XCTAssertEqual(request?.timetable.slug, "pid")
        XCTAssertEqual(request?.station, "Strašnická")
        XCTAssertNil(request?.date)
        XCTAssertNil(request?.time)
        XCTAssertEqual(request?.serviceDate, TransitDate(year: 2026, month: 8, day: 31))
        XCTAssertEqual(request?.serviceTime, TransitTime(hour: 5, minute: 13))
        let departureSearchLanguage = await client.lastDepartureSearchLanguage
        XCTAssertEqual(departureSearchLanguage, AppLanguagePreference.idosLanguage)
        XCTAssertNil(model.resolvingDeparture)
        XCTAssertNil(model.errorMessage)
    }

    func testStationTimetableMinuteTransfersItsResolvedPageIntoDepartures() async throws {
        let client = MockIDOSClient()
        let stationTimetableModel = StationTimetablesViewModel(client: client)
        stationTimetableModel.date = try XCTUnwrap(Calendar.current.date(from: DateComponents(
            year: 2026,
            month: 8,
            day: 31
        )))
        stationTimetableModel.selectTimetable(slug: "pid")
        stationTimetableModel.selectLineSuggestion(IDOSSuggestion(
            text: "Bus 154",
            from: "Strašnická",
            to: "Sídliště Libuš"
        ))
        let matchingDeparture = IDOSDeparture(
            timetableIdentifier: "pid",
            id: "pid:0-54986-31.08.2026 05:13:00",
            stationName: "Strašnická",
            time: "5:13",
            lineName: "Bus 154",
            destination: "Sídliště Libuš"
        )
        await client.configureDepartureResponses([
            "31.8.2026": [matchingDeparture],
        ])

        await stationTimetableModel.search()
        let result = try XCTUnwrap(stationTimetableModel.result)
        let departure = try XCTUnwrap(StationTimetableDepartureReference(
            scheduleIndex: 0,
            schedule: result.schedules[0],
            hourIndex: 0,
            departureIndex: 0
        ))
        let resolvedSearch = await stationTimetableModel.departureSearch(for: departure)
        let search = try XCTUnwrap(resolvedSearch)
        let departuresModel = DeparturesViewModel(client: client)
        departuresModel.isArrival = true
        departuresModel.present(search)

        XCTAssertEqual(departuresModel.timetable.slug, "pid")
        XCTAssertEqual(departuresModel.station, "Strašnická")
        XCTAssertNil(departuresModel.stationSelection)
        XCTAssertEqual(TransitRequestFormatting.displayDate(from: departuresModel.date), "31.8.2026")
        XCTAssertEqual(TransitRequestFormatting.displayTime(from: departuresModel.time), "5:13")
        XCTAssertFalse(departuresModel.isArrival)
        XCTAssertFalse(departuresModel.usesCurrentDateAndTime)
        XCTAssertEqual(departuresModel.departures, [matchingDeparture])
        XCTAssertNil(departuresModel.errorMessage)
        let requests = await client.departureRequests
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests.first, search.request)
    }

    func testWholeWeekMinuteUsesTheNearestConcreteOccurrence() async throws {
        let client = MockIDOSClient()
        let model = StationTimetablesViewModel(client: client)
        model.date = try XCTUnwrap(Calendar.current.date(from: DateComponents(
            year: 2026,
            month: 8,
            day: 31
        )))
        model.wholeWeek = true
        model.selectTimetable(slug: "pid")
        model.selectLineSuggestion(IDOSSuggestion(
            text: "Bus 154",
            from: "Strašnická",
            to: "Sídliště Libuš"
        ))
        await client.configureDepartureResponses([
            "4.9.2026": [
                IDOSDeparture(
                    timetableIdentifier: "pid",
                    id: "pid:0-54986-04.09.2026 05:13:00",
                    time: "5:13",
                    lineName: "Bus 154",
                    destination: "Sídliště Libuš"
                ),
            ],
        ])

        await model.search()
        let result = try XCTUnwrap(model.result)
        let departure = try XCTUnwrap(StationTimetableDepartureReference(
            scheduleIndex: 0,
            schedule: result.schedules[0],
            hourIndex: 0,
            departureIndex: 0
        ))
        let selection = await model.serviceSelection(for: departure)
        let requests = await client.departureRequests

        XCTAssertEqual(
            selection?.id,
            AppTransitValueIdentity(
                dataSourceID: .idos,
                timetableIdentifier: "pid",
                valueIdentifier: "pid:0-54986-04.09.2026 05:13:00"
            )
        )
        XCTAssertEqual(requests.map(\.serviceDate), [TransitDate(year: 2026, month: 9, day: 4)])
        XCTAssertNil(model.errorMessage)
    }

    func testUnavailableStationTimetableMinuteLeavesTheResultAndShowsGuidance() async throws {
        let client = MockIDOSClient()
        let model = StationTimetablesViewModel(client: client)
        model.selectTimetable(slug: "pid")
        model.selectLineSuggestion(IDOSSuggestion(
            text: "Bus 154",
            from: "Strašnická",
            to: "Sídliště Libuš"
        ))
        await client.configureDepartureResponses([:])

        await model.search()
        let result = try XCTUnwrap(model.result)
        let departure = try XCTUnwrap(StationTimetableDepartureReference(
            scheduleIndex: 0,
            schedule: result.schedules[0],
            hourIndex: 0,
            departureIndex: 0
        ))

        let selection = await model.serviceSelection(for: departure)

        XCTAssertNil(selection)
        XCTAssertEqual(
            model.errorMessage,
            AppLocalization.string(
                "%@ could not identify this station-timetable departure.",
                "IDOS"
            )
        )
        XCTAssertEqual(model.result, result)
        XCTAssertNil(model.resolvingDeparture)
    }

    func testStationTimetableResolutionUsesTheProviderWithoutInterpretingItsDisplayValue() async throws {
        let client = SymbolicStationTimetableSource()
        let model = StationTimetablesViewModel(client: client)
        model.date = serviceDate(2026, 8, 31)
        model.line = "Harbor loop"
        model.from = "Market"
        model.to = "Pier"
        await model.search()

        let result = try XCTUnwrap(model.result)
        let reference = try XCTUnwrap(StationTimetableDepartureReference(
            scheduleIndex: 0,
            schedule: result.schedules[0],
            hourIndex: 0,
            departureIndex: 0
        ))
        let resolvedSearch = await model.departureSearch(for: reference)
        let search = try XCTUnwrap(resolvedSearch)

        XCTAssertEqual(reference.value, "quarter past")
        XCTAssertEqual(search.page.departures.first?.id, "symbolic:quarter-past")
        XCTAssertEqual(search.request.serviceTime, TransitTime(hour: 8, minute: 15))
        XCTAssertNotEqual(
            try XCTUnwrap(client.serviceTimeZone).identifier,
            TimeZone.current.identifier
        )
        let departures = DeparturesViewModel(client: client)
        departures.present(search)
        XCTAssertEqual(
            TransitRequestFormatting.serviceDate(from: departures.date),
            TransitDate(year: 2026, month: 8, day: 31)
        )
        XCTAssertEqual(
            TransitRequestFormatting.serviceTime(from: departures.time),
            TransitTime(hour: 8, minute: 15)
        )
        XCTAssertNil(model.errorMessage)
    }

    func testTransitRequestFormattingKeepsGregorianValuesInTheDeviceTimeZone() throws {
        let timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Tokyo"))
        let serviceDate = TransitDate(year: 2026, month: 8, day: 31)
        let serviceTime = TransitTime(hour: 8, minute: 15)
        let value = try XCTUnwrap(TransitRequestFormatting.displayDateAndTime(
            serviceDate: serviceDate,
            serviceTime: serviceTime,
            timeZone: timeZone
        ))
        var buddhistCalendar = Calendar(identifier: .buddhist)
        buddhistCalendar.timeZone = timeZone

        XCTAssertNotEqual(
            buddhistCalendar.component(.year, from: value),
            serviceDate.year
        )
        XCTAssertEqual(
            TransitRequestFormatting.serviceDate(from: value, timeZone: timeZone),
            serviceDate
        )
        XCTAssertEqual(
            TransitRequestFormatting.serviceTime(from: value, timeZone: timeZone),
            serviceTime
        )
    }

    func testStationTimetableMunicipalitySelectionClearsAndScopesTheRoute() async throws {
        let client = MockIDOSClient()
        let model = StationTimetablesViewModel(client: client)
        model.selectTimetable(slug: "odis")
        model.selectLineSuggestion(IDOSSuggestion(
            text: "Tram 1",
            from: "Dubina",
            to: "Hlučínská"
        ))
        let municipality = try XCTUnwrap(
            model.municipalities.first { $0.name == "Frýdek-Místek" }
        )

        model.selectMunicipality(municipality)

        XCTAssertEqual(model.municipality, municipality)
        XCTAssertTrue(model.line.isEmpty)
        XCTAssertTrue(model.from.isEmpty)
        XCTAssertTrue(model.to.isEmpty)
        XCTAssertNil(model.result)

        model.selectLineSuggestion(IDOSSuggestion(
            text: "Bus 301",
            from: "Řepiště,,U kříže",
            to: "Místek,Riviéra"
        ))
        await model.search()

        let request = await client.lastStationTimetableRequest
        XCTAssertEqual(request?.municipality, municipality)
        XCTAssertEqual(model.result?.municipality, municipality)
    }

    func testStationTimetableStopSelectionStartsAtThatStop() async {
        let client = MockIDOSClient()
        let model = StationTimetablesViewModel(client: client)
        model.selectTimetable(slug: "pid")
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

    func testConnectionEmailLoadsIDOSDraftAndSendsNormalizedRecipients() async {
        let client = MockIDOSClient()
        let timetable = IDOSTimetable(slug: "vlaky", displayName: "Trains")
        let model = ConnectionEmailViewModel(
            connection: connection(id: "connection-email"),
            timetable: timetable,
            client: client
        )

        await model.load()

        let expectedAttribution = AppLocalization.string(
            "using the Kaštan app %@",
            ConnectionEmailMessage.projectWebsite.absoluteString
        )
        let expectedMessage = "Prepared by IDOS at https://idos.cz \(expectedAttribution)"
        XCTAssertEqual(model.message, expectedMessage)
        XCTAssertEqual(model.draft?.attachmentFileNames, ["connection.pdf", "connection.ics"])
        XCTAssertFalse(model.canSend)
        model.recipient = " alice@example.com; bob@example.org "
        XCTAssertTrue(model.canSend)

        await model.send()

        let recipient = await client.lastEmailRecipient
        let message = await client.lastEmailMessage
        let sentTimetable = await client.lastEmailTimetable
        let language = await client.lastEmailLanguage
        XCTAssertEqual(recipient, "alice@example.com, bob@example.org")
        XCTAssertEqual(message, expectedMessage)
        XCTAssertEqual(sentTimetable, timetable)
        XCTAssertEqual(language, AppLanguagePreference.idosLanguage)
        XCTAssertEqual(model.sentRecipient, recipient)
        XCTAssertFalse(model.canSend)
    }

    func testOptionEmailPreparesMailDraftWithGeneratedAttachmentsWithoutSending() async throws {
        let client = MockIDOSClient()
        let composer = RecordingConnectionEmailMailComposer()
        let timetable = IDOSTimetable(slug: "vlaky", displayName: "Trains")
        let model = ConnectionsViewModel(
            client: client,
            emailMailComposer: composer
        )
        model.timetable = timetable
        let connection = connection(
            id: "connection-mail-draft",
            timetableIdentifier: timetable.identifier
        )

        await model.composeEmailInMail(for: connection)

        let draft = try XCTUnwrap(composer.draft)
        XCTAssertEqual(draft.subject, "Connection detail")
        XCTAssertEqual(
            draft.message,
            ConnectionEmailMessage.localizedCreditingKastan(
                in: "Prepared by IDOS at https://idos.cz"
            )
        )
        XCTAssertTrue(draft.htmlMessage.hasPrefix("<!doctype html>"))
        XCTAssertTrue(draft.htmlMessage.contains("Prepared by IDOS at https://idos.cz"))
        XCTAssertTrue(draft.htmlMessage.contains("<table class=\"route-summary\">"))
        XCTAssertTrue(draft.htmlMessage.contains("connection-mail-draft") == false)
        XCTAssertTrue(draft.htmlMessage.contains("Praha hl.n."))
        XCTAssertTrue(draft.htmlMessage.contains("Brno hl.n."))
        let richMessage = try draft.attributedMessage()
        XCTAssertTrue(richMessage.string.contains("Prepared by IDOS at https://idos.cz"))
        XCTAssertTrue(richMessage.string.contains(AppLocalization.string("Connections")))
        XCTAssertTrue(richMessage.string.contains("Praha hl.n."))
        XCTAssertTrue(richMessage.string.contains("Brno hl.n."))
        var fontFamilies: Set<String> = []
        var fontSizes: Set<CGFloat> = []
        richMessage.enumerateAttribute(
            .font,
            in: NSRange(location: 0, length: richMessage.length)
        ) { value, _, _ in
            guard let font = value as? NSFont else { return }
            fontFamilies.insert(font.familyName ?? font.fontName)
            fontSizes.insert(font.pointSize)
        }
        let systemFont = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        XCTAssertEqual(fontFamilies, Set([systemFont.familyName ?? systemFont.fontName]))
        XCTAssertGreaterThan(fontSizes.count, 1, "Mail typography should retain its visual hierarchy")
        XCTAssertEqual(draft.attachments.map(\.fileName), ["connection.pdf", "connection.ics"])
        XCTAssertEqual(
            String(data: draft.attachments[0].data, encoding: .utf8),
            "%PDF-1.4\nKaštan"
        )
        XCTAssertEqual(
            String(data: draft.attachments[1].data, encoding: .utf8),
            "BEGIN:VCALENDAR\nEND:VCALENDAR"
        )
        let emailTimetable = await client.lastEmailTimetable
        let emailLanguage = await client.lastEmailLanguage
        let pdfLanguage = await client.lastPDFLanguage
        let calendarLanguage = await client.lastConnectionCalendarLanguage
        let recipient = await client.lastEmailRecipient
        XCTAssertEqual(emailTimetable, timetable)
        XCTAssertEqual(emailLanguage, AppLanguagePreference.idosLanguage)
        XCTAssertEqual(pdfLanguage, AppLanguagePreference.idosLanguage)
        XCTAssertEqual(calendarLanguage, AppLanguagePreference.idosLanguage)
        XCTAssertNil(recipient)
        XCTAssertNil(model.processingEmailConnectionID)
        XCTAssertNil(model.errorMessage)
    }

    func testConnectionEmailRejectsInvalidAddressesAndOversizedInput() async {
        let model = ConnectionEmailViewModel(
            connection: connection(id: "connection-email-validation"),
            timetable: IDOSTimetable(slug: "vlaky", displayName: "Trains"),
            client: MockIDOSClient()
        )
        await model.load()

        model.recipient = "not-an-email"
        XCTAssertTrue(model.recipientHasInvalidAddress)
        XCTAssertFalse(model.canSend)

        model.recipient = String(repeating: "a", count: ConnectionEmailViewModel.maximumRecipientLength + 1)
        XCTAssertTrue(model.recipientIsTooLong)
        XCTAssertFalse(model.canSend)

        model.recipient = "passenger@example.com"
        model.message = String(repeating: "x", count: ConnectionEmailViewModel.maximumMessageLength + 1)
        XCTAssertTrue(model.messageIsTooLong)
        XCTAssertFalse(model.canSend)

        model.message = String(repeating: "😀", count: ConnectionEmailViewModel.maximumMessageLength / 2 + 1)
        XCTAssertTrue(model.messageIsTooLong)
        XCTAssertFalse(model.canSend)
    }

    func testConnectionEmailAttachmentsOpenGeneratedPDFAndCalendarWithoutSending() async {
        let client = MockIDOSClient()
        let opener = RecordingConnectionEmailAttachmentOpener()
        let saver = RecordingConnectionEmailAttachmentSaver()
        let model = ConnectionEmailViewModel(
            connection: connection(id: "connection-email-attachments"),
            timetable: IDOSTimetable(slug: "vlaky", displayName: "Trains"),
            client: client,
            attachmentOpener: opener,
            attachmentSaver: saver
        )
        await model.load()

        await model.performAttachmentAction(named: "connection.pdf", action: .open)
        await model.performAttachmentAction(named: "connection.ics", action: .open)

        XCTAssertEqual(opener.attachments.map(\.fileName), ["connection.pdf", "connection.ics"])
        XCTAssertTrue(saver.attachments.isEmpty)
        XCTAssertEqual(String(data: opener.attachments[0].data, encoding: .utf8), "%PDF-1.4\nKaštan")
        XCTAssertEqual(
            String(data: opener.attachments[1].data, encoding: .utf8),
            "BEGIN:VCALENDAR\nEND:VCALENDAR"
        )
        let pdfLanguage = await client.lastPDFLanguage
        let calendarLanguage = await client.lastConnectionCalendarLanguage
        let recipient = await client.lastEmailRecipient
        XCTAssertEqual(pdfLanguage, AppLanguagePreference.idosLanguage)
        XCTAssertEqual(calendarLanguage, AppLanguagePreference.idosLanguage)
        XCTAssertNil(recipient)
        XCTAssertNil(model.processingAttachmentFileName)
        XCTAssertNil(model.errorMessage)
    }

    func testOptionChangesConnectionEmailAttachmentOpeningToDownload() throws {
        XCTAssertEqual(ConnectionEmailAttachmentAction.preferred(for: []), .open)
        XCTAssertEqual(ConnectionEmailAttachmentAction.preferred(for: [.command]), .open)
        XCTAssertEqual(ConnectionEmailAttachmentAction.preferred(for: [.option]), .download)
        XCTAssertEqual(
            ConnectionEmailAttachmentAction.preferred(for: [.option, .shift]),
            .download
        )
        XCTAssertEqual(ConnectionEmailAttachmentAction.open.systemImage, "arrow.up.right")
        XCTAssertEqual(ConnectionEmailAttachmentAction.download.systemImage, "arrow.down.to.line")

        let czech = try XCTUnwrap(localizationBundle(languageCode: "cs"))
        XCTAssertEqual(
            czech.localizedString(forKey: "Download attachment %@", value: nil, table: nil),
            "Stáhnout přílohu %@"
        )
    }

    func testConnectionEmailAttachmentsDownloadToSelectedDestinationWithoutOpeningOrSending() async {
        let client = MockIDOSClient()
        let opener = RecordingConnectionEmailAttachmentOpener()
        let saver = RecordingConnectionEmailAttachmentSaver()
        let model = ConnectionEmailViewModel(
            connection: connection(id: "connection-email-downloads"),
            timetable: IDOSTimetable(slug: "vlaky", displayName: "Trains"),
            client: client,
            attachmentOpener: opener,
            attachmentSaver: saver
        )
        await model.load()

        await model.performAttachmentAction(named: "connection.pdf", action: .download)
        await model.performAttachmentAction(named: "connection.ics", action: .download)

        XCTAssertTrue(opener.attachments.isEmpty)
        XCTAssertEqual(saver.attachments.map(\.fileName), ["connection.pdf", "connection.ics"])
        XCTAssertEqual(String(data: saver.attachments[0].data, encoding: .utf8), "%PDF-1.4\nKaštan")
        XCTAssertEqual(
            String(data: saver.attachments[1].data, encoding: .utf8),
            "BEGIN:VCALENDAR\nEND:VCALENDAR"
        )
        let recipient = await client.lastEmailRecipient
        XCTAssertNil(recipient)
        XCTAssertNil(model.processingAttachmentFileName)
        XCTAssertNil(model.errorMessage)
    }

    func testConnectionEmailAttachmentFileNameCannotEscapeItsTemporaryDirectory() {
        XCTAssertEqual(
            ConnectionEmailAttachmentFileName.safeValue("../private/Connection: Prague – Brno.pdf"),
            "Connection- Prague – Brno.pdf"
        )
        XCTAssertEqual(ConnectionEmailAttachmentFileName.safeValue(".."), "attachment")
    }
}

private func connection(
    id: String,
    duration: String = "2 h 30 min",
    timetableIdentifier: String = IDOSTimetable.defaultTimetable.identifier
) -> IDOSConnection {
    IDOSConnection(
        timetableIdentifier: timetableIdentifier,
        id: id,
        departureTime: "12:00",
        departureStation: "Praha hl.n.",
        arrivalTime: "14:30",
        arrivalStation: "Brno hl.n.",
        duration: duration,
        legs: []
    )
}

/// Delivers a native double-click to the rendered connection summary in either badge layout.
@MainActor
private func connectionCardOpenCount(
    afterDoubleClickAt location: NSPoint,
    showsConnectionBadges: Bool
) -> Int {
    var openCount = 0
    let card = ConnectionCard(
        number: 1,
        connection: connection(id: "connection-double-click"),
        timetable: IDOSTimetable(slug: "vlaky", displayName: "Trains"),
        client: MockIDOSClient(),
        isShortest: false,
        showsConnectionBadges: showsConnectionBadges,
        showsItemDetails: false,
        showsServiceInformationText: false,
        showsStopNoteText: false,
        isPerformingAction: false,
        showsActionMenu: false,
        showsOpenConnectionButton: false,
        timeFrameCoordinateSpace: nil,
        openConnection: { openCount += 1 },
        openService: { _ in },
        performEmailAction: { _ in },
        performCalendarAction: { _ in },
        performPDFAction: { _ in }
    )
    let hostingView = NSHostingView(
        rootView: card.frame(width: 700, height: 140, alignment: .topLeading)
    )
    hostingView.frame = NSRect(x: 0, y: 0, width: 700, height: 140)
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

    for clickCount in 1...2 {
        for eventType in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            let event = NSEvent.mouseEvent(
                with: eventType,
                location: location,
                modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime + Double(clickCount) * 0.01,
                windowNumber: window.windowNumber,
                context: nil,
                eventNumber: 0,
                clickCount: clickCount,
                pressure: eventType == .leftMouseDown ? 1 : 0
            )
            if let event {
                window.sendEvent(event)
            }
        }
    }

    return openCount
}

private func departure(
    id: String,
    timetableIdentifier: String = IDOSTimetable.defaultTimetable.identifier
) -> IDOSDeparture {
    IDOSDeparture(
        timetableIdentifier: timetableIdentifier,
        id: id,
        time: "16:00",
        lineName: "S2",
        destination: "Opava"
    )
}

@MainActor
private func forceClickPreviewAttachmentCount(in view: NSView) -> Int {
    (view is ForceClickPreviewAttachmentView ? 1 : 0) +
        view.subviews.reduce(0) { $0 + forceClickPreviewAttachmentCount(in: $1) }
}

@MainActor
private struct PresentedServicePreviewTestHost: View {
    let selection: ServiceSelection
    let client: any IDOSClienting
    @State private var isPreviewPresented = false

    var body: some View {
        Text("Preview anchor")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .forceClickPreview(
                size: ResultPreviewLayout.serviceSize,
                isPresented: $isPreviewPresented
            ) {
                ServiceDetailView(
                    selection: selection,
                    client: client,
                    showsItemDetails: false,
                    showsStopNoteText: false,
                    presentation: .preview
                )
            }
            .onAppear {
                isPreviewPresented = true
            }
    }
}

@MainActor
private final class ServiceDetailWindowSelectionTestModel: ObservableObject {
    @Published var selection: ServiceSelection

    init(selection: ServiceSelection) {
        self.selection = selection
    }
}

@MainActor
private struct ServiceDetailWindowSelectionTestHost: View {
    @ObservedObject var selectionModel: ServiceDetailWindowSelectionTestModel
    let client: any IDOSClienting

    var body: some View {
        ServiceDetailWindowContent(
            selection: selectionModel.selection,
            client: client,
            showsItemDetails: false,
            showsStopNoteText: false
        )
    }
}

@MainActor
private func waitForServiceDetailRequests(
    _ count: Int,
    from client: MockIDOSClient
) async -> Bool {
    for _ in 0..<100 {
        if (await client.serviceDetailRequestIDs).count >= count {
            return true
        }
        try? await Task.sleep(for: .milliseconds(10))
    }
    return false
}

@MainActor
private func waitForServicePreviewScrollView(
    in sourceWindow: NSWindow
) async -> NSScrollView? {
    for _ in 0..<100 {
        let previewContentViews = (sourceWindow.childWindows ?? [])
            .compactMap(\.contentView)
        let scrollViews = previewContentViews
            .flatMap { [$0] + $0.allDescendantViews }
            .compactMap { $0 as? NSScrollView }
            .filter { $0.frame.width >= ResultPreviewLayout.serviceSize.width - 20 }
            .filter { scrollView in
                (scrollView.documentView?.frame.height ?? 0) > scrollView.documentVisibleRect.height
            }
        if let scrollView = scrollViews.first {
            return scrollView
        }
        try? await Task.sleep(for: .milliseconds(10))
    }
    return nil
}

@MainActor
private func waitForServicePreviewInitialScroll(in scrollView: NSScrollView) async -> Bool {
    for _ in 0..<100 {
        if scrollView.documentVisibleRect.minY > 100 {
            return true
        }
        try? await Task.sleep(for: .milliseconds(10))
    }
    return false
}

@MainActor
private func stableDocumentHeight(in scrollView: NSScrollView) async -> CGFloat? {
    var previousHeight: CGFloat?
    var stableSamples = 0
    for _ in 0..<100 {
        guard let height = scrollView.documentView?.frame.height else { return nil }
        if let previousHeight, abs(previousHeight - height) <= 0.5 {
            stableSamples += 1
            if stableSamples >= 4 {
                return height
            }
        } else {
            stableSamples = 0
        }
        previousHeight = height
        try? await Task.sleep(for: .milliseconds(10))
    }
    return previousHeight
}

private func localizationBundle(languageCode: String) -> Bundle? {
    guard let url = Bundle.main.url(forResource: languageCode, withExtension: "lproj") else {
        return nil
    }
    return Bundle(url: url)
}

/// Finds visibly rendered pixels inside one horizontal slice of an offscreen SwiftUI view.
private func inkBounds(
    in bitmap: NSBitmapImageRep,
    xRange: Range<Int>,
    maximumBrightness: CGFloat
) -> CGRect? {
    var minimumX = bitmap.pixelsWide
    var minimumY = bitmap.pixelsHigh
    var maximumX = -1
    var maximumY = -1
    let lowerX = max(xRange.lowerBound, 0)
    let upperX = min(xRange.upperBound, bitmap.pixelsWide)

    for y in 0..<bitmap.pixelsHigh {
        for x in lowerX..<upperX {
            guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else {
                continue
            }
            let brightness = (color.redComponent + color.greenComponent + color.blueComponent) / 3
            guard color.alphaComponent > 0.1, brightness <= maximumBrightness else {
                continue
            }
            minimumX = min(minimumX, x)
            minimumY = min(minimumY, y)
            maximumX = max(maximumX, x)
            maximumY = max(maximumY, y)
        }
    }

    guard maximumX >= minimumX, maximumY >= minimumY else { return nil }
    return CGRect(
        x: minimumX,
        y: minimumY,
        width: maximumX - minimumX + 1,
        height: maximumY - minimumY + 1
    )
}

@MainActor
private final class RecordingCalendarImporter: CalendarImporting {
    private(set) var calendarText: String?

    func open(calendarText: String) throws {
        self.calendarText = calendarText
    }
}

@MainActor
private final class RecordingCalendarSaver: CalendarSaving {
    private(set) var calendarText: String?
    private(set) var suggestedFileName: String?

    func save(calendarText: String, suggestedFileName: String) throws {
        self.calendarText = calendarText
        self.suggestedFileName = suggestedFileName
    }
}

@MainActor
private final class RecordingPDFOpener: PDFOpening {
    private(set) var pdfData: Data?
    private(set) var suggestedFileName: String?

    func open(pdfData: Data, suggestedFileName: String) async throws {
        self.pdfData = pdfData
        self.suggestedFileName = suggestedFileName
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

@MainActor
private final class RecordingConnectionEmailMailComposer: ConnectionEmailMailComposing {
    private(set) var draft: ConnectionEmailMailDraft?

    func compose(_ draft: ConnectionEmailMailDraft) throws {
        self.draft = draft
    }
}

@MainActor
private final class RecordingConnectionEmailAttachmentOpener: ConnectionEmailAttachmentOpening {
    struct Attachment {
        let data: Data
        let fileName: String
    }

    private(set) var attachments: [Attachment] = []

    func open(data: Data, fileName: String) throws {
        attachments.append(Attachment(data: data, fileName: fileName))
    }
}

@MainActor
private final class RecordingConnectionEmailAttachmentSaver: ConnectionEmailAttachmentSaving {
    struct Attachment {
        let data: Data
        let fileName: String
    }

    private(set) var attachments: [Attachment] = []

    func save(data: Data, fileName: String) throws {
        attachments.append(Attachment(data: data, fileName: fileName))
    }
}

@MainActor
private final class StubCurrentLocationProvider: CurrentLocationProviding {
    let result: Result<CurrentLocationCoordinate, CurrentLocationError>
    private(set) var requestCount = 0

    init(result: Result<CurrentLocationCoordinate, CurrentLocationError>) {
        self.result = result
    }

    func currentLocation() async throws -> CurrentLocationCoordinate {
        requestCount += 1
        return try result.get()
    }
}

/// Supplies compact provider registries for per-window source-selection and capability tests.
private struct AppSourceSelectionTestSource: TransitDataSource {
    let descriptor: TransitDataSourceDescriptor
    let timetables: [TransitTimetable]
    let defaultTimetable: TransitTimetable
    let connectionRequestRecorder: AppConnectionRequestRecorder?

    init(
        id: TransitDataSourceID,
        name: String,
        timetableIdentifier: String,
        capabilities: Set<TransitDataSourceCapability>,
        connectionOptions: Set<TransitConnectionOption> = [],
        connectionRequestRecorder: AppConnectionRequestRecorder? = nil
    ) {
        descriptor = TransitDataSourceDescriptor(
            id: id,
            displayName: name,
            capabilities: capabilities,
            connectionOptions: connectionOptions
        )
        let timetable = TransitTimetable(
            dataSourceID: id,
            identifier: timetableIdentifier,
            displayName: "\(name) timetable"
        )
        timetables = [timetable]
        defaultTimetable = timetable
        self.connectionRequestRecorder = connectionRequestRecorder
    }

    func findConnections(request: TransitConnectionRequest) async throws -> [TransitConnection] {
        await connectionRequestRecorder?.record(request)
        return []
    }
}

/// Captures provider-neutral requests so capability tests can distinguish supported controls from active values.
private actor AppConnectionRequestRecorder {
    private var requests: [TransitConnectionRequest] = []

    var lastRequest: TransitConnectionRequest? {
        requests.last
    }

    func record(_ request: TransitConnectionRequest) {
        requests.append(request)
    }
}

/// Exercises app routing with a provider whose timetable values are not IDOS-formatted minutes.
private struct SymbolicStationTimetableSource: TransitDataSource {
    static let sourceID: TransitDataSourceID = "symbolic"
    static let timetable = TransitTimetable(
        dataSourceID: sourceID,
        identifier: "harbor",
        displayName: "Harbor Transit"
    )

    let descriptor = TransitDataSourceDescriptor(
        id: sourceID,
        displayName: "Symbolic Transit",
        capabilities: [
            .timetables,
            .stationTimetables,
            .departures,
            .stationTimetableDepartureResolution,
        ]
    )

    private static let providerTimeZone: TimeZone = {
        let tokyo = TimeZone(identifier: "Asia/Tokyo")!
        if tokyo.identifier != TimeZone.current.identifier {
            return tokyo
        }
        return TimeZone(identifier: "America/Los_Angeles")!
    }()

    var defaultTimetable: TransitTimetable { Self.timetable }
    var serviceTimeZone: TimeZone? { Self.providerTimeZone }

    func findStationTimetable(
        request: TransitStationTimetableRequest,
        language: TransitLanguage
    ) async throws -> TransitStationTimetable {
        TransitStationTimetable(
            timetable: Self.timetable,
            lineName: request.line,
            fromStop: request.from,
            toStop: request.to,
            stops: [TransitStationTimetableStop(name: request.from, isSelected: true)],
            schedules: [TransitStationTimetableSchedule(
                label: "market days",
                hours: [TransitStationTimetableHour(
                    hour: "morning",
                    departures: ["quarter past"]
                )]
            )]
        )
    }

    func resolveStationTimetableDeparture(
        request: TransitStationTimetableDepartureResolutionRequest,
        language: TransitLanguage
    ) async throws -> TransitStationTimetableDepartureResolution? {
        let value = request.stationTimetable.schedules[request.scheduleIndex]
            .hours[request.hourIndex].departures[request.departureIndex]
        guard value == "quarter past" else { return nil }
        let serviceTime = TransitTime(hour: 8, minute: 15)
        let departure = TransitDeparture(
            dataSourceID: Self.sourceID,
            timetableIdentifier: Self.timetable.identifier,
            id: "symbolic:quarter-past",
            time: value,
            lineName: "Harbor loop",
            destination: "Pier"
        )
        let departureRequest = TransitDeparturesRequest(
            timetable: Self.timetable,
            station: "Market",
            serviceDate: request.serviceDate,
            serviceTime: serviceTime
        )
        return TransitStationTimetableDepartureResolution(
            departure: departure,
            request: departureRequest,
            page: TransitDeparturePage(
                departures: [departure],
                dataSourceID: Self.sourceID
            ),
            serviceDate: request.serviceDate,
            serviceTime: serviceTime
        )
    }
}

private actor MockIDOSClient: IDOSClienting {
    nonisolated let descriptor = TransitDataSourceDescriptor.idos
    var lastConnectionRequest: IDOSConnectionRequest?
    var lastDeparturesRequest: IDOSDeparturesRequest?
    var departureRequests: [IDOSDeparturesRequest] = []
    var lastSuggestionQuery: SuggestionQuery?
    var lastConnectionSearchLanguage: IDOSLanguage?
    var lastDepartureSearchLanguage: IDOSLanguage?
    var lastPDFLanguage: IDOSLanguage?
    var lastConnectionCalendarLanguage: IDOSLanguage?
    var lastCalendarServiceID: String?
    var lastServiceCalendarLanguage: IDOSLanguage?
    var lastServiceDateLimitsLanguage: IDOSLanguage?
    var lastPDFServiceID: String?
    var lastServicePDFLanguage: IDOSLanguage?
    var lastStationTimetableRequest: IDOSStationTimetableRequest?
    var lastStationTimetableLanguage: IDOSLanguage?
    var lastStationTimetableLineMunicipality: IDOSStationTimetableMunicipality?
    var lastStationTimetableStopMunicipality: IDOSStationTimetableMunicipality?
    var lastEmailRecipient: String?
    var lastEmailMessage: String?
    var lastEmailTimetable: IDOSTimetable?
    var lastEmailLanguage: IDOSLanguage?
    var connectionPageDirections: [IDOSPageDirection] = []
    var departurePageDirections: [IDOSPageDirection] = []
    var connectionSearchCount = 0
    var suggestionRequestCount = 0
    var serviceDetailRequestCount = 0
    var serviceDetailRequestIDs: [String] = []
    var serviceDetailRequestTimetables: [IDOSTimetable] = []
    private var serviceShareURL: String?
    private var configuredServiceDetail: IDOSServiceDetail?
    private var connectionPages: [IDOSPageDirection: [IDOSConnection]] = [:]
    private var departurePages: [IDOSPageDirection: [IDOSDeparture]] = [:]
    private var connectionPagingSessionExpired = false
    private var configuredSuggestions: [IDOSSuggestion]?
    private var departureResponsesByDate: [String: [IDOSDeparture]]?

    func configureSuggestions(_ suggestions: [IDOSSuggestion]) {
        configuredSuggestions = suggestions
    }

    func configureDepartureResponses(_ responses: [String: [IDOSDeparture]]) {
        departureResponsesByDate = responses
    }

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

    func expireConnectionPagingSession() {
        connectionPagingSessionExpired = true
    }

    func configureServiceShareURL(_ value: String?) {
        serviceShareURL = value
    }

    func configureServiceDetail(_ service: IDOSServiceDetail) {
        configuredServiceDetail = service
    }

    func suggest(prefix: String, limit: Int, timetable: IDOSTimetable) async throws -> [IDOSSuggestion] {
        suggestionRequestCount += 1
        lastSuggestionQuery = SuggestionQuery(
            prefix: prefix,
            timetableSlug: timetable.slug,
            limit: limit
        )
        return configuredSuggestions ?? [IDOSSuggestion(text: "Praha hl.n.")]
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

    func searchStationTimetableLines(
        prefix: String,
        limit: Int,
        timetable: IDOSTimetable,
        municipality: IDOSStationTimetableMunicipality?
    ) async throws -> [IDOSSuggestion] {
        lastStationTimetableLineMunicipality = municipality
        return [IDOSSuggestion(text: "Bus 301", from: "Řepiště,,U kříže", to: "Místek,Riviéra")]
    }

    func searchStationTimetableStops(
        prefix: String,
        line: String,
        limit: Int,
        timetable: IDOSTimetable
    ) async throws -> [IDOSSuggestion] {
        [IDOSSuggestion(text: "Strašnická")]
    }

    func searchStationTimetableStops(
        prefix: String,
        line: String,
        limit: Int,
        timetable: IDOSTimetable,
        municipality: IDOSStationTimetableMunicipality?
    ) async throws -> [IDOSSuggestion] {
        lastStationTimetableStopMunicipality = municipality
        return [IDOSSuggestion(text: "Řepiště,,U kříže")]
    }

    func findStationTimetable(
        request: IDOSStationTimetableRequest,
        language: IDOSLanguage
    ) async throws -> IDOSStationTimetable {
        lastStationTimetableRequest = request
        lastStationTimetableLanguage = language
        return IDOSStationTimetable(
            timetable: request.timetable,
            municipality: request.municipality,
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
                    hours: [IDOSStationTimetableHour(hour: "5", departures: ["13", "35A"])]
                )
            ],
            explanations: ["A: runs only to stop Háje"],
            notes: ["valid from 1.7.2026"]
        )
    }

    func resolveStationTimetableDeparture(
        request: TransitStationTimetableDepartureResolutionRequest,
        language: TransitLanguage
    ) async throws -> TransitStationTimetableDepartureResolution? {
        guard let reference = IDOSStationTimetableDepartureReference(request: request) else {
            return nil
        }
        for candidateDate in IDOSStationTimetableDepartureResolver.candidateServiceDates(
            for: reference.scheduleLabel,
            searchDate: request.serviceDate,
            wholeWeek: request.wholeWeek
        ) {
            guard let serviceDate = IDOSStationTimetableDepartureResolver.addingDays(
                reference.dayOffset,
                to: candidateDate
            ), let selectedStop = request.stationTimetable.selectedStop
            else {
                continue
            }
            let departureRequest = TransitDeparturesRequest(
                timetable: request.stationTimetable.timetable,
                station: selectedStop.name,
                serviceDate: serviceDate,
                serviceTime: reference.serviceTime,
                isArrival: false
            )
            let page = try await findDeparturesPage(request: departureRequest, language: language)
            guard let departure = IDOSStationTimetableDepartureResolver.matchingDeparture(
                in: page.departures,
                reference: reference,
                timetable: request.stationTimetable
            ) else {
                continue
            }
            return TransitStationTimetableDepartureResolution(
                departure: departure,
                request: departureRequest,
                page: page,
                serviceDate: serviceDate,
                serviceTime: reference.serviceTime
            )
        }
        return nil
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

    func serviceDateLimits(
        for service: IDOSServiceDetail,
        language: IDOSLanguage
    ) async throws -> IDOSServiceDateLimits {
        lastServiceDateLimitsLanguage = language
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Prague")!
        let date = calendar.date(from: DateComponents(year: 2026, month: 8, day: 27))!
        return IDOSServiceDateLimits(
            referenceDate: date,
            days: [.init(date: date, status: .runs)]
        )
    }

    func findConnections(request: IDOSConnectionRequest) async throws -> [IDOSConnection] {
        connectionSearchCount += 1
        connectionPagingSessionExpired = false
        lastConnectionRequest = request
        return [
            IDOSConnection(
                dataSourceID: request.timetable.dataSourceID,
                timetableIdentifier: request.timetable.identifier,
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
        request: IDOSConnectionRequest,
        language: IDOSLanguage
    ) async throws -> IDOSConnectionPage {
        lastConnectionSearchLanguage = language
        return try await findConnectionsPage(request: request)
    }

    func findConnectionsPage(
        from page: IDOSConnectionPage,
        direction: IDOSPageDirection
    ) async throws -> IDOSConnectionPage {
        connectionPageDirections.append(direction)
        if connectionPagingSessionExpired {
            throw IDOSError.invalidResponse
        }
        return IDOSConnectionPage(
            connections: connectionPages[direction] ?? [],
            canLoadEarlier: connectionPages[.earlier] != nil,
            canLoadLater: connectionPages[.later] != nil
        )
    }

    func connectionCalendar(for connection: IDOSConnection, timetable: IDOSTimetable) async throws -> String {
        "BEGIN:VCALENDAR\nEND:VCALENDAR"
    }

    func connectionEmailDraft(
        for connection: IDOSConnection,
        timetable: IDOSTimetable,
        language: IDOSLanguage
    ) async throws -> IDOSConnectionEmailDraft {
        lastEmailTimetable = timetable
        lastEmailLanguage = language
        return IDOSConnectionEmailDraft(
            message: "Prepared by IDOS at https://idos.cz",
            description: "Connection detail",
            attachmentFileNames: ["connection.pdf", "connection.ics"]
        )
    }

    func sendConnectionByEmail(
        _ connection: IDOSConnection,
        to recipient: String,
        message: String,
        timetable: IDOSTimetable,
        language: IDOSLanguage
    ) async throws {
        lastEmailRecipient = recipient
        lastEmailMessage = message
        lastEmailTimetable = timetable
        lastEmailLanguage = language
    }

    func connectionCalendar(
        for connection: IDOSConnection,
        timetable: IDOSTimetable,
        language: IDOSLanguage
    ) async throws -> String {
        lastConnectionCalendarLanguage = language
        return "BEGIN:VCALENDAR\nEND:VCALENDAR"
    }

    func serviceCalendar(for service: IDOSServiceDetail) async throws -> String {
        lastCalendarServiceID = service.id
        return "BEGIN:VCALENDAR\nEND:VCALENDAR"
    }

    func serviceCalendar(for service: IDOSServiceDetail, language: IDOSLanguage) async throws -> String {
        lastCalendarServiceID = service.id
        lastServiceCalendarLanguage = language
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
        departureRequests.append(request)
        if let departureResponsesByDate {
            let date = request.date ?? request.serviceDate.map {
                "\($0.day).\($0.month).\($0.year)"
            } ?? ""
            return departureResponsesByDate[date] ?? []
        }
        return (1...25).map { index in
            IDOSDeparture(
                dataSourceID: request.timetable.dataSourceID,
                timetableIdentifier: request.timetable.identifier,
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
        request: IDOSDeparturesRequest,
        language: IDOSLanguage
    ) async throws -> IDOSDeparturePage {
        lastDepartureSearchLanguage = language
        return try await findDeparturesPage(request: request)
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
        serviceDetailRequestCount += 1
        serviceDetailRequestIDs.append(id)
        serviceDetailRequestTimetables.append(timetable)
        if let configuredServiceDetail {
            return configuredServiceDetail
        }
        return IDOSServiceDetail(
            id: id,
            timetable: timetable,
            name: "S2",
            stops: [IDOSServiceStop(name: "Ostrava-Svinov")],
            shareURL: serviceShareURL
        )
    }
}

private struct SuggestionQuery: Sendable {
    let prefix: String
    let timetableSlug: String
    let limit: Int
}

/// Marks both sides of a supplemental search row so its rendered alignment can be verified.
private struct SearchSupplementLayoutProbe: NSViewRepresentable {
    let name: String

    func makeNSView(context: Context) -> SearchSupplementLayoutProbeView {
        SearchSupplementLayoutProbeView(name: name)
    }

    func updateNSView(_ nsView: SearchSupplementLayoutProbeView, context: Context) {}
}

private final class SearchSupplementLayoutProbeView: NSView {
    let name: String

    init(name: String) {
        self.name = name
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is unavailable")
    }
}

private extension NSView {
    var allDescendantViews: [NSView] {
        subviews + subviews.flatMap(\.allDescendantViews)
    }
}
