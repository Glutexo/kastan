import Kastan
import SwiftUI

/// Loads a service lazily when the user opens its complete route.
@MainActor
final class ServiceDetailViewModel: ObservableObject {
    @Published private(set) var service: IDOSServiceDetail?
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
        defer { isLoading = false }

        do {
            service = try await client.serviceDetail(id: id, language: AppLanguagePreference.idosLanguage)
        } catch {
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

    func range(in stops: [IDOSServiceStop]) -> ClosedRange<Int>? {
        guard !stops.isEmpty else { return nil }

        let startIndex = fromStop.flatMap { stopIndex(matching: $0, in: stops.indices, stops: stops) }
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

/// Defines the four service actions that remain directly visible in the detail window toolbar.
enum ServiceDetailToolbarAction: CaseIterable, Hashable, Identifiable {
    case addToCalendar
    case saveAsPDF
    case shareLink
    case openInIDOS

    var id: Self { self }

    var title: LocalizedStringKey {
        switch self {
        case .addToCalendar:
            "Add to Calendar"
        case .saveAsPDF:
            "Save as PDF"
        case .shareLink:
            "Share Link"
        case .openInIDOS:
            "Open in IDOS"
        }
    }

    var systemImage: String {
        switch self {
        case .addToCalendar:
            "calendar.badge.plus"
        case .saveAsPDF:
            "arrow.down.doc"
        case .shareLink:
            "square.and.arrow.up"
        case .openInIDOS:
            "arrow.up.right.square"
        }
    }
}

/// Shows every stop and piece of service information supplied by IDOS in its own window.
struct ServiceDetailView: View {
    private static let scrollCoordinateSpace = "service-detail-scroll"

    @Environment(\.openURL) private var openURL
    @StateObject private var model: ServiceDetailViewModel
    @State private var dateIsUnderTitle = false
    private let routeHighlight: ServiceRouteHighlight?

    init(selection: ServiceSelection, client: any IDOSClienting) {
        routeHighlight = selection.highlight
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
        .frame(minWidth: 680, minHeight: 520)
        .navigationTitle(windowTitle)
        .toolbar {
            if let serviceActionURL {
                ToolbarItemGroup(placement: .primaryAction) {
                    ForEach(ServiceDetailToolbarAction.allCases) { action in
                        serviceActionControl(action, url: serviceActionURL)
                    }
                }
            }
        }
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

    /// Renders each service action as an independent native toolbar control.
    @ViewBuilder
    private func serviceActionControl(_ action: ServiceDetailToolbarAction, url: URL) -> some View {
        switch action {
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
            ShareLink(item: url) {
                serviceActionLabel(action)
            }
            .disabled(model.isPerformingExport)
            .help(action.title)
        case .openInIDOS:
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

    @ViewBuilder
    private func exportActionLabel(
        _ action: ServiceDetailToolbarAction,
        isPerforming: Bool
    ) -> some View {
        if isPerforming {
            ProgressView()
                .controlSize(.small)
        } else {
            serviceActionLabel(action)
        }
    }

    private func serviceActionLabel(_ action: ServiceDetailToolbarAction) -> some View {
        Label(action.title, systemImage: action.systemImage)
            .labelStyle(.iconOnly)
    }

    private func serviceContent(_ service: IDOSServiceDetail) -> some View {
        let highlightedRange = routeHighlight?.range(in: service.stops)
        let highlightedColor = Color(idosHTMLColor: service.color) ?? .accentColor

        return ScrollView {
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
                        }
                    }
                }

                if !service.information.isEmpty {
                    GroupBox("Service information") {
                        BulletedTextList(items: service.information)
                            .textSelection(.enabled)
                    }
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
        .onAppear {
            dateIsUnderTitle = false
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
