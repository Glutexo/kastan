import AppKit
import Kastan
import SwiftUI

/// Loads a service lazily when its complete route or contextual detail actions need data.
@MainActor
final class ServiceDetailViewModel: ObservableObject {
    @Published private(set) var service: IDOSServiceDetail?
    @Published private(set) var timetableValidity: IDOSTimetableValidity?
    @Published private(set) var serviceDateLimits: IDOSServiceDateLimits?
    @Published private(set) var isLoading = false
    @Published private(set) var isProcessingCalendar = false
    @Published private(set) var isProcessingPDF = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var actionErrorMessage: String?

    private let id: String
    private let client: any IDOSClienting
    private let calendarImporter: any CalendarImporting
    private let calendarSaver: any CalendarSaving
    private let pdfOpener: any PDFOpening
    private let pdfExporter: any PDFExporting
    private var activeLoadTask: Task<IDOSServiceDetail, Error>?
    private var activeLoadIdentifier: UUID?

    init(
        id: String,
        client: any IDOSClienting,
        calendarImporter: any CalendarImporting = WorkspaceCalendarImporter(),
        calendarSaver: any CalendarSaving = WorkspaceCalendarSaver(),
        pdfOpener: any PDFOpening = WorkspacePDFOpener(),
        pdfExporter: any PDFExporting = WorkspacePDFExporter()
    ) {
        self.id = id
        self.client = client
        self.calendarImporter = calendarImporter
        self.calendarSaver = calendarSaver
        self.pdfOpener = pdfOpener
        self.pdfExporter = pdfExporter
    }

    var isPerformingExport: Bool {
        isProcessingCalendar || isProcessingPDF
    }

    func load() async {
        guard service == nil else { return }

        let loadTask: Task<IDOSServiceDetail, Error>
        let loadIdentifier: UUID
        if let activeLoadTask, let activeLoadIdentifier {
            loadTask = activeLoadTask
            loadIdentifier = activeLoadIdentifier
        } else {
            isLoading = true
            errorMessage = nil

            let id = self.id
            let client = self.client
            let language = AppLanguagePreference.idosLanguage
            loadTask = Task {
                try await client.serviceDetail(id: id, language: language)
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
            let language = AppLanguagePreference.idosLanguage
            async let loadedTimetableValidity = try? client.timetableValidity(
                for: service.timetable,
                language: language
            )
            async let loadedServiceDateLimits = try? client.serviceDateLimits(
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

    /// Supplies a complete service to an action, joining an existing request instead of requiring a second menu opening.
    func loadedService() async -> IDOSServiceDetail? {
        await load()
        return service
    }

    /// Resolves the permanent IDOS result link only when an action actually needs it.
    func localizedPermanentLink() async -> URL? {
        (await loadedService())?.shareURL.flatMap(AppLanguagePreference.localizedIDOSURL)
    }

    /// Formats the same complete localized service detail that Kaštan exposes from loaded result windows.
    func localizedShareText() async -> String? {
        (await loadedService()).map(CLIPlainTextPresentation().service)
    }

    /// Fetches the dated service's calendar and either opens it or lets the user retain its ICS file.
    func performCalendarAction(_ action: CalendarExportAction) async {
        guard !isPerformingExport,
              let service = await loadedService(),
              !isPerformingExport
        else { return }
        isProcessingCalendar = true
        actionErrorMessage = nil
        defer { isProcessingCalendar = false }

        do {
            let calendar = try await client.serviceCalendar(
                for: service,
                language: AppLanguagePreference.idosLanguage
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
            actionErrorMessage = AppErrorPresentation.message(for: error)
        }
    }

    /// Fetches the dated service's PDF and either opens it in Preview or lets the user retain its file.
    func performPDFAction(_ action: PDFExportAction) async {
        guard !isPerformingExport,
              let service = await loadedService(),
              !isPerformingExport
        else { return }
        isProcessingPDF = true
        actionErrorMessage = nil
        defer { isProcessingPDF = false }

        do {
            let data = try await client.servicePDF(
                for: service,
                language: AppLanguagePreference.idosLanguage
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
            actionErrorMessage = AppErrorPresentation.message(for: error)
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
    func departureIndex(in stops: [IDOSServiceStop]) -> Int? {
        guard let fromStop, !stops.isEmpty else { return nil }
        return stopIndex(matching: fromStop, in: stops.indices, stops: stops)
    }

    func range(in stops: [IDOSServiceStop]) -> ClosedRange<Int>? {
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
        stops: [IDOSServiceStop]
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
    let id: String
    let highlight: ServiceRouteHighlight?

    init(id: String, highlight: ServiceRouteHighlight? = nil) {
        self.id = id
        self.highlight = highlight
    }
}

/// Recreates lazy route state whenever an existing detail scene is retargeted to another selected service.
struct ServiceDetailWindowContent: View {
    let selection: ServiceSelection
    let client: any IDOSClienting
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

/// Moves a service date into the window title exactly when its content label has scrolled away.
enum ServiceWindowTitlePresentation {
    static func title(for service: IDOSServiceDetail?, dateIsUnderTitle: Bool) -> String {
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

/// Shows every stop and piece of service information supplied by IDOS in its own window.
struct ServiceDetailView: View {
    /// Opens new service routes at the compact width already supported by the adaptive route layout.
    static let minimumWindowWidth: CGFloat = 400
    static let defaultWindowWidth = minimumWindowWidth

    private static let scrollCoordinateSpace = "service-detail-scroll"

    @StateObject private var model: ServiceDetailViewModel
    @State private var dateIsUnderTitle = false
    @State private var hasAppliedInitialRoutePosition = false
    @State private var hasScheduledInitialRoutePosition = false
    @State private var isServiceInformationExpanded = false
    private let routeHighlight: ServiceRouteHighlight?
    private let presentation: ResultDetailPresentation
    private let showsItemDetails: Bool
    private let showsStopNoteText: Bool

    init(
        selection: ServiceSelection,
        client: any IDOSClienting,
        showsItemDetails: Bool,
        showsStopNoteText: Bool,
        presentation: ResultDetailPresentation = .window
    ) {
        routeHighlight = selection.highlight
        self.presentation = presentation
        self.showsItemDetails = showsItemDetails
        self.showsStopNoteText = showsStopNoteText
        _model = StateObject(wrappedValue: ServiceDetailViewModel(id: selection.id, client: client))
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
                            hasPermanentLink: serviceActionURL != nil,
                            canSendByEmail: false
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
    }

    private var windowTitle: String {
        ServiceWindowTitlePresentation.title(
            for: model.service,
            dateIsUnderTitle: dateIsUnderTitle
        )
    }

    private var serviceActionURL: URL? {
        model.service?.shareURL.flatMap(AppLanguagePreference.localizedIDOSURL)
    }

    private var serviceShareText: String? {
        model.service.map(CLIPlainTextPresentation().service)
    }

    private var resultDetailCommandContext: ResultDetailCommandContext {
        ResultDetailCommandContext(
            hasLoadedResult: model.service != nil,
            isPerformingAction: model.isPerformingExport,
            permanentLink: serviceActionURL,
            shareText: serviceShareText,
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
        if isPerforming {
            ProgressView()
                .controlSize(.small)
        } else {
            serviceActionLabel(
                action,
                calendarExportAction: calendarExportAction,
                pdfExportAction: pdfExportAction
            )
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

    private func serviceContent(_ service: IDOSServiceDetail) -> some View {
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

                        if let actionErrorMessage = model.actionErrorMessage {
                            Label(actionErrorMessage, systemImage: "exclamationmark.triangle.fill")
                                .foregroundStyle(.red)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(12)
                                .background(.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
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

                        if !service.information.isEmpty {
                            ServiceInformationDisclosure(
                                notes: service.information,
                                timetableValidity: model.timetableValidity,
                                serviceDateLimits: model.serviceDateLimits,
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
    let timetableValidity: IDOSTimetableValidity?
    let serviceDateLimits: IDOSServiceDateLimits?
    @Binding var isExpanded: Bool

    init(
        notes: [String],
        timetableValidity: IDOSTimetableValidity? = nil,
        serviceDateLimits: IDOSServiceDateLimits? = nil,
        isExpanded: Binding<Bool>
    ) {
        self.notes = notes
        self.timetableValidity = timetableValidity
        self.serviceDateLimits = serviceDateLimits
        _isExpanded = isExpanded
    }

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            ServiceNotesView(
                notes: notes,
                timetableValidity: timetableValidity,
                serviceDateLimits: serviceDateLimits,
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
    let stop: IDOSServiceStop
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
