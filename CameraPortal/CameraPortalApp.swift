//
//  CameraPortalApp.swift
//  CameraPortal
//
//  Created by Mikhail Kolkov on 10/18/26.
//

import SwiftUI

@main
struct CameraPortalApp: App {
    @UIApplicationDelegateAdaptor(OrientationLockAppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
