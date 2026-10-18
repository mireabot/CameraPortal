//
//  TrayCameraOverlayView+Transition.swift
//  CameraPortal
//
//  The morph itself, following Telegram's CameraScreen animateIn (:3169) and
//  animateOut (:3289): position, bounds and scale of a wrapper around the live
//  preview, over 0.3s with the Telegram bezier. Added here: corner radius
//  interpolation (cell radius -> tray radius) and a fallback for a scrolled-away cell.
//
//  Every animation starts from the current on-screen value, so closing mid-open
//  (or committing a drag) reverses from wherever the preview happens to be.
//

import UIKit

extension TrayCameraOverlayView {
    // MARK: In

    func animateIn() {
        guard bounds.width > 0, bounds.height > 0 else { return }
        setPhase(.animatingIn)
        transitionGeneration += 1
        let generation = transitionGeneration
        controlsView.isUserInteractionEnabled = true

        setupCamera()

        guard !usesReducedMotion,
              let sourceView = transitionIn.sourceView,
              let space = contentView
        else {
            animateCrossfadeIn(generation: generation)
            return
        }

        let sourceRect = sourceView.convert(transitionIn.sourceRect, to: space)
        guard sourceRect.width > 0, sourceRect.height > 0 else {
            animateCrossfadeIn(generation: generation)
            return
        }

        let fromState = CameraPortalGeometry.wrapperState(
            for: sourceRect,
            visualCornerRadius: transitionIn.sourceCornerRadius,
            canvas: bounds.size
        )
        let contentTarget = contentTransform(anchor: sourceRect.center)

        CameraPortalAnimation.perform({
            // t = 0
            fromState.apply(to: previewWrapperView)
            controlsView.alpha = 0
            controlsView.shutterButton.transform = CGAffineTransform(
                scaleX: TrayCameraConfig.shutterStartScale,
                y: TrayCameraConfig.shutterStartScale
            )

            // t = 1
            restState.animate(
                previewWrapperView,
                duration: TrayCameraConfig.transitionDuration,
                curve: .portal
            )
            controlsView.layer.cp_animateAlpha(
                to: 1,
                duration: TrayCameraConfig.controlsFadeDuration,
                delay: TrayCameraConfig.controlsFadeDelay
            )
            controlsView.shutterButton.layer.cp_animateScale(
                to: 1,
                duration: TrayCameraConfig.transitionDuration,
                curve: .portal
            )
            contentView?.layer.cp_animateAlpha(to: 0, duration: TrayCameraConfig.contentFadeDuration, curve: .easeOut)
            contentView?.layer.cp_animateTransform(
                to: CATransform3DMakeAffineTransform(contentTarget),
                duration: TrayCameraConfig.transitionDuration,
                curve: .portal
            )
        }, completion: { [weak self] in
            guard let self, self.transitionGeneration == generation else { return }
            self.movePreviewToCanvas()
            self.setPhase(.presented)
            self.onPresented?()
        })
    }

    /// Reduced motion, or no source view to morph from.
    private func animateCrossfadeIn(generation: Int) {
        CameraPortalAnimation.perform({
            movePreviewToCanvas()
            alpha = 0
            controlsView.alpha = 1
            controlsView.shutterButton.transform = .identity
            layer.cp_animateAlpha(to: 1, duration: TrayCameraConfig.reducedMotionDuration, curve: .easeOut)
            contentView?.layer.cp_animateAlpha(to: 0, duration: TrayCameraConfig.reducedMotionDuration, curve: .easeOut)
        }, completion: { [weak self] in
            guard let self, self.transitionGeneration == generation else { return }
            self.setPhase(.presented)
            self.onPresented?()
        })
    }

    // MARK: Out

    func animateOut(interactive: Bool) {
        guard phase != .animatingOut, phase != .dismissed else { return }
        setPhase(.animatingOut)
        transitionGeneration += 1
        let generation = transitionGeneration
        controlsView.isUserInteractionEnabled = false

        guard !usesReducedMotion else {
            animateCrossfadeOut(generation: generation)
            return
        }

        // The preview animates from the wrapper; it is already there mid-transition or mid-drag.
        movePreviewToWrapper()

        guard let destination = transitionOut(interactive),
              let destinationView = destination.destinationView,
              let space = contentView
        else {
            animateFallbackOut(generation: generation)
            return
        }

        let destinationRect = destinationView.convert(destination.destinationRect, to: space)
        guard destinationRect.width > 0, destinationRect.height > 0 else {
            animateFallbackOut(generation: generation)
            return
        }

        let targetState = CameraPortalGeometry.wrapperState(
            for: destinationRect,
            visualCornerRadius: destination.destinationCornerRadius,
            canvas: bounds.size
        )

        CameraPortalAnimation.perform({
            targetState.animate(
                previewWrapperView,
                duration: TrayCameraConfig.transitionDuration,
                curve: .portal
            )
            controlsView.layer.cp_animateAlpha(to: 0, duration: TrayCameraConfig.controlsFadeOutDuration)
            controlsView.shutterButton.layer.cp_animateScale(
                to: TrayCameraConfig.shutterStartScale,
                duration: TrayCameraConfig.transitionDuration,
                curve: .portal
            )
            contentView?.layer.cp_animateAlpha(
                to: 1,
                duration: TrayCameraConfig.contentFadeDuration,
                delay: TrayCameraConfig.contentFadeInDelay
            )
            contentView?.layer.cp_animateTransform(
                to: CATransform3DIdentity,
                duration: TrayCameraConfig.transitionDuration,
                curve: .portal
            )
        }, completion: { [weak self] in
            self?.finishDismiss(generation: generation)
        })
    }

    /// No destination, or the cell is less than 30% visible: contained fade instead of a morph.
    private func animateFallbackOut(generation: Int) {
        let shrunkScale = previewWrapperView.layer.cp_currentScale * TrayCameraConfig.fallbackScale
        CameraPortalAnimation.perform({
            previewWrapperView.layer.cp_animateScale(to: shrunkScale, duration: TrayCameraConfig.fallbackOutDuration, curve: .easeOut)
            previewWrapperView.layer.cp_animateAlpha(to: 0, duration: TrayCameraConfig.fallbackOutDuration, curve: .easeOut)
            controlsView.layer.cp_animateAlpha(to: 0, duration: TrayCameraConfig.controlsFadeOutDuration)
            contentView?.layer.cp_animateAlpha(to: 1, duration: TrayCameraConfig.fallbackOutDuration, curve: .easeOut)
            contentView?.layer.cp_animateTransform(to: CATransform3DIdentity, duration: TrayCameraConfig.fallbackOutDuration)
        }, completion: { [weak self] in
            self?.finishDismiss(generation: generation)
        })
    }

    private func animateCrossfadeOut(generation: Int) {
        CameraPortalAnimation.perform({
            layer.cp_animateAlpha(to: 0, duration: TrayCameraConfig.reducedMotionDuration, curve: .easeOut)
            contentView?.layer.cp_animateAlpha(to: 1, duration: TrayCameraConfig.reducedMotionDuration, curve: .easeOut)
            contentView?.layer.cp_animateTransform(to: CATransform3DIdentity, duration: 0)
        }, completion: { [weak self] in
            self?.finishDismiss(generation: generation)
        })
    }

    private func finishDismiss(generation: Int) {
        guard transitionGeneration == generation, phase != .dismissed else { return }
        setPhase(.dismissed)

        CameraPortalAnimation.perform {
            // Telegram's `transitionedOut` -> holder.restore(): the preview goes home.
            clearCapturedPhoto()
            holder.restore()
            contentView?.layer.removeAllAnimations()
            contentView?.alpha = 1
            contentView?.transform = .identity
            removeFromSuperview()
        }
        onInteractiveProgress?(0)
        onDismissed?()
    }

    // MARK: Helpers

    /// Scales the tray content around the camera cell, so it recedes towards the cell.
    private func contentTransform(anchor: CGPoint) -> CGAffineTransform {
        guard let contentView else { return .identity }
        return CameraPortalGeometry.scaleTransform(
            TrayCameraConfig.contentScale,
            anchor: anchor,
            center: CGPoint(x: contentView.bounds.midX, y: contentView.bounds.midY)
        )
    }
}

extension CGRect {
    var center: CGPoint { CGPoint(x: midX, y: midY) }
}
