import Foundation

public struct ScalingPreset {
    public let mode: DisplayMode
    public let isDefault: Bool
    public let accessibilityLabel: String
}

public enum ScalingPresets {
    public static func options(for display: DisplaySnapshot) -> [ScalingPreset] {
        guard (display.isActive || display.isMirrored), let current = display.currentMode,
              current.width > 0, current.height > 0 else { return [] }
        let aspect = Double(current.width) / Double(current.height)
        var candidates = display.modes.filter {
            $0.isSelectable && abs(Double($0.width) / Double($0.height) / aspect - 1) < 0.025
        }
        let flaggedDefault = candidates.filter { $0.ioFlags & 0x4 != 0 }.sorted {
            if $0.isHiDPI != $1.isHiDPI { return $0.isHiDPI }
            let a = refreshDistance($0.refreshRate, current.refreshRate)
            let b = refreshDistance($1.refreshRate, current.refreshRate)
            return a == b ? $0.id < $1.id : a < b
        }.first
        if let flaggedDefault, let profile = knownProfile(candidates: candidates, current: current,
                                                         systemDefault: flaggedDefault, builtin: display.isBuiltin) {
            return profile.enumerated().map { index, mode in
                let isDefault = mode.width == flaggedDefault.width && mode.height == flaggedDefault.height
                let label = isDefault ? "Default" : index == 0 ? "Larger Text" : index == profile.count - 1 ? "More Space" : "Text size \(index + 1)"
                return ScalingPreset(mode: mode, isDefault: isDefault, accessibilityLabel: label)
            }
        }
        // Preserve the largest available logical size as well as HiDPI choices.
        let maximum = candidates.max { a, b in
            if a.width != b.width { return a.width < b.width }
            return a.height < b.height
        }
        if candidates.contains(where: \.isHiDPI) {
            candidates = candidates.filter { $0.isHiDPI || $0 == current || $0 == flaggedDefault || $0 == maximum }
        }
        candidates.append(current)
        let groups = Dictionary(grouping: candidates, by: { "\($0.width)x\($0.height)" })
        let sizes = groups.values.compactMap { variants -> DisplayMode? in
            if variants.contains(current) { return current }
            if let flaggedDefault, variants.contains(flaggedDefault) { return flaggedDefault }
            return variants.sorted {
                if $0.isHiDPI != $1.isHiDPI { return $0.isHiDPI }
                let a = refreshDistance($0.refreshRate, current.refreshRate)
                let b = refreshDistance($1.refreshRate, current.refreshRate)
                if a != b { return a < b }
                return $0.id < $1.id
            }.first
        }
        let systemDefault = flaggedDefault.flatMap { flagged in
            sizes.first { $0.width == flagged.width && $0.height == flagged.height }
        }
        let anchor = systemDefault ?? current
        func distance(_ mode: DisplayMode) -> Double { abs(log(Double(mode.width) / Double(anchor.width))) }
        var chosen = Array(sizes.sorted {
            let a = distance($0), b = distance($1)
            return a == b ? $0.width < $1.width : a < b
        }.prefix(5))
        // The active size and any positively identified system default stay visible.
        let maximumSize = maximum.flatMap { highest in sizes.first { $0.width == highest.width && $0.height == highest.height } }
        for required in [Optional(current), systemDefault, maximumSize].compactMap({ $0 }) where !chosen.contains(required) {
            if chosen.count == 5,
               let index = chosen.indices.filter({ chosen[$0] != current && chosen[$0] != systemDefault && chosen[$0] != maximumSize })
                .max(by: { distance(chosen[$0]) < distance(chosen[$1]) }) { chosen.remove(at: index) }
            chosen.append(required)
        }
        chosen.sort { $0.width == $1.width ? $0.height < $1.height : $0.width < $1.width }
        return chosen.enumerated().map { index, mode in
            let isDefault = mode == systemDefault
            let label = isDefault ? "Default" : chosen.count == 1 ? "Current size" :
                index == 0 ? "Larger Text" : index == chosen.count - 1 ? "More Space" : "Text size \(index + 1)"
            return ScalingPreset(mode: mode, isDefault: isDefault, accessibilityLabel: label)
        }
    }

    private struct Profile {
        let builtin: Bool
        let defaultSize: (Int, Int)
        let sizes: [(Int, Int)]
    }

    // Profiles describe observed System Settings choices, not a macOS API guarantee.
    // A profile is usable only when its default and every listed size are present.
    private static let profiles: [Profile] = [
        Profile(builtin: true, defaultSize: (1470, 956), sizes: [(1024, 666), (1280, 832), (1470, 956), (1710, 1112)]),
        Profile(builtin: true, defaultSize: (1710, 1107), sizes: [(1024, 663), (1280, 828), (1440, 932), (1710, 1107), (1920, 1243)]),
        Profile(builtin: true, defaultSize: (1512, 982), sizes: [(1024, 665), (1147, 745), (1352, 878), (1512, 982), (1800, 1169)]),
        Profile(builtin: true, defaultSize: (1728, 1117), sizes: [(1168, 755), (1312, 848), (1496, 967), (1728, 1117), (2056, 1329)]),
        Profile(builtin: true, defaultSize: (1440, 900), sizes: [(1024, 640), (1280, 800), (1440, 900), (1680, 1050)]),
        Profile(builtin: true, defaultSize: (2240, 1260), sizes: [(1280, 720), (1600, 900), (1920, 1080), (2240, 1260), (2560, 1440)]),
        Profile(builtin: false, defaultSize: (2560, 1440), sizes: [(1600, 900), (2048, 1152), (2560, 1440), (2880, 1620), (3200, 1800)]),
        Profile(builtin: false, defaultSize: (3008, 1692), sizes: [(1920, 1080), (2560, 1440), (3008, 1692), (3200, 1800), (3360, 1890)]),
        Profile(builtin: false, defaultSize: (1920, 1080), sizes: [(1920, 1080), (2560, 1440), (3008, 1692), (3360, 1890), (3840, 2160)])
    ]

    private static func knownProfile(candidates: [DisplayMode], current: DisplayMode,
                                     systemDefault: DisplayMode, builtin: Bool) -> [DisplayMode]? {
        for profile in profiles where profile.builtin == builtin &&
            systemDefault.width == profile.defaultSize.0 && systemDefault.height == profile.defaultSize.1 {
            // A different aspect or an advanced current mode must remain accessible.
            guard profile.sizes.contains(where: { $0.0 == current.width && abs($0.1 - current.height) <= 2 }) else { continue }
            var result: [DisplayMode] = []
            for size in profile.sizes {
                let variants = candidates.filter { $0.width == size.0 && abs($0.height - size.1) <= 2 }
                guard let selected = variants.sorted(by: { a, b in
                    if (a == current) != (b == current) { return a == current }
                    if (a == systemDefault) != (b == systemDefault) { return a == systemDefault }
                    if a.isHiDPI != b.isHiDPI { return a.isHiDPI }
                    let da = refreshDistance(a.refreshRate, current.refreshRate)
                    let db = refreshDistance(b.refreshRate, current.refreshRate)
                    return da == db ? a.id < b.id : da < db
                }).first else { result.removeAll(); break }
                result.append(selected)
            }
            if result.count == profile.sizes.count { return result }
        }
        return nil
    }

    private static func refreshDistance(_ rate: Double, _ current: Double) -> Double {
        if rate == current { return 0 }
        if rate <= 0 || current <= 0 { return .greatestFiniteMagnitude }
        return abs(rate - current)
    }
}
