import AppKit
import SwiftUI

/// Keeps service previews large enough to show useful route context without becoming another full window.
enum ResultPreviewLayout {
    static let serviceSize = CGSize(width: 600, height: 560)
}

/// Distinguishes an independent service window from the same route embedded in a preview.
enum ResultDetailPresentation {
    case window
    case preview
}

/// Describes one visible Force Click target in window coordinates.
struct ForceClickPreviewTargetFrame: Equatable {
    let id: UUID
    let frame: CGRect
    let registrationOrder: Int
    let acceptsPressure: Bool
}

/// Chooses the smallest, most recent preview target whose visible content is beneath the pointer.
enum ForceClickPreviewTargetResolver {
    static func targetID(
        at location: CGPoint,
        in targets: [ForceClickPreviewTargetFrame]
    ) -> UUID? {
        targets
            .filter { $0.acceptsPressure && $0.frame.contains(location) && !$0.frame.isEmpty }
            .min { lhs, rhs in
                let lhsArea = lhs.frame.width * lhs.frame.height
                let rhsArea = rhs.frame.width * rhs.frame.height
                if lhsArea == rhsArea {
                    return lhs.registrationOrder > rhs.registrationOrder
                }
                return lhsArea < rhsArea
            }?
            .id
    }
}

/// Coordinates native pressure events across overlapping SwiftUI result rows without intercepting normal clicks.
@MainActor
private final class ForceClickPreviewMonitor {
    static let shared = ForceClickPreviewMonitor()

    private struct Target {
        weak var attachmentView: NSView?
        let registrationOrder: Int
        var acceptsPressure: @MainActor () -> Bool
        var showPreview: @MainActor () -> Void
        var pressureEnded: @MainActor () -> Void
    }

    private let pressureConfiguration = NSPressureConfiguration(
        pressureBehavior: .primaryDeepClick
    )
    private var targets: [UUID: Target] = [:]
    private var nextRegistrationOrder = 0
    private var eventMonitor: Any?
    private var triggeredTargetID: UUID?

    func register(
        id: UUID,
        attachmentView: NSView,
        acceptsPressure: @escaping @MainActor () -> Bool,
        showPreview: @escaping @MainActor () -> Void,
        pressureEnded: @escaping @MainActor () -> Void
    ) {
        let registrationOrder: Int
        if let current = targets[id] {
            registrationOrder = current.registrationOrder
        } else {
            registrationOrder = nextRegistrationOrder
            nextRegistrationOrder += 1
        }
        targets[id] = Target(
            attachmentView: attachmentView,
            registrationOrder: registrationOrder,
            acceptsPressure: acceptsPressure,
            showPreview: showPreview,
            pressureEnded: pressureEnded
        )
        installEventMonitorIfNeeded()
    }

    func unregister(id: UUID) {
        targets.removeValue(forKey: id)
        if targets.isEmpty, let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
            self.eventMonitor = nil
            triggeredTargetID = nil
        }
    }

    private func installEventMonitorIfNeeded() {
        guard eventMonitor == nil else { return }
        eventMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .leftMouseUp, .pressure]
        ) { [weak self] event in
            self?.handle(event)
            return event
        }
    }

    private func handle(_ event: NSEvent) {
        switch event.type {
        case .leftMouseDown:
            triggeredTargetID = nil
            if targetID(for: event) != nil {
                pressureConfiguration.set()
            }
        case .pressure:
            guard event.stage >= 2,
                  triggeredTargetID == nil,
                  let targetID = targetID(for: event),
                  let target = targets[targetID]
            else { return }

            triggeredTargetID = targetID
            target.showPreview()
        case .leftMouseUp:
            guard let targetID = triggeredTargetID else { return }
            let target = targets[targetID]
            triggeredTargetID = nil
            // The underlying Button handles this mouse-up first and consumes its normal action.
            DispatchQueue.main.async {
                target?.pressureEnded()
            }
        default:
            break
        }
    }

    private func targetID(for event: NSEvent) -> UUID? {
        guard let eventWindow = event.window else { return nil }
        let frames = targets.compactMap { id, target -> ForceClickPreviewTargetFrame? in
            guard let view = target.attachmentView,
                  view.window === eventWindow,
                  !view.isHidden,
                  !view.visibleRect.isEmpty
            else { return nil }

            return ForceClickPreviewTargetFrame(
                id: id,
                frame: view.convert(view.visibleRect, to: nil),
                registrationOrder: target.registrationOrder,
                acceptsPressure: target.acceptsPressure()
            )
        }
        return ForceClickPreviewTargetResolver.targetID(
            at: event.locationInWindow,
            in: frames
        )
    }
}

/// Registers a geometry-only SwiftUI background with the shared native pressure monitor.
final class ForceClickPreviewAttachmentView: NSView {}

private struct ForceClickPreviewAttachment: NSViewRepresentable {
    let acceptsPressure: @MainActor () -> Bool
    let showPreview: @MainActor () -> Void
    let pressureEnded: @MainActor () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        let view = ForceClickPreviewAttachmentView()
        ForceClickPreviewMonitor.shared.register(
            id: context.coordinator.id,
            attachmentView: view,
            acceptsPressure: acceptsPressure,
            showPreview: showPreview,
            pressureEnded: pressureEnded
        )
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        ForceClickPreviewMonitor.shared.register(
            id: context.coordinator.id,
            attachmentView: view,
            acceptsPressure: acceptsPressure,
            showPreview: showPreview,
            pressureEnded: pressureEnded
        )
    }

    static func dismantleNSView(_ view: NSView, coordinator: Coordinator) {
        ForceClickPreviewMonitor.shared.unregister(id: coordinator.id)
    }

    final class Coordinator {
        let id = UUID()
    }
}

/// Presents complete result content only while its visible row is hovered, preserving ordinary row actions.
private struct ForceClickPreviewModifier<Preview: View>: ViewModifier {
    let size: CGSize
    let isEnabled: Bool
    let suppressesPrimaryAction: Binding<Bool>?
    @Binding var isPreviewPresented: Bool
    @ViewBuilder let preview: () -> Preview
    @State private var isHovered = false

    func body(content: Content) -> some View {
        content
            .onHover { isHovered = $0 }
            .background {
                ForceClickPreviewAttachment(
                    acceptsPressure: { isEnabled && isHovered },
                    showPreview: {
                        suppressesPrimaryAction?.wrappedValue = true
                        isPreviewPresented = true
                    },
                    pressureEnded: {
                        suppressesPrimaryAction?.wrappedValue = false
                    }
                )
            }
            .popover(isPresented: $isPreviewPresented, arrowEdge: .trailing) {
                preview()
                    .frame(width: size.width, height: size.height)
            }
    }
}

extension View {
    /// Adds the standard result preview without changing the view's normal click behavior.
    func forceClickPreview<Preview: View>(
        size: CGSize,
        isEnabled: Bool = true,
        suppressesPrimaryAction: Binding<Bool>? = nil,
        isPresented: Binding<Bool>,
        @ViewBuilder preview: @escaping () -> Preview
    ) -> some View {
        modifier(ForceClickPreviewModifier(
            size: size,
            isEnabled: isEnabled,
            suppressesPrimaryAction: suppressesPrimaryAction,
            isPreviewPresented: isPresented,
            preview: preview
        ))
    }
}
