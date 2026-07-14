import Kastan
import SwiftUI

/// Top-level product areas available from the app's persistent sidebar.
enum AppSection: String, CaseIterable, Hashable, Identifiable {
    case connections
    case departures

    var id: Self { self }

    var title: LocalizedStringKey {
        switch self {
        case .connections:
            "Connections"
        case .departures:
            "Departures"
        }
    }

    var systemImage: String {
        switch self {
        case .connections:
            "arrow.left.arrow.right"
        case .departures:
            "list.bullet.rectangle"
        }
    }
}

/// Converts the detail column's measured width into stable responsive layout decisions.
struct DetailLayout {
    private static let maximumContentWidth: CGFloat = 1100
    private static let compactPaddingBreakpoint: CGFloat = 600
    private static let stackedEndpointsBreakpoint: CGFloat = 560
    private static let stackedOptionsBreakpoint: CGFloat = 620
    private static let stackedSearchBreakpoint: CGFloat = 820

    let availableWidth: CGFloat

    var containerWidth: CGFloat {
        min(max(availableWidth, 0), Self.maximumContentWidth)
    }

    var horizontalPadding: CGFloat {
        availableWidth < Self.compactPaddingBreakpoint ? 16 : 24
    }

    var contentWidth: CGFloat {
        max(containerWidth - (2 * horizontalPadding), 0)
    }

    var usesStackedEndpoints: Bool {
        contentWidth < Self.stackedEndpointsBreakpoint
    }

    var usesStackedOptions: Bool {
        contentWidth < Self.stackedOptionsBreakpoint
    }

    var usesStackedSearchControls: Bool {
        contentWidth < Self.stackedSearchBreakpoint
    }
}

/// Retains independent search state while the user switches between connections and station boards.
struct ContentView: View {
    private let client: any IDOSClienting
    @StateObject private var connectionsModel: ConnectionsViewModel
    @StateObject private var departuresModel: DeparturesViewModel
    @State private var selection = AppSection.connections
    @State private var showsAppInformation = false

    init(client: any IDOSClienting) {
        self.client = client
        _connectionsModel = StateObject(wrappedValue: ConnectionsViewModel(client: client))
        _departuresModel = StateObject(wrappedValue: DeparturesViewModel(client: client))
    }

    var body: some View {
        NavigationSplitView {
            List(AppSection.allCases, selection: $selection) { section in
                Label(section.title, systemImage: section.systemImage)
                    .tag(section)
            }
            .navigationTitle("Kaštan")
            .safeAreaInset(edge: .bottom) {
                Button {
                    showsAppInformation = true
                } label: {
                    HStack(spacing: 8) {
                        Text("🌰")
                            .accessibilityHidden(true)
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
            }
        }
        .sheet(isPresented: $showsAppInformation) {
            AppInformationView()
        }
    }
}
