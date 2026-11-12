// mPDF — vue PDF avec outils : sélection / déplacement / redimensionnement des ajouts, texte en place, coches, formes, stylo,
// gomme blanche, images, surlignage, notes ; dépôt de PDF et d'images directement sur la page.
import AppKit
import PDFKit
import UniformTypeIdentifiers

enum Tool: Int, CaseIterable {
    case select, hand, highlight, underline, strike, note, text, pen, rect, ellipse, arrow, whiteout, check, cross
    var key: String { ["tool.select", "tool.hand", "tool.highlight", "tool.underline", "tool.strike", "tool.note", "tool.text", "tool.pen", "tool.rect", "tool.ellipse", "tool.arrow", "tool.whiteout", "tool.check", "tool.cross"][rawValue] }
    var symbol: String { ["cursorarrow", "hand.raised", "highlighter", "underline", "strikethrough", "note.text", "textbox", "pencil.tip", "rectangle", "circle", "arrow.up.right", "eraser", "checkmark", "xmark"][rawValue] }
    /// Outils qui restent actifs après un geste (le reste revient à la sélection).
    var persistent: Bool { self == .highlight || self == .underline || self == .strike || self == .pen || self == .hand || self == .select }
}

/// Image posée sur la page : dessinée par la vue, figée dans la page à l'enregistrement (voir ReaderWC.flattenImages).
final class ImageAnnotation: PDFAnnotation {
    var image: NSImage?
    init(image: NSImage, bounds: NSRect) {
        self.image = image
        super.init(bounds: bounds, forType: .stamp, withProperties: nil)
        shouldPrint = true
    }
    required init?(coder: NSCoder) { super.init(coder: coder) }
    override func draw(with box: PDFDisplayBox, in context: CGContext) {
        guard let image, let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
        context.saveGState(); context.interpolationQuality = .high
        context.draw(cg, in: bounds)
        context.restoreGState()
    }
}

/// Calque transparent au-dessus du PDF : poignées de la sélection et aperçu du geste en cours (ne capte aucun clic).
private final class OverlayView: NSView {
    var selectionRect: NSRect?
    var showHandles = true
    var previewPath: NSBezierPath?
    var previewKind: Tool?
    var flippedState = true
    override var isFlipped: Bool { flippedState }
    override func hitTest(_ p: NSPoint) -> NSView? { nil }
    override func draw(_ r: NSRect) {
        if let path = previewPath, let kind = previewKind {
            let color: NSColor = kind == .whiteout ? .white : (kind == .pen ? .systemBlue : .systemRed)
            if kind == .whiteout { color.setFill(); path.fill(); NSColor.separatorColor.setStroke() } else { color.setStroke() }
            path.lineWidth = 2; path.lineCapStyle = .round; path.lineJoinStyle = .round
            path.stroke()
        }
        guard let s = selectionRect else { return }
        let accent = NSColor.controlAccentColor
        accent.setStroke()
        let p = NSBezierPath(rect: s.insetBy(dx: -1, dy: -1)); p.lineWidth = 1.5; p.setLineDash([5, 3], count: 2, phase: 0); p.stroke()
        guard showHandles else { return }
        for h in ReaderPDFView.Handle.allCases {
            let hr = ReaderPDFView.handleRect(h, in: s)
            NSColor.white.setFill(); NSBezierPath(roundedRect: hr, xRadius: 2, yRadius: 2).fill()
            let b = NSBezierPath(roundedRect: hr, xRadius: 2, yRadius: 2); b.lineWidth = 1.5; b.stroke()
        }
    }
}

private final class InlineEditor: NSTextView {
    var onCommit: (() -> Void)?
    override func keyDown(with e: NSEvent) {
        if e.keyCode == 53 || (e.keyCode == 36 && e.modifierFlags.contains(.command)) { onCommit?() } else { super.keyDown(with: e) }
    }
    override func resignFirstResponder() -> Bool { let r = super.resignFirstResponder(); if r { onCommit?() }; return r }
}

final class ReaderPDFView: PDFView {
    enum Handle: CaseIterable { case tl, t, tr, r, br, b, bl, l }

    var tool: Tool = .select {
        didSet { window?.invalidateCursorRects(for: self); if tool != .select { select(nil) } }
    }
    var onAdd: ((PDFAnnotation, PDFPage) -> Void)?
    var onEdit: ((PDFAnnotation, PDFPage) -> Void)?            // note : feuille de saisie
    var onTextChanged: ((PDFAnnotation, PDFPage, String, NSRect) -> Void)?
    var onGeometry: ((PDFAnnotation, PDFPage, NSRect, NSRect) -> Void)?
    var onDeleteSelected: ((PDFAnnotation, PDFPage) -> Void)?
    var onTopOverscroll: (() -> Void)?
    var onLayout: (() -> Void)?
    var fitsPage = true
    var onToolChange: ((Tool) -> Void)?
    var onDropFiles: (([URL], PDFPage, NSPoint, NSPoint) -> Void)?

    private(set) var selected: (annot: PDFAnnotation, page: PDFPage)?
    private let overlay = OverlayView()
    private var editor: InlineEditor?
    private var editing: (a: PDFAnnotation, page: PDFPage, isNew: Bool, oldText: String, oldBounds: NSRect)?
    private weak var scroller: NSScrollView?
    private var observers: [NSObjectProtocol] = []

    // MARK: Cycle de vie

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil, overlay.superview == nil else { return }
        registerForDraggedTypes([.fileURL])
        overlay.flippedState = isFlipped
        overlay.frame = bounds; overlay.autoresizingMask = [.width, .height]
        addSubview(overlay, positioned: .above, relativeTo: nil)
        let nc = NotificationCenter.default
        for n in [Notification.Name.PDFViewScaleChanged, .PDFViewPageChanged, .PDFViewDisplayModeChanged] {
            observers.append(nc.addObserver(forName: n, object: self, queue: .main) { [weak self] _ in MainActor.assumeIsolated { self?.refreshOverlay() } })
        }
        if let s = findScroller(self) {
            s.contentView.postsBoundsChangedNotifications = true
            observers.append(nc.addObserver(forName: NSView.boundsDidChangeNotification, object: s.contentView, queue: .main) { [weak self] _ in MainActor.assumeIsolated { self?.refreshOverlay() } })
        }
    }
    /// Aucune marge système autour de la page (la barre de titre transparente ne réserve rien).
    private func clearInsets() {
        guard let s = findScroller(self) else { return }
        if s.automaticallyAdjustsContentInsets { s.automaticallyAdjustsContentInsets = false }
        if s.contentInsets.top != 0 || s.contentInsets.left != 0 || s.contentInsets.bottom != 0 || s.contentInsets.right != 0 { s.contentInsets = NSEdgeInsetsZero }
    }
    override func layout() { clearInsets(); super.layout(); onLayout?(); refreshOverlay() }

    private func findScroller(_ v: NSView) -> NSScrollView? {
        if let s = v as? NSScrollView { return s }
        for sub in v.subviews { if let s = findScroller(sub) { return s } }
        return nil
    }

    // MARK: Sélection

    static func handleRect(_ h: Handle, in r: NSRect) -> NSRect {
        let s: CGFloat = 9
        let (x, y): (CGFloat, CGFloat)
        switch h {
        case .tl: (x, y) = (r.minX, r.minY); case .t: (x, y) = (r.midX, r.minY); case .tr: (x, y) = (r.maxX, r.minY)
        case .r: (x, y) = (r.maxX, r.midY); case .br: (x, y) = (r.maxX, r.maxY); case .b: (x, y) = (r.midX, r.maxY)
        case .bl: (x, y) = (r.minX, r.maxY); case .l: (x, y) = (r.minX, r.midY)
        }
        return NSRect(x: x - s / 2, y: y - s / 2, width: s, height: s)
    }

    private static let selectableTypes: Set<String> = ["Highlight", "Underline", "StrikeOut", "Text", "FreeText", "Square", "Circle", "Line", "Ink", "Stamp"]
    private static let markupTypes: Set<String> = ["Highlight", "Underline", "StrikeOut"]

    private func canResize(_ a: PDFAnnotation) -> Bool { !(Self.markupTypes.contains(a.type ?? "") || a.type == "Text" || a.type == "Ink") }
    private func canMove(_ a: PDFAnnotation) -> Bool { !Self.markupTypes.contains(a.type ?? "") }

    func select(_ a: PDFAnnotation?, on page: PDFPage? = nil) {
        if let a, let page { selected = (a, page) } else { selected = nil }
        refreshOverlay()
    }

    func refreshOverlay() {
        if let s = selected, s.page.annotations.contains(where: { $0 === s.annot }) {
            overlay.selectionRect = convert(s.annot.bounds, from: s.page)
            overlay.showHandles = canResize(s.annot)
        } else { selected = nil; overlay.selectionRect = nil }
        overlay.needsDisplay = true
    }

    private func hitAnnotation(_ e: NSEvent) -> (PDFAnnotation, PDFPage)? {
        let pt = convert(e.locationInWindow, from: nil)
        guard let page = page(for: pt, nearest: false) else { return nil }
        let pp = convert(pt, to: page)
        let hit = page.annotations.last { a in
            guard let t = a.type, Self.selectableTypes.contains(t) else { return false }
            return a.bounds.insetBy(dx: -4, dy: -4).contains(pp)
        }
        return hit.map { ($0, page) }
    }

    private func handleAt(_ pt: NSPoint) -> Handle? {
        guard let r = overlay.selectionRect, overlay.showHandles else { return nil }
        return Handle.allCases.first { Self.handleRect($0, in: r).insetBy(dx: -3, dy: -3).contains(pt) }
    }

    // MARK: Souris

    override func resetCursorRects() {
        super.resetCursorRects()
        switch tool {
        case .hand: addCursorRect(bounds, cursor: .openHand)
        case .note, .text, .pen, .rect, .ellipse, .arrow, .whiteout, .check, .cross: addCursorRect(bounds, cursor: .crosshair)
        default: break
        }
    }

    override func mouseDown(with e: NSEvent) {
        if editor != nil { commitEditing() }
        let pt = convert(e.locationInWindow, from: nil)
        guard bounds.contains(pt) else { return super.mouseDown(with: e) }   // clic hors de la page (bord, barre de titre) : ne touche ni la sélection ni les outils
        switch tool {
        case .select:
            if let h = handleAt(pt), let s = selected { startResize(h, s, e); return }
            if let (a, p) = hitAnnotation(e) {
                select(a, on: p)
                if e.clickCount == 2, a.type == "FreeText" { beginEditing(a, on: p, isNew: false); return }
                if e.clickCount == 2, a.type == "Text" { onEdit?(a, p); return }
                if canMove(a) { startMove(a, p, e) }
                return
            }
            select(nil)
            super.mouseDown(with: e)
        case .hand:
            scroller = findScroller(self)
            NSCursor.closedHand.set()
        case .note: place(e)
        case .text: placeText(e)
        case .check, .cross: placeMark(e)
        case .highlight: super.mouseDown(with: e); markup(.highlight, .systemYellow)
        case .underline: super.mouseDown(with: e); markup(.underline, .systemRed)
        case .strike: super.mouseDown(with: e); markup(.strikeOut, .systemRed)
        case .rect, .ellipse, .whiteout, .arrow, .pen: drawShape(e)
        }
    }

    override func mouseDragged(with e: NSEvent) {
        guard tool == .hand, let s = scroller else { return super.mouseDragged(with: e) }
        let clip = s.contentView
        var o = clip.bounds.origin
        o.x -= e.deltaX
        o.y += (s.documentView?.isFlipped ?? true) ? -e.deltaY : e.deltaY
        clip.scroll(to: clip.constrainBoundsRect(NSRect(origin: o, size: clip.bounds.size)).origin)
        s.reflectScrolledClipView(clip)
    }

    override func mouseUp(with e: NSEvent) {
        if tool == .hand { NSCursor.openHand.set() } else { super.mouseUp(with: e) }
    }

    override func keyDown(with e: NSEvent) {
        if let s = selected, e.keyCode == 51 || e.keyCode == 117 { onDeleteSelected?(s.annot, s.page); select(nil); return }
        if e.keyCode == 36, let s = selected, s.annot.type == "FreeText" { beginEditing(s.annot, on: s.page, isNew: false); return }
        if e.keyCode == 53 { if selected != nil { select(nil) } else if tool != .select { setTool(.select) }; return }
        super.keyDown(with: e)
    }

    func setTool(_ t: Tool) { tool = t; onToolChange?(t) }
    private func finishPlacement() { if !tool.persistent { setTool(.select) } }

    // MARK: Déplacer / redimensionner

    private func startMove(_ a: PDFAnnotation, _ page: PDFPage, _ e: NSEvent) {
        let old = a.bounds
        var last = convert(e.locationInWindow, from: nil)
        let startViewRect = convert(old, from: page)
        var moved = false
        while let ev = window?.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) {
            if ev.type == .leftMouseUp { break }
            let cur = convert(ev.locationInWindow, from: nil)
            let total = NSSize(width: cur.x - convert(e.locationInWindow, from: nil).x, height: cur.y - convert(e.locationInWindow, from: nil).y)
            if !moved && abs(total.width) + abs(total.height) < 2 { continue }
            moved = true
            a.bounds = convert(startViewRect.offsetBy(dx: total.width, dy: total.height), to: page)
            annotationsChanged(on: page)
            refreshOverlay()
            last = cur
        }
        _ = last
        if moved, a.bounds != old { onGeometry?(a, page, old, a.bounds) }
    }

    private func startResize(_ h: Handle, _ s: (annot: PDFAnnotation, page: PDFPage), _ e: NSEvent) {
        let a = s.annot, page = s.page
        let old = a.bounds
        let startView = convert(old, from: page)
        let startPt = convert(e.locationInWindow, from: nil)
        let keepRatio = a is ImageAnnotation
        let line = a.type == "Line" ? (a.startPoint, a.endPoint) : nil
        while let ev = window?.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) {
            if ev.type == .leftMouseUp { break }
            let cur = convert(ev.locationInWindow, from: nil)
            let dx = cur.x - startPt.x, dy = cur.y - startPt.y
            var r = startView
            switch h {
            case .tl: r.origin.x += dx; r.size.width -= dx; r.origin.y += dy; r.size.height -= dy
            case .t: r.origin.y += dy; r.size.height -= dy
            case .tr: r.size.width += dx; r.origin.y += dy; r.size.height -= dy
            case .r: r.size.width += dx
            case .br: r.size.width += dx; r.size.height += dy
            case .b: r.size.height += dy
            case .bl: r.origin.x += dx; r.size.width -= dx; r.size.height += dy
            case .l: r.origin.x += dx; r.size.width -= dx
            }
            if keepRatio, startView.width > 0, startView.height > 0, [.tl, .tr, .br, .bl].contains(h) {
                let ratio = startView.width / startView.height
                let nh = r.width / ratio
                if h == .tl || h == .tr { r.origin.y = startView.maxY - nh }
                r.size.height = nh
            }
            r.size.width = max(r.width, 14); r.size.height = max(r.height, 14)
            let nb = convert(r, to: page)
            if let line, old.width > 0, old.height > 0 {
                let sx = nb.width / old.width, sy = nb.height / old.height
                a.bounds = nb
                a.startPoint = NSPoint(x: line.0.x * sx, y: line.0.y * sy)
                a.endPoint = NSPoint(x: line.1.x * sx, y: line.1.y * sy)
            } else { a.bounds = nb }
            annotationsChanged(on: page)
            refreshOverlay()
        }
        if a.bounds != old { onGeometry?(a, page, old, a.bounds) }
    }

    // MARK: Texte en place

    private func placeText(_ e: NSEvent) {
        let pt = convert(e.locationInWindow, from: nil)
        guard let page = page(for: pt, nearest: true) else { return }
        let p = convert(pt, to: page)
        let a = PDFAnnotation(bounds: NSRect(x: p.x, y: p.y - 30, width: 240, height: 30), forType: .freeText, withProperties: nil)
        a.font = NSFont.systemFont(ofSize: 16)
        a.fontColor = NSColor(srgbRed: 0.1, green: 0.1, blue: 0.12, alpha: 1)
        a.color = .clear
        let border = PDFBorder(); border.lineWidth = 0; a.border = border
        a.contents = ""
        beginEditing(a, on: page, isNew: true)
    }

    func beginEditing(_ a: PDFAnnotation, on page: PDFPage, isNew: Bool) {
        commitEditing()
        let ed = InlineEditor(frame: convert(a.bounds, from: page))
        ed.isRichText = false; ed.drawsBackground = true
        ed.backgroundColor = NSColor.white.withAlphaComponent(0.9)
        ed.textColor = a.fontColor ?? .black
        ed.font = NSFont.systemFont(ofSize: (a.font?.pointSize ?? 16) * scaleFactor)
        ed.insertionPointColor = NSColor.controlAccentColor
        ed.textContainerInset = NSSize(width: 2, height: 2)
        ed.string = a.contents ?? ""
        ed.wantsLayer = true; ed.layer?.borderColor = NSColor.controlAccentColor.cgColor; ed.layer?.borderWidth = 1.5
        ed.isVerticallyResizable = true; ed.isHorizontallyResizable = false
        ed.textContainer?.widthTracksTextView = true
        ed.onCommit = { [weak self] in self?.commitEditing() }
        ed.delegate = self
        addSubview(ed)
        editor = ed
        editing = (a, page, isNew, a.contents ?? "", a.bounds)
        a.shouldDisplay = false
        annotationsChanged(on: page)
        window?.makeFirstResponder(ed)
    }

    private func fittedBounds(_ a: PDFAnnotation, text: String) -> NSRect {
        let font = a.font ?? NSFont.systemFont(ofSize: 16)
        let w = max(a.bounds.width - 6, 20)
        let h = (text as NSString).boundingRect(with: NSSize(width: w, height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin], attributes: [.font: font]).height
        let nh = max(ceil(h) + 8, font.pointSize + 10)
        return NSRect(x: a.bounds.minX, y: a.bounds.maxY - nh, width: a.bounds.width, height: nh)
    }

    func commitEditing() {
        guard let ed = editor, let ctx = editing else { return }
        editor = nil; editing = nil
        let text = ed.string
        ed.onCommit = nil
        ed.removeFromSuperview()
        ctx.a.shouldDisplay = true
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            if !ctx.isNew { annotationsChanged(on: ctx.page) }
            window?.makeFirstResponder(self)
            return
        }
        ctx.a.contents = text
        ctx.a.bounds = fittedBounds(ctx.a, text: text)
        if ctx.isNew { onAdd?(ctx.a, ctx.page) } else { onTextChanged?(ctx.a, ctx.page, ctx.oldText, ctx.oldBounds) }
        annotationsChanged(on: ctx.page)
        window?.makeFirstResponder(self)
        if ctx.isNew { select(ctx.a, on: ctx.page); finishPlacement() }
    }

    // MARK: Création

    private func markup(_ type: PDFAnnotationSubtype, _ color: NSColor) {
        guard let sel = currentSelection, let text = sel.string, !text.isEmpty else { return }
        let style: PDFMarkupType = type == .highlight ? .highlight : (type == .underline ? .underline : .strikeOut)
        for line in sel.selectionsByLine() {
            for page in line.pages {
                let b = line.bounds(for: page)
                guard b.width > 1 else { continue }
                let a = PDFAnnotation(bounds: b, forType: type, withProperties: nil)
                a.markupType = style
                a.color = type == .highlight ? color.withAlphaComponent(0.5) : color
                let w = b.width, h = b.height
                a.quadrilateralPoints = [NSValue(point: NSPoint(x: 0, y: h)), NSValue(point: NSPoint(x: w, y: h)),
                                         NSValue(point: NSPoint(x: 0, y: 0)), NSValue(point: NSPoint(x: w, y: 0))]
                a.contents = text.trimmingCharacters(in: .whitespacesAndNewlines)
                onAdd?(a, page)
            }
        }
        clearSelection()
    }

    private func place(_ e: NSEvent) {
        let pt = convert(e.locationInWindow, from: nil)
        guard let page = page(for: pt, nearest: true) else { return }
        let p = convert(pt, to: page)
        let a = PDFAnnotation(bounds: NSRect(x: p.x, y: p.y - 24, width: 24, height: 24), forType: .text, withProperties: nil)
        a.iconType = .note
        a.color = .systemYellow
        a.contents = ""
        onAdd?(a, page)
        onEdit?(a, page)
        finishPlacement()
    }

    /// Coche ✓ ou croix ✗ d'un clic (texte libre : reste modifiable, déplaçable, redimensionnable).
    private func placeMark(_ e: NSEvent) {
        let pt = convert(e.locationInWindow, from: nil)
        guard let page = page(for: pt, nearest: true) else { return }
        let p = convert(pt, to: page)
        let a = PDFAnnotation(bounds: NSRect(x: p.x - 16, y: p.y - 18, width: 32, height: 36), forType: .freeText, withProperties: nil)
        a.font = NSFont.systemFont(ofSize: 28, weight: .bold)
        a.fontColor = tool == .check ? NSColor(srgbRed: 0.1, green: 0.55, blue: 0.25, alpha: 1) : NSColor(srgbRed: 0.8, green: 0.15, blue: 0.15, alpha: 1)
        a.alignment = .center
        a.color = .clear
        let border = PDFBorder(); border.lineWidth = 0; a.border = border
        a.contents = tool == .check ? "✓" : "✗"
        onAdd?(a, page)
        select(a, on: page)
        finishPlacement()
    }

    /// Rectangle, ellipse, gomme blanche, flèche, stylo : tracé au glissé, aperçu en direct, annotation à la fin du geste.
    private func drawShape(_ e: NSEvent) {
        let start = convert(e.locationInWindow, from: nil)
        guard let page = page(for: start, nearest: true) else { return }
        let kind = tool
        var pts = [start]
        var cur = start
        overlay.previewKind = kind
        while let ev = window?.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) {
            if ev.type == .leftMouseUp { break }
            cur = convert(ev.locationInWindow, from: nil)
            if kind == .pen { pts.append(cur) }
            let rect = NSRect(x: min(start.x, cur.x), y: min(start.y, cur.y), width: abs(cur.x - start.x), height: abs(cur.y - start.y))
            let path = NSBezierPath()
            switch kind {
            case .rect, .whiteout: path.appendRect(rect)
            case .ellipse: path.appendOval(in: rect)
            case .arrow: path.move(to: start); path.line(to: cur)
            default: path.move(to: pts[0]); pts.dropFirst().forEach { path.line(to: $0) }
            }
            overlay.previewPath = path
            overlay.needsDisplay = true
        }
        overlay.previewPath = nil; overlay.previewKind = nil; overlay.needsDisplay = true
        let dist = hypot(cur.x - start.x, cur.y - start.y)
        guard dist > 3 else { return }
        let s = convert(start, to: page), c = convert(cur, to: page)
        let border = PDFBorder(); border.lineWidth = 2
        let a: PDFAnnotation
        switch kind {
        case .rect, .ellipse, .whiteout:
            let r = NSRect(x: min(s.x, c.x), y: min(s.y, c.y), width: max(abs(c.x - s.x), 6), height: max(abs(c.y - s.y), 6))
            a = PDFAnnotation(bounds: r, forType: kind == .ellipse ? .circle : .square, withProperties: nil)
            if kind == .whiteout { a.color = .white; a.interiorColor = .white; let b0 = PDFBorder(); b0.lineWidth = 0; a.border = b0 }
            else { a.color = .systemRed; a.border = border }
        case .arrow:
            let pad: CGFloat = 10
            let r = NSRect(x: min(s.x, c.x) - pad, y: min(s.y, c.y) - pad, width: abs(c.x - s.x) + 2 * pad, height: abs(c.y - s.y) + 2 * pad)
            a = PDFAnnotation(bounds: r, forType: .line, withProperties: nil)
            a.startPoint = NSPoint(x: s.x - r.minX, y: s.y - r.minY); a.endPoint = NSPoint(x: c.x - r.minX, y: c.y - r.minY)
            a.endLineStyle = .closedArrow
            a.color = .systemRed; a.border = border
        default:
            let pp = pts.map { convert($0, to: page) }
            let minX = pp.map(\.x).min()! - 4, minY = pp.map(\.y).min()! - 4
            let maxX = pp.map(\.x).max()! + 4, maxY = pp.map(\.y).max()! + 4
            let r = NSRect(x: minX, y: minY, width: max(maxX - minX, 8), height: max(maxY - minY, 8))
            a = PDFAnnotation(bounds: r, forType: .ink, withProperties: nil)
            let path = NSBezierPath(); path.move(to: NSPoint(x: pp[0].x - r.minX, y: pp[0].y - r.minY))
            pp.dropFirst().forEach { path.line(to: NSPoint(x: $0.x - r.minX, y: $0.y - r.minY)) }
            a.add(path)
            a.color = .systemBlue; a.border = border
        }
        onAdd?(a, page)
        if kind != .pen { select(a, on: page) }
        finishPlacement()
    }

    // MARK: Images et fichiers déposés

    func placeImage(_ image: NSImage, on page: PDFPage, centeredAt c: NSPoint? = nil) {
        let pb = page.bounds(for: .cropBox)
        var w = min(image.size.width, pb.width * 0.4)
        var h = w * image.size.height / max(image.size.width, 1)
        if h > pb.height * 0.6 { h = pb.height * 0.6; w = h * image.size.width / max(image.size.height, 1) }
        let center = c ?? NSPoint(x: pb.midX, y: pb.midY)
        var r = NSRect(x: center.x - w / 2, y: center.y - h / 2, width: w, height: h)
        r.origin.x = max(pb.minX, min(r.origin.x, pb.maxX - w)); r.origin.y = max(pb.minY, min(r.origin.y, pb.maxY - h))
        let a = ImageAnnotation(image: image, bounds: r)
        onAdd?(a, page)
        select(a, on: page)
    }

    private func droppedURLs(_ info: NSDraggingInfo) -> [URL] {
        let opts: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true,
                                                          .urlReadingContentsConformToTypes: [UTType.pdf.identifier, UTType.image.identifier]]
        return (info.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: opts) as? [URL]) ?? []
    }
    override func draggingEntered(_ s: NSDraggingInfo) -> NSDragOperation { droppedURLs(s).isEmpty ? super.draggingEntered(s) : .copy }
    override func draggingUpdated(_ s: NSDraggingInfo) -> NSDragOperation { droppedURLs(s).isEmpty ? super.draggingUpdated(s) : .copy }
    override func performDragOperation(_ s: NSDraggingInfo) -> Bool {
        let urls = droppedURLs(s)
        guard !urls.isEmpty else { return super.performDragOperation(s) }
        let vp = convert(s.draggingLocation, from: nil)
        guard let page = page(for: vp, nearest: true) else { return false }
        onDropFiles?(urls, page, convert(vp, to: page), vp)
        return true
    }

    // MARK: Défilement : en mode « page entière », la molette / le trackpad tourne les pages

    private var wheelAcc: CGFloat = 0
    private var wheelLockUntil = Date.distantPast
    override func scrollWheel(with e: NSEvent) {
        guard displayMode == .singlePage, fitsPage else { return super.scrollWheel(with: e) }
        if e.phase == .began { wheelAcc = 0 }
        guard Date() >= wheelLockUntil else { return }
        wheelAcc += e.scrollingDeltaY * (e.hasPreciseScrollingDeltas ? 1 : 10)
        if wheelAcc <= -40 { goToNextPage(nil); wheelAcc = 0; wheelLockUntil = Date().addingTimeInterval(0.35) }
        else if wheelAcc >= 40 {
            if canGoToPreviousPage { goToPreviousPage(nil) } else { onTopOverscroll?() }   // balayage vers le bas sur la 1re page : la barre d'outils descend
            wheelAcc = 0; wheelLockUntil = Date().addingTimeInterval(0.35)
        }
    }
}

extension ReaderPDFView: NSTextViewDelegate {
    func textDidChange(_ n: Notification) {
        guard let ed = editor, let ctx = editing else { return }
        let w = ed.frame.width
        let needed = ed.layoutManager.map { lm -> CGFloat in lm.ensureLayout(for: ed.textContainer!); return lm.usedRect(for: ed.textContainer!).height + 6 } ?? ed.frame.height
        var f = ed.frame
        let grow = max(needed, ctx.a.bounds.height * scaleFactor) - f.height
        if abs(grow) > 0.5 { f.size.height += grow; if !isFlipped { f.origin.y -= grow }; f.size.width = w; ed.frame = f }
    }
}
