import Kastan
import SwiftUI

/// Launches the native Kaštan experience while sharing all IDOS behavior with the CLI and MCP server.
@main
struct KastanApp: App {
    private let client = IDOSClient()

    var body: some Scene {
        WindowGroup {
            ContentView(client: client)
                .frame(minWidth: 720, minHeight: 520)
        }
        .defaultSize(width: 1080, height: 720)
        .commands {
            SidebarCommands()
        }
    }
}
