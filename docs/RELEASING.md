# Releasing

Every push to `main` and every pull request runs the CI workflow on a `macos-26` runner. It builds the universal app and the DMG, verifies the signature, the Info.plist, both architectures and the checksum, and keeps the DMG as a workflow artifact.

To publish a release, push a `v*` tag from `main`:

```sh
git tag -a v0.2.0 -m "DisplayDeck 0.2.0"
git push origin v0.2.0
```

The release workflow stamps the tag version into the app, builds `DisplayDeck.dmg` and `DisplayDeck.dmg.sha256`, and publishes them as a GitHub release. The asset names stay the same across versions, so the download link in the README always points to the latest release.
