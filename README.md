# MacZoomer

A native macOS screen-zoom, annotation, and recording tool for technical presentations and demos. Inspired by [Sysinternals ZoomIt](https://learn.microsoft.com/sysinternals/downloads/zoomit) — reimplemented from scratch for macOS.

> **Status:** 🚧 Phase 0 — Foundations. Not yet usable.

## Features (planned for v1.0)

- **Zoom Mode** — freeze the screen and zoom in on a region with the mouse, draw on the frozen image.
- **Live Zoom** — real-time magnification of the live screen.
- **Drawing & Annotation** — pens, highlighters, blur, shapes, text, whiteboard/blackboard.
- **Screenshots** — copy or save full screen or a region as PNG.
- **Recording** — capture the screen, a region, or a focused window as MP4 or animated GIF (video only in v1; audio in v1.1).
- **Break Timer** — full-screen countdown for breaks during presentations.
- **Global hotkeys** — all configurable.
- **Menu bar app** — no Dock icon.

Out of scope for v1: OCR, DemoType, panorama recording, audio in recordings.

## Requirements

- macOS 14 Sonoma or newer
- Apple Silicon or Intel Mac

## Building from source

```sh
# Install build tools (one-time)
brew install xcodegen swiftlint

# Generate the Xcode project
make generate

# Build & run via Xcode
open MacZoomer.xcodeproj

# OR build & test via SwiftPM (no Xcode needed for compile-checking)
make test
```

Full app builds (.app bundle, signing, notarization) require a full Xcode installation.

## License

[MIT](LICENSE) © 2026 Markus Bosch
