//
//  CALayer+CameraPortalAnimation.swift
//  CameraPortal
//
//  Explicit Core Animation helpers for the camera portal transition.
//  Every helper writes the model value first and then animates from the
//  *current* value (the presentation value when an animation for that key is
//  in flight). That single rule is what makes interruptions reverse smoothly:
//  closing mid-open simply animates from wherever the layer is on screen.
//

import UIKit

enum CameraPortalCurve {
    /// Telegram's `kCAMediaTimingFunctionSpring` at 0.3s is a bezier, not a real spring
    /// (Display/Source/CAAnimationUtils.swift).
    case telegram
    /// Strong ease-in-out for the cell-to-tray portal geometry. It accelerates out of the
    /// source cell, then gives the final tray alignment enough time to settle cleanly.
    case portal
    case easeOut
    case easeInOut
    case linear

    var timingFunction: CAMediaTimingFunction {
        switch self {
        case .telegram: CAMediaTimingFunction(controlPoints: 0.380, 0.700, 0.125, 1.000)
        case .portal: CAMediaTimingFunction(controlPoints: 0.770, 0.000, 0.175, 1.000)
        case .easeOut: CAMediaTimingFunction(name: .easeOut)
        case .easeInOut: CAMediaTimingFunction(name: .easeInEaseOut)
        case .linear: CAMediaTimingFunction(name: .linear)
        }
    }
}

enum CameraPortalAnimation {
    /// Groups explicit animations so `completion` runs once, after all of them finish.
    /// Uses `CATransaction` rather than `CAAnimationDelegate` so the completion closure
    /// stays on the main actor with the rest of the module.
    /// Note: the completion also fires when an animation is replaced or removed early,
    /// so callers guard it with a generation token.
    static func perform(_ changes: () -> Void, completion: (() -> Void)? = nil) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        CATransaction.setCompletionBlock(completion)
        changes()
        CATransaction.commit()
    }
}

extension CALayer {
    func cp_animate(
        keyPath: String,
        to value: Any,
        duration: CFTimeInterval,
        delay: CFTimeInterval = 0,
        curve: CameraPortalCurve = .telegram
    ) {
        let fromValue: Any?
        if animation(forKey: keyPath) != nil, let presentation = presentation() {
            fromValue = presentation.value(forKeyPath: keyPath)
        } else {
            fromValue = self.value(forKeyPath: keyPath)
        }

        setValue(value, forKeyPath: keyPath)

        guard duration > 0 else {
            removeAnimation(forKey: keyPath)
            return
        }

        let animation = CABasicAnimation(keyPath: keyPath)
        animation.fromValue = fromValue
        animation.toValue = value
        animation.duration = duration
        animation.timingFunction = curve.timingFunction
        if delay > 0 {
            // Local time so the delay respects `layer.speed` (debug slow motion).
            animation.beginTime = convertTime(CACurrentMediaTime(), from: nil) + delay
            animation.fillMode = .backwards
        }
        // Keyed by key path so a new animation replaces the in-flight one.
        add(animation, forKey: keyPath)
    }

    func cp_animatePosition(to position: CGPoint, duration: CFTimeInterval, delay: CFTimeInterval = 0, curve: CameraPortalCurve = .telegram) {
        cp_animate(keyPath: "position", to: NSValue(cgPoint: position), duration: duration, delay: delay, curve: curve)
    }

    func cp_animateBounds(to bounds: CGRect, duration: CFTimeInterval, delay: CFTimeInterval = 0, curve: CameraPortalCurve = .telegram) {
        cp_animate(keyPath: "bounds", to: NSValue(cgRect: bounds), duration: duration, delay: delay, curve: curve)
    }

    func cp_animateTransform(to transform: CATransform3D, duration: CFTimeInterval, delay: CFTimeInterval = 0, curve: CameraPortalCurve = .telegram) {
        cp_animate(keyPath: "transform", to: NSValue(caTransform3D: transform), duration: duration, delay: delay, curve: curve)
    }

    func cp_animateScale(to scale: CGFloat, duration: CFTimeInterval, delay: CFTimeInterval = 0, curve: CameraPortalCurve = .telegram) {
        cp_animateTransform(to: CATransform3DMakeScale(scale, scale, 1), duration: duration, delay: delay, curve: curve)
    }

    func cp_animateAlpha(to alpha: CGFloat, duration: CFTimeInterval, delay: CFTimeInterval = 0, curve: CameraPortalCurve = .easeOut) {
        cp_animate(keyPath: "opacity", to: NSNumber(value: Float(alpha)), duration: duration, delay: delay, curve: curve)
    }

    func cp_animateCornerRadius(to radius: CGFloat, duration: CFTimeInterval, delay: CFTimeInterval = 0, curve: CameraPortalCurve = .telegram) {
        cp_animate(keyPath: "cornerRadius", to: NSNumber(value: Double(radius)), duration: duration, delay: delay, curve: curve)
    }

    /// Current on-screen scale of a layer whose transform is a pure scale.
    var cp_currentScale: CGFloat {
        let layer = animation(forKey: "transform") != nil ? (presentation() ?? self) : self
        return layer.transform.m11
    }
}
