# WorkDock

A personal macOS utility dock. Built with SwiftUI for macOS 26+ (Liquid Glass).

This is a personal tool — not intended for public distribution or production use.

## Build

```bash
swift build
```

To assemble a launchable `.app` bundle:

```bash
mkdir -p .build/WorkDock.app/Contents/{MacOS,Resources}
cp $(swift build --show-bin-path)/WorkDock .build/WorkDock.app/Contents/MacOS/
cp Info.plist AppIcon.icns logo.png .build/WorkDock.app/Contents/Resources/
codesign --force --deep --sign - .build/WorkDock.app
open .build/WorkDock.app
```

Requires macOS 26+ SDK and libxml2 (`brew install libxml2 pkg-config`).

## License

© 2026 Dylan Liu
