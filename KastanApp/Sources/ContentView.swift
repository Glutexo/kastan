import Kastan
import SwiftUI

/// Top-level product areas available from the app's persistent sidebar.
enum AppSection: String, CaseIterable, Hashable, Identifiable {
    case connections
    case departures
    case stationTimetables
    case favoriteTimetables

    var id: Self { self }

    var title: LocalizedStringKey {
        switch self {
        case .connections:
            "Connections"
        case .departures:
            "Departures"
        case .stationTimetables:
            "Station timetables"
        case .favoriteTimetables:
            "Timetables"
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
        case .favoriteTimetables:
            "star"
        }
    }
}

/// Groups top-level destinations into the two product areas shown in the sidebar.
enum AppSidebarGroup: CaseIterable, Identifiable {
    case searches
    case favorites

    var id: Self { self }

    var title: LocalizedStringKey {
        switch self {
        case .searches:
            "Searches"
        case .favorites:
            "Favorites"
        }
    }

    var sections: [AppSection] {
        switch self {
        case .searches:
            [.connections, .departures, .stationTimetables]
        case .favorites:
            [.favoriteTimetables]
        }
    }
}

/// Exposes the active window's sidebar selection to app-level menu commands.
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

/// Retains independent search state while the user switches between connections and station boards.
struct ContentView: View {
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
        NavigationSplitView {
            List(selection: $selection) {
                ForEach(AppSidebarGroup.allCases) { group in
                    Section {
                        ForEach(group.sections) { section in
                            Label(section.title, systemImage: section.systemImage)
                                .tag(section)
                        }
                    } header: {
                        Text(group.title)
                    }
                }
            }
            .navigationTitle("Kaštan")
            .safeAreaInset(edge: .bottom) {
                Button {
                    openWindow(id: AppWindow.information)
                } label: {
                    HStack(spacing: 8) {
                        ApplicationIcon(size: 28)
                        Text("Powered by public IDOS web data")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 4)
                        Image(systemName: "info.circle")
                            .foregroundStyle(.secondary)
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .background(.bar)
                .help("Show app and data source information")
            }
            .navigationSplitViewColumnWidth(min: 170, ideal: 210)
        } detail: {
            switch selection {
            case .connections:
                ConnectionsView(model: connectionsModel, client: client)
            case .departures:
                DeparturesView(model: departuresModel, client: client)
            case .stationTimetables:
                StationTimetablesView(model: stationTimetablesModel, client: client)
            case .favoriteTimetables:
                FavoriteTimetablesView()
            }
        }
        .focusedSceneValue(\.appSectionSelection, $selection)
    }
}
