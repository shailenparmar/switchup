// SwitchUp — drive the Mac with a Switch Pro controller (couch YouTube mode).
// Menu-bar app; power-user settings window. Needs Accessibility.

import AppKit
import GameController
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, NSWindowDelegate {
    let pad = SwitchUp()
    var item: NSStatusItem!
    var settingsWindow: NSWindow?
    var setupWindow: NSWindow?

    func applicationDidFinishLaunching(_ n: Notification) {
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.menu = NSMenu()
        item.menu?.delegate = self
        pad.onChange = { [weak self] in self?.refreshIcon() }
        pad.start()
        refreshIcon()
        if !UserDefaults.standard.bool(forKey: "setupDone") || CommandLine.arguments.contains("--setup") {
            openSetup()
        } else if !AXIsProcessTrusted() {
            AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary)
        }
        if CommandLine.arguments.contains("--settings") { openSettings() }
    }

    /// Menu-bar apps have no window, so opening SwitchUp again (Finder, Spotlight, Dock)
    /// would look like nothing happened. Show Settings instead.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        openSettings()
        return true
    }

    func refreshIcon() {
        // Always a controller, so it's recognizable: solid = active, outline = paused,
        // dimmed outline = no controller connected.
        let name = pad.controller != nil && pad.enabled ? "gamecontroller.fill" : "gamecontroller"
        item.button?.image = NSImage(systemSymbolName: name, accessibilityDescription: "SwitchUp")
        item.button?.appearsDisabled = pad.controller == nil
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        if !AXIsProcessTrusted() {
            menu.addItem(action("⚠️ Grant Accessibility access…", #selector(openAccessibility)))
            menu.addItem(.separator())
        }
        // Pause → Settings → battery → Setup Guide → Quit, then the layout below.
        menu.addItem(action(pad.enabled ? "Pause" : "Resume", #selector(toggleEnabled)))
        let settings = action("Settings…", #selector(openSettings))
        settings.keyEquivalent = ","
        menu.addItem(settings)
        let status = pad.controller.map { c -> String in
            guard let b = c.battery else { return "Controller connected" }
            return "Battery \(Int((b.batteryLevel * 100).rounded()))%" + (b.batteryState == .charging ? " charging" : "")
        } ?? "No controller connected"
        menu.addItem(disabled(status + (pad.enabled ? "" : " (paused)")))
        menu.addItem(action("Setup Guide…", #selector(openSetup)))
        menu.addItem(NSMenuItem(title: "Quit SwitchUp", action: #selector(NSApp.terminate(_:)), keyEquivalent: "q"))

        // Current layout, Magnet-style: action on the left, button on the right.
        let c = Settings.shared.c
        menu.addItem(.separator())
        menu.addItem(.sectionHeader(title: "Sticks"))
        menu.addItem(controlRow(c.swapSticks ? "Scroll (two-finger)" : "Move cursor", "Left stick"))
        menu.addItem(controlRow(c.swapSticks ? "Move cursor" : "Scroll (two-finger)", "Right stick"))
        for (group, actions) in Action.groups where !group.isEmpty {
            let rows = actions.compactMap { a -> (String, String)? in
                let buttons = ButtonID.allCases.filter { c.mapping($0).action == a }
                guard !buttons.isEmpty else { return nil }
                return (a.label, buttons.map(\.short).joined(separator: " / "))
            }
            guard !rows.isEmpty else { continue }
            menu.addItem(.sectionHeader(title: group))
            for (label, keys) in rows { menu.addItem(controlRow(label, keys)) }
        }
        // Custom shortcuts show what they send.
        for id in ButtonID.allCases where c.mapping(id).action == .customShortcut {
            menu.addItem(controlRow("Shortcut \(c.mapping(id).keyLabel)", id.short))
        }
    }

    private func controlRow(_ title: String, _ button: String) -> NSMenuItem {
        let i = action(title, #selector(openButtonSettings))
        let ps = NSMutableParagraphStyle()
        ps.tabStops = [NSTextTab(textAlignment: .right, location: 440)]
        let s = NSMutableAttributedString(string: title + "\t",
                                          attributes: [.font: NSFont.menuFont(ofSize: 0), .paragraphStyle: ps])
        s.append(NSAttributedString(string: button, attributes: [
            .font: NSFont.systemFont(ofSize: NSFont.systemFontSize, weight: .medium),
            .foregroundColor: NSColor.secondaryLabelColor, .paragraphStyle: ps,
        ]))
        i.attributedTitle = s
        return i
    }

    @objc func openButtonSettings() {
        LiveState.shared.tab = "Buttons"
        openSettings()
    }

    private func disabled(_ t: String) -> NSMenuItem {
        let i = NSMenuItem(title: t, action: nil, keyEquivalent: "")
        i.isEnabled = false
        return i
    }

    private func action(_ t: String, _ sel: Selector) -> NSMenuItem {
        let i = NSMenuItem(title: t, action: sel, keyEquivalent: "")
        i.target = self
        return i
    }

    @objc func toggleEnabled() { pad.enabled.toggle() }

    @objc func openAccessibility() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }

    @objc func openSettings() {
        if settingsWindow == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 660, height: 720),
                             styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            w.title = "SwitchUp Settings"
            w.contentView = NSHostingView(rootView: SettingsView(engine: pad))
            w.isReleasedWhenClosed = false
            w.delegate = self
            w.center()
            settingsWindow = w
        }
        LiveState.shared.watching = true
        NSApp.activate()
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    @objc func openSetup() {
        if setupWindow == nil {
            let w = NSWindow(contentRect: .zero, styleMask: [.titled, .closable], backing: .buffered, defer: false)
            w.title = "SwitchUp Setup"
            w.contentView = NSHostingView(rootView: SetupView(engine: pad) { [weak self] in
                UserDefaults.standard.set(true, forKey: "setupDone")
                self?.setupWindow?.close()
            })
            w.isReleasedWhenClosed = false
            w.center()
            setupWindow = w
        }
        NSApp.activate()
        setupWindow?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ n: Notification) {
        LiveState.shared.watching = false
    }
}

// MARK: - Entry

if CommandLine.arguments.contains("--probe") {
    // Print how GameController labels each input on the connected pad.
    GCController.shouldMonitorBackgroundEvents = true
    func dump(_ c: GCController) {
        print("Controller: \(c.vendorName ?? "?") [\(c.productCategory)]")
        guard let p = c.extendedGamepad else { return }
        let named: [(String, GCControllerElement?)] = [
            ("buttonA", p.buttonA), ("buttonB", p.buttonB), ("buttonX", p.buttonX), ("buttonY", p.buttonY),
            ("leftShoulder", p.leftShoulder), ("rightShoulder", p.rightShoulder),
            ("leftTrigger", p.leftTrigger), ("rightTrigger", p.rightTrigger),
            ("buttonMenu", p.buttonMenu), ("buttonOptions", p.buttonOptions), ("buttonHome", p.buttonHome),
        ]
        for (n, e) in named { print("  \(n) → \(e?.localizedName ?? "-") / \(e?.sfSymbolsName ?? "-")") }
        exit(0)
    }
    NotificationCenter.default.addObserver(forName: .GCControllerDidConnect, object: nil, queue: .main) { n in
        if let c = n.object as? GCController { dump(c) }
    }
    if let c = GCController.controllers().first { dump(c) }
    DispatchQueue.main.asyncAfter(deadline: .now() + 5) { print("No controller found."); exit(1) }
    RunLoop.main.run()
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
