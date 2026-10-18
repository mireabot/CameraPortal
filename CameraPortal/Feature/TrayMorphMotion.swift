//
//  TrayMorphMotion.swift
//  CameraPortal
//
//  Motion tokens for the attach-button -> tray morph, ported from SwiftUX's
//  Transition_MorphingActionMenu (MorphingActionMenuMotion.swift).
//

import SwiftUI

// MARK: - Distortion

/// The squash-and-stretch applied mid-flight, while the button is becoming the tray.
///
/// Every value peaks at the halfway point and is back to zero at both ends, so the
/// surface is undistorted at rest in *both* states with nothing having to be reset —
/// see `TrayMorphSurface.flight`.
struct MorphDistortion {
    /// Added to the scale at peak distortion. Negative squashes, positive stretches.
    var scaleX: CGFloat
    var scaleY: CGFloat
    /// Mid-flight displacement, in the direction the surface is travelling.
    var offset: CGSize
    /// Peak blur. What sells the morph as one substance re-forming rather than two
    /// shapes crossfading: the shape is least readable exactly when it is least rectangular.
    var blurRadius: CGFloat
    /// Fraction of the morph spent handing the label over to the content.
    ///
    /// The two do **not** crossfade across the whole flight: the glyph is gone by
    /// `handoff` and the tray only starts arriving after it, so there is never a frame
    /// with a half-visible paperclip sitting on a half-visible grid.
    var handoff: CGFloat = 0.35

    /// Mirror of the source component's `.trailingToLeading`, for a bottom-**leading**
    /// anchor: the tray travels up and to the trailing edge, so it stretches horizontally
    /// and squashes vertically on the way, and hops that way at the midpoint.
    static let leadingToTrailing = MorphDistortion(
        scaleX: 0.10,
        scaleY: -0.07,
        offset: CGSize(width: 12, height: -8),
        blurRadius: 12
    )

    /// Centre-anchored equivalent, kept for comparison while tuning.
    static let vertical = MorphDistortion(
        scaleX: -0.5,
        scaleY: 0.35,
        offset: CGSize(width: 0, height: -80),
        blurRadius: 14
    )
}

// MARK: - Motion

/// The one curve the whole morph runs on.
///
/// Open and close are the *same* animation played in opposite directions, which is why
/// this is a single token and not a pair. A shorter close curve breaks the illusion: the
/// tray stops being an object that grew out of the button and becomes a sheet that shrinks.
struct TrayMorphMotion {
    /// Mirrors `accessibilityReduceMotion` (plus the debug override). Reduced motion means
    /// *gentler*, not none — the growth is what explains where the tray came from, so what
    /// comes off is the bounce and the distortion.
    var reduceMotion = false

    var morph: Animation {
        reduceMotion
            ? .easeOut(duration: 0.25)
            : .smooth(duration: 0.5)
    }

    /// Scales the distortion to nothing under reduced motion, rather than branching at the
    /// call site — the surface keeps one modifier chain and only the numbers change.
    var distortionScale: CGFloat {
        reduceMotion ? 0 : 1
    }
}
