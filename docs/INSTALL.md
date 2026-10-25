# Installation

## From a release

1. Download [DisplayDeck.dmg](https://github.com/Roadmvn/DisplayDeck/releases/latest/download/DisplayDeck.dmg).
2. Open it and drag **DisplayDeck** into **Applications**.
3. Launch DisplayDeck. It has no Dock icon and only lives in the menu bar.

Each release also ships `DisplayDeck.dmg.sha256` to check the download:

```sh
shasum -a 256 -c DisplayDeck.dmg.sha256
```

### First launch

The app is signed ad hoc and not notarized by Apple, so macOS blocks it the first time:

1. Launch DisplayDeck once and dismiss the warning.
2. Open **System Settings → Privacy & Security** and click **Open Anyway** next to the DisplayDeck message.

Or from a terminal:

```sh
xattr -dr com.apple.quarantine /Applications/DisplayDeck.app
```

### Uninstall

Quit DisplayDeck from its menu, then delete `/Applications/DisplayDeck.app`.

## Building from source

Requires the Xcode command line tools (Swift 6).

```sh
./scripts/build-app.sh   # universal build/DisplayDeck.app, signed ad hoc
./scripts/make-dmg.sh    # rebuilds, then build/DisplayDeck.dmg and its checksum
open build/DisplayDeck.app
```

For a quick debug build: `swift build` then `.build/debug/DisplayDeck`.
