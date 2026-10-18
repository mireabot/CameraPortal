//
//  ShutterOverlayView.swift
//  CameraPortal
//
//  Camera controls drawn inside the tray: shutter bottom center and a Liquid Glass menu
//  beside it that separates upward into flash and camera-flip actions. Hit testing passes
//  through everywhere else so the overlay underneath still receives the dismiss pan.
//
//  The camera has its own close button because the tray header clears away while the camera
//  is open.
//
//  The insets are concentric rather than fixed: a round control of radius `c` sits `r - c`
//  in from a corner of radius `r`, so its curve is concentric with the tray's.
//

import UIKit

final class ShutterOverlayView: UIView {
    var onShutter: (() -> Void)?
    var onFlip: (() -> Void)?
    var onFlashChanged: ((Bool) -> Void)?
    var onClose: (() -> Void)?
    var onRetake: (() -> Void)?
    var onUsePhoto: (() -> Void)?
    var usesReducedMotion = false

    /// The tray's corner radius; the control insets are derived from it.
    var trayCornerRadius: CGFloat = 16 {
        didSet {
            guard trayCornerRadius != oldValue else { return }
            setNeedsLayout()
        }
    }

    /// Concentric inset for the 44pt round buttons: `r - 22`, i.e. 32 on a Pro display.
    private var controlInset: CGFloat {
        TrayCameraConfig.concentricInset(for: TrayCameraConfig.controlButtonSize, in: trayCornerRadius)
    }

    /// Concentric inset for the 72pt shutter: `r - 36`.
    private var shutterInset: CGFloat {
        TrayCameraConfig.concentricInset(for: TrayCameraConfig.shutterSize, in: trayCornerRadius)
    }

    let shutterButton = ShutterButton()
    let cameraMenu = CameraControlMenuView()
    let closeButton = GlassCircleButton(systemImage: "xmark")
    private let retakeButton = GlassCapsuleButton(title: "Retake", tintColor: .glassDestructiveTint)
    private let usePhotoButton = GlassCircleButton(
        systemImage: "checkmark",
        tintColor: .glassConfirmTint
    )
    private var isReviewing = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear

        shutterButton.addTarget(self, action: #selector(shutterTapped), for: .touchUpInside)
        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        retakeButton.addTarget(self, action: #selector(retakeTapped), for: .touchUpInside)
        usePhotoButton.addTarget(self, action: #selector(usePhotoTapped), for: .touchUpInside)
        cameraMenu.onFlip = { [weak self] in self?.onFlip?() }
        cameraMenu.onFlashChanged = { [weak self] enabled in
            self?.onFlashChanged?(enabled)
        }

        addSubview(shutterButton)
        addSubview(cameraMenu)
        addSubview(closeButton)
        addSubview(retakeButton)
        addSubview(usePhotoButton)

        #if DEBUG
        if CameraPortalDebug.expandsCameraMenu { cameraMenu.expand() }
        #endif

        retakeButton.isHidden = true
        usePhotoButton.isHidden = true
        retakeButton.alpha = 0
        usePhotoButton.alpha = 0
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let shutterSize = TrayCameraConfig.shutterSize
        shutterButton.bounds = CGRect(origin: .zero, size: CGSize(width: shutterSize, height: shutterSize))
        shutterButton.center = CGPoint(
            x: bounds.midX,
            y: bounds.maxY - shutterInset - shutterSize / 2
        )

        // The menu's collapsed button replaces the old flip button beside the shutter. Its
        // full frame extends upward, which gives the glass droplets room to separate.
        let buttonSize = TrayCameraConfig.controlButtonSize
        let menuSize = cameraMenu.intrinsicContentSize
        cameraMenu.frame = CGRect(
            x: bounds.maxX - controlInset - buttonSize,
            y: shutterButton.center.y + buttonSize / 2 - menuSize.height,
            width: menuSize.width,
            height: menuSize.height
        )

        closeButton.frame = CGRect(
            x: bounds.maxX - controlInset - buttonSize,
            y: controlInset,
            width: buttonSize,
            height: buttonSize
        )

        // The capsule hugs its label; only the circle is a fixed square.
        let reviewHeight = TrayCameraConfig.controlButtonSize
        let reviewInset = TrayCameraConfig.concentricInset(for: reviewHeight, in: trayCornerRadius)
        let reviewY = bounds.maxY - reviewInset - reviewHeight
        retakeButton.frame = CGRect(
            x: reviewInset,
            y: reviewY,
            width: retakeButton.intrinsicContentSize.width,
            height: reviewHeight
        )
        usePhotoButton.frame = CGRect(
            x: bounds.maxX - reviewInset - reviewHeight,
            y: reviewY,
            width: reviewHeight,
            height: reviewHeight
        )
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let view = super.hitTest(point, with: event)
        return view === self ? nil : view
    }

    @objc private func shutterTapped() {
        onShutter?()
    }

    @objc private func closeTapped() {
        onClose?()
    }

    @objc private func retakeTapped() {
        onRetake?()
    }

    @objc private func usePhotoTapped() {
        onUsePhoto?()
    }

    func setReviewing(_ reviewing: Bool, animated: Bool) {
        guard isReviewing != reviewing else { return }
        isReviewing = reviewing
        shutterButton.isUserInteractionEnabled = !reviewing
        cameraMenu.isUserInteractionEnabled = !reviewing
        closeButton.isUserInteractionEnabled = !reviewing
        retakeButton.isUserInteractionEnabled = reviewing
        usePhotoButton.isUserInteractionEnabled = reviewing

        if reviewing {
            cameraMenu.collapse()
            retakeButton.isHidden = false
            usePhotoButton.isHidden = false
        } else {
            shutterButton.isHidden = false
            cameraMenu.isHidden = false
            closeButton.isHidden = false
        }

        let changes = {
            self.shutterButton.alpha = reviewing ? 0 : 1
            self.cameraMenu.alpha = reviewing ? 0 : 1
            self.closeButton.alpha = reviewing ? 0 : 1
            self.retakeButton.alpha = reviewing ? 1 : 0
            self.usePhotoButton.alpha = reviewing ? 1 : 0
        }
        let completion: (Bool) -> Void = { _ in
            self.shutterButton.isHidden = reviewing
            self.cameraMenu.isHidden = reviewing
            self.closeButton.isHidden = reviewing
            self.retakeButton.isHidden = !reviewing
            self.usePhotoButton.isHidden = !reviewing
        }

        guard animated else {
            changes()
            completion(true)
            return
        }

        UIView.animate(
            withDuration: usesReducedMotion ? 0.1 : 0.16,
            delay: 0,
            options: [.beginFromCurrentState, .allowUserInteraction, .curveEaseOut],
            animations: changes,
            completion: completion
        )
    }
}

// MARK: - Glass camera menu

/// Three native glass elements in one shared container. At rest only the menu owns material;
/// flash and flip materialize as they separate upward from the source droplet.
final class CameraControlMenuView: UIView {
    var onFlip: (() -> Void)?
    var onFlashChanged: ((Bool) -> Void)?

    private let buttonSize = TrayCameraConfig.controlButtonSize
    private let itemSpacing = TrayCameraConfig.cameraMenuSpacing

    private let containerEffect = UIGlassContainerEffect()
    private lazy var containerView = UIVisualEffectView(effect: containerEffect)
    private let flashItem = GlassCircleButton(
        systemImage: "bolt.slash.fill"
    )
    private let flipItem = GlassCircleButton(
        systemImage: "arrow.triangle.2.circlepath"
    )
    private let menuItem = GlassCircleButton(
        systemImage: "ellipsis"
    )

    private var isExpanded = false
    private var isFlashEnabled = false

    override var intrinsicContentSize: CGSize {
        CGSize(
            width: buttonSize,
            height: buttonSize * 3 + itemSpacing * 2
        )
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        containerEffect.spacing = itemSpacing
        addSubview(containerView)

        // Add the actions first so the source menu droplet stays on top while all three share
        // the collapsed frame. The action views have no glass until expansion begins.
        containerView.contentView.addSubview(flashItem)
        containerView.contentView.addSubview(flipItem)
        containerView.contentView.addSubview(menuItem)

        flashItem.addTarget(self, action: #selector(flashTapped), for: .touchUpInside)
        flipItem.addTarget(self, action: #selector(flipTapped), for: .touchUpInside)
        menuItem.addTarget(self, action: #selector(menuTapped), for: .touchUpInside)

        setExpanded(false, animated: false)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        containerView.frame = bounds
        applyFrames(expanded: isExpanded)
    }

    private var collapsedFrame: CGRect {
        CGRect(x: 0, y: bounds.maxY - buttonSize, width: buttonSize, height: buttonSize)
    }

    private func expandedFrame(level: Int) -> CGRect {
        collapsedFrame.offsetBy(
            dx: 0,
            dy: -CGFloat(level) * (buttonSize + itemSpacing)
        )
    }

    private func applyFrames(expanded: Bool) {
        menuItem.frame = collapsedFrame
        flipItem.frame = expanded ? expandedFrame(level: 1) : collapsedFrame
        flashItem.frame = expanded ? expandedFrame(level: 2) : collapsedFrame
    }

    private func setExpanded(_ expanded: Bool, animated: Bool) {
        isExpanded = expanded
        flipItem.isEnabled = expanded
        flashItem.isEnabled = expanded
        flipItem.accessibilityElementsHidden = !expanded
        flashItem.accessibilityElementsHidden = !expanded

        let changes = {
            self.applyFrames(expanded: expanded)
            self.flipItem.setGlassVisible(expanded)
            self.flashItem.setGlassVisible(expanded, tintColor: self.flashTintColor)
            self.flipItem.contentAlpha = expanded ? 1 : 0
            self.flashItem.contentAlpha = expanded ? 1 : 0
        }

        menuItem.updateSymbol(
            systemImage: expanded ? "xmark" : "ellipsis"
        )

        guard animated else {
            changes()
            return
        }

        UIView.animate(
            springDuration: TrayCameraConfig.cameraMenuResponse,
            bounce: 0,
            initialSpringVelocity: 0,
            options: [.beginFromCurrentState, .allowUserInteraction],
            animations: changes
        )
    }

    @objc private func menuTapped() {
        setExpanded(!isExpanded, animated: true)
    }

    func collapse() {
        setExpanded(false, animated: false)
    }

    /// Debug-only entry point for screenshots; the menu is otherwise opened by its own tap.
    func expand() {
        setExpanded(true, animated: false)
    }

    @objc private func flashTapped() {
        isFlashEnabled.toggle()
        applyFlashSymbol()
        onFlashChanged?(isFlashEnabled)
    }

    @objc private func flipTapped() {
        if isFlashEnabled {
            isFlashEnabled = false
            applyFlashSymbol()
            onFlashChanged?(false)
        }
        onFlip?()
    }

    /// Flash-on is state, not chrome: it keeps the yellow wash over the shared black tint so
    /// the control says what it is doing.
    private var flashTintColor: UIColor? {
        isFlashEnabled ? UIColor.systemYellow.withAlphaComponent(0.22) : nil
    }

    private func applyFlashSymbol() {
        flashItem.setSymbol(
            isFlashEnabled ? "bolt.fill" : "bolt.slash.fill",
            tintColor: flashTintColor,
            foreground: isFlashEnabled ? .systemYellow : .white
        )
    }
}

// MARK: - Shutter

final class ShutterButton: UIControl {
    private let glassView: UIVisualEffectView = {
        let glass = UIGlassEffect(style: .regular)
        glass.isInteractive = true
        let view = UIVisualEffectView(effect: glass)
        view.cornerConfiguration = .capsule()
        view.isUserInteractionEnabled = false
        return view
    }()
    private let ringView = UIView()
    private let discView = UIView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        isAccessibilityElement = true
        accessibilityTraits = .button

        addSubview(glassView)

        ringView.layer.borderColor = UIColor.white.cgColor
        ringView.layer.borderWidth = 4
        ringView.cornerConfiguration = .capsule()
        ringView.isUserInteractionEnabled = false
        addSubview(ringView)

        discView.backgroundColor = .white
        discView.cornerConfiguration = .capsule()
        discView.isUserInteractionEnabled = false
        addSubview(discView)

        addTarget(self, action: #selector(handleTouchDown), for: [.touchDown, .touchDragEnter])
        addTarget(self, action: #selector(handleTouchUp), for: [.touchUpInside, .touchUpOutside, .touchCancel, .touchDragExit])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        glassView.frame = bounds
        ringView.frame = bounds
        let inset = bounds.width * 0.14
        discView.frame = bounds.insetBy(dx: inset, dy: inset)
    }

    @objc private func handleTouchDown() {
        UIView.animate(withDuration: 0.12) {
            self.discView.transform = CGAffineTransform(scaleX: 0.9, y: 0.9)
        }
    }

    @objc private func handleTouchUp() {
        UIView.animate(springDuration: 0.3, bounce: 0.2) {
            self.discView.transform = .identity
        }
    }
}
