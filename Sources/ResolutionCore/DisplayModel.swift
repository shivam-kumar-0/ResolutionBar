import Foundation

public struct DisplayMode: Hashable, Codable {
    public var id: UInt32
    public var width: Int
    public var height: Int
    public var pixelWidth: Int
    public var pixelHeight: Int
    public var refreshRate: Double
    public var usable: Bool
    public var interlaced: Bool
    public var stretched: Bool
    public var ioFlags: UInt32

    public init(id: UInt32, width: Int, height: Int, pixelWidth: Int? = nil,
                pixelHeight: Int? = nil, refreshRate: Double = 60, usable: Bool = true,
                interlaced: Bool = false, stretched: Bool = false, ioFlags: UInt32 = 0) {
        self.id = id; self.width = width; self.height = height
        self.pixelWidth = pixelWidth ?? width; self.pixelHeight = pixelHeight ?? height
        self.refreshRate = refreshRate; self.usable = usable
        self.interlaced = interlaced; self.stretched = stretched; self.ioFlags = ioFlags
    }

    public var isHiDPI: Bool { pixelWidth > width || pixelHeight > height }
    public var isSelectable: Bool { usable && !interlaced && !stretched && width > 0 && height > 0 }
    public var title: String {
        var parts = ["\(width) × \(height)", isHiDPI ? "HiDPI" : "1×"]
        if refreshRate.isFinite && refreshRate > 0 {
            let rate = String(format: "%.2f", locale: Locale(identifier: "en_US_POSIX"), refreshRate)
                .replacingOccurrences(of: #"\.?0+$"#, with: "", options: .regularExpression)
            parts.append("\(rate) Hz")
        }
        return parts.joined(separator: " · ")
    }
}

public struct DisplayFrame: Hashable, Codable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double
    public init(x: Double = 0, y: Double = 0, width: Double = 1920, height: Double = 1080) {
        self.x = x; self.y = y; self.width = width; self.height = height
    }
}

public struct DisplaySnapshot: Equatable, Codable {
    public var id: UInt32
    public var identity: String
    public var generation: String
    public var name: String
    public var isActive: Bool
    public var isMain: Bool
    public var isBuiltin: Bool
    public var isMirrored: Bool
    public var mirrorPrimary: UInt32?
    public var frame: DisplayFrame
    public var currentMode: DisplayMode?
    public var modes: [DisplayMode]

    public init(id: UInt32, identity: String, generation: String, name: String,
                isActive: Bool = true, isMain: Bool = false, isBuiltin: Bool = false,
                isMirrored: Bool = false, mirrorPrimary: UInt32? = nil,
                frame: DisplayFrame = DisplayFrame(), currentMode: DisplayMode?, modes: [DisplayMode]) {
        self.id = id; self.identity = identity; self.generation = generation; self.name = name
        self.isActive = isActive; self.isMain = isMain; self.isBuiltin = isBuiltin
        self.isMirrored = isMirrored; self.mirrorPrimary = mirrorPrimary; self.frame = frame
        self.currentMode = currentMode; self.modes = modes
    }

    public func sameConnection(as other: DisplaySnapshot) -> Bool {
        id == other.id && identity == other.identity && generation == other.generation
    }
}

public struct DisplayMenuSection {
    public let display: DisplaySnapshot
    public let title: String
    public let modes: [DisplayMode]
    public let explanation: String?
}

public enum DisplayMenu {
    public static func sections(_ displays: [DisplaySnapshot]) -> [DisplayMenuSection] {
        let active = displays.filter(\.isActive).sorted {
            if $0.isMain != $1.isMain { return $0.isMain }
            if $0.isBuiltin != $1.isBuiltin { return $0.isBuiltin }
            if $0.name != $1.name { return $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            return $0.id < $1.id
        }
        let counts = Dictionary(grouping: active, by: \.name).mapValues(\.count)
        return active.enumerated().map { index, display in
            var title = display.name
            if counts[display.name, default: 0] > 1 { title += " (Display \(index + 1))" }
            if display.isMain { title += " · Main" }
            if display.isBuiltin { title += " · Built-in" }
            if display.isMirrored {
                return DisplayMenuSection(display: display, title: title + " · Mirrored",
                    modes: [], explanation: "Resolution switching is unavailable while mirroring.")
            }
            var candidates = display.modes.filter(\.isSelectable)
            if let current = display.currentMode { candidates.append(current) }
            let modes = Array(Set(candidates)).sorted {
                if $0.width != $1.width { return $0.width < $1.width }
                if $0.height != $1.height { return $0.height < $1.height }
                if $0.isHiDPI != $1.isHiDPI { return $0.isHiDPI }
                if $0.refreshRate != $1.refreshRate { return $0.refreshRate < $1.refreshRate }
                return $0.id < $1.id
            }
            return DisplayMenuSection(display: display, title: title, modes: modes,
                explanation: modes.isEmpty ? "No display modes are available for this display." : nil)
        }
    }
}
