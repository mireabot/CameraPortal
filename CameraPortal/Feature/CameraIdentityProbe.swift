//
//  CameraIdentityProbe.swift
//  CameraPortal
//
//  DEBUG-only evidence that the tray -> camera morph *reparents* one live preview instead of
//  quietly rebuilding it. A smooth morph proves nothing: a session that is torn down and
//  reopened looks identical on screen. So this records, at every phase change, the identity
//  of the three objects that must not be replaced (the AVCaptureSession, the CameraPreviewView
//  and its AVCaptureVideoPreviewLayer), counts the session's lifecycle notifications, and
//  tracks a frame counter fed by a DEBUG-only AVCaptureVideoDataOutput.
//
//  The whole file is inside `#if DEBUG`; the release build has no probe and no video output.
//
//  Threading: `recordFrame` runs on CameraCaptureSession's `captureQueue`, the notification
//  observers run on whatever thread posts them, and `sample`/`snapshot` run on the main actor.
//  All of that funnels through one `Mutex`, so the HUD can read counters at 5Hz without ever
//  hopping onto — or contending for — the capture queue.
//

#if DEBUG

import AVFoundation
import QuartzCore
import SwiftUI
import Synchronization
import UIKit

nonisolated final class CameraIdentityProbe: Sendable {
    static let shared = CameraIdentityProbe()

    // MARK: - Phases

    enum Phase: String, Sendable {
        case trayOpened
        case cameraOpened
        case cameraClosed
        case trayClosed

        /// Where the preview view is supposed to be hanging at this point in the cycle.
        var expectedHostName: String {
            switch self {
            case .cameraOpened: "TrayCameraOverlayView.canvasView"
            case .trayOpened, .cameraClosed, .trayClosed: "MediaGridView.cameraWrapperView"
            }
        }
    }

    // MARK: - Records

    struct Sample: Sendable {
        var cycle: Int
        var phase: Phase
        var time: CFTimeInterval
        var sessionID: ObjectIdentifier
        var previewViewID: ObjectIdentifier
        var previewLayerID: ObjectIdentifier
        /// `previewLayer.session === session` — the layer must still point at the same session.
        var layerSessionMatches: Bool
        var hostMatches: Bool
        var hostName: String
        var isRunning: Bool
        var frameCount: Int
        var startCount: Int
        var stopCount: Int
    }

    private struct GapEvent: Sendable {
        var time: CFTimeInterval
        var gap: Double
    }

    private struct State: Sendable {
        var isObserving = false
        var requestedCycles = 0
        var currentCycle = 0
        var samples: [Sample] = []

        var startCount = 0
        var stopCount = 0
        var interruptionCount = 0
        var runtimeErrorCount = 0
        /// Kept live off the start/stop notifications, so the HUD can show it without
        /// touching the session from the main thread.
        var isRunning = false

        var frameCount = 0
        var lastFrameTime: CFTimeInterval = 0
        var maxGap: Double = 0
        var gapEvents: [GapEvent] = []
        /// The counter is ours and only ever `+= 1`; this would only trip on a probe bug,
        /// but the assertion is cheap and it is the thing the brief asks to prove.
        var sawCounterRegression = false
    }

    /// Gaps below this are not worth remembering; the interesting ones are the stalls.
    private static let gapEventFloor: Double = 0.1
    private static let gapEventLimit = 500

    private let state = Mutex(State())

    private init() {}

    // MARK: - Session lifecycle

    /// Called once from `CameraCaptureSession.configureIfNeeded()`, on `captureQueue`.
    /// The observers are deliberately never removed: the probe and the session both live for
    /// the lifetime of the DEBUG process, and a removal path would need a token store that
    /// buys nothing.
    func observeSession(_ session: AVCaptureSession) {
        let shouldRegister = state.withLock { state -> Bool in
            guard !state.isObserving else { return false }
            state.isObserving = true
            state.isRunning = session.isRunning
            return true
        }
        guard shouldRegister else { return }

        let center = NotificationCenter.default
        _ = center.addObserver(forName: AVCaptureSession.didStartRunningNotification, object: session, queue: nil) { [self] _ in
            state.withLock { $0.startCount += 1; $0.isRunning = true }
        }
        _ = center.addObserver(forName: AVCaptureSession.didStopRunningNotification, object: session, queue: nil) { [self] _ in
            state.withLock { $0.stopCount += 1; $0.isRunning = false }
        }
        _ = center.addObserver(forName: AVCaptureSession.wasInterruptedNotification, object: session, queue: nil) { [self] _ in
            state.withLock { $0.interruptionCount += 1 }
        }
        _ = center.addObserver(forName: AVCaptureSession.runtimeErrorNotification, object: session, queue: nil) { [self] _ in
            state.withLock { $0.runtimeErrorCount += 1 }
        }
    }

    // MARK: - Frames

    /// Called from the DEBUG video data output's delegate, on `captureQueue`.
    func recordFrame(hostTime: CFTimeInterval) {
        state.withLock { state in
            let previous = state.frameCount
            state.frameCount = previous + 1
            if state.frameCount <= previous { state.sawCounterRegression = true }

            defer { state.lastFrameTime = hostTime }
            guard previous > 0, hostTime > state.lastFrameTime else { return }

            let gap = hostTime - state.lastFrameTime
            state.maxGap = max(state.maxGap, gap)
            if gap >= Self.gapEventFloor, state.gapEvents.count < Self.gapEventLimit {
                state.gapEvents.append(GapEvent(time: hostTime, gap: gap))
            }
        }
    }

    // MARK: - Sampling

    func begin(cycles: Int) {
        state.withLock { state in
            state.requestedCycles = cycles
            state.currentCycle = 0
            state.samples.removeAll(keepingCapacity: true)
            state.startCount = 0
            state.stopCount = 0
            state.interruptionCount = 0
            state.runtimeErrorCount = 0
            state.frameCount = 0
            state.lastFrameTime = 0
            state.maxGap = 0
            state.gapEvents.removeAll(keepingCapacity: true)
            state.sawCounterRegression = false
        }
    }

    func setCycle(_ cycle: Int) {
        state.withLock { $0.currentCycle = cycle }
    }

    /// One observation of the whole invariant. Main-actor because it reads UIKit.
    ///
    /// `session.isRunning` is read here rather than hopped onto `captureQueue`: it is a
    /// KVO-compliant, any-thread property, and a synchronous hop would block the main thread
    /// on the very queue that is delivering the frames we are timing.
    @MainActor
    func sample(
        phase: Phase,
        cycle: Int? = nil,
        session: AVCaptureSession,
        previewView: UIView,
        expectedHost: UIView?
    ) {
        let resolvedCycle = cycle ?? state.withLock { $0.currentCycle }
        let layer = previewView.layer
        let previewLayer = layer as? AVCaptureVideoPreviewLayer
        let host = previewView.superview

        let sample = state.withLock { state -> Sample in
            let sample = Sample(
                cycle: resolvedCycle,
                phase: phase,
                time: CACurrentMediaTime(),
                sessionID: ObjectIdentifier(session),
                previewViewID: ObjectIdentifier(previewView),
                previewLayerID: ObjectIdentifier(layer),
                layerSessionMatches: previewLayer?.session === session,
                hostMatches: host != nil && host === expectedHost,
                hostName: host.map { "\(type(of: $0))" } ?? "nil",
                isRunning: session.isRunning,
                frameCount: state.frameCount,
                startCount: state.startCount,
                stopCount: state.stopCount
            )
            state.samples.append(sample)
            state.currentCycle = resolvedCycle
            return sample
        }

        print("[IdentityProbe] cycle \(sample.cycle) \(sample.phase.rawValue) "
            + "session \(Self.shortID(sample.sessionID)) view \(Self.shortID(sample.previewViewID)) "
            + "layer \(Self.shortID(sample.previewLayerID)) host \(sample.hostName) "
            + "running \(sample.isRunning) frames \(sample.frameCount)")
    }

    // MARK: - HUD

    struct Snapshot: Sendable {
        var hasSamples = false
        /// False on a host with no camera, which greys the stream-dependent rows out instead
        /// of showing them as failures.
        var hasDevice = true
        var sessionID = "------"
        var previewViewID = "------"
        var previewLayerID = "------"
        var sessionStable = true
        var viewStable = true
        var layerStable = true
        var startCount = 0
        var stopCount = 0
        var interruptionCount = 0
        var runtimeErrorCount = 0
        var frameCount = 0
        var sessionIdentityCount = 0
        var previewViewIdentityCount = 0
        var previewLayerIdentityCount = 0
        var maxGap: Double = 0
        var isRunning = false
        var cycle = 0
        var totalCycles = 0
    }

    /// Read by the HUD on a timer. One uncontended lock acquisition; no queue hop, so the
    /// capture queue never waits on the display.
    func snapshot() -> Snapshot {
        state.withLock { state in
            var snapshot = Snapshot()
            snapshot.hasDevice = Self.cachedEnvironment.hasDevice
            snapshot.startCount = state.startCount
            snapshot.stopCount = state.stopCount
            snapshot.interruptionCount = state.interruptionCount
            snapshot.runtimeErrorCount = state.runtimeErrorCount
            snapshot.frameCount = state.frameCount
            snapshot.isRunning = state.isRunning
            snapshot.cycle = state.currentCycle
            snapshot.totalCycles = state.requestedCycles
            snapshot.sessionIdentityCount = Set(state.samples.map(\.sessionID)).count
            snapshot.previewViewIdentityCount = Set(state.samples.map(\.previewViewID)).count
            snapshot.previewLayerIdentityCount = Set(state.samples.map(\.previewLayerID)).count

            // A stall that has not ended yet has produced no gap event, so fold the pending
            // one in: a frozen preview grows the number on screen instead of hiding behind
            // the last completed interval.
            var maxGap = state.maxGap
            if state.isRunning, state.frameCount > 0 {
                maxGap = max(maxGap, CACurrentMediaTime() - state.lastFrameTime)
            }
            snapshot.maxGap = maxGap

            guard let first = state.samples.first else { return snapshot }
            snapshot.hasSamples = true
            snapshot.sessionID = Self.shortID(first.sessionID)
            snapshot.previewViewID = Self.shortID(first.previewViewID)
            snapshot.previewLayerID = Self.shortID(first.previewLayerID)
            snapshot.sessionStable = state.samples.allSatisfy { $0.sessionID == first.sessionID }
            snapshot.viewStable = state.samples.allSatisfy { $0.previewViewID == first.previewViewID }
            snapshot.layerStable = state.samples.allSatisfy { $0.previewLayerID == first.previewLayerID }
            return snapshot
        }
    }

    // MARK: - Verdict

    /// `unverified` is the honest third state: on a host with no capture device, nothing about
    /// session continuity or frame delivery can be observed at all, and reporting that as
    /// either a pass or a failure of the morph would be a lie in one direction or the other.
    private enum AssertionResult {
        case pass
        case fail
        case unverified

        var label: String {
            switch self {
            case .pass: "PASS"
            case .fail: "FAIL"
            case .unverified: "SKIP"
            }
        }
    }

    private struct Assertion {
        var name: String
        var result: AssertionResult
        var detail: String

        init(name: String, result: AssertionResult, detail: String) {
            self.name = name
            self.result = result
            self.detail = detail
        }

        init(name: String, passed: Bool, detail: String) {
            self.init(name: name, result: passed ? .pass : .fail, detail: detail)
        }

        /// For everything that needs a live camera: without one the observation is impossible,
        /// not failed.
        init(name: String, passed: Bool, requiresCamera: Bool, detail: String) {
            self.init(
                name: name,
                result: requiresCamera ? (passed ? .pass : .fail) : .unverified,
                detail: detail
            )
        }
    }

    /// What the host actually offered. Without this the verdict cannot tell "the morph tore the
    /// session down" apart from "there was never a session to tear down".
    struct CaptureEnvironment: Sendable {
        var hasDevice: Bool
        var authorization: String

        var summary: String {
            "capture device \(hasDevice ? "present" : "ABSENT"), authorization \(authorization)"
        }
    }

    /// Queried once: a host does not grow a camera mid-run, and the HUD reads this at 5Hz.
    static let cachedEnvironment = captureEnvironment()

    static func captureEnvironment() -> CaptureEnvironment {
        let authorization = switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: "authorized"
        case .denied: "denied"
        case .restricted: "restricted"
        case .notDetermined: "notDetermined"
        @unknown default: "unknown"
        }
        return CaptureEnvironment(
            hasDevice: AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) != nil,
            authorization: authorization
        )
    }

    /// Frames are expected roughly every 1/30s; 0.5s is ~15 dropped frames in a row.
    static let gapThreshold: Double = 0.5

    func printVerdict() {
        let lines = verdictLines()
        for line in lines { print(line) }
    }

    /// The two invariants this exploration exists to prove. The automated driver calls this
    /// after its twentieth collapse, so a visually smooth but rebuilt camera fails loudly.
    func assertStableIdentityAndFrames() {
        let state = state.withLock { $0 }
        let sessionIDs = Set(state.samples.map(\.sessionID))
        let viewIDs = Set(state.samples.map(\.previewViewID))
        let layerIDs = Set(state.samples.map(\.previewLayerID))
        let sampledFrames = state.samples.map(\.frameCount)
        let morphWindows = Self.morphWindows(in: state.samples)

        assert(morphWindows.count == state.requestedCycles, "Only completed \(morphWindows.count)/\(state.requestedCycles) camera morphs")
        assert(sessionIDs.count == 1, "Camera session identity changed: \(sessionIDs.count) distinct sessions")
        assert(viewIDs.count == 1, "Camera preview identity changed: \(viewIDs.count) distinct views")
        assert(layerIDs.count == 1, "Camera preview-layer identity changed: \(layerIDs.count) distinct layers")
        assert(!state.sawCounterRegression && Self.isNonDecreasing(sampledFrames), "Camera frame counter regressed")

        // Without a capture device there is no stream to assert about, and trapping here would
        // turn "the Simulator has no camera" into a crash that looks like a broken morph. The
        // printed verdict already says UNVERIFIED, loudly.
        guard Self.captureEnvironment().hasDevice else { return }
        assert(state.frameCount > 0, "Camera delivered no frames during the identity run")
        assert(
            morphWindows.allSatisfy { $0.end.frameCount > $0.start.frameCount },
            "The camera frame counter failed to advance across at least one morph"
        )
    }

    private func verdictLines() -> [String] {
        let state = state.withLock { $0 }
        let environment = Self.captureEnvironment()
        /// Everything downstream of an actual video stream hangs off this one fact.
        let hasCamera = environment.hasDevice
        var assertions: [Assertion] = []

        guard let first = state.samples.first else {
            return ["IDENTITY CHECK: FAIL (no samples were taken — the driver never ran)"]
        }

        // MARK: identity
        let sessionIDs = Set(state.samples.map(\.sessionID))
        assertions.append(Assertion(
            name: "session identity",
            passed: sessionIDs.count == 1,
            detail: "\(sessionIDs.count) distinct AVCaptureSession id(s) over \(state.samples.count) samples: "
                + sessionIDs.map(Self.shortID).sorted().joined(separator: ", ")
        ))

        let viewIDs = Set(state.samples.map(\.previewViewID))
        assertions.append(Assertion(
            name: "preview view identity",
            passed: viewIDs.count == 1,
            detail: "\(viewIDs.count) distinct CameraPreviewView id(s): "
                + viewIDs.map(Self.shortID).sorted().joined(separator: ", ")
        ))

        let layerIDs = Set(state.samples.map(\.previewLayerID))
        assertions.append(Assertion(
            name: "preview layer identity",
            passed: layerIDs.count == 1,
            detail: "\(layerIDs.count) distinct AVCaptureVideoPreviewLayer id(s): "
                + layerIDs.map(Self.shortID).sorted().joined(separator: ", ")
        ))

        let layerSessionFailures = state.samples.filter { !$0.layerSessionMatches }
        assertions.append(Assertion(
            name: "previewLayer.session === session",
            passed: layerSessionFailures.isEmpty,
            detail: layerSessionFailures.isEmpty
                ? "held at all \(state.samples.count) samples"
                : "broken at \(Self.describe(layerSessionFailures))"
        ))

        let hostFailures = state.samples.filter { !$0.hostMatches }
        assertions.append(Assertion(
            name: "preview superview is the phase's host",
            passed: hostFailures.isEmpty,
            detail: hostFailures.isEmpty
                ? "correct at all \(state.samples.count) samples"
                : hostFailures.map {
                    "cycle \($0.cycle) \($0.phase.rawValue): host \($0.hostName), expected \($0.phase.expectedHostName)"
                }.joined(separator: "; ")
        ))

        // MARK: session continuity
        assertions.append(Assertion(
            name: "didStartRunning fired exactly once",
            passed: state.startCount == 1,
            requiresCamera: hasCamera,
            detail: "\(state.startCount) start notification(s)"
        ))
        assertions.append(Assertion(
            name: "didStopRunning never fired",
            passed: state.stopCount == 0,
            requiresCamera: hasCamera,
            detail: "\(state.stopCount) stop notification(s)"
        ))
        assertions.append(Assertion(
            name: "no interruptions",
            passed: state.interruptionCount == 0,
            requiresCamera: hasCamera,
            detail: "\(state.interruptionCount) interruption(s)"
        ))
        assertions.append(Assertion(
            name: "no runtime errors",
            passed: state.runtimeErrorCount == 0,
            requiresCamera: hasCamera,
            detail: "\(state.runtimeErrorCount) runtime error(s)"
        ))

        // The claim actually under test is about the *morph*, so the same counters are also
        // scoped to it: between the tray-opened and camera-closed samples of each cycle, the
        // camera is handed from the grid cell to the tray and back, and nothing may restart.
        let morphWindows = Self.morphWindows(in: state.samples)
        let morphRestarts = morphWindows.filter { $0.end.startCount != $0.start.startCount || $0.end.stopCount != $0.start.stopCount }
        assertions.append(Assertion(
            name: "no start/stop across the morph itself",
            passed: morphRestarts.isEmpty && !morphWindows.isEmpty,
            requiresCamera: hasCamera,
            detail: morphWindows.isEmpty
                ? "no complete morph window was sampled"
                : (morphRestarts.isEmpty
                    ? "\(morphWindows.count) morph window(s), 0 starts, 0 stops inside them"
                    : morphRestarts.map { "cycle \($0.start.cycle): +\($0.end.startCount - $0.start.startCount) starts, +\($0.end.stopCount - $0.start.stopCount) stops" }.joined(separator: "; "))
        ))

        let notRunning = state.samples.filter { !$0.isRunning }
        assertions.append(Assertion(
            name: "session.isRunning at every sample",
            passed: notRunning.isEmpty,
            requiresCamera: hasCamera,
            detail: notRunning.isEmpty
                ? "running at all \(state.samples.count) samples"
                : "not running at \(Self.describe(notRunning))"
        ))

        // MARK: frames
        let sawFrames = state.frameCount > 0
        assertions.append(Assertion(
            name: "frame counter monotonic",
            passed: sawFrames && !state.sawCounterRegression && Self.isNonDecreasing(state.samples.map(\.frameCount)),
            requiresCamera: hasCamera,
            detail: sawFrames
                ? "\(state.frameCount) frames, per-sample counts \(Self.isNonDecreasing(state.samples.map(\.frameCount)) ? "never decrease" : "DECREASE")"
                : "UNVERIFIED — no frames were delivered at all"
        ))

        let morphFrameStalls = morphWindows.filter { $0.end.frameCount <= $0.start.frameCount }
        assertions.append(Assertion(
            name: "frames arrive across every morph",
            passed: sawFrames && morphFrameStalls.isEmpty && !morphWindows.isEmpty,
            requiresCamera: hasCamera,
            detail: !sawFrames
                ? "UNVERIFIED — no frames were delivered at all"
                : (morphFrameStalls.isEmpty
                    ? "every morph window advanced the counter"
                    : morphFrameStalls.map { "cycle \($0.start.cycle): \($0.start.frameCount) -> \($0.end.frameCount)" }.joined(separator: "; "))
        ))

        assertions.append(Assertion(
            name: "no inter-frame gap > \(Self.format(Self.gapThreshold))s (whole run)",
            passed: sawFrames && state.maxGap <= Self.gapThreshold,
            requiresCamera: hasCamera,
            detail: sawFrames
                ? "max gap \(Self.format(state.maxGap))s"
                : "UNVERIFIED — no frames were delivered at all"
        ))

        let morphGap = morphWindows.reduce(0.0) { partial, window in
            let inside = state.gapEvents
                .filter { $0.time >= window.start.time && $0.time <= window.end.time }
                .map(\.gap)
                .max() ?? 0
            return max(partial, inside)
        }
        assertions.append(Assertion(
            name: "no inter-frame gap > \(Self.format(Self.gapThreshold))s (inside the morph)",
            passed: sawFrames && morphGap <= Self.gapThreshold,
            requiresCamera: hasCamera,
            detail: sawFrames
                ? "max gap inside a morph window \(Self.format(morphGap))s"
                : "UNVERIFIED — no frames were delivered at all"
        ))

        // MARK: output
        var lines: [String] = []
        lines.append("================ CAMERA IDENTITY CHECK ================")
        lines.append("host: \(environment.summary)")
        lines.append("cycles requested \(state.requestedCycles), samples \(state.samples.count), "
            + "session \(Self.shortID(first.sessionID)), view \(Self.shortID(first.previewViewID)), "
            + "layer \(Self.shortID(first.previewLayerID))")
        for assertion in assertions {
            lines.append("  \(assertion.result.label)  \(assertion.name) — \(assertion.detail)")
        }

        let failures = assertions.filter { $0.result == .fail }
        let unverified = assertions.filter { $0.result == .unverified }
        let summary = "(\(state.requestedCycles) cycles, \(state.startCount) start"
            + (state.startCount == 1 ? "" : "s")
            + ", \(state.frameCount) frames, max gap \(Self.format(state.maxGap))s)"

        if !failures.isEmpty {
            lines.append("IDENTITY CHECK: FAIL \(summary) — violated: "
                + failures.map(\.name).joined(separator: " | "))
        } else if unverified.isEmpty {
            lines.append("IDENTITY CHECK: PASS \(summary)")
        } else {
            // Not a pass: the identity half held, and the half that needs a live stream was
            // never observable on this host. Saying PASS here would be the fake the brief
            // warns about.
            lines.append("IDENTITY CHECK: PASS (identity) + \(unverified.count) UNVERIFIED \(summary)"
                + " — no capture device on this host, so these could not be observed: "
                + unverified.map(\.name).joined(separator: " | "))
        }
        lines.append("=======================================================")
        return lines
    }

    // MARK: - Helpers

    private struct MorphWindow {
        var start: Sample
        var end: Sample
    }

    /// Pairs each cycle's `trayOpened` with its `cameraClosed`: the span in which the preview
    /// leaves the grid cell, fills the tray and comes back.
    private static func morphWindows(in samples: [Sample]) -> [MorphWindow] {
        var windows: [MorphWindow] = []
        var pendingStart: Sample?
        for sample in samples {
            switch sample.phase {
            case .trayOpened:
                pendingStart = sample
            case .cameraClosed:
                if let start = pendingStart, start.cycle == sample.cycle {
                    windows.append(MorphWindow(start: start, end: sample))
                }
                pendingStart = nil
            case .cameraOpened, .trayClosed:
                break
            }
        }
        return windows
    }

    private static func isNonDecreasing(_ values: [Int]) -> Bool {
        zip(values, values.dropFirst()).allSatisfy { $0 <= $1 }
    }

    private static func describe(_ samples: [Sample]) -> String {
        samples.prefix(5).map { "cycle \($0.cycle) \($0.phase.rawValue)" }.joined(separator: ", ")
            + (samples.count > 5 ? " (+\(samples.count - 5) more)" : "")
    }

    static func shortID(_ id: ObjectIdentifier) -> String {
        String(format: "%06llx", UInt64(UInt(bitPattern: id)) & 0xFF_FFFF)
    }

    static func format(_ value: Double) -> String {
        String(format: "%.2f", value)
    }
}

/// The same assertions the console verdict prints, but live, so an expand/collapse cycle can
/// be screen-recorded with the counters visible beside the morph.
///
/// It samples the probe on a 5Hz timer rather than being pushed from the capture queue: the
/// delegate writes ~30 times a second and must never drive a SwiftUI update. The view owns
/// its own `@State`, so the ticking never invalidates the chat or the tray around it.
@MainActor
struct CameraIdentityHUD: View {
    @State private var snapshot = CameraIdentityProbe.shared.snapshot()

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("CAMERA IDENTITY")
                .foregroundStyle(.secondary)

            // The headline: a session that was torn down and reopened shows a 2 here, no
            // matter how smooth the morph looked.
            row(
                "start",
                value: "\(snapshot.startCount)",
                ok: snapshot.startCount == 1,
                pending: !snapshot.hasDevice || snapshot.startCount == 0
            )
            row(
                "session",
                value: snapshot.sessionID,
                ok: snapshot.sessionStable,
                pending: !snapshot.hasSamples
            )
            row(
                "view",
                value: snapshot.previewViewID,
                ok: snapshot.viewStable,
                pending: !snapshot.hasSamples
            )
            row(
                "layer",
                value: snapshot.previewLayerID,
                ok: snapshot.layerStable,
                pending: !snapshot.hasSamples
            )
            row(
                "stop/int/err",
                value: "\(snapshot.stopCount)/\(snapshot.interruptionCount)/\(snapshot.runtimeErrorCount)",
                ok: snapshot.stopCount == 0 && snapshot.interruptionCount == 0 && snapshot.runtimeErrorCount == 0,
                pending: !snapshot.hasDevice
            )
            row(
                "frames",
                value: "\(snapshot.frameCount)",
                ok: snapshot.frameCount > 0,
                pending: !snapshot.hasDevice || snapshot.frameCount == 0
            )
            row(
                "max gap",
                value: "\(CameraIdentityProbe.format(snapshot.maxGap))s",
                ok: snapshot.maxGap <= CameraIdentityProbe.gapThreshold,
                pending: !snapshot.hasDevice || snapshot.frameCount == 0
            )
            row(
                "running",
                value: snapshot.isRunning ? "yes" : "no",
                ok: snapshot.isRunning,
                pending: !snapshot.hasDevice
            )

            if !snapshot.hasDevice {
                Text("no capture device")
                    .foregroundStyle(.yellow)
            }

            if snapshot.totalCycles > 0 {
                Text("cycle \(snapshot.cycle)/\(snapshot.totalCycles)")
                    .foregroundStyle(.white.opacity(0.6))
            }
        }
        // Monospaced *and* monospacedDigit: the glyph width never changes, so a counter
        // ticking 30 times a second does not make the panel twitch in a screen recording.
        .font(.system(size: 10, weight: .semibold, design: .monospaced))
        .monospacedDigit()
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(.black.opacity(0.55), in: .rect(cornerRadius: 10, style: .continuous))
        .allowsHitTesting(false)
        .task {
            while !Task.isCancelled {
                snapshot = CameraIdentityProbe.shared.snapshot()
                do {
                    try await Task.sleep(for: .milliseconds(200))
                } catch {
                    return
                }
            }
        }
    }

    /// `pending` is the "nothing has happened yet" grey, so an un-started run does not read
    /// as a failure.
    private func row(_ label: String, value: String, ok: Bool, pending: Bool) -> some View {
        HStack(spacing: 5) {
            Text(label)
                // Wide enough for the longest label ("stop/int/err") at this size: a wrapped
                // label would shift every row below it as the numbers tick.
                .frame(width: 86, alignment: .leading)
                .lineLimit(1)
                .foregroundStyle(.white.opacity(0.6))
            Text(value)
                .frame(width: 54, alignment: .leading)
                .foregroundStyle(.white)
            Text(pending ? "··" : (ok ? "OK" : "FAIL"))
                .foregroundStyle(pending ? Color.white.opacity(0.4) : (ok ? .green : .red))
        }
    }
}

#endif
