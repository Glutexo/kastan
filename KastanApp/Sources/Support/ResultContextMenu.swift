import SwiftUI

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

    /// Services retain a compact preview, while complete connections open directly in a full window with export actions.
    static func availableActions(
        for target: ResultContextTarget,
        hasPermanentLink: Bool = false
    ) -> [Self] {
        guard target == .connection else {
            return [.preview, .openInNewWindow]
        }

        return [.openInNewWindow, .separator] + ResultDetailAction
            .availableActions(hasPermanentLink: hasPermanentLink)
            .map(Self.detail)
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

/// Keeps a service row's own navigation from falling through to its enclosing connection menu.
struct ServiceContextMenuContent: View {
    let showPreview: () -> Void
    let openInNewWindow: () -> Void

    var body: some View {
        ForEach(ResultContextAction.availableActions(for: .service)) { action in
            switch action {
            case .preview:
                Button(action: showPreview) {
                    ResultContextActionLabel(action: action, target: .service)
                }
            case .openInNewWindow:
                Button(action: openInNewWindow) {
                    ResultContextActionLabel(action: action, target: .service)
                }
            case .separator, .detail:
                EmptyView()
            }
        }
    }
}
