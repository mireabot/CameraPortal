# How I built the camera portal

A camera portal makes a live preview expand out of a media grid and return to its cell. In this implementation, the same preview view changes parents while an animated wrapper controls its position and crop.

The expanded camera stays inside the attachment tray. It fills the black rounded panel at the bottom of the screen, with a close button at the top right and the shutter below. The white screen above it stays in place.

## What came from Telegram

Telegram's iOS source provided the camera handoff pattern. Its media picker passes a `CameraHolder` containing the existing camera, preview view, original parent, and a restore closure. The camera screen takes that preview and adds it to an animation wrapper. After dismissal, the restore closure puts it back into the picker. I adapted that ownership and handoff structure. [Telegram media picker](https://github.com/TelegramMessenger/Telegram-iOS/blob/f1dd7a2dbd02cbbf513e75d5695d8d36d1cf5838/submodules/MediaPickerUI/Sources/MediaPickerScreen.swift#L916), [camera setup](https://github.com/TelegramMessenger/Telegram-iOS/blob/f1dd7a2dbd02cbbf513e75d5695d8d36d1cf5838/submodules/TelegramUI/Components/CameraScreen/Sources/CameraScreen.swift#L2834)

I also adapted its transition descriptors and wrapper animation. The source and destination each describe a view and a rectangle in that view's coordinates. Telegram converts those rectangles into the camera's coordinate space, then animates the wrapper's position, bounds, and scale over 0.3 seconds. [Telegram opening transition](https://github.com/TelegramMessenger/Telegram-iOS/blob/f1dd7a2dbd02cbbf513e75d5695d8d36d1cf5838/submodules/TelegramUI/Components/CameraScreen/Sources/CameraScreen.swift#L3301), [closing transition](https://github.com/TelegramMessenger/Telegram-iOS/blob/f1dd7a2dbd02cbbf513e75d5695d8d36d1cf5838/submodules/TelegramUI/Components/CameraScreen/Sources/CameraScreen.swift#L3375)

My version keeps that transition inside the existing tray. It adds corner radius interpolation and a fade fallback when the destination cell is mostly out of view. The geometry uses a locally tuned cubic Bézier curve, `0.770, 0.000, 0.175, 1.000`. One source comment still mentions Telegram's curve, but the animation calls use the local curve. [Local transition](../CameraPortal/Feature/TrayCameraOverlayView+Transition.swift), [animation curves](../CameraPortal/Feature/CALayer+CameraPortalAnimation.swift)

The attachment button's expansion into the tray has a separate source. `TrayMorphSurface` credits SwiftUX's `Transition_MorphingActionMenu`. Telegram is the reference for the camera handoff inside that tray. [Tray surface](../CameraPortal/Feature/TrayMorphSurface.swift)

## What keeps its identity

`MediaTrayContentView` creates one `CameraCaptureSession` and one `CameraPreviewView`. The preview's backing layer is an `AVCaptureVideoPreviewLayer`, attached to that session during initialization. Moving the view to another parent keeps that same layer and session association. [Camera ownership](../CameraPortal/Feature/MediaTrayContentView.swift), [preview layer](../CameraPortal/Feature/CameraPreviewSource.swift)

Tapping the camera cell disables its tap gesture and passes those existing objects to the overlay through `CameraHolder`. The preview moves into the animation wrapper. Once expansion finishes, it moves into the resting canvas. Closing moves it back through the wrapper, then `holder.restore()` returns it to the cell and enables tapping again. [Handoff and restore](../CameraPortal/Feature/MediaGridView.swift), [preview parents](../CameraPortal/Feature/TrayCameraOverlayView.swift)

The session, preview view, and preview layer retain their identity across that transition. Their parent and geometry change. Their object identity does not.

## How the frame moves

The cell starts inside a scrolling grid. Its rectangle is local to its parent, so the overlay first converts that rectangle into the tray content's coordinates. The overlay occupies the same tray bounds. Both ends of the animation can now use one coordinate space.

The preview takes the expanded canvas size before the animation starts. It keeps that size during the animation. The wrapper clips it to a smaller rectangle and scales that rectangle until it matches the camera cell.

Expanding changes the wrapper's position, bounds, scale, and corner radius. The crop opens until the full canvas is visible. The live preview does not need a new layout on every animation frame. Closing reverses the process and restores the cell-sized preview at the end. [Wrapper geometry](../CameraPortal/Feature/CameraTransition.swift)

The radius needs scale compensation too. The code divides the desired visible radius by the wrapper's scale before assigning the layer radius. This keeps the scaled corner at the intended size on screen.

All of this happens inside the tray's clipping shape. There is no separate `UIWindow` or private portal view in this implementation.

## Reversing and dismissing

When a new animation replaces one already running, the animation helper reads the presentation layer's current visible value. It writes the new target to the model layer and animates between them. Closing halfway through opening starts at the position currently on screen. This preserves position continuity. It does not preserve spring velocity. A generation counter prevents an earlier completion from moving the preview after a newer transition has started. [Animation helper](../CameraPortal/Feature/CALayer+CameraPortalAnimation.swift)

Dragging moves the preview into the wrapper again. The wrapper follows the finger and shrinks while the grid reappears. A short drag returns it to the camera canvas. Crossing the distance or velocity threshold commits dismissal. The code queries the destination again before returning. If less than 30% of the cell is visible, it uses a contained fade and shrink. Reduced Motion uses a crossfade. [Drag handling](../CameraPortal/Feature/TrayCameraOverlayView.swift), [return destination](../CameraPortal/Feature/MediaGridView.swift)

## Where SwiftUI stops and UIKit starts

SwiftUI owns the chat, attachment button, button-to-tray morph, outer shape, clipping, and tray navigation control. The tray's hosted content keeps its expanded layout size while SwiftUI scales and clips the surrounding surface.

`MediaTrayRepresentable` creates the UIKit content and updates its inputs. A weak command handle lets SwiftUI request camera actions. Callbacks tell SwiftUI when to hide or restore the tray control.

UIKit owns the grid, capture session, live preview, camera controls, reparenting, drag gesture, and Core Animation transitions. The source explicitly keeps camera dismissal here because it drives layer animations on the reparented preview. [SwiftUI screen](../CameraPortal/Feature/ChatScreen.swift), [bridge](../CameraPortal/Feature/MediaTrayView.swift), [UIKit content](../CameraPortal/Feature/MediaTrayContentView.swift)

Capture lifetime is separate from that handoff. Opening and closing the expanded camera keep the session running. Closing the entire attachment tray stops capture. Reopening starts it again with the same owned objects.

## The easing curve

The camera wrapper uses `cubic-bezier(0.77, 0, 0.175, 1)` for its 0.3-second expansion and return. It begins slowly, moves fastest through the middle, and slows before reaching the destination. This is a timing curve. It changes how quickly the wrapper moves along its transition, rather than defining a curved route across the screen.

The ball in [the 200 × 200 demo](bezier.html) traces that timing curve. The horizontal axis is elapsed time. The vertical axis is animation progress. Time advances evenly while progress follows the curve, so the ball rises slowly at each end and quickly through the middle. The demo lasts 1.8 seconds, six times the native duration, to make that change visible. It plays once when it becomes visible. Click it to replay.

```css
transition-timing-function: cubic-bezier(0.77, 0, 0.175, 1);
```

The demo uses the portfolio's Radix gray palette, pink accent, 8 px frame radius, and embedded Open Sauce Two font. It follows the system's light or dark appearance. Reduced Motion keeps the ball at the endpoint and uses a short fade on replay.

To embed it, serve the accompanying HTML file and use:

```html
<iframe
  src="bezier.html"
  title="Camera portal easing curve"
  width="200"
  height="200"
  style="display: block; border: 0"
  loading="lazy"
></iframe>
```

The HTML file includes its font and has no external dependencies. Markdown platforms that strip iframe tags can link to it instead. Design tokens match the portfolio's Radix gray palette and iframe styles.

## Source notes

This account describes the current local implementation. Telegram links point to revision `f1dd7a2dbd02cbbf513e75d5695d8d36d1cf5838`, checked against the source. The exact upstream revision used during development is unknown. The original Explorations directory had no available Git history at extraction, so the source does not establish the order of earlier attempts.

The native debug probe records session, preview view, and preview layer identities, lifecycle events, and delivered frames. No device-run verdict was inspected for this post. The code shows what the probe checks, rather than proving that a particular run passed. [Identity probe](../CameraPortal/Feature/CameraIdentityProbe.swift)
