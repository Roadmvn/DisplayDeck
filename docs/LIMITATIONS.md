# Known limitations

- DisplayDeck relies on private Apple APIs (DisplayServices, the CoreGraphics `CGVirtualDisplay` classes, IOKit's `IOAVService`). They are undocumented and may change or disappear with any macOS update.
- For the same reason, it cannot be distributed on the Mac App Store.
- DDC has not been tested on real hardware yet. Depending on the monitor and the connection (some docks, adapters and HDMI ports do not pass DDC through), the DDC sliders may not show up or may have no effect.
- Two identical monitors may be matched in the wrong order, since matching relies on the vendor and model read from the EDID.
- A virtual display's resolution is chosen when it is created. If it is changed afterwards (for example in System Settings), macOS keeps that display until DisplayDeck quits.
- Software dimming temporarily replaces the calibration curve; it is restored by moving the slider back to the maximum or by quitting the app.
