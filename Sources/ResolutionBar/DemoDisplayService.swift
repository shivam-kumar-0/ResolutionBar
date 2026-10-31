import Foundation
import ResolutionCore

/// Explicit --demo mode: completely separate from Core Graphics mutation.
@MainActor final class DemoDisplayService: DisplayService {
    private var displays: [DisplaySnapshot]
    init(scenario: String) {
        let modes = [
            DisplayMode(id: 1, width: 1440, height: 900, pixelWidth: 2880, pixelHeight: 1800),
            DisplayMode(id: 2, width: 1680, height: 1050, pixelWidth: 3360, pixelHeight: 2100, ioFlags: 0x4),
            DisplayMode(id: 3, width: 1920, height: 1200, pixelWidth: 3840, pixelHeight: 2400),
            DisplayMode(id: 4, width: 1920, height: 1200)
        ]
        var first = DisplaySnapshot(id: 1, identity: "demo-1", generation: "demo-connection-1",
            name: "Built-in Retina Display", isMain: true, isBuiltin: true,
            currentMode: modes[1], modes: modes)
        var second = DisplaySnapshot(id: 2, identity: "demo-2", generation: "demo-connection-2",
            name: "Studio Display", frame: DisplayFrame(x: 1440), currentMode: modes[2], modes: modes)
        switch scenario {
        case "multiple": displays = [first, second]
        case "mirrored":
            first.isMirrored = true; second.isMirrored = true; second.mirrorPrimary = 1
            second.isActive = false; displays = [first, second]
        case "none": displays = []
        default: displays = [first]
        }
    }
    func snapshot() throws -> [DisplaySnapshot] { displays }
    func apply(display expected: DisplaySnapshot, mode: DisplayMode, scope: ChangeScope) throws {
        guard let index = displays.firstIndex(where: { $0.sameConnection(as: expected) }),
              displays[index].currentMode == expected.currentMode,
              displays[index].modes.contains(mode) else { throw SwitchFailure("Demo display changed") }
        displays[index].currentMode = mode
        displays[index].frame.width = Double(mode.width)
        displays[index].frame.height = Double(mode.height)
    }
}
