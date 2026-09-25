// SettingsView — the power-user panel. Every change applies live.

import AppKit
import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings = Settings.shared
    @ObservedObject var live = LiveState.shared
    let engine: SwitchUp

    var body: some View {
        TabView(selection: $live.tab) {
            CursorTab(settings: settings).tabItem { Text("Cursor") }.tag("Cursor")
            ScrollTab(settings: settings).tabItem { Text("Scroll") }.tag("Scroll")
            ButtonsTab(settings: settings).tabItem { Text("Buttons") }.tag("Buttons")
            DictationTab(settings: settings, engine: engine).tabItem { Text("Dictation") }.tag("Dictation")
            GeneralTab(settings: settings, engine: engine).tabItem { Text("General") }.tag("General")
        }
        .padding(12)
        .frame(minWidth: 620, minHeight: 640)
    }
}

// MARK: - Building blocks

struct ParamRow: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    var digits = 2
    var unit = ""
    var help = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(title)
                Spacer()
                TextField("", value: $value, format: .number.precision(.fractionLength(digits)))
                    .frame(width: 72)
                    .multilineTextAlignment(.trailing)
                Text(unit).foregroundStyle(.secondary).frame(width: 38, alignment: .leading)
            }
            Slider(value: $value, in: range)
            if !help.isEmpty { Text(help).font(.caption).foregroundStyle(.secondary) }
        }
    }
}

/// Speed vs. stick deflection, with the live stick position marked.
struct CurveGraph: View {
    let response: (Double) -> Double
    let maxOut: Double
    let deadzone: Double
    let live: Double
    let unit: String

    var body: some View {
        Canvas { ctx, size in
            let w = size.width, h = size.height
            func pt(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: x * w, y: h - min(y / max(maxOut, 1), 1) * h) }

            ctx.fill(Path(CGRect(x: 0, y: 0, width: deadzone * w, height: h)), with: .color(.secondary.opacity(0.12)))
            for i in 1..<4 {
                let g = Double(i) / 4
                ctx.stroke(Path { $0.move(to: CGPoint(x: g * w, y: 0)); $0.addLine(to: CGPoint(x: g * w, y: h)) },
                           with: .color(.secondary.opacity(0.15)))
                ctx.stroke(Path { $0.move(to: CGPoint(x: 0, y: g * h)); $0.addLine(to: CGPoint(x: w, y: g * h)) },
                           with: .color(.secondary.opacity(0.15)))
            }
            ctx.stroke(Path { $0.move(to: pt(0, 0)); $0.addLine(to: pt(1, maxOut)) },
                       with: .color(.secondary.opacity(0.35)), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
            var curve = Path()
            for i in 0...200 {
                let x = Double(i) / 200
                i == 0 ? curve.move(to: pt(x, response(x))) : curve.addLine(to: pt(x, response(x)))
            }
            ctx.stroke(curve, with: .color(.accentColor), lineWidth: 2)
            let dot = pt(min(live, 1), response(min(live, 1)))
            ctx.fill(Path(ellipseIn: CGRect(x: dot.x - 5, y: dot.y - 5, width: 10, height: 10)), with: .color(.orange))
        }
        .frame(height: 150)
        .overlay(alignment: .topLeading) {
            Text("\(Int(maxOut)) \(unit)").font(.caption2.monospaced()).foregroundStyle(.secondary).padding(4)
        }
        .overlay(alignment: .bottomTrailing) {
            Text("stick deflection →").font(.caption2.monospaced()).foregroundStyle(.secondary).padding(4)
        }
        .background(RoundedRectangle(cornerRadius: 6).stroke(.secondary.opacity(0.3)))
    }
}

// MARK: - Cursor

struct CursorTab: View {
    @ObservedObject var settings: Settings
    @ObservedObject var live = LiveState.shared

    var body: some View {
        Form {
            Section {
                CurveGraph(response: settings.c.cursorResponse, maxOut: settings.c.cursorMaxSpeed,
                           deadzone: settings.c.cursorDeadzone,
                           live: hypot(live.cursorStick.x, live.cursorStick.y), unit: "px/s")
                HStack {
                    Text(String(format: "stick %.2f, %.2f", live.cursorStick.x, live.cursorStick.y))
                    Spacer()
                    Text("\(Int(live.cursorSpeed)) px/s")
                }
                .font(.caption.monospaced()).foregroundStyle(.secondary)
            }
            Section("Response curve") {
                ParamRow(title: "Max speed", value: $settings.c.cursorMaxSpeed, range: 100...6000, digits: 0, unit: "px/s",
                         help: "Speed at full tilt.")
                ParamRow(title: "Min speed", value: $settings.c.cursorMinSpeed, range: 0...400, digits: 0, unit: "px/s",
                         help: "Speed just past the deadzone. Raise it if small nudges feel dead.")
                ParamRow(title: "Exponent", value: $settings.c.cursorExponent, range: 0.5...5, digits: 2,
                         help: "1 = linear. Higher = more precision near center, faster rush at the edge.")
                ParamRow(title: "Inner deadzone", value: $settings.c.cursorDeadzone, range: 0...0.5, digits: 3,
                         help: "Ignore stick drift below this. Raise it if the cursor creeps on its own.")
                ParamRow(title: "Outer deadzone", value: $settings.c.cursorOuterDeadzone, range: 0.5...1, digits: 3,
                         help: "Deflection that counts as full tilt.")
                Picker("Deadzone shape", selection: $settings.c.cursorDeadzoneShape) {
                    Text("Radial (smooth diagonals)").tag(DeadzoneShape.radial)
                    Text("Axial (snaps to straight lines)").tag(DeadzoneShape.axial)
                }
                ParamRow(title: "Smoothing", value: $settings.c.cursorSmoothing, range: 0...0.95, digits: 2,
                         help: "0 = instant. Higher = glidier starts and stops.")
            }
            Section("Modifiers") {
                ParamRow(title: "Precision multiplier", value: $settings.c.precisionMultiplier, range: 0.05...1, digits: 2, unit: "×")
                ParamRow(title: "Auto-turbo at full tilt", value: $settings.c.turboMultiplier, range: 1...5, digits: 2, unit: "×",
                         help: "Holding the stick fully over ramps speed up to this. 1 = off.")
                ParamRow(title: "Auto-turbo ramp time", value: $settings.c.turboRampTime, range: 0.05...3, digits: 2, unit: "s")
                ParamRow(title: "Turbo-hold multiplier", value: $settings.c.turboHoldMultiplier, range: 1...6, digits: 2, unit: "×",
                         help: "For the \"Turbo cursor (while held)\" button action.")
                Toggle("Invert Y", isOn: $settings.c.cursorInvertY)
                Toggle("Swap sticks (right stick moves cursor)", isOn: $settings.c.swapSticks)
            }
            Button("Reset cursor settings") {
                let d = Config()
                settings.c.cursorMaxSpeed = d.cursorMaxSpeed; settings.c.cursorMinSpeed = d.cursorMinSpeed
                settings.c.cursorExponent = d.cursorExponent; settings.c.cursorDeadzone = d.cursorDeadzone
                settings.c.cursorOuterDeadzone = d.cursorOuterDeadzone; settings.c.cursorDeadzoneShape = d.cursorDeadzoneShape
                settings.c.cursorSmoothing = d.cursorSmoothing; settings.c.precisionMultiplier = d.precisionMultiplier
                settings.c.turboMultiplier = d.turboMultiplier; settings.c.turboRampTime = d.turboRampTime
                settings.c.turboHoldMultiplier = d.turboHoldMultiplier; settings.c.cursorInvertY = d.cursorInvertY
                settings.c.swapSticks = d.swapSticks
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Scroll

struct ScrollTab: View {
    @ObservedObject var settings: Settings
    @ObservedObject var live = LiveState.shared

    var body: some View {
        Form {
            Section {
                CurveGraph(response: settings.c.scrollResponse, maxOut: settings.c.scrollMaxSpeed,
                           deadzone: settings.c.scrollDeadzone,
                           live: hypot(live.scrollStick.x, live.scrollStick.y), unit: "px/s")
            }
            Section("Style") {
                Picker("Right stick acts like", selection: $settings.c.scrollStyle) {
                    Text("Two fingers on a trackpad").tag(ScrollStyle.trackpad)
                    Text("Mouse scroll wheel").tag(ScrollStyle.wheel)
                }
                .pickerStyle(.segmented)
                Text("Trackpad style sends real gesture phases: stick ← swipes notifications away and swipes Back in browsers, with rubber-band overscroll.")
                    .font(.caption).foregroundStyle(.secondary)
                Toggle("Momentum (glide after release, trackpad style)", isOn: $settings.c.scrollMomentum)
                ParamRow(title: "Momentum decay", value: $settings.c.momentumDecay, range: 0.80...0.99, digits: 3,
                         help: "Speed kept every 1/120 s after release. Higher = longer glide.")
            }
            Section("Response curve") {
                ParamRow(title: "Max speed", value: $settings.c.scrollMaxSpeed, range: 100...8000, digits: 0, unit: "px/s")
                ParamRow(title: "Min speed", value: $settings.c.scrollMinSpeed, range: 0...600, digits: 0, unit: "px/s")
                ParamRow(title: "Exponent", value: $settings.c.scrollExponent, range: 0.5...5, digits: 2)
                ParamRow(title: "Deadzone", value: $settings.c.scrollDeadzone, range: 0...0.5, digits: 3)
            }
            Section("Direction") {
                Toggle("Invert vertical", isOn: $settings.c.scrollInvertY)
                Toggle("Horizontal scrolling", isOn: $settings.c.scrollHorizontal)
                Toggle("Invert horizontal", isOn: $settings.c.scrollInvertX)
            }
            Button("Reset scroll settings") {
                let d = Config()
                settings.c.scrollMaxSpeed = d.scrollMaxSpeed; settings.c.scrollMinSpeed = d.scrollMinSpeed
                settings.c.scrollExponent = d.scrollExponent; settings.c.scrollDeadzone = d.scrollDeadzone
                settings.c.scrollInvertY = d.scrollInvertY; settings.c.scrollInvertX = d.scrollInvertX
                settings.c.scrollHorizontal = d.scrollHorizontal
                settings.c.scrollStyle = d.scrollStyle; settings.c.scrollMomentum = d.scrollMomentum
                settings.c.momentumDecay = d.momentumDecay
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Buttons

struct ButtonsTab: View {
    @ObservedObject var settings: Settings
    @ObservedObject var live = LiveState.shared

    private func mapping(_ id: ButtonID) -> Binding<Mapping> {
        Binding(get: { settings.c.mapping(id) }, set: { settings.c.bindings[id.rawValue] = $0 })
    }

    var body: some View {
        Form {
            Section {
                Text("Press a button on the controller and its row lights up.")
                    .font(.caption).foregroundStyle(.secondary)
                ForEach(ButtonID.allCases) { id in
                    HStack {
                        Text(id.label)
                            .frame(width: 170, alignment: .leading)
                            .fontWeight(live.pressed.contains(id) ? .bold : .regular)
                            .foregroundStyle(live.pressed.contains(id) ? Color.orange : Color.primary)
                        Picker("", selection: mapping(id).action) {
                            ForEach(Action.groups, id: \.0) { group in
                                if group.0.isEmpty {
                                    ForEach(group.1) { Text($0.label).tag($0) }
                                } else {
                                    Section(group.0) { ForEach(group.1) { Text($0.label).tag($0) } }
                                }
                            }
                        }
                        .labelsHidden()
                        if mapping(id).wrappedValue.action == .customShortcut {
                            ShortcutRecorder(mapping: mapping(id))
                        }
                    }
                }
            }
            Section("Hold-to-repeat (arrows, seek, volume, app switcher)") {
                ParamRow(title: "Repeat delay", value: $settings.c.repeatDelay, range: 0.1...1.5, digits: 2, unit: "s")
                ParamRow(title: "Repeat interval", value: $settings.c.repeatInterval, range: 0.02...0.5, digits: 3, unit: "s")
            }
            Section("App switcher (⌘⇥)") {
                ParamRow(title: "Commit delay", value: $settings.c.switcherCommitDelay, range: 0.2...3, digits: 2, unit: "s",
                         help: "Each press moves one app along while ⌘ stays held. The switch lands this long after your last press, or right away when you press any other button.")
            }
            Button("Reset button mapping") { settings.c.bindings = Config().bindings }
        }
        .formStyle(.grouped)
    }
}

struct ShortcutRecorder: View {
    @Binding var mapping: Mapping
    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        Button(recording ? "Press keys…" : (mapping.keyLabel.isEmpty ? "Record" : mapping.keyLabel)) {
            recording ? stop() : start()
        }
        .frame(minWidth: 90)
    }

    private func start() {
        recording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { e in
            var f: CGEventFlags = []
            let m = e.modifierFlags
            if m.contains(.command) { f.insert(.maskCommand) }
            if m.contains(.option) { f.insert(.maskAlternate) }
            if m.contains(.control) { f.insert(.maskControl) }
            if m.contains(.shift) { f.insert(.maskShift) }
            mapping.keyCode = e.keyCode
            mapping.modifiers = f.rawValue
            mapping.keyLabel = ShortcutRecorder.describe(e)
            stop()
            return nil
        }
    }

    private func stop() {
        recording = false
        if let m = monitor { NSEvent.removeMonitor(m) }
        monitor = nil
    }

    static func describe(_ e: NSEvent) -> String {
        let m = e.modifierFlags
        var s = ""
        if m.contains(.control) { s += "⌃" }
        if m.contains(.option) { s += "⌥" }
        if m.contains(.shift) { s += "⇧" }
        if m.contains(.command) { s += "⌘" }
        let names: [UInt16: String] = [123: "←", 124: "→", 125: "↓", 126: "↑", 36: "↩", 48: "⇥", 49: "Space",
                                       51: "⌫", 53: "Esc", 116: "PgUp", 121: "PgDn", 115: "Home", 119: "End",
                                       122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6",
                                       98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12"]
        return s + (names[e.keyCode] ?? e.charactersIgnoringModifiers?.uppercased() ?? "key \(e.keyCode)")
    }
}

// MARK: - Dictation

struct DictationTab: View {
    @ObservedObject var settings: Settings
    let engine: SwitchUp
    @State private var testText = ""

    var body: some View {
        Form {
            Section("Method") {
                Picker("Trigger", selection: $settings.c.dictationMethod) {
                    ForEach(DictationMethod.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.radioGroup)
                Text("⌘⌘ copies your own shortcut exactly and works in every app. The menu item skips the double-tap timing but only works in apps that have Edit › Start Dictation (most do, including Chrome and Safari).")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("⌘⌘ double-tap") {
                Picker("Command key", selection: $settings.c.dictationRightCommand) {
                    Text("Left ⌘").tag(false)
                    Text("Right ⌘").tag(true)
                }
                .pickerStyle(.segmented)
                Text("Match System Settings › Keyboard › Dictation › Shortcut. If it says \"Press Either Command Key Twice\", either works.")
                    .font(.caption).foregroundStyle(.secondary)
                ParamRow(title: "Tap hold", value: $settings.c.dictationTapHoldMs, range: 10...150, digits: 0, unit: "ms")
                ParamRow(title: "Gap between taps", value: $settings.c.dictationTapGapMs, range: 20...300, digits: 0, unit: "ms")
            }
            Section("Hold to talk") {
                ParamRow(title: "Hold threshold", value: $settings.c.dictationHoldThreshold, range: 0.1...1.5, digits: 2, unit: "s",
                         help: "For \"Dictation (hold to talk)\": hold longer than this and releasing stops dictation. A quicker tap leaves it running until you tap again.")
            }
            Section("Test") {
                TextField("Click here, then press Test (or your dictation button) and speak", text: $testText, axis: .vertical)
                    .lineLimit(3...6)
                HStack {
                    Button("Test dictation") { engine.startDictation() }
                    Button("Clear") { testText = "" }
                }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - General

struct GeneralTab: View {
    @ObservedObject var settings: Settings
    let engine: SwitchUp
    @State private var loginEnabled = SMAppService.mainApp.status == .enabled

    var body: some View {
        Form {
            Section("Engine") {
                ParamRow(title: "Polling rate", value: $settings.c.pollHz, range: 30...500, digits: 0, unit: "Hz",
                         help: "How often the sticks are read. 120 is smooth; 240+ matches high-refresh displays.")
                Toggle("Player LED shows when SwitchUp is active", isOn: $settings.c.playerLED)
                    .onChange(of: settings.c.playerLED) { engine.updateLights() }
            }
            Section("App") {
                Toggle("Launch at login", isOn: $loginEnabled)
                    .onChange(of: loginEnabled) {
                        let s = SMAppService.mainApp
                        do { if loginEnabled { try s.register() } else { try s.unregister() } }
                        catch { NSLog("SwitchUp login item: \(error)") }
                    }
                HStack {
                    Button("Reveal config file") {
                        NSWorkspace.shared.activateFileViewerSelecting([Settings.fileURL])
                    }
                    Button("Reload config file") { settings.c = Settings.load() }
                }
                Text("Everything lives in config.json. Edit it by hand, then Reload.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section {
                Button("Reset ALL settings to defaults", role: .destructive) { settings.c = Config() }
            }
        }
        .formStyle(.grouped)
    }
}
