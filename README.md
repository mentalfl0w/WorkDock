# WorkDock

A personal macOS utility dock. Built with SwiftUI for macOS 26+ (Liquid Glass).

This is a personal tool — not intended for public distribution or production use.

WorkDock starts in the menu bar. Its Dock icon visibility follows the setting
in WorkDock Settings, including when the app starts at login. Opening a
WorkDock notification brings the corresponding module window forward.

## Screenshot OCR

Open **Screenshot OCR** from the gallery or menu bar to capture a screen region,
recognize a clipboard image, or choose an image file. Recognition uses Apple's
Vision framework locally for Simplified Chinese and English. Results can be
edited and copied; they are not stored as history.

The module settings let you enable, customize, or reset the global screenshot
shortcut. WorkDock must be running for the shortcut to work. Screen capture
requires macOS Screen Recording permission; image files and clipboard images
do not. If a shortcut cannot be registered, choose another combination.

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
