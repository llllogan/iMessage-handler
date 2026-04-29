import AppKit
import CalendarHandlerCore
import Foundation

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var runtime: CalendarHandlerRuntime?
    private let statusMenuItem = NSMenuItem(title: "Starting...", action: nil, keyEquivalent: "")
    private let logURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/calendar-handler-menubar.log")

    func applicationDidFinishLaunching(_ notification: Notification) {
        log("applicationDidFinishLaunching")
        NSApp.setActivationPolicy(.accessory)
        configureMenu()
        startRuntime()
        requestAccessOnFirstLaunch()
    }

    private func configureMenu() {
        log("configureMenu")
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "calendar", accessibilityDescription: "Calendar Handler")
            button.toolTip = "Calendar Handler"
        }

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
        log("status item configured")
    }

    private func startRuntime() {
        do {
            let runtime = try CalendarHandlerRuntime()
            self.runtime = runtime
            log("runtime initialized")
            runtime.startInBackground { [weak self] message in
                Task { @MainActor in
                    self?.log("server error: \(message)")
                    self?.statusMenuItem.title = "Server error: \(message)"
                }
            }
            log("server start requested")
            updateStatus()
        } catch {
            log("startup failed: \(error.localizedDescription)")
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
                self.log(title)
                self.statusMenuItem.title = title
            }
        }
    }

    private func requestAccessOnFirstLaunch() {
        guard let runtime else {
            return
        }
        statusMenuItem.title = "Checking Calendar access..."
        DispatchQueue.global(qos: .userInitiated).async {
            let title: String
            do {
                title = try runtime.requestAccessIfNotDetermined()
            } catch {
                title = "Access failed: \(error.localizedDescription)"
            }
            Task { @MainActor in
                self.log(title)
                self.statusMenuItem.title = title
            }
        }
    }

    @objc private func refreshStatus() {
        updateStatus()
    }

    private func updateStatus() {
        statusMenuItem.title = runtime?.statusText() ?? "Runtime not started"
        log(statusMenuItem.title)
    }

    @objc private func openCalendarSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func quit() {
        log("quit")
        NSApp.terminate(nil)
    }

    private func log(_ message: String) {
        let line = "\(Date()) \(message)\n"
        guard let data = line.data(using: .utf8) else {
            return
        }
        if FileManager.default.fileExists(atPath: logURL.path),
           let handle = try? FileHandle(forWritingTo: logURL) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: logURL, options: .atomic)
        }
    }
}
