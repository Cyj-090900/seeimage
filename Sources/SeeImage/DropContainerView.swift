import AppKit

/// The window's content view. It accepts files and image URLs dragged in from
/// Finder or a browser and highlights itself while a drag is hovering.
final class DropContainerView: NSView {
    var onDrop: (([URL]) -> Void)?

    private var isHighlighting = false {
        didSet { updateBorder() }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        registerForDraggedTypes([.fileURL, .URL])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func updateBorder() {
        layer?.borderWidth = isHighlighting ? 2 : 0
        layer?.borderColor = NSColor.controlAccentColor.withAlphaComponent(0.85).cgColor
    }

    private static func urls(from pasteboard: NSPasteboard) -> [URL] {
        var urls: [URL] = []
        if let objects = pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: false]
        ) {
            for object in objects {
                if let url = object as? URL {
                    urls.append(url)
                } else if let url = object as? NSURL {
                    urls.append(url as URL)
                }
            }
        }
        if urls.isEmpty,
           let raw = pasteboard.string(forType: .URL),
           let url = URL(string: raw) {
            urls.append(url)
        }

        var seen = Set<String>()
        return urls.filter { url in
            guard !url.absoluteString.isEmpty else { return false }
            return seen.insert(url.absoluteString).inserted
        }
    }

    private func canAccept(_ sender: NSDraggingInfo) -> Bool {
        !Self.urls(from: sender.draggingPasteboard).isEmpty
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard canAccept(sender) else { return [] }
        isHighlighting = true
        return .copy
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        canAccept(sender) ? .copy : []
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        isHighlighting = false
    }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        canAccept(sender)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        isHighlighting = false
        let urls = Self.urls(from: sender.draggingPasteboard)
        guard !urls.isEmpty else { return false }
        onDrop?(urls)
        return true
    }

    override func concludeDragOperation(_ sender: NSDraggingInfo?) {
        isHighlighting = false
    }
}
