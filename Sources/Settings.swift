// mPDF — fenêtre des réglages : mises à jour automatiques (case « installer automatiquement » + recherche manuelle).
import AppKit

@MainActor
enum SettingsWindow {
    private static var window: NSWindow?
    @MainActor private final class Target: NSObject {
        @objc func toggle(_ b: NSButton) { UserDefaults.standard.set(b.state == .on, forKey: "autoInstall") }
        @objc func check(_ b: NSButton) { UpdateEngine.shared.checkNow() }
    }
    private static let target = Target()

    static func show() {
        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 380, height: 150), styleMask: [.titled, .closable], backing: .buffered, defer: false)
            w.isReleasedWhenClosed = false
            w.title = L.t("settings.title")
            let box = NSButton(checkboxWithTitle: L.t("settings.auto"), target: target, action: #selector(Target.toggle(_:)))
            box.state = UserDefaults.standard.bool(forKey: "autoInstall") ? .on : .off
            let btn = NSButton(title: L.t("settings.check"), target: target, action: #selector(Target.check(_:)))
            btn.bezelStyle = .rounded
            let v = (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? ""
            let ver = NSTextField(labelWithString: L.t("about.version", v)); ver.textColor = .secondaryLabelColor
            let stack = NSStackView(views: [box, btn, ver]); stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 14
            stack.translatesAutoresizingMaskIntoConstraints = false
            let c = NSView(); c.addSubview(stack)
            NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo: c.leadingAnchor, constant: 28), stack.trailingAnchor.constraint(equalTo: c.trailingAnchor, constant: -28),
                                         stack.topAnchor.constraint(equalTo: c.topAnchor, constant: 28), stack.bottomAnchor.constraint(equalTo: c.bottomAnchor, constant: -28)])
            w.contentView = c
            window = w
        }
        window?.updaterCenter()
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}
