import Kastan
import SwiftUI

/// Launches the native Kaštan experience while sharing all IDOS behavior with the CLI and MCP server.
@main
struct KastanApp: App {
    private let client = IDOSClient()

    var body: some Scene {
        WindowGroup {
            ContentView(client: client)
                .frame(minWidth: 1000, minHeight: 620)
        }
        .defaultSize(width: 1180, height: 760)
        .commands {
            SidebarCommands()
        }
    }
}
