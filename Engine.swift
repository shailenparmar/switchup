// Engine — GameController in, CGEvent out. Reads Settings.shared.c live.

import AppKit
import ApplicationServices
import GameController
import IOKit.hid

enum Key {
    static let left: CGKeyCode = 123, right: CGKeyCode = 124, down: CGKeyCode = 125, up: CGKeyCode = 126
    static let a: CGKeyCode = 0, f: CGKeyCode = 3, c: CGKeyCode = 8, w: CGKeyCode = 13, t: CGKeyCode = 17
    static let rightBracket: CGKeyCode = 30, leftBracket: CGKeyCode = 33, l: CGKeyCode = 37, j: CGKeyCode = 38
    static let k: CGKeyCode = 40, comma: CGKeyCode = 43, m: CGKeyCode = 46, period: CGKeyCode = 47
    static let ret: CGKeyCode = 36, tab: CGKeyCode = 48, space: CGKeyCode = 49, escape: CGKeyCode = 53
    static let rightCommand: CGKeyCode = 54, leftCommand: CGKeyCode = 55
    static let delete: CGKeyCode = 51
    static let pageUp: CGKeyCode = 116, pageDown: CGKeyCode = 121, f11: CGKeyCode = 103
}

// NX_KEYTYPE_* media keys
enum Media: Int {
    case volumeUp = 0, volumeDown = 1, mute = 7, play = 16, next = 17, previous = 18
}

// MARK: - Event synthesis

final class Synth {
    let src = CGEventSource(stateID: .hidSystemState)
    private var lastDown = Date.distantPast
    private var lastDownPoint = CGPoint.zero
    private var clickCount = 1

    var cursor: CGPoint { CGEvent(source: nil)?.location ?? .zero }

    func move(to p: CGPoint, leftHeld: Bool) {
        guard let e = CGEvent(mouseEventSource: src, mouseType: leftHeld ? .leftMouseDragged : .mouseMoved,
                              mouseCursorPosition: p, mouseButton: .left) else { return }
        e.flags = []
        e.post(tap: .cghidEventTap)
    }

    func mouse(_ button: CGMouseButton, down: Bool, flags: CGEventFlags = []) {
        let p = cursor
        let type: CGEventType = switch (button, down) {
        case (.left, true): .leftMouseDown
        case (.left, false): .leftMouseUp
        case (.right, true): .rightMouseDown
        case (.right, false): .rightMouseUp
        case (_, true): .otherMouseDown
        case (_, false): .otherMouseUp
        }
        if down {
            let now = Date()
            let close = hypot(p.x - lastDownPoint.x, p.y - lastDownPoint.y) < 6
            clickCount = (now.timeIntervalSince(lastDown) < NSEvent.doubleClickInterval && close) ? clickCount + 1 : 1
            lastDown = now
            lastDownPoint = p
        }
        guard let e = CGEvent(mouseEventSource: src, mouseType: type, mouseCursorPosition: p, mouseButton: button)
        else { return }
        e.setIntegerValueField(.mouseEventClickState, value: Int64(clickCount))
        // Always explicit: the shared source remembers ⌃ from ⌃⇥/⌃← taps, and ⌃-click = right click.
        e.flags = flags
        e.post(tap: .cghidEventTap)
    }

    func doubleClick() {
        let p = cursor
        for state in [1, 2] as [Int64] {
            for type in [CGEventType.leftMouseDown, .leftMouseUp] {
                guard let e = CGEvent(mouseEventSource: src, mouseType: type, mouseCursorPosition: p, mouseButton: .left)
                else { continue }
                e.setIntegerValueField(.mouseEventClickState, value: state)
                e.flags = []
                e.post(tap: .cghidEventTap)
            }
        }
        lastDown = .distantPast   // don't let the next A press count as a triple-click
    }

    func scroll(dy: Int32, dx: Int32) {
        guard let e = CGEvent(scrollWheelEvent2Source: src, units: .pixel, wheelCount: 2,
                              wheel1: dy, wheel2: dx, wheel3: 0) else { return }
        e.flags = []   // a leftover ⌃ would turn scrolling into zoom
        e.post(tap: .cghidEventTap)
    }

    /// Trackpad-style scroll: a phased scroll event plus a gesture event, the way
    /// an Apple trackpad sends them (recipe from Mac Mouse Fix's GestureScrollSimulator).
    /// phase: 1 began, 2 changed, 4 ended (0 = none). momentum: 1 begin, 2 continue, 3 end.
    func gestureScroll(dx: Double, dy: Double, phase: Int64, momentum: Int64 = 0) {
        func f(_ r: UInt32) -> CGEventField { CGEventField(rawValue: r)! }
        func lineInt(_ v: Double) -> Int64 { Int64(abs(v) <= 1 ? (v < 0 ? floor(v) : ceil(v)) : (v < 0 ? ceil(v) : floor(v))) }
        let s = CGEvent(source: nil)!
        s.setIntegerValueField(f(55), value: 22)                 // scroll wheel
        s.setIntegerValueField(f(88), value: 1)                  // continuous
        s.setIntegerValueField(f(137), value: naturalScrolling ? 1 : 0)
        let ly = dy / 10, lx = dx / 10
        s.setIntegerValueField(f(11), value: lineInt(ly)); s.setIntegerValueField(f(96), value: Int64(dy))
        s.setIntegerValueField(f(93), value: Int64(ly * 65536))
        s.setIntegerValueField(f(12), value: lineInt(lx)); s.setIntegerValueField(f(97), value: Int64(dx))
        s.setIntegerValueField(f(94), value: Int64(lx * 65536))
        s.setIntegerValueField(f(99), value: phase)
        s.setIntegerValueField(f(123), value: momentum)
        s.flags = []
        s.post(tap: .cgSessionEventTap)
        guard phase != 0 else { return }
        let g = CGEvent(source: nil)!
        g.setIntegerValueField(f(55), value: 29)                 // gesture
        g.setIntegerValueField(f(110), value: 6)                 // HID scroll
        g.setDoubleValueField(f(116), value: dx == 0 ? -0.0 : dx * 1.67)
        g.setDoubleValueField(f(119), value: dy == 0 ? -0.0 : dy * 1.67)
        g.setIntegerValueField(f(132), value: phase)
        g.post(tap: .cgSessionEventTap)
    }

    let naturalScrolling = UserDefaults.standard.persistentDomain(forName: UserDefaults.globalDomain)?["com.apple.swipescrolldirection"] as? Bool ?? true

    func key(_ code: CGKeyCode, flags: CGEventFlags = [], down: Bool) {
        guard let e = CGEvent(keyboardEventSource: src, virtualKey: code, keyDown: down) else { return }
        var f = flags
        // Real arrow-key events carry these; Spaces switching wants them.
        if (Key.left...Key.up).contains(code) { f.formUnion([.maskSecondaryFn, .maskNumericPad]) }
        e.flags = f
        e.post(tap: .cghidEventTap)
    }

    func tap(_ code: CGKeyCode, flags: CGEventFlags = []) {
        key(code, flags: flags, down: true)
        key(code, flags: flags, down: false)
    }

    /// A bare modifier press/release (flagsChanged), with left/right device bits.
    func command(down: Bool, right: Bool = false) {
        guard let e = CGEvent(keyboardEventSource: src, virtualKey: right ? Key.rightCommand : Key.leftCommand,
                              keyDown: down) else { return }
        e.type = .flagsChanged
        e.flags = down ? CGEventFlags(rawValue: CGEventFlags.maskCommand.rawValue | (right ? 0x10 : 0x08)) : []
        e.post(tap: .cghidEventTap)
    }

    func media(_ key: Media) {
        for down in [true, false] {
            let state = down ? 0xA : 0xB
            NSEvent.otherEvent(with: .systemDefined, location: .zero,
                               modifierFlags: NSEvent.ModifierFlags(rawValue: UInt(state << 8)),
                               timestamp: 0, windowNumber: 0, context: nil, subtype: 8,
                               data1: (key.rawValue << 16) | (state << 8), data2: -1)?
                .cgEvent?.post(tap: .cghidEventTap)
        }
    }
}

// MARK: - Engine

final class SwitchUp {
    let synth = Synth()
    let settings = Settings.shared
    let live = LiveState.shared
    var c: Config { settings.c }

    var enabled = true { didSet { updateLights(); if !enabled { releaseAll() }; onChange?() } }
    var precisionToggled = false
    var onChange: (() -> Void)?

    private(set) var controller: GCController?
    private var timer: Timer?
    private var timerHz = 0.0
    private var leftHolders = 0
    private var precisionHeld = false, turboHeld = false, scrollModeHeld = false
    private var pos: CGPoint?
    private var velocity = CGPoint.zero
    private var fullTiltTime = 0.0
    private var scrollRemainder = CGPoint.zero
    private var active: [ButtonID: Mapping] = [:]      // what each held button is doing
    private var repeaters: [ButtonID: Timer] = [:]
    private var switcherOpen = false
    private var switcherCommit: DispatchWorkItem?
    private var tickCount = 0
    private var dictationPressedAt: Date?
    private var hidManager: IOHIDManager?
    private let hidBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 512)
    private var homeDown = false
    private var gestureActive = false, momentumActive = false, momentumStarted = false
    private var lastScrollVelocity = CGPoint.zero, momentumVelocity = CGPoint.zero

    func start() {
        GCController.shouldMonitorBackgroundEvents = true
        let nc = NotificationCenter.default
        nc.addObserver(forName: .GCControllerDidConnect, object: nil, queue: .main) { [weak self] n in
            if let ctl = n.object as? GCController { self?.attach(ctl) }
        }
        nc.addObserver(forName: .GCControllerDidDisconnect, object: nil, queue: .main) { [weak self] n in
            guard let self, (n.object as? GCController) === self.controller else { return }
            self.controller = nil
            self.releaseAll()
            if let next = GCController.controllers().first(where: { $0.extendedGamepad != nil }) {
                self.attach(next)
            } else { self.onChange?() }
        }
        GCController.startWirelessControllerDiscovery {}
        if let ctl = GCController.controllers().first(where: { $0.extendedGamepad != nil }) { attach(ctl) }
        restartTimer()
        startRawHome()
    }

    /// macOS keeps the Home button for itself (it never reaches GameController apps),
    /// so read it straight from the Pro Controller's HID reports: report 0x30, byte 4, bit 0x10.
    private func startRawHome() {
        let m = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        IOHIDManagerSetDeviceMatching(m, [kIOHIDVendorIDKey: 0x057E, kIOHIDProductIDKey: 0x2009] as CFDictionary)
        let ctx = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(m, { ctx, _, _, device in
            guard let ctx else { return }
            let me = Unmanaged<SwitchUp>.fromOpaque(ctx).takeUnretainedValue()
            IOHIDDeviceRegisterInputReportCallback(device, me.hidBuffer, 512, { ctx, _, _, _, id, report, length in
                guard let ctx, id == 0x30, length >= 6 else { return }
                Unmanaged<SwitchUp>.fromOpaque(ctx).takeUnretainedValue().homeChanged(report[4] & 0x10 != 0)
            }, ctx)
        }, ctx)
        IOHIDManagerScheduleWithRunLoop(m, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        IOHIDManagerOpen(m, IOOptionBits(kIOHIDOptionsTypeNone))
        hidManager = m
    }

    /// Both the raw reader and GameController feed Home through here; only edges count.
    private func homeChanged(_ down: Bool) {
        guard down != homeDown else { return }
        homeDown = down
        handle(.home, down)
    }

    private func restartTimer() {
        timer?.invalidate()
        timerHz = min(max(c.pollHz, 30), 500)
        let t = Timer(timeInterval: 1 / timerHz, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func element(_ id: ButtonID, _ p: GCExtendedGamepad) -> GCControllerButtonInput? {
        switch id {
        case .a: p.buttonA; case .b: p.buttonB; case .x: p.buttonX; case .y: p.buttonY
        case .l: p.leftShoulder; case .r: p.rightShoulder; case .zl: p.leftTrigger; case .zr: p.rightTrigger
        case .plus: p.buttonMenu; case .minus: p.buttonOptions; case .home: p.buttonHome
        case .capture: p.buttons[GCInputButtonShare]
        case .l3: p.leftThumbstickButton; case .r3: p.rightThumbstickButton
        case .dpadUp: p.dpad.up; case .dpadDown: p.dpad.down; case .dpadLeft: p.dpad.left; case .dpadRight: p.dpad.right
        }
    }

    private func attach(_ ctl: GCController) {
        guard let pad = ctl.extendedGamepad else { return }
        controller = ctl
        pad.buttonHome?.preferredSystemGestureState = .disabled
        pad.buttons[GCInputButtonShare]?.preferredSystemGestureState = .disabled
        for id in ButtonID.allCases {
            element(id, pad)?.pressedChangedHandler = { [weak self] _, _, pressed in
                id == .home ? self?.homeChanged(pressed) : self?.handle(id, pressed)
            }
        }
        updateLights()
        onChange?()
    }

    // MARK: Buttons

    private func handle(_ id: ButtonID, _ pressed: Bool) {
        if pressed { live.pressed.insert(id) } else { live.pressed.remove(id) }

        guard pressed else {
            stopRepeat(id)
            if let m = active.removeValue(forKey: id) { perform(m, pressed: false) }
            return
        }
        let m = c.mapping(id)
        guard enabled || m.action == .pauseSwitchUp else { return }

        // Any other button while ⌘⇥ is open commits the switch and is swallowed.
        if switcherOpen, m.action != .appSwitchNext, m.action != .appSwitchPrev {
            commitSwitcher()
            return
        }

        active[id] = m
        perform(m, pressed: true)
        if m.action.repeats { startRepeat(id, m) }
    }

    private func startRepeat(_ id: ButtonID, _ m: Mapping) {
        stopRepeat(id)
        let delay = Timer(timeInterval: max(c.repeatDelay, 0.05), repeats: false) { [weak self] _ in
            guard let self else { return }
            let r = Timer(timeInterval: max(self.c.repeatInterval, 0.01), repeats: true) { [weak self] _ in
                self?.perform(m, pressed: true)
            }
            RunLoop.main.add(r, forMode: .common)
            self.repeaters[id] = r
        }
        RunLoop.main.add(delay, forMode: .common)
        repeaters[id] = delay
    }

    private func stopRepeat(_ id: ButtonID) {
        repeaters.removeValue(forKey: id)?.invalidate()
    }

    private func perform(_ m: Mapping, pressed down: Bool) {
        // Hold-style actions: act on press and release.
        switch m.action {
        case .leftClick:
            let before = leftHolders
            leftHolders = max(0, leftHolders + (down ? 1 : -1))
            if before == 0, leftHolders == 1 { synth.mouse(.left, down: true) }
            if before > 0, leftHolders == 0 { synth.mouse(.left, down: false) }
            return
        case .rightClick: synth.mouse(.right, down: down); return
        case .middleClick: synth.mouse(.center, down: down); return
        case .openLinkNewTab: synth.mouse(.left, down: down, flags: [.maskCommand, .maskShift]); return
        case .openLinkBackground: synth.mouse(.left, down: down, flags: .maskCommand); return
        case .dictationHold:
            if down {
                if isDictating() {
                    // Already listening (e.g. after a tap): this press stops it.
                    dictationPressedAt = nil
                    stopDictation()
                } else {
                    dictationPressedAt = Date()
                    startDictation()
                }
            } else if let t = dictationPressedAt {
                dictationPressedAt = nil
                // Held = push-to-talk, stop on release. A quick tap leaves it running until the next press.
                if Date().timeIntervalSince(t) >= c.dictationHoldThreshold { stopDictation() }
            }
            return
        case .precisionHold: precisionHeld = down; return
        case .turboHold: turboHeld = down; return
        case .scrollModeHold: scrollModeHeld = down; return
        case .customShortcut:
            synth.key(m.keyCode, flags: CGEventFlags(rawValue: m.modifiers), down: down); return
        default: break
        }
        guard down else { return }

        switch m.action {
        case .back: synth.tap(Key.leftBracket, flags: .maskCommand)
        case .forward: synth.tap(Key.rightBracket, flags: .maskCommand)
        case .nextTab: synth.tap(Key.tab, flags: .maskControl)
        case .prevTab: synth.tap(Key.tab, flags: [.maskControl, .maskShift])
        case .closeTab: synth.tap(Key.w, flags: .maskCommand)
        case .closeWindow: synth.tap(Key.w, flags: [.maskCommand, .maskShift])
        case .addressBar: synth.tap(Key.l, flags: .maskCommand)
        case .spotlight: toggleSpotlight()
        case .doubleClick: synth.doubleClick()
        case .reopenTab: synth.tap(Key.t, flags: [.maskCommand, .maskShift])
        case .ytPlayPause: synth.tap(Key.k)
        case .ytFullscreen: synth.tap(Key.f)
        case .ytSeekBack: synth.tap(Key.j)
        case .ytSeekForward: synth.tap(Key.l)
        case .ytCaptions: synth.tap(Key.c)
        case .ytMute: synth.tap(Key.m)
        case .ytFaster: synth.tap(Key.period, flags: .maskShift)
        case .ytSlower: synth.tap(Key.comma, flags: .maskShift)
        case .space: synth.tap(Key.space)
        case .enter: synth.tap(Key.ret)
        case .escape: synth.tap(Key.escape)
        case .tab: synth.tap(Key.tab)
        case .backspace: synth.tap(Key.delete)
        case .deleteWord: synth.tap(Key.delete, flags: .maskAlternate)
        case .arrowUp: synth.tap(Key.up)
        case .arrowDown: synth.tap(Key.down)
        case .arrowLeft: synth.tap(Key.left)
        case .arrowRight: synth.tap(Key.right)
        case .pageUp: synth.tap(Key.pageUp)
        case .pageDown: synth.tap(Key.pageDown)
        case .desktopPrev: synth.tap(Key.left, flags: .maskControl)
        case .desktopNext: synth.tap(Key.right, flags: .maskControl)
        case .missionControl: NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Mission Control.app"))
        case .appWindows: synth.tap(Key.down, flags: .maskControl)
        case .showDesktop: synth.tap(Key.f11, flags: .maskSecondaryFn)
        case .dictation: isDictating() ? stopDictation() : startDictation()
        case .appSwitchNext: switcherStep(back: false)
        case .appSwitchPrev: switcherStep(back: true)
        case .lastApp: synth.tap(Key.tab, flags: .maskCommand)
        case .mediaPlayPause: synth.media(.play)
        case .mediaNext: synth.media(.next)
        case .mediaPrev: synth.media(.previous)
        case .volumeUp: synth.media(.volumeUp)
        case .volumeDown: synth.media(.volumeDown)
        case .mute: synth.media(.mute)
        case .precisionToggle: precisionToggled.toggle()
        case .pauseSwitchUp: enabled.toggle()
        default: break
        }
    }

    // MARK: Spotlight

    /// A synthetic ⌘Space opens Spotlight but doesn't close it the way the real key does,
    /// so close it with Esc (twice if the first only cleared the query).
    private func toggleSpotlight() {
        guard spotlightVisible() else { synth.tap(Key.space, flags: .maskCommand); return }
        synth.tap(Key.escape)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            if self?.spotlightVisible() == true { self?.synth.tap(Key.escape) }
        }
    }

    private func spotlightVisible() -> Bool {
        let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
        return windows.contains { w in
            (w[kCGWindowOwnerName as String] as? String) == "Spotlight"
                && (w[kCGWindowAlpha as String] as? Double ?? 0) > 0
                && ((w[kCGWindowBounds as String] as? [String: Any])?["Height"] as? Double ?? 0) > 30
        }
    }

    // MARK: App switcher (⌘ held virtually across presses)

    private func switcherStep(back: Bool) {
        if !switcherOpen {
            synth.command(down: true)
            switcherOpen = true
        }
        synth.tap(Key.tab, flags: back ? [.maskCommand, .maskShift] : .maskCommand)
        switcherCommit?.cancel()
        let w = DispatchWorkItem { [weak self] in self?.commitSwitcher() }
        switcherCommit = w
        DispatchQueue.main.asyncAfter(deadline: .now() + max(c.switcherCommitDelay, 0.1), execute: w)
    }

    private func commitSwitcher() {
        switcherCommit?.cancel()
        switcherCommit = nil
        guard switcherOpen else { return }
        switcherOpen = false
        synth.command(down: false)
    }

    // MARK: Dictation

    func startDictation() {
        guard c.dictationMethod != .doubleCommand else { doubleCommand(); return }
        if pressDictationMenuItem("Start Dictation") { return }
        let titles = dictationMenuTitles()
        if titles.contains(where: { $0.hasPrefix("Cancel Dictation") }) {
            // macOS sometimes hangs on "Cancel Dictation" after a session ends, with no Start
            // item until it clears. Cancel the stale session, then start once the menu updates.
            _ = pressDictationMenuItem("Cancel Dictation")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                _ = self?.pressDictationMenuItem("Start Dictation")
            }
        } else if titles.isEmpty, c.dictationMethod == .menuThenCommand {
            doubleCommand()   // app has no Dictation menu at all
        }
    }

    func stopDictation() {
        switch c.dictationMethod {
        case .doubleCommand: doubleCommand()
        case .menuItem: _ = pressDictationMenuItem("Stop Dictation")
        case .menuThenCommand:
            if !pressDictationMenuItem("Stop Dictation"), dictationMenuTitles().isEmpty { doubleCommand() }
        }
    }

    /// Menu methods can see state: the Edit menu says "Stop Dictation" while listening.
    /// (⌘⌘ is a blind toggle, so with that method every press just toggles.)
    private func isDictating() -> Bool {
        c.dictationMethod != .doubleCommand && dictationMenuTitles().contains { $0.hasPrefix("Stop Dictation") }
    }

    private func doubleCommand() {
        let hold = c.dictationTapHoldMs / 1000, gap = c.dictationTapGapMs / 1000
        let right = c.dictationRightCommand
        var t = 0.0
        for _ in 0..<2 {
            DispatchQueue.main.asyncAfter(deadline: .now() + t) { [synth] in synth.command(down: true, right: right) }
            t += hold
            DispatchQueue.main.asyncAfter(deadline: .now() + t) { [synth] in synth.command(down: false, right: right) }
            t += gap
        }
    }

    /// The frontmost app's dictation menu items ("Start Dictation…" / "Stop Dictation").
    /// Only the Edit menu is read: walking every menu (Chrome's Bookmarks, History…) can take
    /// seconds, which made presses look ignored. Each query is capped at 0.5 s.
    private func dictationMenuItems() -> [(title: String, item: AXUIElement, enabled: Bool)] {
        guard let app = NSWorkspace.shared.frontmostApplication else { return [] }
        let ax = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(ax, 0.5)
        guard let bar: AXUIElement = attr(ax, kAXMenuBarAttribute),
              let top: [AXUIElement] = attr(bar, kAXChildrenAttribute) else { return [] }
        let edit = top.first { (attr($0, kAXTitleAttribute) as String?) == "Edit" }
        var found: [(String, AXUIElement, Bool)] = []
        for barItem in edit.map({ [$0] }) ?? top {
            guard let menus: [AXUIElement] = attr(barItem, kAXChildrenAttribute) else { continue }
            for menu in menus {
                for item in (attr(menu, kAXChildrenAttribute) as [AXUIElement]?) ?? [] {
                    if let t: String = attr(item, kAXTitleAttribute), t.contains("Dictation") {
                        found.append((t, item, (attr(item, kAXEnabledAttribute) as Bool?) ?? true))
                    }
                }
            }
            if !found.isEmpty { break }
        }
        return found
    }

    private func dictationMenuTitles() -> [String] { dictationMenuItems().map(\.title) }

    /// Presses the enabled menu item starting with `prefix`; false if missing or greyed out.
    private func pressDictationMenuItem(_ prefix: String) -> Bool {
        guard let hit = dictationMenuItems().first(where: { $0.title.hasPrefix(prefix) }), hit.enabled
        else { return false }
        return AXUIElementPerformAction(hit.item, kAXPressAction as CFString) == .success
    }

    private func attr<T>(_ el: AXUIElement, _ name: String) -> T? {
        var v: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, name as CFString, &v) == .success else { return nil }
        return v as? T
    }

    // MARK: State

    private func releaseAll() {
        for (id, m) in active { stopRepeat(id); perform(m, pressed: false) }
        active.removeAll()
        if leftHolders > 0 { leftHolders = 0; synth.mouse(.left, down: false) }
        commitSwitcher()
        precisionHeld = false; turboHeld = false; scrollModeHeld = false
    }

    func updateLights() {
        controller?.playerIndex = (enabled && c.playerLED) ? .index1 : .indexUnset
    }

    // MARK: Sticks

    private func vector(_ x: Double, _ y: Double, shape: DeadzoneShape, _ f: (Double) -> Double) -> CGPoint {
        switch shape {
        case .radial:
            let m = hypot(x, y)
            guard m > 0 else { return .zero }
            let s = f(min(m, 1)) / m
            return CGPoint(x: x * s, y: y * s)
        case .axial:
            return CGPoint(x: (x < 0 ? -1 : 1) * f(abs(x)), y: (y < 0 ? -1 : 1) * f(abs(y)))
        }
    }

    private func tick() {
        if abs(c.pollHz - timerHz) > 0.5 { restartTimer() }
        guard let pad = controller?.extendedGamepad else { return }
        let cfg = c
        let dt = 1 / timerHz
        let cs = cfg.swapSticks ? pad.rightThumbstick : pad.leftThumbstick
        let ss = cfg.swapSticks ? pad.leftThumbstick : pad.rightThumbstick
        let cx = Double(cs.xAxis.value), cy = Double(cs.yAxis.value)
        var sx = Double(ss.xAxis.value), sy = Double(ss.yAxis.value)

        tickCount += 1
        if live.watching, tickCount % 4 == 0 {
            live.cursorStick = CGPoint(x: cx, y: cy)
            live.scrollStick = CGPoint(x: sx, y: sy)
        }
        guard enabled else { return }

        // Scroll-mode: the cursor stick scrolls instead.
        var cursorX = cx, cursorY = cy
        if scrollModeHeld { sx = cx; sy = cy; cursorX = 0; cursorY = 0 }

        // Cursor
        var target = vector(cursorX, cursorY, shape: cfg.cursorDeadzoneShape, cfg.cursorResponse)
        let m = cfg.cursorDeadzoneShape == .radial ? hypot(cursorX, cursorY) : max(abs(cursorX), abs(cursorY))
        fullTiltTime = m >= cfg.cursorOuterDeadzone ? fullTiltTime + dt : 0
        var mult = (precisionToggled != precisionHeld) ? cfg.precisionMultiplier : 1
        if turboHeld { mult *= cfg.turboHoldMultiplier }
        if cfg.turboMultiplier > 1 {
            mult *= 1 + (cfg.turboMultiplier - 1) * min(fullTiltTime / max(cfg.turboRampTime, 0.001), 1)
        }
        target.x *= mult; target.y *= mult * (cfg.cursorInvertY ? -1 : 1)
        let sm = min(max(cfg.cursorSmoothing, 0), 0.98)
        velocity = CGPoint(x: velocity.x * sm + target.x * (1 - sm), y: velocity.y * sm + target.y * (1 - sm))
        if hypot(velocity.x, velocity.y) < 0.5 { velocity = .zero }
        if live.watching, tickCount % 4 == 0 { live.cursorSpeed = hypot(velocity.x, velocity.y) }

        if velocity != .zero {
            let actual = synth.cursor
            var p = pos ?? actual
            if hypot(p.x - actual.x, p.y - actual.y) > 1.5 { p = actual }   // trackpad moved it
            let next = clamp(CGPoint(x: p.x + velocity.x * dt, y: p.y - velocity.y * dt), from: p)
            pos = next
            synth.move(to: next, leftHeld: leftHolders > 0)
        } else {
            pos = nil
        }

        // Scroll
        let sv = vector(sx, sy, shape: .radial, cfg.scrollResponse)
        if cfg.scrollStyle == .trackpad {
            trackpadScroll(sv, dt: dt, cfg: cfg)
        } else if sv != .zero {
            scrollRemainder.x += (cfg.scrollHorizontal ? -sv.x : 0) * dt * (cfg.scrollInvertX ? -1 : 1)
            scrollRemainder.y += sv.y * dt * (cfg.scrollInvertY ? -1 : 1)
            let dx = scrollRemainder.x.rounded(.towardZero), dy = scrollRemainder.y.rounded(.towardZero)
            scrollRemainder.x -= dx; scrollRemainder.y -= dy
            if dx != 0 || dy != 0 { synth.scroll(dy: Int32(dy), dx: Int32(dx)) }
        } else {
            scrollRemainder = .zero
        }
    }

    /// Stick = two fingers: deflecting starts a gesture, centering ends it (then momentum).
    /// Both axes act like a wheel: stick → reveals content to the right, stick ↑ scrolls up.
    /// So stick ← is the two-finger swipe right (dismisses notifications, Back in browsers).
    private func trackpadScroll(_ sv: CGPoint, dt: Double, cfg: Config) {
        let vx = (cfg.scrollHorizontal ? -sv.x : 0) * (cfg.scrollInvertX ? -1 : 1)
        let vy = sv.y * (cfg.scrollInvertY ? -1 : 1)

        func take(_ v: CGPoint) -> (Double, Double) {
            scrollRemainder.x += v.x * dt; scrollRemainder.y += v.y * dt
            let dx = scrollRemainder.x.rounded(.towardZero), dy = scrollRemainder.y.rounded(.towardZero)
            scrollRemainder.x -= dx; scrollRemainder.y -= dy
            return (dx, dy)
        }

        if vx != 0 || vy != 0 {
            if momentumActive {
                if momentumStarted { synth.gestureScroll(dx: 0, dy: 0, phase: 0, momentum: 3) }
                momentumActive = false
            }
            lastScrollVelocity = CGPoint(x: vx, y: vy)
            let (dx, dy) = take(lastScrollVelocity)
            guard dx != 0 || dy != 0 else { return }            // real trackpads never send empty deltas
            synth.gestureScroll(dx: dx, dy: dy, phase: gestureActive ? 2 : 1)
            gestureActive = true
        } else if gestureActive {
            synth.gestureScroll(dx: 0, dy: 0, phase: 4)
            gestureActive = false
            scrollRemainder = .zero
            if cfg.scrollMomentum {
                momentumVelocity = lastScrollVelocity
                momentumActive = true
                momentumStarted = false
            }
        } else if momentumActive {
            let k = pow(min(max(cfg.momentumDecay, 0), 0.999), dt * 120)
            momentumVelocity = CGPoint(x: momentumVelocity.x * k, y: momentumVelocity.y * k)
            if hypot(momentumVelocity.x, momentumVelocity.y) < 40 {
                if momentumStarted { synth.gestureScroll(dx: 0, dy: 0, phase: 0, momentum: 3) }
                momentumActive = false
                scrollRemainder = .zero
                return
            }
            let (dx, dy) = take(momentumVelocity)
            guard dx != 0 || dy != 0 else { return }
            synth.gestureScroll(dx: dx, dy: dy, phase: 0, momentum: momentumStarted ? 2 : 1)
            momentumStarted = true
        }
    }

    // Keep the cursor on some display (handles multi-monitor layouts).
    private func clamp(_ p: CGPoint, from old: CGPoint) -> CGPoint {
        var ids = [CGDirectDisplayID](repeating: 0, count: 16)
        var n: UInt32 = 0
        CGGetActiveDisplayList(16, &ids, &n)
        let rects = ids.prefix(Int(n)).map { CGDisplayBounds($0) }
        if rects.contains(where: { $0.contains(p) }) { return p }
        let home = rects.first { $0.contains(old) } ?? rects.first ?? .zero
        return CGPoint(x: min(max(p.x, home.minX), home.maxX - 1), y: min(max(p.y, home.minY), home.maxY - 1))
    }
}
