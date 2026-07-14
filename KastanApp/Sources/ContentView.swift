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

/// Retains independent search state while the user switches between connections and station boards.
struct ContentView: View {
    private let client: any IDOSClienting
    @StateObject private var connectionsModel: ConnectionsViewModel
    @StateObject private var departuresModel: DeparturesViewModel
    @State private var selection = AppSection.connections

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
                HStack(spacing: 8) {
                    Text("🌰")
                    Text("Powered by public IDOS web data")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.bar)
            }
            .navigationSplitViewColumnWidth(min: 190, ideal: 220)
        } detail: {
            switch selection {
            case .connections:
                ConnectionsView(model: connectionsModel, client: client)
            case .departures:
                DeparturesView(model: departuresModel, client: client)
            }
        }
    }
}
