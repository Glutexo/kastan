import Kastan
import SwiftUI

/// Loads a service lazily when its complete route or contextual detail actions need data.
@MainActor
final class ServiceDetailViewModel: ObservableObject {
    @Published private(set) var service: IDOSServiceDetail?
    @Published private(set) var timetableValidity: IDOSTimetableValidity?
    @Published private(set) var isLoading = false
    @Published private(set) var isAddingToCalendar = false
    @Published private(set) var isSavingPDF = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var actionErrorMessage: String?

    private let id: String
    private let client: any IDOSClienting
    private let calendarImporter: any CalendarImporting
    private let pdfExporter: any PDFExporting

    init(
        id: String,
        client: any IDOSClienting,
        calendarImporter: any CalendarImporting = WorkspaceCalendarImporter(),
        pdfExporter: any PDFExporting = WorkspacePDFExporter()
    ) {
        self.id = id
        self.client = client
        self.calendarImporter = calendarImporter
        self.pdfExporter = pdfExporter
    }

    var isPerformingExport: Bool {
        isAddingToCalendar || isSavingPDF
    }

    func load() async {
        guard service == nil, !isLoading else {
            return
        }
        isLoading = true
        errorMessage = nil

        do {
            let service = try await client.serviceDetail(id: id, language: AppLanguagePreference.idosLanguage)
            self.service = service
            isLoading = false
            timetableValidity = try? await client.timetableValidity(
                for: service.timetable,
                language: AppLanguagePreference.idosLanguage
            )
        } catch {
            isLoading = false
            errorMessage = AppErrorPresentation.message(for: error)
        }
    }

    /// Opens the dated service's native IDOS calendar export in the user's calendar application.
    func addToCalendar() async {
        guard let service, !isPerformingExport else {
            return
        }
        isAddingToCalendar = true
        actionErrorMessage = nil
        defer { isAddingToCalendar = false }

        do {
            let calendar = try await client.serviceCalendar(for: service)
            try calendarImporter.open(calendarText: calendar)
        } catch {
            actionErrorMessage = AppErrorPresentation.message(for: error)
        }
    }

    /// Saves the dated service's native IDOS PDF to a location chosen by the user.
    func saveAsPDF() async {
        guard let service, !isPerformingExport else {
            return
        }
        isSavingPDF = true
        actionErrorMessage = nil
        defer { isSavingPDF = false }

        do {
            let data = try await client.servicePDF(
                for: service,
                language: AppLanguagePreference.idosLanguage
            )
            try await pdfExporter.save(
                pdfData: data,
                suggestedFileName: PDFExportFileName.connection(
                    from: service.stops.first?.name ?? service.name,
                    to: service.stops.last?.name ?? service.name
                )
            )
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

    @Environment(\.openURL) private var openURL
    @StateObject private var model: ServiceDetailViewModel
    @State private var dateIsUnderTitle = false
    @State private var hasAppliedInitialRoutePosition = false
    @State private var hasScheduledInitialRoutePosition = false
    @State private var initialRouteBottomClearance: CGFloat = 0
    private let routeHighlight: ServiceRouteHighlight?
    private let presentation: ResultDetailPresentation

    init(
        selection: ServiceSelection,
        client: any IDOSClienting,
        presentation: ResultDetailPresentation = .window
    ) {
        routeHighlight = selection.highlight
        self.presentation = presentation
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
                            hasPermanentLink: serviceActionURL != nil
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

    private var resultDetailCommandContext: ResultDetailCommandContext {
        ResultDetailCommandContext(
            hasLoadedResult: model.service != nil,
            isPerformingExport: model.isPerformingExport,
            permanentLink: serviceActionURL,
            copyToClipboard: {
                if let service = model.service {
                    ResultClipboard.copy(service: service)
                }
            },
            addToCalendar: {
                Task { await model.addToCalendar() }
            },
            saveAsPDF: {
                Task { await model.saveAsPDF() }
            },
            openInIDOS: {
                if let serviceActionURL {
                    openURL(serviceActionURL)
                }
            }
        )
    }

    /// Renders each service action as an independent native toolbar control.
    @ViewBuilder
    private func serviceActionControl(_ action: ResultDetailAction, url: URL?) -> some View {
        switch action {
        case .copyToClipboard:
            Button {
                if let service = model.service {
                    ResultClipboard.copy(service: service)
                }
            } label: {
                serviceActionLabel(action)
            }
            .disabled(model.isPerformingExport)
            .accessibilityLabel(action.title)
            .help(action.title)
        case .addToCalendar:
            Button {
                Task { await model.addToCalendar() }
            } label: {
                exportActionLabel(action, isPerforming: model.isAddingToCalendar)
            }
            .disabled(model.isPerformingExport)
            .accessibilityLabel(action.title)
            .help(action.title)
        case .saveAsPDF:
            Button {
                Task { await model.saveAsPDF() }
            } label: {
                exportActionLabel(action, isPerforming: model.isSavingPDF)
            }
            .disabled(model.isPerformingExport)
            .accessibilityLabel(action.title)
            .help(action.title)
        case .shareLink:
            if let url {
                ShareLink(item: url) {
                    serviceActionLabel(action)
                }
                .disabled(model.isPerformingExport)
                .help(action.title)
            }
        case .openInIDOS:
            if let url {
                Button {
                    openURL(url)
                } label: {
                    serviceActionLabel(action)
                }
                .disabled(model.isPerformingExport)
                .accessibilityLabel(action.title)
                .help(action.title)
            }
        }
    }

    @ViewBuilder
    private func exportActionLabel(
        _ action: ResultDetailAction,
        isPerforming: Bool
    ) -> some View {
        if isPerforming {
            ProgressView()
                .controlSize(.small)
        } else {
            serviceActionLabel(action)
        }
    }

    private func serviceActionLabel(_ action: ResultDetailAction) -> some View {
        Label(action.title, systemImage: action.systemImage)
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
                                            highlightedColor: highlightedColor
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
            return
        }

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

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 0) {
                Rectangle()
                    .fill(isFirst ? Color.clear : topRouteColor)
                    .frame(width: 2, height: 10)

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
                .frame(width: 14, height: 14)

                Rectangle()
                    .fill(isLast ? Color.clear : bottomRouteColor)
                    .frame(width: 2)
                    .frame(maxHeight: .infinity)
            }
            .frame(width: 14)

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text(stop.name)
                        .font(.headline)
                        .foregroundStyle(isDimmed ? Color.secondary : Color.primary)
                    Spacer()
                    Text(stopTimes)
                        .font(.body.monospacedDigit())
                        .foregroundStyle(isDimmed ? Color.secondary : Color.primary)
                }

                if let metadata = ResultMetadata.joined(
                    ResultMetadata.station(tariffZone: stop.tariffZone, platform: stop.platform),
                    stop.track.map { AppLocalization.string("Track %@", $0) },
                    stop.distance
                ) {
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
