// mPDF — panneau des pages : miniatures, glisser-déposer de PDF ou d'images entre deux pages, réordonnancement.
import AppKit
import PDFKit
import UniformTypeIdentifiers

extension NSPasteboard.PasteboardType { static let mpdfPage = NSPasteboard.PasteboardType("fr.stephan.mpdf.page") }

private final class PageCell: NSTableCellView {
    let thumb = NSImageView()
    let number = NSTextField(labelWithString: "")
    var page: PDFPage?
    private let frame_ = FlatView(S.border)
    private var thumbH: NSLayoutConstraint!

    override init(frame f: NSRect) {
        super.init(frame: f)
        thumb.imageScaling = .scaleProportionallyUpOrDown
        thumb.translatesAutoresizingMaskIntoConstraints = false
        thumb.wantsLayer = true
        number.translatesAutoresizingMaskIntoConstraints = false
        number.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        number.textColor = S.textMuted
        addSubview(thumb); addSubview(number)
        thumbH = thumb.heightAnchor.constraint(equalToConstant: 150)
        NSLayoutConstraint.activate([
            thumb.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            thumb.centerXAnchor.constraint(equalTo: centerXAnchor),
            thumb.widthAnchor.constraint(equalToConstant: PagesPanel.thumbWidth),
            thumbH,
            number.centerXAnchor.constraint(equalTo: centerXAnchor),
            number.topAnchor.constraint(equalTo: thumb.bottomAnchor, constant: 4),
        ])
    }
    required init?(coder: NSCoder) { fatalError() }
    func set(height: CGFloat) { thumbH.constant = height }
}

final class PagesTable: NSTableView {
    var onDelete: (() -> Void)?
    override func keyDown(with e: NSEvent) {
        if e.keyCode == 51 || e.keyCode == 117 { onDelete?() } else { super.keyDown(with: e) }
    }
}

@MainActor
final class PagesPanel: NSObject, NSTableViewDataSource, NSTableViewDelegate {
    static let thumbWidth: CGFloat = 124
    let scroll = NSScrollView()
    let table = PagesTable()
    weak var document: PDFDocument?
    var onSelect: ((Int) -> Void)?
    var onInsert: (([URL], Int) -> Void)?
    var onMove: ((Int, Int) -> Void)?
    var onDelete: ((Int) -> Void)?
    enum Action: Int { case duplicate, blankAfter, delete, rotateLeft, rotateRight, insertFile }
    var onAction: ((Action, Int) -> Void)?
    private var cache: [ObjectIdentifier: (PDFPage, NSImage)] = [:]
    private var suppress = false

    override init() {
        super.init()
        let col = NSTableColumn(identifier: .init("p")); col.resizingMask = .autoresizingMask
        col.minWidth = 60
        table.addTableColumn(col)
        table.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        table.headerView = nil; table.style = .plain; table.backgroundColor = .clear
        table.intercellSpacing = NSSize(width: 0, height: 0)
        table.dataSource = self; table.delegate = self
        table.allowsEmptySelection = true
        table.draggingDestinationFeedbackStyle = .gap
        table.registerForDraggedTypes([.fileURL, .mpdfPage])
        table.setDraggingSourceOperationMask(.move, forLocal: true)
        table.onDelete = { [weak self] in if let r = self?.table.selectedRow, r >= 0 { self?.onDelete?(r) } }
        let menu = NSMenu()
        for (a, key, sym) in [(Action.insertFile, "pm.insertFile", "doc.badge.plus"), (.blankAfter, "pm.blank", "plus.rectangle.on.rectangle"), (.duplicate, "pm.duplicate", "plus.square.on.square"),
                              (.rotateLeft, "menu.rotateLeft", "rotate.left"), (.rotateRight, "menu.rotateRight", "rotate.right"), (.delete, "pm.delete", "trash")] {
            let it = NSMenuItem(title: L.t(key), action: #selector(menuAction(_:)), keyEquivalent: ""); it.tag = a.rawValue; it.target = self
            it.image = NSImage(systemSymbolName: sym, accessibilityDescription: nil); menu.addItem(it)
            if a == .duplicate || a == .rotateRight { menu.addItem(.separator()) }
        }
        table.menu = menu
        scroll.documentView = table
        scroll.hasVerticalScroller = true; scroll.drawsBackground = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
    }

    @objc private func menuAction(_ m: NSMenuItem) {
        let row = table.clickedRow >= 0 ? table.clickedRow : table.selectedRow
        if row >= 0, let a = Action(rawValue: m.tag) { onAction?(a, row) }
    }

    func reload() {
        if cache.count > 400 { cache.removeAll() }
        table.reloadData()
    }

    func select(page index: Int) {
        guard index >= 0, index < (document?.pageCount ?? 0), table.selectedRow != index else { return }
        suppress = true
        table.selectRowIndexes([index], byExtendingSelection: false)
        table.scrollRowToVisible(index)
        suppress = false
    }

    private func height(for page: PDFPage) -> CGFloat {
        let b = page.bounds(for: .cropBox)
        let (w, h) = page.rotation % 180 == 0 ? (b.width, b.height) : (b.height, b.width)
        guard w > 0 else { return 150 }
        return min(max(Self.thumbWidth * h / w, 40), 190)
    }

    // MARK: Données
    func numberOfRows(in tableView: NSTableView) -> Int { document?.pageCount ?? 0 }
    func tableView(_ tv: NSTableView, heightOfRow row: Int) -> CGFloat {
        guard let p = document?.page(at: row) else { return 100 }
        return height(for: p) + 8 + 4 + 16 + 10
    }
    func tableView(_ tv: NSTableView, rowViewForRow row: Int) -> NSTableRowView? { SelRow() }
    func tableView(_ tv: NSTableView, viewFor col: NSTableColumn?, row: Int) -> NSView? {
        guard let page = document?.page(at: row) else { return nil }
        let cell = (tv.makeView(withIdentifier: .init("pc"), owner: self) as? PageCell) ?? { let c = PageCell(frame: .zero); c.identifier = .init("pc"); return c }()
        let h = height(for: page)
        cell.set(height: h)
        cell.page = page
        cell.number.stringValue = String(row + 1)
        let key = ObjectIdentifier(page)
        if let hit = cache[key], hit.0 === page { cell.thumb.image = hit.1 }
        else {
            cell.thumb.image = nil
            let size = NSSize(width: Self.thumbWidth * 2, height: h * 2)
            DispatchQueue.global(qos: .userInitiated).async { [weak self, weak cell] in
                let img = page.thumbnail(of: size, for: .cropBox)
                DispatchQueue.main.async {
                    MainActor.assumeIsolated {
                        self?.cache[key] = (page, img)
                        if let cell, cell.page === page { cell.thumb.image = img }
                    }
                }
            }
        }
        return cell
    }
    func tableViewSelectionDidChange(_ n: Notification) {
        guard !suppress, table.selectedRow >= 0 else { return }
        onSelect?(table.selectedRow)
    }

    // MARK: Glisser-déposer
    func tableView(_ tv: NSTableView, pasteboardWriterForRow row: Int) -> NSPasteboardWriting? {
        let item = NSPasteboardItem()
        item.setString(String(row), forType: .mpdfPage)
        return item
    }
    private func fileURLs(_ info: NSDraggingInfo) -> [URL] {
        let opts: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true,
                                                          .urlReadingContentsConformToTypes: [UTType.pdf.identifier, UTType.image.identifier]]
        return (info.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: opts) as? [URL]) ?? []
    }
    func tableView(_ tv: NSTableView, validateDrop info: NSDraggingInfo, proposedRow row: Int, proposedDropOperation op: NSTableView.DropOperation) -> NSDragOperation {
        if op == .on { tv.setDropRow(row, dropOperation: .above) }
        if (info.draggingSource as? NSTableView) === tv { return .move }
        return fileURLs(info).isEmpty ? [] : .copy
    }
    func tableView(_ tv: NSTableView, acceptDrop info: NSDraggingInfo, row: Int, dropOperation op: NSTableView.DropOperation) -> Bool {
        if (info.draggingSource as? NSTableView) === tv {
            guard let s = info.draggingPasteboard.string(forType: .mpdfPage), let from = Int(s) else { return false }
            onMove?(from, row)
            return true
        }
        let urls = fileURLs(info)
        guard !urls.isEmpty else { return false }
        onInsert?(urls, row)
        return true
    }
}
