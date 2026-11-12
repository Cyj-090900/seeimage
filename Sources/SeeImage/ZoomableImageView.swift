import AppKit

/// The canvas of the preview window. It draws a single image with rounded
/// corners and a soft shadow, supports zooming / panning / rotating / flipping,
/// and reports horizontal swipes so the window can page through a gallery.
final class ZoomableImageView: NSView {
    var image: NSImage? {
        didSet {
            rotation = 0
            flippedHorizontally = false
            zoom = 1
            offset = .zero
            updateFitScale()
            needsDisplay = true
            onZoomChanged?(zoom)
        }
    }

    private(set) var rotation = 0
    private(set) var flippedHorizontally = false
    private(set) var zoom: CGFloat = 1

    var onZoomChanged: ((CGFloat) -> Void)?
    var onHorizontalDrag: ((CGFloat) -> Void)?
    var contextMenuProvider: (() -> NSMenu)?

    private let contentInset: CGFloat = 30
    private let minimumZoom: CGFloat = 0.2
    private let maximumZoom: CGFloat = 8

    private var offset = CGPoint.zero
    private var fitScale: CGFloat = 1
    private var isPanning = false
    private var dragStartPoint = CGPoint.zero
    private var dragStartOffset = CGPoint.zero
    private var dragTranslation = CGSize.zero

    override var acceptsFirstResponder: Bool { true }
    override var isFlipped: Bool { false }

    // MARK: - Geometry

    private var baseSize: CGSize {
        guard let image else { return .zero }
        let size = image.size
        return rotation % 2 == 0 ? size : CGSize(width: size.height, height: size.width)
    }

    private var displayedSize: CGSize {
        let size = baseSize
        let scale = fitScale * zoom
        return CGSize(width: size.width * scale, height: size.height * scale)
    }

    private var drawSize: CGSize {
        let size = baseSize
        let scale = fitScale * zoom
        return CGSize(width: size.width * scale, height: size.height * scale)
    }

    override func layout() {
        super.layout()
        updateFitScale()
        needsDisplay = true
    }

    private func updateFitScale() {
        guard bounds.width > 0, bounds.height > 0, baseSize.width > 0, baseSize.height > 0 else {
            fitScale = 1
            return
        }
        let availableWidth = max(bounds.width - contentInset * 2, 40)
        let availableHeight = max(bounds.height - contentInset * 2, 40)
        fitScale = min(availableWidth / baseSize.width, availableHeight / baseSize.height)
        clampOffset()
    }

    private func clampOffset() {
        guard zoom > 0 else { return }
        let displayed = displayedSize
        let marginX = max((displayed.width - bounds.width) / 2 + contentInset, 0)
        let marginY = max((displayed.height - bounds.height) / 2 + contentInset, 0)
        if displayed.width <= bounds.width {
            offset.x = 0
        } else {
            offset.x = min(max(offset.x, -marginX), marginX)
        }
        if displayed.height <= bounds.height {
            offset.y = 0
        } else {
            offset.y = min(max(offset.y, -marginY), marginY)
        }
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let image else { return }
        let displayed = displayedSize
        guard displayed.width > 1, displayed.height > 1 else { return }

        let rect = CGRect(
            x: bounds.midX - displayed.width / 2 + offset.x,
            y: bounds.midY - displayed.height / 2 + offset.y,
            width: displayed.width,
            height: displayed.height
        )
        let path = NSBezierPath(roundedRect: rect, xRadius: 10, yRadius: 10)

        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.20)
        shadow.shadowBlurRadius = 22
        shadow.shadowOffset = CGSize(width: 0, height: -4)
        shadow.set()
        NSColor.white.setFill()
        path.fill()
        NSGraphicsContext.restoreGraphicsState()

        NSGraphicsContext.saveGraphicsState()
        path.addClip()

        let transform = NSAffineTransform()
        transform.translateX(by: rect.midX, yBy: rect.midY)
        transform.rotate(byDegrees: CGFloat(rotation) * 90)
        if flippedHorizontally {
            transform.scaleX(by: -1, yBy: 1)
        }
        transform.concat()

        let size = drawSize
        let destination = CGRect(
            x: -size.width / 2,
            y: -size.height / 2,
            width: size.width,
            height: size.height
        )
        let interpolation: NSImageInterpolation = zoom >= 2 ? .none : .high
        image.draw(
            in: destination,
            from: .zero,
            operation: .sourceOver,
            fraction: 1,
            respectFlipped: true,
            hints: [.interpolation: interpolation]
        )
        NSGraphicsContext.restoreGraphicsState()
    }

    // MARK: - Commands

    func setZoom(_ newZoom: CGFloat, anchor: CGPoint? = nil) {
        guard image != nil else { return }
        let clamped = min(max(newZoom, minimumZoom), maximumZoom)
        guard abs(clamped - zoom) > 0.0005 else { return }
        let ratio = clamped / zoom
        let anchorPoint = anchor ?? CGPoint(x: bounds.midX, y: bounds.midY)
        offset.x = anchorPoint.x + (bounds.midX + offset.x - anchorPoint.x) * ratio - bounds.midX
        offset.y = anchorPoint.y + (bounds.midY + offset.y - anchorPoint.y) * ratio - bounds.midY
        zoom = clamped
        clampOffset()
        needsDisplay = true
        onZoomChanged?(zoom)
    }

    func zoom(by factor: CGFloat) {
        setZoom(zoom * factor)
    }

    func fitToWindow() {
        guard image != nil else { return }
        offset = .zero
        if abs(zoom - 1) > 0.0005 {
            zoom = 1
            onZoomChanged?(zoom)
        }
        clampOffset()
        needsDisplay = true
    }

    func rotate(by quarterTurns: Int) {
        guard image != nil else { return }
        rotation = ((rotation + quarterTurns) % 4 + 4) % 4
        offset = .zero
        updateFitScale()
        needsDisplay = true
    }

    func flipHorizontally() {
        guard image != nil else { return }
        flippedHorizontally.toggle()
        needsDisplay = true
    }

    // MARK: - Interaction

    override func scrollWheel(with event: NSEvent) {
        guard image != nil else { return }
        if event.modifierFlags.contains(.command) || event.modifierFlags.contains(.option) {
            let anchor = convert(event.locationInWindow, from: nil)
            let factor = 1 + event.scrollingDeltaY * 0.01
            setZoom(zoom * factor, anchor: anchor)
            return
        }
        guard zoom > 1.001 else { return }
        offset.x -= event.scrollingDeltaX
        offset.y += event.scrollingDeltaY
        clampOffset()
        needsDisplay = true
    }

    override func magnify(with event: NSEvent) {
        guard image != nil else { return }
        let anchor = convert(event.locationInWindow, from: nil)
        setZoom(zoom * (1 + event.magnification), anchor: anchor)
    }

    override func mouseDown(with event: NSEvent) {
        guard image != nil else { return }
        window?.makeFirstResponder(self)
        let point = convert(event.locationInWindow, from: nil)
        if event.clickCount == 2 {
            if zoom > 1.01 {
                fitToWindow()
            } else {
                setZoom(2, anchor: point)
            }
            return
        }
        isPanning = true
        dragStartPoint = point
        dragStartOffset = offset
        dragTranslation = .zero
    }

    override func mouseDragged(with event: NSEvent) {
        guard isPanning, image != nil else { return }
        let point = convert(event.locationInWindow, from: nil)
        let translation = CGSize(width: point.x - dragStartPoint.x, height: point.y - dragStartPoint.y)
        dragTranslation = translation
        if zoom > 1.001 {
            offset = CGPoint(x: dragStartOffset.x + translation.width, y: dragStartOffset.y + translation.height)
            clampOffset()
        } else {
            offset = CGPoint(x: translation.width * 0.22, y: 0)
        }
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard isPanning else { return }
        isPanning = false
        defer { needsDisplay = true }
        guard zoom <= 1.001 else { return }
        offset = .zero
        if abs(dragTranslation.width) > 70,
           abs(dragTranslation.width) > abs(dragTranslation.height) {
            onHorizontalDrag?(dragTranslation.width)
        }
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        contextMenuProvider?()
    }
}
