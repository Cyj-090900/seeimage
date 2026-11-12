import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controllers: [ImagePreviewWindowController] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = buildMainMenu()

        let urls = Self.urlsFromCommandLine()
        if urls.isEmpty {
            showWindow(items: [])
        } else {
            open(urls: urls)
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        open(urls: urls)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag, let controller = controllers.last {
            controller.showWindow(nil)
            controller.window?.makeKeyAndOrderFront(nil)
        }
        return true
    }

    // MARK: - Opening images

    private static func urlsFromCommandLine() -> [URL] {
        CommandLine.arguments.dropFirst().compactMap { raw in
            guard !raw.isEmpty, !raw.hasPrefix("-") else { return nil }
            if let url = URL(string: raw),
               let scheme = url.scheme?.lowercased(),
               ["http", "https", "file"].contains(scheme) {
                return url
            }
            return URL(fileURLWithPath: raw)
        }
    }

    private func open(urls: [URL]) {
        let items = urls.map(ImageItem.init(url:))
        guard !items.isEmpty else { return }

        if let emptyWindow = controllers.last(where: { $0.isShowingEmptyState }) {
            emptyWindow.replace(items: items)
            emptyWindow.showWindow(nil)
            emptyWindow.window?.makeKeyAndOrderFront(nil)
            return
        }
        showWindow(items: items)
    }

    private func showWindow(items: [ImageItem]) {
        let controller = ImagePreviewWindowController(items: items)
        controller.onClose = { [weak self] closed in
            self?.controllers.removeAll { $0 === closed }
        }
        controllers.append(controller)
        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
    }

    private var frontController: ImagePreviewWindowController? {
        controllers.last(where: { $0.window?.isKeyWindow == true }) ?? controllers.last
    }

    // MARK: - Menu actions

    @objc private func openImagesAction() {
        frontController?.openImages()
    }

    @objc private func saveImageAction() {
        frontController?.saveImage()
    }

    @objc private func closeWindowAction() {
        NSApp.keyWindow?.performClose(nil)
    }

    @objc private func zoomInAction() {
        frontController?.zoomIn()
    }

    @objc private func zoomOutAction() {
        frontController?.zoomOut()
    }

    @objc private func fitAction() {
        frontController?.fitToWindow()
    }

    @objc private func rotateLeftAction() {
        frontController?.rotateLeft()
    }

    @objc private func rotateRightAction() {
        frontController?.rotateRight()
    }

    @objc private func flipAction() {
        frontController?.flipImage()
    }

    @objc private func previousImageAction() {
        frontController?.goPrevious()
    }

    @objc private func nextImageAction() {
        frontController?.goNext()
    }

    // MARK: - Menu

    private func buildMainMenu() -> NSMenu {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu(title: "SeeImage")
        appMenu.addItem(makeItem("关于 SeeImage", #selector(NSApplication.orderFrontStandardAboutPanel(_:)), "", target: NSApp))
        appMenu.addItem(.separator())
        appMenu.addItem(makeItem("隐藏 SeeImage", #selector(NSApplication.hide(_:)), "h", target: NSApp))
        let hideOthers = makeItem("隐藏其他", #selector(NSApplication.hideOtherApplications(_:)), "h", target: NSApp)
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(hideOthers)
        appMenu.addItem(makeItem("显示全部", #selector(NSApplication.unhideAllApplications(_:)), "", target: NSApp))
        appMenu.addItem(.separator())
        appMenu.addItem(makeItem("退出 SeeImage", #selector(NSApplication.terminate(_:)), "q", target: NSApp))
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        let fileMenuItem = NSMenuItem()
        let fileMenu = NSMenu(title: "文件")
        fileMenu.addItem(makeItem("打开图片…", #selector(openImagesAction), "o"))
        fileMenu.addItem(makeItem("存储图片…", #selector(saveImageAction), "s"))
        fileMenu.addItem(.separator())
        fileMenu.addItem(makeItem("关闭窗口", #selector(closeWindowAction), "w"))
        fileMenuItem.submenu = fileMenu
        mainMenu.addItem(fileMenuItem)

        let viewMenuItem = NSMenuItem()
        let viewMenu = NSMenu(title: "显示")
        viewMenu.addItem(makeItem("放大", #selector(zoomInAction), "+"))
        viewMenu.addItem(makeItem("缩小", #selector(zoomOutAction), "-"))
        viewMenu.addItem(makeItem("适应窗口", #selector(fitAction), "0"))
        viewMenu.addItem(.separator())
        viewMenu.addItem(makeItem("向左旋转", #selector(rotateLeftAction), "R"))
        viewMenu.addItem(makeItem("向右旋转", #selector(rotateRightAction), "r"))
        viewMenu.addItem(makeItem("左右翻转", #selector(flipAction), "F"))
        viewMenu.addItem(.separator())
        viewMenu.addItem(makeItem("上一张", #selector(previousImageAction), "["))
        viewMenu.addItem(makeItem("下一张", #selector(nextImageAction), "]"))
        viewMenuItem.submenu = viewMenu
        mainMenu.addItem(viewMenuItem)

        let windowMenuItem = NSMenuItem()
        let windowMenu = NSMenu(title: "窗口")
        windowMenu.addItem(makeItem("最小化", #selector(NSWindow.performMiniaturize(_:)), "m"))
        windowMenu.addItem(makeItem("缩放", #selector(NSWindow.performZoom(_:)), ""))
        windowMenuItem.submenu = windowMenu
        NSApp.windowsMenu = windowMenu
        mainMenu.addItem(windowMenuItem)

        return mainMenu
    }

    private func makeItem(_ title: String, _ action: Selector, _ key: String, target: AnyObject? = nil) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = target ?? self
        return item
    }
}
