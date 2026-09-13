import AppKit
import Kastan
import SwiftUI

/// Loads a service lazily when its complete route or contextual detail actions need data.
@MainActor
final class ServiceDetailViewModel: ObservableObject {
    @Published private(set) var service: TransitServiceDetail?
    @Published private(set) var timetableValidity: TransitTimetableValidity?
    @Published private(set) var serviceDateLimits: TransitServiceDateLimits?
    @Published private(set) var isLoading = false
    @Published private(set) var isProcessingCalendar = false
    @Published private(set) var isProcessingPDF = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var actionError: ResultActionError?

    private let id: String
    private let timetable: TransitTimetable
    private let client: any TransitDataSource
    private let calendarImporter: any CalendarImporting
    private let calendarSaver: any CalendarSaving
    private let pdfOpener: any PDFOpening
    private let pdfExporter: any PDFExporting
    private var activeLoadTask: Task<TransitServiceDetail, Error>?
    private var activeLoadIdentifier: UUID?

    init(
        id: String,
        timetable: TransitTimetable = .defaultTimetable,
        client: any TransitDataSource,
        calendarImporter: any CalendarImporting = WorkspaceCalendarImporter(),
        calendarSaver: any CalendarSaving = WorkspaceCalendarSaver(),
        pdfOpener: any PDFOpening = WorkspacePDFOpener(),
        pdfExporter: any PDFExporting = WorkspacePDFExporter()
    ) {
        self.id = id
        self.timetable = timetable
        self.client = client
        self.calendarImporter = calendarImporter
        self.calendarSaver = calendarSaver
        self.pdfOpener = pdfOpener
        self.pdfExporter = pdfExporter
    }

    var isPerformingExport: Bool {
        isProcessingCalendar || isProcessingPDF
    }

    /// Exposes only stable provider metadata needed to decide which service actions the UI can offer.
    var dataSourceDescriptor: TransitDataSourceDescriptor {
        client.descriptor
    }

    /// Clears modal feedback after the passenger acknowledges a failed result action.
    func dismissActionError() {
        actionError = nil
    }

    func load() async {
        guard service == nil else { return }

        let loadTask: Task<TransitServiceDetail, Error>
        let loadIdentifier: UUID
        if let activeLoadTask, let activeLoadIdentifier {
            loadTask = activeLoadTask
            loadIdentifier = activeLoadIdentifier
        } else {
            isLoading = true
            errorMessage = nil

            let id = self.id
            let timetable = self.timetable
            let client = self.client
            let language = AppLanguagePreference.transitLanguage
            loadTask = Task {
                try await client.serviceDetail(
                    id: id,
                    timetable: timetable,
                    language: language
                )
            }
            loadIdentifier = UUID()
            activeLoadTask = loadTask
            activeLoadIdentifier = loadIdentifier
        }

        do {
            let service = try await loadTask.value
            guard self.service == nil, activeLoadIdentifier == loadIdentifier else { return }

            activeLoadTask = nil
            activeLoadIdentifier = nil
            self.service = service
            isLoading = false
            let language = AppLanguagePreference.transitLanguage
            async let loadedTimetableValidity = loadTimetableValidity(
                for: service,
                language: language
            )
            async let loadedServiceDateLimits = loadServiceDateLimits(
                for: service,
                language: language
            )
            let auxiliaryData = await (loadedTimetableValidity, loadedServiceDateLimits)
            timetableValidity = auxiliaryData.0
            serviceDateLimits = auxiliaryData.1
        } catch {
            guard activeLoadIdentifier == loadIdentifier else { return }

            activeLoadTask = nil
            activeLoadIdentifier = nil
            isLoading = false
            errorMessage = AppErrorPresentation.message(for: error)
        }
    }

    private func loadTimetableValidity(
        for service: TransitServiceDetail,
        language: TransitLanguage
    ) async -> TransitTimetableValidity? {
        guard client.descriptor.supports(.timetableValidity) else { return nil }
        return try? await client.timetableValidity(for: service.timetable, language: language)
    }

    private func loadServiceDateLimits(
        for service: TransitServiceDetail,
        language: TransitLanguage
    ) async -> TransitServiceDateLimits? {
        guard client.descriptor.supports(.serviceDateLimits) else { return nil }
        return try? await client.serviceDateLimits(for: service, language: language)
    }

    /// Supplies a complete service to an action, joining an existing request instead of requiring a second menu opening.
    func loadedService() async -> TransitServiceDetail? {
        await load()
        return service
    }

    /// Resolves the permanent IDOS result link only when an action actually needs it.
    func localizedPermanentLink() async -> URL? {
        (await loadedService())?.shareURL.flatMap(AppLanguagePreference.localizedResultURL)
    }

    /// Formats the same complete localized service detail that Kaštan exposes from loaded result windows.
    func localizedShareText() async -> String? {
        (await loadedService()).map(CLIPlainTextPresentation().service)
    }

    /// Fetches the dated service's calendar and either opens it or lets the user retain its ICS file.
    func performCalendarAction(_ action: CalendarExportAction) async {
        guard !isPerformingExport else { return }
        isProcessingCalendar = true
        actionError = nil
        defer { isProcessingCalendar = false }

        guard let service = await loadedService() else {
            if let errorMessage {
                actionError = ResultActionError(
                    title: action.localizedTitle,
                    message: errorMessage
                )
            }
            return
        }

        do {
            let calendar = try await client.serviceCalendar(
                for: service,
                language: AppLanguagePreference.transitLanguage
            )
            switch action {
            case .addToCalendar:
                try calendarImporter.open(calendarText: calendar)
            case .download:
                try calendarSaver.save(
                    calendarText: calendar,
                    suggestedFileName: CalendarExportFileName.connection(
                        from: service.stops.first?.name ?? service.name,
                        to: service.stops.last?.name ?? service.name
                    )
                )
            }
        } catch {
            actionError = ResultActionError(title: action.localizedTitle, error: error)
        }
    }

    /// Fetches the dated service's PDF and either opens it in Preview or lets the user retain its file.
    func performPDFAction(_ action: PDFExportAction) async {
        guard !isPerformingExport else { return }
        isProcessingPDF = true
        actionError = nil
        defer { isProcessingPDF = false }

        guard let service = await loadedService() else {
            if let errorMessage {
                actionError = ResultActionError(
                    title: action.localizedTitle,
                    message: errorMessage
                )
            }
            return
        }

        do {
            let data = try await client.servicePDF(
                for: service,
                language: AppLanguagePreference.transitLanguage
            )
            let fileName = PDFExportFileName.connection(
                from: service.stops.first?.name ?? service.name,
                to: service.stops.last?.name ?? service.name
            )
            switch action {
            case .openInPreview:
                try await pdfOpener.open(pdfData: data, suggestedFileName: fileName)
            case .download:
                try await pdfExporter.save(pdfData: data, suggestedFileName: fileName)
            }
        } catch {
            actionError = ResultActionError(title: action.localizedTitle, error: error)
        }
    }
}

/// Describes the part of a complete service route relevant to the originating search.
struct ServiceRouteHighlight: Codable, Hashable {
    let fromStop: String?
    let toStop: String?

    init(fromStop: String? = nil, toStop: String? = nil) {
        self.fromStop = fromStop
        self.toStop = toStop
    }

    /// Finds the stop where the searched journey boards this service.
    func departureIndex(in stops: [TransitServiceStop]) -> Int? {
        guard let fromStop, !stops.isEmpty else { return nil }
        return stopIndex(matching: fromStop, in: stops.indices, stops: stops)
    }

    func range(in stops: [TransitServiceStop]) -> ClosedRange<Int>? {
        guard !stops.isEmpty else { return nil }

        let startIndex = departureIndex(in: stops)
        let endSearchIndices = (startIndex ?? stops.startIndex)..<stops.endIndex
        let endIndex = toStop.flatMap { stopIndex(matching: $0, in: endSearchIndices, stops: stops) }

        switch (startIndex, endIndex) {
        case let (start?, end?) where start <= end:
            return start...end
        case let (start?, _):
            return start...(stops.endIndex - 1)
        case let (_, end?):
            return stops.startIndex...end
        default:
            return nil
        }
    }

    private func stopIndex(
        matching name: String,
        in indices: Range<Int>,
        stops: [TransitServiceStop]
    ) -> Int? {
        let query = Self.normalizedStopName(name)
        guard query.count >= 3 else { return nil }

        if let exact = indices.first(where: { Self.normalizedStopName(stops[$0].name) == query }) {
            return exact
        }
        return indices.first { index in
            let candidate = Self.normalizedStopName(stops[index].name)
            return candidate.hasSuffix(query) || query.hasSuffix(candidate)
        }
    }

    private static func normalizedStopName(_ value: String) -> String {
        value
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "cs_CZ"))
            .lowercased()
            .filter { $0.isLetter || $0.isNumber }
    }
}

/// Identifies a selected service and preserves the route context that supplied it.
struct ServiceSelection: Codable, Hashable, Identifiable {
    let serviceID: String
    /// Preserves the exact provider-owned timetable needed to resolve an otherwise opaque service identifier.
    let timetable: TransitTimetable
    let highlight: ServiceRouteHighlight?

    var dataSourceID: TransitDataSourceID { timetable.dataSourceID }

    /// Qualifies provider-owned service identifiers for scene and SwiftUI identity.
    var id: AppTransitValueIdentity {
        AppTransitValueIdentity(
            dataSourceID: timetable.dataSourceID,
            timetableIdentifier: timetable.identifier,
            valueIdentifier: serviceID
        )
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.serviceID == rhs.serviceID &&
            lhs.timetable == rhs.timetable &&
            lhs.highlight == rhs.highlight
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(highlight)
    }

    init(
        id: String,
        timetable: TransitTimetable = .defaultTimetable,
        highlight: ServiceRouteHighlight? = nil
    ) {
        serviceID = id
        self.timetable = timetable
        self.highlight = highlight
    }

    /// Reads the short-lived source-only representation without guessing an IDOS timetable for another provider.
    init(
        id: String,
        dataSourceID: TransitDataSourceID,
        highlight: ServiceRouteHighlight? = nil
    ) {
        self.init(
            id: id,
            timetable: Self.defaultTimetable(for: dataSourceID),
            highlight: highlight
        )
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case timetable
        case dataSourceID
        case highlight
    }

    /// Restores selections saved before source identity was introduced as IDOS-backed services.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        serviceID = try container.decode(String.self, forKey: .id)
        if let timetable = try container.decodeIfPresent(TransitTimetable.self, forKey: .timetable) {
            self.timetable = timetable
        } else {
            let dataSourceID = try container.decodeIfPresent(
                TransitDataSourceID.self,
                forKey: .dataSourceID
            ) ?? .idos
            self.timetable = Self.defaultTimetable(for: dataSourceID)
        }
        highlight = try container.decodeIfPresent(ServiceRouteHighlight.self, forKey: .highlight)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(serviceID, forKey: .id)
        try container.encode(timetable, forKey: .timetable)
        try container.encode(timetable.dataSourceID, forKey: .dataSourceID)
        try container.encodeIfPresent(highlight, forKey: .highlight)
    }

    private static func defaultTimetable(for dataSourceID: TransitDataSourceID) -> TransitTimetable {
        guard dataSourceID != .idos else { return .defaultTimetable }
        return TransitTimetable(
            dataSourceID: dataSourceID,
            identifier: "default",
            displayName: dataSourceID.rawValue
        )
    }
}

/// Recreates lazy route state whenever an existing detail scene is retargeted to another selected service.
struct ServiceDetailWindowContent: View {
    let selection: ServiceSelection
    let client: any TransitDataSource
    let showsItemDetails: Bool
    let showsStopNoteText: Bool

    var body: some View {
        ServiceDetailView(
            selection: selection,
            client: client,
            showsItemDetails: showsItemDetails,
            showsStopNoteText: showsStopNoteText
        )
        .id(selection)
    }
}

/// Keeps the searches derived from one calling point together while omitting unsupported destinations.
struct ServiceStopSearchSelections {
    let connection: ConnectionSearchSelection?
    let departure: DepartureSearchSelection?
    let arrival: DepartureSearchSelection?
    let stationTimetable: StationTimetableSelection?

    var availableSections: [AppSection] {
        AppSection.allCases.filter { section in
            switch section {
            case .connections:
                connection != nil
            case .departures:
                departure != nil || arrival != nil
            case .stationTimetables:
                stationTimetable != nil
            }
        }
    }
}

/// Converts a service-route stop's displayed civil instant into each supported main-window search.
enum ServiceStopSearchSelectionFactory {
    static func selections(
        forStopAt index: Int,
        in service: TransitServiceDetail,
        routeHighlight: ServiceRouteHighlight? = nil,
        client: any TransitDataSource
    ) -> ServiceStopSearchSelections {
        guard service.stops.indices.contains(index),
              let serviceDate = serviceDate(forStopAt: index, in: service),
              let serviceTime = serviceTime(for: service.stops[index])
        else {
            return ServiceStopSearchSelections(
                connection: nil,
                departure: nil,
                arrival: nil,
                stationTimetable: nil
            )
        }

        let stop = service.stops[index]
        let route = searchRoute(
            forStopAt: index,
            in: service.stops,
            routeHighlight: routeHighlight
        )
        let routeServiceDate = route.flatMap {
            Self.serviceDate(forStopAt: $0.fromIndex, in: service)
        }
        let routeServiceTime = route.flatMap {
            Self.serviceTime(for: service.stops[$0.fromIndex])
        }
        let connection: ConnectionSearchSelection?
        if let route, let routeServiceDate, let routeServiceTime {
            connection = ConnectionSearchSelectionFactory.stationTimetable(
                timetable: service.timetable,
                from: service.stops[route.fromIndex].name,
                to: service.stops[route.toIndex].name,
                serviceDate: routeServiceDate,
                serviceTime: routeServiceTime,
                client: client
            )
        } else {
            connection = nil
        }
        let departure = DepartureSearchSelectionFactory.search(
            timetable: service.timetable,
            station: stop.name,
            serviceDate: serviceDate,
            serviceTime: serviceTime,
            client: client
        )
        let arrival: DepartureSearchSelection?
        if let arrivalDate = Self.serviceDate(
            forStopAt: index,
            in: service,
            mode: .arrivals
        ), let arrivalTime = Self.serviceTime(for: stop, mode: .arrivals) {
            arrival = DepartureSearchSelectionFactory.search(
                timetable: service.timetable,
                station: stop.name,
                serviceDate: arrivalDate,
                serviceTime: arrivalTime,
                isArrival: true,
                client: client
            )
        } else {
            arrival = nil
        }
        let stationTimetable: StationTimetableSelection?
        if let route, let routeServiceDate {
            stationTimetable = StationTimetableSelectionFactory.serviceStop(
                timetable: service.timetable,
                line: service.name,
                from: service.stops[route.fromIndex].name,
                to: service.stops[route.toIndex].name,
                serviceDate: routeServiceDate,
                client: client
            )
        } else {
            stationTimetable = nil
        }

        return ServiceStopSearchSelections(
            connection: connection,
            departure: departure,
            arrival: arrival,
            stationTimetable: stationTimetable
        )
    }

    private struct SearchRoute {
        let fromIndex: Int
        let toIndex: Int
    }

    /// Keeps every earlier stop aimed at the searched destination, then continues later stops to the terminus.
    private static func searchRoute(
        forStopAt index: Int,
        in stops: [TransitServiceStop],
        routeHighlight: ServiceRouteHighlight?
    ) -> SearchRoute? {
        guard stops.count > 1 else { return nil }
        let firstIndex = stops.startIndex
        let lastIndex = stops.index(before: stops.endIndex)

        if let highlightedRange = routeHighlight?.range(in: stops) {
            if index < highlightedRange.upperBound {
                return SearchRoute(fromIndex: index, toIndex: highlightedRange.upperBound)
            }
            if index == highlightedRange.upperBound,
               highlightedRange.lowerBound < highlightedRange.upperBound {
                return SearchRoute(
                    fromIndex: highlightedRange.lowerBound,
                    toIndex: highlightedRange.upperBound
                )
            }
        }

        return index == lastIndex
            ? SearchRoute(fromIndex: firstIndex, toIndex: index)
            : SearchRoute(fromIndex: index, toIndex: lastIndex)
    }

    /// Uses the requested station-board event and falls back to the other displayed event when necessary.
    private static func serviceTime(
        for stop: TransitServiceStop,
        mode: DepartureBoardMode = .departures
    ) -> TransitTime? {
        let values = mode == .arrivals
            ? [stop.arrivalTime, stop.departureTime]
            : [stop.departureTime, stop.arrivalTime]
        return values
            .compactMap(parsedServiceTime)
            .first
    }

    private enum ServiceStopEvent: Equatable {
        case arrival
        case departure
    }

    private struct TimedServiceStopEvent {
        let event: ServiceStopEvent
        let time: TransitTime
    }

    /// Walks arrivals before departures so a midnight dwell can place them on different civil days.
    private static func serviceDate(
        forStopAt index: Int,
        in service: TransitServiceDetail,
        mode: DepartureBoardMode = .departures
    ) -> TransitDate? {
        guard let initialDate = parsedServiceDate(in: service.date) ?? parsedServiceDate(in: service.id)
        else {
            return nil
        }
        let targetEvents = timedEvents(for: service.stops[index])
        let preferredTargetEvent: ServiceStopEvent = mode == .arrivals ? .arrival : .departure
        guard let targetEvent = targetEvents.first(where: { $0.event == preferredTargetEvent })
            ?? targetEvents.first
        else {
            return nil
        }

        var previousMinuteOfDay: Int?
        var dayOffset = 0
        for stopIndex in service.stops.indices where stopIndex <= index {
            for event in timedEvents(for: service.stops[stopIndex]) {
                let minuteOfDay = event.time.hour * 60 + event.time.minute
                if let previousMinuteOfDay, minuteOfDay < previousMinuteOfDay {
                    dayOffset += 1
                }
                if stopIndex == index, event.event == targetEvent.event {
                    return addingDays(dayOffset, to: initialDate)
                }
                previousMinuteOfDay = minuteOfDay
            }
        }
        return nil
    }

    private static func timedEvents(for stop: TransitServiceStop) -> [TimedServiceStopEvent] {
        [
            parsedServiceTime(stop.arrivalTime).map {
                TimedServiceStopEvent(event: .arrival, time: $0)
            },
            parsedServiceTime(stop.departureTime).map {
                TimedServiceStopEvent(event: .departure, time: $0)
            },
        ].compactMap { $0 }
    }

    private static func parsedServiceTime(_ value: String?) -> TransitTime? {
        guard let value else { return nil }
        return TransitRequestFormatting.serviceTime(
            from: value.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    /// Accepts the numeric dates used by IDOS and structured providers, including spaces around separators.
    private static func parsedServiceDate(in value: String?) -> TransitDate? {
        guard let value,
              let expression = try? NSRegularExpression(
                  pattern: #"(?<!\d)(\d{1,2})\s*\.\s*(\d{1,2})\s*\.\s*(\d{4})(?!\d)"#
              ),
              let match = expression.firstMatch(
                  in: value,
                  range: NSRange(value.startIndex..<value.endIndex, in: value)
              ),
              let dayRange = Range(match.range(at: 1), in: value),
              let monthRange = Range(match.range(at: 2), in: value),
              let yearRange = Range(match.range(at: 3), in: value),
              let day = Int(value[dayRange]),
              let month = Int(value[monthRange]),
              let year = Int(value[yearRange])
        else {
            return nil
        }

        let date = TransitDate(year: year, month: month, day: day)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        guard let absoluteDate = date.date(in: calendar) else { return nil }
        let verified = TransitDate(absoluteDate, calendar: calendar)
        return verified == date ? date : nil
    }

    private static func addingDays(_ days: Int, to date: TransitDate) -> TransitDate? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        guard let absoluteDate = date.date(in: calendar),
              let adjusted = calendar.date(byAdding: .day, value: days, to: absoluteDate)
        else {
            return nil
        }
        return TransitDate(adjusted, calendar: calendar)
    }
}

/// Keeps a service stop's search groups in the same order as the main toolbar modes.
struct ServiceStopSearchOpenActions: View {
    let selections: ServiceStopSearchSelections
    let openConnection: (ConnectionSearchSelection, ConnectionSearchOpenDestination) -> Void
    let openDeparture: (DepartureSearchSelection, DepartureSearchOpenDestination) -> Void
    let openStationTimetable: (StationTimetableSelection, StationTimetableOpenDestination) -> Void

    var availableSections: [AppSection] {
        selections.availableSections
    }

    var body: some View {
        ForEach(availableSections) { section in
            switch section {
            case .connections:
                if let selection = selections.connection {
                    ConnectionSearchOpenActions { destination in
                        openConnection(selection, destination)
                    }
                }
            case .departures:
                if let selection = selections.departure {
                    DepartureSearchOpenActions { destination in
                        openDeparture(selection, destination)
                    }
                }
                if let selection = selections.arrival {
                    DepartureSearchOpenActions(mode: .arrivals) { destination in
                        openDeparture(selection, destination)
                    }
                }
            case .stationTimetables:
                if let selection = selections.stationTimetable {
                    StationTimetableOpenActions { destination in
                        openStationTimetable(selection, destination)
                    }
                }
            }
        }
    }
}

/// Moves a service date into the window title exactly when its content label has scrolled away.
enum ServiceWindowTitlePresentation {
    static func title(for service: TransitServiceDetail?, dateIsUnderTitle: Bool) -> String {
        guard let service else {
            return AppLocalization.string("Service route")
        }

        var components = [[service.transportMode?.emoji, service.name]
            .compactMap { $0 }
            .joined(separator: " ")]
        if dateIsUnderTitle, let date = service.date, !date.isEmpty {
            components.append(date)
        }
        return components.joined(separator: " · ")
    }

    static func dateIsUnderTitle(frame: CGRect?) -> Bool {
        (frame?.maxY ?? 1) <= 0
    }
}

private struct ServiceDateFramePreferenceKey: PreferenceKey {
    static let defaultValue: CGRect? = nil

    static func reduce(value: inout CGRect?, nextValue: () -> CGRect?) {
        value = nextValue() ?? value
    }
}

/// Supplies the geometry needed to bring a searched departure toward the visible top of a route.
private struct ServiceRouteInitialLayout: Equatable {
    var routeFrame: CGRect?
    var departureFrame: CGRect?
}

private struct ServiceRouteInitialLayoutPreferenceKey: PreferenceKey {
    static let defaultValue = ServiceRouteInitialLayout()

    static func reduce(
        value: inout ServiceRouteInitialLayout,
        nextValue: () -> ServiceRouteInitialLayout
    ) {
        let nextValue = nextValue()
        value.routeFrame = nextValue.routeFrame ?? value.routeFrame
        value.departureFrame = nextValue.departureFrame ?? value.departureFrame
    }
}

/// Brings a searched departure toward the visible top without extending the route past its natural end.
@MainActor
enum ServiceRouteInitialScroll {
    /// Leaves the searched departure clear of either a toolbar or the rounded preview edge.
    static func topClearance(for presentation: ResultDetailPresentation) -> CGFloat {
        presentation == .preview ? 20 : 16
    }

    /// Preserves the natural top when no preceding route needs to be skipped or the complete route already fits.
    static func needsPositioning(
        departureIndex: Int,
        viewportHeight: CGFloat,
        routeBottom: CGFloat
    ) -> Bool {
        departureIndex > 0 && routeBottom > viewportHeight
    }

    /// Converts the fixed visual clearance into the shared item-and-viewport anchor used by `scrollTo`.
    static func anchor(
        viewportHeight: CGFloat,
        departureHeight: CGFloat,
        topClearance: CGFloat
    ) -> UnitPoint {
        let availableTravel = viewportHeight - departureHeight
        guard availableTravel > 0 else { return .top }
        return UnitPoint(
            x: 0.5,
            y: min(1, topClearance / availableTravel)
        )
    }

    /// Waits for the loaded route's title and toolbar to establish the visible top edge before positioning it.
    static func afterWindowLayout(_ action: @escaping @MainActor () -> Void) {
        DispatchQueue.main.async {
            action()
        }
    }
}

/// Shows every stop and piece of service information supplied by the selected data source in its own window.
struct ServiceDetailView: View {
    /// Opens new service routes at the compact width already supported by the adaptive route layout.
    nonisolated static let minimumWindowWidth: CGFloat = 400
    static let defaultWindowWidth = minimumWindowWidth

    private static let scrollCoordinateSpace = "service-detail-scroll"

    @Environment(\.openWindow) private var openWindow
    @StateObject private var model: ServiceDetailViewModel
    @State private var dateIsUnderTitle = false
    @State private var hasAppliedInitialRoutePosition = false
    @State private var hasScheduledInitialRoutePosition = false
    @State private var isServiceInformationExpanded = false
    private let routeHighlight: ServiceRouteHighlight?
    private let presentation: ResultDetailPresentation
    private let showsItemDetails: Bool
    private let showsStopNoteText: Bool
    private let serviceTimeZone: TimeZone?
    private let client: any TransitDataSource

    init(
        selection: ServiceSelection,
        client: any TransitDataSource,
        showsItemDetails: Bool,
        showsStopNoteText: Bool,
        presentation: ResultDetailPresentation = .window
    ) {
        routeHighlight = selection.highlight
        self.presentation = presentation
        self.showsItemDetails = showsItemDetails
        self.showsStopNoteText = showsStopNoteText
        serviceTimeZone = client.serviceTimeZone
        self.client = client
        _model = StateObject(wrappedValue: ServiceDetailViewModel(
            id: selection.serviceID,
            timetable: selection.timetable,
            client: client
        ))
    }

    var body: some View {
        Group {
            if model.isLoading {
                ProgressView("Loading service route…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let errorMessage = model.errorMessage {
                VStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 34))
                        .foregroundStyle(.secondary)
                    Text("Service route unavailable")
                        .font(.title3.bold())
                    Text(errorMessage)
                        .foregroundStyle(.secondary)
                }
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let service = model.service {
                serviceContent(service)
            } else {
                Color.clear
            }
        }
        .frame(minWidth: Self.minimumWindowWidth, minHeight: 520)
        .navigationTitle(windowTitle)
        .toolbar {
            if presentation == .window, model.service != nil {
                ToolbarItemGroup(placement: .primaryAction) {
                    ForEach(
                        ResultDetailAction.availableActions(
                            canSendByEmail: actionAvailability.canSendByEmail,
                            canAddToCalendar: actionAvailability.canAddToCalendar,
                            canOpenPDF: actionAvailability.canOpenPDF
                        )
                    ) { action in
                        serviceActionControl(action, url: serviceActionURL)
                    }
                }
            }
        }
        .focusedSceneValue(\.resultDetailCommandContext, resultDetailCommandContext)
        .task {
            await model.load()
        }
        .resultActionErrorAlert(model.actionError) {
            model.dismissActionError()
        }
    }

    private var windowTitle: String {
        ServiceWindowTitlePresentation.title(
            for: model.service,
            dateIsUnderTitle: dateIsUnderTitle
        )
    }

    private var serviceActionURL: URL? {
        model.service?.shareURL.flatMap(AppLanguagePreference.localizedResultURL)
    }

    private var serviceShareText: String? {
        model.service.map(CLIPlainTextPresentation().service)
    }

    private var actionAvailability: ResultDetailActionAvailability {
        .service(model.dataSourceDescriptor)
    }

    private var resultDetailCommandContext: ResultDetailCommandContext {
        ResultDetailCommandContext(
            hasLoadedResult: model.service != nil,
            isPerformingAction: model.isPerformingExport,
            permanentLink: serviceActionURL,
            shareText: serviceShareText,
            availability: actionAvailability,
            performCalendarAction: { calendarExportAction in
                Task { await model.performCalendarAction(calendarExportAction) }
            },
            performPDFAction: { pdfExportAction in
                Task { await model.performPDFAction(pdfExportAction) }
            }
        )
    }

    /// Renders each service action as an independent native toolbar control.
    @ViewBuilder
    private func serviceActionControl(_ action: ResultDetailAction, url: URL?) -> some View {
        switch action {
        case .sendByEmail:
            EmptyView()
        case .addToCalendar:
            CalendarExportButton(placement: .toolbar) { calendarExportAction in
                Task { await model.performCalendarAction(calendarExportAction) }
            } label: { calendarExportAction in
                exportActionLabel(
                    action,
                    calendarExportAction: calendarExportAction,
                    isPerforming: model.isProcessingCalendar
                )
            }
            .disabled(model.isPerformingExport)
        case .openPDF:
            PDFExportButton(placement: .toolbar) { pdfExportAction in
                Task { await model.performPDFAction(pdfExportAction) }
            } label: { pdfExportAction in
                exportActionLabel(
                    action,
                    pdfExportAction: pdfExportAction,
                    isPerforming: model.isProcessingPDF
                )
            }
            .disabled(model.isPerformingExport)
        case .share:
            ResultShareButton(
                link: url,
                text: serviceShareText,
                placement: .toolbar
            ) { sharingAction in
                serviceActionLabel(action, sharingAction: sharingAction)
            }
            .disabled(model.isPerformingExport)
        }
    }

    @ViewBuilder
    private func exportActionLabel(
        _ action: ResultDetailAction,
        calendarExportAction: CalendarExportAction = .addToCalendar,
        pdfExportAction: PDFExportAction = .openInPreview,
        isPerforming: Bool
    ) -> some View {
        ZStack {
            serviceActionLabel(
                action,
                calendarExportAction: calendarExportAction,
                pdfExportAction: pdfExportAction
            )
            .opacity(isPerforming ? 0 : 1)

            ProgressView()
                .controlSize(.small)
                .opacity(isPerforming ? 1 : 0)
        }
    }

    private func serviceActionLabel(
        _ action: ResultDetailAction,
        calendarExportAction: CalendarExportAction = .addToCalendar,
        pdfExportAction: PDFExportAction = .openInPreview,
        sharingAction: ResultSharingAction = .link
    ) -> some View {
        Label(
            action.title(
                calendarExportAction: calendarExportAction,
                pdfExportAction: pdfExportAction,
                sharingAction: sharingAction
            ),
            systemImage: action.systemImage(
                calendarExportAction: calendarExportAction,
                pdfExportAction: pdfExportAction,
                sharingAction: sharingAction
            )
        )
            .labelStyle(.iconOnly)
    }

    private func serviceContent(_ service: TransitServiceDetail) -> some View {
        let highlightedRange = routeHighlight?.range(in: service.stops)
        let departureIndex = routeHighlight?.departureIndex(in: service.stops)
        let highlightedColor = Color(idosHTMLColor: service.color) ?? .accentColor

        return GeometryReader { viewport in
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        if let date = service.date {
                            Text(date)
                                .foregroundStyle(.secondary)
                                .background {
                                    GeometryReader { geometry in
                                        Color.clear.preference(
                                            key: ServiceDateFramePreferenceKey.self,
                                            value: geometry.frame(in: .named(Self.scrollCoordinateSpace))
                                        )
                                    }
                                }
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            Label("Stops", systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                                .font(.headline)

                            VStack(alignment: .leading, spacing: 0) {
                                ForEach(Array(service.stops.enumerated()), id: \.offset) { index, stop in
                                    ServiceStopRow(
                                        stop: stop,
                                        isFirst: index == 0,
                                        isLast: index == service.stops.count - 1,
                                        hasHighlight: highlightedRange != nil,
                                        isHighlighted: highlightedRange?.contains(index) == true,
                                        isHighlightBoundary: index == highlightedRange?.lowerBound ||
                                            index == highlightedRange?.upperBound,
                                        topIsHighlighted: highlightedRange.map {
                                            index > $0.lowerBound && index <= $0.upperBound
                                        } ?? false,
                                        bottomIsHighlighted: highlightedRange.map {
                                            index >= $0.lowerBound && index < $0.upperBound
                                        } ?? false,
                                        highlightedColor: highlightedColor,
                                        showsItemDetails: showsItemDetails,
                                        showsStopNoteText: showsStopNoteText
                                    )
                                    .contentShape(Rectangle())
                                    .contextMenu {
                                        serviceStopSearchActions(
                                            forStopAt: index,
                                            in: service
                                        )
                                    }
                                    .alternatingRowBackground(at: index)
                                    .background {
                                        if index == departureIndex {
                                            GeometryReader { geometry in
                                                Color.clear.preference(
                                                    key: ServiceRouteInitialLayoutPreferenceKey.self,
                                                    value: ServiceRouteInitialLayout(
                                                        departureFrame: geometry.frame(
                                                            in: .named(Self.scrollCoordinateSpace)
                                                        )
                                                    )
                                                )
                                            }
                                        }
                                    }
                                    .id(index)
                                }
                            }
                        }
                        .background {
                            GeometryReader { geometry in
                                Color.clear.preference(
                                    key: ServiceRouteInitialLayoutPreferenceKey.self,
                                    value: ServiceRouteInitialLayout(
                                        routeFrame: geometry.frame(
                                            in: .named(Self.scrollCoordinateSpace)
                                        )
                                    )
                                )
                            }
                        }

                        if !service.serviceInformation.isEmpty {
                            ServiceInformationDisclosure(
                                serviceInformation: service.serviceInformation,
                                timetableValidity: model.timetableValidity,
                                serviceDateLimits: model.serviceDateLimits,
                                serviceTimeZone: serviceTimeZone,
                                isExpanded: $isServiceInformationExpanded
                            )
                        }
                    }
                    .padding(24)
                }
                .coordinateSpace(name: Self.scrollCoordinateSpace)
                .onPreferenceChange(ServiceDateFramePreferenceKey.self) { frame in
                    let newValue = ServiceWindowTitlePresentation.dateIsUnderTitle(frame: frame)
                    if dateIsUnderTitle != newValue {
                        dateIsUnderTitle = newValue
                    }
                }
                .onPreferenceChange(ServiceRouteInitialLayoutPreferenceKey.self) { layout in
                    prepareInitialRoutePosition(
                        layout: layout,
                        viewportHeight: viewport.size.height,
                        departureIndex: departureIndex,
                        proxy: proxy
                    )
                }
                .onAppear {
                    dateIsUnderTitle = false
                }
            }
        }
    }

    /// Starts a stop-derived search in a main scene because route details do not own editable search state.
    @ViewBuilder
    private func serviceStopSearchActions(
        forStopAt index: Int,
        in service: TransitServiceDetail
    ) -> some View {
        ServiceStopSearchOpenActions(
            selections: ServiceStopSearchSelectionFactory.selections(
                forStopAt: index,
                in: service,
                routeHighlight: routeHighlight,
                client: client
            ),
            openConnection: openConnection,
            openDeparture: openDeparture,
            openStationTimetable: openStationTimetable
        )
    }

    private func openConnection(
        _ selection: ConnectionSearchSelection,
        at destination: ConnectionSearchOpenDestination
    ) {
        let sceneValue = MainWindowSceneValue(
            dataSourceID: selection.dataSourceID,
            initialConnectionSelection: selection
        )
        openMainSearch(sceneValue, inNewTab: destination == .newTab)
    }

    private func openDeparture(
        _ selection: DepartureSearchSelection,
        at destination: DepartureSearchOpenDestination
    ) {
        let sceneValue = MainWindowSceneValue(
            dataSourceID: selection.dataSourceID,
            initialDepartureSelection: selection
        )
        openMainSearch(sceneValue, inNewTab: destination == .newTab)
    }

    private func openStationTimetable(
        _ selection: StationTimetableSelection,
        at destination: StationTimetableOpenDestination
    ) {
        let sceneValue = MainWindowSceneValue(
            dataSourceID: selection.dataSourceID,
            initialStationTimetableSelection: selection
        )
        openMainSearch(sceneValue, inNewTab: destination == .newTab)
    }

    private func openMainSearch(_ sceneValue: MainWindowSceneValue, inNewTab: Bool) {
        if inNewTab {
            AppWindowActions.newTab(sceneID: sceneValue.id) {
                openWindow(id: AppWindow.main, value: sceneValue)
            }
        } else {
            openWindow(id: AppWindow.main, value: sceneValue)
        }
    }

    /// Requests the searched departure while allowing the scroll view to clamp at the real content end.
    private func prepareInitialRoutePosition(
        layout: ServiceRouteInitialLayout,
        viewportHeight: CGFloat,
        departureIndex: Int?,
        proxy: ScrollViewProxy
    ) {
        guard
            !hasAppliedInitialRoutePosition,
            !hasScheduledInitialRoutePosition,
            let departureIndex,
            let routeFrame = layout.routeFrame,
            let departureFrame = layout.departureFrame
        else {
            return
        }

        guard ServiceRouteInitialScroll.needsPositioning(
            departureIndex: departureIndex,
            viewportHeight: viewportHeight,
            routeBottom: routeFrame.maxY
        ) else {
            hasAppliedInitialRoutePosition = true
            return
        }

        let topClearance = ServiceRouteInitialScroll.topClearance(for: presentation)
        hasScheduledInitialRoutePosition = true
        let scrollAnchor = ServiceRouteInitialScroll.anchor(
            viewportHeight: viewportHeight,
            departureHeight: departureFrame.height,
            topClearance: topClearance
        )
        ServiceRouteInitialScroll.afterWindowLayout {
            proxy.scrollTo(departureIndex, anchor: scrollAnchor)
            hasAppliedInitialRoutePosition = true
        }
    }
}

/// Keeps supporting service notes out of the route overview until the passenger asks to see them.
struct ServiceInformationDisclosure: View {
    let notes: [String]
    let serviceInformation: [TransitServiceInformation]?
    let timetableValidity: TransitTimetableValidity?
    let serviceDateLimits: TransitServiceDateLimits?
    let serviceTimeZone: TimeZone?
    @Binding var isExpanded: Bool

    init(
        notes: [String],
        timetableValidity: TransitTimetableValidity? = nil,
        serviceDateLimits: TransitServiceDateLimits? = nil,
        serviceTimeZone: TimeZone? = nil,
        isExpanded: Binding<Bool>
    ) {
        self.notes = notes
        serviceInformation = nil
        self.timetableValidity = timetableValidity
        self.serviceDateLimits = serviceDateLimits
        self.serviceTimeZone = serviceTimeZone
        _isExpanded = isExpanded
    }

    /// Retains semantic categories supplied by a structured provider instead of reclassifying its text as IDOS.
    init(
        serviceInformation: [TransitServiceInformation],
        timetableValidity: TransitTimetableValidity? = nil,
        serviceDateLimits: TransitServiceDateLimits? = nil,
        serviceTimeZone: TimeZone? = nil,
        isExpanded: Binding<Bool>
    ) {
        notes = serviceInformation.map(\.text)
        self.serviceInformation = serviceInformation
        self.timetableValidity = timetableValidity
        self.serviceDateLimits = serviceDateLimits
        self.serviceTimeZone = serviceTimeZone
        _isExpanded = isExpanded
    }

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            ServiceNotesView(
                notes: notes,
                serviceInformation: serviceInformation,
                timetableValidity: timetableValidity,
                serviceDateLimits: serviceDateLimits,
                serviceTimeZone: serviceTimeZone,
                requiresExactServiceOperatingDays: true
            )
            .textSelection(.enabled)
            .padding(.top, 8)
        } label: {
            Label("Service information", systemImage: "info.circle")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation {
                        isExpanded.toggle()
                    }
                }
        }
        .accessibilityLabel("Service information")
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Keeps a route marker centered beside the stop content that remains visible.
enum ServiceStopTimelineLayout {
    static let metadataSpacing: CGFloat = 4
    /// Keeps every route marker, stop title, and time away from its alternating band edges.
    static let rowHorizontalPadding: CGFloat = 12
    /// Balances the existing row breathing room above and below its primary stop content.
    static let rowVerticalPadding: CGFloat = 6

    static var topConnectorHeight: CGFloat {
        let headlineHeight = NSFont.preferredFont(forTextStyle: .headline).boundingRectForFont.height
        return max((headlineHeight - RouteStopMarker.diameter) / 2, 0)
    }
}

/// Gives route stops the same outlined marker while allowing endpoints or a selection to stand out.
struct RouteStopMarker: View {
    nonisolated static let diameter: CGFloat = 14

    let color: Color
    let isEmphasized: Bool
    let showsCenter: Bool

    var body: some View {
        ZStack {
            Circle()
                .fill(.background)
            Circle()
                .strokeBorder(color, lineWidth: isEmphasized ? 3 : 2)
            if showsCenter {
                Circle()
                    .fill(color)
                    .frame(width: 6, height: 6)
            }
        }
        .frame(width: Self.diameter, height: Self.diameter)
    }
}

private enum ServiceStopMarkerCenterAlignment: AlignmentID {
    static func defaultValue(in context: ViewDimensions) -> CGFloat {
        context[VerticalAlignment.center]
    }
}

private extension VerticalAlignment {
    static let serviceStopMarkerCenter = VerticalAlignment(ServiceStopMarkerCenterAlignment.self)
}

struct ServiceStopRow: View {
    let stop: TransitServiceStop
    let isFirst: Bool
    let isLast: Bool
    let hasHighlight: Bool
    let isHighlighted: Bool
    let isHighlightBoundary: Bool
    let topIsHighlighted: Bool
    let bottomIsHighlighted: Bool
    let highlightedColor: Color
    let showsItemDetails: Bool
    let showsStopNoteText: Bool

    var body: some View {
        let stationMetadata = ResultMetadata.station(
            tariffZone: stop.tariffZone,
            platform: stop.platform,
            track: stop.track,
            platformTrack: stop.platformTrack
        )
        let compactMetadata = ResultMetadata.compactStopValues(
            showsDetails: showsItemDetails,
            showsSymbolsAsText: showsStopNoteText,
            ResultMetadata.compactStation(
                tariffZone: stop.tariffZone,
                platform: stop.platform,
                track: stop.track,
                platformTrack: stop.platformTrack
            )
        )
        let metadata = ResultMetadata.visible(
            showsDetails: showsItemDetails,
            showsStopNoteText ? stationMetadata : nil,
            stop.distance
        )
        let notePresentation = StopNotePresentation(
            notes: stop.notes,
            showsText: showsStopNoteText
        )

        HStack(alignment: .serviceStopMarkerCenter, spacing: 12) {
            VStack(spacing: 0) {
                Rectangle()
                    .fill(isFirst ? Color.clear : topRouteColor)
                    .frame(
                        width: 2,
                        height: ServiceStopTimelineLayout.topConnectorHeight
                    )

                RouteStopMarker(
                    color: markerColor,
                    isEmphasized: isHighlighted,
                    showsCenter: isFirst || isLast || isHighlightBoundary
                )
                .alignmentGuide(.serviceStopMarkerCenter) { context in
                    context[VerticalAlignment.center]
                }

                Rectangle()
                    .fill(isLast ? Color.clear : bottomRouteColor)
                    .frame(width: 2)
                    .frame(maxHeight: .infinity)
            }
            .frame(width: RouteStopMarker.diameter)

            VStack(alignment: .leading, spacing: ServiceStopTimelineLayout.metadataSpacing) {
                HStack(alignment: .firstTextBaseline) {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(stop.name)
                        StopNoteSymbols(values: notePresentation.symbols)
                        CompactStopMetadata(values: compactMetadata)
                    }
                    .font(.headline)
                    .foregroundStyle(isDimmed ? Color.secondary : Color.primary)
                    Spacer()
                    Text(stopTimes)
                        .font(.body.monospacedDigit())
                        .foregroundStyle(isDimmed ? Color.secondary : Color.primary)
                }
                .alignmentGuide(.serviceStopMarkerCenter) { context in
                    context[VerticalAlignment.center]
                }

                if let metadata {
                    Text(metadata)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                ForEach(notePresentation.textNotes, id: \.self) { note in
                    NoteText(note)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, ServiceStopTimelineLayout.rowVerticalPadding)
        }
        .padding(.horizontal, ServiceStopTimelineLayout.rowHorizontalPadding)
    }

    private var neutralRouteColor: Color {
        .secondary.opacity(0.55)
    }

    private var markerColor: Color {
        isHighlighted ? highlightedColor : neutralRouteColor
    }

    private var topRouteColor: Color {
        topIsHighlighted ? highlightedColor : neutralRouteColor
    }

    private var bottomRouteColor: Color {
        bottomIsHighlighted ? highlightedColor : neutralRouteColor
    }

    private var isDimmed: Bool {
        hasHighlight && !isHighlighted
    }

    private var stopTimes: String {
        switch (stop.arrivalTime, stop.departureTime) {
        case let (arrival?, departure?) where arrival != departure:
            return "\(arrival) / \(departure)"
        case let (arrival?, _):
            return arrival
        case let (_, departure?):
            return departure
        default:
            return ""
        }
    }
}
