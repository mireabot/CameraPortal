//
//  CameraTransition.swift
//  CameraPortal
//
//  Transition descriptors (mirroring Telegram's CameraScreenTransitionIn/Out),
//  tuning constants and the geometry math for the cell -> tray morph.
//

import UIKit

// MARK: - Transition descriptors

/// Where the camera comes from. `sourceRect` is local to `sourceView`.
struct CameraTransitionIn {
    weak var sourceView: UIView?
    var sourceRect: CGRect
    /// Visual corner radius of the source cell. Telegram ignores this; we interpolate it.
    var sourceCornerRadius: CGFloat
}

/// Where the camera returns to. Re-queried at dismissal time because the grid may have scrolled.
struct CameraTransitionOut {
    weak var destinationView: UIView?
    var destinationRect: CGRect
    var destinationCornerRadius: CGFloat
}

// MARK: - Config

enum TrayCameraConfig {
    /// Tray inset from the screen's left, right and bottom edges.
    static let margin: CGFloat = 8
    /// Side padding of the grid inside the tray: none, the grid runs edge to edge and the
    /// tray's own rounded shape is what cuts the cells at the corners.
    static let gridPadding: CGFloat = 0
    /// Inset of the tray's chrome (header, camera controls) from its edges. Also the
    /// concentric step for anything nested: a child inset by this gets `trayRadius - 8`.
    static let chromePadding: CGFloat = 8
    static let gridSpacing: CGFloat = 2
    static let gridColumns = 3
    static let trayHeightFraction: CGFloat = 0.58

    static let transitionDuration: CFTimeInterval = 0.3
    static let contentFadeDuration: CFTimeInterval = transitionDuration
    static let contentFadeInDelay: CFTimeInterval = 0.05
    static let controlsFadeDuration: CFTimeInterval = 0.2
    static let controlsFadeDelay: CFTimeInterval = 0.1
    static let controlsFadeOutDuration: CFTimeInterval = 0.15
    static let fallbackOutDuration: CFTimeInterval = 0.2
    static let reducedMotionDuration: CFTimeInterval = 0.25

    static let contentScale: CGFloat = 0.97
    static let shutterStartScale: CGFloat = 0.6
    static let fallbackScale: CGFloat = 0.9

    /// Below this visible fraction of the camera cell, closing uses the fallback fade.
    static let minVisibleFraction: CGFloat = 0.3

    static let panActivationDistance: CGFloat = 10
    static let panDismissFraction: CGFloat = 0.3
    static let panDismissVelocity: CGFloat = 1000
    static let panMaxScaleReduction: CGFloat = 0.15
    static let panCornerRadiusGrowth: CGFloat = 1.2

    static let shutterSize: CGFloat = 72
    /// The one round-control size in the feature: the camera's close, the camera menu's
    /// droplets, the tray header's close and the chat's attach button are all this.
    static let controlButtonSize: CGFloat = 44
    static let controlSymbolSize: CGFloat = 17
    /// Tint opacity of the black glass every round control carries.
    static let controlTintOpacity: CGFloat = 0.8
    static let cameraMenuSpacing: CGFloat = 10
    static let cameraMenuResponse: TimeInterval = 0.36

    /// A round control of radius `c` sits `r - c` in from a corner of radius `r`, so its
    /// curve stays concentric with the container's. With a 54pt tray and a 44pt control
    /// that is 32pt — the same number for the header's close, the camera's close and the
    /// review pills.
    static func concentricInset(for controlSize: CGFloat, in cornerRadius: CGFloat) -> CGFloat {
        max(chromePadding, cornerRadius - controlSize / 2)
    }
}

// MARK: - Geometry

/// Center, bounds, scale and layer corner radius of the preview wrapper.
struct CameraWrapperState {
    var center: CGPoint
    var bounds: CGRect
    var scale: CGFloat
    /// Radius set on the layer, i.e. already divided by `scale`.
    var layerCornerRadius: CGFloat

    func apply(to view: UIView) {
        view.bounds = bounds
        view.center = center
        view.transform = CGAffineTransform(scaleX: scale, y: scale)
        view.layer.cornerRadius = layerCornerRadius
    }

    func animate(_ view: UIView, duration: CFTimeInterval, curve: CameraPortalCurve = .telegram) {
        let layer = view.layer
        layer.cp_animatePosition(to: center, duration: duration, curve: curve)
        layer.cp_animateBounds(to: bounds, duration: duration, curve: curve)
        layer.cp_animateScale(to: scale, duration: duration, curve: curve)
        layer.cp_animateCornerRadius(to: layerCornerRadius, duration: duration, curve: curve)
    }
}

enum CameraPortalGeometry {
    static func aspectFitted(_ size: CGSize, in bounding: CGSize) -> CGSize {
        guard size.width > 0, size.height > 0, bounding.width > 0, bounding.height > 0 else {
            return bounding
        }
        let scale = min(bounding.width / size.width, bounding.height / size.height)
        return CGSize(width: size.width * scale, height: size.height * scale)
    }

    /// Wrapper state that makes a canvas-sized preview appear aspect-filled inside `rect`.
    ///
    /// The preview child stays fixed at `(0, 0, canvas)`. The wrapper's bounds `B` are
    /// `rect.size` aspect-fitted into the canvas and centered in it, so clipping crops the
    /// preview to the rect's aspect. Scaling by `rect.w / B.w` brings it to the rect's size,
    /// so only the wrapper animates and the preview never re-lays out mid-flight.
    static func wrapperState(for rect: CGRect, visualCornerRadius: CGFloat, canvas: CGSize) -> CameraWrapperState {
        let fitted = aspectFitted(rect.size, in: canvas)
        let bounds = CGRect(
            x: (canvas.width - fitted.width) / 2,
            y: (canvas.height - fitted.height) / 2,
            width: fitted.width,
            height: fitted.height
        )
        let scale = fitted.width > 0 ? max(0.01, rect.width / fitted.width) : 1
        return CameraWrapperState(
            center: CGPoint(x: rect.midX, y: rect.midY),
            bounds: bounds,
            scale: scale,
            layerCornerRadius: layerCornerRadius(visual: visualCornerRadius, scale: scale)
        )
    }

    static func layerCornerRadius(visual: CGFloat, scale: CGFloat) -> CGFloat {
        visual / max(0.01, scale)
    }

    /// Radius of a rounded rect inset by `inset` inside one with radius `outer`.
    static func concentricRadius(outer: CGFloat, inset: CGFloat, minimum: CGFloat) -> CGFloat {
        max(minimum, outer - inset)
    }

    /// Scale by `scale` around `anchor`, for a view whose center is `center` (same space).
    static func scaleTransform(_ scale: CGFloat, anchor: CGPoint, center: CGPoint) -> CGAffineTransform {
        let dx = anchor.x - center.x
        let dy = anchor.y - center.y
        return CGAffineTransform(translationX: dx, y: dy)
            .scaledBy(x: scale, y: scale)
            .translatedBy(x: -dx, y: -dy)
    }
}

// MARK: - Screen corner radius

enum ScreenCornerRadius {
    /// Display corner radius via guarded KVC on the private `_displayCornerRadius`.
    /// Returns 0 when unavailable, which makes the tray fall back to its minimum radius.
    static func current(for screen: UIScreen?) -> CGFloat {
        guard let screen else { return 0 }
        let key = "_displayCornerRadius"
        guard screen.responds(to: NSSelectorFromString(key)) else { return 0 }
        return (screen.value(forKey: key) as? CGFloat) ?? 0
    }

    /// The active scene's display radius. Read once from SwiftUI, which has no `UIScreen`
    /// of its own to hand over.
    @MainActor
    static var currentDisplay: CGFloat {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
        return current(for: scene?.screen)
    }
}
