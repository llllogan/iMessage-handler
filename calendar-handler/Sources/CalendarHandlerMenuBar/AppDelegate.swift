import AppKit
import CalendarHandlerCore
import Foundation

@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var runtime: CalendarHandlerRuntime?
    private let statusMenuItem = NSMenuItem(title: "Starting...", action: nil, keyEquivalent: "")

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        configureMenu()
        startRuntime()
    }

    private func configureMenu() {
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "Calendar"

        let menu = NSMenu()
        statusMenuItem.isEnabled = false
        menu.addItem(statusMenuItem)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Request Calendar Access", action: #selector(requestAccess), keyEquivalent: "a"))
        menu.addItem(NSMenuItem(title: "Refresh Status", action: #selector(refreshStatus), keyEquivalent: "s"))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Open Calendar Privacy Settings", action: #selector(openCalendarSettings), keyEquivalent: ""))
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
            let runtime = try CalendarHandlerRuntime()
            self.runtime = runtime
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

    @objc private func requestAccess() {
        guard let runtime else {
            statusMenuItem.title = "Runtime not started"
            return
        }
        statusMenuItem.title = "Requesting Calendar access..."
        DispatchQueue.global(qos: .userInitiated).async {
            let title: String
            do {
                title = try runtime.requestAccess()
            } catch {
                title = "Access failed: \(error.localizedDescription)"
            }
            Task { @MainActor in
                self.statusMenuItem.title = title
            }
        }
    }

    @objc private func refreshStatus() {
        updateStatus()
    }

    private func updateStatus() {
        statusMenuItem.title = runtime?.statusText() ?? "Runtime not started"
    }

    @objc private func openCalendarSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
