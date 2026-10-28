# Known limitations

- DisplayDeck relies on private Apple APIs (DisplayServices, `OSD.framework`, the CoreGraphics `CGVirtualDisplay` classes, IOKit's `IOAVService`). They are undocumented and may change or disappear with any macOS update.
- For the same reason, it cannot be distributed on the Mac App Store.
- DDC reads have been checked against one external monitor (a Dell P3424WE), which answered brightness, contrast and volume; writes have not been exercised on real hardware. Depending on the monitor and the connection (some docks, adapters and HDMI ports do not pass DDC through), the DDC sliders may not show up or may have no effect.
- Monitors are matched to their DDC channel by the vendor, model and serial number read from the EDID. Two monitors that are identical down to the serial number, or whose EDID cannot be read, may still be matched in the wrong order when more than one of them is connected.
- A virtual display's resolution is chosen when it is created. If it is changed afterwards (for example in System Settings), macOS keeps that display until DisplayDeck quits.
- Software dimming temporarily replaces the calibration curve; it is restored by moving the slider back to the maximum or by quitting the app.
- If a macOS update removes the private `OSD.framework` class behind the HUD, the controls keep working and only the HUD disappears.
- Automatic brightness only appears for displays whose light sensor macOS exposes, which in practice means the built-in display.
