// mPDF — lecteur PDF rapide pour macOS (PDFKit). Menus, ouverture des documents.
import AppKit
import SwiftUI

@main
enum Main {
    @MainActor static let delegate = AppDelegate()
    @MainActor static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        app.delegate = delegate
        app.run()
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ n: Notification) {
        UserDefaults.standard.register(defaults: ["NSQuitAlwaysKeepsWindows": false])   // pas de restauration de fenêtres (mPDF rouvre le PDF lui-même)
        UserDefaults.standard.register(defaults: ["autoInstall": true])
        Socle.apply()
        Socle.brand("mPDF", color: Color(red: 0.79, green: 0.16, blue: 0.18))
        _ = NSDocumentController.shared
        NSApp.mainMenu = buildMenu()
        let up = UpdateEngine.shared
        up.configure(repo: "mPDF", lang: { L.lang })
        up.autoInstall = { UserDefaults.standard.bool(forKey: "autoInstall") }
        up.installAppMenuItem()
        up.start()
        // Lancé sans fichier : le sélecteur de fichier s'ouvre (sauf en essai automatique).
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            if NSDocumentController.shared.documents.isEmpty, ProcessInfo.processInfo.environment["MPDF_NO_PANEL"] == nil {
                NSDocumentController.shared.openDocument(nil)
            }
        }
    }
    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool { false }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { NSDocumentController.shared.openDocument(nil) }
        return false
    }
    @objc func showAbout(_ s: Any?) { About.show() }
    @objc func showSettings(_ s: Any?) { SettingsWindow.show() }

    // MARK: Menus

    private func item(_ title: String, _ action: Selector?, _ key: String = "", _ mods: NSEvent.ModifierFlags = [.command], tag: Int = 0) -> NSMenuItem {
        let i = NSMenuItem(title: title, action: action, keyEquivalent: key)
        if !key.isEmpty { i.keyEquivalentModifierMask = mods }
        i.tag = tag
        return i
    }
    private func menu(_ title: String, _ items: [NSMenuItem]) -> NSMenuItem {
        let m = NSMenu(title: title); items.forEach { m.addItem($0) }
        let host = NSMenuItem(title: title, action: nil, keyEquivalent: ""); host.submenu = m
        return host
    }

    private func buildMenu() -> NSMenu {
        let t = L.t
        let main = NSMenu()
        let app = menu("mPDF", [
            item(t("menu.about"), #selector(showAbout(_:))), .separator(),
            item(t("menu.settings"), #selector(showSettings(_:)), ","), .separator(),
            item(t("menu.hide"), #selector(NSApplication.hide(_:)), "h"),
            item(t("menu.hideOthers"), #selector(NSApplication.hideOtherApplications(_:)), "h", [.command, .option]),
            item(t("menu.showAll"), #selector(NSApplication.unhideAllApplications(_:))), .separator(),
            item(t("menu.quit"), #selector(NSApplication.terminate(_:)), "q")])
        main.addItem(app)

        let recent = NSMenu(title: t("menu.recent"))
        recent.addItem(item(t("menu.clearRecent"), #selector(NSDocumentController.clearRecentDocuments(_:))))
        recent.perform(NSSelectorFromString("_setMenuName:"), with: "NSRecentDocumentsMenu")
        let recentHost = NSMenuItem(title: t("menu.recent"), action: nil, keyEquivalent: ""); recentHost.submenu = recent
        main.addItem(menu(t("menu.file"), [
            item(t("menu.open"), #selector(NSDocumentController.openDocument(_:)), "o"), recentHost, .separator(),
            item(t("menu.close"), #selector(NSWindow.performClose(_:)), "w"),
            item(t("menu.save"), #selector(NSDocument.save(_:)), "s"),
            item(t("menu.saveAs"), #selector(NSDocument.saveAs(_:)), "S", [.command, .shift]), .separator(),
            item(t("menu.print"), #selector(NSDocument.printDocument(_:)), "p")]))

        main.addItem(menu(t("menu.edit"), [
            item(t("menu.undo"), Selector(("undo:")), "z"), item(t("menu.redo"), Selector(("redo:")), "Z", [.command, .shift]), .separator(),
            item(t("menu.copy"), #selector(NSText.copy(_:)), "c"), item(t("menu.selectAll"), #selector(NSText.selectAll(_:)), "a"), .separator(),
            item(t("menu.find"), #selector(ReaderWC.focusSearch(_:)), "f"),
            item(t("menu.findNext"), #selector(ReaderWC.findNext(_:)), "g"),
            item(t("menu.findPrev"), #selector(ReaderWC.findPrevious(_:)), "G", [.command, .shift])]))

        let displays = ["menu.single", "menu.continuous", "menu.twoUp", "menu.twoUpContinuous"].enumerated().map {
            item(t($1), #selector(ReaderWC.selectDisplay(_:)), "", tag: $0) }
        main.addItem(menu(t("menu.view"), [
            item(t("menu.toolbar"), #selector(ReaderWC.toggleChrome(_:)), "t", [.command, .option]),
            item(t("menu.sidebar"), #selector(ReaderWC.toggleSidebar), "s", [.command, .control]),
            item(t("menu.panelLeft"), #selector(ReaderWC.setPanelSide(_:)), "", tag: 0), item(t("menu.panelRight"), #selector(ReaderWC.setPanelSide(_:)), "", tag: 1),
            item(t("menu.notesPanel"), #selector(ReaderWC.toggleNotes), "n", [.command, .option]), .separator(),
            item(t("menu.zoomIn"), #selector(ReaderWC.zoomIn(_:)), "+"), item(t("menu.zoomOut"), #selector(ReaderWC.zoomOut(_:)), "-"),
            item(t("menu.actualSize"), #selector(ReaderWC.actualSize(_:)), "0"),
            item(t("menu.fitWidth"), #selector(ReaderWC.fitWidth(_:)), "9"), item(t("menu.fitPage"), #selector(ReaderWC.fitPage(_:)), "8"), .separator()]
            + displays + [.separator(),
            item(t("menu.rotateLeft"), #selector(ReaderWC.rotateLeft(_:)), "l"), item(t("menu.rotateRight"), #selector(ReaderWC.rotateRight(_:)), "r"), .separator(),
            item(t("menu.fullScreen"), #selector(NSWindow.toggleFullScreen(_:)), "f", [.command, .control]),
            item(t("menu.presentation"), #selector(ReaderWC.startPresentation(_:)), "p", [.command, .option])]))

        let tools = Tool.allCases.map { item(t($0.key), #selector(ReaderWC.selectTool(_:)), $0.rawValue < 9 ? String($0.rawValue + 1) : "", [.command, .control], tag: $0.rawValue) }
        main.addItem(menu(t("menu.tools"), tools))
        main.addItem(menu(t("menu.pagesMenu"), [
            item(t("menu.insertImage"), #selector(ReaderWC.insertImage(_:)), "i", [.command, .shift]),
            item(t("menu.insertPDF"), #selector(ReaderWC.insertPDFPages(_:)), "o", [.command, .option]), .separator(),
            item(t("menu.blankPage"), #selector(ReaderWC.insertBlankPage(_:)), "n", [.command, .shift]),
            item(t("menu.duplicatePage"), #selector(ReaderWC.duplicateCurrentPage(_:)), "d", [.command, .shift]),
            item(t("menu.deletePage"), #selector(ReaderWC.deleteCurrentPage(_:)), String(UnicodeScalar(NSDeleteCharacter)!), [.command])]))

        main.addItem(menu(t("menu.go"), [
            item(t("menu.nextPage"), #selector(ReaderWC.nextPage(_:)), "]", [.command, .option]), item(t("menu.prevPage"), #selector(ReaderWC.prevPage(_:)), "[", [.command, .option]),
            item(t("menu.firstPage"), #selector(ReaderWC.firstPage(_:)), String(UnicodeScalar(NSHomeFunctionKey)!), []),
            item(t("menu.lastPage"), #selector(ReaderWC.lastPage(_:)), String(UnicodeScalar(NSEndFunctionKey)!), []),
            item(t("menu.goToPage"), #selector(ReaderWC.goToPage(_:)), "g", [.command, .option]), .separator(),
            item(t("menu.back"), #selector(ReaderWC.goBackHistory(_:)), "["), item(t("menu.forward"), #selector(ReaderWC.goForwardHistory(_:)), "]")]))

        let win = menu(t("menu.window"), [
            item(t("menu.minimize"), #selector(NSWindow.performMiniaturize(_:)), "m"), item(t("menu.zoom"), #selector(NSWindow.performZoom(_:))), .separator(),
            item(t("menu.bringAll"), #selector(NSApplication.arrangeInFront(_:)))])
        main.addItem(win)
        NSApp.windowsMenu = win.submenu
        return main
    }
}
