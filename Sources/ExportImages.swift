import AppKit
import PDFKit

/// Export du PDF en images (PNG, JPG, GIF), une par page.
extension ReaderWC {
    @objc func exportImages(_ s: Any?) {
        guard let d = pdfView.document, let win = window else { return }
        pdfView.commitEditing()
        let formats: [(String, String, NSBitmapImageRep.FileType)] = [("PNG", "png", .png), ("JPG", "jpg", .jpeg), ("GIF", "gif", .gif)]
        let scales: [(String, CGFloat)] = [("72 dpi", 1), ("144 dpi", 2), ("216 dpi", 3), ("300 dpi", 300.0 / 72)]
        let multi = d.pageCount > 1

        let fmt = NSPopUpButton(frame: .zero, pullsDown: false); fmt.addItems(withTitles: formats.map { $0.0 })
        let res = NSPopUpButton(frame: .zero, pullsDown: false); res.addItems(withTitles: scales.map { $0.0 }); res.selectItem(at: 1)
        let scope = NSPopUpButton(frame: .zero, pullsDown: false); scope.addItems(withTitles: [L.t("exp.all"), L.t("exp.current")])
        scope.isEnabled = multi
        func row(_ title: String, _ v: NSView) -> NSStackView {
            let l = NSTextField(labelWithString: title); l.alignment = .right
            l.widthAnchor.constraint(equalToConstant: 90).isActive = true
            v.widthAnchor.constraint(equalToConstant: 150).isActive = true
            let r = NSStackView(views: [l, v]); r.spacing = 8; return r
        }
        let box = NSStackView(views: [row(L.t("exp.format"), fmt), row(L.t("exp.scale"), res)] + (multi ? [row(L.t("exp.pages"), scope)] : []))
        box.orientation = .vertical; box.alignment = .leading; box.spacing = 8
        box.edgeInsets = NSEdgeInsets(top: 10, left: 10, bottom: 10, right: 10)
        box.frame = NSRect(origin: .zero, size: box.fittingSize)

        let panel = NSSavePanel()
        panel.accessoryView = box
        panel.prompt = L.t("exp.button")
        panel.canCreateDirectories = true
        let base = (doc.fileURL?.deletingPathExtension().lastPathComponent) ?? doc.displayName ?? "mPDF"
        panel.nameFieldStringValue = base + ".png"
        fmt.target = nil
        let sync = BlockTarget { panel.nameFieldStringValue = (panel.nameFieldStringValue as NSString).deletingPathExtension + "." + formats[fmt.indexOfSelectedItem].1 }
        fmt.target = sync; fmt.action = #selector(BlockTarget.fire)
        objc_setAssociatedObject(fmt, "blk", sync, .OBJC_ASSOCIATION_RETAIN)

        panel.beginSheetModal(for: win) { [weak self] r in
            guard r == .OK, let url = panel.url, let self else { return }
            let f = formats[fmt.indexOfSelectedItem], k = scales[res.indexOfSelectedItem].1
            var idx = Array(0..<d.pageCount)
            if multi, scope.indexOfSelectedItem == 1, let c = self.pdfView.currentPage { idx = [d.index(for: c)] }
            do { try Self.writeImages(d, idx, url, f.1, f.2, k) } catch {
                let a = NSAlert(); a.messageText = L.t("exp.fail"); a.informativeText = error.localizedDescription
                a.beginSheetModal(for: win)
            }
        }
    }

    private static func writeImages(_ d: PDFDocument, _ pages: [Int], _ url: URL, _ ext: String, _ type: NSBitmapImageRep.FileType, _ k: CGFloat) throws {
        let dir = url.deletingLastPathComponent()
        let base = url.deletingPathExtension().lastPathComponent
        for i in pages {
            guard let page = d.page(at: i) else { continue }
            let box = page.bounds(for: .cropBox)
            let rotated = page.rotation % 180 != 0
            let w = Int((rotated ? box.height : box.width) * k), h = Int((rotated ? box.width : box.height) * k)
            guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h, bitsPerSample: 8, samplesPerPixel: 4,
                                             hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
                  let gc = NSGraphicsContext(bitmapImageRep: rep) else { throw CocoaError(.fileWriteUnknown) }
            NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = gc
            let ctx = gc.cgContext
            ctx.setFillColor(NSColor.white.cgColor); ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
            ctx.interpolationQuality = .high
            ctx.scaleBy(x: CGFloat(w) / (rotated ? box.height : box.width), y: CGFloat(h) / (rotated ? box.width : box.height))
            ctx.translateBy(x: -box.minX, y: -box.minY)
            page.draw(with: .cropBox, to: ctx)
            NSGraphicsContext.restoreGraphicsState()
            var props: [NSBitmapImageRep.PropertyKey: Any] = [:]
            if type == .jpeg { props[.compressionFactor] = 0.92 }
            guard let data = rep.representation(using: type, properties: props) else { throw CocoaError(.fileWriteUnknown) }
            let name = pages.count > 1 ? String(format: "%@-%03d.%@", base, i + 1, ext) : "\(base).\(ext)"
            try data.write(to: dir.appendingPathComponent(name))
        }
    }
}

final class BlockTarget: NSObject {
    let block: () -> Void
    init(_ b: @escaping () -> Void) { block = b }
    @objc func fire() { block() }
}
