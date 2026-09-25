// Config — every tunable, persisted as JSON in
// ~/Library/Application Support/SwitchUp/config.json (hand-editable).

import AppKit
import Combine

// MARK: - Buttons

enum ButtonID: String, CaseIterable, Codable, Identifiable {
    case a, b, x, y, l, r, zl, zr, plus, minus, l3, r3, dpadUp, dpadDown, dpadLeft, dpadRight, home, capture
    var id: String { rawValue }
    /// Compact name for the menu-bar list.
    var short: String {
        switch self {
        case .a: "A"; case .b: "B"; case .x: "X"; case .y: "Y"
        case .l: "L"; case .r: "R"; case .zl: "ZL"; case .zr: "ZR"
        case .plus: "+"; case .minus: "−"; case .home: "Home"; case .capture: "Capture"
        case .l3: "L3 click"; case .r3: "R3 click"
        case .dpadUp: "D-pad ↑"; case .dpadDown: "D-pad ↓"; case .dpadLeft: "D-pad ←"; case .dpadRight: "D-pad →"
        }
    }
    var label: String {
        switch self {
        case .a: "A"; case .b: "B"; case .x: "X"; case .y: "Y"
        case .l: "L"; case .r: "R"; case .zl: "ZL"; case .zr: "ZR"
        case .plus: "+ (Plus)"; case .minus: "− (Minus)"; case .home: "Home"; case .capture: "Capture (◻︎ left of Home)"
        case .l3: "L3 (left stick press)"; case .r3: "R3 (right stick press)"
        case .dpadUp: "D-pad ↑"; case .dpadDown: "D-pad ↓"; case .dpadLeft: "D-pad ←"; case .dpadRight: "D-pad →"
        }
    }
}

// MARK: - Actions

enum Action: String, CaseIterable, Codable, Identifiable {
    case none
    // Mouse
    case leftClick, rightClick, middleClick, doubleClick, openLinkNewTab, openLinkBackground
    // Browser
    case back, forward, nextTab, prevTab, closeTab, closeWindow, reopenTab, addressBar
    // YouTube
    case ytPlayPause, ytFullscreen, ytSeekBack, ytSeekForward, ytCaptions, ytMute, ytFaster, ytSlower
    // Keys
    case space, enter, escape, tab, backspace, deleteWord, arrowUp, arrowDown, arrowLeft, arrowRight, pageUp, pageDown
    // System
    case spotlight, desktopPrev, desktopNext, missionControl, appWindows, showDesktop, dictation, dictationHold
    case appSwitchNext, appSwitchPrev, lastApp
    // Media
    case mediaPlayPause, mediaNext, mediaPrev, volumeUp, volumeDown, mute
    // SwitchUp
    case precisionToggle, precisionHold, turboHold, scrollModeHold, pauseSwitchUp
    case customShortcut

    var id: String { rawValue }

    var label: String {
        switch self {
        case .none: "— Nothing —"
        case .leftClick: "Left click (hold = drag)"; case .rightClick: "Right click"; case .middleClick: "Middle click"
        case .doubleClick: "Double-click (YouTube fullscreen on video)"
        case .openLinkNewTab: "Open link in new tab + jump to it (⌘⇧-click)"
        case .openLinkBackground: "Open link in background tab (⌘-click)"
        case .back: "Back (⌘[)"; case .forward: "Forward (⌘])"
        case .nextTab: "Next tab (⌃⇥)"; case .prevTab: "Previous tab (⌃⇧⇥)"
        case .addressBar: "Address bar (⌘L)"
        case .closeWindow: "Close window (⌘⇧W)"
        case .closeTab: "Close tab (⌘W)"; case .reopenTab: "Reopen closed tab (⌘⇧T)"
        case .ytPlayPause: "YouTube play/pause (K)"; case .ytFullscreen: "YouTube fullscreen (F)"
        case .ytSeekBack: "YouTube −10s (J)"; case .ytSeekForward: "YouTube +10s (L)"
        case .ytCaptions: "YouTube captions (C)"; case .ytMute: "YouTube mute (M)"
        case .ytFaster: "YouTube faster (⇧.)"; case .ytSlower: "YouTube slower (⇧,)"
        case .space: "Space"; case .enter: "Return"; case .escape: "Esc"; case .tab: "Tab"
        case .backspace: "Backspace (⌫)"; case .deleteWord: "Delete word (⌥⌫)"
        case .arrowUp: "↑"; case .arrowDown: "↓"; case .arrowLeft: "←"; case .arrowRight: "→"
        case .pageUp: "Page Up"; case .pageDown: "Page Down"
        case .desktopPrev: "Previous desktop (⌃←)"; case .desktopNext: "Next desktop (⌃→)"
        case .missionControl: "Mission Control"; case .appWindows: "App windows (⌃↓)"
        case .spotlight: "Spotlight (⌘Space)"
        case .showDesktop: "Show Desktop (fn F11)"
        case .dictation: "Dictation (toggle)"
        case .dictationHold: "Dictation (hold to talk, tap to toggle)"
        case .appSwitchNext: "App switcher → (⌘⇥, cycles)"; case .appSwitchPrev: "App switcher ← (⌘⇧⇥, cycles)"
        case .lastApp: "Jump to last app (instant ⌘⇥)"
        case .mediaPlayPause: "Media play/pause"; case .mediaNext: "Media next"; case .mediaPrev: "Media previous"
        case .volumeUp: "System volume +"; case .volumeDown: "System volume −"; case .mute: "System mute"
        case .precisionToggle: "Precision mode (toggle)"; case .precisionHold: "Precision mode (while held)"
        case .turboHold: "Turbo cursor (while held)"; case .scrollModeHold: "Cursor stick scrolls (while held)"
        case .pauseSwitchUp: "Pause / resume SwitchUp"
        case .customShortcut: "Custom shortcut…"
        }
    }

    /// Auto-repeat while the button is held.
    var repeats: Bool {
        switch self {
        case .arrowUp, .arrowDown, .arrowLeft, .arrowRight, .pageUp, .pageDown, .backspace, .deleteWord,
             .ytSeekBack, .ytSeekForward, .volumeUp, .volumeDown, .appSwitchNext, .appSwitchPrev: true
        default: false
        }
    }

    static let groups: [(String, [Action])] = [
        ("", [.none]),
        ("Mouse", [.leftClick, .rightClick, .middleClick, .doubleClick, .openLinkNewTab, .openLinkBackground]),
        ("Browser", [.back, .forward, .prevTab, .nextTab, .closeTab, .closeWindow, .reopenTab, .addressBar]),
        ("YouTube", [.ytPlayPause, .ytFullscreen, .ytSeekBack, .ytSeekForward, .ytCaptions, .ytMute, .ytFaster, .ytSlower]),
        ("Keys", [.space, .enter, .escape, .tab, .backspace, .deleteWord, .arrowUp, .arrowDown, .arrowLeft, .arrowRight, .pageUp, .pageDown]),
        ("Apps", [.appSwitchPrev, .appSwitchNext, .lastApp]),
        ("System", [.spotlight, .desktopPrev, .desktopNext, .missionControl, .appWindows, .showDesktop, .dictation, .dictationHold]),
        ("Media", [.mediaPlayPause, .mediaNext, .mediaPrev, .volumeUp, .volumeDown, .mute]),
        ("SwitchUp", [.precisionToggle, .precisionHold, .turboHold, .scrollModeHold, .pauseSwitchUp]),
        ("Custom", [.customShortcut]),
    ]
}

struct Mapping: Codable, Equatable {
    var action: Action
    var keyCode: UInt16 = 0          // customShortcut only
    var modifiers: UInt64 = 0        // CGEventFlags raw value
    var keyLabel: String = ""
}

enum DictationMethod: String, Codable, CaseIterable, Identifiable {
    case doubleCommand, menuItem, menuThenCommand
    var id: String { rawValue }
    var label: String {
        switch self {
        case .doubleCommand: "Simulate ⌘⌘ double-tap"
        case .menuItem: "Press Edit › Start Dictation (Accessibility)"
        case .menuThenCommand: "Menu item, fall back to ⌘⌘"
        }
    }
}

enum ScrollStyle: String, Codable, CaseIterable, Identifiable {
    case trackpad, wheel
    var id: String { rawValue }
}

enum DeadzoneShape: String, Codable, CaseIterable, Identifiable {
    case radial, axial
    var id: String { rawValue }
}

// MARK: - Config

struct Config: Codable, Equatable {
    // Cursor
    var cursorMaxSpeed = 2081.0          // px/s at full tilt
    var cursorMinSpeed = 0.0             // px/s just past the deadzone
    var cursorExponent = 2.788             // response curve (1 = linear)
    var cursorDeadzone = 0.0
    var cursorOuterDeadzone = 1.0       // stick ≥ this counts as full tilt
    var cursorDeadzoneShape = DeadzoneShape.radial
    var cursorSmoothing = 0.361            // 0 = raw, 0.9 = very floaty
    var precisionMultiplier = 0.134
    var turboMultiplier = 1.0            // auto-turbo at full tilt (1 = off)
    var turboRampTime = 0.6              // s at full tilt to reach turbo
    var turboHoldMultiplier = 2.5        // "Turbo (while held)" action
    var cursorInvertY = false
    var swapSticks = false

    // Scroll
    var scrollStyle = ScrollStyle.trackpad      // trackpad = two-finger gestures (swipe notifications, page swipes)
    var scrollMomentum = true
    var momentumDecay = 0.95             // velocity kept per 1/120 s after release
    var scrollMaxSpeed = 1800.0
    var scrollMinSpeed = 0.0
    var scrollExponent = 2.0
    var scrollDeadzone = 0.0
    var scrollInvertY = false
    var scrollInvertX = false
    var scrollHorizontal = true

    // Buttons
    var repeatDelay = 0.40
    var repeatInterval = 0.08
    var switcherCommitDelay = 0.8        // s after last ⌘⇥ press before ⌘ is released
    var bindings: [String: Mapping] = Config.defaultBindings.reduce(into: [:]) { $0[$1.key.rawValue] = $1.value }

    // Dictation
    var dictationMethod = DictationMethod.menuThenCommand
    var dictationRightCommand = false
    var dictationTapHoldMs = 30.0
    var dictationTapGapMs = 70.0
    var dictationHoldThreshold = 0.35    // shorter press = toggle (stays on)

    // General
    var pollHz = 120.0
    var playerLED = true

    static let defaultBindings: [ButtonID: Mapping] = [
        .a: .init(action: .leftClick), .b: .init(action: .rightClick),
        .x: .init(action: .closeTab), .y: .init(action: .spotlight),
        .zl: .init(action: .desktopPrev), .zr: .init(action: .desktopNext),
        .l: .init(action: .prevTab), .r: .init(action: .nextTab),
        .plus: .init(action: .dictationHold), .minus: .init(action: .deleteWord),
        .dpadLeft: .init(action: .appSwitchPrev), .dpadRight: .init(action: .appSwitchNext),
        .dpadUp: .init(action: .missionControl), .dpadDown: .init(action: .showDesktop),
        .l3: .init(action: .precisionToggle), .r3: .init(action: .addressBar),
        .home: .init(action: .enter), .capture: .init(action: .escape),
    ]

    func mapping(_ id: ButtonID) -> Mapping {
        bindings[id.rawValue] ?? Config.defaultBindings[id] ?? .init(action: .none)
    }

    /// Stick magnitude (0…1) → px/s, before precision/turbo.
    static func response(_ m: Double, dz: Double, outer: Double, exp: Double, minS: Double, maxS: Double) -> Double {
        guard m > dz else { return 0 }
        let t = min((m - dz) / max(outer - dz, 0.001), 1)
        return minS + (maxS - minS) * pow(t, exp)
    }
    func cursorResponse(_ m: Double) -> Double {
        Config.response(m, dz: cursorDeadzone, outer: cursorOuterDeadzone, exp: cursorExponent,
                        minS: cursorMinSpeed, maxS: cursorMaxSpeed)
    }
    func scrollResponse(_ m: Double) -> Double {
        Config.response(m, dz: scrollDeadzone, outer: 1, exp: scrollExponent,
                        minS: scrollMinSpeed, maxS: scrollMaxSpeed)
    }
}

// MARK: - Store

final class Settings: ObservableObject {
    static let shared = Settings()
    @Published var c: Config { didSet { if c != oldValue { scheduleSave() } } }

    static let fileURL: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SwitchUp", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        // One-time carry-over from the app's old name.
        let old = dir.deletingLastPathComponent().appendingPathComponent("PadMouse/config.json")
        let new = dir.appendingPathComponent("config.json")
        if !FileManager.default.fileExists(atPath: new.path), FileManager.default.fileExists(atPath: old.path) {
            try? FileManager.default.copyItem(at: old, to: new)
        }
        return dir.appendingPathComponent("config.json")
    }()

    private var saveWork: DispatchWorkItem?

    init() { c = Settings.load() }

    /// Missing keys fall back to defaults, so old config files keep working.
    static func load() -> Config {
        guard let data = try? Data(contentsOf: fileURL),
              let saved = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let defData = try? JSONEncoder().encode(Config()),
              var merged = try? JSONSerialization.jsonObject(with: defData) as? [String: Any]
        else { return Config() }
        for (k, v) in saved {
            if k == "bindings", let sb = v as? [String: Any], var db = merged[k] as? [String: Any] {
                sb.forEach { db[$0] = $1 }
                merged[k] = db
            } else { merged[k] = v }
        }
        guard let m = try? JSONSerialization.data(withJSONObject: merged),
              let cfg = try? JSONDecoder().decode(Config.self, from: m) else { return Config() }
        return cfg
    }

    private func scheduleSave() {
        saveWork?.cancel()
        let w = DispatchWorkItem { [c] in
            // Only store buttons that differ from the defaults, so layout changes shipped in
            // the app aren't masked by a stale snapshot of every button.
            var c = c
            c.bindings = c.bindings.filter { key, m in
                ButtonID(rawValue: key).map { Config.defaultBindings[$0] != m } ?? true
            }
            let enc = JSONEncoder()
            enc.outputFormatting = [.prettyPrinted, .sortedKeys]
            try? enc.encode(c).write(to: Settings.fileURL)
        }
        saveWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: w)
    }
}

/// Live controller readout for the settings window.
final class LiveState: ObservableObject {
    static let shared = LiveState()
    @Published var cursorStick = CGPoint.zero
    @Published var scrollStick = CGPoint.zero
    @Published var cursorSpeed = 0.0
    @Published var pressed: Set<ButtonID> = []
    @Published var tab = "Cursor"
    var watching = false
}
