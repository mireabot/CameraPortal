# CameraPortal

A camera portal makes a live preview expand out of a media grid and return to its cell. In this implementation, the same preview view changes parents while an animated wrapper controls its position and crop.

The expanded camera stays inside the attachment tray. It fills the available frame of the tray with a close button at the top right and the shutter below. The parent screen above it stays in place.

This is a standalone SwiftUI and UIKit demo, extracted from Explorations.

Open `CameraPortal.xcodeproj` in Xcode 26 or later. The deployment target is iOS 26.0. Choose the shared `CameraPortal` scheme and run it on an iPhone. The app requests camera permission when the attachment tray opens. A simulator without a capture device shows a black preview.

Tap the paperclip to open the tray. Tap the camera cell to expand it. Close the camera or drag it back into the grid. The shutter takes a photo for the in-memory review screen. Retake discards it and Use photo closes review. This demo does not save images to Photos or send messages.

## Project structure

- `CameraPortal/ContentView.swift` opens the chat demo.
- `CameraPortal/Feature/` contains the complete feature, including its controls, geometry helpers, capture session, grid sample data, and debug instrumentation.
- `CameraPortal/Helpers/OrientationLock.swift` contains the app delegate and orientation helper used by the camera screen.

All feature code is local. There are no Swift package dependencies or references back to Explorations. The media grid uses generated placeholder colors and durations, so it needs no photo assets or photo library permission.

SwiftUI owns the chat and outer tray morph. UIKit owns the grid, live preview, camera controls, and preview handoff. One capture session and preview view survive the cell-to-camera transition. Closing the entire tray stops capture while retaining those objects.

## Documentation

Read [how the camera portal works](docs/camera-portal.md). The notes include Telegram source references, preview identity, wrapper geometry, and the SwiftUI/UIKit split. [The 200 × 200 Bézier demo](docs/bezier.html) is self-contained HTML.

## Build

```sh
xcodebuild -project CameraPortal.xcodeproj -scheme CameraPortal \
  -configuration Debug -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO build
```

Choose your signing team in Xcode before running on a physical device. The project retains the bundle identifier `com.MKM.CameraPortal` from the provided app template.

## Debug launch arguments

Add arguments in Product > Scheme > Edit Scheme > Run > Arguments.

| Arguments | Behavior |
| --- | --- |
| `-CameraPortalAutoDemo tray` | Opens the tray. |
| `-CameraPortalAutoDemo camera` | Opens the tray and camera. |
| `-CameraPortalAutoDemo cycle` | Opens and closes the camera and tray once. |
| `-CameraPortalAutoDemo slow` | Runs the cycle with slower layer animations. |
| `-CameraPortalMorphProgress 0.5` | Holds the outer tray morph at a chosen progress. |
| `-CameraPortalCameraMenu expanded` | Starts with the camera menu expanded. |
| `-CameraPortalFocusInput 1` | Focuses the message field before opening the tray. |
| `-CameraPortalCaptureReview 1 -CameraPortalAutoDemo camera` | Shows capture review after opening. |
| `-CameraPortalIdentityCycles 20` | Exercises preview handoffs and checks object identity and frame delivery. |
| `-CameraPortalIdentityCycles 20 -CameraPortalIdentityTray 1` | Also closes and reopens the entire tray each cycle. |
| `-CameraPortalIdentityHUD 1` | Displays identity and capture counters. |

Debug instrumentation is excluded from Release builds. Frame-delivery checks require a working capture device. No device-run identity verdict is included in this extraction.

## Reference and limitations

The camera handoff and wrapper transitions adapt patterns from [Telegram iOS](https://github.com/TelegramMessenger/Telegram-iOS). The outer tray surface credits SwiftUX's `Transition_MorphingActionMenu`. Existing source comments retain those references.

The demo retains the original private display-radius lookup and variable-blur filter helper. These are experimental implementation details. Review them before distributing an app. The camera preview and photo capture use AVFoundation.
