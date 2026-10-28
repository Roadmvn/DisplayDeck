# Known limitations

- DisplayDeck relies on private Apple APIs (DisplayServices, `OSD.framework`, the CoreGraphics `CGVirtualDisplay` classes, IOKit's `IOAVService`). They are undocumented and may change or disappear with any macOS update.
- For the same reason, it cannot be distributed on the Mac App Store.
- DDC reads have been checked against one external monitor (a Dell P3424WE), which answered brightness, contrast and volume; writes have not been exercised on real hardware. Depending on the monitor and the connection (some docks, adapters and HDMI ports do not pass DDC through), the DDC sliders may not show up or may have no effect.
- Monitors are matched to their DDC channel by the vendor, model and serial number read from the EDID. Two monitors that are identical down to the serial number, or whose EDID cannot be read, may still be matched in the wrong order when more than one of them is connected.
- A virtual display's resolution is chosen when it is created. If it is changed afterwards (for example in System Settings), macOS keeps that display until DisplayDeck quits.
- Software dimming and the image adjustments temporarily replace the display's colour table; they are restored by Reset, by returning every control to neutral, or by quitting the app.
- The image adjustments curve each channel on its own, which is all a display colour table can do. Saturation, hue and vibrance need the channels mixed together and are therefore not available through this mechanism.
- Any app that writes the display's colour table — another display utility, a calibration tool, a game — overwrites these adjustments. DisplayDeck reapplies them when displays are reconfigured, not continuously.
- If a macOS update removes the private `OSD.framework` class behind the HUD, the controls keep working and only the HUD disappears.
- Automatic brightness only appears for displays whose light sensor macOS exposes, which in practice means the built-in display.
- The bottom of a DDC brightness slider is the monitor's lowest backlight, not darkness. Turning a monitor off is a separate command, which only appears for monitors that answer for it.
- Turning a monitor off over DDC leaves macOS believing it is still connected, so it keeps drawing to it and will not wake it on its own. Turn it back on from the panel, or from the monitor's own buttons.
- The keyboard brightness keys act on the display the pointer is on. A background app with no window has no better signal about which display you are looking at.
- Intercepting the brightness keys needs Accessibility permission, and macOS ties that permission to the app's signature. The DMG is signed ad-hoc, so **every update invalidates the grant**: the signature hash is reproducible for identical sources but changes with any code change. The old entry remains in the Accessibility list and looks granted, while the event tap is refused. Removing the entry and adding the new copy restores it. A real signing identity would make the grant survive updates.
- The event tap is removed by macOS if the app ever stops answering it in time. It is re-enabled automatically, but a keypress may be missed when that happens.
