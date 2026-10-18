//
//  CameraPortalDebug.swift
//  CameraPortal
//
//  Launch arguments that drive the exploration without touch input, so every state can be
//  screenshotted from the command line. All of them are DEBUG-only and default to the
//  normal, hand-driven app.
//
//    -CameraPortalAutoDemo tray|camera|cycle|slow
//                                         open the tray, then the camera, then close them
//    -CameraPortalMorphProgress 0.5       pin the morph part-way and leave it there
//    -CameraPortalCameraMenu expanded     start the camera's control menu separated
//    -CameraPortalFocusInput 1            focus the message field on launch
//    -CameraPortalCaptureReview 1         drop the camera into its capture-review state
//    -CameraPortalIdentityCycles 20       expand/collapse one live camera 20 times, assert
//                                         stable session/view/layer identity and frame count
//    -CameraPortalIdentityTray 1          close and reopen the tray inside each of those
//                                         cycles as well (the tray stops the session)
//    -CameraPortalIdentityHUD 1           show the live counters over the chat
//

import SwiftUI

enum CameraPortalDebug {
    static var autoDemoMode: String? {
        #if DEBUG
        UserDefaults.standard.string(forKey: "CameraPortalAutoDemo")
        #else
        nil
        #endif
    }

    /// A pinned morph progress, for catching the middle of the animation in a screenshot.
    static var pinnedProgress: CGFloat? {
        #if DEBUG
        guard UserDefaults.standard.object(forKey: "CameraPortalMorphProgress") != nil else { return nil }
        return CGFloat(UserDefaults.standard.double(forKey: "CameraPortalMorphProgress"))
        #else
        nil
        #endif
    }

    /// Focuses the message field on launch, so the keyboard's behaviour can be seen without
    /// a tap.
    static var focusesInput: Bool {
        #if DEBUG
        UserDefaults.standard.bool(forKey: "CameraPortalFocusInput")
        #else
        false
        #endif
    }

    /// Shows the capture-review controls without a shutter press.
    static var showsCaptureReview: Bool {
        #if DEBUG
        UserDefaults.standard.bool(forKey: "CameraPortalCaptureReview")
        #else
        false
        #endif
    }

    /// Opens the camera's glass menu without a tap, so its separated droplets can be
    /// screenshotted.
    static var expandsCameraMenu: Bool {
        #if DEBUG
        UserDefaults.standard.string(forKey: "CameraPortalCameraMenu") == "expanded"
        #else
        false
        #endif
    }

    /// Runs the view-identity proof on a real camera: N automated open/close morphs, then the
    /// printed verdict and the hard assertions.
    static var identityCycles: Int {
        #if DEBUG
        max(0, UserDefaults.standard.integer(forKey: "CameraPortalIdentityCycles"))
        #else
        0
        #endif
    }

    /// Adds the tray's own close/open to each identity cycle, i.e. the literal
    /// tray -> camera -> camera -> tray loop. Off by default because closing the tray also
    /// stops the capture session (`MediaTrayContentView.setCameraActive`), which is a
    /// lifecycle policy rather than anything the morph does — see the check's own output.
    static var identityCyclesTray: Bool {
        #if DEBUG
        UserDefaults.standard.bool(forKey: "CameraPortalIdentityTray")
        #else
        false
        #endif
    }

    /// The live counter overlay. Off by default so it never sits over the feature during a
    /// hand-driven run; on automatically whenever the automated check is driving, because
    /// that is exactly when someone wants to watch the numbers hold.
    static var showsIdentityHUD: Bool {
        #if DEBUG
        UserDefaults.standard.bool(forKey: "CameraPortalIdentityHUD") || identityCycles > 0
        #else
        false
        #endif
    }
}
