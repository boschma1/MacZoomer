# Contributing to MacZoomer

Thanks for your interest. MacZoomer is in early development; contributions, bug reports, and feature ideas are welcome.

## Development setup

1. Install Xcode 15.4+ from the App Store.
2. Install command-line tools: `brew install xcodegen swiftlint`.
3. Clone the repo.
4. Run `make generate` to produce the Xcode project.
5. Open `MacZoomer.xcodeproj` in Xcode.

## Workflow

- Use feature branches off `main`.
- Run `make test` and `make lint` before pushing.
- Open a PR; CI must pass.
- Keep PRs focused — one feature or one fix per PR.

## Permissions during development

The app needs Screen Recording, Accessibility, and Input Monitoring permissions to function. Grant them from **System Settings → Privacy & Security** to the build product (`MacZoomer.app` in `~/Library/Developer/Xcode/DerivedData`). You may need to re-grant after rebuilds; the app's permission coordinator will prompt you.

## Code style

- Swift 5.10+, `// MARK: -` for section dividers.
- Prefer SwiftUI for new UI; AppKit only where SwiftUI lacks the capability (overlay windows, status bar).
- Tests live in `Tests/MacZoomerTests/`.
