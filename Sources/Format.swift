// mPDF — style du texte (police, taille, gras, italique, couleur) et barre de format qui apparaît avec l'outil Texte.
import AppKit

struct TextStyle: Equatable {
    var family = "Helvetica Neue"
    var size: CGFloat = 16
    var bold = false
    var italic = false
    var color = NSColor(srgbRed: 0.1, green: 0.1, blue: 0.12, alpha: 1)

    var font: NSFont {
        let fm = NSFontManager.shared
        var traits: NSFontTraitMask = []
        if bold { traits.insert(.boldFontMask) }
        if italic { traits.insert(.italicFontMask) }
        return fm.font(withFamily: family, traits: traits, weight: 5, size: size) ?? NSFont.systemFont(ofSize: size)
    }

    /// Style relevé sur une police existante (texte déjà posé).
    init(font: NSFont?, color: NSColor?) {
        if let font {
            family = font.familyName ?? "Helvetica Neue"; size = font.pointSize
            let t = NSFontManager.shared.traits(of: font)
            bold = t.contains(.boldFontMask); italic = t.contains(.italicFontMask)
        }
        if let color { self.color = color }
    }
    init() {}

    private static let key = "textStyle"
    static func load() -> TextStyle {
        var s = TextStyle()
        guard let d = UserDefaults.standard.dictionary(forKey: key) else { return s }
        if let f = d["family"] as? String { s.family = f }
        if let z = d["size"] as? Double { s.size = CGFloat(z) }
        s.bold = d["bold"] as? Bool ?? false; s.italic = d["italic"] as? Bool ?? false
        if let c = d["color"] as? [Double], c.count == 3 { s.color = NSColor(srgbRed: c[0], green: c[1], blue: c[2], alpha: 1) }
        return s
    }
    func save() {
        let c = color.usingColorSpace(.sRGB) ?? color
        UserDefaults.standard.set(["family": family, "size": Double(size), "bold": bold, "italic": italic, "color": [Double(c.redComponent), Double(c.greenComponent), Double(c.blueComponent)]], forKey: Self.key)
    }

    /// Polices proposées en tête de liste (celles qu'une enseignante utilise le plus), puis toutes les autres.
    static let favorites = ["Helvetica Neue", "Arial", "Verdana", "Comic Sans MS", "Chalkboard SE", "Marker Felt", "Noteworthy", "Bradley Hand", "Georgia", "Times New Roman", "Courier New", "Futura", "Avenir Next", "Baskerville", "Didot"]
    static let sizes: [CGFloat] = [10, 12, 14, 16, 18, 20, 24, 28, 32, 40, 48, 64, 72, 96]
    static let palette: [(String, NSColor)] = [
        ("Noir", NSColor(srgbRed: 0.1, green: 0.1, blue: 0.12, alpha: 1)), ("Rouge", NSColor(srgbRed: 0.85, green: 0.15, blue: 0.15, alpha: 1)),
        ("Orange", NSColor(srgbRed: 0.95, green: 0.55, blue: 0.1, alpha: 1)), ("Vert", NSColor(srgbRed: 0.1, green: 0.6, blue: 0.3, alpha: 1)),
        ("Bleu", NSColor(srgbRed: 0.1, green: 0.4, blue: 0.9, alpha: 1)), ("Violet", NSColor(srgbRed: 0.55, green: 0.25, blue: 0.8, alpha: 1)),
        ("Blanc", NSColor.white)]
}

private final class Swatch: NSButton {
    let swatchColor: NSColor
    var chosen = false { didSet { needsDisplay = true } }
    init(_ c: NSColor, name: String, target: AnyObject?, action: Selector) {
        swatchColor = c
        super.init(frame: .zero)
        isBordered = false; title = ""; self.target = target; self.action = action; toolTip = name
        setAccessibilityLabel(name)
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: 22).isActive = true; heightAnchor.constraint(equalToConstant: 22).isActive = true
    }
    required init?(coder: NSCoder) { fatalError() }
    override func draw(_ r: NSRect) {
        let c = bounds.insetBy(dx: 3, dy: 3)
        swatchColor.setFill(); NSBezierPath(ovalIn: c).fill()
        NSColor.separatorColor.setStroke(); let o = NSBezierPath(ovalIn: c); o.lineWidth = 1; o.stroke()
        if chosen { NSColor.controlAccentColor.setStroke(); let p = NSBezierPath(ovalIn: bounds.insetBy(dx: 0.75, dy: 0.75)); p.lineWidth = 2; p.stroke() }
    }
}

/// Barre de format : police, taille, gras, italique, couleur. Elle apparaît avec l'outil Texte ou quand un texte est sélectionné.
@MainActor
final class FormatBar: NSVisualEffectView {
    var onChange: ((TextStyle) -> Void)?
    private(set) var style = TextStyle.load()
    private let fontPop = NSPopUpButton(frame: .zero, pullsDown: false)
    private let sizePop = NSPopUpButton(frame: .zero, pullsDown: false)
    private var boldBtn: BarButton!, italicBtn: BarButton!
    private var swatches: [Swatch] = []
    private var updating = false

    init() {
        super.init(frame: .zero)
        material = .hudWindow; blendingMode = .withinWindow; state = .active
        wantsLayer = true; layer?.cornerRadius = 12; layer?.masksToBounds = true
        translatesAutoresizingMaskIntoConstraints = false
        alphaValue = 0; isHidden = true

        let installed = Set(NSFontManager.shared.availableFontFamilies)
        let fav = TextStyle.favorites.filter { installed.contains($0) }
        let others = installed.subtracting(fav).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        for f in fav { addFont(f) }
        fontPop.menu?.addItem(.separator())
        for f in others { addFont(f) }
        fontPop.target = self; fontPop.action = #selector(changed(_:)); fontPop.controlSize = .regular
        fontPop.toolTip = L.t("fmt.font")
        sizePop.addItems(withTitles: TextStyle.sizes.map { String(Int($0)) })
        sizePop.target = self; sizePop.action = #selector(changed(_:)); sizePop.toolTip = L.t("fmt.size")
        boldBtn = BarButton(symbol: "bold", tip: L.t("fmt.bold"), target: self, action: #selector(changed(_:)))
        italicBtn = BarButton(symbol: "italic", tip: L.t("fmt.italic"), target: self, action: #selector(changed(_:)))
        swatches = TextStyle.palette.map { Swatch($0.1, name: $0.0, target: self, action: #selector(pickColor(_:))) }

        let row = NSStackView(views: [fontPop, sizePop, boldBtn, italicBtn] + swatches)
        row.spacing = 6; row.setCustomSpacing(12, after: sizePop); row.setCustomSpacing(12, after: italicBtn)
        row.edgeInsets = NSEdgeInsets(top: 6, left: 10, bottom: 6, right: 10)
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        NSLayoutConstraint.activate([row.leadingAnchor.constraint(equalTo: leadingAnchor), row.trailingAnchor.constraint(equalTo: trailingAnchor),
                                     row.topAnchor.constraint(equalTo: topAnchor), row.bottomAnchor.constraint(equalTo: bottomAnchor),
                                     fontPop.widthAnchor.constraint(equalToConstant: 170)])
        apply(style)
    }
    required init?(coder: NSCoder) { fatalError() }

    private func addFont(_ family: String) {
        let it = NSMenuItem(title: family, action: nil, keyEquivalent: "")
        it.attributedTitle = NSAttributedString(string: family, attributes: [.font: NSFontManager.shared.font(withFamily: family, traits: [], weight: 5, size: 13) ?? NSFont.systemFont(ofSize: 13)])
        fontPop.menu?.addItem(it)
    }

    /// Reflète le style d'un texte sélectionné (sans changer le style par défaut).
    func apply(_ s: TextStyle) {
        updating = true; style = s
        if fontPop.itemTitles.contains(s.family) { fontPop.selectItem(withTitle: s.family) }
        else { fontPop.addItem(withTitle: s.family); fontPop.selectItem(withTitle: s.family) }
        let nearest = TextStyle.sizes.min { abs($0 - s.size) < abs($1 - s.size) } ?? 16
        sizePop.selectItem(withTitle: String(Int(nearest)))
        boldBtn.selectedState = s.bold; italicBtn.selectedState = s.italic
        for sw in swatches { sw.chosen = sw.swatchColor.usingColorSpace(.sRGB).map { abs($0.redComponent - (s.color.usingColorSpace(.sRGB)?.redComponent ?? -1)) < 0.02 && abs($0.greenComponent - (s.color.usingColorSpace(.sRGB)?.greenComponent ?? -1)) < 0.02 && abs($0.blueComponent - (s.color.usingColorSpace(.sRGB)?.blueComponent ?? -1)) < 0.02 } ?? false }
        updating = false
    }

    @objc private func changed(_ sender: Any?) {
        guard !updating else { return }
        var s = style
        if let f = fontPop.titleOfSelectedItem { s.family = f }
        if let z = sizePop.titleOfSelectedItem, let v = Double(z) { s.size = CGFloat(v) }
        if (sender as AnyObject) === boldBtn { s.bold.toggle() }
        if (sender as AnyObject) === italicBtn { s.italic.toggle() }
        apply(s); s.save(); onChange?(s)
    }
    @objc private func pickColor(_ b: Swatch) {
        var s = style; s.color = b.swatchColor
        apply(s); s.save(); onChange?(s)
    }

    func setVisible(_ v: Bool) {
        if v { isHidden = false }
        NSAnimationContext.runAnimationGroup({ ctx in ctx.duration = 0.18; animator().alphaValue = v ? 1 : 0 }, completionHandler: { [weak self] in if !v { self?.isHidden = true } })
    }
}
