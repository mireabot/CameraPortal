//
//  CameraPreviewSource.swift
//  CameraPortal
//
//  A live AVCaptureVideoPreviewLayer that can be reparented between the media grid and
//  the full camera surface. With no capture input (including Simulator), its black backing
//  becomes the camera cell instead of substituting synthetic content.
//

import AVFoundation
import UIKit

protocol CameraPreviewSource: UIView {
    /// Width / height of the video frames, used to aspect-fill whatever bounds the view gets.
    var contentAspectRatio: CGFloat { get }
    func setActive(_ active: Bool)
}

final class CameraPreviewView: UIView, CameraPreviewSource {
    let contentAspectRatio: CGFloat = 3.0 / 4.0

    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }

    private var previewLayer: AVCaptureVideoPreviewLayer {
        layer as! AVCaptureVideoPreviewLayer
    }

    init(session: AVCaptureSession) {
        super.init(frame: .zero)
        backgroundColor = .black
        clipsToBounds = true
        isUserInteractionEnabled = false
        accessibilityElementsHidden = true
        previewLayer.videoGravity = .resizeAspectFill
        previewLayer.session = session
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard let connection = previewLayer.connection,
              connection.isVideoRotationAngleSupported(90) else { return }
        connection.videoRotationAngle = 90
    }

    /// Capture lifetime belongs to `CameraCaptureSession`; reparenting the preview must not
    /// start or stop a second session.
    func setActive(_ active: Bool) {}
}
