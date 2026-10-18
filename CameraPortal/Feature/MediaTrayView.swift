//
//  MediaTrayView.swift
//  CameraPortal
//
//  The tray's expanded content: the UIKit media grid and camera morph under a lightweight
//  SwiftUI header. The header floats over the content and clears away while the camera owns
//  the tray.
//

import SwiftUI
import UIKit

// MARK: - Command channel

/// A handle onto the hosted UIKit view, so SwiftUI can ask for the camera without owning
/// it. Not observable: nothing about it drives a view update, it only carries commands.
@MainActor
final class MediaTrayController {
    fileprivate weak var view: MediaTrayContentView?

    func openCamera() { view?.openCameraFromCell() }
    func closeCamera() { view?.closeCamera() }

    #if DEBUG
    func showCaptureReview() { view?.showCaptureReview() }
    #endif
}

// MARK: - Tray content

struct MediaTrayView: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var cornerRadius: CGFloat
    var controller: MediaTrayController
    var isActive: Bool
    var usesReducedMotion: Bool
    /// 1 with the grid showing, 0 with the camera filling the tray.
    var headerOpacity: Double
    var onClose: () -> Void
    var onCameraFocusChanged: (Bool) -> Void

    var body: some View {
        gallery
            .overlay(alignment: .bottom) { navigation }
    }

    /// 54 - 22 on a Pro display: a 44pt control in a corner of radius 54.
    private var controlInset: CGFloat {
        TrayCameraConfig.concentricInset(
            for: TrayCameraConfig.controlButtonSize,
            in: cornerRadius
        )
    }

    private var gallery: some View {
        MediaTrayRepresentable(
            cornerRadius: cornerRadius,
            contentInsets: .zero,
            controller: controller,
            isActive: isActive,
            usesReducedMotion: usesReducedMotion,
            onCameraFocusChanged: onCameraFocusChanged
        )
    }

    // MARK: Chrome

    private var navigation: some View {
        HStack {
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .glassCircleControl()
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        // The same concentric inset the camera's own controls use, so the two close buttons
        // sit at the same distance from the tray's corners.
        .padding(.horizontal, controlInset)
        .padding(.bottom, controlInset)
        .opacity(headerOpacity)
        .allowsHitTesting(headerOpacity > 0.5)
    }
}

// MARK: - UIKit bridge

struct MediaTrayRepresentable: UIViewRepresentable {
    var cornerRadius: CGFloat
    var contentInsets: UIEdgeInsets
    var controller: MediaTrayController
    var isActive: Bool
    var usesReducedMotion: Bool
    var onCameraFocusChanged: (Bool) -> Void

    func makeUIView(context: Context) -> MediaTrayContentView {
        let view = MediaTrayContentView(frame: .zero)
        controller.view = view
        return view
    }

    func updateUIView(_ view: MediaTrayContentView, context: Context) {
        view.trayCornerRadius = cornerRadius
        view.contentInsets = contentInsets
        view.usesReducedMotion = usesReducedMotion
        view.onCameraFocusChanged = onCameraFocusChanged
        view.setCameraActive(isActive)
    }
}
