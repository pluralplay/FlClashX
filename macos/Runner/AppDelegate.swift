import Cocoa
import FlutterMacOS
import window_ext
import LaunchAtLogin

@main
class AppDelegate: FlutterAppDelegate {
    var statusBarController: StatusBarController?
    
    var flutterUIPopover = NSPopover.init()
    
    override init() {
        super.init()
        flutterUIPopover.behavior = NSPopover.Behavior.transient
    }
    
    override func applicationDidFinishLaunching(_ aNotification: Notification) {
        NSLog("AppDelegate: applicationDidFinishLaunching called")
        
        setupCoreInApplicationSupport()
        
        
        guard let mainController = mainFlutterWindow?.contentViewController as? FlutterViewController else {
            NSLog("ERROR: Could not get FlutterViewController from mainFlutterWindow")
            return
        }
        
        
        let popoverContainer = PopoverContainerViewController(flutterViewController: mainController)
        
        flutterUIPopover.contentSize = NSSize(width: 375, height: 600)
        
        flutterUIPopover.contentViewController = popoverContainer
        
        statusBarController = StatusBarController.init(flutterUIPopover)
        
        setupStatusBarChannel(flutterViewController: mainController)
        
        super.applicationDidFinishLaunching(aNotification)
        
        mainFlutterWindow?.close()
    }
    
    func setupStatusBarChannel(flutterViewController: FlutterViewController) {
        let channel = FlutterMethodChannel(
            name: "status_bar_icon",
            binaryMessenger: flutterViewController.engine.binaryMessenger
        )
        
        channel.setMethodCallHandler { [weak self] (call: FlutterMethodCall, result: @escaping FlutterResult) in
            switch call.method {
            case "updateIcon":
                if let args = call.arguments as? [String: Any],
                   let isConnected = args["isConnected"] as? Bool {
                    self?.statusBarController?.updateIcon(isVpnConnected: isConnected)
                    result(true)
                } else {
                    result(FlutterError(code: "INVALID_ARGS", message: "Invalid arguments", details: nil))
                }
            default:
                result(FlutterMethodNotImplemented)
            }
        }
        
        NSLog("StatusBar channel set up successfully")
    }
    
    func setupCoreInApplicationSupport() {
        guard let appSupportURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            print("ERROR: Could not get Application Support directory")
            return
        }
        
        let bundleURL = Bundle.main.bundleURL
        let bundleCorePath = bundleURL.appendingPathComponent("Contents/MacOS/FlClashCore")
        let appSupportCorePath = appSupportURL.appendingPathComponent("com.follow.clash/cores/FlClashCore")
        let appSupportDir = appSupportCorePath.deletingLastPathComponent()
        
        do {
            try FileManager.default.createDirectory(at: appSupportDir, withIntermediateDirectories: true)
            print("Directory created: \(appSupportDir.path)")
            
            let coreExists = FileManager.default.fileExists(atPath: appSupportCorePath.path)
            let needsUpdate = !coreExists || shouldUpdateCore(bundlePath: bundleCorePath.path, appSupportPath: appSupportCorePath.path)
            
            if needsUpdate {
                try? FileManager.default.removeItem(at: appSupportCorePath)
                
                try FileManager.default.copyItem(at: bundleCorePath, to: appSupportCorePath)
                
                if setCorePermissions(corePath: appSupportCorePath.path) {
                    print("FlClashCore updated to: \(appSupportCorePath.path)")
                }
            } else {
                let attrs = try? FileManager.default.attributesOfItem(atPath: appSupportCorePath.path)
                if let posixPerms = attrs?[.posixPermissions] as? NSNumber {
                    // Check if setuid bit is set (04000 in octal)
                    if (posixPerms.uint16Value & 0o4000) == 0 {
                        print("Permissions not set, setting them now...")
                        let _ = setCorePermissions(corePath: appSupportCorePath.path)
                    } else {
                        print("FlClashCore already up-to-date with correct permissions")
                    }
                }
            }
        } catch {
            print("Failed to setup core: \(error)")
        }
    }
    
    func setCorePermissions(corePath: String) -> Bool {
        let script = """
        do shell script "chown root:admin '\(corePath)' && chmod +sx '\(corePath)'" with administrator privileges
        """
        
        var error: NSDictionary?
        if let scriptObject = NSAppleScript(source: script) {
            scriptObject.executeAndReturnError(&error)
            if let error = error {
                if let errorCode = error["NSAppleScriptErrorNumber"] as? Int, errorCode == -128 {
                    print("User cancelled password prompt")
                    showPermissionRequiredAlert()
                    NSApplication.shared.terminate(nil)
                    return false
                }
                print("Failed to set permissions: \(error)")
                return false
            } else {
                print("Permissions set successfully for: \(corePath)")
                return true
            }
        }
        return false
    }
    
    func showPermissionRequiredAlert() {
        let alert = NSAlert()
        alert.messageText = "Administrator Access Required"
        alert.informativeText = "FlClashX requires administrator privileges to set up the network core. The application cannot run without these permissions.\n\nPlease restart the application and grant administrator access when prompted."
        alert.alertStyle = .critical
        alert.addButton(withTitle: "Quit")
        alert.runModal()
    }
    
    func shouldUpdateCore(bundlePath: String, appSupportPath: String) -> Bool {
        guard let bundleAttrs = try? FileManager.default.attributesOfItem(atPath: bundlePath),
              let appSupportAttrs = try? FileManager.default.attributesOfItem(atPath: appSupportPath),
              let bundleDate = bundleAttrs[.modificationDate] as? Date,
              let appSupportDate = appSupportAttrs[.modificationDate] as? Date else {
            return true
        }
        return bundleDate > appSupportDate
    }
    
    override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }
    
    override func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        WindowExtPlugin.instance?.handleShouldTerminate()
        return .terminateCancel
    }

    override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
      return true
    }
    
    override func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag, let controller = statusBarController {
            if !flutterUIPopover.isShown {
                controller.showPopover(self)
            }
        }
        return true
    }
}
