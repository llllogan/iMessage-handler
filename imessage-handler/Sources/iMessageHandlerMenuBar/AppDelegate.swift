import AppKit
import Foundation
import iMessageHandlerCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var runtime: IMessageHandlerRuntime?
    private let statusMenuItem = NSMenuItem(title: "Starting...", action: nil, keyEquivalent: "")
    private let databaseAccessItem = NSMenuItem(title: "Checking Messages access...", action: nil, keyEquivalent: "")

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        configureMenu()
        startRuntime()
    }

    private func configureMenu() {
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "message", accessibilityDescription: "iMessage Handler")
            button.toolTip = "iMessage Handler"
        }

        let menu = NSMenu()
        statusMenuItem.isEnabled = false
        databaseAccessItem.isEnabled = false
        menu.addItem(statusMenuItem)
        menu.addItem(databaseAccessItem)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Sync Now", action: #selector(syncNow), keyEquivalent: "s"))
        menu.addItem(NSMenuItem(title: "Rebuild Index", action: #selector(rebuildIndex), keyEquivalent: "r"))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Open Full Disk Access Settings", action: #selector(openFullDiskAccessSettings), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q"))

        for item in menu.items where item.action != nil {
            item.target = self
        }

        statusItem.menu = menu
        self.statusItem = statusItem
    }

    private func startRuntime() {
        do {
            let runtime = try IMessageHandlerRuntime()
            self.runtime = runtime
            updateAccessStatus()
            runtime.startInBackground { [weak self] message in
                Task { @MainActor in
                    self?.statusMenuItem.title = "Server error: \(message)"
                }
            }
            updateStatus()
        } catch {
            statusMenuItem.title = "Startup failed: \(error.localizedDescription)"
        }
    }

    private func updateStatus() {
        guard let runtime else {
            return
        }
        statusMenuItem.title = runtime.statusText()
        updateAccessStatus()
    }

    private func updateAccessStatus() {
        guard let runtime else {
            databaseAccessItem.title = "Messages DB access unknown"
            return
        }
        databaseAccessItem.title = runtime.canReadMessagesDatabase()
            ? "Messages DB access: OK"
            : "Messages DB access: Full Disk Access required"
    }

    @objc private func syncNow() {
        runRuntimeAction("Syncing...") { runtime in
            try runtime.syncNow()
        }
    }

    @objc private func rebuildIndex() {
        runRuntimeAction("Rebuilding index...") { runtime in
            try runtime.rebuildIndex()
        }
    }

    private func runRuntimeAction(_ pendingTitle: String, action: @escaping @Sendable (IMessageHandlerRuntime) throws -> String) {
        guard let runtime else {
            statusMenuItem.title = "Runtime not started"
            return
        }
        statusMenuItem.title = pendingTitle
        DispatchQueue.global(qos: .userInitiated).async {
            let title: String
            do {
                title = try action(runtime)
            } catch {
                title = "Action failed: \(error.localizedDescription)"
            }
            Task { @MainActor in
                self.statusMenuItem.title = title
                self.updateAccessStatus()
            }
        }
    }

    @objc private func openFullDiskAccessSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
