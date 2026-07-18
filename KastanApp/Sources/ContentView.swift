import Kastan
import SwiftUI

/// The three equivalent IDOS search modes available from the main window toolbar.
enum AppSection: String, CaseIterable, Hashable, Identifiable {
    case connections
    case departures
    case stationTimetables

    var id: Self { self }

    var localizationKey: String {
        switch self {
        case .connections:
            "Connections"
        case .departures:
            "Departures"
        case .stationTimetables:
            "Station timetables"
        }
    }

    var title: LocalizedStringKey {
        LocalizedStringKey(localizationKey)
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
    @State private var viewportHeight: CGFloat = 0

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
                    SearchResultPullMonitor(
                        canLoadEarlier: canLoadEarlier,
                        canLoadLater: canLoadLater,
                        isLoadingEarlier: isLoadingEarlier,
                        isLoadingLater: isLoadingLater,
                        load: requestPage
                    )
                }
            }
            .background {
                GeometryReader { geometry in
                    Color.clear.preference(
                        key: SearchResultViewportHeightPreferenceKey.self,
                        value: geometry.size.height
                    )
                }
            }
            .onPreferenceChange(SearchResultViewportHeightPreferenceKey.self) { height in
                viewportHeight = height
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private func requestPage(_ edge: SearchResultPagingEdge) {
        switch edge {
        case .earlier:
            guard let loadEarlier else { return }
            Task { @MainActor in await loadEarlier() }
        case .later:
            guard let loadLater else { return }
            Task { @MainActor in await loadLater() }
        }
    }
}

/// Retains independent search state while the native toolbar switches among all three IDOS search modes.
struct ContentView: View {
    /// Supplies the native toolbar with a localized width that still fits compact windows.
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
        selectedContent
            .background {
                MainWindowToolbarInstaller(
                    selection: $selection,
                    openFavoriteTimetables: { openWindow(id: AppWindow.favoriteTimetables) },
                    openAppInformation: { openWindow(id: AppWindow.information) }
                )
            }
            .focusedSceneValue(\.appSectionSelection, $selection)
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
