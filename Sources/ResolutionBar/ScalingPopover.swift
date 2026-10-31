import AppKit
import ResolutionCore

@MainActor final class ScalingPresetButton: NSButton {
    let preset: ScalingPreset
    private let sampleSize: CGFloat
    private var hovering = false

    init(preset: ScalingPreset, index: Int, count: Int, selected: Bool, enabled: Bool) {
        self.preset = preset
        sampleSize = count > 1 ? 23 - CGFloat(index) * 11 / CGFloat(count - 1) : 17
        super.init(frame: NSRect(x: 0, y: 0, width: 76, height: 94))
        title = preset.accessibilityLabel
        isBordered = false
        setButtonType(.momentaryChange)
        state = selected ? .on : .off
        isEnabled = enabled
        focusRingType = .exterior
        toolTip = preset.mode.title
        setAccessibilityLabel("\(preset.accessibilityLabel), \(preset.mode.title)")
        setAccessibilityValue(selected ? "Selected" : "")
        widthAnchor.constraint(equalToConstant: 76).isActive = true
        heightAnchor.constraint(equalToConstant: 94).isActive = true
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var isFlipped: Bool { false }
    override var acceptsFirstResponder: Bool { isEnabled }
    override func updateTrackingAreas() {
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInKeyWindow],
                                      owner: self, userInfo: nil))
        super.updateTrackingAreas()
    }
    override func mouseEntered(with event: NSEvent) { hovering = true; needsDisplay = true }
    override func mouseExited(with event: NSEvent) { hovering = false; needsDisplay = true }
    override func draw(_ dirtyRect: NSRect) {
        let tile = NSRect(x: 5, y: 24, width: 66, height: 64)
        let path = NSBezierPath(roundedRect: tile, xRadius: 8, yRadius: 8)
        (hovering && isEnabled ? NSColor.controlColor : NSColor.controlBackgroundColor).setFill()
        path.fill()
        (state == .on ? NSColor.controlAccentColor : NSColor.separatorColor).setStroke()
        path.lineWidth = state == .on ? 3 : 1
        path.stroke()
        NSGraphicsContext.saveGraphicsState()
        path.addClip()
        for (index, color) in [NSColor.systemRed, .systemYellow, .systemGreen].enumerated() {
            color.withAlphaComponent(isEnabled ? 0.9 : 0.35).setFill()
            NSBezierPath(ovalIn: NSRect(x: 12 + index * 10, y: 75, width: 6, height: 6)).fill()
        }
        let textColor = isEnabled ? NSColor.labelColor : NSColor.disabledControlTextColor
        let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: sampleSize), .foregroundColor: textColor]
        ("Aa" as NSString).draw(at: NSPoint(x: 12, y: 47), withAttributes: attributes)
        for row in 0..<3 {
            NSColor.secondaryLabelColor.withAlphaComponent(isEnabled ? 0.5 : 0.2).setFill()
            NSBezierPath(roundedRect: NSRect(x: 12, y: CGFloat(40 - row * 6), width: row == 2 ? 31 : 50,
                                            height: 2), xRadius: 1, yRadius: 1).fill()
        }
        NSGraphicsContext.restoreGraphicsState()
        let caption = preset.isDefault ? "Default" : state == .on ? "Selected" : ""
        let paragraph = NSMutableParagraphStyle(); paragraph.alignment = .center
        (caption as NSString).draw(in: NSRect(x: 0, y: 3, width: 76, height: 17), withAttributes: [
            .font: NSFont.systemFont(ofSize: 11, weight: state == .on ? .semibold : .regular),
            .foregroundColor: textColor, .paragraphStyle: paragraph
        ])
    }
}

@MainActor private final class ScalingDocumentView: NSView { override var isFlipped: Bool { true } }

@MainActor final class ScalingPopoverController: NSViewController {
    private var actions: [ObjectIdentifier: () -> Void] = [:]

    init(displays: [DisplaySnapshot], notice: String?, demo: Bool, switching: Bool,
         onSelect: @escaping (DisplaySnapshot, DisplayMode) -> Void,
         onAdvanced: @escaping (NSButton) -> Void, onQuit: @escaping () -> Void) {
        super.init(nibName: nil, bundle: nil)
        let stack = NSStackView()
        stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 16
        if demo { stack.addArrangedSubview(label("Demo — real displays are unchanged", size: 11, secondary: true)) }
        let sections = DisplayMenu.sections(displays)
        if sections.isEmpty { stack.addArrangedSubview(label("No active displays found. Reopen to retry.", size: 13)) }
        for (index, section) in sections.enumerated() {
            if index > 0 { stack.addArrangedSubview(separator()) }
            let heading = NSStackView()
            heading.orientation = .vertical; heading.alignment = .leading; heading.spacing = 4
            let name = label(section.title, size: 14); name.font = .systemFont(ofSize: 14, weight: .semibold)
            heading.addArrangedSubview(name)
            if let current = section.display.currentMode {
                heading.addArrangedSubview(label("Looks like \(current.width) × \(current.height)", size: 12, secondary: true))
            }
            stack.addArrangedSubview(heading)
            if let explanation = section.explanation {
                stack.addArrangedSubview(label(explanation, size: 12, secondary: true))
            }
            let presets = ScalingPresets.options(for: section.display)
            if !presets.isEmpty {
                let row = NSStackView(); row.orientation = .horizontal; row.spacing = 8
                row.distribution = .equalSpacing
                row.widthAnchor.constraint(equalToConstant: 412).isActive = true
                for (presetIndex, preset) in presets.enumerated() {
                    let button = ScalingPresetButton(preset: preset, index: presetIndex, count: presets.count,
                        selected: preset.mode == section.display.currentMode,
                        enabled: section.explanation == nil && !switching && preset.mode.isSelectable)
                    button.target = self; button.action = #selector(activate(_:))
                    actions[ObjectIdentifier(button)] = { onSelect(section.display, preset.mode) }
                    row.addArrangedSubview(button)
                }
                stack.addArrangedSubview(row)
                if presets.count > 1 {
                    let ends = NSView()
                    let larger = label("Larger Text", size: 11, secondary: true)
                    let more = label("More Space", size: 11, secondary: true)
                    more.alignment = .right
                    for text in [larger, more] { ends.addSubview(text); text.translatesAutoresizingMaskIntoConstraints = false }
                    NSLayoutConstraint.activate([
                        ends.widthAnchor.constraint(equalToConstant: 412), ends.heightAnchor.constraint(equalToConstant: 16),
                        larger.leadingAnchor.constraint(equalTo: ends.leadingAnchor), larger.centerYAnchor.constraint(equalTo: ends.centerYAnchor),
                        more.trailingAnchor.constraint(equalTo: ends.trailingAnchor), more.centerYAnchor.constraint(equalTo: ends.centerYAnchor),
                        larger.widthAnchor.constraint(equalToConstant: 120), more.widthAnchor.constraint(equalToConstant: 120)
                    ])
                    stack.addArrangedSubview(ends)
                }
            }
        }
        if let notice { stack.addArrangedSubview(label(notice, size: 11, secondary: true)) }
        stack.addArrangedSubview(separator())
        let advanced = NSButton(title: "All resolutions…", target: self, action: #selector(activate(_:)))
        advanced.bezelStyle = .rounded; advanced.controlSize = .small
        actions[ObjectIdentifier(advanced)] = { onAdvanced(advanced) }
        let quit = NSButton(title: "Quit", target: self, action: #selector(activate(_:)))
        quit.bezelStyle = .rounded; quit.controlSize = .small
        actions[ObjectIdentifier(quit)] = onQuit
        let footer = NSStackView(views: [advanced, NSView(), quit])
        footer.orientation = .horizontal
        footer.widthAnchor.constraint(equalToConstant: 412).isActive = true
        stack.addArrangedSubview(footer)

        let document = ScalingDocumentView()
        document.addSubview(stack); stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: document.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: document.trailingAnchor, constant: -20),
            stack.topAnchor.constraint(equalTo: document.topAnchor, constant: 20),
            stack.bottomAnchor.constraint(equalTo: document.bottomAnchor, constant: -20),
            document.widthAnchor.constraint(equalToConstant: 452)
        ])
        document.layoutSubtreeIfNeeded()
        let height = stack.fittingSize.height + 40
        document.setFrameSize(NSSize(width: 452, height: height))
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 452, height: min(580, height)))
        scroll.drawsBackground = true; scroll.backgroundColor = .windowBackgroundColor
        scroll.hasVerticalScroller = height > 580
        scroll.autohidesScrollers = true; scroll.documentView = document
        view = scroll
        preferredContentSize = scroll.frame.size
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    @objc private func activate(_ sender: NSButton) { actions[ObjectIdentifier(sender)]?() }
    private func label(_ text: String, size: CGFloat, secondary: Bool = false) -> NSTextField {
        let result = NSTextField(wrappingLabelWithString: text)
        result.font = .systemFont(ofSize: size)
        result.textColor = secondary ? .secondaryLabelColor : .labelColor
        result.widthAnchor.constraint(lessThanOrEqualToConstant: 412).isActive = true
        return result
    }
    private func separator() -> NSBox {
        let line = NSBox(); line.boxType = .separator
        line.widthAnchor.constraint(equalToConstant: 412).isActive = true
        return line
    }
}
