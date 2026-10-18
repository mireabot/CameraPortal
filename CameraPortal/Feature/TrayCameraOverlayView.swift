//
//  TrayCameraOverlayView.swift
//  CameraPortal
//
//  The camera "screen", except it lives inside the tray instead of a pushed
//  controller. It owns the animating wrapper, the canvas the preview rests in,
//  and the controls. Because it shares the tray's clipping surface, no portal
//  view is needed: the grid simply fades underneath.
//

import UIKit

final class TrayCameraOverlayView: UIView {
    enum Phase {
        case idle
        case animatingIn
        case presented
        case interactive
        case animatingOut
        case dismissed
    }

    // MARK: Inputs

    let holder: CameraHolder
    let transitionIn: CameraTransitionIn
    /// Re-queried on dismissal (`interactive`) because the grid may have scrolled.
    let transitionOut: (Bool) -> CameraTransitionOut?
    /// The tray content that fades out under the camera. Also the coordinate space the
    /// source and destination rects are converted into: its frame equals the tray bounds,
    /// so its untransformed space matches this overlay's.
    weak var contentView: UIView?
    let usesReducedMotion: Bool

    var trayCornerRadius: CGFloat {
        didSet { setNeedsLayout() }
    }

    /// Called once the preview has been handed back to the cell and the overlay removed.
    var onDismissed: (() -> Void)?
    /// Called after the same preview view has landed in the full-tray canvas.
    var onPresented: (() -> Void)?
    /// Reports interactive progress so the tray can cross-fade its own content.
    var onInteractiveProgress: ((CGFloat) -> Void)?

    // MARK: Views

    let previewWrapperView = UIView()
    let canvasView = UIView()
    let controlsView = ShutterOverlayView()
    private let flashView = UIView()
    private let capturedPhotoView = UIImageView()

    // MARK: State

    private(set) var phase: Phase = .idle
    private var isCapturePending = false
    /// Guards `CATransaction` completions: they also fire when animations are replaced.
    var transitionGeneration = 0
    private var panActivated = false
    private lazy var panGesture: UIPanGestureRecognizer = {
        let gesture = UIPanGestureRecognizer(target: self, action: #selector(handlePan))
        gesture.delegate = self
        return gesture
    }()

    var isStable: Bool { phase == .idle || phase == .presented }
    var isReviewingCapture: Bool { capturedPhotoView.superview != nil }

    init(
        holder: CameraHolder,
        transitionIn: CameraTransitionIn,
        transitionOut: @escaping (Bool) -> CameraTransitionOut?,
        contentView: UIView?,
        trayCornerRadius: CGFloat,
        usesReducedMotion: Bool
    ) {
        self.holder = holder
        self.transitionIn = transitionIn
        self.transitionOut = transitionOut
        self.contentView = contentView
        self.trayCornerRadius = trayCornerRadius
        self.usesReducedMotion = usesReducedMotion
        super.init(frame: .zero)

        backgroundColor = .clear

        // Both stay transparent: the grid has to be visible underneath the growing preview,
        // and the wrapper must not cover the canvas once the preview rests there.
        canvasView.clipsToBounds = true
        canvasView.layer.cornerCurve = .continuous
        canvasView.backgroundColor = .clear
        addSubview(canvasView)

        previewWrapperView.clipsToBounds = true
        previewWrapperView.layer.cornerCurve = .continuous
        previewWrapperView.backgroundColor = .clear
        addSubview(previewWrapperView)

        flashView.backgroundColor = .white
        flashView.alpha = 0
        flashView.isUserInteractionEnabled = false
        addSubview(flashView)

        capturedPhotoView.backgroundColor = .black
        capturedPhotoView.contentMode = .scaleAspectFill
        capturedPhotoView.clipsToBounds = true
        capturedPhotoView.isUserInteractionEnabled = false
        capturedPhotoView.autoresizingMask = [.flexibleWidth, .flexibleHeight]

        controlsView.usesReducedMotion = usesReducedMotion
        controlsView.onShutter = { [weak self] in self?.captureTapped() }
        controlsView.onFlip = { [weak self] in self?.flipTapped() }
        controlsView.onFlashChanged = { [weak self] enabled in
            self?.holder.camera.setFlashEnabled(enabled)
        }
        controlsView.onClose = { [weak self] in self?.requestDismiss(interactive: false) }
        controlsView.onRetake = { [weak self] in self?.retakeCapturedPhoto() }
        controlsView.onUsePhoto = { [weak self] in self?.useCapturedPhoto() }
        addSubview(controlsView)

        addGestureRecognizer(panGesture)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: Hierarchy

    /// Telegram `setupCamera()` (CameraScreen.swift:2782): the same preview view, reparented.
    func setupCamera() {
        CameraPortalAnimation.perform {
            previewWrapperView.isHidden = false
            previewWrapperView.addSubview(holder.previewView)
            holder.previewView.frame = CGRect(origin: .zero, size: bounds.size)
            holder.previewView.transform = .identity
            // AVCaptureVideoPreviewLayer resizes its video sublayer in its own layout pass,
            // which otherwise runs later with an implicit animation from the old cell frame.
            holder.previewView.layer.layoutIfNeeded()
        }
    }

    func movePreviewToCanvas() {
        canvasView.addSubview(holder.previewView)
        holder.previewView.frame = canvasView.bounds
        previewWrapperView.isHidden = true
    }

    func movePreviewToWrapper() {
        guard holder.previewView.superview !== previewWrapperView else { return }
        previewWrapperView.isHidden = false
        restState.apply(to: previewWrapperView)
        previewWrapperView.addSubview(holder.previewView)
        holder.previewView.frame = CGRect(origin: .zero, size: bounds.size)
    }

    /// Wrapper state that exactly fills the tray.
    var restState: CameraWrapperState {
        CameraPortalGeometry.wrapperState(for: bounds, visualCornerRadius: trayCornerRadius, canvas: bounds.size)
    }

    func setPhase(_ phase: Phase) {
        self.phase = phase
    }

    // MARK: Layout

    override func layoutSubviews() {
        super.layoutSubviews()
        // Skip layout mid-transition so animated values are never overwritten.
        guard isStable, bounds.width > 0, bounds.height > 0 else { return }

        canvasView.frame = bounds
        canvasView.layer.cornerRadius = trayCornerRadius
        flashView.frame = bounds
        controlsView.trayCornerRadius = trayCornerRadius
        controlsView.frame = bounds

        if holder.previewView.superview === canvasView {
            holder.previewView.frame = canvasView.bounds
        } else if holder.previewView.superview === previewWrapperView, phase == .presented {
            restState.apply(to: previewWrapperView)
            holder.previewView.frame = CGRect(origin: .zero, size: bounds.size)
        }
    }

    // MARK: Actions

    func requestDismiss(interactive: Bool) {
        guard phase != .animatingOut, phase != .dismissed else { return }
        animateOut(interactive: interactive)
    }

    #if DEBUG
    /// Screenshot scaffolding: the review controls without a shutter press.
    func debugShowCaptureReview() {
        controlsView.setReviewing(true, animated: false)
    }
    #endif

    private func captureTapped() {
        guard phase == .presented, !isCapturePending, !isReviewingCapture else { return }
        isCapturePending = true
        controlsView.shutterButton.isEnabled = false
        holder.camera.capturePhoto { [weak self] data in
            guard let self, self.phase == .presented else { return }
            self.presentCapturedPhoto(data.flatMap(UIImage.init(data:)))
        }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        flashView.alpha = 0.85
        UIView.animate(withDuration: 0.25) {
            self.flashView.alpha = 0
        }
    }

    private func presentCapturedPhoto(_ image: UIImage?) {
        isCapturePending = false
        controlsView.shutterButton.isEnabled = true
        capturedPhotoView.image = image
        capturedPhotoView.frame = holder.previewView.bounds
        capturedPhotoView.alpha = 0
        holder.previewView.addSubview(capturedPhotoView)
        controlsView.setReviewing(true, animated: true)

        UIView.animate(
            withDuration: usesReducedMotion ? 0.1 : 0.16,
            delay: 0,
            options: [.beginFromCurrentState, .allowUserInteraction, .curveEaseOut]
        ) {
            self.capturedPhotoView.alpha = 1
        }
    }

    private func retakeCapturedPhoto() {
        guard isReviewingCapture else { return }
        controlsView.setReviewing(false, animated: true)

        UIView.animate(
            withDuration: usesReducedMotion ? 0.1 : 0.16,
            delay: 0,
            options: [.beginFromCurrentState, .allowUserInteraction, .curveEaseOut]
        ) {
            self.capturedPhotoView.alpha = 0
        } completion: { _ in
            self.clearCapturedPhoto()
        }
    }

    private func useCapturedPhoto() {
        guard isReviewingCapture else { return }
        requestDismiss(interactive: false)
    }

    func clearCapturedPhoto() {
        capturedPhotoView.removeFromSuperview()
        capturedPhotoView.image = nil
        capturedPhotoView.alpha = 1
        isCapturePending = false
        controlsView.shutterButton.isEnabled = true
    }

    private func flipTapped() {
        guard phase == .presented else { return }
        UIView.transition(with: canvasView, duration: 0.35, options: [.transitionFlipFromLeft, .allowAnimatedContent]) {
            self.holder.camera.togglePosition()
        }
    }

    // MARK: Interactive dismissal

    /// Telegram `handlePan` (CameraScreen.swift:2990), adapted: the wrapper itself follows
    /// the finger instead of a container's sublayerTransform.
    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        let translation = gesture.translation(in: self)
        let velocity = gesture.velocity(in: self)
        let height = max(1, bounds.height)

        switch gesture.state {
        case .began:
            panActivated = false
        case .changed:
            if !panActivated {
                guard abs(translation.y) > TrayCameraConfig.panActivationDistance,
                      abs(translation.y) > abs(translation.x) else { return }
                panActivated = true
                setPhase(.interactive)
                transitionGeneration += 1
                movePreviewToWrapper()
            }
            updateInteractive(translationY: translation.y)
        case .ended, .cancelled, .failed:
            guard panActivated else { return }
            panActivated = false
            let progress = abs(translation.y) / height
            let shouldDismiss = gesture.state == .ended
                && (progress > TrayCameraConfig.panDismissFraction || abs(velocity.y) > TrayCameraConfig.panDismissVelocity)
            if shouldDismiss {
                animateOut(interactive: true)
            } else {
                springBackFromInteractive()
            }
        default:
            break
        }
    }

    private func updateInteractive(translationY: CGFloat) {
        let height = max(1, bounds.height)
        let progress = min(1, abs(translationY) / height)
        let scale = 1 - TrayCameraConfig.panMaxScaleReduction * progress
        let visualRadius = trayCornerRadius * (1 + (TrayCameraConfig.panCornerRadiusGrowth - 1) * progress)

        var state = restState
        state.center.y += translationY
        state.scale = scale
        state.layerCornerRadius = CameraPortalGeometry.layerCornerRadius(visual: visualRadius, scale: scale)
        state.apply(to: previewWrapperView)

        let fadeProgress = min(1, abs(translationY) / (TrayCameraConfig.panDismissFraction * height))
        controlsView.alpha = 1 - fadeProgress
        contentView?.alpha = fadeProgress
        onInteractiveProgress?(fadeProgress)
    }

    private func springBackFromInteractive() {
        transitionGeneration += 1
        let generation = transitionGeneration
        CameraPortalAnimation.perform({
            restState.animate(previewWrapperView, duration: TrayCameraConfig.transitionDuration)
            controlsView.layer.cp_animateAlpha(to: 1, duration: TrayCameraConfig.contentFadeDuration)
            contentView?.layer.cp_animateAlpha(to: 0, duration: TrayCameraConfig.contentFadeDuration)
        }, completion: { [weak self] in
            guard let self, self.transitionGeneration == generation else { return }
            self.movePreviewToCanvas()
            self.setPhase(.presented)
            self.onInteractiveProgress?(0)
        })
    }
}

// MARK: - UIGestureRecognizerDelegate

extension TrayCameraOverlayView: UIGestureRecognizerDelegate {
    // UIView declares this too, hence `override`.
    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard gestureRecognizer === panGesture else { return true }
        guard !isReviewingCapture else { return false }
        guard phase == .presented || phase == .interactive else { return false }
        let velocity = panGesture.velocity(in: self)
        return abs(velocity.y) > abs(velocity.x)
    }
}
