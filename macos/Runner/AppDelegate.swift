import Cocoa
import FlutterMacOS
import window

@main
class AppDelegate: FlutterAppDelegate {
    
    override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }
    
    // Cancelling would also cancel a logout, restart or shutdown that asked.
    // Dart exits the process once it has cleaned up; the reply covers a Dart
    // that never gets there.
    override func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let plugin = WindowPlugin.instance else {
            return .terminateNow
        }
        plugin.handleShouldTerminate()
        DispatchQueue.main.asyncAfter(deadline: .now() + 6) {
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
      return true
    }
    
    override func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        WindowPlugin.instance?.handleReopen()
        return false
    }
}
