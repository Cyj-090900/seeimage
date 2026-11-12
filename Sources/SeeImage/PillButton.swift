import AppKit

/// Capsule-shaped toolbar button: an SF Symbol plus a short label, with hover,
/// pressed and disabled treatments that echo the original preview window.
final class PillButton: NSButton {
    private let symbolName: String?
    private var isHovered = false {
        didSet { needsDisplay = true }
    }
    private var trackingArea: NSTrackingArea?

    init(title: String, symbol: String?, target: AnyObject?, action: Selector?) {
        self.symbolName = symbol
        super.init(frame: .zero)
        self.title = title
        self.target = target
        self.action = action
        isBordered = false
        bezelStyle = .inline
        setButtonType(.momentaryPushIn)
        font = .systemFont(ofSize: 12.5, weight: .medium)
        focusRingType = .none
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: 28).isActive = true
        setAccessibilityLabel(title)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: NSSize {
        let textWidth = (title as NSString).size(withAttributes: [.font: resolvedFont]).width
        let iconAllowance: CGFloat = symbolName == nil ? 0 : 18
        return NSSize(width: ceil(textWidth + iconAllowance + 24), height: 28)
    }

    private var resolvedFont: NSFont {
        font ?? .systemFont(ofSize: 12.5, weight: .medium)
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
        let path = NSBezierPath(
            roundedRect: rect,
            xRadius: rect.height / 2,
            yRadius: rect.height / 2
        )

        let background: NSColor
        if !isEnabled {
            background = NSColor.quaternaryLabelColor.withAlphaComponent(0.05)
        } else if isHighlighted {
            background = NSColor.controlAccentColor.withAlphaComponent(0.75)
        } else if isHovered {
            background = NSColor.controlBackgroundColor
        } else {
            background = NSColor.controlBackgroundColor.withAlphaComponent(0.72)
        }
        background.setFill()
        path.fill()

        NSColor.separatorColor.withAlphaComponent(isEnabled ? 0.28 : 0.12).setStroke()
        path.lineWidth = 1
        path.stroke()

        let themeColor: NSColor
        if !isEnabled {
            themeColor = .tertiaryLabelColor
        } else if isHighlighted {
            themeColor = .white
        } else {
            themeColor = .labelColor
        }

        let font = resolvedFont
        let textAttributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: themeColor,
        ]
        let textSize = (title as NSString).size(withAttributes: textAttributes)

        var iconImage: NSImage?
        if let symbolName,
           let base = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil) {
            let palette = NSImage.SymbolConfiguration(paletteColors: [themeColor])
            let size = NSImage.SymbolConfiguration(pointSize: 11.5, weight: .semibold)
            iconImage = base.withSymbolConfiguration(size.applying(palette))
        }

        let iconSize = iconImage?.size ?? .zero
        let spacing: CGFloat = (iconImage != nil && textSize.width > 0) ? 5 : 0
        let contentWidth = iconSize.width + spacing + textSize.width
        var cursorX = (bounds.width - contentWidth) / 2

        if let iconImage {
            let iconRect = NSRect(
                x: cursorX,
                y: bounds.midY - iconSize.height / 2,
                width: iconSize.width,
                height: iconSize.height
            )
            iconImage.draw(
                in: iconRect,
                from: .zero,
                operation: .sourceOver,
                fraction: 1,
                respectFlipped: true,
                hints: nil
            )
            cursorX += iconSize.width + spacing
        }

        let textRect = NSRect(
            x: cursorX,
            y: bounds.midY - textSize.height / 2,
            width: textSize.width + 1,
            height: textSize.height
        )
        (title as NSString).draw(in: textRect, withAttributes: textAttributes)
    }
}
