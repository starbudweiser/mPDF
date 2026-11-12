// mPDF — fenêtre « À propos » (modèle Socle, sans dépendance externe).
import AppKit

enum Brand {
    /// Rouge du logo ; la lettre « m » minuscule du nom en prend la couleur (règle Socle).
    static let color = NSColor(name: nil) { a in
        a.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(srgbRed: 0xff / 255, green: 0x6b / 255, blue: 0x6b / 255, alpha: 1)
            : NSColor(srgbRed: 0xc9 / 255, green: 0x2a / 255, blue: 0x2a / 255, alpha: 1)
    }
    static func name(size: CGFloat) -> NSAttributedString {
        let s = NSMutableAttributedString(string: "mPDF", attributes: [.font: NSFont.boldSystemFont(ofSize: size), .foregroundColor: NSColor.labelColor])
        s.addAttribute(.foregroundColor, value: color, range: NSRange(location: 0, length: 1))
        return s
    }
}

@MainActor
enum About {
    private static var window: NSWindow?

    static func show() {
        if window == nil { window = make() }
        window?.center()
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }

    private static func label(_ t: String, size: CGFloat = 12, secondary: Bool = false) -> NSTextField {
        let f = NSTextField(wrappingLabelWithString: t)
        f.font = .systemFont(ofSize: size); f.alignment = .center; f.isSelectable = false
        f.textColor = secondary ? .secondaryLabelColor : .labelColor
        f.preferredMaxLayoutWidth = 300
        return f
    }

    private static func make() -> NSWindow {
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 360, height: 360), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        w.isReleasedWhenClosed = false
        w.title = ""
        let icon = NSImageView(image: NSApp.applicationIconImage)
        icon.widthAnchor.constraint(equalToConstant: 96).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 96).isActive = true
        let name = NSTextField(labelWithString: ""); name.attributedStringValue = Brand.name(size: 26); name.alignment = .center
        let v = (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "1.0"
        let stack = NSStackView(views: [icon, name, label(L.t("about.version", v), secondary: true), label(L.t("about.tagline")),
                                        label(L.t("about.author")), label(L.t("about.license"), secondary: true), label(L.t("about.warranty"), secondary: true)])
        stack.orientation = .vertical; stack.alignment = .centerX; stack.spacing = 8
        stack.setCustomSpacing(14, after: icon); stack.setCustomSpacing(14, after: stack.views[2])
        stack.translatesAutoresizingMaskIntoConstraints = false
        let c = NSView(); c.addSubview(stack)
        NSLayoutConstraint.activate([stack.centerXAnchor.constraint(equalTo: c.centerXAnchor), stack.centerYAnchor.constraint(equalTo: c.centerYAnchor)])
        w.contentView = c
        return w
    }
}
