// mPDF — composants AppKit au design Socle (plat, sans ombre ni dégradé ; tokens de Socle.swift).
import AppKit
import SwiftUI

/// Couleurs Socle en NSColor (dynamiques : suivent le thème de la fenêtre).
enum S {
    static let bg = NSColor(Socle.C.bg)
    static let bgSunken = NSColor(Socle.C.bgSunken)
    static let surface = NSColor(Socle.C.surface)
    static let surfaceRaised = NSColor(Socle.C.surfaceRaised)
    static let surfaceHover = NSColor(Socle.C.surfaceHover)
    static let surfaceSelected = NSColor(Socle.C.surfaceSelected)
    static let control = NSColor(Socle.C.control)
    static let controlHover = NSColor(Socle.C.controlHover)
    static let controlPressed = NSColor(Socle.C.controlPressed)
    static let border = NSColor(Socle.C.border)
    static let text = NSColor(Socle.C.text)
    static let textStrong = NSColor(Socle.C.textStrong)
    static let textMuted = NSColor(Socle.C.textMuted)
    static let textSubtle = NSColor(Socle.C.textSubtle)
    static let accentFill = NSColor(Socle.C.accentFill)
    static let accentFillHover = NSColor(Socle.C.accentFillHover)
    static let onAccentFill = NSColor(Socle.C.onAccentFill)
    static let accentText = NSColor(Socle.C.accentText)
    /// Tailles de texte Socle × 1,1 (échelle fixe des applis desktop).
    static func font(_ size: CGFloat, _ weight: NSFont.Weight = .regular) -> NSFont { .systemFont(ofSize: (size * 1.1).rounded(), weight: weight) }
}

/// Aplat de couleur (fond de barre, de colonne, filet de 1 px) qui suit le thème.
final class FlatView: NSView {
    var fill: NSColor { didSet { needsDisplay = true } }
    init(_ fill: NSColor) { self.fill = fill; super.init(frame: .zero); wantsLayer = true; translatesAutoresizingMaskIntoConstraints = false }
    required init?(coder: NSCoder) { fatalError() }
    override var wantsUpdateLayer: Bool { true }
    override func updateLayer() { effectiveAppearance.performAsCurrentDrawingAppearance { layer?.backgroundColor = fill.cgColor } }
    override func viewDidChangeEffectiveAppearance() { needsDisplay = true }
    override func hitTest(_ p: NSPoint) -> NSView? { subviews.isEmpty ? nil : super.hitTest(p) }

    static func hairline(vertical: Bool) -> FlatView {
        let v = FlatView(S.border)
        if vertical { v.widthAnchor.constraint(equalToConstant: 1).isActive = true } else { v.heightAnchor.constraint(equalToConstant: 1).isActive = true }
        return v
    }
}

/// Bouton de barre d'outils « à la Apple » : sans fond au repos, un cartouche discret au survol, la sélection en teinte d'accent ;
/// icône SF Symbol seule, ou icône avec son libellé dessous (comme les barres de Pages ou d'Aperçu).
final class BarButton: NSButton {
    var selectedState = false { didSet { refresh() } }
    private var hover = false { didSet { refresh() } }
    private let stacked: Bool

    init(symbol: String, tip: String, target: AnyObject?, action: Selector) {
        stacked = false
        super.init(frame: .zero)
        image = Self.symbol(symbol, tip, 16)
        common(tip, target, action)
        widthAnchor.constraint(equalToConstant: 34).isActive = true
        heightAnchor.constraint(equalToConstant: 34).isActive = true
    }
    /// Icône au-dessus, libellé dessous.
    init(symbol: String, label: String, tip: String, target: AnyObject?, action: Selector) {
        stacked = true
        super.init(frame: .zero)
        image = Self.symbol(symbol, tip, 18)
        let p = NSMutableParagraphStyle(); p.alignment = .center
        attrs = [.font: NSFont.systemFont(ofSize: 10, weight: .medium), .paragraphStyle: p]
        labelText = label
        common(tip, target, action)
        let w = ceil(NSAttributedString(string: label, attributes: attrs).size().width) + 12
        widthAnchor.constraint(equalToConstant: max(w, 38)).isActive = true
        heightAnchor.constraint(equalToConstant: 44).isActive = true
    }
    required init?(coder: NSCoder) { fatalError() }

    private var attrs: [NSAttributedString.Key: Any] = [:]
    private var labelText = ""

    private static func symbol(_ name: String, _ tip: String, _ size: CGFloat) -> NSImage? {
        NSImage(systemSymbolName: name, accessibilityDescription: tip)?.withSymbolConfiguration(.init(pointSize: size, weight: .regular))
    }
    private func common(_ name: String, _ target: AnyObject?, _ action: Selector) {
        toolTip = name
        self.target = target; self.action = action
        imagePosition = stacked ? .imageAbove : .imageOnly
        isBordered = false; bezelStyle = .regularSquare; imageScaling = .scaleNone; focusRingType = .exterior
        setButtonType(.momentaryChange)
        wantsLayer = true; layer?.cornerRadius = 8
        translatesAutoresizingMaskIntoConstraints = false
        setAccessibilityLabel(name)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self))
        refresh()
    }
    func setSymbol(_ name: String) { image = Self.symbol(name, toolTip ?? "", stacked ? 18 : 16) }
    override func mouseEntered(with e: NSEvent) { hover = true }
    override func mouseExited(with e: NSEvent) { hover = false }
    override var isHighlighted: Bool { didSet { refresh() } }
    override var isEnabled: Bool { didSet { refresh() } }
    override func viewDidChangeEffectiveAppearance() { refresh() }

    func refresh() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            let bg: NSColor = selectedState ? NSColor.controlAccentColor.withAlphaComponent(0.20)
                : (isHighlighted ? NSColor.labelColor.withAlphaComponent(0.16) : (hover ? NSColor.labelColor.withAlphaComponent(0.08) : .clear))
            layer?.backgroundColor = bg.cgColor
            let fg: NSColor = selectedState ? .controlAccentColor : NSColor.labelColor.withAlphaComponent(0.86)
            contentTintColor = fg
            if stacked {
                var a = attrs; a[.foregroundColor] = selectedState ? NSColor.controlAccentColor : NSColor.secondaryLabelColor
                attributedTitle = NSAttributedString(string: labelText, attributes: a)
            }
        }
        alphaValue = isEnabled ? 1 : 0.4
    }
}

/// Filet vertical entre deux groupes d'outils.
final class ToolbarDivider: NSView {
    init() {
        super.init(frame: .zero)
        wantsLayer = true; translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: 1).isActive = true; heightAnchor.constraint(equalToConstant: 26).isActive = true
    }
    required init?(coder: NSCoder) { fatalError() }
    override var wantsUpdateLayer: Bool { true }
    override func updateLayer() { effectiveAppearance.performAsCurrentDrawingAppearance { layer?.backgroundColor = NSColor.separatorColor.cgColor } }
    override func viewDidChangeEffectiveAppearance() { needsDisplay = true }
}

/// Zone de saisie Socle : angles droits, fond `bg-sunken`, marge intérieure `space-3`, pas de contour (sauf focus).
final class FieldCell: NSTextFieldCell {
    private let inset: CGFloat = Socle.M.space3
    override func drawingRect(forBounds r: NSRect) -> NSRect { centered(super.drawingRect(forBounds: r.insetBy(dx: inset, dy: 0))) }
    override func titleRect(forBounds r: NSRect) -> NSRect { centered(super.titleRect(forBounds: r.insetBy(dx: inset, dy: 0))) }
    override func edit(withFrame r: NSRect, in v: NSView, editor: NSText, delegate d: Any?, event e: NSEvent?) { super.edit(withFrame: drawingRect(forBounds: r), in: v, editor: editor, delegate: d, event: e) }
    override func select(withFrame r: NSRect, in v: NSView, editor: NSText, delegate d: Any?, start: Int, length: Int) { super.select(withFrame: drawingRect(forBounds: r), in: v, editor: editor, delegate: d, start: start, length: length) }
    private func centered(_ r: NSRect) -> NSRect {
        let h = cellSize(forBounds: r).height
        return NSRect(x: r.minX, y: r.minY + (r.height - h) / 2, width: r.width, height: h)
    }
}

final class SearchField: NSTextField {
    override class var cellClass: AnyClass? { get { FieldCell.self } set {} }
    init(placeholder: String) {
        super.init(frame: .zero)
        isBordered = false; isBezeled = false; drawsBackground = false; isEditable = true
        font = S.font(12)
        focusRingType = .exterior
        wantsLayer = true
        translatesAutoresizingMaskIntoConstraints = false
        (cell as? NSTextFieldCell)?.isScrollable = true
        placeholderAttributedString = NSAttributedString(string: placeholder, attributes: [.font: S.font(12), .foregroundColor: S.textSubtle])
        heightAnchor.constraint(equalToConstant: Socle.M.sizeControl).isActive = true
        updateColors()
    }
    required init?(coder: NSCoder) { fatalError() }
    override func viewDidChangeEffectiveAppearance() { updateColors() }
    private func updateColors() {
        effectiveAppearance.performAsCurrentDrawingAppearance { layer?.backgroundColor = S.bgSunken.cgColor; textColor = S.textStrong }
    }
}

/// Séparateur de colonnes : filet de 1 px aux couleurs Socle.
final class FlatSplitView: NSSplitView {
    override var dividerColor: NSColor { S.border }
    override var dividerThickness: CGFloat { 1 }
}

/// Ligne sélectionnée : aplat `surface-selected` (le contrôle porte l'accent, pas la ligne).
final class SelRow: NSTableRowView {
    override func drawSelection(in dirtyRect: NSRect) { S.surfaceSelected.setFill(); bounds.fill() }
    override var isEmphasized: Bool { get { false } set {} }
}

extension Notification.Name { static let mpdfPanelSide = Notification.Name("mpdfPanelSide") }

/// Pastille d'information (nom du fichier, page) : translucide, centrée en bas, s'efface seule ; ne capte aucun clic.
@MainActor
final class PageHUD: NSVisualEffectView {
    private let label = NSTextField(labelWithString: "")
    private var work: DispatchWorkItem?

    init() {
        super.init(frame: .zero)
        material = .hudWindow; blendingMode = .withinWindow; state = .active
        wantsLayer = true; layer?.cornerRadius = 10; layer?.masksToBounds = true
        alphaValue = 0
        translatesAutoresizingMaskIntoConstraints = false
        label.translatesAutoresizingMaskIntoConstraints = false
        label.lineBreakMode = .byTruncatingMiddle; label.maximumNumberOfLines = 1
        label.cell?.usesSingleLineMode = true; label.cell?.wraps = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14), label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            label.topAnchor.constraint(equalTo: topAnchor, constant: 7), label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -7),
            widthAnchor.constraint(lessThanOrEqualToConstant: 520),
        ])
    }
    required init?(coder: NSCoder) { fatalError() }
    override func hitTest(_ p: NSPoint) -> NSView? { nil }

    func show(name: String, detail: String, hold: TimeInterval = 1.8) {
        let s = NSMutableAttributedString(string: name, attributes: [.font: S.font(12, .semibold), .foregroundColor: NSColor.labelColor])
        s.append(NSAttributedString(string: "   " + detail, attributes: [.font: S.font(12), .foregroundColor: NSColor.secondaryLabelColor]))
        label.attributedStringValue = s
        work?.cancel()
        NSAnimationContext.runAnimationGroup { $0.duration = 0.15; animator().alphaValue = 1 }
        let w = DispatchWorkItem { [weak self] in NSAnimationContext.runAnimationGroup { $0.duration = 0.4; self?.animator().alphaValue = 0 } }
        work = w
        DispatchQueue.main.asyncAfter(deadline: .now() + hold, execute: w)
    }
}
