import AppKit
import ResolutionCore

@MainActor func run() {
    let arguments = Array(CommandLine.arguments.dropFirst())
    let application = NSApplication.shared
    application.setActivationPolicy(.accessory)
    if arguments.contains("--diagnose") {
        do {
            let displays = try NativeDisplayService().snapshot()
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            print(String(decoding: try encoder.encode(displays), as: UTF8.self))
        } catch { fputs("\(error.localizedDescription)\n", stderr); exit(1) }
        return
    }
    if arguments.contains("--smoke-test") {
        do {
            for scenario in ["single", "multiple", "mirrored", "none"] {
                let service = DemoDisplayService(scenario: scenario)
                let controller = AppController(service: service, demo: true)
                controller.rebuildMenu()
                guard controller.menu.items.contains(where: { $0.title == "Quit ResolutionBar" }) else {
                    throw SwitchFailure("Missing Quit action in \(scenario) menu")
                }
                let modeItems = controller.menu.items.filter { $0.action != nil && $0.title.contains("×") }
                let expected = scenario == "multiple" ? 8 : scenario == "single" ? 4 : 0
                guard modeItems.count == expected else { throw SwitchFailure("Unexpected \(scenario) mode count") }
                print("PASS native menu: \(scenario) (\(modeItems.count) resolution actions)")
                let content = try controller.scalingContent()
                let presets = descendants(content.view).compactMap { $0 as? ScalingPresetButton }
                let presetCount = scenario == "multiple" ? 6 : scenario == "single" ? 3 : 0
                guard presets.count == presetCount, content.preferredContentSize.width == 452,
                      content.preferredContentSize.height > 0, content.preferredContentSize.height <= 580 else {
                    throw SwitchFailure("Invalid compact picker layout in \(scenario)")
                }
                guard let document = (content.view as? NSScrollView)?.documentView,
                      let quit = descendants(document).compactMap({ $0 as? NSButton }).first(where: { $0.title == "Quit" }) else {
                    throw SwitchFailure("Picker Quit button is missing in \(scenario)")
                }
                document.layoutSubtreeIfNeeded()
                let quitRect = quit.convert(quit.bounds, to: document)
                guard quitRect.minY >= 0, quitRect.maxY <= document.bounds.height + 1 else {
                    throw SwitchFailure("Picker Quit button is outside its scrollable content in \(scenario): \(quitRect) in \(document.bounds)")
                }
                if let scroll = content.view as? NSScrollView,
                   document.bounds.height > scroll.contentSize.height + 1, !scroll.hasVerticalScroller {
                    throw SwitchFailure("Picker content exceeds its viewport without a scrollbar in \(scenario)")
                }
                print("PASS compact picker: \(scenario) (\(presets.count) presets, \(Int(content.preferredContentSize.height)) pt height)")
            }
            let loginService = DemoLaunchAtLoginService()
            let loginPreferences = DemoLaunchNudgePreferences()
            let loginController = AppController(service: DemoDisplayService(scenario: "single"), demo: true,
                                                loginService: loginService, loginPreferences: loginPreferences)
            let suggestionView = try loginController.scalingContent().view
            let suggestionButtons = descendants(suggestionView).compactMap { $0 as? NSButton }
            guard let dismiss = suggestionButtons.first(where: { $0.title == "Not Now" }),
                  loginService.status == .disabled else { throw SwitchFailure("Initial login suggestion is missing") }
            dismiss.performClick(nil)
            var settingsView = try loginController.scalingContent().view
            guard !descendants(settingsView).compactMap({ $0 as? NSButton }).contains(where: { $0.title == "Not Now" }),
                  let loginToggle = descendants(settingsView).compactMap({ $0 as? NSButton }).first(where: { $0.title == "Open at Login" }) else {
                throw SwitchFailure("Login suggestion did not dismiss or setting is missing")
            }
            loginToggle.performClick(nil)
            guard loginService.status == .enabled else { throw SwitchFailure("Login setting did not enable the demo service") }
            settingsView = try loginController.scalingContent().view
            guard let enabledToggle = descendants(settingsView).compactMap({ $0 as? NSButton }).first(where: { $0.title == "Open at Login" }),
                  enabledToggle.state == .on else { throw SwitchFailure("Login setting did not show as enabled") }
            enabledToggle.performClick(nil)
            guard loginService.status == .disabled else { throw SwitchFailure("Login setting did not disable the demo service") }
            settingsView = try loginController.scalingContent().view
            guard !descendants(settingsView).compactMap({ $0 as? NSButton }).contains(where: { $0.title == "Not Now" }) else {
                throw SwitchFailure("Login suggestion returned after an explicit choice")
            }
            let nudgeService = DemoLaunchAtLoginService()
            let nudgeController = AppController(service: DemoDisplayService(scenario: "single"), demo: true,
                                                loginService: nudgeService, loginPreferences: DemoLaunchNudgePreferences())
            let nudgeView = try nudgeController.scalingContent().view
            guard let enableFromNudge = descendants(nudgeView).compactMap({ $0 as? NSButton }).first(where: { $0.title == "Open at Login" }) else {
                throw SwitchFailure("Login suggestion's enable action is missing")
            }
            enableFromNudge.performClick(nil)
            guard nudgeService.status == .enabled else { throw SwitchFailure("Login suggestion did not enable the demo service") }
            loginService.status = .requiresApproval
            settingsView = try loginController.scalingContent().view
            guard let approval = descendants(settingsView).compactMap({ $0 as? NSButton }).first(where: { $0.title == "Open Login Items…" }),
                  let pending = descendants(settingsView).compactMap({ $0 as? NSButton }).first(where: { $0.title == "Open at Login" }),
                  pending.state == .mixed else { throw SwitchFailure("Pending login approval is not shown") }
            approval.performClick(nil)
            guard loginService.didOpenSettings else { throw SwitchFailure("Login settings action did not reach the demo service") }
            print("PASS login suggestion, dismissal, enable, disable and approval UI (demo only)")
            let service = DemoDisplayService(scenario: "single")
            let controller = AppController(service: service, demo: true)
            for action in ["Revert", "Keep", "Close"] {
                let content = try controller.scalingContent()
                let buttons = descendants(content.view).compactMap { $0 as? ScalingPresetButton }
                let current = try service.snapshot()[0].currentMode
                guard let choice = buttons.first(where: { $0.preset.mode != current && $0.isEnabled }) else {
                    throw SwitchFailure("Missing alternative preset")
                }
                choice.performClick(nil)
                RunLoop.main.run(until: Date().addingTimeInterval(0.1))
                guard let panel = application.windows.first(where: { $0.title == "Keep this resolution?" && $0.isVisible }),
                      let panelContent = panel.contentView else { throw SwitchFailure("Confirmation panel did not open") }
                let controls = descendants(panelContent).compactMap { $0 as? NSButton }
                guard let revert = controls.first(where: { $0.title == "Revert" }), revert.keyEquivalent == "\u{1b}" else {
                    throw SwitchFailure("Escape is not bound to Revert")
                }
                if action == "Close" { panel.performClose(nil) }
                else {
                    guard let button = controls.first(where: { $0.title == action }) else { throw SwitchFailure("Missing \(action) action") }
                    button.performClick(nil)
                }
                guard !panel.isVisible else { throw SwitchFailure("Confirmation did not dismiss after \(action)") }
                let after = try service.snapshot()[0].currentMode
                guard after == (action == "Keep" ? choice.preset.mode : current) else {
                    throw SwitchFailure("Incorrect demo mode after \(action)")
                }
                print("PASS preset → confirmation → \(action)")
            }
        } catch { fputs("\(error.localizedDescription)\n", stderr); exit(1) }
        return
    }
    if let index = arguments.firstIndex(of: "--render-demo"), arguments.indices.contains(index + 1) {
        do {
            let controller = AppController(service: DemoDisplayService(scenario: "single"), demo: true)
            defer { withExtendedLifetime(controller) {} }
            let content = try controller.scalingContent()
            content.view.layoutSubtreeIfNeeded()
            guard let bitmap = content.view.bitmapImageRepForCachingDisplay(in: content.view.bounds) else {
                throw SwitchFailure("Could not render the compact picker")
            }
            content.view.cacheDisplay(in: content.view.bounds, to: bitmap)
            guard let png = bitmap.representation(using: .png, properties: [:]) else { throw SwitchFailure("PNG encoding failed") }
            try png.write(to: URL(fileURLWithPath: arguments[index + 1]))
        } catch { fputs("\(error.localizedDescription)\n", stderr); exit(1) }
        return
    }
    let demo = arguments.contains("--demo")
    let scenario = arguments.first(where: { ["single", "multiple", "mirrored", "none"].contains($0) }) ?? "single"
    let service: DisplayService = demo ? DemoDisplayService(scenario: scenario) : NativeDisplayService()
    let controller = AppController(service: service, demo: demo)
    application.delegate = controller
    withExtendedLifetime(controller) { application.run() }
}

@MainActor func descendants(_ view: NSView) -> [NSView] {
    view.subviews.flatMap { [$0] + descendants($0) }
}

MainActor.assumeIsolated { run() }
