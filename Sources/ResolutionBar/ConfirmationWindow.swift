import AppKit
import ResolutionCore

@MainActor final class ConfirmationWindow: NSObject, NSWindowDelegate {
    private let window: NSPanel
    private let countdown = NSTextField(labelWithString: "")
    var onKeep: (() -> Void)?
    var onRevert: (() -> Void)?

    override init() {
        window = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 430, height: 220),
            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        super.init()
        window.title = "Keep this resolution?"
        window.level = .floating
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    }

    func show(change: PendingChange, seconds: Int, demo: Bool) {
        let title = NSTextField(wrappingLabelWithString: change.original.name)
        title.font = .boldSystemFont(ofSize: 16)
        let resolution = NSTextField(wrappingLabelWithString: change.desired.title)
        resolution.font = .monospacedDigitSystemFont(ofSize: 14, weight: .regular)
        countdown.font = .systemFont(ofSize: 13)
        countdown.textColor = .secondaryLabelColor
        countdown.setAccessibilityIdentifier("preview-countdown")
        let keep = NSButton(title: "Keep", target: self, action: #selector(keepPressed))
        keep.bezelStyle = .rounded
        keep.keyEquivalent = "\r"
        let revert = NSButton(title: "Revert", target: self, action: #selector(revertPressed))
        revert.bezelStyle = .rounded
        revert.keyEquivalent = "\u{1b}"
        let buttons = NSStackView(views: [revert, keep])
        buttons.orientation = .horizontal
        buttons.alignment = .centerY
        buttons.spacing = 12
        let stack = NSStackView(views: [title, resolution, countdown, buttons])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 16
        if demo {
            let label = NSTextField(labelWithString: "Demo — your real displays are unchanged")
            label.font = .systemFont(ofSize: 11)
            label.textColor = .secondaryLabelColor
            stack.addArrangedSubview(label)
        }
        let content = NSView()
        content.addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -24),
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 20),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -20)
        ])
        window.contentView = content
        window.setContentSize(NSSize(width: 430, height: demo ? 250 : 220))
        update(seconds: seconds)
        window.center()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func update(seconds: Int) { countdown.stringValue = "Reverting in \(seconds) seconds unless you keep this setting." }
    func dismiss() { window.orderOut(nil) }
    func windowShouldClose(_ sender: NSWindow) -> Bool { onRevert?(); return false }
    @objc private func keepPressed() { onKeep?() }
    @objc private func revertPressed() { onRevert?() }
}
