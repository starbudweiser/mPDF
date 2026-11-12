// mPDF — présentation plein écran : une page à la fois, flèches / espace / clic pour avancer, Échap pour quitter.
import AppKit
import PDFKit

private final class PresWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
    override func keyDown(with e: NSEvent) {
        guard let v = contentView as? PresView else { return super.keyDown(with: e) }
        switch e.keyCode {
        case 53: Presentation.stop()                                   // Échap
        case 124, 125, 49, 121, 36: v.goToNextPage(nil)                // →, ↓, espace, page suivante, retour
        case 123, 126, 51, 116: v.goToPreviousPage(nil)                // ←, ↑, effacer, page précédente
        case 115: v.goToFirstPage(nil)
        case 119: v.goToLastPage(nil)
        default: super.keyDown(with: e)
        }
        NSCursor.setHiddenUntilMouseMoves(true)
    }
}

private final class PresView: PDFView {
    override var acceptsFirstResponder: Bool { true }
    override func mouseDown(with e: NSEvent) { goToNextPage(nil) }
    override func rightMouseDown(with e: NSEvent) { goToPreviousPage(nil) }
    override func scrollWheel(with e: NSEvent) {}
}

@MainActor
enum Presentation {
    private static var window: NSWindow?

    static func start(document: PDFDocument?, page: PDFPage?, from screen: NSScreen?) {
        guard let document, window == nil else { return }
        let scr = screen ?? NSScreen.main ?? NSScreen.screens[0]
        let w = PresWindow(contentRect: scr.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        w.level = .mainMenu + 1
        w.isReleasedWhenClosed = false
        w.backgroundColor = .black
        let v = PresView(frame: scr.frame)
        v.document = document
        v.displayMode = .singlePage
        v.displaysPageBreaks = false
        v.autoScales = true
        v.backgroundColor = .black
        v.interpolationQuality = .high
        w.contentView = v
        NSApp.presentationOptions = [.hideDock, .hideMenuBar]
        w.setFrame(scr.frame, display: true)
        w.makeKeyAndOrderFront(nil)
        w.makeFirstResponder(v)
        if let page { v.go(to: page) }
        NSCursor.setHiddenUntilMouseMoves(true)
        window = w
    }

    static func stop() {
        NSApp.presentationOptions = []
        window?.orderOut(nil)
        window = nil
    }
}
