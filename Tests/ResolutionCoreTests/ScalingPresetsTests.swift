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

    @Test func mirrorsAndUnreadableDisplaysHaveNoPresets() {
        var mirrored = display(); mirrored.isMirrored = true
        #expect(ScalingPresets.options(for: mirrored).isEmpty)
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
