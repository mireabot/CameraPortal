# CameraPortal

A camera portal makes a live preview expand out of a media grid and return to its cell. In this implementation, the same preview view changes parents while an animated wrapper controls its position and crop.

The expanded camera stays inside the attachment tray. It fills the available frame of the tray with a close button at the top right and the shutter below. The parent screen above it stays in place.

This is a standalone SwiftUI and UIKit demo, extracted from Explorations.

## Project structure

- `CameraPortal/ContentView.swift` opens the chat demo.
- `CameraPortal/Feature/` contains the complete feature, including its controls, geometry helpers, capture session, and grid sample data.
- `CameraPortal/Helpers/OrientationLock.swift` contains the app delegate and orientation helper used by the camera screen.

SwiftUI owns the chat and outer tray morph. UIKit owns the grid, live preview, camera controls, and preview handoff. One capture session and preview view survive the cell-to-camera transition. Closing the entire tray stops capture while retaining those objects.

## Documentation

Read [how the camera portal works](docs/camera-portal.md). The notes include Telegram source references, preview identity, wrapper geometry, and the SwiftUI/UIKit split.

## Reference and limitations

The camera handoff and wrapper transitions adapt patterns from [Telegram iOS](https://github.com/TelegramMessenger/Telegram-iOS). The outer tray surface credits SwiftUX's `Transition_MorphingActionMenu`. Existing source comments retain those references.

The demo retains the original private display-radius lookup and variable-blur filter helper. These are experimental implementation details. Review them before distributing an app. The camera preview and photo capture use AVFoundation.
