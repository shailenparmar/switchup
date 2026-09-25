// SetupView — first-launch checklist for a new Mac (Accessibility, controller, Home button).

import AppKit
import GameController
import SwiftUI

struct SetupView: View {
    let engine: SwitchUp
    let onDone: () -> Void
    @State private var trusted = AXIsProcessTrusted()
    @State private var connected = false
    @State private var homeDone = false
    private let poll = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Set up SwitchUp").font(.title2.bold())
                Text("A few quick steps and your controller drives the Mac.").foregroundStyle(.secondary)
            }

            step(1, "Pair your controller", done: connected,
                 detail: "Hold the small sync button on top of the Pro Controller until the lights run, then pick it in System Settings › Bluetooth.",
                 button: "Open Bluetooth") {
                open("x-apple.systempreferences:com.apple.BluetoothSettings")
            }

            step(2, "Allow Accessibility", done: trusted,
                 detail: "Lets SwitchUp move the pointer, click, and press keys. Switch SwitchUp on in the list.",
                 button: "Open Accessibility") {
                AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary)
                open("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
            }

            step(3, "Free up the Home button", done: homeDone,
                 detail: "In Game Controllers, open Controller Shortcuts and turn off \"Enable controller shortcuts\". Otherwise Home also opens Apple's Games app.",
                 button: "Open Game Controllers") {
                open("x-apple.systempreferences:com.apple.Game-Controller-Settings.extension")
                homeDone = true
            }

            step(4, "Turn on Dictation (optional)", done: false,
                 detail: "The + button starts dictation. Switch Dictation on in System Settings › Keyboard; hold + to talk, let go to stop.",
                 button: "Open Keyboard") {
                open("x-apple.systempreferences:com.apple.Keyboard-Settings.extension")
            }

            Divider()
            HStack {
                Text("Your layout is in the menu-bar icon. Tune everything in Settings.")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button(trusted ? "Done" : "Finish later") { onDone() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 520)
        .onReceive(poll) { _ in
            trusted = AXIsProcessTrusted()
            connected = engine.controller != nil
        }
        .onAppear { connected = engine.controller != nil }
    }

    private func step(_ n: Int, _ title: String, done: Bool, detail: String, button: String,
                      action: @escaping () -> Void) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: done ? "checkmark.circle.fill" : "\(n).circle")
                .font(.title2)
                .foregroundStyle(done ? Color.green : Color.secondary)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.headline)
                Text(detail).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Button(button, action: action)
            }
        }
    }

    private func open(_ url: String) { NSWorkspace.shared.open(URL(string: url)!) }
}
