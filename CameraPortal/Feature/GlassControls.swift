//
//  GlassControls.swift
//  CameraPortal
//
//  One definition of "round glass control" per side of the bridge, because the feature has
//  them in both: 44pt circle, black at 0.8, white SF Symbol. Every icon-only control in the
//  tray, the camera and the input bar goes through one of these two, so the numbers live
//  here and nowhere else.
//
//  The SwiftUI half is real Liquid Glass. The UIKit half cannot be — see the note below the
//  MARK; it matches the look with a plain fill.
//
//  Not covered on purpose: the shutter (it is a shutter, not an icon button), the capture
//  review pills (they carry text and are wider than they are tall — they take the tint from
//  here but keep their capsule), and the debug toolbar items (system nav-bar chrome).
//

import SwiftUI
import UIKit

// MARK: - Shared values

extension Color {
    /// The control tint. Dark enough to carry a white glyph over a camera preview, and the
    /// same over the tray's own glass.
    static let glassControlTint = Color.black.opacity(TrayCameraConfig.controlTintOpacity)
}

extension UIColor {
    static let glassControlTint = UIColor.black.withAlphaComponent(TrayCameraConfig.controlTintOpacity)
    /// Retake: the same material, in the colour of undoing the shot.
    static let glassDestructiveTint = UIColor.systemRed.withAlphaComponent(TrayCameraConfig.controlTintOpacity)
    /// Use photo.
    static let glassConfirmTint = UIColor.systemBlue.withAlphaComponent(TrayCameraConfig.controlTintOpacity)
}

// MARK: - SwiftUI

extension View {
    /// The round glass control: a white symbol in a 44pt tinted glass circle.
    func glassCircleControl() -> some View {
        font(.system(size: TrayCameraConfig.controlSymbolSize, weight: .semibold))
            .foregroundStyle(.white)
            .frame(
                width: TrayCameraConfig.controlButtonSize,
                height: TrayCameraConfig.controlButtonSize
            )
            .contentShape(.circle)
            // Interactive here, unlike the morph surface underneath: a button's press
            // response is the whole point, and nothing is morphing on the same touch.
            .glassEffect(.regular.tint(.glassControlTint).interactive(), in: .circle)
    }
}

// MARK: - UIKit

//  A translucent fill, not glass — and not for want of trying, twice.
//
//  These controls live in the UIKit view that SwiftUI hosts inside the morph surface. Nothing
//  that samples a backdrop renders in there: a `UIVisualEffectView` with
//  `UIGlassEffect(style: .regular)` draws nothing, nor does a `.clearGlass()` configuration,
//  nor `UIButton.Configuration.glass()` tinted through `baseBackgroundColor` (tried again on
//  2026-09-18, after the opaque-background confound was found and removed — still nothing on
//  screen). Checked once with the tint swapped to `.systemRed`, so it is not a black-on-black
//  illusion. A plain configuration background is ordinary drawing, so it renders, and black at
//  0.8 over a camera preview lands within a shade of the SwiftUI side's real glass.
//
//  Still unexplained. SwiftUI glass *does* sample hosted UIKit content, so the boundary is not
//  simply opaque to backdrop sampling — it is something about UIKit's own glass inside it.
//
//  The SwiftUI half above is real `.glassEffect` and needs no such fallback; it is applied
//  outside the hosted view.

extension UIButton.Configuration {
    /// The same material the SwiftUI side asks for, in the form that survives the hosting.
    static func glassControl(
        tintColor: UIColor? = .glassControlTint,
        horizontalPadding: CGFloat = 0
    ) -> UIButton.Configuration {
        var configuration = UIButton.Configuration.plain()
        configuration.baseForegroundColor = .white
        configuration.background.backgroundColor = tintColor
        // Half the control height: a circle on a 44pt square, a capsule on anything wider.
        // The button's own `cornerConfiguration` does not reach the configuration's
        // background, which otherwise draws a squircle.
        configuration.background.cornerRadius = TrayCameraConfig.controlButtonSize / 2
        configuration.contentInsets = NSDirectionalEdgeInsets(
            top: 0,
            leading: horizontalPadding,
            bottom: 0,
            trailing: horizontalPadding
        )
        return configuration
    }
}

/// The UIKit half: a 44pt circular glass button with a white symbol.
final class GlassCircleButton: UIButton {
    private let tint: UIColor?

    init(systemImage: String, tintColor: UIColor? = .glassControlTint) {
        tint = tintColor
        super.init(frame: CGRect(origin: .zero, size: Self.size))

        var configuration = UIButton.Configuration.glassControl(tintColor: tintColor)
        configuration.image = Self.symbol(systemImage)
        configuration.symbolContentTransition = UISymbolContentTransition(
            .replace.magic(fallback: .replace)
        )
        self.configuration = configuration
        cornerConfiguration = .capsule()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    static var size: CGSize {
        CGSize(width: TrayCameraConfig.controlButtonSize, height: TrayCameraConfig.controlButtonSize)
    }

    override var intrinsicContentSize: CGSize { Self.size }

    /// Fades the glyph without touching the material, for the camera menu's separation.
    var contentAlpha: CGFloat {
        get { configuration?.baseForegroundColor?.cgColor.alpha ?? 1 }
        set { configuration?.baseForegroundColor = UIColor.white.withAlphaComponent(newValue) }
    }

    private static func symbol(_ systemImage: String) -> UIImage? {
        UIImage(
            systemName: systemImage,
            withConfiguration: UIImage.SymbolConfiguration(
                pointSize: TrayCameraConfig.controlSymbolSize,
                weight: .semibold
            )
        )
    }

    func updateSymbol(systemImage: String) {
        configuration?.image = Self.symbol(systemImage)
    }

    /// Recolours the glyph and the tint together, for the flash's on state.
    func setSymbol(_ systemImage: String, tintColor: UIColor?, foreground: UIColor) {
        configuration?.image = Self.symbol(systemImage)
        configuration?.baseForegroundColor = foreground
        if configuration?.background.backgroundColor != nil {
            configuration?.background.backgroundColor = tintColor ?? tint
        }
    }

    /// The camera menu's droplets carry no material until they separate.
    func setGlassVisible(_ visible: Bool, tintColor: UIColor? = nil) {
        configuration?.background.backgroundColor = visible ? (tintColor ?? tint) : .clear
    }
}

/// The wider sibling: a titled capsule at the same height and corner radius, so a text
/// action reads as the same family of object as the round ones. Its width is its label's,
/// plus `horizontalPadding` on each side — nothing here is a fixed width.
final class GlassCapsuleButton: UIButton {
    init(title: String, tintColor: UIColor? = .glassControlTint, horizontalPadding: CGFloat = 12) {
        super.init(frame: .zero)

        var configuration = UIButton.Configuration.glassControl(
            tintColor: tintColor,
            horizontalPadding: horizontalPadding
        )
        configuration.attributedTitle = AttributedString(
            title,
            attributes: AttributeContainer([
                .font: UIFont.systemFont(ofSize: TrayCameraConfig.controlSymbolSize, weight: .semibold)
            ])
        )
        self.configuration = configuration
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: CGSize {
        CGSize(
            width: super.intrinsicContentSize.width,
            height: TrayCameraConfig.controlButtonSize
        )
    }
}
