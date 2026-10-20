import Cocoa
import FlutterMacOS

public class TrayPlugin: NSObject, FlutterPlugin {
    /// Posted with the status item's button as the object when one appears,
    /// and with nil when it goes, for a popover to hang from.
    public static let statusButtonNotification = Notification.Name("tray.statusButton")

    /// The status item's button while one is shown.
    public private(set) static var statusButton: NSView? {
        didSet {
            NotificationCenter.default.post(name: statusButtonNotification, object: statusButton)
        }
    }

    private var channel: FlutterMethodChannel!
    private var statusItem: TrayStatusItem?
    private var menu: TrayMenu?
    private var clickActivates = false

    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: "tray", binaryMessenger: registrar.messenger)
        let instance = TrayPlugin()
        instance.channel = channel
        registrar.addMethodCallDelegate(instance, channel: channel)
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "show":
            result(show(call.arguments as? [String: Any]))
        case "setTitle":
            result(setTitle(call.arguments as? [String: Any]))
        case "hide":
            hide()
            result(true)
        case "openMenu":
            result(openMenu())
        case "setClickActivates":
            clickActivates = (call.arguments as? [String: Any])?["value"] as? Bool ?? false
            result(true)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    private func show(_ arguments: [String: Any]?) -> Bool {
        guard let arguments = arguments else {
            return false
        }

        guard let item = statusItem ?? makeStatusItem() else {
            return false
        }

        if let icon = arguments["icon"] as? [String: Any] {
            guard let image = makeImage(icon) else {
                return false
            }
            item.setImage(image, position: icon["position"] as? String ?? "leading")
        }

        item.setToolTip(arguments["toolTip"] as? String ?? "")
        item.setTitle(arguments["title"] as? String ?? "")

        if let items = arguments["menu"] as? [[String: Any]] {
            menu = TrayMenu(
                items: items,
                onSelect: { [weak self] id in
                    self?.channel.invokeMethod("onMenuItemSelected", arguments: ["id": id])
                },
                onClose: { [weak self] in
                    self?.statusItem?.closeMenu()
                }
            )
        }

        return true
    }

    private func setTitle(_ arguments: [String: Any]?) -> Bool {
        guard let statusItem = statusItem else {
            return false
        }
        statusItem.setTitle(arguments?["title"] as? String ?? "")
        return true
    }

    private func hide() {
        statusItem?.remove()
        statusItem = nil
        Self.statusButton = nil
        menu = nil
    }

    private func openMenu() -> Bool {
        guard let statusItem = statusItem, let menu = menu else {
            return false
        }
        statusItem.openMenu(menu)
        return true
    }

    private func makeStatusItem() -> TrayStatusItem? {
        guard let item = TrayStatusItem(onClick: { [weak self] primary in
            guard let self else { return }
            if primary && self.clickActivates {
                self.channel.invokeMethod("onIconActivated", arguments: nil)
            } else {
                self.channel.invokeMethod("onMenuRequested", arguments: nil)
            }
        }) else {
            return nil
        }
        statusItem = item
        Self.statusButton = item.statusItem.button
        return item
    }

    private func makeImage(_ icon: [String: Any]) -> NSImage? {
        let size = icon["size"] as? Int ?? 18
        let pointSize = NSSize(width: size, height: size)
        let image = NSImage(size: pointSize)
        for rep in icon["reps"] as? [[String: Any]] ?? [] {
            guard let encoded = rep["bytes"] as? String,
                  let data = Data(base64Encoded: encoded, options: .ignoreUnknownCharacters),
                  let bitmap = NSBitmapImageRep(data: data) else {
                continue
            }
            bitmap.size = pointSize
            image.addRepresentation(bitmap)
        }
        guard !image.representations.isEmpty else {
            return nil
        }
        image.isTemplate = icon["isTemplate"] as? Bool ?? false
        return image
    }
}
