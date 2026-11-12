// mPDF — document : lecture/écriture du PDF (PDFKit), mot de passe, impression.
import AppKit
import PDFKit

final class PDFDoc: NSDocument {
    var pdf: PDFDocument?

    override class var autosavesInPlace: Bool { false }
    override class var readableTypes: [String] { ["com.adobe.pdf"] }
    override class func canConcurrentlyReadDocuments(ofType typeName: String) -> Bool { false }

    override func read(from url: URL, ofType typeName: String) throws {
        guard let d = PDFDocument(url: url) else { throw CocoaError(.fileReadCorruptFile) }
        if d.isLocked {
            var ok = false
            for attempt in 0..<3 {
                guard let pw = MainActor.assumeIsolated({ Self.askPassword(name: url.lastPathComponent, wrong: attempt > 0) }) else { throw CocoaError(.userCancelled) }
                if d.unlock(withPassword: pw) { ok = true; break }
            }
            guard ok else { throw CocoaError(.fileReadNoPermission) }
        }
        pdf = d
    }

    override func write(to url: URL, ofType typeName: String) throws {
        MainActor.assumeIsolated { (windowControllers.first as? ReaderWC)?.flattenImages() }
        guard let pdf, pdf.write(to: url) else { throw CocoaError(.fileWriteUnknown) }
    }

    override func makeWindowControllers() {
        addWindowController(ReaderWC(doc: self))
    }

    override func printOperation(withSettings printSettings: [NSPrintInfo.AttributeKey: Any]) throws -> NSPrintOperation {
        let info = (printInfo.copy() as? NSPrintInfo) ?? NSPrintInfo.shared
        info.dictionary().addEntries(from: printSettings.reduce(into: [:]) { $0[$1.key.rawValue] = $1.value })
        guard let op = pdf?.printOperation(for: info, scalingMode: .pageScaleDownToFit, autoRotate: true) else { throw CocoaError(.fileReadUnknown) }
        return op
    }

    @MainActor private static func askPassword(name: String, wrong: Bool) -> String? {
        let alert = NSAlert()
        alert.messageText = L.t("pw.title")
        alert.informativeText = (wrong ? L.t("pw.wrong") + " " : "") + L.t("pw.info", name)
        let field = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        alert.accessoryView = field
        alert.addButton(withTitle: L.t("pw.open"))
        alert.addButton(withTitle: L.t("note.cancel"))
        alert.window.initialFirstResponder = field
        return alert.runModal() == .alertFirstButtonReturn ? field.stringValue : nil
    }
}
