import UIKit

/// Screens that rely on fixed geometry (CameraPortal) pin the interface orientation.
enum OrientationLock {
    static var mask: UIInterfaceOrientationMask = .all {
        didSet {
            guard mask != oldValue else { return }
            applyToActiveScene()
        }
    }

    /// Re-requests the current mask. Needed when the mask was set before the scene became
    /// foreground-active (e.g. in the first `onAppear`), where the request is skipped.
    static func reapply() {
        applyToActiveScene()
    }

    private static func applyToActiveScene() {
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }) else { return }
        scene.keyWindow?.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
        scene.requestGeometryUpdate(.iOS(interfaceOrientations: mask))
    }
}

final class OrientationLockAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        supportedInterfaceOrientationsFor window: UIWindow?
    ) -> UIInterfaceOrientationMask {
        OrientationLock.mask
    }
}
