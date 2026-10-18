//
//  MediaGridView.swift
//  CameraPortal
//
//  Three column media grid. Column 0, rows 0-1 is the live camera cell
//  (Telegram MediaPickerScreen.swift:1722 uses the same rect: itemW x itemW * 2 + 1).
//

import UIKit

struct MediaGridItem {
    let id: Int
    let color: UIColor
    let duration: String?
}

final class MediaGridView: UIView {
    // MARK: Inputs

    var items: [MediaGridItem] {
        didSet { rebuildItemViews() }
    }

    /// Radius of the grid cells. 0: square cells inside the tray's 8pt glass gutter, and
    /// the camera morph then interpolates from 0 up to the tray's own radius.
    var cellCornerRadius: CGFloat = 0 {
        didSet {
            guard cellCornerRadius != oldValue else { return }
            applyCornerRadius()
        }
    }

    var onCameraTap: ((CameraHolder) -> Void)?

    // MARK: Views

    let scrollView = UIScrollView()
    /// Telegram's `cameraWrapperView` (MediaPickerScreen.swift:402): the preview's home cell.
    let cameraWrapperView = UIView()

    private let camera: CameraSession
    private let previewView: CameraPreviewSource
    private let cameraBadgeView = UIImageView()
    private var itemViews: [UIView] = []
    private lazy var cameraTapGesture = UITapGestureRecognizer(target: self, action: #selector(cameraTapped))

    init(camera: CameraSession, previewView: CameraPreviewSource, items: [MediaGridItem]) {
        self.camera = camera
        self.previewView = previewView
        self.items = items
        super.init(frame: .zero)

        // Only bounce when the content genuinely exceeds the frame; with it always on, a
        // short grid drags free of the tray.
        scrollView.alwaysBounceVertical = false
        scrollView.bounces = true
        scrollView.showsVerticalScrollIndicator = false
        scrollView.contentInsetAdjustmentBehavior = .never
        addSubview(scrollView)

        cameraWrapperView.clipsToBounds = true
        cameraWrapperView.layer.cornerCurve = .continuous
        // Matches the preview fallback when no capture device is available, including the
        // Simulator. It also keeps the source cell visually stable during reparenting.
        cameraWrapperView.backgroundColor = .black
        cameraWrapperView.isAccessibilityElement = true
        cameraWrapperView.accessibilityTraits = .button
        cameraWrapperView.addGestureRecognizer(cameraTapGesture)
        scrollView.addSubview(cameraWrapperView)

        cameraWrapperView.addSubview(previewView)
        setupCameraBadge()
        rebuildItemViews()
        applyCornerRadius()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: Camera handoff

    /// Telegram `cameraTapped()` (MediaPickerScreen.swift:872): disable the gesture until
    /// the preview has been restored, then hand the running camera over.
    @objc func cameraTapped() {
        guard cameraTapGesture.isEnabled else { return }
        cameraTapGesture.isEnabled = false
        let holder = CameraHolder(
            camera: camera,
            previewView: previewView,
            parentView: cameraWrapperView,
            restore: { [weak self] in self?.restoreCamera() }
        )
        onCameraTap?(holder)
    }

    /// Re-parents the preview back into the cell and re-enables the tap.
    func restoreCamera() {
        previewView.layer.removeAllAnimations()
        previewView.transform = .identity
        previewView.alpha = 1
        cameraWrapperView.insertSubview(previewView, at: 0)
        previewView.frame = cameraWrapperView.bounds
        previewView.layer.layoutIfNeeded()
        cameraWrapperView.bringSubviewToFront(cameraBadgeView)
        cameraTapGesture.isEnabled = true
    }

    /// Destination for the reverse transition, or nil when the cell is mostly scrolled away.
    func cameraDestination() -> CameraTransitionOut? {
        let cellFrame = cameraWrapperView.frame
        guard cellFrame.width > 0, cellFrame.height > 0 else { return nil }
        let visibleRect = scrollView.bounds.inset(by: UIEdgeInsets(
            top: scrollView.adjustedContentInset.top,
            left: 0,
            bottom: scrollView.adjustedContentInset.bottom,
            right: 0
        ))
        let intersection = cellFrame.intersection(visibleRect)
        guard !intersection.isNull else { return nil }
        let fraction = (intersection.width * intersection.height) / (cellFrame.width * cellFrame.height)
        guard fraction >= TrayCameraConfig.minVisibleFraction else { return nil }
        return CameraTransitionOut(
            destinationView: cameraWrapperView,
            destinationRect: cameraWrapperView.bounds,
            destinationCornerRadius: cellCornerRadius
        )
    }

    // MARK: Layout

    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.width > 0 else { return }
        scrollView.frame = bounds

        let padding = TrayCameraConfig.gridPadding
        let spacing = TrayCameraConfig.gridSpacing
        let columns = CGFloat(TrayCameraConfig.gridColumns)
        let itemWidth = (bounds.width - padding * 2 - spacing * (columns - 1)) / columns
        guard itemWidth > 0 else { return }

        func frame(row: Int, column: Int) -> CGRect {
            CGRect(
                x: padding + CGFloat(column) * (itemWidth + spacing),
                y: CGFloat(row) * (itemWidth + spacing),
                width: itemWidth,
                height: itemWidth
            )
        }

        cameraWrapperView.frame = CGRect(
            x: padding,
            y: 0,
            width: itemWidth,
            height: itemWidth * 2 + spacing
        )
        if previewView.superview === cameraWrapperView {
            previewView.frame = cameraWrapperView.bounds
        }
        cameraWrapperView.bringSubviewToFront(cameraBadgeView)

        var slot = 0
        for itemView in itemViews {
            // Skip the two slots taken by the camera cell.
            while slot == 0 || slot == TrayCameraConfig.gridColumns {
                slot += 1
            }
            itemView.frame = frame(row: slot / TrayCameraConfig.gridColumns, column: slot % TrayCameraConfig.gridColumns)
            slot += 1
        }

        let rows = Int(ceil(Double(slot) / Double(TrayCameraConfig.gridColumns)))
        scrollView.contentSize = CGSize(
            width: bounds.width,
            // Minus the trailing gap: `rows * (item + spacing)` counts a spacing below the
            // last row that no row follows, and that is free over-scroll.
            height: max(0, CGFloat(rows) * (itemWidth + spacing) - spacing)
        )
    }

    // MARK: Private

    private func setupCameraBadge() {
        let symbolConfiguration = UIImage.SymbolConfiguration(pointSize: 20, weight: .semibold)
        cameraBadgeView.image = UIImage(systemName: "camera.circle")
        cameraBadgeView.preferredSymbolConfiguration = symbolConfiguration
        cameraBadgeView.tintColor = .white
        cameraBadgeView.contentMode = .scaleAspectFit
        cameraBadgeView.translatesAutoresizingMaskIntoConstraints = false
        cameraBadgeView.isUserInteractionEnabled = false
        cameraBadgeView.accessibilityElementsHidden = true
        cameraBadgeView.layer.shadowColor = UIColor.black.cgColor
        cameraBadgeView.layer.shadowOpacity = 0.4
        cameraBadgeView.layer.shadowRadius = 3
        cameraBadgeView.layer.shadowOffset = .zero
        cameraWrapperView.addSubview(cameraBadgeView)

        NSLayoutConstraint.activate([
            cameraBadgeView.topAnchor.constraint(equalTo: cameraWrapperView.topAnchor, constant: 10),
            cameraBadgeView.trailingAnchor.constraint(equalTo: cameraWrapperView.trailingAnchor, constant: -10),
            cameraBadgeView.widthAnchor.constraint(equalToConstant: 24),
            cameraBadgeView.heightAnchor.constraint(equalTo: cameraBadgeView.widthAnchor)
        ])
    }

    private func rebuildItemViews() {
        itemViews.forEach { $0.removeFromSuperview() }
        itemViews = items.map { item in
            let view = MediaGridCellView(item: item)
            view.layer.cornerRadius = cellCornerRadius
            scrollView.addSubview(view)
            return view
        }
        setNeedsLayout()
    }

    private func applyCornerRadius() {
        cameraWrapperView.layer.cornerRadius = cellCornerRadius
        itemViews.forEach { $0.layer.cornerRadius = cellCornerRadius }
    }
}

// MARK: - Cell

private final class MediaGridCellView: UIView {
    private let durationLabel = UILabel()

    init(item: MediaGridItem) {
        super.init(frame: .zero)
        backgroundColor = item.color
        clipsToBounds = true
        layer.cornerCurve = .continuous
        isAccessibilityElement = true
        accessibilityTraits = .image

        if let duration = item.duration {
            durationLabel.text = duration
            durationLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .semibold)
            durationLabel.textColor = .white
            durationLabel.layer.shadowColor = UIColor.black.cgColor
            durationLabel.layer.shadowOpacity = 0.5
            durationLabel.layer.shadowRadius = 2
            durationLabel.layer.shadowOffset = .zero
            addSubview(durationLabel)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard durationLabel.superview != nil else { return }
        durationLabel.sizeToFit()
        durationLabel.frame.origin = CGPoint(
            x: bounds.width - durationLabel.bounds.width - 6,
            y: bounds.height - durationLabel.bounds.height - 5
        )
    }
}

// MARK: - Placeholder content

enum MediaGridSampleData {
    static func items(count: Int = 90) -> [MediaGridItem] {
        (0..<count).map { index in
            let hue = CGFloat((index * 37) % 360) / 360
            return MediaGridItem(
                id: index + 1,
                color: UIColor(hue: hue, saturation: 0.35, brightness: index.isMultiple(of: 3) ? 0.75 : 0.55, alpha: 1),
                duration: index.isMultiple(of: 7) ? String(format: "0:%02d", (index * 13) % 60) : nil
            )
        }
    }
}
