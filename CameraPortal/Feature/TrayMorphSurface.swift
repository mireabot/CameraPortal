//
//  TrayMorphSurface.swift
//  CameraPortal
//
//  One surface that morphs between the attach button and the media tray. Adapted from
//  SwiftUX's Transition_MorphingActionMenu (MorphingActionMenuSurface.swift); the component's
//  `GlassContainer` / `BlurConfig` helpers and its lime tint are dropped, and the material is
//  an interpolating fill rather than glass — see the note in the body for why.
//
//  Three deviations from the source, all because the expanded content is a tray with a live
//  UIKit view in it rather than a menu panel:
//  - the expanded size is *given*, not measured. The tray has no natural size (the UIKit
//    grid fills whatever it gets), and measuring it under `fixedSize` would hand the
//    measurement its own output back as input.
//  - `collapsedLift` moves the anchor itself, because the button lives above the home
//    indicator while the tray is 8pt from the physical screen edge, where its corners can be
//    concentric with the display's.
//  - no `GlassEffectContainer`, and the derived curves are clamped. See the body.
//

import SwiftUI

struct TrayMorphSurface<Content: View, Label: View>: View, Animatable {
    /// 0 is the attach button, 1 is the open tray. Driven from outside so a caller can
    /// animate it, scrub it, or pin it for a screenshot.
    var progress: CGFloat
    /// The collapsed puck. Fixed, because at rest the tray is not laid out to be measured.
    var labelSize: CGSize
    /// The tray's resting size.
    var expandedSize: CGSize
    var collapsedCornerRadius: CGFloat
    var expandedCornerRadius: CGFloat
    /// How far above the resting anchor the collapsed label sits (the bottom safe area).
    var collapsedLift: CGFloat = 0
    var distortion: MorphDistortion = .leadingToTrailing
    /// Scales the distortion; 0 removes it. Fed from the motion token.
    var distortionScale: CGFloat = 1

    @ViewBuilder var content: Content
    @ViewBuilder var label: Label

    /// Without this, `withAnimation` interpolates the resulting *frame* and re-runs the
    /// body twice — the morph snaps between two layouts with a spring on the outside.
    /// With it, every curve below is evaluated per frame.
    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            trayLayer
            labelLayer
        }
        .frame(width: surfaceSize.width, height: surfaceSize.height, alignment: .bottomLeading)
        // The surface's material is a *fill that interpolates*, not glass.
        //
        // The finding behind that, measured with a probe rather than reasoned: **glass does
        // not sample the window backdrop inside a view that conforms to `Animatable`.** This
        // exact chain rebuilt by hand without the conformance lenses whatever is behind it;
        // with the conformance it renders flat, and so does anything whose own backdrop is
        // this surface — which is why the attach button in the label slot and the UIKit
        // controls inside the hosted tray use tints and fills rather than real glass.
        // Everything else is innocent: `compositingGroup`, `blur`, `opacity`, `clipShape`,
        // `scaleEffect`, `offset`, a `Button` wrapper, a hosted `UIView` sibling, and glass
        // nested in glass all sample correctly. Lifting the button out to a sibling does
        // restore its sampling — and costs the continuous morph, which is the point here.
        //
        // A colour has no such problem: it interpolates per frame like every other animatable
        // value, so the surface fades from nothing at rest to the tray's own background as it
        // expands. The `.glassEffect` that used to sit here is gone rather than kept
        // underneath: at rest it was the washed-out white puck behind the button, and at full
        // size this opaque fill covers it completely — it was a render pass paying for
        // nothing at both ends.
        .background(surfaceFill)
        .compositingGroup()
        .clipShape(shape)
        .scaleEffect(
            x: 1 + (distortion.scaleX * flight * distortionScale),
            y: 1 + (distortion.scaleY * flight * distortionScale),
            anchor: .bottomLeading
        )
        .offset(
            x: distortion.offset.width * flight * distortionScale,
            y: distortion.offset.height * flight * distortionScale - collapsedLift * (1 - contentOpacity)
        )
    }

    // MARK: - Layers

    /// The tray, scaled down into the button's footprint so it reads as being *inside* the
    /// glass from the first frame rather than arriving over it. It keeps its resting size
    /// at every progress, so the UIKit grid underneath lays out once instead of per frame.
    private var trayLayer: some View {
        content
            .frame(width: expandedSize.width, height: expandedSize.height)
            .compositingGroup()
            .scaleEffect(contentScale, anchor: .bottomLeading)
            .blur(radius: distortion.blurRadius * flight * distortionScale)
            .opacity(contentOpacity)
            .allowsHitTesting(contentOpacity > 0)
    }

    private var labelLayer: some View {
        label
            .compositingGroup()
            .blur(radius: distortion.blurRadius * flight * distortionScale)
            .opacity(1 - labelOpacity)
            .allowsHitTesting(labelOpacity < 1)
            .frame(width: labelSize.width, height: labelSize.height)
    }

    // MARK: - Curves

    private var shape: ConcentricRectangle {
        ConcentricRectangle(
            corners: .concentric(minimum: .fixed(currentCornerRadius)),
            isUniform: true
        )
    }

    /// The tray's background, on the *label's* curve rather than the content's: it is solid
    /// exactly when the glyph finishes leaving, at `handoff`, so the surface becomes the
    /// object at the same moment the button stops being it. The content then arrives on its
    /// own curve into something already opaque, instead of fading in over visible chat —
    /// which is what `contentOpacity` here gave, and it read as see-through at 0.8.
    private var surfaceFill: Color {
        Color(uiColor: .systemBackground).opacity(labelOpacity)
    }

    /// How much of the label's fade is done. Complete by `handoff`.
    private var labelOpacity: CGFloat {
        min(progress / distortion.handoff, 1)
    }

    /// How much of the tray's arrival is done. Starts at `handoff`.
    private var contentOpacity: CGFloat {
        let raw = max(progress - distortion.handoff, 0) / (1 - distortion.handoff)
        // Clamped, and it is not cosmetic: unclamped this lands on 1.0000000000000002 at
        // rest, which leaves SwiftUI an opacity layer over the hosted UIKit tray forever.
        return min(max(raw, 0), 1)
    }

    /// The frame grows on the tray's own curve, not on `progress`: a button that stretches
    /// while the glyph is still in it looks like a layout error.
    private var surfaceSize: CGSize {
        CGSize(
            width: labelSize.width + max(expandedSize.width - labelSize.width, 0) * contentOpacity,
            height: labelSize.height + max(expandedSize.height - labelSize.height, 0) * contentOpacity
        )
    }

    private var contentScale: CGFloat {
        guard expandedSize.width > 0, expandedSize.height > 0 else { return 1 }
        guard progress < 1 else { return 1 }
        let fitted = min(
            labelSize.width / expandedSize.width,
            labelSize.height / expandedSize.height
        )
        return fitted + (1 - fitted) * progress
    }

    /// The minimum follows the frame's curve, while `ConcentricRectangle` resolves the true
    /// radius from the containing display and keeps all four corners uniform.
    private var currentCornerRadius: CGFloat {
        collapsedCornerRadius + (expandedCornerRadius - collapsedCornerRadius) * contentOpacity
    }

    /// A triangle: 0 at both ends, 1 at the halfway point. Everything decorative hangs off
    /// this, which is what guarantees the surface is undistorted at rest in *both* states.
    private var flight: CGFloat {
        progress > 0.5 ? (1 - progress) / 0.5 : progress / 0.5
    }
}

// MARK: - Previews

/// Scrubbing is the only way to actually see the middle of this animation.
#Preview("Scrub") {
    @Previewable @State var progress: CGFloat = 0

    ZStack(alignment: .bottomLeading) {
        LinearGradient(colors: [.indigo, .teal], startPoint: .top, endPoint: .bottom)
            .ignoresSafeArea()

        TrayMorphSurface(
            progress: progress,
            labelSize: CGSize(width: 40, height: 40),
            expandedSize: CGSize(width: 320, height: 420),
            collapsedCornerRadius: 20,
            expandedCornerRadius: 46
        ) {
            Color.black.opacity(0.25)
        } label: {
            Image(systemName: "paperclip")
        }
        .padding(.leading, 8)
        .padding(.bottom, 8)

        Slider(value: $progress, in: 0...1)
            .padding(40)
    }
}
