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
            details = ResultDetailAction.availableActions(
                hasPermanentLink: hasPermanentLink,
                canSendByEmail: true
            )
        case .service:
            navigation = [.preview, .openInNewWindow]
            details = ResultDetailAction.availableActions(
                hasPermanentLink: true,
                canSendByEmail: false
            )
        }

        return navigation + [.separator] + details.map(Self.detail)
    }
}

/// Supplies the result-specific wording and stable symbols shared by every contextual menu.
private struct ResultContextActionLabel: View {
    let action: ResultContextAction
    let target: ResultContextTarget
    let calendarExportAction: CalendarExportAction
    let pdfExportAction: PDFExportAction

    init(
        action: ResultContextAction,
        target: ResultContextTarget,
        calendarExportAction: CalendarExportAction = .addToCalendar,
        pdfExportAction: PDFExportAction = .openInPreview
    ) {
        self.action = action
        self.target = target
        self.calendarExportAction = calendarExportAction
        self.pdfExportAction = pdfExportAction
    }

    @ViewBuilder
    var body: some View {
        switch action {
        case .preview:
            Label("Preview service", systemImage: "eye")
        case .openInNewWindow:
            Label(LocalizedStringKey(target.openInNewWindowTitleKey), systemImage: "macwindow")
        case .detail(let action):
            Label(
                action.title(
                    calendarExportAction: calendarExportAction,
                    pdfExportAction: pdfExportAction
                ),
                systemImage: action.systemImage(
                    calendarExportAction: calendarExportAction,
                    pdfExportAction: pdfExportAction
                )
            )
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
    let sendByEmail: () -> Void
    let performCalendarAction: (CalendarExportAction) -> Void
    let performPDFAction: (PDFExportAction) -> Void

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
        case .detail(.sendByEmail):
            Button(action: sendByEmail) {
                ResultContextActionLabel(action: action, target: .connection)
            }
            .disabled(isPerformingExport)
        case .detail(.addToCalendar):
            CalendarExportButton(
                placement: .menu,
                perform: performCalendarAction
            ) { calendarExportAction in
                ResultContextActionLabel(
                    action: action,
                    target: .connection,
                    calendarExportAction: calendarExportAction
                )
            }
            .disabled(isPerformingExport)
        case .detail(.openPDF):
            PDFExportButton(
                placement: .menu,
                perform: performPDFAction
            ) { pdfExportAction in
                ResultContextActionLabel(
                    action: action,
                    target: .connection,
                    pdfExportAction: pdfExportAction
                )
            }
            .disabled(isPerformingExport)
        case .detail(.shareLink):
            if let permanentLink {
                IDOSShareLink(item: permanentLink) {
                    ResultContextActionLabel(action: action, target: .connection)
                }
                .disabled(isPerformingExport)
            }
        }
    }
}

/// Keeps a service row's complete action set from falling through to its enclosing connection menu.
struct ServiceContextMenuContent: View {
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
        case .detail(.sendByEmail):
            EmptyView()
        case .detail(.addToCalendar):
            CalendarExportButton(placement: .menu) { calendarExportAction in
                Task { await model.performCalendarAction(calendarExportAction) }
            } label: { calendarExportAction in
                ResultContextActionLabel(
                    action: action,
                    target: .service,
                    calendarExportAction: calendarExportAction
                )
            }
            .disabled(detailActionsAreDisabled)
        case .detail(.openPDF):
            PDFExportButton(placement: .menu) { pdfExportAction in
                Task { await model.performPDFAction(pdfExportAction) }
            } label: { pdfExportAction in
                ResultContextActionLabel(
                    action: action,
                    target: .service,
                    pdfExportAction: pdfExportAction
                )
            }
            .disabled(detailActionsAreDisabled)
        case .detail(.shareLink):
            IDOSShareLink(resolving: model.localizedPermanentLink) {
                ResultContextActionLabel(action: action, target: .service)
            }
            .disabled(detailActionsAreDisabled)
        }
    }
}
