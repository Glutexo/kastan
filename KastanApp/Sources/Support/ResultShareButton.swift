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

    /// Makes portable text the visible action when the result has no permanent provider link.
    static func primary(hasLink: Bool, hasText: Bool) -> Self {
        hasLink || !hasText ? .link : .text
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

/// Shares either a provider-supplied result link or its complete localized plain-text representation.
struct ResultShareButton<Label: View>: View {
    let placement: OptionAlternateButtonPlacement
    private let link: URL?
    private let text: String?
    private let resolveLink: (@MainActor () async -> URL?)?
    private let resolveText: (@MainActor () async -> String?)?
    private let primaryAction: ResultSharingAction
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
        primaryAction = .primary(
            hasLink: link != nil,
            hasText: text?.isEmpty == false
        )
        self.offersTextAlternate = offersTextAlternate && primaryAction == .link
        self.label = label
    }

    /// Resolves a service representation only after the passenger activates its sharing action.
    init(
        placement: OptionAlternateButtonPlacement,
        offersLink: Bool = true,
        resolvingLink resolveLink: @escaping @MainActor () async -> URL?,
        resolvingText resolveText: @escaping @MainActor () async -> String?,
        @ViewBuilder label: @escaping (ResultSharingAction) -> Label
    ) {
        self.placement = placement
        link = nil
        text = nil
        self.resolveLink = resolveLink
        self.resolveText = resolveText
        primaryAction = offersLink ? .link : .text
        offersTextAlternate = offersLink
        self.label = label
    }

    @ViewBuilder
    var body: some View {
        if offersTextAlternate {
            OptionAlternateButton(
                placement: placement,
                primaryAction: primaryAction,
                alternateAction: .text,
                title: \.title,
                isEnabled: isAvailable,
                perform: present,
                label: label
            )
        } else {
            Button {
                present(primaryAction)
            } label: {
                label(primaryAction)
            }
            .accessibilityLabel(primaryAction.title)
            .help(primaryAction.title)
            .disabled(!isAvailable(primaryAction))
        }
    }

    /// Keeps a text alternate usable even when the data source omitted a permanent link.
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

/// Presents result content through macOS and adds direct link opening only when the shared item is a URL.
@MainActor
final class ResultSharingServicePickerPresenter: NSObject, @preconcurrency NSSharingServicePickerDelegate {
    static let shared = ResultSharingServicePickerPresenter()

    private let openURL: @MainActor (URL) -> Void
    private let activeSourceView: @MainActor () -> NSView?
    private let presentPicker: @MainActor (NSSharingServicePicker, NSRect, NSView) -> Void
    private var activePicker: NSSharingServicePicker?

    init(
        openURL: @escaping @MainActor (URL) -> Void = { url in
            _ = NSWorkspace.shared.open(url)
        },
        activeSourceView: @escaping @MainActor () -> NSView? = {
            (NSApplication.shared.keyWindow ?? NSApplication.shared.mainWindow)?.contentView
        },
        presentPicker: @escaping @MainActor (NSSharingServicePicker, NSRect, NSView) -> Void = {
            picker,
            anchorRect,
            sourceView in
            picker.show(relativeTo: anchorRect, of: sourceView, preferredEdge: .minY)
        }
    ) {
        self.openURL = openURL
        self.activeSourceView = activeSourceView
        self.presentPicker = presentPicker
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
        guard let sourceView = activeSourceView() else { return }
        let anchorRect = Self.anchorRect(in: sourceView)

        // A contextual or application menu is still tracking while it invokes its action. AppKit ignores a
        // sharing picker opened in that callback, so wait until the menu has finished dismissing itself.
        DispatchQueue.main.async { [weak self, weak sourceView] in
            guard let self, let sourceView, sourceView.window != nil else { return }

            self.activePicker?.close()

            let picker = NSSharingServicePicker(items: items)
            picker.delegate = self
            self.activePicker = picker
            self.presentPicker(picker, anchorRect, sourceView)
        }
    }

    func sharingServicePicker(
        _ sharingServicePicker: NSSharingServicePicker,
        sharingServicesForItems items: [Any],
        proposedSharingServices proposedServices: [NSSharingService]
    ) -> [NSSharingService] {
        guard let url = items.lazy.compactMap(Self.url(from:)).first else {
            return proposedServices
        }

        return proposedServices + [openLinkService(for: url)]
    }

    func sharingServicePicker(
        _ sharingServicePicker: NSSharingServicePicker,
        didChoose service: NSSharingService?
    ) {
        guard activePicker === sharingServicePicker else { return }
        activePicker = nil
    }

    /// Creates a regular sharing-service row so direct opening remains visually consistent with macOS services.
    private func openLinkService(for url: URL) -> NSSharingService {
        let title = AppLocalization.string("Open Link")
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
