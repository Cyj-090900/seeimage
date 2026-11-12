import AppKit
import UniformTypeIdentifiers

/// The standalone preview window: a small toolbar on top, a zoomable canvas
/// below, and the gallery navigation that used to live inside 上门超人.
final class ImagePreviewWindowController: NSWindowController, NSWindowDelegate {
    var onClose: ((ImagePreviewWindowController) -> Void)?

    private(set) var items: [ImageItem]
    private var index: Int

    private let canvas = ZoomableImageView()
    private let counterLabel = NSTextField(labelWithString: "")
    private let zoomLabel = NSTextField(labelWithString: "100%")

    private var emptyState = NSView()
    private var loadingState = NSView()
    private var errorState = NSView()
    private let spinner = NSProgressIndicator()

    private lazy var previousButton = PillButton(title: "‹ 上一张", target: self, action: #selector(goPrevious))
    private lazy var nextButton = PillButton(title: "下一张 ›", target: self, action: #selector(goNext))
    private lazy var rotateLeftButton = PillButton(title: "↺ 左转", target: self, action: #selector(rotateLeft))
    private lazy var rotateRightButton = PillButton(title: "↻ 右转", target: self, action: #selector(rotateRight))
    private lazy var flipButton = PillButton(title: "↔ 左右翻转", target: self, action: #selector(flipImage))
    private lazy var zoomOutButton = PillButton(title: "− 缩小", target: self, action: #selector(zoomOut))
    private lazy var zoomInButton = PillButton(title: "+ 放大", target: self, action: #selector(zoomIn))
    private lazy var fitButton = PillButton(title: "适应窗口", target: self, action: #selector(fitToWindow))
    private lazy var openButton = PillButton(title: "浏览器打开原图", target: self, action: #selector(openInBrowser))
    private lazy var saveButton = PillButton(title: "存储图片…", target: self, action: #selector(saveImage))

    private var imageCache: [URL: NSImage] = [:]
    private var dataCache: [URL: Data] = [:]
    private var keyMonitor: Any?

    var isShowingEmptyState: Bool { items.isEmpty }

    var currentItem: ImageItem? {
        items.indices.contains(index) ? items[index] : nil
    }

    // MARK: - Lifecycle

    init(items: [ImageItem], startIndex: Int = 0) {
        self.items = items
        if items.isEmpty {
            self.index = 0
        } else {
            self.index = min(max(startIndex, 0), items.count - 1)
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1024, height: 780),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "图片预览"
        window.minSize = NSSize(width: 720, height: 520)
        window.backgroundColor = .windowBackgroundColor
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.center()

        super.init(window: window)
        window.delegate = self

        buildInterface()
        installKeyMonitor()
        refreshChrome()
        loadCurrentImage()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
        }
    }

    // MARK: - Interface

    private func buildInterface() {
        guard let window else { return }

        let content = DropContainerView()
        content.onDrop = { [weak self] urls in
            self?.handleDrop(urls: urls)
        }
        window.contentView = content

        canvas.translatesAutoresizingMaskIntoConstraints = false
        canvas.onZoomChanged = { [weak self] zoom in
            self?.zoomLabel.stringValue = "\(Int((zoom * 100).rounded()))%"
        }
        canvas.onHorizontalDrag = { [weak self] translation in
            guard let self else { return }
            if translation < -70 {
                self.goNext()
            } else if translation > 70 {
                self.goPrevious()
            }
        }
        canvas.contextMenuProvider = { [weak self] in
            self?.makeContextMenu() ?? NSMenu()
        }
        content.addSubview(canvas)

        let firstRow = NSStackView(views: [
            previousButton, nextButton, rotateLeftButton, rotateRightButton, flipButton,
        ])
        firstRow.orientation = .horizontal
        firstRow.alignment = .centerY
        firstRow.spacing = 12
        firstRow.translatesAutoresizingMaskIntoConstraints = false

        let secondRow = NSStackView(views: [
            zoomOutButton, zoomInButton, fitButton, openButton, saveButton,
        ])
        secondRow.orientation = .horizontal
        secondRow.alignment = .centerY
        secondRow.spacing = 12
        secondRow.translatesAutoresizingMaskIntoConstraints = false

        for label in [counterLabel, zoomLabel] {
            label.font = .monospacedDigitSystemFont(ofSize: 13, weight: .medium)
            label.textColor = .secondaryLabelColor
            label.alignment = .right
            label.setContentHuggingPriority(.required, for: .horizontal)
            label.setContentCompressionResistancePriority(.required, for: .horizontal)
        }

        let statusRow = NSStackView(views: [counterLabel, zoomLabel])
        statusRow.orientation = .horizontal
        statusRow.alignment = .centerY
        statusRow.spacing = 14
        statusRow.translatesAutoresizingMaskIntoConstraints = false

        content.addSubview(firstRow)
        content.addSubview(secondRow)
        content.addSubview(statusRow)

        emptyState = makeMessageView(
            symbol: "photo.on.rectangle.angled",
            title: "把图片拖进来",
            detail: "支持本地文件，也支持网页里的图片链接",
            actionTitle: "打开图片…",
            action: #selector(openImages)
        )
        loadingState = makeLoadingView()
        errorState = makeMessageView(
            symbol: "exclamationmark.triangle",
            title: "图片加载失败",
            detail: "检查文件是否仍然存在，或者网络是否正常",
            actionTitle: "重试",
            action: #selector(retryLoading)
        )
        for view in [emptyState, loadingState, errorState] {
            content.addSubview(view)
            NSLayoutConstraint.activate([
                view.centerXAnchor.constraint(equalTo: canvas.centerXAnchor),
                view.centerYAnchor.constraint(equalTo: canvas.centerYAnchor),
            ])
        }

        NSLayoutConstraint.activate([
            firstRow.topAnchor.constraint(equalTo: content.topAnchor, constant: 20),
            firstRow.centerXAnchor.constraint(equalTo: content.centerXAnchor),

            secondRow.topAnchor.constraint(equalTo: firstRow.bottomAnchor, constant: 14),
            secondRow.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 28),

            statusRow.centerYAnchor.constraint(equalTo: secondRow.centerYAnchor),
            statusRow.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -32),

            canvas.topAnchor.constraint(equalTo: secondRow.bottomAnchor, constant: 8),
            canvas.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            canvas.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            canvas.bottomAnchor.constraint(equalTo: content.bottomAnchor),
        ])
    }

    private func makeMessageView(
        symbol: String,
        title: String,
        detail: String,
        actionTitle: String?,
        action: Selector?
    ) -> NSView {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false

        let iconView = NSImageView()
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.image = NSImage(
            systemSymbolName: symbol,
            accessibilityDescription: nil
        )?.withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 44, weight: .regular))
        iconView.contentTintColor = .tertiaryLabelColor

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 16, weight: .semibold)
        titleLabel.textColor = .labelColor
        titleLabel.alignment = .center

        let detailLabel = NSTextField(labelWithString: detail)
        detailLabel.font = .systemFont(ofSize: 12.5)
        detailLabel.textColor = .secondaryLabelColor
        detailLabel.alignment = .center

        let stack = NSStackView(views: [iconView, titleLabel, detailLabel])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.setCustomSpacing(18, after: iconView)
        stack.setCustomSpacing(14, after: detailLabel)

        if let actionTitle, let action {
            let button = NSButton(title: actionTitle, target: self, action: action)
            button.bezelStyle = .rounded
            button.controlSize = .large
            button.font = .systemFont(ofSize: 13, weight: .medium)
            stack.addArrangedSubview(button)
        }

        container.addSubview(stack)
        NSLayoutConstraint.activate([
            iconView.widthAnchor.constraint(equalToConstant: 46),
            iconView.heightAnchor.constraint(equalToConstant: 46),
            stack.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: container.centerYAnchor),
        ])
        return container
    }

    private func makeLoadingView() -> NSView {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false

        spinner.style = .spinning
        spinner.controlSize = .regular
        spinner.isDisplayedWhenStopped = false
        spinner.translatesAutoresizingMaskIntoConstraints = false

        let label = NSTextField(labelWithString: "正在加载…")
        label.font = .systemFont(ofSize: 12.5)
        label.textColor = .secondaryLabelColor
        label.alignment = .center

        let stack = NSStackView(views: [spinner, label])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: container.centerYAnchor),
        ])
        return container
    }

    // MARK: - Gallery

    func replace(items newItems: [ImageItem]) {
        items = newItems
        index = 0
        refreshChrome()
        loadCurrentImage()
    }

    @objc func goPrevious() {
        guard index > 0 else { return }
        index -= 1
        refreshChrome()
        loadCurrentImage()
    }

    @objc func goNext() {
        guard index + 1 < items.count else { return }
        index += 1
        refreshChrome()
        loadCurrentImage()
    }

    private func handleDrop(urls: [URL]) {
        let dropped = urls.map(ImageItem.init(url:))
        guard !dropped.isEmpty else { return }
        if items.isEmpty {
            replace(items: dropped)
        } else {
            let firstNew = items.count
            items.append(contentsOf: dropped)
            index = firstNew
            refreshChrome()
            loadCurrentImage()
        }
    }

    // MARK: - Loading

    private func loadCurrentImage() {
        guard items.indices.contains(index) else {
            showEmptyState()
            return
        }
        let item = items[index]
        hideMessages()

        if let cached = imageCache[item.url] {
            apply(image: cached)
            return
        }

        if !item.isRemote {
            if let image = NSImage(contentsOf: item.url) {
                imageCache[item.url] = image
                apply(image: image)
            } else {
                showErrorState()
            }
            return
        }

        showLoadingState()
        let requestedURL = item.url
        Task { [weak self] in
            guard let self else { return }
            do {
                let (data, response) = try await URLSession.shared.data(from: requestedURL)
                if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                    throw URLError(.badServerResponse)
                }
                guard let image = NSImage(data: data) else {
                    throw URLError(.cannotDecodeContentData)
                }
                guard self.currentItem?.url == requestedURL else { return }
                self.imageCache[requestedURL] = image
                self.dataCache[requestedURL] = data
                self.apply(image: image)
                self.prefetchNeighbours()
            } catch {
                guard self.currentItem?.url == requestedURL else { return }
                self.showErrorState()
            }
        }
    }

    private func apply(image: NSImage) {
        hideMessages()
        canvas.image = image
        zoomLabel.stringValue = "100%"
        window?.makeFirstResponder(canvas)
    }

    private func prefetchNeighbours() {
        guard !items.isEmpty else { return }
        for offset in [-1, 1] {
            let neighbourIndex = index + offset
            guard items.indices.contains(neighbourIndex) else { continue }
            let item = items[neighbourIndex]
            guard item.isRemote, imageCache[item.url] == nil else { continue }
            let url = item.url
            Task { [weak self] in
                guard let self else { return }
                guard let (data, _) = try? await URLSession.shared.data(from: url),
                      let image = NSImage(data: data) else { return }
                self.imageCache[url] = image
                self.dataCache[url] = data
            }
        }
    }

    @objc private func retryLoading() {
        loadCurrentImage()
    }

    // MARK: - States

    private func hideMessages() {
        emptyState.isHidden = true
        loadingState.isHidden = true
        errorState.isHidden = true
        spinner.stopAnimation(nil)
    }

    private func showEmptyState() {
        hideMessages()
        canvas.image = nil
        emptyState.isHidden = false
        counterLabel.stringValue = ""
        window?.title = "图片预览"
    }

    private func showLoadingState() {
        hideMessages()
        canvas.image = nil
        loadingState.isHidden = false
        spinner.startAnimation(nil)
    }

    private func showErrorState() {
        hideMessages()
        canvas.image = nil
        errorState.isHidden = false
    }

    private func refreshChrome() {
        let hasItems = !items.isEmpty
        previousButton.isEnabled = hasItems && index > 0
        nextButton.isEnabled = hasItems && index + 1 < items.count
        rotateLeftButton.isEnabled = hasItems
        rotateRightButton.isEnabled = hasItems
        flipButton.isEnabled = hasItems
        zoomOutButton.isEnabled = hasItems
        zoomInButton.isEnabled = hasItems
        fitButton.isEnabled = hasItems
        openButton.isEnabled = hasItems
        saveButton.isEnabled = hasItems
        counterLabel.stringValue = hasItems ? "\(index + 1) / \(items.count)" : ""
        window?.title = hasItems ? "图片预览 \(index + 1)/\(items.count)" : "图片预览"
    }

    // MARK: - Commands

    @objc func openImages() {
        guard let window else { return }
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.image]
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK else { return }
            self?.handleDrop(urls: panel.urls)
        }
    }

    @objc func zoomIn() {
        canvas.zoom(by: 1.25)
    }

    @objc func zoomOut() {
        canvas.zoom(by: 0.8)
    }

    @objc func fitToWindow() {
        canvas.fitToWindow()
    }

    @objc func rotateLeft() {
        canvas.rotate(by: -1)
    }

    @objc func rotateRight() {
        canvas.rotate(by: 1)
    }

    @objc func flipImage() {
        canvas.flipHorizontally()
    }

    @objc func copyImageAddress() {
        guard let item = currentItem else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(item.url.absoluteString, forType: .string)
    }

    @objc func openInBrowser() {
        guard let item = currentItem else { return }
        if item.isRemote {
            NSWorkspace.shared.open(item.url)
            return
        }
        let probe = URL(string: "https://example.com")!
        if let browser = NSWorkspace.shared.urlForApplication(toOpen: probe) {
            NSWorkspace.shared.open(
                [item.url],
                withApplicationAt: browser,
                configuration: NSWorkspace.OpenConfiguration()
            )
        } else {
            NSWorkspace.shared.open(item.url)
        }
    }

    @objc func saveImage() {
        guard let item = currentItem, let window else { return }
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = item.suggestedFileName
        panel.allowedContentTypes = [UTType(filenameExtension: item.fileExtension) ?? .png]
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let destination = panel.url else { return }
            self?.writeImageData(for: item, to: destination)
        }
    }

    private func writeImageData(for item: ImageItem, to destination: URL) {
        if let data = dataCache[item.url] {
            persist(data, to: destination)
            return
        }
        if !item.isRemote, let data = try? Data(contentsOf: item.url) {
            dataCache[item.url] = data
            persist(data, to: destination)
            return
        }
        Task { [weak self] in
            guard let self else { return }
            do {
                let (data, _) = try await URLSession.shared.data(from: item.url)
                self.dataCache[item.url] = data
                self.persist(data, to: destination)
            } catch {
                self.presentError("图片下载失败，无法存储。")
            }
        }
    }

    private func persist(_ data: Data, to destination: URL) {
        do {
            try data.write(to: destination, options: .atomic)
        } catch {
            presentError("保存失败：\(error.localizedDescription)")
        }
    }

    private func presentError(_ message: String) {
        guard let window else { return }
        let alert = NSAlert()
        alert.messageText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "好")
        alert.beginSheetModal(for: window, completionHandler: nil)
    }

    private func makeContextMenu() -> NSMenu {
        let menu = NSMenu()
        let entries: [(String, Selector)] = [
            ("适应窗口", #selector(fitToWindow)),
            ("放大", #selector(zoomIn)),
            ("缩小", #selector(zoomOut)),
            ("", #selector(fitToWindow)),
            ("向左旋转", #selector(rotateLeft)),
            ("向右旋转", #selector(rotateRight)),
            ("左右翻转", #selector(flipImage)),
            ("", #selector(fitToWindow)),
            ("复制图片地址", #selector(copyImageAddress)),
            ("在浏览器中打开原图", #selector(openInBrowser)),
            ("存储图片…", #selector(saveImage)),
        ]
        for (title, action) in entries {
            if title.isEmpty {
                menu.addItem(.separator())
                continue
            }
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = self
            menu.addItem(item)
        }
        return menu
    }

    // MARK: - Keyboard

    private func installKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.window === self.window else { return event }
            return self.handleKeyDown(event) ? nil : event
        }
    }

    private func handleKeyDown(_ event: NSEvent) -> Bool {
        if event.modifierFlags.contains(.command) || event.modifierFlags.contains(.control) {
            return false
        }
        switch event.keyCode {
        case 123:
            goPrevious()
            return true
        case 124:
            goNext()
            return true
        default:
            break
        }

        guard let characters = event.charactersIgnoringModifiers?.lowercased() else { return false }
        switch characters {
        case "+", "=":
            zoomIn()
            return true
        case "-", "_":
            zoomOut()
            return true
        case "0":
            fitToWindow()
            return true
        case "r":
            if event.modifierFlags.contains(.shift) {
                rotateLeft()
            } else {
                rotateRight()
            }
            return true
        case "f":
            flipImage()
            return true
        default:
            return false
        }
    }

    // MARK: - NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
        onClose?(self)
    }
}
