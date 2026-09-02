import Foundation
@testable import Kastan
import Testing
@testable import KastanCLI

/// Applies the provider invariants every concrete data-source test suite can reuse.
func expectTransitDataSourceContract(
    _ dataSource: any TransitDataSource,
    connectionOptions expectedConnectionOptions: Set<TransitConnectionOption>
) {
    let descriptor = dataSource.descriptor
    let timetableIdentifiers = dataSource.timetables.map { $0.identifier.lowercased() }

    #expect(!descriptor.id.rawValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    #expect(!descriptor.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    #expect(descriptor.supports(.timetables))
    #expect(descriptor.connectionOptions == expectedConnectionOptions)
    #expect(descriptor.connectionOptions.isEmpty || descriptor.supports(.connections))
    #expect(dataSource.defaultTimetable.dataSourceID == descriptor.id)
    #expect(dataSource.timetables.contains(dataSource.defaultTimetable))
    #expect(dataSource.timetables.allSatisfy { $0.dataSourceID == descriptor.id })
    #expect(Set(timetableIdentifiers).count == timetableIdentifiers.count)
}

/// Exercises the reusable provider contract against both complete and conservative declarations.
@Suite struct TransitDataSourceProviderContractTests {
    @Test func builtInProvider() {
        expectTransitDataSourceContract(
            IDOSDataSource(),
            connectionOptions: Set(TransitConnectionOption.allCases)
        )
    }

    @Test func customProviderWithNoImpliedOptions() {
        expectTransitDataSourceContract(
            MunicipalTransitDataSource(),
            connectionOptions: []
        )
    }

    @Test func customProviderWithExplicitOptions() {
        expectTransitDataSourceContract(
            RegionalTransitDataSource(),
            connectionOptions: [.onlyDirect, .via]
        )
    }
}

/// Keeps the built-in provider's identity and complete product contract discoverable through neutral metadata.
@Test func builtInDescriptorAdvertisesEveryTransitCapability() {
    let descriptor = TransitDataSourceDescriptor.idos

    #expect(descriptor.id == .idos)
    #expect(descriptor.displayName == "IDOS")
    #expect(descriptor.capabilities == Set(TransitDataSourceCapability.allCases))
    #expect(descriptor.connectionOptions == Set(TransitConnectionOption.allCases))
    #expect(IDOSDataSource.descriptor == descriptor)
    #expect(IDOSDataSource().descriptor == descriptor)
}

/// Keeps every IDOS connection control discoverable without implying support for custom or legacy providers.
@Test func connectionOptionsRequireExplicitProviderSupport() {
    let custom = MunicipalTransitDataSource().descriptor
    let legacy = LegacyTransitClient().descriptor

    #expect(TransitConnectionOption.allCases == [
        .onlyDirect,
        .via,
        .maximumTransfers,
        .minimumTransferTime,
        .maximumTransferTime,
        .maximumWalkingTime,
        .maximumCityWalkingTime,
        .walkToNearbyStops,
        .sameNameWalkingTransfersOnly,
    ])
    #expect(TransitConnectionOption.allCases.allSatisfy(TransitDataSourceDescriptor.idos.supports))
    #expect(custom.supports(.connections))
    #expect(custom.connectionOptions.isEmpty)
    #expect(legacy.supports(.connections))
    #expect(legacy.connectionOptions.isEmpty)
}

/// Preserves stored descriptors from before connection-option discovery while round-tripping explicit support.
@Test func descriptorJSONPreservesFineGrainedOptionCompatibility() throws {
    let legacyJSON = Data(
        #"{"id":"regional","displayName":"Regional Transit","capabilities":["connections","timetables"]}"#.utf8
    )
    let decoder = JSONDecoder()
    let legacy = try decoder.decode(TransitDataSourceDescriptor.self, from: legacyJSON)

    #expect(legacy.connectionOptions.isEmpty)

    let legacyReencoded = try JSONSerialization.jsonObject(with: JSONEncoder().encode(legacy))
    let legacyObject = try #require(legacyReencoded as? [String: Any])
    #expect(legacyObject["connectionOptions"] == nil)

    let declared = TransitDataSourceDescriptor(
        id: "regional",
        displayName: "Regional Transit",
        capabilities: [.timetables, .connections],
        connectionOptions: [.onlyDirect, .via]
    )
    #expect(
        try decoder.decode(
            TransitDataSourceDescriptor.self,
            from: JSONEncoder().encode(declared)
        ) == declared
    )
}

/// Keeps cross-surface departure matching opt-in for providers whose station-timetable and board data align.
@Test func stationTimetableDepartureResolutionRequiresAnExplicitCapability() {
    let capability = TransitDataSourceCapability.stationTimetableDepartureResolution

    #expect(capability.rawValue == "stationTimetableDepartureResolution")
    #expect(TransitDataSourceDescriptor.idos.supports(capability))
    #expect(!MunicipalTransitDataSource().descriptor.supports(capability))
}

/// Proves that a provider can resolve its own timetable value without adopting IDOS minute or line syntax.
@Test func customProviderResolvesAnOpaqueStationTimetableValue() async throws {
    let source = SymbolicDepartureDataSource()
    let timetable = TransitStationTimetable(
        timetable: SymbolicDepartureDataSource.timetable,
        lineName: "Harbor loop",
        fromStop: "Market",
        toStop: "Pier",
        stops: [TransitStationTimetableStop(name: "Market", isSelected: true)],
        schedules: [TransitStationTimetableSchedule(
            label: "market days",
            hours: [TransitStationTimetableHour(
                hour: "morning",
                departures: ["quarter past"]
            )]
        )]
    )
    let request = TransitStationTimetableDepartureResolutionRequest(
        stationTimetable: timetable,
        scheduleIndex: 0,
        hourIndex: 0,
        departureIndex: 0,
        serviceDate: TransitDate(year: 2026, month: 9, day: 7),
        wholeWeek: false
    )

    let resolution = try #require(
        try await source.resolveStationTimetableDeparture(request: request, language: .english)
    )
    #expect(source.descriptor.supports(.stationTimetableDepartureResolution))
    #expect(resolution.departure.id == "symbolic:quarter-past")
    #expect(resolution.serviceDate == request.serviceDate)
    #expect(resolution.serviceTime == TransitTime(hour: 8, minute: 15))
    #expect(resolution.request.station == "Market")
    #expect(resolution.page.departures == [resolution.departure])
}

/// Keeps IDOS's display-text interpretation inside the IDOS adapter, including post-midnight duplicates.
@Test func idosResolverInterpretsItsOwnStationTimetableValues() throws {
    let timetable = TransitStationTimetable(
        timetable: TransitTimetable(slug: "pid", displayName: "Prague + PID"),
        lineName: "Line Bus 154",
        fromStop: "Strašnická",
        toStop: "Sídliště Libuš",
        stops: [TransitStationTimetableStop(name: "Strašnická", isSelected: true)],
        schedules: [TransitStationTimetableSchedule(
            label: "Workdays",
            hours: [
                TransitStationTimetableHour(hour: "23", departures: ["40"]),
                TransitStationTimetableHour(hour: "0", departures: ["12A", "12B"]),
            ]
        )]
    )
    let request = TransitStationTimetableDepartureResolutionRequest(
        stationTimetable: timetable,
        scheduleIndex: 0,
        hourIndex: 1,
        departureIndex: 1,
        serviceDate: TransitDate(year: 2026, month: 9, day: 7),
        wholeWeek: false
    )
    let reference = try #require(IDOSStationTimetableDepartureReference(request: request))

    #expect(reference.serviceTime == TransitTime(hour: 0, minute: 12))
    #expect(reference.dayOffset == 1)
    #expect(reference.occurrence == 1)
    #expect(
        IDOSStationTimetableDepartureResolver.addingDays(1, to: request.serviceDate) ==
            TransitDate(year: 2026, month: 9, day: 8)
    )

    let departures = [
        TransitDeparture(
            timetableIdentifier: "pid",
            id: "wrong-line",
            time: "0:12",
            lineName: "Tram 7",
            destination: "Radlická"
        ),
        TransitDeparture(
            timetableIdentifier: "pid",
            id: "first-run",
            time: "0:12",
            lineName: "Bus 154",
            destination: "Sídliště Libuš"
        ),
        TransitDeparture(
            timetableIdentifier: "pid",
            id: "second-run",
            time: "00:12",
            lineName: "Bus 154",
            destination: "Sídliště Libuš"
        ),
    ]
    #expect(
        IDOSStationTimetableDepartureResolver.matchingDeparture(
            in: departures,
            reference: reference,
            timetable: timetable
        )?.id == "second-run"
    )
}

/// Keeps IDOS whole-week labels in its adapter while the public request remains a semantic civil date.
@Test func idosResolverChoosesTheNearestMatchingWholeWeekDate() {
    #expect(
        IDOSStationTimetableDepartureResolver.candidateServiceDates(
            for: "Friday",
            searchDate: TransitDate(year: 2026, month: 8, day: 31),
            wholeWeek: true
        ) == [TransitDate(year: 2026, month: 9, day: 4)]
    )
}

/// Keeps coordinate encoding behind the selected provider instead of leaking IDOS hidden-form values to callers.
@Test func builtInSourceCreatesItsOwnCoordinatePlaceSelection() throws {
    let source = IDOSDataSource()
    let selection = try source.coordinatePlaceSelection(
        text: "My location",
        latitude: 49.197391,
        longitude: 16.619124,
        timetable: .defaultTimetable
    )

    #expect(selection.dataSourceID == .idos)
    #expect(selection.timetableIdentifier == TransitTimetable.defaultTimetable.identifier)
    #expect(selection.text == "My location")
    #expect(selection.isCurrentLocation)
    #expect(selection.listID == "loc: 49.197391; 16.619124")
    #expect(selection.itemID == "myPosition=true")
}

/// Lets a provider omit coordinate lookup without manufacturing an IDOS-shaped place selection.
@Test func coordinatePlaceSelectionDefaultsToAnAdvertisedUnsupportedOperation() {
    let source = MunicipalTransitDataSource()

    do {
        _ = try source.coordinatePlaceSelection(
            text: "Current position",
            latitude: 50.0,
            longitude: 14.0,
            timetable: MunicipalTransitDataSource.metro
        )
        Issue.record("Expected an unsupported coordinate selection to fail.")
    } catch let error as TransitDataSourceError {
        #expect(
            error == .unsupported(.coordinatePlaceSelection, source: source.descriptor)
        )
    } catch {
        Issue.record("Unexpected coordinate-selection error: \(error)")
    }
}

/// Makes the shipped registry usable as the composition root instead of requiring a concrete provider type.
@Test func builtInRegistryRoutesItsDefaultProviderByStableIdentifier() {
    let registry = TransitDataSourceRegistry.builtIn

    #expect(registry.defaultDataSourceID == .idos)
    #expect(registry.descriptors == [.idos])
    #expect(registry.defaultDataSource.descriptor == .idos)
    #expect(registry.dataSource(for: .idos)?.descriptor == .idos)
    #expect(registry.dataSource(for: "unregistered") == nil)
}

/// Routes colliding timetable and result identifiers through the provider selected by stable source identity.
@Test func registryRoutesTwoProvidersWithCollidingOwnedIdentifiers() async throws {
    let municipal = MunicipalTransitDataSource()
    let regional = RegionalTransitDataSource()
    let registry = try TransitDataSourceRegistry(
        dataSources: [regional, municipal],
        defaultDataSourceID: MunicipalTransitDataSource.sourceID
    )

    #expect(registry.defaultDataSource.descriptor.id == MunicipalTransitDataSource.sourceID)
    #expect(registry.descriptors.map(\.id) == [
        MunicipalTransitDataSource.sourceID,
        RegionalTransitDataSource.sourceID,
    ])

    let routedMunicipal = try #require(registry.dataSource(for: MunicipalTransitDataSource.sourceID))
    let routedRegional = try #require(registry.dataSource(for: RegionalTransitDataSource.sourceID))
    #expect(routedMunicipal.defaultTimetable.identifier == routedRegional.defaultTimetable.identifier)
    #expect(routedMunicipal.defaultTimetable.dataSourceID == MunicipalTransitDataSource.sourceID)
    #expect(routedRegional.defaultTimetable.dataSourceID == RegionalTransitDataSource.sourceID)
    #expect(routedMunicipal.descriptor.connectionOptions.isEmpty)
    #expect(routedRegional.descriptor.connectionOptions == [.onlyDirect, .via])

    let municipalPage = try await routedMunicipal.findConnectionsPage(request: TransitConnectionRequest(
        timetable: MunicipalTransitDataSource.metro,
        from: "River Market",
        to: "Museum"
    ))
    let regionalPage = try await routedRegional.findConnectionsPage(request: TransitConnectionRequest(
        timetable: RegionalTransitDataSource.metro,
        from: "River Market",
        to: "Museum",
        onlyDirect: true,
        via: ["Junction"]
    ))
    let municipalResult = try #require(municipalPage.connections.first)
    let regionalResult = try #require(regionalPage.connections.first)

    #expect(municipalResult.id == regionalResult.id)
    #expect(municipalResult.timetableIdentifier == regionalResult.timetableIdentifier)
    #expect(municipalPage.dataSourceID == MunicipalTransitDataSource.sourceID)
    #expect(regionalPage.dataSourceID == RegionalTransitDataSource.sourceID)
    #expect(municipalResult.dataSourceID == municipalPage.dataSourceID)
    #expect(regionalResult.dataSourceID == regionalPage.dataSourceID)
    #expect(municipalResult.dataSourceID != regionalResult.dataSourceID)
}

/// Proves that the CLI consumes a provider-owned timetable catalog and suggestions through the neutral contract.
@Test func commandRunnerUsesACustomTransitDataSourceCatalogAndSuggestions() async throws {
    let source = MunicipalTransitDataSource()
    let runner = CommandRunner(
        dataSource: source,
        preferredLanguageIdentifiers: ["en"],
        environment: [:]
    )

    let timetablesOutput = await runner.output(for: ["timetables", "--format", "json"])
    let timetables = try JSONDecoder().decode(
        TimetablesEnvelope.self,
        from: Data(timetablesOutput.utf8)
    )

    #expect(timetables.timetables == source.timetables)

    let suggestionsOutput = await runner.output(
        for: [
            "suggest", "River", "--timetable", "metro", "--limit", "1", "--format", "json",
        ]
    )
    let suggestions = try JSONDecoder().decode(
        SuggestionsEnvelope.self,
        from: Data(suggestionsOutput.utf8)
    )

    #expect(suggestions.query == "River")
    #expect(suggestions.timetable == MunicipalTransitDataSource.metro)
    #expect(suggestions.suggestions == [MunicipalTransitDataSource.riverMarket])
}

/// Resolves persisted alias identity through the active catalog after a provider renames its display label.
@Test func commandRunnerRefreshesAnAliasTimetableFromTheActiveProviderCatalog() async throws {
    let aliasFile = transitAliasFile()
    var database = StopAliasDatabase()
    let persistedMetro = TransitTimetable(
        dataSourceID: MunicipalTransitDataSource.sourceID,
        identifier: MunicipalTransitDataSource.metro.identifier,
        displayName: "Old Metro Name"
    )
    try database.upsert(StopAlias(name: "home", station: "River Market", timetable: persistedMetro))
    try database.upsert(StopAlias(name: "work", station: "Museum", timetable: persistedMetro))
    try aliasFile.save(database)
    let runner = CommandRunner(
        dataSource: MunicipalTransitDataSource(),
        aliasFile: aliasFile,
        preferredLanguageIdentifiers: ["en"],
        environment: [:]
    )

    let output = await runner.output(
        for: ["connections", "--from", "home", "--to", "work", "--limit", "1", "--format", "json"]
    )

    #expect(!output.contains("❌"))
    #expect(output.contains("Metro Network"))
}

/// Refuses to route a persisted alias from another provider through a colliding local identifier.
@Test func commandRunnerRejectsAnAliasOwnedByAnotherProvider() async throws {
    let aliasFile = transitAliasFile()
    var database = StopAliasDatabase()
    try database.upsert(StopAlias(
        name: "home",
        station: "River Market",
        timetable: TransitTimetable(slug: "metro", displayName: "Foreign Metro")
    ))
    try aliasFile.save(database)
    let runner = CommandRunner(
        dataSource: MunicipalTransitDataSource(),
        aliasFile: aliasFile,
        preferredLanguageIdentifiers: ["en"],
        environment: [:]
    )

    let output = await runner.output(
        for: ["connections", "--from", "home", "--to", "Museum", "--limit", "1"]
    )

    #expect(output.contains("Transit value belongs to data source idos, not municipal."))
}

/// Prevents an opaque identifier reused by another provider from receiving an unrelated IDOS catalog name.
@Test func cliLocalizesKnownTimetableIdentifiersOnlyForIDOS() {
    let providerTimetable = TransitTimetable(
        dataSourceID: "municipal",
        identifier: "vlaky",
        displayName: "Municipal Rail"
    )
    let idosTimetable = TransitTimetable(slug: "vlaky", displayName: "Trains")

    #expect(Localization(language: .english).timetableName(providerTimetable) == "Municipal Rail")
    #expect(Localization(language: .czech).timetableName(providerTimetable) == "Municipal Rail")
    #expect(Localization(language: .czech).timetableName(idosTimetable) == "Vlaky")
}

/// Lets each provider round-trip private, strongly typed pagination state without publishing its representation.
@Test func connectionPageRetainsAProviderTypedContinuation() throws {
    let cursor = MunicipalConnectionCursor(token: "next:42")
    let page = TransitConnectionPage(
        connections: [],
        canLoadEarlier: false,
        canLoadLater: true,
        dataSourceID: MunicipalTransitDataSource.sourceID,
        continuation: cursor
    )

    #expect(page.dataSourceID == MunicipalTransitDataSource.sourceID)
    #expect(page.continuation?.value(as: MunicipalConnectionCursor.self) == cursor)
    #expect(page.continuation?.value(as: String.self) == nil)
}

/// Prevents one provider from interpreting continuation state created by another provider.
@Test func connectionPagingRejectsAPageOwnedByAnotherSource() async {
    let source = MunicipalTransitDataSource()
    let foreignPage = TransitConnectionPage(
        connections: [],
        dataSourceID: "regional"
    )

    do {
        _ = try await source.findConnectionsPage(from: foreignPage, direction: .later)
        Issue.record("Expected paging to reject a page owned by another data source.")
    } catch let error as TransitDataSourceError {
        #expect(
            error == .pageBelongsToDifferentSource(
                expected: MunicipalTransitDataSource.sourceID,
                actual: "regional"
            )
        )
    } catch {
        Issue.record("Unexpected paging error: \(error)")
    }
}

/// Makes an unimplemented generic paging operation fail explicitly instead of looking like the end of data.
@Test func genericAdjacentPagingDefaultsReportUnsupportedCapabilities() async {
    let source = MunicipalTransitDataSource()

    do {
        _ = try await source.findConnectionsPage(
            from: TransitConnectionPage(connections: [], dataSourceID: source.descriptor.id),
            direction: .later
        )
        Issue.record("Expected generic connection paging to be unsupported.")
    } catch let error as TransitDataSourceError {
        #expect(error == .unsupported(.connectionPaging, source: source.descriptor))
    } catch {
        Issue.record("Unexpected connection paging error: \(error)")
    }

    do {
        _ = try await source.findDeparturesPage(
            from: TransitDeparturePage(departures: [], dataSourceID: source.descriptor.id),
            direction: .later
        )
        Issue.record("Expected generic departure paging to be unsupported.")
    } catch let error as TransitDataSourceError {
        #expect(error == .unsupported(.departurePaging, source: source.descriptor))
    } catch {
        Issue.record("Unexpected departure paging error: \(error)")
    }
}

/// Preserves the historical empty adjacent-page adapters for an older IDOS protocol conformer.
@Test func legacyIDOSClientAdjacentPagingDefaultsRemainEmpty() async throws {
    let source = LegacyTransitClient()
    let connections = try await source.findConnectionsPage(
        from: TransitConnectionPage(connections: [], dataSourceID: .idos),
        direction: .later
    )
    let departures = try await source.findDeparturesPage(
        from: TransitDeparturePage(departures: [], dataSourceID: .idos),
        direction: .earlier
    )

    #expect(connections.connections.isEmpty)
    #expect(departures.departures.isEmpty)
}

/// Rejects ambiguous registration before consumers can route an operation to the wrong implementation.
@Test func registryRejectsDuplicateProviderIdentifiers() {
    do {
        _ = try TransitDataSourceRegistry(
            dataSources: [MunicipalTransitDataSource(), MunicipalTransitDataSource()],
            defaultDataSourceID: MunicipalTransitDataSource.sourceID
        )
        Issue.record("Expected duplicate data-source registration to fail.")
    } catch let error as TransitDataSourceRegistryError {
        #expect(error == .duplicate(MunicipalTransitDataSource.sourceID))
    } catch {
        Issue.record("Unexpected registry error: \(error)")
    }
}

/// Keeps the provider-scoped timetable identity used by persistence and result routing unambiguous.
@Test func registryRejectsCaseInsensitiveDuplicateTimetableIdentifiersWithinAProvider() {
    let defaultTimetable = TransitTimetable(
        dataSourceID: MisownedTimetableDataSource.sourceID,
        identifier: "local",
        displayName: "Local"
    )
    let source = MisownedTimetableDataSource(
        defaultTimetable: defaultTimetable,
        timetables: [
            defaultTimetable,
            TransitTimetable(
                dataSourceID: MisownedTimetableDataSource.sourceID,
                identifier: "LOCAL",
                displayName: "Duplicate Local"
            ),
        ]
    )

    do {
        _ = try TransitDataSourceRegistry(
            dataSources: [source],
            defaultDataSourceID: MisownedTimetableDataSource.sourceID
        )
        Issue.record("Expected a duplicate timetable identifier to fail registration.")
    } catch let error as TransitDataSourceRegistryError {
        #expect(
            error == .duplicateTimetableIdentifier(
                source: MisownedTimetableDataSource.sourceID,
                identifier: "LOCAL"
            )
        )
    } catch {
        Issue.record("Unexpected registry error: \(error)")
    }
}

/// Gives stable identifiers precedence over a display name that happens to use the same text.
@Test func timetableResolverPrefersAnIdentifierOverAnEarlierDisplayName() throws {
    let shadow = TransitTimetable(
        dataSourceID: MisownedTimetableDataSource.sourceID,
        identifier: "regional",
        displayName: "metro"
    )
    let metro = TransitTimetable(
        dataSourceID: MisownedTimetableDataSource.sourceID,
        identifier: "metro",
        displayName: "City Metro"
    )
    let source = MisownedTimetableDataSource(
        defaultTimetable: shadow,
        timetables: [shadow, metro]
    )

    #expect(try source.resolveTimetable("metro") == metro)
}

/// Keeps the provider default selectable from the same canonical catalog presented to consumers.
@Test func registryRejectsADefaultTimetableMissingFromItsCatalog() {
    let source = MisownedTimetableDataSource(
        defaultTimetable: TransitTimetable(
            dataSourceID: MisownedTimetableDataSource.sourceID,
            identifier: "default",
            displayName: "Default"
        ),
        timetables: [
            TransitTimetable(
                dataSourceID: MisownedTimetableDataSource.sourceID,
                identifier: "local",
                displayName: "Local"
            ),
        ]
    )

    do {
        _ = try TransitDataSourceRegistry(
            dataSources: [source],
            defaultDataSourceID: MisownedTimetableDataSource.sourceID
        )
        Issue.record("Expected a default timetable outside the catalog to fail registration.")
    } catch let error as TransitDataSourceRegistryError {
        #expect(
            error == .defaultTimetableMissingFromCatalog(
                source: MisownedTimetableDataSource.sourceID,
                identifier: "default"
            )
        )
    } catch {
        Issue.record("Unexpected registry error: \(error)")
    }
}

/// Requires every registry to route its declared default identifier to an installed provider.
@Test func registryRejectsAMissingDefaultProvider() {
    do {
        _ = try TransitDataSourceRegistry(
            dataSources: [MunicipalTransitDataSource()],
            defaultDataSourceID: "regional"
        )
        Issue.record("Expected a missing default data source to fail.")
    } catch let error as TransitDataSourceRegistryError {
        #expect(error == .missingDefault("regional"))
    } catch {
        Issue.record("Unexpected registry error: \(error)")
    }
}

/// Rejects a provider whose advertised default timetable is namespaced to another source.
@Test func registryRejectsAForeignDefaultTimetable() {
    let source = MisownedTimetableDataSource(
        defaultTimetable: TransitTimetable(
            dataSourceID: "regional",
            identifier: "foreign-default",
            displayName: "Foreign Default"
        ),
        timetables: []
    )

    do {
        _ = try TransitDataSourceRegistry(
            dataSources: [source],
            defaultDataSourceID: MisownedTimetableDataSource.sourceID
        )
        Issue.record("Expected a foreign default timetable to fail registration.")
    } catch let error as TransitDataSourceRegistryError {
        #expect(
            error == .timetableBelongsToDifferentSource(
                expected: MisownedTimetableDataSource.sourceID,
                actual: "regional",
                identifier: "foreign-default",
                role: .defaultTimetable
            )
        )
    } catch {
        Issue.record("Unexpected registry error: \(error)")
    }
}

/// Rejects any foreign timetable hidden among otherwise valid provider catalog entries.
@Test func registryRejectsAForeignCatalogTimetable() {
    let validDefault = TransitTimetable(
        dataSourceID: MisownedTimetableDataSource.sourceID,
        identifier: "local",
        displayName: "Local"
    )
    let source = MisownedTimetableDataSource(
        defaultTimetable: validDefault,
        timetables: [
            validDefault,
            TransitTimetable(
                dataSourceID: "regional",
                identifier: "foreign-catalog",
                displayName: "Foreign Catalog"
            ),
        ]
    )

    do {
        _ = try TransitDataSourceRegistry(
            dataSources: [source],
            defaultDataSourceID: MisownedTimetableDataSource.sourceID
        )
        Issue.record("Expected a foreign catalog timetable to fail registration.")
    } catch let error as TransitDataSourceRegistryError {
        #expect(
            error == .timetableBelongsToDifferentSource(
                expected: MisownedTimetableDataSource.sourceID,
                actual: "regional",
                identifier: "foreign-catalog",
                role: .catalogEntry
            )
        )
    } catch {
        Issue.record("Unexpected registry error: \(error)")
    }
}

/// Preserves ownership of timetable values persisted before data-source namespacing was introduced.
@Test func legacyTimetableJSONDefaultsToTheBuiltInDataSource() throws {
    let data = Data(#"{"slug":"vlaky","displayName":"Trains"}"#.utf8)

    let timetable = try JSONDecoder().decode(TransitTimetable.self, from: data)

    #expect(timetable.dataSourceID == .idos)
    #expect(timetable.identifier == "vlaky")
    #expect(timetable.displayName == "Trains")
}

/// Keeps built-in timetable JSON stable while explicitly namespacing catalogs from additional providers.
@Test func timetableJSONEncodesADataSourceIdentifierOnlyWhenNeeded() throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]

    let builtIn = TransitTimetable(slug: "vlaky", displayName: "Trains")
    let builtInJSON = try #require(String(data: encoder.encode(builtIn), encoding: .utf8))
    #expect(builtInJSON == #"{"displayName":"Trains","slug":"vlaky"}"#)

    let municipal = MunicipalTransitDataSource.metro
    let municipalJSON = try #require(String(data: encoder.encode(municipal), encoding: .utf8))
    #expect(
        municipalJSON ==
            #"{"dataSourceID":"municipal","displayName":"Metro Network","slug":"metro"}"#
    )
}

/// Retains identity without falsely advertising optional operations for a legacy client with no metadata.
@Test func legacyClientConformerReceivesAConservativeBuiltInDescriptor() {
    #expect(LegacyTransitClient().descriptor == .legacyIDOSClient)
    #expect(LegacyTransitClient().descriptor.id == .idos)
    #expect(LegacyTransitClient().descriptor.capabilities == [
        .timetables,
        .placeSuggestions,
        .coordinatePlaceSelection,
        .stationSearch,
        .connections,
        .departures,
        .serviceDetails,
        .connectionCalendarExport,
    ])
}

/// Lets an additional provider create an exact selectable place without manufacturing IDOS fields.
@Test func customSuggestionSelectionRoundTripsToItsOwningProvider() async throws {
    let source = MunicipalTransitDataSource()
    let suggestions = try await source.suggest(
        prefix: "River",
        limit: 1,
        timetable: source.defaultTimetable
    )
    let suggestion = try #require(suggestions.first)
    let selection = try #require(TransitPlaceSelection(suggestion: suggestion))

    #expect(selection.dataSourceID == MunicipalTransitDataSource.sourceID)
    #expect(selection.timetableIdentifier == MunicipalTransitDataSource.metro.identifier)
    #expect(selection.identifier == "place:river-market")
    #expect(selection.listID.isEmpty)
    #expect(selection.itemID.isEmpty)

    let connections = try await source.findConnections(request: TransitConnectionRequest(
        timetable: source.defaultTimetable,
        from: selection.text,
        to: "Museum",
        fromSelection: selection
    ))
    #expect(connections.first?.dataSourceID == MunicipalTransitDataSource.sourceID)
    #expect(connections.first?.timetableIdentifier == MunicipalTransitDataSource.metro.identifier)
}

/// Stops IDOS from interpreting a timetable-scoped exact place in a different catalog.
@Test func idosRejectsAPlaceSelectionFromAnotherTimetableBeforeRequesting() async throws {
    let suggestion = TransitSuggestion(
        timetableIdentifier: "vlaky",
        text: "Praha hl.n.",
        value: "100003",
        value2: "5457076"
    )
    let selection = try #require(TransitPlaceSelection(suggestion: suggestion))
    let request = TransitConnectionRequest(
        timetable: .defaultTimetable,
        from: selection.text,
        to: "Brno hl.n.",
        fromSelection: selection
    )

    do {
        _ = try await IDOSDataSource().findConnections(request: request)
        Issue.record("Expected a timetable-scoped place mismatch to fail before networking.")
    } catch let error as TransitDataSourceError {
        #expect(
            error == .valueBelongsToDifferentTimetable(
                expected: TransitTimetable.defaultTimetable.identifier,
                actual: "vlaky",
                source: .idos
            )
        )
    } catch {
        Issue.record("Unexpected exact-place ownership error: \(error)")
    }
}

/// Stops IDOS from interpreting one integrated network's municipality inside another catalog.
@Test func idosRejectsAMunicipalityFromAnotherTimetableBeforeRequesting() async throws {
    let odis = TransitTimetable(slug: "odis", displayName: "ODIS")
    let iredo = TransitTimetable(slug: "iredo", displayName: "IREDO")
    let municipality = try #require(TransitStationTimetableMunicipality.available(for: odis).first)

    do {
        _ = try await IDOSDataSource().searchStationTimetableLines(
            prefix: "1",
            timetable: iredo,
            municipality: municipality
        )
        Issue.record("Expected a timetable-scoped municipality mismatch to fail before networking.")
    } catch let error as TransitDataSourceError {
        #expect(
            error == .valueBelongsToDifferentTimetable(
                expected: iredo.identifier,
                actual: odis.identifier,
                source: .idos
            )
        )
    } catch {
        Issue.record("Unexpected municipality ownership error: \(error)")
    }
}

/// Keeps the built-in JSON contract stable while allowing additional providers to persist opaque identities.
@Test func providerOwnedValueJSONPreservesIDOSCompatibility() throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]

    let idosSuggestion = TransitSuggestion(text: "Praha", value: "100003", value2: "5457076")
    #expect(
        String(decoding: try encoder.encode(idosSuggestion), as: UTF8.self) ==
            #"{"text":"Praha","value":"100003","value2":"5457076"}"#
    )
    let idosSelection = TransitPlaceSelection(text: "Praha", listID: "100003", itemID: "5457076")
    #expect(
        String(decoding: try encoder.encode(idosSelection), as: UTF8.self) ==
            #"{"itemID":"5457076","listID":"100003","text":"Praha"}"#
    )
    let idosMunicipality = TransitStationTimetableMunicipality(
        name: "Ostrava",
        timetableIndex: 2,
        timetableName: "ODIS"
    )
    #expect(
        String(decoding: try encoder.encode(idosMunicipality), as: UTF8.self) ==
            #"{"name":"Ostrava","timetableIndex":2,"timetableName":"ODIS"}"#
    )

    let customSelection = TransitPlaceSelection(
        dataSourceID: MunicipalTransitDataSource.sourceID,
        timetableIdentifier: MunicipalTransitDataSource.metro.identifier,
        identifier: "place:river-market",
        text: "River Market"
    )
    let decoded = try JSONDecoder().decode(
        TransitPlaceSelection.self,
        from: encoder.encode(customSelection)
    )
    #expect(decoded == customSelection)

    let customMunicipality = TransitStationTimetableMunicipality(
        dataSourceID: MunicipalTransitDataSource.sourceID,
        timetableIdentifier: MunicipalTransitDataSource.metro.identifier,
        identifier: "municipality:centre",
        name: "Centre"
    )
    #expect(
        try JSONDecoder().decode(
            TransitStationTimetableMunicipality.self,
            from: encoder.encode(customMunicipality)
        ) == customMunicipality
    )
}

/// Treats an older IDOS suggestion without a persisted catalog as unscoped when it becomes an exact selection.
@Test func legacySuggestionJSONDoesNotInventATimetableScope() throws {
    let data = Data(#"{"text":"Praha","value":"100003","value2":"5457076"}"#.utf8)
    let suggestion = try JSONDecoder().decode(TransitSuggestion.self, from: data)
    let selection = try #require(TransitPlaceSelection(suggestion: suggestion))

    #expect(suggestion.timetableIdentifier == TransitTimetable.defaultTimetable.identifier)
    #expect(selection.timetableIdentifier == nil)
}

/// Requires every explicitly non-IDOS persisted value to keep its provider-owned timetable namespace.
@Test func nonIDOSResultJSONRequiresATimetableIdentifier() {
    func expectMissingTimetableIdentifier<Value: Decodable>(
        _ type: Value.Type,
        json: String
    ) {
        do {
            _ = try JSONDecoder().decode(type, from: Data(json.utf8))
            Issue.record("Expected \(type) without a timetable identifier to fail decoding.")
        } catch DecodingError.keyNotFound(let key, _) {
            #expect(key.stringValue == "timetableIdentifier")
        } catch {
            Issue.record("Unexpected \(type) decoding error: \(error)")
        }
    }

    expectMissingTimetableIdentifier(
        TransitSuggestion.self,
        json: #"{"dataSourceID":"municipal","text":"Market"}"#
    )
    expectMissingTimetableIdentifier(
        TransitConnection.self,
        json: #"{"dataSourceID":"municipal","id":"1","departureTime":"08:00","departureStation":"Market","arrivalTime":"08:10","arrivalStation":"Museum","duration":"10 min","legs":[]}"#
    )
    expectMissingTimetableIdentifier(
        TransitDeparture.self,
        json: #"{"dataSourceID":"municipal","id":"1","time":"08:00","lineName":"M1","destination":"Museum"}"#
    )
}

/// Keeps the writable fields of the historical IDOS value types source-compatible.
@Test func legacyIDOSSelectionAndMunicipalityFieldsRemainMutable() {
    var selection = TransitPlaceSelection(text: "Praha", listID: "100003", itemID: "5457076")
    selection.listID = "100004"
    selection.itemID = "5457077"
    #expect(selection.listID == "100004")
    #expect(selection.itemID == "5457077")

    var municipality = TransitStationTimetableMunicipality(
        name: "Ostrava",
        timetableIndex: 2,
        timetableName: "ODIS"
    )
    municipality.timetableIndex = 3
    municipality.timetableName = "FM"
    #expect(municipality.timetableIndex == 3)
    #expect(municipality.timetableName == "FM")
    #expect(municipality.timetableIdentifier == "odis")
}

/// Gives every provider structured civil date and local-time values without requiring IDOS string parsing.
@Test func semanticServiceDateAndTimeAreProviderNeutralCodableValues() throws {
    let serviceDate = TransitDate(year: 2026, month: 9, day: 7)
    let serviceTime = TransitTime(hour: 5, minute: 4)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]

    #expect(
        String(decoding: try encoder.encode(serviceDate), as: UTF8.self) ==
            #"{"day":7,"month":9,"year":2026}"#
    )
    #expect(
        String(decoding: try encoder.encode(serviceTime), as: UTF8.self) ==
            #"{"hour":5,"minute":4}"#
    )
    #expect(try JSONDecoder().decode(TransitDate.self, from: encoder.encode(serviceDate)) == serviceDate)
    #expect(try JSONDecoder().decode(TransitTime.self, from: encoder.encode(serviceTime)) == serviceTime)

    let request = TransitConnectionRequest(
        from: "River Market",
        to: "Museum",
        serviceDate: serviceDate,
        serviceTime: serviceTime
    )
    let decoded = try JSONDecoder().decode(
        TransitConnectionRequest.self,
        from: encoder.encode(request)
    )
    #expect(decoded.serviceDate == serviceDate)
    #expect(decoded.serviceTime == serviceTime)
    #expect(decoded.date == nil)
    #expect(decoded.time == nil)
}

/// Keeps operating-day lookup tied to the provider's civil zone instead of the machine running Kaštan.
@Test func serviceDateLimitsUseTheExplicitProviderTimeZone() throws {
    let timeZone = try #require(TimeZone(identifier: "America/Los_Angeles"))
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = timeZone
    let noon = try #require(calendar.date(from: DateComponents(
        year: 2026,
        month: 9,
        day: 7,
        hour: 12
    )))
    let limits = TransitServiceDateLimits(
        referenceDate: noon,
        days: [.init(date: noon, status: .runs)],
        timeZone: timeZone
    )

    #expect(limits.timeZoneIdentifier == timeZone.identifier)
    #expect(limits.referenceServiceDate == TransitDate(year: 2026, month: 9, day: 7))
    #expect(limits.firstServiceDate == TransitDate(year: 2026, month: 9, day: 7))
    #expect(limits.status(on: TransitDate(year: 2026, month: 9, day: 7)) == .runs)
    #expect(limits.status(on: TransitDate(year: 2026, month: 9, day: 8)) == nil)

    let decoded = try JSONDecoder().decode(
        TransitServiceDateLimits.self,
        from: JSONEncoder().encode(limits)
    )
    #expect(decoded == limits)
    #expect(decoded.status(on: TransitDate(year: 2026, month: 9, day: 7)) == .runs)
}

/// Decodes the former IDOS JSON shape with the same Prague service-day semantics it had when written.
@Test func legacyServiceDateLimitsJSONDefaultsToTheIDOSCivilTimeZone() throws {
    struct LegacyLimits: Encodable {
        let referenceDate: Date
        let days: [TransitServiceDateLimits.Day]
    }

    let prague = IDOSDataSource.serviceTimeZone
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = prague
    let noon = try #require(calendar.date(from: DateComponents(
        year: 2026,
        month: 9,
        day: 7,
        hour: 12
    )))
    let data = try JSONEncoder().encode(LegacyLimits(
        referenceDate: noon,
        days: [.init(date: noon, status: .doesNotRun)]
    ))
    let decoded = try JSONDecoder().decode(TransitServiceDateLimits.self, from: data)

    #expect(decoded.timeZoneIdentifier == prague.identifier)
    #expect(decoded.referenceServiceDate == TransitDate(year: 2026, month: 9, day: 7))
    #expect(decoded.status(on: TransitDate(year: 2026, month: 9, day: 7)) == .doesNotRun)
}

/// Retains the historical two-argument initializer while normalizing an arbitrary instant to Prague midnight.
@Test func legacyServiceDateLimitsInitializerKeepsIDOSNormalization() throws {
    let prague = IDOSDataSource.serviceTimeZone
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = prague
    let noon = try #require(calendar.date(from: DateComponents(
        year: 2026,
        month: 9,
        day: 7,
        hour: 12
    )))
    let limits = IDOSServiceDateLimits(
        referenceDate: noon,
        days: [.init(date: noon, status: .runs)]
    )

    #expect(calendar.component(.hour, from: limits.referenceDate) == 0)
    #expect(calendar.component(.hour, from: try #require(limits.firstDate)) == 0)
    #expect(limits.status(on: TransitDate(year: 2026, month: 9, day: 7)) == .runs)
}

/// Keeps the historical request JSON shape unchanged when callers continue to use IDOS strings.
@Test func legacyRequestJSONOmitsSemanticDateAndTimeKeys() throws {
    let encoder = JSONEncoder()
    let requests: [Data] = try [
        encoder.encode(TransitConnectionRequest(
            from: "Praha",
            to: "Brno",
            date: "7.9.2026",
            time: "05:04"
        )),
        encoder.encode(TransitDeparturesRequest(
            station: "Praha hl.n.",
            date: "7.9.2026",
            time: "05:04"
        )),
        encoder.encode(TransitStationTimetableRequest(
            timetable: .defaultTimetable,
            line: "Metro A",
            from: "Dejvická",
            to: "Depo Hostivař",
            date: "7.9.2026"
        )),
    ]

    for data in requests {
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["date"] as? String == "7.9.2026")
        #expect(object["serviceDate"] == nil)
        #expect(object["serviceTime"] == nil)
    }
    let connection = try #require(JSONSerialization.jsonObject(with: requests[0]) as? [String: Any])
    let departures = try #require(JSONSerialization.jsonObject(with: requests[1]) as? [String: Any])
    #expect(connection["time"] as? String == "05:04")
    #expect(departures["time"] as? String == "05:04")
}

/// Converts structured values only inside IDOS and gives them precedence over legacy string fallbacks.
@Test func idosRequestMappingPrefersSemanticDateAndTime() {
    let serviceDate = TransitDate(year: 2026, month: 9, day: 7)
    let serviceTime = TransitTime(hour: 5, minute: 4)
    let connection = TransitConnectionRequest(
        from: "Praha",
        to: "Brno",
        date: "legacy-date",
        time: "legacy-time",
        serviceDate: serviceDate,
        serviceTime: serviceTime
    )
    let departures = TransitDeparturesRequest(
        station: "Praha hl.n.",
        date: "legacy-date",
        time: "legacy-time",
        serviceDate: serviceDate,
        serviceTime: serviceTime
    )
    let stationTimetable = TransitStationTimetableRequest(
        timetable: .defaultTimetable,
        line: "Metro A",
        from: "Dejvická",
        to: "Depo Hostivař",
        date: "legacy-date",
        serviceDate: serviceDate
    )

    let connectionValues = Dictionary(uniqueKeysWithValues: connection.formItems.map { ($0.name, $0.value) })
    let departureValues = Dictionary(uniqueKeysWithValues: departures.formItems.map { ($0.name, $0.value) })
    let stationValues = Dictionary(uniqueKeysWithValues: stationTimetable.queryItems.map { ($0.name, $0.value) })

    #expect(connectionValues["Date"] == "7.9.2026")
    #expect(connectionValues["Time"] == "05:04")
    #expect(departureValues["Date"] == "7.9.2026")
    #expect(departureValues["Time"] == "05:04")
    #expect(stationValues["date"] == "7.9.2026")
}

/// Carries source and timetable ownership on provider results without changing built-in JSON.
@Test func resultValuesCarryProviderOwnership() throws {
    let connection = TransitConnection(
        dataSourceID: MunicipalTransitDataSource.sourceID,
        timetableIdentifier: MunicipalTransitDataSource.metro.identifier,
        id: "connection:1",
        departureTime: "08:00",
        departureStation: "River Market",
        arrivalTime: "08:10",
        arrivalStation: "Museum",
        duration: "10 min",
        legs: []
    )
    let departure = TransitDeparture(
        dataSourceID: MunicipalTransitDataSource.sourceID,
        timetableIdentifier: MunicipalTransitDataSource.metro.identifier,
        id: "service:1",
        time: "08:00",
        lineName: "M1",
        destination: "Museum"
    )

    #expect(connection.dataSourceID == MunicipalTransitDataSource.sourceID)
    #expect(connection.timetableIdentifier == "metro")
    #expect(departure.dataSourceID == MunicipalTransitDataSource.sourceID)
    #expect(departure.timetableIdentifier == "metro")

    let connectionJSON = String(decoding: try JSONEncoder().encode(connection), as: UTF8.self)
    let departureJSON = String(decoding: try JSONEncoder().encode(departure), as: UTF8.self)
    #expect(connectionJSON.contains(#""dataSourceID":"municipal""#))
    #expect(departureJSON.contains(#""dataSourceID":"municipal""#))
}

/// Round-trips a built-in result's non-default timetable while leaving default IDOS JSON unchanged.
@Test func idosCodableValuesPersistOnlyNonDefaultTimetableIdentity() throws {
    let encoder = JSONEncoder()
    let decoder = JSONDecoder()
    let suggestion = TransitSuggestion(
        timetableIdentifier: "vlaky",
        text: "Praha hl.n.",
        value: "100003",
        value2: "5457076"
    )
    let connection = TransitConnection(
        timetableIdentifier: "vlaky",
        id: "42",
        departureTime: "08:00",
        departureStation: "Praha hl.n.",
        arrivalTime: "10:30",
        arrivalStation: "Brno hl.n.",
        duration: "2 h 30 min",
        legs: []
    )
    let departure = TransitDeparture(
        timetableIdentifier: "vlaky",
        id: "vlaky:1-2-07.09.2026 08:00:00",
        time: "08:00",
        lineName: "R 1",
        destination: "Brno hl.n."
    )

    #expect(try decoder.decode(TransitSuggestion.self, from: encoder.encode(suggestion)) == suggestion)
    #expect(try decoder.decode(TransitConnection.self, from: encoder.encode(connection)) == connection)
    #expect(try decoder.decode(TransitDeparture.self, from: encoder.encode(departure)) == departure)

    let defaultSuggestion = TransitSuggestion(text: "Praha", value: "100003", value2: "5457076")
    let defaultConnection = TransitConnection(
        id: "1",
        departureTime: "08:00",
        departureStation: "Praha",
        arrivalTime: "09:00",
        arrivalStation: "Beroun",
        duration: "1 h",
        legs: []
    )
    let defaultDeparture = TransitDeparture(
        id: "1",
        time: "08:00",
        lineName: "S7",
        destination: "Beroun"
    )
    #expect(try decoder.decode(TransitSuggestion.self, from: encoder.encode(defaultSuggestion)) == defaultSuggestion)
    #expect(try decoder.decode(TransitConnection.self, from: encoder.encode(defaultConnection)) == defaultConnection)
    #expect(try decoder.decode(TransitDeparture.self, from: encoder.encode(defaultDeparture)) == defaultDeparture)
    for value in [
        try encoder.encode(defaultSuggestion),
        try encoder.encode(defaultConnection),
        try encoder.encode(defaultDeparture),
    ] {
        let object = try #require(JSONSerialization.jsonObject(with: value) as? [String: Any])
        #expect(object["timetableIdentifier"] == nil)
    }
}

/// Rejects provider-owned results before an IDOS export can interpret their opaque payload.
@Test func idosExportRejectsAConnectionOwnedByAnotherProvider() async {
    let connection = TransitConnection(
        dataSourceID: MunicipalTransitDataSource.sourceID,
        timetableIdentifier: MunicipalTransitDataSource.metro.identifier,
        id: "connection:1",
        departureTime: "08:00",
        departureStation: "River Market",
        arrivalTime: "08:10",
        arrivalStation: "Museum",
        duration: "10 min",
        legs: []
    )

    do {
        _ = try await IDOSDataSource().connectionCalendar(for: connection, timetable: .defaultTimetable)
        Issue.record("Expected IDOS to reject a connection from another provider.")
    } catch let error as TransitDataSourceError {
        #expect(
            error == .valueBelongsToDifferentSource(
                expected: .idos,
                actual: MunicipalTransitDataSource.sourceID
            )
        )
    } catch {
        Issue.record("Unexpected export error: \(error)")
    }
}

/// Rejects IDOS-owned results before an export can send them to another timetable endpoint.
@Test func idosExportRejectsAConnectionOwnedByAnotherTimetable() async {
    let connection = TransitConnection(
        timetableIdentifier: "vlaky",
        id: "connection:1",
        departureTime: "08:00",
        departureStation: "Praha hl.n.",
        arrivalTime: "10:30",
        arrivalStation: "Brno hl.n.",
        duration: "2 hr 30 min",
        legs: []
    )
    let buses = TransitTimetable(slug: "autobusy", displayName: "Buses")

    do {
        _ = try await IDOSDataSource().connectionCalendar(for: connection, timetable: buses)
        Issue.record("Expected IDOS to reject a connection from another timetable.")
    } catch let error as TransitDataSourceError {
        #expect(
            error == .valueBelongsToDifferentTimetable(
                expected: buses.identifier,
                actual: "vlaky",
                source: .idos
            )
        )
    } catch {
        Issue.record("Unexpected export timetable ownership error: \(error)")
    }
}

/// Keeps an older persisted IDOS result usable when its original non-default catalog was not encoded.
@Test func idosExportAcceptsALegacyConnectionWithoutPersistedTimetableScope() async throws {
    let encoded = try JSONEncoder().encode(TransitConnection(
        id: "connection:legacy",
        departureTime: "08:00",
        departureStation: "Praha hl.n.",
        arrivalTime: "10:30",
        arrivalStation: "Brno hl.n.",
        duration: "2 hr 30 min",
        legs: []
    ))
    let connection = try JSONDecoder().decode(TransitConnection.self, from: encoded)
    let trains = TransitTimetable(slug: "vlaky", displayName: "Trains")

    do {
        _ = try await IDOSDataSource().connectionCalendar(for: connection, timetable: trains)
        Issue.record("Expected the legacy result without an export payload to be unavailable.")
    } catch let error as IDOSError {
        guard case .calendarUnavailable = error else {
            Issue.record("Unexpected IDOS compatibility error: \(error)")
            return
        }
    } catch {
        Issue.record("Unexpected legacy export compatibility error: \(error)")
    }
}

/// Converts documented CLI values semantically while leaving unrecognized legacy strings to the selected source.
@Test func cliAddsSemanticDateAndTimeWithoutRejectingLegacyProviderInput() {
    #expect(
        CLITransitRequestFormatting.serviceDate(from: "7.9.2026") ==
            TransitDate(year: 2026, month: 9, day: 7)
    )
    #expect(
        CLITransitRequestFormatting.serviceDate(from: "2026-09-07") ==
            TransitDate(year: 2026, month: 9, day: 7)
    )
    #expect(CLITransitRequestFormatting.serviceDate(from: "31.2.2026") == nil)
    #expect(CLITransitRequestFormatting.serviceDate(from: "tomorrow") == nil)
    #expect(CLITransitRequestFormatting.serviceTime(from: "5:04") == TransitTime(hour: 5, minute: 4))
    #expect(CLITransitRequestFormatting.serviceTime(from: "24:00") == nil)
}

/// A provider outside the built-in ecosystem used to exercise provider-neutral composition.
private struct MunicipalTransitDataSource: TransitDataSource {
    static let sourceID: TransitDataSourceID = "municipal"
    static let metro = TransitTimetable(
        dataSourceID: sourceID,
        identifier: "metro",
        displayName: "Metro Network"
    )
    static let ferry = TransitTimetable(
        dataSourceID: sourceID,
        identifier: "ferry",
        displayName: "River Ferry"
    )
    static let riverMarket = TransitSuggestion(
        dataSourceID: sourceID,
        timetableIdentifier: metro.identifier,
        identifier: "place:river-market",
        selectedText: "River Market",
        text: "River Market",
        description: "metro station"
    )

    let descriptor = TransitDataSourceDescriptor(
        id: sourceID,
        displayName: "Municipal Transit",
        capabilities: [.timetables, .placeSuggestions, .connections]
    )

    var timetables: [TransitTimetable] {
        [Self.metro, Self.ferry]
    }

    var defaultTimetable: TransitTimetable {
        Self.metro
    }

    func suggest(
        prefix: String,
        limit: Int,
        timetable: TransitTimetable
    ) async throws -> [TransitSuggestion] {
        guard prefix == "River", timetable == Self.metro else {
            throw MunicipalFixtureError.unexpectedSuggestionRequest
        }
        return Array([Self.riverMarket].prefix(limit))
    }

    func findConnections(request: TransitConnectionRequest) async throws -> [TransitConnection] {
        guard request.timetable == Self.metro,
              request.from == Self.riverMarket.text,
              request.to == "Museum",
              request.fromSelection == nil || (
                  request.fromSelection?.dataSourceID == Self.sourceID &&
                      request.fromSelection?.identifier == Self.riverMarket.identifier
              )
        else {
            throw MunicipalFixtureError.unexpectedConnectionRequest
        }
        return [TransitConnection(
            dataSourceID: Self.sourceID,
            timetableIdentifier: request.timetable.identifier,
            id: "connection:1",
            departureTime: "08:00",
            departureStation: request.from,
            arrivalTime: "08:10",
            arrivalStation: request.to,
            duration: "10 min",
            legs: []
        )]
    }
}

/// A second provider that deliberately reuses another provider's timetable and result identifiers.
private struct RegionalTransitDataSource: TransitDataSource {
    static let sourceID: TransitDataSourceID = "regional"
    static let metro = TransitTimetable(
        dataSourceID: sourceID,
        identifier: MunicipalTransitDataSource.metro.identifier,
        displayName: "Regional Metro"
    )

    let descriptor = TransitDataSourceDescriptor(
        id: sourceID,
        displayName: "Regional Transit",
        capabilities: [.timetables, .connections],
        connectionOptions: [.onlyDirect, .via]
    )

    var defaultTimetable: TransitTimetable { Self.metro }

    func findConnections(request: TransitConnectionRequest) async throws -> [TransitConnection] {
        guard request.timetable == Self.metro,
              request.from == "River Market",
              request.to == "Museum",
              request.onlyDirect,
              request.via == ["Junction"]
        else {
            throw MunicipalFixtureError.unexpectedConnectionRequest
        }
        return [TransitConnection(
            dataSourceID: Self.sourceID,
            timetableIdentifier: request.timetable.identifier,
            id: "connection:1",
            departureTime: "08:00",
            departureStation: request.from,
            arrivalTime: "08:12",
            arrivalStation: request.to,
            duration: "12 min",
            legs: []
        )]
    }
}

/// A non-IDOS source whose visible station-timetable values are intentionally not clock strings.
private struct SymbolicDepartureDataSource: TransitDataSource {
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

    var defaultTimetable: TransitTimetable { Self.timetable }

    func resolveStationTimetableDeparture(
        request: TransitStationTimetableDepartureResolutionRequest,
        language: TransitLanguage
    ) async throws -> TransitStationTimetableDepartureResolution? {
        guard request.stationTimetable.schedules[request.scheduleIndex]
            .hours[request.hourIndex].departures[request.departureIndex] == "quarter past"
        else {
            return nil
        }
        let serviceTime = TransitTime(hour: 8, minute: 15)
        let departure = TransitDeparture(
            dataSourceID: Self.sourceID,
            timetableIdentifier: Self.timetable.identifier,
            id: "symbolic:quarter-past",
            time: "provider display value",
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

/// Private pagination state meaningful only to the municipal provider fixture.
private struct MunicipalConnectionCursor: Equatable, Sendable {
    let token: String
}

/// Detects accidental CLI routing to the wrong catalog or query in the provider fixture.
private enum MunicipalFixtureError: Error {
    case unexpectedSuggestionRequest
    case unexpectedConnectionRequest
}

/// Supplies deliberately invalid timetable ownership to exercise registry validation.
private struct MisownedTimetableDataSource: TransitDataSource {
    static let sourceID: TransitDataSourceID = "misowned"

    let descriptor = TransitDataSourceDescriptor(
        id: sourceID,
        displayName: "Misowned Timetables",
        capabilities: [.timetables]
    )
    let defaultTimetable: TransitTimetable
    let timetables: [TransitTimetable]
}

/// Decodes the public timetable result shape emitted by the command runner.
private struct TimetablesEnvelope: Decodable {
    let timetables: [TransitTimetable]
}

/// Decodes the public suggestion result shape emitted by the command runner.
private struct SuggestionsEnvelope: Decodable {
    let query: String
    let timetable: TransitTimetable
    let suggestions: [TransitSuggestion]
}

private func transitAliasFile() -> StopAliasFile {
    StopAliasFile(fileURL: FileManager.default.temporaryDirectory
        .appendingPathComponent("kastan-transit-source-tests-\(UUID().uuidString)")
        .appendingPathComponent("aliases.json"))
}

/// Models a client written against the original protocol before provider descriptors existed.
private struct LegacyTransitClient: IDOSClienting {
    func suggest(prefix: String, limit: Int, timetable: TransitTimetable) async throws -> [TransitSuggestion] {
        []
    }

    func searchStations(prefix: String, limit: Int, timetable: TransitTimetable) async throws -> [TransitSuggestion] {
        []
    }

    func findConnections(request: TransitConnectionRequest) async throws -> [TransitConnection] {
        []
    }

    func findDepartures(request: TransitDeparturesRequest) async throws -> [TransitDeparture] {
        []
    }

    func serviceDetail(id: String, timetable: TransitTimetable) async throws -> TransitServiceDetail {
        TransitServiceDetail(id: id, timetable: timetable, name: id, stops: [])
    }

    func connectionCalendar(
        for connection: TransitConnection,
        timetable: TransitTimetable
    ) async throws -> String {
        "BEGIN:VCALENDAR\nEND:VCALENDAR"
    }
}
