# SwitchUp

A macOS menu-bar app that turns a Nintendo Switch Pro Controller into a mouse, trackpad and remote.

**Download:** [shailenparmar.com/switchup](https://shailenparmar.com/switchup/) (notarized, macOS 14+, Apple Silicon & Intel)

- Left stick moves the pointer; right stick scrolls like two fingers on a trackpad (with momentum and swipe gestures)
- Every button is remappable: clicks, tabs, desktops, ⌘⇥ app switching, Spotlight, dictation, delete-word, and more
- Tunable response curves (speed, exponent, dead zones, smoothing), all live in Settings
- First-launch setup window for Bluetooth, Accessibility and the Home button

## Build

```sh
./build.sh      # dev build → ~/Applications/SwitchUp.app
./release.sh    # Developer ID sign + notarize → dist/SwitchUp.zip
```

Plain Swift, no Xcode project: `main.swift` (menu bar, windows), `Engine.swift` (GameController → CGEvent),
`Config.swift` (settings + actions), `SettingsView.swift`, `SetupView.swift`.
Settings are saved to `~/Library/Application Support/SwitchUp/config.json`.

Notes: macOS keeps the controller's Home button for itself, so SwitchUp reads it straight from the
Pro Controller's HID reports. Trackpad-style scrolling uses the gesture-event recipe from
[Mac Mouse Fix](https://github.com/noah-nuebling/mac-mouse-fix).
