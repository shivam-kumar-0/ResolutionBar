import AppKit
import ResolutionCore

@MainActor private final class ModeChoice: NSObject {
    let display: DisplaySnapshot
    let mode: DisplayMode
    init(display: DisplaySnapshot, mode: DisplayMode) { self.display = display; self.mode = mode }
}

@MainActor final class AppController: NSObject, NSApplicationDelegate, NSMenuDelegate {
    let menu = NSMenu()
    private let service: DisplayService
    private let coordinator: SwitchCoordinator
    private let launchAtLogin: LaunchAtLoginCoordinator
    private let confirmation = ConfirmationWindow()
    private let popover = NSPopover()
    private var statusItem: NSStatusItem?
    private var timer: Timer?
    private var refreshWork: DispatchWorkItem?
    private var wakeObserver: NSObjectProtocol?
    private var notice: String?
    private let demo: Bool

    init(service: DisplayService, demo: Bool = false,
         loginService: LaunchAtLoginService? = nil, loginPreferences: LaunchNudgePreferences? = nil) {
        self.service = service; self.demo = demo
        let resolvedLoginService: LaunchAtLoginService = loginService ?? (demo ? DemoLaunchAtLoginService() : SystemLaunchAtLoginService())
        let resolvedPreferences: LaunchNudgePreferences = loginPreferences ?? (demo ? DemoLaunchNudgePreferences() : StoredLaunchNudgePreferences())
        launchAtLogin = LaunchAtLoginCoordinator(service: resolvedLoginService, preferences: resolvedPreferences)
        let clock = ContinuousClock()
        let start = clock.now
        coordinator = SwitchCoordinator(service: service, now: {
            let elapsed = start.duration(to: clock.now).components
            return Double(elapsed.seconds) + Double(elapsed.attoseconds) / 1e18
        })
        super.init()
        menu.delegate = self
        menu.autoenablesItems = false
        confirmation.onKeep = { [weak self] in self?.keep() }
        confirmation.onRevert = { [weak self] in self?.revert() }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem?.button?.image = NSImage(systemSymbolName: "display", accessibilityDescription: "ResolutionBar")
        statusItem?.button?.toolTip = demo ? "ResolutionBar Demo" : "ResolutionBar"
        statusItem?.button?.target = self
        statusItem?.button?.action = #selector(togglePopover)
        popover.behavior = .transient
        popover.animates = false
        if let native = service as? NativeDisplayService {
            native.onChange = { [weak self] in self?.scheduleRefresh() }
            do { try native.startObserving() } catch { notice = error.localizedDescription }
        }
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in MainActor.assumeIsolated { self?.handleWake() } }
        rebuildMenu()
        if ProcessInfo.processInfo.arguments.contains("--demo-open") {
            DispatchQueue.main.async { [weak self] in self?.statusItem?.button?.performClick(nil) }
        }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        do { try coordinator.tick(); _ = try coordinator.reconcile() }
        catch { notice = error.localizedDescription }
        synchronizeConfirmation()
        rebuildMenu()
    }

    func rebuildMenu() {
        menu.removeAllItems()
        if demo { addLabel("Demo — real displays are unchanged"); menu.addItem(.separator()) }
        do {
            let sections = DisplayMenu.sections(try service.snapshot())
            if sections.isEmpty { addLabel("No active displays found. Reopen this menu to retry.") }
            for (index, section) in sections.enumerated() {
                if index > 0 { menu.addItem(.separator()) }
                addLabel(section.title)
                if let explanation = section.explanation {
                    if let current = section.display.currentMode { addLabel("Current: \(current.title)") }
                    addLabel(explanation)
                }
                for mode in section.modes {
                    let item = NSMenuItem(title: mode.title, action: #selector(selectMode(_:)), keyEquivalent: "")
                    item.target = self
                    item.representedObject = ModeChoice(display: section.display, mode: mode)
                    item.state = mode == section.display.currentMode ? .on : .off
                    item.isEnabled = mode.isSelectable && section.explanation == nil && coordinator.pending == nil && !coordinator.isBusy
                    item.toolTip = "Rendered at \(mode.pixelWidth) × \(mode.pixelHeight) pixels"
                    menu.addItem(item)
                }
            }
        } catch { addLabel(error.localizedDescription) }
        menu.addItem(.separator())
        if coordinator.pending != nil {
            addAction("Show resolution preview…", #selector(showPreview))
            addAction("Revert resolution", #selector(revertFromMenu))
        }
        if let message = notice ?? coordinator.notice { addLabel(message) }
        addAction("About ResolutionBar", #selector(about))
        addAction("Quit ResolutionBar", #selector(quit), key: "q")
    }

    @objc private func selectMode(_ sender: NSMenuItem) {
        guard let choice = sender.representedObject as? ModeChoice else { return }
        beginPreview(display: choice.display, mode: choice.mode)
    }

    private func beginPreview(display: DisplaySnapshot, mode: DisplayMode) {
        popover.performClose(nil)
        // Let native menu tracking finish before starting a synchronous OS change.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.notice = nil
            do {
                if try self.coordinator.select(display: display, mode: mode) {
                    self.showPreview()
                    self.startTimer()
                }
            } catch { self.report(error) }
            self.rebuildMenu()
        }
    }

    @objc private func togglePopover() {
        if popover.isShown { popover.performClose(nil); return }
        guard let button = statusItem?.button else { return }
        do {
            try coordinator.tick()
            _ = try coordinator.reconcile()
            let content = try scalingContent()
            popover.contentViewController = content
            popover.contentSize = content.preferredContentSize
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        } catch { report(error) }
        synchronizeConfirmation()
    }

    func scalingContent() throws -> ScalingPopoverController {
        ScalingPopoverController(displays: try service.snapshot(), notice: notice ?? coordinator.notice,
            demo: demo, switching: coordinator.pending != nil || coordinator.isBusy,
            loginStatus: launchAtLogin.status, showLoginSuggestion: launchAtLogin.shouldSuggest,
            onSelect: { [weak self] display, mode in self?.beginPreview(display: display, mode: mode) },
            onAdvanced: { [weak self] sender in
                guard let self else { return }
                self.rebuildMenu()
                self.menu.popUp(positioning: nil, at: NSPoint(x: 0, y: 0), in: sender)
            }, onEnableLogin: { [weak self] in self?.changeLaunchAtLogin(enabled: true) },
            onDismissLoginSuggestion: { [weak self] in
                self?.launchAtLogin.dismissSuggestion()
                self?.refreshOpenPopover()
            }, onToggleLogin: { [weak self] in
                guard let self else { return }
                self.changeLaunchAtLogin(enabled: self.launchAtLogin.status == .disabled)
            }, onOpenLoginSettings: { [weak self] in self?.launchAtLogin.openSettings() },
            onQuit: { NSApp.terminate(nil) })
    }

    private func changeLaunchAtLogin(enabled: Bool) {
        do {
            if enabled { try launchAtLogin.enable() } else { try launchAtLogin.disable() }
            notice = nil
        } catch {
            notice = "Could not change Open at Login: \(error.localizedDescription)"
        }
        refreshOpenPopover()
    }

    private func refreshOpenPopover() {
        guard popover.isShown, let content = try? scalingContent() else { return }
        popover.contentViewController = content
        popover.contentSize = content.preferredContentSize
    }

    @objc private func showPreview() {
        guard let change = coordinator.pending else { return }
        confirmation.show(change: change, seconds: coordinator.remainingSeconds, demo: demo)
    }

    private func startTimer() {
        timer?.invalidate()
        let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.timerFired() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func timerFired() {
        do { try coordinator.tick() } catch { report(error) }
        synchronizeConfirmation()
    }

    private func synchronizeConfirmation() {
        if coordinator.pending == nil {
            timer?.invalidate(); timer = nil
            confirmation.dismiss()
        } else { confirmation.update(seconds: coordinator.remainingSeconds) }
    }

    private func keep() {
        do { try coordinator.keep() } catch { report(error) }
        synchronizeConfirmation(); rebuildMenu()
    }

    private func revert() {
        do { try coordinator.revert() } catch { report(error) }
        synchronizeConfirmation(); rebuildMenu()
    }

    private func handleWake() { timerFired(); scheduleRefresh() }

    private func scheduleRefresh() {
        refreshWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            do { _ = try self.coordinator.reconcile() } catch { self.report(error) }
            self.synchronizeConfirmation()
            self.refreshOpenPopover()
            // Do not rebuild a menu currently tracking a click. Its next opening refreshes it.
        }
        refreshWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: work)
    }

    private func report(_ error: Error) {
        notice = error.localizedDescription
        confirmation.dismiss()
        let alert = NSAlert()
        alert.messageText = "The display change could not be completed"
        alert.informativeText = error.localizedDescription
        alert.addButton(withTitle: "OK")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    private func addLabel(_ title: String) {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        menu.addItem(item)
    }

    private func addAction(_ title: String, _ action: Selector, key: String = "") {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        menu.addItem(item)
    }

    @objc private func revertFromMenu() { DispatchQueue.main.async { [weak self] in self?.revert() } }
    @objc private func about() {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "ResolutionBar 0.1.0"
            alert.informativeText = "A small, offline menu bar utility. Choose a display resolution, then Keep or Revert within 15 seconds. HiDPI is Retina-style rendering; 1× is standard-density rendering. Mirrored groups are read-only in this version."
            alert.addButton(withTitle: "OK")
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
        }
    }
    @objc private func quit() { NSApp.terminate(nil) }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        do { try coordinator.revert() }
        catch { report(error) }
        return .terminateNow
    }

    func applicationWillTerminate(_ notification: Notification) {
        timer?.invalidate(); refreshWork?.cancel()
        (service as? NativeDisplayService)?.stopObserving()
        if let wakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver) }
    }
}
