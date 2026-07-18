import Kastan
import SwiftUI

/// The three equivalent IDOS search modes available from the main window toolbar.
enum AppSection: String, CaseIterable, Hashable, Identifiable {
    case connections
    case departures
    case stationTimetables

    var id: Self { self }

    var title: LocalizedStringKey {
        switch self {
        case .connections:
            "Connections"
        case .departures:
            "Departures"
        case .stationTimetables:
            "Station timetables"
        }
    }

    var systemImage: String {
        switch self {
        case .connections:
            "arrow.left.arrow.right"
        case .departures:
            "list.bullet.rectangle"
        case .stationTimetables:
            "calendar"
        }
    }
}

/// Exposes the active window's search mode to app-level menu commands.
struct AppSectionSelectionKey: FocusedValueKey {
    typealias Value = Binding<AppSection>
}

extension FocusedValues {
    var appSectionSelection: Binding<AppSection>? {
        get { self[AppSectionSelectionKey.self] }
        set { self[AppSectionSelectionKey.self] = newValue }
    }
}

/// Converts the detail column's measured width into stable responsive layout decisions.
struct DetailLayout {
    private static let compactPaddingBreakpoint: CGFloat = 600
    private static let stackedSearchBreakpoint: CGFloat = 820

    let availableWidth: CGFloat

    var containerWidth: CGFloat {
        max(availableWidth, 0)
    }

    var horizontalPadding: CGFloat {
        availableWidth < Self.compactPaddingBreakpoint ? 16 : 24
    }

    var contentWidth: CGFloat {
        max(containerWidth - (2 * horizontalPadding), 0)
    }

    var usesStackedSearchControls: Bool {
        contentWidth < Self.stackedSearchBreakpoint
    }
}

/// Identifies the result-list edge crossed far enough to request another chronological page.
enum SearchResultPagingEdge: Equatable {
    case earlier
    case later
}

/// Converts elastic scroll distance into one load per pull-and-release gesture.
struct SearchResultPullTrigger {
    static let activationDistance: CGFloat = 48
    private static let releaseDistance: CGFloat = 4

    private var didTriggerEarlier = false
    private var didTriggerLater = false

    mutating func edgeToLoad(
        contentFrame: CGRect,
        viewportHeight: CGFloat,
        canLoadEarlier: Bool,
        canLoadLater: Bool,
        isLoadingEarlier: Bool,
        isLoadingLater: Bool
    ) -> SearchResultPagingEdge? {
        guard !contentFrame.isNull, viewportHeight > 0 else { return nil }

        let earlierDistance = max(contentFrame.minY, 0)
        let laterDistance = max(viewportHeight - contentFrame.maxY, 0)

        if earlierDistance <= Self.releaseDistance, !isLoadingEarlier {
            didTriggerEarlier = false
        }
        if laterDistance <= Self.releaseDistance, !isLoadingLater {
            didTriggerLater = false
        }

        guard contentFrame.height > viewportHeight + 1 else { return nil }

        if canLoadEarlier,
           !isLoadingEarlier,
           !didTriggerEarlier,
           earlierDistance >= Self.activationDistance
        {
            didTriggerEarlier = true
            return .earlier
        }
        if canLoadLater,
           !isLoadingLater,
           !didTriggerLater,
           laterDistance >= Self.activationDistance
        {
            didTriggerLater = true
            return .later
        }
        return nil
    }
}

private struct SearchResultContentFramePreferenceKey: PreferenceKey {
    static let defaultValue = CGRect.null

    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        value = nextValue()
    }
}

private struct SearchResultViewportHeightPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

/// Keeps search controls visible while giving only the result area the remaining scrollable space.
struct SearchWorkspace<SearchContent: View, ResultsContent: View>: View {
    let layout: DetailLayout
    private let searchVerticalPadding: CGFloat
    private let canLoadEarlier: Bool
    private let canLoadLater: Bool
    private let isLoadingEarlier: Bool
    private let isLoadingLater: Bool
    private let loadEarlier: (@MainActor () async -> Void)?
    private let loadLater: (@MainActor () async -> Void)?
    private let searchContent: SearchContent
    private let resultsContent: ResultsContent
    @Namespace private var scrollCoordinateSpace
    @State private var contentFrame = CGRect.null
    @State private var viewportHeight: CGFloat = 0
    @State private var pullTrigger = SearchResultPullTrigger()

    init(
        layout: DetailLayout,
        searchVerticalPadding: CGFloat = 18,
        canLoadEarlier: Bool = false,
        canLoadLater: Bool = false,
        isLoadingEarlier: Bool = false,
        isLoadingLater: Bool = false,
        loadEarlier: (@MainActor () async -> Void)? = nil,
        loadLater: (@MainActor () async -> Void)? = nil,
        @ViewBuilder searchContent: () -> SearchContent,
        @ViewBuilder resultsContent: () -> ResultsContent
    ) {
        self.layout = layout
        self.searchVerticalPadding = searchVerticalPadding
        self.canLoadEarlier = canLoadEarlier
        self.canLoadLater = canLoadLater
        self.isLoadingEarlier = isLoadingEarlier
        self.isLoadingLater = isLoadingLater
        self.loadEarlier = loadEarlier
        self.loadLater = loadLater
        self.searchContent = searchContent()
        self.resultsContent = resultsContent()
    }

    var body: some View {
        VStack(spacing: 0) {
            searchContent
                .padding(.horizontal, layout.horizontalPadding)
                .padding(.vertical, searchVerticalPadding)
                .frame(width: layout.containerWidth, alignment: .topLeading)
                .frame(width: layout.availableWidth, alignment: .topLeading)
                .background(.bar)

            Divider()

            ScrollView {
                VStack(spacing: 0) {
                    if isLoadingEarlier {
                        ProgressView("Loading earlier results…")
                            .controlSize(.small)
                            .padding(.vertical, 12)
                    }

                    resultsContent
                        .padding(.horizontal, layout.horizontalPadding)
                        .padding(.vertical, 20)
                        .frame(width: layout.containerWidth, alignment: .topLeading)
                        .frame(width: layout.availableWidth, alignment: .topLeading)

                    if isLoadingLater {
                        ProgressView("Loading later results…")
                            .controlSize(.small)
                            .padding(.vertical, 12)
                    }
                }
                .frame(
                    maxWidth: .infinity,
                    minHeight: viewportHeight + 2,
                    alignment: .top
                )
                .background {
                    GeometryReader { geometry in
                        Color.clear.preference(
                            key: SearchResultContentFramePreferenceKey.self,
                            value: geometry.frame(in: .named(scrollCoordinateSpace))
                        )
                    }
                }
            }
            .coordinateSpace(name: scrollCoordinateSpace)
            .background {
                GeometryReader { geometry in
                    Color.clear.preference(
                        key: SearchResultViewportHeightPreferenceKey.self,
                        value: geometry.size.height
                    )
                }
            }
            .onPreferenceChange(SearchResultContentFramePreferenceKey.self) { frame in
                contentFrame = frame
                evaluatePagingPull()
            }
            .onPreferenceChange(SearchResultViewportHeightPreferenceKey.self) { height in
                viewportHeight = height
                evaluatePagingPull()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private func evaluatePagingPull() {
        var trigger = pullTrigger
        let edge = trigger.edgeToLoad(
            contentFrame: contentFrame,
            viewportHeight: viewportHeight,
            canLoadEarlier: canLoadEarlier,
            canLoadLater: canLoadLater,
            isLoadingEarlier: isLoadingEarlier,
            isLoadingLater: isLoadingLater
        )
        pullTrigger = trigger

        switch edge {
        case .earlier:
            guard let loadEarlier else { return }
            Task { @MainActor in await loadEarlier() }
        case .later:
            guard let loadLater else { return }
            Task { @MainActor in await loadLater() }
        case nil:
            break
        }
    }
}

/// Retains independent search state while the toolbar switches among all three IDOS search modes.
struct ContentView: View {
    /// Reserves the compact toolbar for the search-mode picker so it never collapses into overflow.
    struct ToolbarLayout {
        static let compactBreakpoint: CGFloat = 720

        let availableWidth: CGFloat

        var isCompact: Bool {
            availableWidth < Self.compactBreakpoint
        }

        var modePickerWidth: CGFloat {
            isCompact ? 260 : 320
        }
    }

    @Environment(\.openWindow) private var openWindow
    private let client: any IDOSClienting
    @StateObject private var connectionsModel: ConnectionsViewModel
    @StateObject private var departuresModel: DeparturesViewModel
    @StateObject private var stationTimetablesModel: StationTimetablesViewModel
    @State private var selection = AppSection.connections

    init(client: any IDOSClienting) {
        self.client = client
        _connectionsModel = StateObject(wrappedValue: ConnectionsViewModel(client: client))
        _departuresModel = StateObject(wrappedValue: DeparturesViewModel(client: client))
        _stationTimetablesModel = StateObject(wrappedValue: StationTimetablesViewModel(client: client))
    }

    var body: some View {
        GeometryReader { geometry in
            let toolbarLayout = ToolbarLayout(availableWidth: geometry.size.width)

            NavigationStack {
                selectedContent
                    .navigationTitle("")
                    .toolbar {
                        ToolbarItem(placement: .principal) {
                            modePicker(width: toolbarLayout.modePickerWidth)
                        }

                        if !toolbarLayout.isCompact {
                            ToolbarItemGroup(placement: .primaryAction) {
                                favoriteTimetablesButton
                                appInformationButton
                            }
                        }
                    }
            }
        }
        .focusedSceneValue(\.appSectionSelection, $selection)
    }

    private func modePicker(width: CGFloat) -> some View {
        Picker("Search mode", selection: $selection) {
            ForEach(AppSection.allCases) { section in
                Text(section.title)
                    .tag(section)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .frame(width: width)
        .accessibilityLabel("Search mode")
    }

    private var favoriteTimetablesButton: some View {
        Button {
            openWindow(id: AppWindow.favoriteTimetables)
        } label: {
            Label("Favorite timetables", systemImage: "star")
                .labelStyle(.iconOnly)
        }
        .help("Favorite timetables")
    }

    private var appInformationButton: some View {
        Button {
            openWindow(id: AppWindow.information)
        } label: {
            Label("Show app and data source information", systemImage: "info.circle")
                .labelStyle(.iconOnly)
        }
        .help("Show app and data source information")
    }

    @ViewBuilder
    private var selectedContent: some View {
        switch selection {
        case .connections:
            ConnectionsView(model: connectionsModel, client: client)
        case .departures:
            DeparturesView(model: departuresModel, client: client)
        case .stationTimetables:
            StationTimetablesView(model: stationTimetablesModel, client: client)
        }
    }
}
