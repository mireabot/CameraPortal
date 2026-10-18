//
//  CameraCaptureSession.swift
//  CameraPortal
//
//  Capture session and Telegram-style preview handoff object.
//

import AVFoundation
import UIKit

nonisolated protocol CameraSession: AnyObject {
    func startCapture()
    func stopCapture()
    func capturePhoto(
        completion: @escaping @MainActor @Sendable (Data?) -> Void
    )
    func togglePosition()
    func setFlashEnabled(_ enabled: Bool)
}

/// Owns one capture session for the lifetime of the media tray.
///
/// All session mutations run on `captureQueue`, as required by AVFoundation. The immutable
/// session reference is exposed only so the main-actor preview layer can display it. This
/// queue-confinement invariant is the reason for `@unchecked Sendable`; remove the unchecked
/// conformance if this backend moves to an actor with a serial custom executor.
nonisolated final class CameraCaptureSession: NSObject, CameraSession, @unchecked Sendable {
    let session = AVCaptureSession()

    private let captureQueue = DispatchQueue(
        label: "com.MKM.CameraPortal.capture",
        qos: .userInitiated
    )
    private let photoOutput = AVCapturePhotoOutput()
    #if DEBUG
    private let identityVideoOutput = AVCaptureVideoDataOutput()
    #endif

    private var videoInput: AVCaptureDeviceInput?
    private var wantsRunning = false
    private var isConfigured = false
    private var position: AVCaptureDevice.Position = .back
    private var isFlashEnabled = false
    /// Access is confined to `captureQueue`; delegate callbacks hop back onto that queue.
    private var pendingPhotoCompletion: (@MainActor @Sendable (Data?) -> Void)?

    func startCapture() {
        captureQueue.async { [self] in
            wantsRunning = true
        }

        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            enqueueStartIfNeeded()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                guard granted else { return }
                self?.enqueueStartIfNeeded()
            }
        case .denied, .restricted:
            break
        @unknown default:
            break
        }
    }

    func stopCapture() {
        captureQueue.async { [self] in
            wantsRunning = false
            if session.isRunning {
                session.stopRunning()
            }
        }
    }

    func capturePhoto(
        completion: @escaping @MainActor @Sendable (Data?) -> Void
    ) {
        captureQueue.async { [self] in
            guard session.isRunning, isConfigured else {
                Task { @MainActor in completion(nil) }
                return
            }

            let settings = AVCapturePhotoSettings()
            let canUseFlash = isFlashEnabled
                && videoInput?.device.hasFlash == true
                && photoOutput.supportedFlashModes.contains(.on)
            settings.flashMode = canUseFlash ? .on : .off
            settings.photoQualityPrioritization = .speed
            pendingPhotoCompletion = completion
            photoOutput.capturePhoto(with: settings, delegate: self)
        }
    }

    func togglePosition() {
        captureQueue.async { [self] in
            let target: AVCaptureDevice.Position = position == .back ? .front : .back
            guard let replacement = makeInput(position: target) else { return }

            session.beginConfiguration()
            if let videoInput {
                session.removeInput(videoInput)
            }

            if session.canAddInput(replacement) {
                session.addInput(replacement)
                videoInput = replacement
                position = target
                isFlashEnabled = false
            } else if let videoInput, session.canAddInput(videoInput) {
                session.addInput(videoInput)
            }
            session.commitConfiguration()
        }
    }

    func setFlashEnabled(_ enabled: Bool) {
        captureQueue.async { [self] in
            isFlashEnabled = enabled
        }
    }

    private func enqueueStartIfNeeded() {
        captureQueue.async { [self] in
            guard wantsRunning else { return }
            guard configureIfNeeded() else { return }
            if !session.isRunning {
                session.startRunning()
            }
        }
    }

    private func configureIfNeeded() -> Bool {
        if isConfigured { return true }
        guard let input = makeInput(position: position) else { return false }

        session.beginConfiguration()
        defer { session.commitConfiguration() }
        session.sessionPreset = .photo

        guard session.canAddInput(input), session.canAddOutput(photoOutput) else {
            return false
        }

        session.addInput(input)
        session.addOutput(photoOutput)
        #if DEBUG
        CameraIdentityProbe.shared.observeSession(session)
        identityVideoOutput.alwaysDiscardsLateVideoFrames = true
        identityVideoOutput.setSampleBufferDelegate(self, queue: captureQueue)
        if session.canAddOutput(identityVideoOutput) {
            session.addOutput(identityVideoOutput)
        }
        #endif
        videoInput = input
        isConfigured = true
        return true
    }

    private func makeInput(position: AVCaptureDevice.Position) -> AVCaptureDeviceInput? {
        guard let device = AVCaptureDevice.default(
            .builtInWideAngleCamera,
            for: .video,
            position: position
        ) else {
            return nil
        }
        return try? AVCaptureDeviceInput(device: device)
    }
}

nonisolated extension CameraCaptureSession: AVCapturePhotoCaptureDelegate {
    func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: (any Error)?
    ) {
        let data = error == nil ? photo.fileDataRepresentation() : nil

        captureQueue.async { [self] in
            guard let completion = pendingPhotoCompletion else { return }
            pendingPhotoCompletion = nil
            Task { @MainActor in completion(data) }
        }
    }
}

#if DEBUG
nonisolated extension CameraCaptureSession: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        CameraIdentityProbe.shared.recordFrame(hostTime: CACurrentMediaTime())
    }
}
#endif

/// Carries the running camera and its preview view from the grid cell to the camera overlay.
/// The overlay reparents `previewView`; `restore` puts it back into `parentView`.
final class CameraHolder {
    let camera: CameraSession
    let previewView: CameraPreviewSource
    weak var parentView: UIView?
    let restore: () -> Void

    init(
        camera: CameraSession,
        previewView: CameraPreviewSource,
        parentView: UIView,
        restore: @escaping () -> Void
    ) {
        self.camera = camera
        self.previewView = previewView
        self.parentView = parentView
        self.restore = restore
    }
}
