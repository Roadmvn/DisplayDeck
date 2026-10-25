# DisplayDeck

A small macOS menu bar app to control your displays:

- **Brightness** of the built-in display (hardware backlight) and **software dimming** of any display through its gamma table.
- **HiDPI virtual displays** (1920×1080, 2560×1440 and 1440×900 presets, in points), handy for screen recording, screen sharing or layout testing.
- **DDC/CI** for external monitors: brightness and volume set directly on the monitor.
- **Resolution switching** among every available mode, HiDPI included.

## Download

Grab the latest `DisplayDeck-<version>.dmg` from the [Releases](https://github.com/Roadmvn/DisplayDeck/releases) page, open it and drag **DisplayDeck** into **Applications**.

The app is signed ad hoc, not notarized by Apple, so macOS blocks it on first launch. To open it anyway:

1. Launch DisplayDeck once and dismiss the warning.
2. Open **System Settings → Privacy & Security** and click **Open Anyway** next to the DisplayDeck message.

Or from a terminal:

```sh
xattr -dr com.apple.quarantine /Applications/DisplayDeck.app
```

DisplayDeck has no Dock icon: it only lives in the menu bar.

## Requirements

- macOS 13 or later, on Apple Silicon or Intel.
- Apple Silicon for DDC.

## Build from source

Requires the Xcode command line tools (Swift 6).

```sh
./scripts/build-app.sh          # universal build/DisplayDeck.app, signed ad hoc
./scripts/make-dmg.sh           # rebuilds, then build/DisplayDeck-<version>.dmg
open build/DisplayDeck.app
```

For a quick debug build: `swift build` then `.build/debug/DisplayDeck`.

## Releases

Pushing a `v*` tag (for example `v0.2.0`) runs the release workflow: it builds the universal app with that version, packages the DMG with its SHA-256 checksum and publishes them as a GitHub release. Every push and pull request runs the CI build and keeps the DMG as a workflow artifact.

## Limitations

- DisplayDeck relies on private Apple APIs (DisplayServices, the CoreGraphics `CGVirtualDisplay` classes, IOKit's `IOAVService`). They are undocumented and may change or disappear with any macOS update.
- For the same reason, it cannot be distributed on the Mac App Store.
- DDC has not been tested on real hardware yet. Depending on the monitor and the connection (some docks, adapters and HDMI ports do not pass DDC through), the DDC sliders may not show up or may have no effect.
- Two identical monitors may be matched in the wrong order, since matching relies on the vendor and model read from the EDID.
- A virtual display's resolution is chosen when it is created. If it is changed afterwards (for example in System Settings), macOS keeps that display until DisplayDeck quits.
- Software dimming temporarily replaces the calibration curve; it is restored by moving the slider back to the maximum or by quitting the app.
