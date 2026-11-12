// mPDF — fenêtre de lecture « liseuse » : le PDF occupe toute la fenêtre, sans bord ; la barre d'outils et les panneaux
// (pages, notes) sont des calques qui glissent à la demande (survol du haut de la fenêtre, balayage vers le bas, menus).
import AppKit
import PDFKit

private final class NotesTable: NSTableView {
    var onDelete: (() -> Void)?
    override func keyDown(with e: NSEvent) {
        if e.keyCode == 51 || e.keyCode == 117 { onDelete?() } else { super.keyDown(with: e) }
    }
}

private struct NoteRow { let annot: PDFAnnotation; let page: PDFPage; let pageIndex: Int }

/// Panneau calque qui glisse depuis un bord de la fenêtre, par-dessus le PDF (la page ne bouge pas).
@MainActor
private final class Drawer {
    let view: NSVisualEffectView = {
        let v = NSVisualEffectView(); v.material = .sidebar; v.blendingMode = .withinWindow; v.state = .active
        v.translatesAutoresizingMaskIntoConstraints = false; return v
    }()
    let width: CGFloat
    private(set) var visible = false
    private var left: NSLayoutConstraint!, right: NSLayoutConstraint!
    private(set) var onRight = false
    init(width: CGFloat) { self.width = width }

    func install(in root: NSView) {
        root.addSubview(view)
        left = view.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: -width)
        right = view.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: width)
        NSLayoutConstraint.activate([view.topAnchor.constraint(equalTo: root.topAnchor), view.bottomAnchor.constraint(equalTo: root.bottomAnchor),
                                     view.widthAnchor.constraint(equalToConstant: width), left])
    }
    func place(onRight r: Bool) {
        onRight = r
        left.isActive = false; right.isActive = false
        (r ? right : left)!.isActive = true
        left.constant = visible ? 0 : -width; right.constant = visible ? 0 : width
    }
    func set(_ v: Bool, animated: Bool = true) {
        visible = v
        let c = onRight ? right! : left!
        let target = v ? 0 : (onRight ? width : -width)
        if animated {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.24; ctx.timingFunction = CAMediaTimingFunction(name: .easeOut); ctx.allowsImplicitAnimation = true
                c.animator().constant = target
            }
        } else { c.constant = target }
    }
}

@MainActor
final class ReaderWC: NSWindowController, NSWindowDelegate, NSTableViewDataSource, NSTableViewDelegate,
                      NSOutlineViewDataSource, NSOutlineViewDelegate, PDFDocumentDelegate, NSMenuItemValidation {
    let doc: PDFDoc
    let pdfView = ReaderPDFView()
    private let pages = PagesPanel()
    private let pagesDrawer = Drawer(width: 232)
    private let notesDrawer = Drawer(width: 292)
    private var sideLines: [FlatView] = [], notesLines: [FlatView] = []
    private let outlineView = NSOutlineView()
    private let outlineScroll = NSScrollView()
    private let emptyOutline = NSTextField(wrappingLabelWithString: L.t("side.empty"))
    private let notesTable = NotesTable()
    private let notesEmpty = NSTextField(wrappingLabelWithString: L.t("notes.empty"))
    private var rows: [NoteRow] = []
    private var matches: [PDFSelection] = []
    private var matchIndex = 0
    private let searchField = SearchField(placeholder: L.t("tb.search"))
    private var toolButtons: [BarButton] = []
    private var thumbsTab: BarButton!, outlineTab: BarButton!
    private var pagesBtn: BarButton!, notesBtn: BarButton!, displayBtn: BarButton!
    private var barRow: NSStackView!
    private var imageBtn: BarButton!, moreBtn: BarButton!
    static let directTools: [Tool] = [.select, .hand, .highlight, .text, .pen, .check]
    private var bar: NSVisualEffectView!, barLine: FlatView!
    private let hud = PageHUD()
    private var barTop: NSLayoutConstraint!
    private(set) var chromeVisible = false
    private var hideWork: DispatchWorkItem?
    private var monitor: Any?
    private var statusExtra: String?
    private var observers: [NSObjectProtocol] = []
    nonisolated static let sideKey = "pagesPanelRight"
    static var panelOnRight: Bool { get { UserDefaults.standard.bool(forKey: sideKey) } set { UserDefaults.standard.set(newValue, forKey: sideKey) } }
    private let barH = Socle.M.sizeBar

    init(doc: PDFDoc) {
        self.doc = doc
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 760, height: 900),
                         styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        w.isReleasedWhenClosed = false
        w.isRestorable = false   // la fenêtre épouse toujours le format de la page ; pas de taille restaurée
        w.minSize = NSSize(width: 480, height: 360)
        w.titlebarAppearsTransparent = true
        w.titleVisibility = .hidden
        w.backgroundColor = S.bgSunken
        w.acceptsMouseMovedEvents = true
        super.init(window: w)
        w.delegate = self
        setup()
    }
    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Construction (design Socle : plat, aplats, filets de 1 px)

    /// Taille initiale : la fenêtre épouse le format de la première page, pour que la page remplisse tout, sans bord.
    private func fitWindowToFirstPage() {
        guard let w = window, let page = doc.pdf?.page(at: 0) else { return }
        let b = page.bounds(for: .cropBox)
        let (pw, ph) = page.rotation % 180 == 0 ? (b.width, b.height) : (b.height, b.width)
        guard pw > 0, ph > 0 else { return }
        // Écran où se trouve le pointeur (règle Socle), zone utile (hors barre des menus et Dock)
        let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main ?? NSScreen.screens[0]
        let scr = screen.visibleFrame
        var h = min(scr.height * 0.94, 1200), wd = h * pw / ph
        if wd > scr.width * 0.94 { wd = scr.width * 0.94; h = wd * ph / pw }
        w.setContentSize(NSSize(width: max(wd.rounded(), 480), height: max(h.rounded(), 360)))
        var f = w.frame
        f.origin = NSPoint(x: scr.midX - f.width / 2, y: scr.midY - f.height / 2)
        let n = NSDocumentController.shared.documents.count
        if n > 1 { f.origin.x += 28 * CGFloat(n - 1); f.origin.y -= 28 * CGFloat(n - 1) }
        w.setFrame(f, display: false)
    }

    private func setup() {
        guard let window else { return }
        // PDF : pleine fenêtre, une page ajustée, sans marge entre page et bord
        pdfView.document = doc.pdf
        pdfView.autoScales = true
        pdfView.displayMode = .singlePage
        pdfView.displayDirection = .vertical
        pdfView.displaysPageBreaks = false
        pdfView.pageBreakMargins = NSEdgeInsetsZero
        pdfView.displayBox = .cropBox
        pdfView.interpolationQuality = .high
        pdfView.backgroundColor = S.bgSunken
        pdfView.minScaleFactor = 0.1
        pdfView.maxScaleFactor = 16
        pdfView.onAdd = { [weak self] a, p in self?.addAnnotation(a, to: p) }
        pdfView.onEdit = { [weak self] a, p in self?.editText(a, page: p) }
        pdfView.onTextChanged = { [weak self] a, p, oldText, oldBounds in self?.registerEdit(a, p, oldText, oldBounds) }
        pdfView.onGeometry = { [weak self] a, p, old, new in self?.registerGeometry(a, p, old, new) }
        pdfView.onDeleteSelected = { [weak self] a, p in self?.removeAnnotation(a, from: p) }
        pdfView.onToolChange = { [weak self] t in self?.updateToolButtons(t) }
        pdfView.onDropFiles = { [weak self] urls, page, pp, vp in self?.handleDrop(urls, page: page, pagePoint: pp, viewPoint: vp) }
        pdfView.onLayout = { [weak self] in self?.applyFit() }
        pdfView.onTopOverscroll = { [weak self] in self?.setChrome(true) }
        doc.pdf?.delegate = self

        let root = NSView()
        pdfView.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(pdfView)
        NSLayoutConstraint.activate([pdfView.topAnchor.constraint(equalTo: root.topAnchor), pdfView.bottomAnchor.constraint(equalTo: root.bottomAnchor),
                                     pdfView.leadingAnchor.constraint(equalTo: root.leadingAnchor), pdfView.trailingAnchor.constraint(equalTo: root.trailingAnchor)])
        let m = Socle.M.space3
        let top = barH + m

        // Panneau des pages : miniatures / sommaire
        pages.document = doc.pdf
        pages.onSelect = { [weak self] i in if let p = self?.pdfView.document?.page(at: i) { self?.pdfView.go(to: p) } }
        pages.onInsert = { [weak self] urls, i in self?.insertPages(from: urls, at: i) }
        pages.onMove = { [weak self] from, to in self?.movePage(from: from, to: to) }
        pages.onAction = { [weak self] a, row in self?.pageAction(a, row: row) }
        pages.onDelete = { [weak self] i in if let p = self?.pdfView.document?.page(at: i) { self?.removePages([p]) } }
        thumbsTab = BarButton(title: L.t("side.thumbs"), target: self, action: #selector(sideChanged(_:)))
        outlineTab = BarButton(title: L.t("side.outline"), target: self, action: #selector(sideChanged(_:)))
        thumbsTab.selectedState = true
        let tabs = NSStackView(views: [thumbsTab, outlineTab]); tabs.spacing = 2; tabs.distribution = .fillEqually
        tabs.translatesAutoresizingMaskIntoConstraints = false
        let sideView = pagesDrawer.view
        sideLines = [FlatView.hairline(vertical: true), FlatView.hairline(vertical: true)]
        pagesDrawer.install(in: root)
        for v in [tabs, pages.scroll, outlineScroll, emptyOutline] + sideLines as [NSView] { v.translatesAutoresizingMaskIntoConstraints = false; sideView.addSubview(v) }
        let col = NSTableColumn(identifier: .init("o")); col.resizingMask = .autoresizingMask
        outlineView.addTableColumn(col); outlineView.outlineTableColumn = col
        outlineView.headerView = nil; outlineView.dataSource = self; outlineView.delegate = self
        outlineView.style = .plain; outlineView.backgroundColor = .clear; outlineView.rowHeight = 26
        outlineScroll.documentView = outlineView; outlineScroll.hasVerticalScroller = true; outlineScroll.drawsBackground = false
        emptyOutline.alignment = .center; emptyOutline.textColor = S.textMuted; emptyOutline.font = S.font(12)
        outlineScroll.isHidden = true; emptyOutline.isHidden = true
        NSLayoutConstraint.activate([
            tabs.topAnchor.constraint(equalTo: sideView.topAnchor, constant: top),
            tabs.leadingAnchor.constraint(equalTo: sideView.leadingAnchor, constant: m + 1),
            tabs.trailingAnchor.constraint(equalTo: sideView.trailingAnchor, constant: -m - 1),
            pages.scroll.topAnchor.constraint(equalTo: tabs.bottomAnchor, constant: m),
            outlineScroll.topAnchor.constraint(equalTo: tabs.bottomAnchor, constant: m),
            emptyOutline.topAnchor.constraint(equalTo: tabs.bottomAnchor, constant: 24),
            emptyOutline.leadingAnchor.constraint(equalTo: sideView.leadingAnchor, constant: m + 1),
            emptyOutline.trailingAnchor.constraint(equalTo: sideView.trailingAnchor, constant: -m - 1),
            sideLines[0].topAnchor.constraint(equalTo: sideView.topAnchor), sideLines[0].bottomAnchor.constraint(equalTo: sideView.bottomAnchor), sideLines[0].trailingAnchor.constraint(equalTo: sideView.trailingAnchor),
            sideLines[1].topAnchor.constraint(equalTo: sideView.topAnchor), sideLines[1].bottomAnchor.constraint(equalTo: sideView.bottomAnchor), sideLines[1].leadingAnchor.constraint(equalTo: sideView.leadingAnchor),
        ])
        for v in [pages.scroll, outlineScroll] as [NSView] {
            v.leadingAnchor.constraint(equalTo: sideView.leadingAnchor, constant: 1).isActive = true
            v.trailingAnchor.constraint(equalTo: sideView.trailingAnchor, constant: -1).isActive = true
            v.bottomAnchor.constraint(equalTo: sideView.bottomAnchor).isActive = true
        }

        // Panneau des notes
        let nc = NSTableColumn(identifier: .init("n")); nc.resizingMask = .autoresizingMask
        notesTable.addTableColumn(nc); notesTable.headerView = nil
        notesTable.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        notesTable.dataSource = self; notesTable.delegate = self
        notesTable.rowHeight = 50; notesTable.style = .plain; notesTable.backgroundColor = .clear
        notesTable.target = self; notesTable.doubleAction = #selector(editSelectedNote)
        notesTable.onDelete = { [weak self] in self?.deleteSelectedNote() }
        let menu = NSMenu()
        menu.addItem(withTitle: L.t("notes.edit"), action: #selector(editSelectedNote), keyEquivalent: "").target = self
        menu.addItem(withTitle: L.t("notes.delete"), action: #selector(deleteSelectedNote), keyEquivalent: "").target = self
        notesTable.menu = menu
        let ns = NSScrollView(); ns.documentView = notesTable; ns.hasVerticalScroller = true; ns.drawsBackground = false
        let notesView = notesDrawer.view
        notesLines = [FlatView.hairline(vertical: true), FlatView.hairline(vertical: true)]
        notesDrawer.install(in: root)
        let title = NSTextField(labelWithString: "")
        title.attributedStringValue = NSAttributedString(string: L.t("notes.title"), attributes: [.font: S.font(14, .bold), .foregroundColor: S.textStrong, .kern: 0.35])
        for v in [title, ns, notesEmpty] + notesLines as [NSView] { v.translatesAutoresizingMaskIntoConstraints = false; notesView.addSubview(v) }
        notesEmpty.alignment = .center; notesEmpty.textColor = S.textMuted; notesEmpty.font = S.font(12)
        NSLayoutConstraint.activate([
            title.topAnchor.constraint(equalTo: notesView.topAnchor, constant: top + 4), title.leadingAnchor.constraint(equalTo: notesView.leadingAnchor, constant: m + 1),
            ns.topAnchor.constraint(equalTo: title.bottomAnchor, constant: m), ns.bottomAnchor.constraint(equalTo: notesView.bottomAnchor),
            ns.leadingAnchor.constraint(equalTo: notesView.leadingAnchor, constant: 1), ns.trailingAnchor.constraint(equalTo: notesView.trailingAnchor, constant: -1),
            notesEmpty.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 24),
            notesEmpty.leadingAnchor.constraint(equalTo: notesView.leadingAnchor, constant: m + 1), notesEmpty.trailingAnchor.constraint(equalTo: notesView.trailingAnchor, constant: -m),
            notesLines[0].topAnchor.constraint(equalTo: notesView.topAnchor), notesLines[0].bottomAnchor.constraint(equalTo: notesView.bottomAnchor), notesLines[0].leadingAnchor.constraint(equalTo: notesView.leadingAnchor),
            notesLines[1].topAnchor.constraint(equalTo: notesView.topAnchor), notesLines[1].bottomAnchor.constraint(equalTo: notesView.bottomAnchor), notesLines[1].trailingAnchor.constraint(equalTo: notesView.trailingAnchor),
        ])

        // Barre d'en-tête (size-bar) : calque au-dessus de tout, masqué par défaut
        bar = buildBar()
        barLine = FlatView.hairline(vertical: false)
        for v in [hud, bar!, barLine!] { root.addSubview(v) }
        NSLayoutConstraint.activate([hud.centerXAnchor.constraint(equalTo: root.centerXAnchor), hud.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -22)])
        barTop = bar.topAnchor.constraint(equalTo: root.topAnchor, constant: -barH - 1)
        NSLayoutConstraint.activate([
            barTop, bar.leadingAnchor.constraint(equalTo: root.leadingAnchor), bar.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            bar.heightAnchor.constraint(equalToConstant: barH),
            barLine.topAnchor.constraint(equalTo: bar.bottomAnchor), barLine.leadingAnchor.constraint(equalTo: root.leadingAnchor), barLine.trailingAnchor.constraint(equalTo: root.trailingAnchor),
        ])
        let rootVC = NSViewController(); rootVC.view = root
        window.contentViewController = rootVC
        applySide()
        fitWindowToFirstPage()
        updateAspectLock()
        window.initialFirstResponder = pdfView   // le focus est au document (flèches, espace), pas dans la recherche

        let nc2 = NotificationCenter.default
        observers.append(nc2.addObserver(forName: .PDFViewPageChanged, object: pdfView, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.pageChanged() } })
        observers.append(nc2.addObserver(forName: .PDFViewScaleChanged, object: pdfView, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.savePosition() } })
        observers.append(nc2.addObserver(forName: .mpdfPanelSide, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.applySide() } })
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved]) { [weak self] e in
            MainActor.assumeIsolated { self?.handleMouseMoved(e) }
            return e
        }
        reloadOutline()
        DispatchQueue.main.async { [weak self] in
            self?.restorePosition(); self?.pages.reload(); self?.pageChanged()
            self?.window?.makeFirstResponder(self?.pdfView)
            self?.setTrafficLights(visible: false, animated: false)
            // Au premier affichage, la barre se montre un instant puis se range : on apprend ainsi où elle se cache.
            self?.setChrome(true)
            self?.scheduleHide(after: 2.4)
        }
    }

    private func buildBar() -> NSVisualEffectView {
        let bar = NSVisualEffectView()
        bar.material = .headerView; bar.blendingMode = .withinWindow; bar.state = .active
        bar.translatesAutoresizingMaskIntoConstraints = false
        func group(_ b: [BarButton]) -> NSStackView { let g = NSStackView(views: b); g.spacing = 2; g.translatesAutoresizingMaskIntoConstraints = false; return g }
        pagesBtn = BarButton(symbol: "sidebar.left", tip: L.t("menu.sidebar"), target: self, action: #selector(toggleSidebar))
        let zoom = group([
            BarButton(symbol: "minus.magnifyingglass", tip: L.t("menu.zoomOut"), target: self, action: #selector(zoomOut(_:))),
            BarButton(symbol: "plus.magnifyingglass", tip: L.t("menu.zoomIn"), target: self, action: #selector(zoomIn(_:))),
            BarButton(symbol: "arrow.left.and.right", tip: L.t("menu.fitWidth"), target: self, action: #selector(fitWidth(_:))),
            BarButton(symbol: "arrow.up.left.and.down.right.magnifyingglass", tip: L.t("menu.fitPage"), target: self, action: #selector(fitPage(_:)))])
        toolButtons = Self.directTools.map { t in
            let b = BarButton(symbol: t.symbol, tip: L.t(t.key), target: self, action: #selector(toolClicked(_:))); b.tag = t.rawValue; return b }
        toolButtons[0].selectedState = true
        imageBtn = BarButton(symbol: "photo", tip: L.t("menu.insertImage"), target: self, action: #selector(insertImage(_:)))
        moreBtn = BarButton(symbol: "ellipsis", tip: L.t("tb.more"), target: self, action: #selector(showToolsMenu(_:)))
        displayBtn = BarButton(symbol: "rectangle.grid.1x2", tip: L.t("tb.display"), target: self, action: #selector(showDisplayMenu(_:)))
        notesBtn = BarButton(symbol: "sidebar.right", tip: L.t("menu.notesPanel"), target: self, action: #selector(toggleNotes))

        searchField.target = self; searchField.action = #selector(search(_:))
        searchField.widthAnchor.constraint(equalToConstant: 180).isActive = true
        let tools = group(toolButtons + [imageBtn, moreBtn])

        let row = NSStackView(views: [pagesBtn, zoom, tools, displayBtn, NSView(), searchField, notesBtn])
        row.spacing = Socle.M.space4
        row.detachesHiddenViews = true
        // Quand la fenêtre est étroite, les éléments se retirent d'eux-mêmes, du moins important au plus important.
        for (v, pr) in [(pagesBtn!, 1000), (notesBtn!, 1000), (searchField, 800), (tools, 700), (zoom, 600), (displayBtn!, 500)] as [(NSView, Float)] {
            row.setVisibilityPriority(NSStackView.VisibilityPriority(rawValue: pr), for: v)
        }
        let flex = row.arrangedSubviews[4]; flex.setContentHuggingPriority(.init(1), for: .horizontal); flex.setContentCompressionResistancePriority(.init(1), for: .horizontal)
        row.setVisibilityPriority(NSStackView.VisibilityPriority(rawValue: 100), for: flex)
        barRow = row
        row.translatesAutoresizingMaskIntoConstraints = false
        bar.addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: bar.leadingAnchor, constant: 84),
            row.trailingAnchor.constraint(equalTo: bar.trailingAnchor, constant: -Socle.M.space3),
            row.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
        ])
        return bar
    }

    // MARK: - Barre d'outils et panneaux à la demande

    /// Affiche ou range la barre d'outils (glissement depuis le haut) ; les boutons de fenêtre suivent.
    func setChrome(_ v: Bool) {
        hideWork?.cancel()
        guard v != chromeVisible else { return }
        chromeVisible = v
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = v ? 0.30 : 0.26; ctx.timingFunction = CAMediaTimingFunction(name: v ? .easeOut : .easeIn); ctx.allowsImplicitAnimation = true
            barTop.animator().constant = v ? 0 : -barH - 1
            barLine.animator().alphaValue = v ? 1 : 0
        }
        setTrafficLights(visible: v, animated: true)
    }
    @objc func toggleChrome(_ s: Any?) { setChrome(!chromeVisible) }

    private func setTrafficLights(visible: Bool, animated: Bool) {
        guard let w = window else { return }
        for t in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            guard let b = w.standardWindowButton(t) else { continue }
            if animated { NSAnimationContext.runAnimationGroup { $0.duration = 0.2; b.animator().alphaValue = visible ? 1 : 0 } } else { b.alphaValue = visible ? 1 : 0 }
        }
        alignTrafficLights()
    }

    private func scheduleHide(after t: TimeInterval) {
        hideWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.chromeVisible else { return }
            // Pas de rangement pendant une saisie dans la recherche
            if let ed = self.searchField.currentEditor(), self.window?.firstResponder === ed { return }
            self.setChrome(false)
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + t, execute: work)
    }

    private func handleMouseMoved(_ e: NSEvent) {
        guard let w = window, e.window === w, let cv = w.contentView else { return }
        let fromTop = cv.bounds.height - e.locationInWindow.y
        if fromTop <= 44 { if !chromeVisible { setChrome(true) } else { hideWork?.cancel() } }
        else if chromeVisible && fromTop > barH + 8 { scheduleHide(after: 1.1) }
    }

    @objc func toggleSidebar() {
        notesDrawer.set(false)
        pagesDrawer.set(!pagesDrawer.visible)
        if pagesDrawer.visible { pages.select(page: pdfView.document.flatMap { d in pdfView.currentPage.map { d.index(for: $0) } } ?? 0) }
    }
    @objc func toggleNotes() {
        pagesDrawer.set(false)
        notesDrawer.set(!notesDrawer.visible)
        if notesDrawer.visible { reloadNotes() }
    }
    @objc func setPanelSide(_ m: NSMenuItem) {
        Self.panelOnRight = m.tag == 1
        NotificationCenter.default.post(name: .mpdfPanelSide, object: nil)
    }

    /// Place le panneau des pages à gauche ou à droite (préférence commune) ; les notes prennent l'autre côté.
    private func applySide() {
        let right = Self.panelOnRight
        pagesDrawer.place(onRight: right); notesDrawer.place(onRight: !right)
        sideLines[0].isHidden = right; sideLines[1].isHidden = !right
        notesLines[0].isHidden = !right; notesLines[1].isHidden = right
        pagesBtn.setSymbol(right ? "sidebar.right" : "sidebar.left"); notesBtn.setSymbol(right ? "sidebar.left" : "sidebar.right")
        guard let row = barRow else { return }
        for b in [pagesBtn!, notesBtn!] { row.removeArrangedSubview(b); b.removeFromSuperview() }
        if right { row.insertArrangedSubview(notesBtn, at: 0); row.addArrangedSubview(pagesBtn) }
        else { row.insertArrangedSubview(pagesBtn, at: 0); row.addArrangedSubview(notesBtn) }
        for b in [pagesBtn!, notesBtn!] { row.setVisibilityPriority(.mustHold, for: b) }
    }

    @objc private func toolClicked(_ b: BarButton) { setTool(Tool(rawValue: b.tag) ?? .select) }
    @objc private func sideChanged(_ b: BarButton) {
        let thumbsOn = b === thumbsTab
        thumbsTab.selectedState = thumbsOn; outlineTab.selectedState = !thumbsOn
        pages.scroll.isHidden = !thumbsOn
        outlineScroll.isHidden = thumbsOn || pdfView.document?.outlineRoot == nil
        emptyOutline.isHidden = thumbsOn || pdfView.document?.outlineRoot != nil
    }
    /// Menu d'affichage : modes de page et côté du panneau des pages.
    @objc private func showDisplayMenu(_ b: BarButton) {
        let menu = NSMenu()
        for (i, k) in ["menu.single", "menu.continuous", "menu.twoUp", "menu.twoUpContinuous"].enumerated() {
            let it = NSMenuItem(title: L.t(k), action: #selector(selectDisplay(_:)), keyEquivalent: ""); it.tag = i; it.target = self; menu.addItem(it)
        }
        menu.addItem(.separator())
        for (i, k) in ["menu.panelLeft", "menu.panelRight"].enumerated() {
            let it = NSMenuItem(title: L.t(k), action: #selector(setPanelSide(_:)), keyEquivalent: ""); it.tag = i; it.target = self; menu.addItem(it)
        }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: b.isFlipped ? b.bounds.maxY + 4 : -4), in: b)
    }

    // MARK: - Pages : ajout (PDF, images), déplacement, suppression, avec annuler/rétablir

    func insertPages(from urls: [URL], at index: Int) {
        guard let d = pdfView.document else { return }
        var pos = max(0, min(index, d.pageCount))
        var inserted: [PDFPage] = []
        for u in urls {
            if u.pathExtension.lowercased() == "pdf" {
                guard let src = PDFDocument(url: u), !src.isLocked else { continue }
                for i in 0..<src.pageCount {
                    if let p = src.page(at: i)?.copy() as? PDFPage { d.insert(p, at: pos); pos += 1; inserted.append(p) }
                }
            } else if let img = NSImage(contentsOf: u), let p = PDFPage(image: img) {
                d.insert(p, at: pos); pos += 1; inserted.append(p)
            }
        }
        guard let first = inserted.first else { return }
        doc.undoManager?.registerUndo(withTarget: self) { $0.removePages(inserted) }
        pagesChanged(goTo: first)
    }

    func removePages(_ list: [PDFPage]) {
        guard let d = pdfView.document else { return }
        let items = list.compactMap { p -> (Int, PDFPage)? in let i = d.index(for: p); return i >= 0 && i < d.pageCount ? (i, p) : nil }.sorted { $0.0 < $1.0 }
        guard !items.isEmpty, items.count < d.pageCount else { return }
        for (i, _) in items.reversed() { d.removePage(at: i) }
        doc.undoManager?.registerUndo(withTarget: self) { $0.reinsert(items) }
        pagesChanged(goTo: d.page(at: min(items[0].0, d.pageCount - 1)))
    }
    private func reinsert(_ items: [(Int, PDFPage)]) {
        guard let d = pdfView.document else { return }
        for (i, p) in items { d.insert(p, at: min(i, d.pageCount)) }
        doc.undoManager?.registerUndo(withTarget: self) { $0.removePages(items.map { $0.1 }) }
        pagesChanged(goTo: items.first?.1)
    }

    func movePage(from: Int, to: Int) {
        guard let d = pdfView.document, let p = d.page(at: from) else { return }
        let dest = to > from ? to - 1 : to
        guard dest != from, dest >= 0, dest < d.pageCount else { return }
        d.removePage(at: from); d.insert(p, at: dest)
        doc.undoManager?.registerUndo(withTarget: self) { $0.movePage(from: dest, to: from > dest ? from + 1 : from) }
        pagesChanged(goTo: p)
    }

    private func pagesChanged(goTo page: PDFPage?) {
        pdfView.layoutDocumentView()
        pages.reload()
        notesChanged()
        if let page { pdfView.go(to: page); if let d = pdfView.document { pages.select(page: d.index(for: page)) } }
        updateTitle()
    }
    /// Nom du fichier et page, en pastille discrète en bas de la fenêtre (elle s'efface seule).
    private func updateTitle() {
        guard let d = pdfView.document, let p = pdfView.currentPage else { return }
        let name = doc.fileURL?.lastPathComponent ?? doc.displayName ?? ""
        let detail = statusExtra ?? L.t("page.of", d.index(for: p) + 1, d.pageCount)
        hud.show(name: name, detail: detail)
    }

    // MARK: - Ajouts : images, PDF, pages vierges, dépôt sur la page

    private var currentIndex: Int { pdfView.document.flatMap { d in pdfView.currentPage.map { d.index(for: $0) } } ?? 0 }

    @objc func insertImage(_ s: Any?) {
        guard let window else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]; panel.allowsMultipleSelection = true; panel.canChooseDirectories = false
        panel.beginSheetModal(for: window) { [weak self] r in
            guard r == .OK, let self, let page = self.pdfView.currentPage else { return }
            for u in panel.urls { if let img = NSImage(contentsOf: u) { self.pdfView.placeImage(img, on: page) } }
        }
    }
    @objc func insertPDFPages(_ s: Any?) {
        guard let window else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.pdf, .image]; panel.allowsMultipleSelection = true; panel.canChooseDirectories = false
        panel.beginSheetModal(for: window) { [weak self] r in
            guard r == .OK, let self else { return }
            self.insertPages(from: panel.urls, at: self.currentIndex + 1)
        }
    }
    @objc func insertBlankPage(_ s: Any?) { insertBlank(after: currentIndex) }
    @objc func duplicateCurrentPage(_ s: Any?) { duplicatePage(at: currentIndex) }
    @objc func deleteCurrentPage(_ s: Any?) { if let p = pdfView.currentPage { removePages([p]) } }

    func insertBlank(after i: Int) {
        guard let d = pdfView.document, let ref = d.page(at: i) else { return }
        let p = PDFPage()
        p.setBounds(ref.bounds(for: .mediaBox), for: .mediaBox); p.setBounds(ref.bounds(for: .cropBox), for: .cropBox)
        d.insert(p, at: i + 1)
        doc.undoManager?.registerUndo(withTarget: self) { $0.removePages([p]) }
        pagesChanged(goTo: p)
    }
    func duplicatePage(at i: Int) {
        guard let d = pdfView.document, let c = d.page(at: i)?.copy() as? PDFPage else { return }
        d.insert(c, at: i + 1)
        doc.undoManager?.registerUndo(withTarget: self) { $0.removePages([c]) }
        pagesChanged(goTo: c)
    }
    func rotatePage(at i: Int, by deg: Int) {
        guard let p = pdfView.document?.page(at: i) else { return }
        p.rotation = (p.rotation + deg + 360) % 360
        doc.undoManager?.registerUndo(withTarget: self) { $0.rotatePage(at: i, by: -deg) }
        pagesChanged(goTo: p)
    }
    func pageAction(_ a: PagesPanel.Action, row: Int) {
        guard let d = pdfView.document, let p = d.page(at: row) else { return }
        switch a {
        case .duplicate: duplicatePage(at: row)
        case .blankAfter: insertBlank(after: row)
        case .delete: removePages([p])
        case .rotateLeft: rotatePage(at: row, by: -90)
        case .rotateRight: rotatePage(at: row, by: 90)
        case .insertFile: pdfView.go(to: p); insertPDFPages(nil)
        }
    }

    private final class MenuAction: NSObject {
        let block: () -> Void
        init(_ b: @escaping () -> Void) { block = b }
        @objc func run() { block() }
    }

    /// Fichier(s) déposé(s) sur la page : un petit menu demande où les placer (avant / après la page, ou ici pour une image).
    private func handleDrop(_ urls: [URL], page: PDFPage, pagePoint: NSPoint, viewPoint: NSPoint) {
        guard let d = pdfView.document else { return }
        let idx = d.index(for: page)
        let pdfs = urls.filter { $0.pathExtension.lowercased() == "pdf" }
        let imgs = urls.filter { !pdfs.contains($0) }
        let menu = NSMenu()
        var keep: [MenuAction] = []
        func add(_ title: String, _ symbol: String, _ block: @escaping () -> Void) {
            let a = MenuAction(block); keep.append(a)
            let it = NSMenuItem(title: title, action: #selector(MenuAction.run), keyEquivalent: ""); it.target = a; it.representedObject = a
            it.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
            menu.addItem(it)
        }
        if !imgs.isEmpty {
            add(L.t("drop.placeHere"), "photo") { [weak self] in
                for (k, u) in imgs.enumerated() {
                    if let img = NSImage(contentsOf: u) { self?.pdfView.placeImage(img, on: page, centeredAt: NSPoint(x: pagePoint.x + CGFloat(k) * 24, y: pagePoint.y - CGFloat(k) * 24)) }
                }
            }
        }
        if !pdfs.isEmpty || !imgs.isEmpty {
            if !menu.items.isEmpty { menu.addItem(.separator()) }
            let all = pdfs.isEmpty ? imgs : urls
            add(L.t(pdfs.isEmpty ? "drop.newPageBefore" : "drop.before", idx + 1), "arrow.up.doc") { [weak self] in self?.insertPages(from: all, at: idx) }
            add(L.t(pdfs.isEmpty ? "drop.newPageAfter" : "drop.after", idx + 1), "arrow.down.doc") { [weak self] in self?.insertPages(from: all, at: idx + 1) }
        }
        objc_setAssociatedObject(menu, Unmanaged.passUnretained(menu).toOpaque(), keep, .OBJC_ASSOCIATION_RETAIN)
        menu.popUp(positioning: nil, at: viewPoint, in: pdfView)
    }

    /// À l'enregistrement, les images posées sont figées dans la page (contenu vectoriel conservé, texte sélectionnable).
    func flattenImages() {
        guard let d = pdfView.document else { return }
        pdfView.commitEditing()
        let current = pdfView.currentPage
        var changed = false
        for i in 0..<d.pageCount {
            guard let page = d.page(at: i), page.annotations.contains(where: { $0 is ImageAnnotation }) else { continue }
            let rot = page.rotation
            page.rotation = 0
            var box = page.bounds(for: .mediaBox)
            let data = NSMutableData()
            guard let consumer = CGDataConsumer(data: data), let ctx = CGContext(consumer: consumer, mediaBox: &box, nil) else { page.rotation = rot; continue }
            ctx.beginPDFPage(nil)
            page.draw(with: .mediaBox, to: ctx)
            ctx.endPDFPage(); ctx.closePDF()
            page.rotation = rot
            guard let nd = PDFDocument(data: data as Data), let np = nd.page(at: 0) else { continue }
            np.rotation = rot
            np.setBounds(page.bounds(for: .cropBox), for: .cropBox)
            d.removePage(at: i); d.insert(np, at: i)
            changed = true
        }
        guard changed else { return }
        doc.undoManager?.removeAllActions()
        pdfView.select(nil)
        pages.reload()
        notesChanged()
        if let c = current, let idx = Optional(d.index(for: c)), idx >= 0, let np = d.page(at: min(idx, d.pageCount - 1)) { pdfView.go(to: np) }
    }

    // MARK: - Actions de menu (chaîne de répondeurs)

    func setTool(_ t: Tool) { pdfView.tool = t; updateToolButtons(t) }
    private func updateToolButtons(_ t: Tool) {
        toolButtons.forEach { $0.selectedState = $0.tag == t.rawValue }
        moreBtn?.selectedState = !Self.directTools.contains(t)
    }
    /// Tous les autres outils (soulignement, barré, note, formes, gomme blanche, croix).
    @objc private func showToolsMenu(_ b: BarButton) {
        let menu = NSMenu()
        for t in Tool.allCases where !Self.directTools.contains(t) {
            let it = NSMenuItem(title: L.t(t.key), action: #selector(selectTool(_:)), keyEquivalent: ""); it.tag = t.rawValue; it.target = self
            it.image = NSImage(systemSymbolName: t.symbol, accessibilityDescription: nil); menu.addItem(it)
        }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: b.isFlipped ? b.bounds.maxY + 4 : -4), in: b)
    }
    @objc func selectTool(_ s: NSMenuItem) { setTool(Tool(rawValue: s.tag) ?? .select) }
    /// Mode « page entière » : le format de la fenêtre suit celui de la page, donc aucun vide sur les côtés.
    private func applyFit() {
        pdfView.fitsPage = fitFill && pdfView.displayMode == .singlePage
        guard pdfView.fitsPage, let page = pdfView.currentPage else { return }
        let b = page.bounds(for: pdfView.displayBox)
        let (pw, ph) = page.rotation % 180 == 0 ? (b.width, b.height) : (b.height, b.width)
        let vb = pdfView.bounds.size
        guard pw > 0, ph > 0, vb.width > 0, vb.height > 0 else { return }
        let sc = min(vb.width / pw, vb.height / ph)
        if pdfView.autoScales { pdfView.autoScales = false }
        if abs(pdfView.scaleFactor - sc) > 0.0001 { pdfView.scaleFactor = sc }
    }

    private func updateAspectLock(animated: Bool = false) {
        guard let w = window else { return }
        guard pdfView.displayMode == .singlePage, fitFill, !w.styleMask.contains(.fullScreen), let page = pdfView.currentPage else {
            w.resizeIncrements = NSSize(width: 1, height: 1); return   // lève le verrou
        }
        let b = page.bounds(for: .cropBox)
        let (pw, ph) = page.rotation % 180 == 0 ? (b.width, b.height) : (b.height, b.width)
        guard pw > 0, ph > 0 else { return }
        w.contentAspectRatio = NSSize(width: pw, height: ph)
        let cur = w.contentRect(forFrameRect: w.frame).size
        guard abs(cur.width / cur.height - pw / ph) > 0.004 else { return }
        var f = w.frame
        let vis = (w.screen ?? NSScreen.main)?.visibleFrame ?? f
        var nw = (f.height * pw / ph).rounded(), nh = f.height
        if nw > vis.width { nw = vis.width; nh = (nw * ph / pw).rounded() }
        f.origin.x += (f.width - nw) / 2; f.origin.y += f.height - nh
        f.size = NSSize(width: nw, height: nh)
        w.setFrame(f, display: true, animate: animated)
    }

    func setDisplay(_ i: Int) {
        let modes: [PDFDisplayMode] = [.singlePage, .singlePageContinuous, .twoUp, .twoUpContinuous]
        pdfView.displayMode = modes[max(0, min(3, i))]
        fitFill = (i == 0)
        if !fitFill { pdfView.autoScales = true }
        applyFit()
        updateAspectLock(animated: true)
    }
    @objc func selectDisplay(_ s: NSMenuItem) { setDisplay(s.tag) }
    @objc func zoomIn(_ s: Any?) { fitFill = false; applyFit(); pdfView.autoScales = false; pdfView.zoomIn(nil); updateAspectLock() }
    @objc func zoomOut(_ s: Any?) { fitFill = false; applyFit(); pdfView.autoScales = false; pdfView.zoomOut(nil); updateAspectLock() }
    @objc func actualSize(_ s: Any?) { fitFill = false; applyFit(); pdfView.autoScales = false; pdfView.scaleFactor = 1; updateAspectLock() }
    @objc func fitPage(_ s: Any?) {
        if pdfView.displayMode == .singlePage { fitFill = true; applyFit() } else { pdfView.autoScales = true }
        updateAspectLock(animated: true)
    }
    @objc func fitWidth(_ s: Any?) {
        guard let page = pdfView.currentPage else { return }
        let w = page.bounds(for: pdfView.displayBox).width
        let rotated = page.rotation % 180 != 0
        let pw = rotated ? page.bounds(for: pdfView.displayBox).height : w
        fitFill = false; applyFit()
        pdfView.autoScales = false
        pdfView.scaleFactor = max(0.1, pdfView.bounds.width / pw)
        updateAspectLock()
    }
    @objc func rotateLeft(_ s: Any?) { rotate(-90) }
    @objc func rotateRight(_ s: Any?) { rotate(90) }
    private func rotate(_ d: Int) {
        guard let p = pdfView.currentPage else { return }
        p.rotation = (p.rotation + d + 360) % 360
        pdfView.layoutDocumentView()
    }
    @objc func nextPage(_ s: Any?) { pdfView.goToNextPage(nil) }
    @objc func prevPage(_ s: Any?) { pdfView.goToPreviousPage(nil) }
    @objc func firstPage(_ s: Any?) { pdfView.goToFirstPage(nil) }
    @objc func lastPage(_ s: Any?) { pdfView.goToLastPage(nil) }
    @objc func goBackHistory(_ s: Any?) { pdfView.goBack(nil) }
    @objc func goForwardHistory(_ s: Any?) { pdfView.goForward(nil) }
    @objc func focusSearch(_ s: Any?) { setChrome(true); window?.makeFirstResponder(searchField) }
    @objc func findNext(_ s: Any?) { step(1) }
    @objc func findPrevious(_ s: Any?) { step(-1) }
    @objc func startPresentation(_ s: Any?) { Presentation.start(document: doc.pdf, page: pdfView.currentPage, from: window?.screen) }

    @objc func goToPage(_ s: Any?) {
        guard let d = pdfView.document, let window else { return }
        let a = NSAlert()
        a.messageText = L.t("page.goto.title"); a.informativeText = L.t("page.goto.info", d.pageCount)
        let f = NSTextField(frame: NSRect(x: 0, y: 0, width: 120, height: 24)); a.accessoryView = f
        a.addButton(withTitle: L.t("note.ok")); a.addButton(withTitle: L.t("note.cancel"))
        a.beginSheetModal(for: window) { [weak self] r in
            guard r == .alertFirstButtonReturn, let n = Int(f.stringValue.trimmingCharacters(in: .whitespaces)), n >= 1, n <= d.pageCount, let p = d.page(at: n - 1) else { return }
            self?.pdfView.go(to: p)
        }
        a.window.initialFirstResponder = f
    }

    @objc func validateMenuItem(_ m: NSMenuItem) -> Bool {
        switch m.action {
        case #selector(selectTool(_:)): m.state = pdfView.tool.rawValue == m.tag ? .on : .off
        case #selector(selectDisplay(_:)):
            let modes: [PDFDisplayMode] = [.singlePage, .singlePageContinuous, .twoUp, .twoUpContinuous]
            m.state = pdfView.displayMode == modes[m.tag] ? .on : .off
        case #selector(setPanelSide(_:)): m.state = (m.tag == 1) == Self.panelOnRight ? .on : .off
        case #selector(goBackHistory(_:)): return pdfView.canGoBack
        case #selector(goForwardHistory(_:)): return pdfView.canGoForward
        case #selector(nextPage(_:)): return pdfView.canGoToNextPage
        case #selector(prevPage(_:)): return pdfView.canGoToPreviousPage
        case #selector(findNext(_:)), #selector(findPrevious(_:)): return !matches.isEmpty
        default: break
        }
        return true
    }

    // MARK: - Recherche

    @objc private func search(_ f: NSTextField) {
        guard let d = pdfView.document else { return }
        d.cancelFindString(); matches = []; matchIndex = 0
        pdfView.highlightedSelections = nil
        let q = f.stringValue.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { statusExtra = nil; pageChanged(); return }
        d.delegate = self
        d.beginFindString(q, withOptions: [.caseInsensitive, .diacriticInsensitive])
    }
    nonisolated func didMatchString(_ instance: PDFSelection) {
        MainActor.assumeIsolated {
            instance.color = .systemYellow
            matches.append(instance)
            if matches.count == 1 { show(0) }
        }
    }
    nonisolated func documentDidEndDocumentFind(_ notification: Notification) {
        MainActor.assumeIsolated {
            pdfView.highlightedSelections = matches
            statusExtra = matches.isEmpty ? L.t("search.none") : L.t("search.results", matches.count)
            updateTitle()
        }
    }
    private func show(_ i: Int) {
        guard matches.indices.contains(i) else { return }
        matchIndex = i
        pdfView.setCurrentSelection(matches[i], animate: true)
        pdfView.go(to: matches[i])
    }
    private func step(_ d: Int) {
        guard !matches.isEmpty else { return }
        show((matchIndex + d + matches.count) % matches.count)
    }

    // MARK: - Pages, position mémorisée

    private func pageChanged() {
        guard let d = pdfView.document, let p = pdfView.currentPage else { return }
        if statusExtra != nil && !matches.isEmpty { statusExtra = nil }
        pages.select(page: d.index(for: p))
        applyFit()
        updateAspectLock(animated: true)
        updateTitle()
        savePosition()
    }
    private var posKey: String { "pos:" + (doc.fileURL?.path ?? "") }
    private func savePosition() {
        guard let d = pdfView.document, let p = pdfView.currentPage, doc.fileURL != nil else { return }
        UserDefaults.standard.set(["page": d.index(for: p), "scale": pdfView.scaleFactor, "auto": fitFill], forKey: posKey)
    }
    private func restorePosition() {
        guard let d = pdfView.document, let s = UserDefaults.standard.dictionary(forKey: posKey),
              let i = s["page"] as? Int, let p = d.page(at: i) else { return }
        if let auto = s["auto"] as? Bool, !auto, let sc = s["scale"] as? Double { fitFill = false; pdfView.autoScales = false; pdfView.scaleFactor = sc }
        if i > 0 { pdfView.go(to: p) }
    }
    /// Centre les trois boutons de fenêtre sur l'axe de la barre d'en-tête (hauteur `size-bar`).
    private func alignTrafficLights() {
        guard let w = window else { return }
        for t in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            guard let b = w.standardWindowButton(t), let sv = b.superview else { continue }
            b.setFrameOrigin(NSPoint(x: b.frame.origin.x, y: sv.bounds.height - Socle.M.sizeBar / 2 - b.frame.height / 2 - (sv.bounds.height - 28)))
        }
    }
    func windowDidResize(_ n: Notification) { alignTrafficLights(); applyFit() }
    func windowDidEndLiveResize(_ n: Notification) { alignTrafficLights() }
    func windowWillClose(_ n: Notification) {
        savePosition()
        doc.pdf?.cancelFindString()
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        if let m = monitor { NSEvent.removeMonitor(m); monitor = nil }
        hideWork?.cancel()
    }

    // MARK: - Notes

    private var notesDirty = false
    /// Mode « page entière » : le facteur d'échelle est calculé ici (et non par PDFKit, qui laisse une marge autour de la page).
    private var fitFill = true
    /// Les notes ne sont recalculées que si leur panneau est ouvert (gros documents : pas de balayage à chaque geste).
    private func notesChanged() { notesDirty = true; if notesDrawer.visible { reloadNotes() } }

    private func addAnnotation(_ a: PDFAnnotation, to page: PDFPage) {
        page.addAnnotation(a)
        pdfView.annotationsChanged(on: page)
        doc.undoManager?.registerUndo(withTarget: self) { $0.removeAnnotation(a, from: page) }
        notesChanged()
    }
    private func removeAnnotation(_ a: PDFAnnotation, from page: PDFPage) {
        if pdfView.selected?.annot === a { pdfView.select(nil) }
        page.removeAnnotation(a)
        pdfView.annotationsChanged(on: page)
        doc.undoManager?.registerUndo(withTarget: self) { $0.addAnnotation(a, to: page) }
        notesChanged()
    }

    /// Déplacement / redimensionnement d'un ajout : annulable.
    private func registerGeometry(_ a: PDFAnnotation, _ page: PDFPage, _ old: NSRect, _ new: NSRect) {
        doc.undoManager?.registerUndo(withTarget: self) { $0.applyBounds(a, page, to: old) }
        doc.updateChangeCount(.changeDone)
    }
    private func applyBounds(_ a: PDFAnnotation, _ page: PDFPage, to target: NSRect) {
        let cur = a.bounds
        if a.type == "Line", cur.width > 0, cur.height > 0 {
            let sx = target.width / cur.width, sy = target.height / cur.height
            a.startPoint = NSPoint(x: a.startPoint.x * sx, y: a.startPoint.y * sy); a.endPoint = NSPoint(x: a.endPoint.x * sx, y: a.endPoint.y * sy)
        }
        a.bounds = target
        pdfView.annotationsChanged(on: page); pdfView.refreshOverlay()
        doc.undoManager?.registerUndo(withTarget: self) { $0.applyBounds(a, page, to: cur) }
    }
    /// Texte modifié en place : annulable (texte et taille).
    private func registerEdit(_ a: PDFAnnotation, _ page: PDFPage, _ oldText: String, _ oldBounds: NSRect) {
        doc.undoManager?.registerUndo(withTarget: self) { $0.restoreEdit(a, page, oldText, oldBounds) }
        doc.updateChangeCount(.changeDone)
        notesChanged()
    }
    private func restoreEdit(_ a: PDFAnnotation, _ page: PDFPage, _ text: String, _ bounds: NSRect) {
        let curT = a.contents ?? "", curB = a.bounds
        a.contents = text; a.bounds = bounds
        pdfView.annotationsChanged(on: page); pdfView.refreshOverlay()
        doc.undoManager?.registerUndo(withTarget: self) { $0.restoreEdit(a, page, curT, curB) }
        notesChanged()
    }

    func editText(_ a: PDFAnnotation, page: PDFPage) {
        guard let window else { return }
        let alert = NSAlert()
        alert.messageText = L.t("note.prompt")
        let tv = NSTextView(frame: NSRect(x: 0, y: 0, width: 320, height: 110))
        tv.string = a.contents ?? ""; tv.font = .systemFont(ofSize: 13); tv.isRichText = false
        let sc = NSScrollView(frame: tv.frame); sc.documentView = tv; sc.hasVerticalScroller = true; sc.borderType = .bezelBorder
        alert.accessoryView = sc
        alert.addButton(withTitle: L.t("note.ok")); alert.addButton(withTitle: L.t("note.cancel"))
        alert.window.initialFirstResponder = tv
        alert.beginSheetModal(for: window) { [weak self] r in
            guard r == .alertFirstButtonReturn, let self else { return }
            let old = a.contents ?? ""
            a.contents = tv.string
            self.pdfView.annotationsChanged(on: page)
            self.doc.undoManager?.registerUndo(withTarget: self) { $0.restoreText(a, old, page) }
            self.doc.updateChangeCount(.changeDone)
            self.notesChanged()
        }
    }
    private func restoreText(_ a: PDFAnnotation, _ text: String, _ page: PDFPage) {
        let cur = a.contents ?? ""
        a.contents = text
        pdfView.annotationsChanged(on: page)
        doc.undoManager?.registerUndo(withTarget: self) { $0.restoreText(a, cur, page) }
        notesChanged()
    }

    private func reloadNotes() {
        guard let d = pdfView.document else { return }
        var out: [NoteRow] = []
        for i in 0..<d.pageCount {
            guard let p = d.page(at: i) else { continue }
            for a in p.annotations {
                switch a.type ?? "" { case "Link", "Widget", "Popup", "": continue; default: out.append(NoteRow(annot: a, page: p, pageIndex: i)) }
            }
        }
        rows = out
        notesDirty = false
        notesTable.reloadData()
        notesEmpty.isHidden = !rows.isEmpty
    }
    @objc private func editSelectedNote() {
        guard rows.indices.contains(notesTable.clickedRow >= 0 ? notesTable.clickedRow : notesTable.selectedRow) else { return }
        let r = rows[notesTable.clickedRow >= 0 ? notesTable.clickedRow : notesTable.selectedRow]
        editText(r.annot, page: r.page)
    }
    @objc private func deleteSelectedNote() {
        let i = notesTable.clickedRow >= 0 ? notesTable.clickedRow : notesTable.selectedRow
        guard rows.indices.contains(i) else { return }
        removeAnnotation(rows[i].annot, from: rows[i].page)
    }
    private func kindName(_ a: PDFAnnotation) -> String {
        switch a.type ?? "" {
        case "Highlight": return L.t("kind.highlight"); case "Underline": return L.t("kind.underline"); case "StrikeOut": return L.t("kind.strike")
        case "Text": return L.t("kind.note"); case "FreeText": return L.t("kind.text")
        case "Square", "Circle", "Line": return L.t("kind.shape"); case "Ink": return L.t("kind.ink"); case "Stamp": return L.t("kind.image")
        default: return L.t("kind.other")
        }
    }

    // MARK: - Tables

    func numberOfRows(in tableView: NSTableView) -> Int { rows.count }
    func tableView(_ tv: NSTableView, viewFor col: NSTableColumn?, row: Int) -> NSView? {
        let cell = NSTableCellView()
        let tf = NSTextField(wrappingLabelWithString: "")
        tf.translatesAutoresizingMaskIntoConstraints = false; tf.maximumNumberOfLines = 2; tf.lineBreakMode = .byTruncatingTail
        cell.addSubview(tf); cell.textField = tf
        NSLayoutConstraint.activate([tf.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 8), tf.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -8), tf.centerYAnchor.constraint(equalTo: cell.centerYAnchor)])
        let r = rows[row]
        let head = NSAttributedString(string: kindName(r.annot) + "  ·  " + L.t("note.page", r.pageIndex + 1) + "\n", attributes: [.font: NSFont.systemFont(ofSize: 10, weight: .semibold), .foregroundColor: NSColor.secondaryLabelColor])
        let body = NSAttributedString(string: (r.annot.contents ?? "").replacingOccurrences(of: "\n", with: " "), attributes: [.font: NSFont.systemFont(ofSize: 12), .foregroundColor: NSColor.labelColor])
        let m = NSMutableAttributedString(attributedString: head); m.append(body)
        tf.attributedStringValue = m
        return cell
    }
    func tableViewSelectionDidChange(_ n: Notification) {
        guard notesTable.selectedRow >= 0, rows.indices.contains(notesTable.selectedRow) else { return }
        let r = rows[notesTable.selectedRow]
        pdfView.go(to: PDFDestination(page: r.page, at: NSPoint(x: r.annot.bounds.minX, y: r.annot.bounds.maxY + 30)))
    }

    private func reloadOutline() {
        outlineView.reloadData()
        outlineView.expandItem(nil, expandChildren: false)
    }
    func outlineView(_ ov: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        ((item as? PDFOutline) ?? pdfView.document?.outlineRoot)?.numberOfChildren ?? 0
    }
    func outlineView(_ ov: NSOutlineView, child i: Int, ofItem item: Any?) -> Any {
        ((item as? PDFOutline) ?? pdfView.document?.outlineRoot)!.child(at: i)!
    }
    func outlineView(_ ov: NSOutlineView, isItemExpandable item: Any) -> Bool { ((item as? PDFOutline)?.numberOfChildren ?? 0) > 0 }
    func outlineView(_ ov: NSOutlineView, viewFor col: NSTableColumn?, item: Any) -> NSView? {
        let cell = NSTableCellView(); let tf = NSTextField(labelWithString: (item as? PDFOutline)?.label ?? "")
        tf.translatesAutoresizingMaskIntoConstraints = false; tf.lineBreakMode = .byTruncatingTail
        cell.addSubview(tf); cell.textField = tf
        NSLayoutConstraint.activate([tf.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 2), tf.trailingAnchor.constraint(equalTo: cell.trailingAnchor), tf.centerYAnchor.constraint(equalTo: cell.centerYAnchor)])
        return cell
    }
    func outlineViewSelectionDidChange(_ n: Notification) {
        if let o = outlineView.item(atRow: outlineView.selectedRow) as? PDFOutline, let dest = o.destination { pdfView.go(to: dest) }
    }
}
