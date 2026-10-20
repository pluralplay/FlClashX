import Cocoa

/// The Flutter view moved out of its window into a popover under a status
/// item, the way menu bar utilities present themselves.
final class MenuBarPopover: NSObject, NSPopoverDelegate {
    static let contentSize = NSSize(width: 420, height: 720)

    var onShown: (() -> Void)?
    var onClosed: (() -> Void)?

    private let popover = NSPopover()
    private let container = NSViewController()
    private var content: NSViewController?
    private var shownAt: Date = .distantPast
    private var reactivation: DispatchWorkItem?

    override init() {
        super.init()
        container.view = NSView(frame: NSRect(origin: .zero, size: Self.contentSize))
        popover.contentViewController = container
        popover.contentSize = Self.contentSize
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
    }

    var isShown: Bool { popover.isShown }

    /// Takes [content] over from its window; `release` gives it back.
    func adopt(_ content: NSViewController) {
        self.content = content
        container.addChild(content)
        content.view.frame = container.view.bounds
        content.view.autoresizingMask = [.width, .height]
        container.view.addSubview(content.view)
    }

    func release() -> NSViewController? {
        guard let content else { return nil }
        close()
        content.view.removeFromSuperview()
        content.removeFromParent()
        self.content = nil
        return content
    }

    func show(relativeTo anchor: NSView) {
        if popover.isShown { return }
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .maxY)
        popover.contentViewController?.view.window?.makeKey()
        shownAt = Date()
    }

    func close() {
        reactivation?.cancel()
        reactivation = nil
        if popover.isShown {
            popover.performClose(nil)
        }
    }

    // A Dock reopen activates an accessory app only provisionally; a click elsewhere is a mouse event.
    func popoverShouldClose(_ popover: NSPopover) -> Bool {
        let event = NSApp.currentEvent
        let deactivated = event?.type == .appKitDefined
            && event?.subtype == .applicationDeactivated
        guard deactivated, Date().timeIntervalSince(shownAt) < 1 else { return true }
        reactivate(attempt: 0)
        return false
    }

    private func reactivate(attempt: Int) {
        reactivation?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.popover.isShown else { return }
            NSApp.activate(ignoringOtherApps: true)
            self.popover.contentViewController?.view.window?.makeKey()
            if attempt < 3 {
                self.reactivate(attempt: attempt + 1)
            }
        }
        reactivation = work
        DispatchQueue.main.asyncAfter(deadline: .now() + (attempt == 0 ? 0.15 : 0.3), execute: work)
    }

    func popoverDidShow(_ notification: Notification) {
        onShown?()
    }

    func popoverDidClose(_ notification: Notification) {
        reactivation?.cancel()
        reactivation = nil
        onClosed?()
    }
}
