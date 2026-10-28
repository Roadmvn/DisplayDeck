# DisplayDeck

A macOS menu bar app that puts every display control in one panel — brightness, contrast, volume, resolution, and virtual displays — including the controls macOS does not give you for external monitors.

**[Download DisplayDeck.dmg](https://github.com/Roadmvn/DisplayDeck/releases/latest/download/DisplayDeck.dmg)** · [All releases](https://github.com/Roadmvn/DisplayDeck/releases)

Requires macOS 13 or later. Apple Silicon for everything involving an external monitor.

## Why

macOS gives you one brightness slider for the built-in display and nothing for the monitor next to it. Its brightness keys stop at the laptop screen. Changing resolution means opening System Settings, and there is no way to create a scaled HiDPI display at all.

DisplayDeck is one menu bar panel that covers all of it, with no background service, no helper process and no account.

## What it does

### Brightness

| | Built-in display | External monitor |
|---|---|---|
| Hardware brightness | ✅ via `DisplayServices` | ✅ via DDC/CI |
| Keyboard brightness keys | ✅ macOS already does it | ✅ DisplayDeck forwards them |
| Automatic (light sensor) | ✅ where a sensor exists | — no sensor to read |
| Software dimming | ✅ | ✅ works on any display |

The slider tracks the system: press the keyboard keys, let the light sensor move it, change it from another app, and the panel already shows the new value when you open it.

**Software dimming** goes below what the hardware allows by reshaping the display's colour curve, so it works on any display — including one with no DDC at all. It is restored by moving the slider back to the maximum or by quitting the app.

### Image adjustments

Contrast, gamma, colour temperature and colour inversion, on any display, applied on top of the display's own calibration rather than replacing it.

| | |
|---|---|
| **Contrast** | Steepens or flattens the curve around mid grey |
| **Gamma** | Lifts or drops the midtones without moving black or white |
| **Temperature** | Warms or cools by removing from a channel, never by adding, so nothing clips |
| **Invert** | Reverses the curve |

These run through the display's colour table, which curves each channel on its own. That is why there is no saturation, hue or vibrance here: mixing channels is beyond what a per-channel table can express, and would need a compositing layer over the whole screen.

Leaving every adjustment at its neutral position reproduces the display's calibrated table exactly, so opening the panel never changes what you see. **Reset** returns the display to its profile.

### Keyboard brightness keys on external monitors

The brightness keys normally only reach the built-in display. DisplayDeck intercepts them and sends the change over DDC to **the monitor your pointer is on**. If that display has no DDC brightness, the keys are left alone and macOS handles them as usual.

- One press = one notch of the system HUD, the same step macOS uses.
- **Shift + Option** = a quarter notch, again matching macOS.
- The system HUD appears on the monitor being changed.

This needs **Accessibility** permission, because intercepting media keys requires an event tap. The panel has a button that takes you there. Nothing is intercepted until you grant it, and the switch in the panel turns the whole thing off without revoking anything.

### External monitor controls over DDC/CI

Brightness, contrast and volume, spoken directly to the monitor over the display cable — the same controls as the monitor's own on-screen buttons, without the buttons.

A slider only appears if the monitor answers for it. A monitor that does not implement contrast simply shows no contrast slider, instead of a dead one.

Every change raises the same HUD macOS shows for its own brightness and volume keys, which matters when the panel is on a different screen from the monitor you are adjusting.

### Resolution and HiDPI

Every mode the display reports, including the HiDPI modes System Settings hides, with the refresh rate.

### Virtual displays

Create a HiDPI display that does not physically exist — for a screen-sharing target, a scaled workspace, or to park windows. Presets at 1920 × 1080, 2560 × 1440 and 1440 × 900. A virtual display lasts until you remove it or quit.

## Install

Download the DMG and drag DisplayDeck to Applications.

The app is signed ad-hoc, not notarised, so Gatekeeper refuses the first launch. Right-click the app and choose **Open**, or:

```bash
xattr -dr com.apple.quarantine /Applications/DisplayDeck.app
```

To use the keyboard brightness keys, grant Accessibility in **System Settings → Privacy & Security → Accessibility**. The panel links straight there.

## Build from source

```bash
git clone https://github.com/Roadmvn/DisplayDeck.git
cd DisplayDeck
./scripts/build-app.sh      # build/DisplayDeck.app
./scripts/make-dmg.sh       # build/DisplayDeck.dmg
```

Needs Xcode 16 or later for the Swift 6 toolchain. Details in [docs/INSTALL.md](docs/INSTALL.md).

## How it works

DisplayDeck is a SwiftUI `MenuBarExtra` with a thin Objective-C layer over the Apple APIs that have no public equivalent.

| Feature | API |
|---|---|
| Built-in brightness, light sensor | `DisplayServices` (private, loaded at runtime) |
| Brightness change notifications | `DisplayServicesRegisterForBrightnessChangeNotifications` |
| External monitor control | DDC/CI over `IOAVService` — Apple Silicon only |
| Keyboard key interception | `CGEventTap` on system-defined events |
| System HUD | `OSDManager` from `OSD.framework` (private) |
| Software dimming, image adjustments | `CGSetDisplayTransferByTable` |
| Virtual displays | `CGVirtualDisplay` (private CoreGraphics classes) |
| Resolution | `CGDisplayCopyAllDisplayModes` |

Each one is probed before use and degrades on its own: if a private symbol disappears in a macOS update, that single control stops appearing and the rest keeps working.

Monitors are matched to their DDC channel by the vendor, model and serial number in their EDID, falling back to vendor and model when a monitor does not publish its serial the same way on both sides.

## Documentation

- [Installation and building from source](docs/INSTALL.md)
- [Known limitations](docs/LIMITATIONS.md)
- [Releasing](docs/RELEASING.md)
