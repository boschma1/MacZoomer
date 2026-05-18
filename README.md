# MacZoomer

A native macOS screen-zoom, annotation, screenshot, and recording tool for technical presentations and demos. Inspired by [Sysinternals ZoomIt](https://learn.microsoft.com/sysinternals/downloads/zoomit) — reimplemented from scratch for macOS.

> **Status:** 🛠 Pre-release. Zoom, Live Zoom, Drawing, Screenshots, and the Break Timer are functional. Screen Recording and final distribution polish are still in progress.

## Features

| Feature | Default shortcut | Status |
| --- | --- | --- |
| Zoom Mode (freeze + magnify) | ⌘1 | ✅ |
| Drawing & Annotation (pens, highlighter, blur, shapes, text, whiteboard) | ⌘2 | ✅ |
| Break Timer (full-screen countdown) | ⌘3 | ✅ |
| Live Zoom (real-time magnification with pan) | ⌘4 | ✅ |
| Live Draw (annotate the live desktop) | ⌘⇧4 | ✅ |
| Copy / save full screen or region as PNG | ⌘6 / ⌘⇧6 / ⌘⌃6 / ⌘⇧⌃6 | ✅ |
| Screen Recording (MP4 + GIF) | ⌘5 / ⌘⇧5 / ⌘⌥5 | ⏳ in progress |
| Auto-update via Sparkle + signed/notarized DMG | — | ⏳ in progress |

Every shortcut is rebindable in Settings → Hotkeys. Settings can be exported/imported as JSON.

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

A signed Release `.app` for local installation:

```sh
xcodebuild -project MacZoomer.xcodeproj -scheme MacZoomer -configuration Release \
  -derivedDataPath build CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO build

codesign --force --deep --sign - \
  --identifier com.markusbosch.MacZoomer --options runtime \
  --entitlements Sources/MacZoomer/Resources/MacZoomer.entitlements \
  build/Build/Products/Release/MacZoomer.app

cp -R build/Build/Products/Release/MacZoomer.app /Applications/
```

Full Developer ID signing, notarization, and DMG packaging will be wired into a GitHub Actions release workflow before v1.0.

## Permissions

MacZoomer requests **Screen Recording** the first time you trigger an action that needs it. The grant only takes effect after the app is fully quit and relaunched (a macOS requirement, not a MacZoomer choice).

If you build from source, every fresh build produces a new code-signing hash, which invalidates the previous grant. Use `tccutil reset ScreenCapture com.markusbosch.MacZoomer` to start fresh.

## License

[MIT](LICENSE) © 2026 Markus Bosch

