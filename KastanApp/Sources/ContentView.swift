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

/// Keeps search controls visible while giving only the result area the remaining scrollable space.
struct SearchWorkspace<SearchContent: View, ResultsContent: View>: View {
    let layout: DetailLayout
    private let searchVerticalPadding: CGFloat
    private let searchContent: SearchContent
    private let resultsContent: ResultsContent

    init(
        layout: DetailLayout,
        searchVerticalPadding: CGFloat = 18,
        @ViewBuilder searchContent: () -> SearchContent,
        @ViewBuilder resultsContent: () -> ResultsContent
    ) {
        self.layout = layout
        self.searchVerticalPadding = searchVerticalPadding
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
                resultsContent
                    .padding(.horizontal, layout.horizontalPadding)
                    .padding(.vertical, 20)
                    .frame(width: layout.containerWidth, alignment: .topLeading)
                    .frame(width: layout.availableWidth, alignment: .topLeading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}

/// Retains independent search state while the toolbar switches among all three IDOS search modes.
struct ContentView: View {
    /// Leaves room for both trailing actions at the main window's 720-point minimum width.
    private static let modePickerWidth: CGFloat = 320

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
        NavigationStack {
            selectedContent
                .navigationTitle("")
                .toolbar {
                    ToolbarItem(placement: .principal) {
                        Picker("Search mode", selection: $selection) {
                            ForEach(AppSection.allCases) { section in
                                Text(section.title)
                                    .tag(section)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .frame(width: Self.modePickerWidth)
                        .accessibilityLabel("Search mode")
                    }

                    ToolbarItemGroup(placement: .primaryAction) {
                        Button {
                            openWindow(id: AppWindow.favoriteTimetables)
                        } label: {
                            Label("Favorite timetables", systemImage: "star")
                                .labelStyle(.iconOnly)
                        }
                        .help("Favorite timetables")

                        Button {
                            openWindow(id: AppWindow.information)
                        } label: {
                            Label("Show app and data source information", systemImage: "info.circle")
                                .labelStyle(.iconOnly)
                        }
                        .help("Show app and data source information")
                    }
                }
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
