//
//  ChatScreen.swift
//  CameraPortal
//
//  The chat: a placeholder conversation, the input bar, and the attachment tray that
//  morphs out of the attach button as one glass surface. Everything here is SwiftUI; the
//  only UIKit left in the feature is inside the tray (MediaTrayView -> MediaTrayContentView).
//

import SwiftUI
import UIKit

struct ChatScreen: View {
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion

    /// 0 is the attach button, 1 is the open tray. A value rather than a Bool, because the
    /// surface is animatable on it — and because a launch argument can pin it mid-flight.
    @State private var trayProgress: CGFloat = CameraPortalDebug.pinnedProgress ?? 0
    @State private var metrics = TrayMetrics()
    @State private var displayCornerRadius: CGFloat = 0
    @State private var isCameraOpen = false
    @State private var isTrayHeaderVisible = true
    @State private var headerRevealTask: Task<Void, Never>?
    @State private var forcesReducedMotion = false
    @State private var slowAnimations = false
    @State private var feedbackTick = 0
    @State private var trayController = MediaTrayController()
    @FocusState private var isInputFocused: Bool

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            chatContent
            scrim
            traySurface
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle("Camera Portal")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { debugToolbar }
        #if DEBUG
        // Outside the tray's morph surface on purpose: it must never become part of what is
        // being measured, so it hangs off the screen's own overlay and takes no touches.
        .overlay(alignment: .topLeading) {
            if CameraPortalDebug.showsIdentityHUD {
                CameraIdentityHUD()
                    .padding(10)
            }
        }
        #endif
        .sensoryFeedback(.impact(weight: .light), trigger: feedbackTick)
        .onAppear {
            OrientationLock.mask = .portrait
            displayCornerRadius = ScreenCornerRadius.currentDisplay
        }
        .onDisappear {
            headerRevealTask?.cancel()
            OrientationLock.mask = .all
        }
        .onChange(of: slowAnimations) { _, slow in applyAnimationSpeed(slow) }
        .task {
            #if DEBUG
            // Ahead of any auto-demo, so the tray opens *into* a raised keyboard and the
            // resign-on-open can be seen.
            if CameraPortalDebug.focusesInput {
                try? await Task.sleep(for: .milliseconds(400))
                isInputFocused = true
            }
            if CameraPortalDebug.identityCycles > 0 {
                await runIdentityCheck(cycles: CameraPortalDebug.identityCycles)
                return
            }
            #endif
            await runAutoDemo()
        }
    }

    // MARK: - Layers

    private var chatContent: some View {
        VStack(spacing: 0) {
            ChatMessageList(messages: ChatMessage.samples)
            ChatInputBar(isFocused: $isInputFocused)
        }
        // Nothing behind the tray is tappable while it is open — the scrim owns dismissal.
        // Driven off `trayProgress` itself rather than a second flag: the attach button is
        // not in here (it is the morph surface's label, a sibling above the scrim), so it
        // keeps working at progress 0 and the tray can always be reopened.
        .allowsHitTesting(trayProgress == 0)
        // The tray needs the *window's* geometry, not this view's: it sits 8pt from the
        // physical bottom edge, below everything the safe area protects.
        .onGeometryChange(for: TrayMetrics.self) { proxy in
            TrayMetrics(
                containerWidth: proxy.size.width + proxy.safeAreaInsets.leading + proxy.safeAreaInsets.trailing,
                screenHeight: proxy.size.height + proxy.safeAreaInsets.top + proxy.safeAreaInsets.bottom,
                safeAreaBottom: proxy.safeAreaInsets.bottom
            )
        } action: { metrics = $0 }
    }

    /// Tap-anywhere dismissal, and nothing else: the chat behind the tray keeps its full
    /// brightness. It is not optional as a *target* — the paperclip is gone a third of the
    /// way into the morph, so there is no button left to tap a second time.
    ///
    /// `0.001` rather than `.clear`, because a fully clear colour is not reliably hit-tested.
    @ViewBuilder
    private var scrim: some View {
        if isTrayOpen {
            Color.black
                .opacity(0.001)
                .ignoresSafeArea()
                .contentShape(.rect)
                .onTapGesture { closeTray() }
        }
    }

    private var traySurface: some View {
        TrayMorphSurface(
            progress: trayProgress,
            labelSize: CGSize(width: ChatInputBar.height, height: ChatInputBar.height),
            expandedSize: traySize,
            collapsedCornerRadius: ChatInputBar.height / 2,
            expandedCornerRadius: trayCornerRadius,
            collapsedLift: metrics.safeAreaBottom,
            distortion: .leadingToTrailing,
            distortionScale: motion.distortionScale
        ) {
            MediaTrayView(
                cornerRadius: trayCornerRadius,
                controller: trayController,
                isActive: trayProgress > 0,
                usesReducedMotion: usesReducedMotion,
                headerOpacity: isTrayHeaderVisible ? 1 : 0,
                onClose: closeTray,
                onCameraFocusChanged: cameraFocusChanged
            )
        } label: {
            Button(action: toggleTray) {
                Image(systemName: "paperclip")
                    .glassCircleControl()
            }
            .buttonStyle(.plain)
        }
        .padding(.leading, TrayCameraConfig.margin)
        .padding(.bottom, TrayCameraConfig.margin)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        .ignoresSafeArea(edges: .bottom)
    }

    // MARK: - Derived values

    private var motion: TrayMorphMotion {
        TrayMorphMotion(reduceMotion: usesReducedMotion)
    }

    private var usesReducedMotion: Bool {
        systemReduceMotion || forcesReducedMotion
    }

    private var isTrayOpen: Bool { trayProgress > 0 }

    /// Concentric with the display: the tray is inset by `margin` on the left, right and
    /// bottom, so its corners are the display's radius less that inset.
    private var trayCornerRadius: CGFloat {
        CameraPortalGeometry.concentricRadius(
            outer: displayCornerRadius,
            inset: TrayCameraConfig.margin,
            minimum: 16
        )
    }

    private var traySize: CGSize {
        CGSize(
            width: max(0, metrics.containerWidth - TrayCameraConfig.margin * 2),
            height: (metrics.screenHeight * TrayCameraConfig.trayHeightFraction).rounded()
        )
    }

    // MARK: - Actions

    /// The title leaves on the same event that starts the camera transition. It returns only
    /// after UIKit reports that dismissal has completed, plus a short separation beat.
    private func cameraFocusChanged(_ isOpen: Bool) {
        isCameraOpen = isOpen
        headerRevealTask?.cancel()

        if isOpen {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                isTrayHeaderVisible = false
            }
            return
        }

        headerRevealTask = Task { @MainActor in
            do {
                try await Task.sleep(for: .milliseconds(70))
            } catch {
                return
            }

            guard !isCameraOpen else { return }
            withAnimation(.easeOut(duration: 0.12)) {
                isTrayHeaderVisible = true
            }
        }
    }

    private func toggleTray() {
        isTrayOpen ? closeTray() : openTray()
    }

    private func openTray() {
        feedbackTick += 1
        // Before the morph, not during it: a keyboard sliding out from under the growing
        // tray reads as two screens fighting. Hit testing is off for the whole bar from the
        // same frame, so the field cannot take focus back mid-morph either.
        isInputFocused = false
        withAnimation(motion.morph) { trayProgress = 1 }
    }

    /// The camera owns the tray while it is open: it has its own dismissal (the close
    /// button and the downward pan), and the tray must not go out from under it.
    private func closeTray() {
        guard isTrayOpen, !isCameraOpen else { return }
        feedbackTick += 1
        withAnimation(motion.morph) { trayProgress = 0 }
    }

    // MARK: - Debug

    @ToolbarContentBuilder
    private var debugToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                slowAnimations.toggle()
            } label: {
                Image(systemName: "tortoise")
                    .foregroundStyle(slowAnimations ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                forcesReducedMotion.toggle()
            } label: {
                Image(systemName: "figure.walk.motion")
                    .foregroundStyle(forcesReducedMotion ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
            }
        }
    }

    private func applyAnimationSpeed(_ slow: Bool) {
        let windows = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
        for window in windows {
            window.layer.speed = slow ? 0.1 : 1
        }
    }

    /// See `CameraPortalDebug`. Modes: tray | camera | cycle | slow.
    private func runAutoDemo() async {
        #if DEBUG
        guard CameraPortalDebug.pinnedProgress == nil,
              let mode = CameraPortalDebug.autoDemoMode else { return }

        print("[CameraPortal] display radius \(displayCornerRadius), tray radius \(trayCornerRadius), tray \(traySize), safe bottom \(metrics.safeAreaBottom)")
        try? await Task.sleep(for: .seconds(0.8))
        if mode == "slow" { slowAnimations = true }
        openTray()
        guard mode != "tray" else { return }

        try? await Task.sleep(for: .seconds(mode == "slow" ? 6 : 1.2))
        trayController.openCamera()
        if CameraPortalDebug.showsCaptureReview {
            try? await Task.sleep(for: .seconds(1))
            trayController.showCaptureReview()
        }
        guard mode == "cycle" || mode == "slow" else { return }

        try? await Task.sleep(for: .seconds(mode == "slow" ? 8 : 2))
        trayController.closeCamera()
        try? await Task.sleep(for: .seconds(1.2))
        closeTray()
        #endif
    }

    #if DEBUG
    /// Reparents the same preview into and out of the camera canvas N times.
    ///
    /// By default the tray stays open for the whole run, so the only thing moving is the
    /// preview. `-CameraPortalIdentityTray 1` adds the tray's own close/reopen to each cycle,
    /// which is the literal four-step loop — and which also tears the session down and back
    /// up, because `MediaTrayContentView.setCameraActive(false)` calls `stopCapture()`. Both
    /// are worth running: the first isolates the morph, the second shows what the tray's
    /// lifecycle policy costs.
    ///
    /// Every sleep is a settle: the morph is 0.3s, so 0.65s leaves it finished and stable
    /// before the next step fires.
    private func runIdentityCheck(cycles: Int) async {
        let probe = CameraIdentityProbe.shared
        let cyclesTray = CameraPortalDebug.identityCyclesTray
        probe.begin(cycles: cycles)

        try? await Task.sleep(for: .milliseconds(500))
        openTray()
        try? await Task.sleep(for: .milliseconds(1_200))

        for cycle in 1...cycles {
            guard !Task.isCancelled else { return }
            probe.setCycle(cycle)

            if cyclesTray, !isTrayOpen {
                openTray()
                try? await Task.sleep(for: .milliseconds(900))
            }

            trayController.openCamera()
            try? await Task.sleep(for: .milliseconds(650))
            trayController.closeCamera()
            try? await Task.sleep(for: .milliseconds(650))

            if cyclesTray {
                closeTray()
                try? await Task.sleep(for: .milliseconds(900))
            }
        }

        probe.printVerdict()
        probe.assertStableIdentityAndFrames()
    }
    #endif
}

// MARK: - Metrics

/// What the tray needs from the window: its full width and height (the tray is measured
/// against the screen, not against the safe area) and the bottom inset the collapsed button
/// sits above.
/// `nonisolated` because `onGeometryChange` wants a `Sendable` value: the module defaults
/// to `MainActor` isolation, which would otherwise isolate the `Equatable` conformance too.
nonisolated struct TrayMetrics: Equatable, Sendable {
    var containerWidth: CGFloat = 0
    var screenHeight: CGFloat = 0
    var safeAreaBottom: CGFloat = 0
}

#Preview {
    NavigationStack {
        ChatScreen()
    }
}
