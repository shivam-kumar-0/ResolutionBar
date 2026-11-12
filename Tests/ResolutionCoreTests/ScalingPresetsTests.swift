import Testing
@testable import ResolutionCore


private func scalingMode(_ id: UInt32 = 1, width: Int = 1920, hz: Double = 60, hidpi: Bool = false) -> DisplayMode {
    DisplayMode(id: id, width: width, height: width * 9 / 16,
                pixelWidth: hidpi ? width * 2 : width,
                pixelHeight: (hidpi ? width * 2 : width) * 9 / 16, refreshRate: hz)
}

struct ScalingPresetsTests {
    @Test func manyVariantsBecomeAtMostFiveDistinctSizesWithCurrentVisible() {
        var modes: [DisplayMode] = []
        for index in 1...14 {
            modes.append(scalingMode(UInt32(index), width: 800 + index * 160, hz: 60, hidpi: true))
            modes.append(scalingMode(UInt32(index + 100), width: 800 + index * 160, hz: 120, hidpi: true))
        }
        let current = modes[12]
        let options = ScalingPresets.options(for: display(current: current, modes: modes))
        #expect(options.count == 5)
        #expect(Set(options.map { $0.mode.width }).count == 5)
        #expect(options.contains { $0.mode == current })
        #expect(options.allSatisfy { $0.mode.isHiDPI && $0.mode.refreshRate == 60 })
        #expect(options.map { $0.mode.width } == options.map { $0.mode.width }.sorted())
    }

    @Test func macOSDefaultFlagIsPreservedWithoutInventingDefault() {
        var systemDefault = scalingMode(5, width: 1600, hidpi: true)
        systemDefault.ioFlags = 0x4
        let modes = [scalingMode(1, width: 1280, hidpi: true), systemDefault,
                     scalingMode(2, width: 1920, hidpi: true)]
        let options = ScalingPresets.options(for: display(current: modes[0], modes: modes))
        #expect(options.filter { $0.isDefault }.map { $0.mode.id } == [5])
        #expect(options.first?.accessibilityLabel == "Larger Text")
        #expect(options.last?.accessibilityLabel == "More Space")
        let unflagged = ScalingPresets.options(for: display())
        #expect(unflagged.allSatisfy { !$0.isDefault })
    }

    @Test func prefersHiDPIAndRetainsAnActiveStandardDensityMode() {
        let current = scalingMode(1)
        let modes = [current, scalingMode(2, hidpi: true), scalingMode(3, width: 2560, hidpi: true)]
        let options = ScalingPresets.options(for: display(current: current, modes: modes))
        #expect(options.contains { $0.mode == current })
        #expect(options.contains { $0.mode.id == 3 })
        #expect(Set(options.map { $0.mode.width }).count == options.count)
    }

    @Test func mirroredMainDisplayProvidesPresetsAndUnreadableDoesNot() {
        var mirrored = display(); mirrored.isMirrored = true; mirrored.isMain = true
        #expect(!ScalingPresets.options(for: mirrored).isEmpty)
        #expect(ScalingPresets.options(for: display(current: nil)).isEmpty)
    }

    @Test func explicitDefaultSurvivesCompetingRefreshAndDensityVariants() {
        var defaultMode = scalingMode(5, width: 1920, hz: 60, hidpi: true)
        defaultMode.ioFlags = 0x4
        let current = scalingMode(1, width: 2560, hz: 120, hidpi: true)
        let variants = [current, defaultMode, scalingMode(6, width: 1920, hz: 120, hidpi: true)]
        let options = ScalingPresets.options(for: display(current: current, modes: variants))
        #expect(options.contains { $0.isDefault && $0.mode.id == 5 })
        defaultMode.pixelWidth = defaultMode.width; defaultMode.pixelHeight = defaultMode.height
        let mixed = ScalingPresets.options(for: display(current: current, modes: [current, defaultMode]))
        #expect(mixed.contains { $0.isDefault && $0.mode.id == 5 })
    }
}

extension ScalingPresetsTests {
    @Test func fourKExternalPresetsSpanDefaultThroughNative() {
        let widths = [960, 1024, 1152, 1280, 1504, 1600, 1680, 1920, 2048, 2304, 2560, 3008, 3200, 3360]
        var modes = widths.enumerated().map { scalingMode(UInt32($0.offset + 1), width: $0.element, hz: 30, hidpi: true) }
        let defaultIndex = widths.firstIndex(of: 1920)!
        modes[defaultIndex].ioFlags = 7
        let current = modes[defaultIndex]
        modes.append(scalingMode(99, width: 3840, hz: 30))
        var external = display(current: current, modes: modes)
        external.isBuiltin = false
        let options = ScalingPresets.options(for: external)
        #expect(options.map(\.mode.width) == [1920, 2560, 3008, 3360, 3840])
        #expect(options.last?.mode.isHiDPI == false)
    }

    @Test func builtInThirteenInchModesRemainCompact() {
        let sizes = [(1024, 666), (1280, 832), (1470, 956), (1710, 1112)]
        let widths = sizes.map(\.0)
        var modes = sizes.enumerated().map { index, size in
            DisplayMode(id: UInt32(index + 1), width: size.0, height: size.1, pixelWidth: size.0 * 2, pixelHeight: size.1 * 2)
        }
        modes[2].ioFlags = 7
        var builtin = display(current: modes[2], modes: modes)
        builtin.isBuiltin = true
        #expect(ScalingPresets.options(for: builtin).map(\.mode.width) == widths)
    }

    @Test func builtInSixteenInchModesRemainCompact() {
        let sizes = [(1168, 755), (1312, 848), (1496, 967), (1728, 1117), (2056, 1329)]
        let widths = sizes.map(\.0)
        var modes = sizes.enumerated().map { index, size in
            DisplayMode(id: UInt32(index + 1), width: size.0, height: size.1, pixelWidth: size.0 * 2, pixelHeight: size.1 * 2)
        }
        modes[3].ioFlags = 7
        var builtin = display(current: modes[3], modes: modes)
        builtin.isBuiltin = true
        #expect(ScalingPresets.options(for: builtin).map(\.mode.width) == widths)
    }
}

extension ScalingPresetsTests {
    @Test func unknownExternalIncludesMaximumEvenWhenHiDPIExists() {
        var defaultMode = scalingMode(1, width: 1600, hidpi: true)
        defaultMode.ioFlags = 7
        let sizes = [1200, 1400, 1800, 2000, 2200, 2400].enumerated().map { scalingMode(UInt32($0.offset + 2), width: $0.element, hidpi: true) }
        let maximum = scalingMode(100, width: 3200)
        var external = display(current: defaultMode, modes: [defaultMode] + sizes + [maximum])
        external.isBuiltin = false
        let options = ScalingPresets.options(for: external)
        #expect(options.count <= 5)
        #expect(options.contains { $0.mode == maximum })
        #expect(options.contains { $0.mode == defaultMode })
    }

    @Test func studioDisplayProfileSelectsDocumentedSizes() {
        let sizes = [(1600,900), (2048,1152), (2560,1440), (2880,1620), (3200,1800)]
        var modes = sizes.enumerated().map { index, size in
            DisplayMode(id: UInt32(index + 1), width: size.0, height: size.1, pixelWidth: size.0 * 2, pixelHeight: size.1 * 2)
        }
        modes[2].ioFlags = 7
        modes.append(scalingMode(20, width: 5120))
        modes.append(scalingMode(21, width: 2304, hidpi: true))
        var studio = display(current: modes[2], modes: modes)
        studio.isBuiltin = false
        #expect(ScalingPresets.options(for: studio).map(\.mode.width) == sizes.map(\.0))
    }
}
