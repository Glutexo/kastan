import CoreTransferable
import SwiftUI
import UniformTypeIdentifiers

/// Identifies the passenger result whose contextual actions must stay under the pointer.
enum ResultContextTarget: CaseIterable {
    case connection
    case service

    var openInNewWindowTitleKey: String {
        switch self {
        case .connection:
            "Open connection in new window"
        case .service:
            "Open service in new window"
        }
    }
}

/// Defines stable contextual-menu contents independently of the visible ellipsis or right-click gesture.
enum ResultContextAction: Hashable, Identifiable {
    case preview
    case openInNewWindow
    case separator
    case detail(ResultDetailAction)

    var id: Self { self }

    /// Services retain a compact preview and expose every detail action once their complete route has loaded.
    static func availableActions(
        for target: ResultContextTarget,
        hasPermanentLink: Bool = false
    ) -> [Self] {
        let navigation: [Self]
        let details: [ResultDetailAction]

        switch target {
        case .connection:
            navigation = [.openInNewWindow]
            details = ResultDetailAction.availableActions(hasPermanentLink: hasPermanentLink)
        case .service:
            navigation = [.preview, .openInNewWindow]
            details = ResultDetailAction.allCases
        }

        return navigation + [.separator] + details.map(Self.detail)
    }
}

/// Supplies the result-specific wording and stable symbols shared by every contextual menu.
private struct ResultContextActionLabel: View {
    let action: ResultContextAction
    let target: ResultContextTarget

    @ViewBuilder
    var body: some View {
        switch action {
        case .preview:
            Label("Preview service", systemImage: "eye")
        case .openInNewWindow:
            Label(LocalizedStringKey(target.openInNewWindowTitleKey), systemImage: "macwindow")
        case .detail(let action):
            Label(action.title, systemImage: action.systemImage)
        case .separator:
            EmptyView()
        }
    }
}

/// Renders the complete connection action set in both its ellipsis and whole-card context menus.
struct ConnectionContextMenuContent: View {
    let permanentLink: URL?
    let isPerformingExport: Bool
    let openInNewWindow: () -> Void
    let copyToClipboard: () -> Void
    let addToCalendar: () -> Void
    let saveAsPDF: () -> Void

    var body: some View {
        ForEach(
            ResultContextAction.availableActions(
                for: .connection,
                hasPermanentLink: permanentLink != nil
            )
        ) { action in
            control(action)
        }
    }

    @ViewBuilder
    private func control(_ action: ResultContextAction) -> some View {
        switch action {
        case .preview:
            EmptyView()
        case .openInNewWindow:
            Button(action: openInNewWindow) {
                ResultContextActionLabel(action: action, target: .connection)
            }
        case .separator:
            Divider()
        case .detail(.copyToClipboard):
            Button(action: copyToClipboard) {
                ResultContextActionLabel(action: action, target: .connection)
            }
            .disabled(isPerformingExport)
        case .detail(.addToCalendar):
            Button(action: addToCalendar) {
                ResultContextActionLabel(action: action, target: .connection)
            }
            .disabled(isPerformingExport)
        case .detail(.saveAsPDF):
            Button(action: saveAsPDF) {
                ResultContextActionLabel(action: action, target: .connection)
            }
            .disabled(isPerformingExport)
        case .detail(.shareLink):
            if let permanentLink {
                ShareLink(item: permanentLink) {
                    ResultContextActionLabel(action: action, target: .connection)
                }
                .disabled(isPerformingExport)
            }
        case .detail(.openInIDOS):
            if let permanentLink {
                Link(destination: permanentLink) {
                    ResultContextActionLabel(action: action, target: .connection)
                }
                .disabled(isPerformingExport)
            }
        }
    }
}

/// Gives the system share picker a URL item immediately while resolving the service link only if sharing is chosen.
struct DeferredServicePermanentLink: Transferable {
    let model: ServiceDetailViewModel

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .url) { item in
            try await item.exportedData()
        }
    }

    /// Encodes the same localized permanent URL that the loaded service toolbar shares directly.
    func exportedData() async throws -> Data {
        guard let url = await model.localizedPermanentLink() else {
            throw ExportError.unavailable
        }
        return Data(url.absoluteString.utf8)
    }

    private enum ExportError: Error {
        case unavailable
    }
}

/// Keeps a service row's complete action set from falling through to its enclosing connection menu.
struct ServiceContextMenuContent: View {
    @Environment(\.openURL) private var openURL
    @ObservedObject var model: ServiceDetailViewModel
    let showPreview: () -> Void
    let openInNewWindow: () -> Void

    var body: some View {
        ForEach(ResultContextAction.availableActions(for: .service)) { action in
            control(action)
        }
    }

    /// Keeps first-open actions selectable; the chosen action performs the shared lazy detail load itself.
    var detailActionsAreDisabled: Bool {
        model.isPerformingExport
    }

    @ViewBuilder
    private func control(_ action: ResultContextAction) -> some View {
        switch action {
        case .preview:
            Button(action: showPreview) {
                ResultContextActionLabel(action: action, target: .service)
            }
        case .openInNewWindow:
            Button(action: openInNewWindow) {
                ResultContextActionLabel(action: action, target: .service)
            }
        case .separator:
            Divider()
        case .detail(.copyToClipboard):
            Button {
                Task {
                    if let service = await model.loadedService() {
                        ResultClipboard.copy(service: service)
                    }
                }
            } label: {
                ResultContextActionLabel(action: action, target: .service)
            }
            .disabled(detailActionsAreDisabled)
        case .detail(.addToCalendar):
            Button {
                Task { await model.addToCalendar() }
            } label: {
                ResultContextActionLabel(action: action, target: .service)
            }
            .disabled(detailActionsAreDisabled)
        case .detail(.saveAsPDF):
            Button {
                Task { await model.saveAsPDF() }
            } label: {
                ResultContextActionLabel(action: action, target: .service)
            }
            .disabled(detailActionsAreDisabled)
        case .detail(.shareLink):
            ShareLink(
                item: DeferredServicePermanentLink(model: model),
                preview: SharePreview("Share Link")
            ) {
                ResultContextActionLabel(action: action, target: .service)
            }
            .disabled(detailActionsAreDisabled)
        case .detail(.openInIDOS):
            Button {
                Task {
                    if let permanentLink = await model.localizedPermanentLink() {
                        openURL(permanentLink)
                    }
                }
            } label: {
                ResultContextActionLabel(action: action, target: .service)
            }
            .disabled(detailActionsAreDisabled)
        }
    }
}
