import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    let store = RuleStore()
    private var coordinator: Coordinator!
    private let watcher = FolderWatcher()
    private var statusItem: NSStatusItem!
    private var settingsWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        store.load()
        coordinator = Coordinator(store: store)

        setupStatusItem()

        // 起動時スキャン: アプリが寝ていた間のズレを直す
        coordinator.runReconcile()

        // ホームディレクトリを常駐監視（新規作成・移動・改名に追従）
        watcher.handler = { [weak self] events in
            self?.coordinator.handleEvents(events)
        }
        watcher.start(watching: NSHomeDirectory())
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "paintpalette",
                                           accessibilityDescription: "iroha")

        let menu = NSMenu()
        menu.addItem(withTitle: "設定を開く…", action: #selector(openSettings), keyEquivalent: ",")
        menu.addItem(withTitle: "今すぐ塗り直す", action: #selector(reconcileNow), keyEquivalent: "r")
        menu.addItem(.separator())
        menu.addItem(withTitle: "irohaを終了", action: #selector(quit), keyEquivalent: "q")
        for item in menu.items { item.target = self }
        statusItem.menu = menu
    }

    @objc private func openSettings() {
        if settingsWindow == nil {
            let view = SettingsView(store: store, coordinator: coordinator)
            let window = NSWindow(contentViewController: NSHostingController(rootView: view))
            window.title = "iroha"
            window.styleMask = [.titled, .closable, .miniaturizable, .fullSizeContentView]
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.isMovableByWindowBackground = true
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        }
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // Launchpadなどからもう一度開かれたら設定画面を出す
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        openSettings()
        return true
    }

    @objc private func reconcileNow() {
        coordinator.runReconcile()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
