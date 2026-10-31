import AppKit
import CoreGraphics
import ColorSync
import ResolutionCore

private let reconfigurationCallback: CGDisplayReconfigurationCallBack = { id, flags, context in
    guard let context else { return }
    let service = Unmanaged<NativeDisplayService>.fromOpaque(context).takeUnretainedValue()
    // Invalidate immediately, even if main-queue refresh is still waiting to run.
    if flags.contains(.removeFlag) || flags.contains(.addFlag) { service.connections.invalidate(id: id) }
    // Never reconfigure inside a Core Graphics callback. Some callbacks are synchronous.
    DispatchQueue.main.async { [weak service] in service?.configurationChanged(id: id, flags: flags) }
}

@MainActor final class NativeDisplayService: DisplayService {
    var onChange: (() -> Void)?
    nonisolated let connections = ConnectionLedger()
    private var observing = false

    func startObserving() throws {
        let result = CGDisplayRegisterReconfigurationCallback(reconfigurationCallback,
            Unmanaged.passUnretained(self).toOpaque())
        guard result == .success else { throw failure("Automatic display refresh could not start", result) }
        observing = true
    }

    func stopObserving() {
        if observing {
            CGDisplayRemoveReconfigurationCallback(reconfigurationCallback, Unmanaged.passUnretained(self).toOpaque())
            observing = false
        }
    }

    func configurationChanged(id: UInt32, flags: CGDisplayChangeSummaryFlags) {
        if !flags.contains(.beginConfigurationFlag) { onChange?() }
    }

    func snapshot() throws -> [DisplaySnapshot] {
        var count: UInt32 = 0
        var result = CGGetOnlineDisplayList(0, nil, &count)
        guard result == .success else { throw failure("Connected displays could not be read", result) }
        var ids = [CGDirectDisplayID](repeating: 0, count: max(16, Int(count) + 8))
        result = CGGetOnlineDisplayList(UInt32(ids.count), &ids, &count)
        guard result == .success else { throw failure("Connected displays changed while being read. Try again", result) }
        ids = Array(ids.prefix(Int(count)))
        let screens = NSScreen.screens
        var snapshots: [DisplaySnapshot] = []
        for id in ids {
            let identity: String
            var identityReliable = true
            if let uuid = CGDisplayCreateUUIDFromDisplayID(id) {
                identity = CFUUIDCreateString(nil, uuid.takeRetainedValue()) as String
            } else {
                identity = "\(CGDisplayVendorNumber(id))-\(CGDisplayModelNumber(id))-\(CGDisplaySerialNumber(id))"
                identityReliable = CGDisplaySerialNumber(id) != 0 && CGDisplayVendorNumber(id) != 0 && CGDisplayModelNumber(id) != 0
            }
            let screen = screens.first {
                ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == id
            }
            let builtin = CGDisplayIsBuiltin(id) != 0
            let name = screen?.localizedName ?? (builtin ? "Built-in display" : "External display")
            let bounds = CGDisplayBounds(id)
            let mirror = CGDisplayMirrorsDisplay(id)
            // Primary mirror displays can return a null mirror ID. Test membership too.
            let mirrored = CGDisplayIsInMirrorSet(id) != 0 || mirror != kCGNullDirectDisplay
            let current = CGDisplayCopyDisplayMode(id).map(Self.describe)
            snapshots.append(DisplaySnapshot(id: id, identity: identity,
                generation: connections.token(id: id, identity: identity), name: name,
                isActive: CGDisplayIsActive(id) != 0, isMain: CGDisplayIsMain(id) != 0,
                isBuiltin: builtin, isMirrored: mirrored,
                mirrorPrimary: mirror == kCGNullDirectDisplay ? nil : mirror,
                frame: DisplayFrame(x: bounds.origin.x, y: bounds.origin.y,
                                    width: bounds.width, height: bounds.height),
                currentMode: current, modes: nativeModes(id).map(Self.describe),
                unavailableReason: !identityReliable ? "Display identity is unavailable; switching is disabled." :
                    !observing ? "Display monitoring is unavailable; switching is disabled. Quit and reopen ResolutionBar to retry." : nil))
        }
        return snapshots
    }

    func apply(display expected: DisplaySnapshot, mode: DisplayMode, scope: ChangeScope) throws {
        // Repeat validation at the OS boundary; menu snapshots may already be stale.
        let displays = try snapshot()
        guard observing, let fresh = displays.first(where: { $0.sameConnection(as: expected) }),
              fresh.unavailableReason == nil, displays.filter({ $0.identity == fresh.identity }).count == 1,
              fresh.isActive, !fresh.isMirrored, fresh.currentMode == expected.currentMode else {
            throw SwitchFailure("The display connection or current resolution changed. Please choose again.")
        }
        guard let native = nativeModes(fresh.id).first(where: { Self.describe($0) == mode }) else {
            throw SwitchFailure("The requested resolution is no longer available on this display.")
        }
        var configuration: CGDisplayConfigRef?
        var result = CGBeginDisplayConfiguration(&configuration)
        guard result == .success, let configuration else { throw failure("A display change could not begin", result) }
        result = CGConfigureDisplayWithDisplayMode(configuration, fresh.id, native, nil)
        guard result == .success else {
            CGCancelDisplayConfiguration(configuration)
            throw failure("macOS rejected this resolution", result)
        }
        // Complete consumes the configuration even when it fails.
        result = CGCompleteDisplayConfiguration(configuration, scope == .permanent ? .permanently : .forAppOnly)
        guard result == .success else { throw failure("macOS could not apply the resolution", result) }
    }

    private func nativeModes(_ id: UInt32) -> [CGDisplayMode] {
        let options = [kCGDisplayShowDuplicateLowResolutionModes as String: true] as CFDictionary
        return CGDisplayCopyAllDisplayModes(id, options) as? [CGDisplayMode] ?? []
    }

    private static func describe(_ mode: CGDisplayMode) -> DisplayMode {
        let flags = mode.ioFlags
        // Public IOGraphicsTypes.h: interlaced=0x40, stretched=0x800.
        return DisplayMode(id: UInt32(bitPattern: mode.ioDisplayModeID), width: mode.width,
            height: mode.height, pixelWidth: mode.pixelWidth, pixelHeight: mode.pixelHeight,
            refreshRate: mode.refreshRate, usable: mode.isUsableForDesktopGUI(),
            interlaced: flags & 0x40 != 0, stretched: flags & 0x800 != 0, ioFlags: flags)
    }

    private func failure(_ message: String, _ error: CGError) -> SwitchFailure {
        SwitchFailure("\(message). Try again after leaving full-screen apps. (macOS error \(error.rawValue))")
    }
}
