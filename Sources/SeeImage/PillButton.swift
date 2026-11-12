import AppKit

/// Soft grey capsule used by the preview toolbar. Text carries its own glyph
/// (`‹ 上一张`, `↺ 左转`, …) exactly like the original window, so no SF Symbol
/// boxes are needed.
final class PillButton: NSButton {
    private var isHovered = false {
        didSet { needsDisplay = true }
    }
    private var trackingArea: NSTrackingArea?

    private let horizontalPadding: CGFloat = 18
    private let buttonHeight: CGFloat = 34

    init(title: String, target: AnyObject?, action: Selector?) {
        super.init(frame: .zero)
        self.title = title
        self.target = target
        self.action = action
        isBordered = false
        bezelStyle = .inline
        setButtonType(.momentaryPushIn)
        font = .systemFont(ofSize: 14, weight: .medium)
        focusRingType = .none
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: buttonHeight).isActive = true
        setAccessibilityLabel(title)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: NSSize {
        let textWidth = (title as NSString).size(withAttributes: [.font: resolvedFont]).width
        return NSSize(width: ceil(textWidth + horizontalPadding * 2), height: buttonHeight)
    }

    private var resolvedFont: NSFont {
        font ?? .systemFont(ofSize: 14, weight: .medium)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        let area = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
    }

    override func draw(_ dirtyRect: NSRect) {
        let rect = bounds.insetBy(dx: 0.5, dy: 0.5)
        let path = NSBezierPath(roundedRect: rect, xRadius: 11, yRadius: 11)

        let fill: NSColor
        if !isEnabled {
            fill = NSColor.labelColor.withAlphaComponent(0.035)
        } else if isHighlighted {
            fill = NSColor.labelColor.withAlphaComponent(0.16)
        } else if isHovered {
            fill = NSColor.labelColor.withAlphaComponent(0.10)
        } else {
            fill = NSColor.labelColor.withAlphaComponent(0.06)
        }
        fill.setFill()
        path.fill()

        let textColor: NSColor
        if !isEnabled {
            textColor = .tertiaryLabelColor
        } else if isHighlighted {
            textColor = .labelColor
        } else {
            textColor = .labelColor
        }

        let attributes: [NSAttributedString.Key: Any] = [
            .font: resolvedFont,
            .foregroundColor: textColor,
        ]
        let textSize = (title as NSString).size(withAttributes: attributes)
        let textRect = NSRect(
            x: bounds.midX - textSize.width / 2,
            y: bounds.midY - textSize.height / 2,
            width: textSize.width + 1,
            height: textSize.height
        )
        (title as NSString).draw(in: textRect, withAttributes: attributes)
    }
}
