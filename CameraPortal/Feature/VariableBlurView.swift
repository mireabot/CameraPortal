//
//  VariableBlurView.swift
//  CameraPortal
//
//  Adapted from SwiftUX's Progressive Blur Refresh Header dependency.
//

import SwiftUI
import UIKit

/// A backdrop blur whose radius is driven by a gradient's alpha.
///
/// This uses the private `CAFilter`/`variableBlur` runtime API. If that API is unavailable,
/// the view safely falls back to the regular blur installed by `UIVisualEffectView`.
struct VariableBlurView: UIViewRepresentable {
    var maxRadius: CGFloat = 20
    var stops: [Gradient.Stop]
    var axis: Axis = .horizontal

    func makeUIView(context _: Context) -> VariableBlurEffectView {
        VariableBlurEffectView(maxRadius: maxRadius, stops: stops, axis: axis)
    }

    func updateUIView(_ view: VariableBlurEffectView, context _: Context) {
        view.update(maxRadius: maxRadius, stops: stops, axis: axis)
    }
}

final class VariableBlurEffectView: UIVisualEffectView {
    private var maxRadius: CGFloat
    private var stops: [Gradient.Stop]
    private var axis: Axis
    private var renderedSize: CGSize = .zero
    private var filterUnavailable = false

    init(maxRadius: CGFloat, stops: [Gradient.Stop], axis: Axis) {
        self.maxRadius = maxRadius
        self.stops = stops
        self.axis = axis
        super.init(effect: UIBlurEffect(style: .regular))
        backgroundColor = .clear
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(maxRadius: CGFloat, stops: [Gradient.Stop], axis: Axis) {
        self.maxRadius = maxRadius
        self.stops = stops
        self.axis = axis
        renderedSize = .zero
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.size != renderedSize, bounds.width > 0, bounds.height > 0 else { return }
        if applyFilter() { renderedSize = bounds.size }
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard window != nil else { return }
        renderedSize = .zero
        setNeedsLayout()
    }

    private var backdropLayer: CALayer? {
        subviews.first { String(describing: type(of: $0)).contains("Backdrop") }?.layer
    }

    @discardableResult
    private func applyFilter() -> Bool {
        for subview in subviews where !String(describing: type(of: subview)).contains("Backdrop") {
            subview.alpha = 0
        }

        guard !filterUnavailable else { return true }
        guard let backdropLayer else { return false }
        guard let filter = Self.makeVariableBlurFilter() else {
            filterUnavailable = true
            return true
        }
        guard let mask = makeMaskImage(size: bounds.size) else { return false }

        filter.setValue(maxRadius, forKey: "inputRadius")
        filter.setValue(mask, forKey: "inputMaskImage")
        filter.setValue(true, forKey: "inputNormalizeEdges")
        backdropLayer.filters = [filter]
        return true
    }

    private func makeMaskImage(size: CGSize) -> CGImage? {
        guard size.width > 0, size.height > 0, !stops.isEmpty else { return nil }

        let colors = stops.map { UIColor($0.color).cgColor } as CFArray
        let locations = stops.map(\.location)
        guard let gradient = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: colors,
            locations: locations
        ) else { return nil }

        let end = axis == .horizontal
            ? CGPoint(x: size.width, y: 0)
            : CGPoint(x: 0, y: size.height)

        return UIGraphicsImageRenderer(size: size).image { context in
            context.cgContext.drawLinearGradient(
                gradient,
                start: .zero,
                end: end,
                options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
            )
        }.cgImage
    }

    private static func makeVariableBlurFilter() -> NSObject? {
        guard let filterClass = NSClassFromString("CAFilter") as? NSObject.Type else { return nil }
        let selector = NSSelectorFromString("filterWithType:")
        guard filterClass.responds(to: selector),
              let filter = filterClass.perform(selector, with: "variableBlur")?.takeUnretainedValue()
        else { return nil }
        return filter as? NSObject
    }
}
