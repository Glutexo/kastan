import AppKit
import Kastan
import SwiftUI

/// Loads a service lazily when its complete route or contextual detail actions need data.
@MainActor
final class ServiceDetailViewModel: ObservableObject {
    @Published private(set) var service: IDOSServiceDetail?
    @Published private(set) var timetableValidity: IDOSTimetableValidity?
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
            timetableValidity = try? await client.timetableValidity(
                for: service.timetable,
                language: AppLanguagePreference.idosLanguage
            )
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

/// Supplies the geometry needed to keep a searched departure stop at the visible top of a route.
private struct ServiceRouteInitialLayout: Equatable {
    var naturalContentFrame: CGRect?
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
        value.naturalContentFrame = nextValue.naturalContentFrame ?? value.naturalContentFrame
        value.routeFrame = nextValue.routeFrame ?? value.routeFrame
        value.departureFrame = nextValue.departureFrame ?? value.departureFrame
    }
}

/// Makes enough room below a route to place its searched departure stop at the visible top.
@MainActor
enum ServiceRouteInitialScroll {
    /// Leaves the searched departure clear of either a toolbar or the rounded preview edge.
    static func topClearance(for presentation: ResultDetailPresentation) -> CGFloat {
        presentation == .preview ? 12 : 8
    }

    /// Preserves the natural top when no preceding route needs to be skipped or the complete route already fits.
    static func needsPositioning(
        departureIndex: Int,
        viewportHeight: CGFloat,
        routeBottom: CGFloat
    ) -> Bool {
        departureIndex > 0 && routeBottom > viewportHeight
    }

    static func bottomClearance(
        viewportHeight: CGFloat,
        naturalContentBottom: CGFloat,
        departureTop: CGFloat,
        topClearance: CGFloat
    ) -> CGFloat {
        let contentBelowDeparture = max(0, naturalContentBottom - departureTop)
        return max(0, viewportHeight - topClearance - contentBelowDeparture)
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
    /// Keeps new service windows compact while leaving room for the adaptive route and information layout.
    static let defaultWindowWidth: CGFloat = 540
    static let minimumWindowWidth: CGFloat = 480

    private static let scrollCoordinateSpace = "service-detail-scroll"

    @StateObject private var model: ServiceDetailViewModel
    @State private var dateIsUnderTitle = false
    @State private var hasAppliedInitialRoutePosition = false
    @State private var hasScheduledInitialRoutePosition = false
    @State private var initialRouteBottomClearance: CGFloat = 0
    private let routeHighlight: ServiceRouteHighlight?
    private let presentation: ResultDetailPresentation
    private let showsItemDetails: Bool

    init(
        selection: ServiceSelection,
        client: any IDOSClienting,
        showsItemDetails: Bool,
        presentation: ResultDetailPresentation = .window
    ) {
        routeHighlight = selection.highlight
        self.presentation = presentation
        self.showsItemDetails = showsItemDetails
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
                    VStack(spacing: 0) {
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
                                            showsItemDetails: showsItemDetails
                                        )
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
                                GroupBox("Service information") {
                                    ServiceNotesView(
                                        notes: service.information,
                                        timetableValidity: model.timetableValidity
                                    )
                                        .textSelection(.enabled)
                                }
                            }
                        }
                        .padding(24)
                        .background {
                            GeometryReader { geometry in
                                Color.clear.preference(
                                    key: ServiceRouteInitialLayoutPreferenceKey.self,
                                    value: ServiceRouteInitialLayout(
                                        naturalContentFrame: geometry.frame(
                                            in: .named(Self.scrollCoordinateSpace)
                                        )
                                    )
                                )
                            }
                        }

                        Color.clear
                            .frame(height: initialRouteBottomClearance)
                    }
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

    /// Adds only the trailing room the scroll view needs before aligning the searched departure stop.
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
            let naturalContentFrame = layout.naturalContentFrame,
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
            if initialRouteBottomClearance > 0.5 {
                initialRouteBottomClearance = 0
                return
            }
            hasAppliedInitialRoutePosition = true
            return
        }

        let topClearance = ServiceRouteInitialScroll.topClearance(for: presentation)
        let bottomClearance = ServiceRouteInitialScroll.bottomClearance(
            viewportHeight: viewportHeight,
            naturalContentBottom: naturalContentFrame.maxY,
            departureTop: departureFrame.minY,
            topClearance: topClearance
        )
        if abs(initialRouteBottomClearance - bottomClearance) > 0.5 {
            initialRouteBottomClearance = bottomClearance
        }

        // The trailing spacer does not change these measured frames, so a preview may not emit another preference.
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

/// Keeps a route marker centered beside the stop content that remains visible.
enum ServiceStopTimelineLayout {
    static let markerDiameter: CGFloat = 14
    static let metadataSpacing: CGFloat = 4

    static func topConnectorHeight(hasVisibleMetadata: Bool) -> CGFloat {
        let headlineHeight = NSFont.preferredFont(forTextStyle: .headline).boundingRectForFont.height
        let metadataHeight = hasVisibleMetadata
            ? metadataSpacing + NSFont.preferredFont(forTextStyle: .caption1).boundingRectForFont.height
            : 0
        return max(((headlineHeight + metadataHeight) - markerDiameter) / 2, 0)
    }
}

private struct ServiceStopRow: View {
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

    var body: some View {
        let metadata = ResultMetadata.visible(
            showsDetails: showsItemDetails,
            ResultMetadata.station(tariffZone: stop.tariffZone, platform: stop.platform),
            stop.track.map { AppLocalization.string("Track %@", $0) },
            stop.distance
        )

        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 0) {
                Rectangle()
                    .fill(isFirst ? Color.clear : topRouteColor)
                    .frame(
                        width: 2,
                        height: ServiceStopTimelineLayout.topConnectorHeight(
                            hasVisibleMetadata: metadata != nil
                        )
                    )

                ZStack {
                    Circle()
                        .fill(.background)
                    Circle()
                        .strokeBorder(markerColor, lineWidth: isHighlighted ? 3 : 2)
                    if isFirst || isLast || isHighlightBoundary {
                        Circle()
                            .fill(markerColor)
                            .frame(width: 6, height: 6)
                    }
                }
                .frame(
                    width: ServiceStopTimelineLayout.markerDiameter,
                    height: ServiceStopTimelineLayout.markerDiameter
                )

                Rectangle()
                    .fill(isLast ? Color.clear : bottomRouteColor)
                    .frame(width: 2)
                    .frame(maxHeight: .infinity)
            }
            .frame(width: ServiceStopTimelineLayout.markerDiameter)

            VStack(alignment: .leading, spacing: ServiceStopTimelineLayout.metadataSpacing) {
                HStack(alignment: .firstTextBaseline) {
                    Text(stop.name)
                        .font(.headline)
                        .foregroundStyle(isDimmed ? Color.secondary : Color.primary)
                    Spacer()
                    Text(stopTimes)
                        .font(.body.monospacedDigit())
                        .foregroundStyle(isDimmed ? Color.secondary : Color.primary)
                }

                if let metadata {
                    Text(metadata)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                ForEach(stop.notes, id: \.self) { note in
                    NoteText(note)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.bottom, 12)
        }
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
