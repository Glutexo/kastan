import AppKit
import SwiftUI

/// Defines which portable representation the passenger sends from Kaštan's single sharing action.
enum ResultSharingAction: CaseIterable, Hashable {
    case link
    case text

    /// Chooses text only for an intentional Option-modified activation.
    static func preferred(for modifierFlags: NSEvent.ModifierFlags) -> Self {
        modifierFlags.contains(.option) ? .text : .link
    }

    var title: LocalizedStringKey {
        switch self {
        case .link:
            "Share Link"
        case .text:
            "Share Text"
        }
    }

    var systemImage: String {
        switch self {
        case .link:
            "square.and.arrow.up"
        case .text:
            "doc.plaintext"
        }
    }
}

/// Shares either a permanent IDOS link or its complete localized plain-text result from one stable control.
struct ResultShareButton<Label: View>: View {
    let placement: OptionAlternateButtonPlacement
    private let link: URL?
    private let text: String?
    private let resolveLink: (@MainActor () async -> URL?)?
    private let resolveText: (@MainActor () async -> String?)?
    private let offersTextAlternate: Bool
    private let label: (ResultSharingAction) -> Label

    /// Uses immediately available result representations without delaying the native sharing picker.
    init(
        link: URL?,
        text: String?,
        placement: OptionAlternateButtonPlacement,
        offersTextAlternate: Bool = true,
        @ViewBuilder label: @escaping (ResultSharingAction) -> Label
    ) {
        self.placement = placement
        self.link = link
        self.text = text
        resolveLink = nil
        resolveText = nil
        self.offersTextAlternate = offersTextAlternate
        self.label = label
    }

    /// Resolves a service representation only after the passenger activates its sharing action.
    init(
        placement: OptionAlternateButtonPlacement,
        resolvingLink resolveLink: @escaping @MainActor () async -> URL?,
        resolvingText resolveText: @escaping @MainActor () async -> String?,
        @ViewBuilder label: @escaping (ResultSharingAction) -> Label
    ) {
        self.placement = placement
        link = nil
        text = nil
        self.resolveLink = resolveLink
        self.resolveText = resolveText
        offersTextAlternate = true
        self.label = label
    }

    @ViewBuilder
    var body: some View {
        if offersTextAlternate {
            OptionAlternateButton(
                placement: placement,
                primaryAction: ResultSharingAction.link,
                alternateAction: .text,
                title: \.title,
                isEnabled: isAvailable,
                perform: present,
                label: label
            )
        } else {
            Button {
                present(.link)
            } label: {
                label(.link)
            }
            .accessibilityLabel(ResultSharingAction.link.title)
            .help(ResultSharingAction.link.title)
            .disabled(!isAvailable(.link))
        }
    }

    /// Keeps a text alternate usable even when IDOS omitted the result's permanent link.
    private func isAvailable(_ action: ResultSharingAction) -> Bool {
        switch action {
        case .link:
            link != nil || resolveLink != nil
        case .text:
            text?.isEmpty == false || resolveText != nil
        }
    }

    private func present(_ action: ResultSharingAction) {
        switch action {
        case .link:
            if let link {
                ResultSharingServicePickerPresenter.shared.show(link: link)
            } else if let resolveLink {
                Task { @MainActor in
                    if let link = await resolveLink() {
                        ResultSharingServicePickerPresenter.shared.show(link: link)
                    }
                }
            }
        case .text:
            if let text, !text.isEmpty {
                ResultSharingServicePickerPresenter.shared.show(text: text)
            } else if let resolveText {
                Task { @MainActor in
                    if let text = await resolveText(), !text.isEmpty {
                        ResultSharingServicePickerPresenter.shared.show(text: text)
                    }
                }
            }
        }
    }
}

/// Presents result content through macOS and adds direct IDOS opening only when the shared item is a URL.
@MainActor
final class ResultSharingServicePickerPresenter: NSObject, @preconcurrency NSSharingServicePickerDelegate {
    static let shared = ResultSharingServicePickerPresenter()

    private let openURL: @MainActor (URL) -> Void
    private var activePicker: NSSharingServicePicker?

    init(openURL: @escaping @MainActor (URL) -> Void = { url in
        _ = NSWorkspace.shared.open(url)
    }) {
        self.openURL = openURL
        super.init()
    }

    func show(link: URL) {
        show(items: [link])
    }

    func show(text: String) {
        guard !text.isEmpty else { return }
        show(items: [text])
    }

    /// Anchors every toolbar, menu, and contextual presentation to the active result window.
    private func show(items: [Any]) {
        guard let sourceView = (NSApplication.shared.keyWindow ?? NSApplication.shared.mainWindow)?.contentView
        else { return }

        activePicker?.close()

        let picker = NSSharingServicePicker(items: items)
        picker.delegate = self
        activePicker = picker
        picker.show(
            relativeTo: Self.anchorRect(in: sourceView),
            of: sourceView,
            preferredEdge: .minY
        )
    }

    func sharingServicePicker(
        _ sharingServicePicker: NSSharingServicePicker,
        sharingServicesForItems items: [Any],
        proposedSharingServices proposedServices: [NSSharingService]
    ) -> [NSSharingService] {
        guard let url = items.lazy.compactMap(Self.url(from:)).first else {
            return proposedServices
        }

        return proposedServices + [openInIDOSService(for: url)]
    }

    func sharingServicePicker(
        _ sharingServicePicker: NSSharingServicePicker,
        didChoose service: NSSharingService?
    ) {
        guard activePicker === sharingServicePicker else { return }
        activePicker = nil
    }

    /// Creates a regular sharing-service row so direct opening remains visually consistent with macOS services.
    private func openInIDOSService(for url: URL) -> NSSharingService {
        let title = AppLocalization.string("Open in IDOS")
        let image = NSImage(
            systemSymbolName: "arrow.up.right.square",
            accessibilityDescription: title
        ) ?? NSImage(size: NSSize(width: 18, height: 18))
        let service = NSSharingService(
            title: title,
            image: image,
            alternateImage: nil
        ) { [openURL] in
            openURL(url)
        }
        service.menuItemTitle = title
        return service
    }

    private static func url(from item: Any) -> URL? {
        if let url = item as? URL {
            return url
        }
        return (item as? NSURL).map { $0 as URL }
    }

    /// Uses the initiating pointer position when possible and a stable top-center window anchor for keyboard commands.
    private static func anchorRect(in view: NSView) -> NSRect {
        let fallback = NSPoint(x: view.bounds.midX, y: view.bounds.maxY)
        guard let event = NSApplication.shared.currentEvent,
              event.window === view.window
        else {
            return NSRect(origin: fallback, size: NSSize(width: 1, height: 1))
        }

        let location = view.convert(event.locationInWindow, from: nil)
        let point = NSPoint(
            x: min(max(location.x, view.bounds.minX), view.bounds.maxX),
            y: min(max(location.y, view.bounds.minY), view.bounds.maxY)
        )
        return NSRect(origin: point, size: NSSize(width: 1, height: 1))
    }
}
