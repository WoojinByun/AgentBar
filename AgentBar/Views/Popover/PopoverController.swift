import Cocoa
import SwiftUI

@MainActor
final class PopoverController {
    static let shared = PopoverController()

    private var popover: NSPopover?
    private var isShown = false
    private var outsideClickMonitor: Any?
    private var resignActiveObserver: NSObjectProtocol?

    private init() {}

    func toggle(relativeTo button: NSButton, viewModel: UsageViewModel) {
        if isShown {
            hide()
        } else {
            show(relativeTo: button, viewModel: viewModel)
        }
    }

    func show(relativeTo button: NSButton, viewModel: UsageViewModel) {
        let popover = NSPopover()
        popover.contentSize = NSSize(width: 320, height: 350)
        popover.behavior = .transient
        popover.animates = true
        popover.contentViewController = NSHostingController(
            rootView: DetailPopoverView(viewModel: viewModel)
        )
        popover.delegate = PopoverDelegateHandler.shared
        // An accessory app is not active when the status item is clicked, so
        // `.transient` alone never sees outside clicks. Activate first.
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
        self.popover = popover
        isShown = true
        installDismissMonitors()

        // Clear first responder so no button shows a focus ring on open.
        DispatchQueue.main.async {
            popover.contentViewController?.view.window?.makeFirstResponder(nil)
        }
    }

    func hide() {
        removeDismissMonitors()
        popover?.performClose(nil)
        popover = nil
        isShown = false
    }

    /// Ignores close notifications from a popover that was already replaced.
    fileprivate func popoverDidClose(_ closedID: ObjectIdentifier?) {
        guard let popover, closedID == nil || closedID == ObjectIdentifier(popover) else { return }
        hide()
    }

    /// Closes the popover on clicks in other apps or when AgentBar loses focus.
    private func installDismissMonitors() {
        removeDismissMonitors()
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { _ in
            Task { @MainActor in
                PopoverController.shared.hide()
            }
        }
        resignActiveObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in
                PopoverController.shared.hide()
            }
        }
    }

    private func removeDismissMonitors() {
        if let outsideClickMonitor {
            NSEvent.removeMonitor(outsideClickMonitor)
            self.outsideClickMonitor = nil
        }
        if let resignActiveObserver {
            NotificationCenter.default.removeObserver(resignActiveObserver)
            self.resignActiveObserver = nil
        }
    }
}

// Simple delegate to track popover closure
@MainActor
private final class PopoverDelegateHandler: NSObject, NSPopoverDelegate {
    static let shared = PopoverDelegateHandler()

    nonisolated func popoverDidClose(_ notification: Notification) {
        let closedID = (notification.object as AnyObject?).map(ObjectIdentifier.init)
        Task { @MainActor in
            PopoverController.shared.popoverDidClose(closedID)
        }
    }
}
