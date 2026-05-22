import AppKit

@main
final class AppDelegate: NSObject, NSApplicationDelegate {

    private var window: NSWindow!

    func applicationDidFinishLaunching(_ notification: Notification) {
        let style: NSWindow.StyleMask = [.titled, .closable, .miniaturizable, .resizable]
        let rect = NSRect(x: 0, y: 0, width: 900, height: 640)
        window = NSWindow(contentRect: rect, styleMask: style, backing: .buffered, defer: false)
        window.title = "Cobe — macOS Demo"
        window.center()
        window.contentViewController = ViewController()
        window.makeKeyAndOrderFront(nil)
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
