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
        .onAppear {
            Task {
                await model.load()
            }
        }
    }

    private var permanentLink: URL? {
        model.service?.shareURL.flatMap(AppLanguagePreference.localizedIDOSURL)
    }

    private var detailActionIsDisabled: Bool {
        model.service == nil || model.isPerformingExport
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
                if let service = model.service {
                    ResultClipboard.copy(service: service)
                }
            } label: {
                ResultContextActionLabel(action: action, target: .service)
            }
            .disabled(detailActionIsDisabled)
        case .detail(.addToCalendar):
            Button {
                Task { await model.addToCalendar() }
            } label: {
                ResultContextActionLabel(action: action, target: .service)
            }
            .disabled(detailActionIsDisabled)
        case .detail(.saveAsPDF):
            Button {
                Task { await model.saveAsPDF() }
            } label: {
                ResultContextActionLabel(action: action, target: .service)
            }
            .disabled(detailActionIsDisabled)
        case .detail(.shareLink):
            if let permanentLink {
                ShareLink(item: permanentLink) {
                    ResultContextActionLabel(action: action, target: .service)
                }
                .disabled(model.isPerformingExport)
            } else {
                unavailableControl(action)
            }
        case .detail(.openInIDOS):
            if let permanentLink {
                Button {
                    openURL(permanentLink)
                } label: {
                    ResultContextActionLabel(action: action, target: .service)
                }
                .disabled(model.isPerformingExport)
            } else {
                unavailableControl(action)
            }
        }
    }

    private func unavailableControl(_ action: ResultContextAction) -> some View {
        Button {} label: {
            ResultContextActionLabel(action: action, target: .service)
        }
        .disabled(true)
    }
}
