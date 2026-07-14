# MacZoomer

A native macOS screen-zoom, annotation, screenshot, and recording tool for technical presentations and demos. Inspired by [Sysinternals ZoomIt](https://learn.microsoft.com/sysinternals/downloads/zoomit) — reimplemented from scratch for macOS.

> **Status:** 🛠 Pre-release. Zoom, Live Zoom, Drawing, Screenshots, the Break Timer, and Screen Recording are functional. Builds are now signed with Developer ID and notarized by Apple, with auto-updates via Sparkle.

## Features

| Feature | Default shortcut | Status |
| --- | --- | --- |
| Zoom Mode (freeze + magnify) | ⌘1 | ✅ |
| Drawing & Annotation (pens, highlighter, blur, shapes, text, whiteboard) | ⌘2 | ✅ |
| Break Timer (full-screen countdown) | ⌘3 | ✅ |
| Live Zoom (real-time magnification with pan) | ⌘4 | ✅ |
| Live Draw (annotate the live desktop) | ⌘⇧4 | ✅ |
| Copy / save full screen or region as PNG | ⌘6 / ⌘⇧6 / ⌘⌃6 / ⌘⇧⌃6 | ✅ |
| Screen Recording (MP4) | ⌘5 / ⌘⇧5 / ⌘⌥5 | ✅ |
| Auto-update via Sparkle + signed/notarized DMG | — | ✅ |

Every shortcut is rebindable in Settings → Hotkeys. Settings can be exported/imported as JSON.

While drawing (⌘2), press **H** for an on-screen hub listing every tool, color, and modifier.

Out of scope for v1: OCR, DemoType, panorama recording, audio in recordings (deferred to v1.1).

## Requirements

- macOS 14 Sonoma or newer
- Apple Silicon or Intel Mac
- Screen Recording permission (granted on first use; needed for zoom, screenshots, and recording)

## Building from source

```sh
# Install build tools (one-time)
brew install xcodegen

# Generate the Xcode project
make generate

# Build & run via Xcode
open MacZoomer.xcodeproj

# OR build via SwiftPM (no Xcode needed for compile-checking)
swift build
```

A Developer-ID-signed, notarized Release `.app` + DMG for local distribution
(requires the Developer ID Application certificate in your keychain and
notarytool credentials stored under profile `MacZoomerNotary` —
see [`docs/RELEASING.md`](docs/RELEASING.md)):

```sh
scripts/release-local.sh           # uses MARKETING_VERSION from project.yml
scripts/release-local.sh 0.5.0     # override version
```

To build an unsigned `.app` for local-only smoke testing (no Apple
Developer cert required):

```sh
xcodebuild -project MacZoomer.xcodeproj -scheme MacZoomer -configuration Release \
  -derivedDataPath build CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO build
```

Tagged pushes (`vX.Y.Z`) trigger
[`.github/workflows/release.yml`](.github/workflows/release.yml), which
builds, signs, notarizes, staples, packages the DMG, publishes the
Sparkle `appcast.xml` to GitHub Pages, and creates a draft GitHub
Release.

## Permissions

MacZoomer requests **Screen Recording** the first time you trigger an action that needs it. The grant only takes effect after the app is fully quit and relaunched (a macOS requirement, not a MacZoomer choice).

If you build from source, every fresh build produces a new code-signing hash, which invalidates the previous grant. Use `tccutil reset ScreenCapture com.markusbosch.MacZoomer` to start fresh.

## License

[MIT](LICENSE) © 2026 Markus Bosch
