import Foundation

public struct ScalingPreset {
    public let mode: DisplayMode
    public let isDefault: Bool
    public let accessibilityLabel: String
}

public enum ScalingPresets {
    public static func options(for display: DisplaySnapshot) -> [ScalingPreset] {
        guard display.isActive, !display.isMirrored, let current = display.currentMode,
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
        if candidates.contains(where: \.isHiDPI) {
            candidates = candidates.filter { $0.isHiDPI || $0 == current || $0 == flaggedDefault }
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
        for required in [Optional(current), systemDefault].compactMap({ $0 }) where !chosen.contains(required) {
            if chosen.count == 5,
               let index = chosen.indices.filter({ chosen[$0] != current && chosen[$0] != systemDefault })
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

    private static func refreshDistance(_ rate: Double, _ current: Double) -> Double {
        if rate == current { return 0 }
        if rate <= 0 || current <= 0 { return .greatestFiniteMagnitude }
        return abs(rate - current)
    }
}
