//
//  MediaTrayContentView.swift
//  CameraPortal
//
//  The tray's internals, and the last UIKit view in the feature: the media grid with its
//  live camera cell, and the camera overlay that morphs out of that cell to fill the tray.
//  It draws no background and no corners — the SwiftUI morph surface owns the glass, the
//  size and the clipping, and this view simply fills whatever bounds it is given.
//
//  Extracted from the former TrayViewController. What did *not* come along: the tray
//  chrome (header and glass), the presentation spring and the tray's own
//  pan-to-dismiss, all of which are now SwiftUI. The camera's pan-to-dismiss stays here,
//  because it drives layer animations on a reparented live preview.
//

import UIKit

final class MediaTrayContentView: UIView {
    // MARK: Inputs

    /// The tray's resting corner radius, i.e. what the camera morph interpolates *to*.
    var trayCornerRadius: CGFloat = 16 {
        didSet {
            guard trayCornerRadius != oldValue else { return }
            cameraOverlayView?.trayCornerRadius = trayCornerRadius
        }
    }

    /// Room reserved for the SwiftUI header drawn over this view.
    var contentInsets: UIEdgeInsets = .zero {
        didSet {
            guard contentInsets != oldValue else { return }
            setNeedsLayout()
        }
    }

    var usesReducedMotion = false

    /// True while the camera fills the tray, so SwiftUI can fade the chrome and deepen the dim.
    var onCameraFocusChanged: ((Bool) -> Void)?
    /// Interactive camera-dismiss progress (0...1), so SwiftUI can fade the chrome back in.
    var onCameraDragProgress: ((CGFloat) -> Void)?

    // MARK: Views

    /// The content that fades out under the camera. Also the coordinate space the source
    /// and destination rects are converted into: its frame equals this view's bounds.
    private let contentView = UIView()
    private let gridView: MediaGridView
    private let camera: CameraCaptureSession
    private let previewView: CameraPreviewView
    private var cameraOverlayView: TrayCameraOverlayView?
    private var isCameraActive = false

    var isCameraOpen: Bool { cameraOverlayView != nil }

    // MARK: Init

    override init(frame: CGRect) {
        let camera = CameraCaptureSession()
        self.camera = camera
        let previewView = CameraPreviewView(session: camera.session)
        self.previewView = previewView
        gridView = MediaGridView(camera: camera, previewView: previewView, items: MediaGridSampleData.items())
        super.init(frame: frame)

        backgroundColor = .clear
        addSubview(contentView)
        contentView.addSubview(gridView)

        gridView.onCameraTap = { [weak self] holder in
            self?.openCamera(holder: holder)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: Lifecycle

    /// Driven by SwiftUI rather than by `didMoveToWindow`: the tray stays in the hierarchy
    /// while collapsed (so the morph never has to build it mid-flight), and a display link
    /// should not run behind a closed tray.
    func setCameraActive(_ active: Bool) {
        guard active != isCameraActive else { return }
        isCameraActive = active
        if active {
            camera.startCapture()
        } else {
            #if DEBUG
            sampleIdentity(phase: .trayClosed)
            #endif
            camera.stopCapture()
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        // Never re-lay out mid-transition: the overlay's animated values would be clobbered.
        if let overlay = cameraOverlayView, !overlay.isStable { return }
        guard bounds.width > 0, bounds.height > 0 else { return }

        contentView.frame = bounds
        gridView.frame = CGRect(
            x: 0,
            y: contentInsets.top,
            width: bounds.width,
            height: max(0, bounds.height - contentInsets.top)
        )
        gridView.scrollView.contentInset.bottom = contentInsets.bottom

        cameraOverlayView?.trayCornerRadius = trayCornerRadius
        cameraOverlayView?.frame = bounds
    }

    // MARK: Camera

    /// Entry points for the SwiftUI side (and the debug auto-demo).
    func openCameraFromCell() {
        gridView.cameraTapped()
    }

    #if DEBUG
    func showCaptureReview() {
        cameraOverlayView?.debugShowCaptureReview()
    }
    #endif

    func closeCamera() {
        cameraOverlayView?.requestDismiss(interactive: false)
    }

    /// Telegram's `openCamera(holder:)`: build the transition descriptors and stage the
    /// overlay. There is no second controller — the tray is the stage.
    private func openCamera(holder: CameraHolder) {
        guard cameraOverlayView == nil, let sourceView = holder.parentView else {
            holder.restore()
            return
        }

        #if DEBUG
        sampleIdentity(phase: .trayOpened)
        #endif

        let overlay = TrayCameraOverlayView(
            holder: holder,
            transitionIn: CameraTransitionIn(
                sourceView: sourceView,
                sourceRect: sourceView.bounds,
                sourceCornerRadius: gridView.cellCornerRadius
            ),
            transitionOut: { [weak self] _ in self?.gridView.cameraDestination() },
            contentView: contentView,
            trayCornerRadius: trayCornerRadius,
            usesReducedMotion: usesReducedMotion || UIAccessibility.isReduceMotionEnabled
        )
        overlay.frame = bounds
        overlay.onPresented = { [weak self] in
            #if DEBUG
            self?.sampleIdentity(phase: .cameraOpened)
            #endif
        }
        overlay.onDismissed = { [weak self] in
            guard let self else { return }
            #if DEBUG
            self.sampleIdentity(phase: .cameraClosed)
            #endif
            self.cameraOverlayView = nil
            self.gridView.scrollView.isScrollEnabled = true
            self.onCameraFocusChanged?(false)
        }
        overlay.onInteractiveProgress = { [weak self] progress in
            self?.onCameraDragProgress?(progress)
        }

        cameraOverlayView = overlay
        addSubview(overlay)
        overlay.layoutIfNeeded()

        gridView.scrollView.isScrollEnabled = false
        onCameraFocusChanged?(true)
        overlay.animateIn()
    }

    #if DEBUG
    private func sampleIdentity(phase: CameraIdentityProbe.Phase) {
        let expectedHost: UIView? = switch phase {
        case .cameraOpened:
            cameraOverlayView?.canvasView
        case .trayOpened, .cameraClosed, .trayClosed:
            gridView.cameraWrapperView
        }

        CameraIdentityProbe.shared.sample(
            phase: phase,
            session: camera.session,
            previewView: previewView,
            expectedHost: expectedHost
        )
    }
    #endif
}
