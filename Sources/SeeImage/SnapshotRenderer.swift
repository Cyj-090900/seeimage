import AppKit

/// Renders the preview window into a PNG without showing it on screen. Used by
/// CI and by `scripts/preview.sh` to keep documentation screenshots honest.
enum SnapshotRenderer {
    static func run(outputPath: String, inputs: [URL] = []) {
        let application = NSApplication.shared
        application.setActivationPolicy(.accessory)

        var urls = inputs
        if urls.isEmpty {
            urls = makeSampleImages()
        }
        guard !urls.isEmpty else {
            print("snapshot: no images to render")
            return
        }

        let controller = ImagePreviewWindowController(
            items: urls.map(ImageItem.init(url:)),
            startIndex: urls.count > 1 ? 1 : 0
        )
        guard let window = controller.window else { return }
        window.appearance = NSAppearance(named: .aqua)
        window.setContentSize(NSSize(width: 1120, height: 820))

        // Briefly put the window on screen and make it key, so the traffic
        // lights render in their active colours like a real window. It lives
        // at the bottom-left corner for a fraction of a second.
        window.setFrameOrigin(NSPoint(x: 40, y: 40))
        window.makeKeyAndOrderFront(nil)
        if #available(macOS 14.0, *) {
            application.activate()
        } else {
            application.activate(ignoringOtherApps: true)
        }
        RunLoop.current.run(until: Date().addingTimeInterval(0.4))

        guard let view = window.contentView?.superview ?? window.contentView else { return }
        view.layoutSubtreeIfNeeded()
        view.displayIfNeeded()

        let bounds = view.bounds
        guard let representation = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(bounds.width * 2),
            pixelsHigh: Int(bounds.height * 2),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else { return }
        representation.size = bounds.size
        view.cacheDisplay(in: bounds, to: representation)

        guard let png = representation.representation(using: .png, properties: [:]) else { return }
        let destination = URL(fileURLWithPath: outputPath)
        try? FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        window.orderOut(nil)
        do {
            try png.write(to: destination)
            print("snapshot written to \(destination.path)")
        } catch {
            print("snapshot failed: \(error)")
        }
    }

    private static func makeSampleImages() -> [URL] {
        let size = NSSize(width: 1170, height: 1500)
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("seeimage-snapshot", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        var urls: [URL] = []
        for variant in 0..<2 {
            let image = SampleImage.make(size: size, variant: variant)
            guard let tiff = image.tiffRepresentation,
                  let representation = NSBitmapImageRep(data: tiff),
                  let png = representation.representation(using: .png, properties: [:]) else {
                continue
            }
            let url = directory.appendingPathComponent("sample-\(variant).png")
            try? png.write(to: url)
            urls.append(url)
        }
        return urls
    }
}
