# Releasing

Every pull request runs the CI workflow on a `macos-26` runner. It builds the universal app and the DMG, verifies the signature, the Info.plist, both architectures and the checksum, and keeps the DMG as a workflow artifact.

Every push to `main` runs the release workflow. It picks the next version from the commits since the last `v*` tag, following the Conventional Commits prefixes:

| Commits since the last tag | Bump |
|---|---|
| a `!` after the type (`feat!:`, `fix(ddc)!:`) or a `BREAKING CHANGE:` footer | major |
| at least one `feat:` | minor |
| anything else (`fix:`, `docs:`, `ci:`...) | patch |

It stamps that version into the app, builds and verifies `DisplayDeck.dmg` and `DisplayDeck.dmg.sha256`, creates the tag and publishes them as a GitHub release with generated notes. No manual tag is needed. The asset names stay the same across versions, so the download link in the README always points to the latest release.

To see which version the next push to `main` would produce:

```sh
./scripts/next-version.sh
```
