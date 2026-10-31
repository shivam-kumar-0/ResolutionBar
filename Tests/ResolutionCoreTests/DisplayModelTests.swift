import Testing
@testable import ResolutionCore

func mode(_ id: UInt32 = 1, width: Int = 1920, hz: Double = 60, hidpi: Bool = false,
          usable: Bool = true, interlaced: Bool = false, stretched: Bool = false) -> DisplayMode {
    DisplayMode(id: id, width: width, height: 1080, pixelWidth: hidpi ? width * 2 : width,
                pixelHeight: hidpi ? 2160 : 1080, refreshRate: hz, usable: usable,
                interlaced: interlaced, stretched: stretched)
}

func display(_ id: UInt32 = 1, name: String = "Monitor", current: DisplayMode? = mode(),
             modes: [DisplayMode] = [mode(), mode(2, width: 2560)]) -> DisplaySnapshot {
    DisplaySnapshot(id: id, identity: "hardware-\(id)", generation: "connection-\(id)",
                    name: name, currentMode: current, modes: modes)
}

struct DisplayModelTests {
    @Test func testSingleDisplayHasDirectModeListAndCurrentMode() {
        let sections = DisplayMenu.sections([display()])
        #expect(sections.count == 1)
        #expect(sections.first?.modes.map(\.id) == [1, 2])
    }

    @Test func testDistinctHiDPIAndRefreshModesArePreserved() {
        let modes = [mode(), mode(2, hz: 120), mode(3, hidpi: true), mode()]
        let sections = DisplayMenu.sections([display(modes: modes)])
        #expect(sections.first?.modes.count == 3)
        #expect(mode(3, hidpi: true).title.contains("HiDPI"))
        #expect(mode(2, hz: 120).title.contains("120 Hz"))
    }

    @Test func testUnknownRefreshRateIsNotInvented() {
        #expect(!mode(hz: 0).title.contains("Hz"))
        #expect(mode(hz: 59.94).title.contains("59.94 Hz"))
    }

    @Test func testUnsafeModesAreFilteredButActualCurrentModeRemainsVisible() {
        let unsafe = mode(3, interlaced: true)
        let modes = [mode(), mode(2, usable: false), unsafe, mode(4, stretched: true)]
        let sections = DisplayMenu.sections([display(current: unsafe, modes: modes)])
        #expect(Set(sections.first?.modes.map(\.id) ?? []) == Set([1, 3]))
        #expect(!unsafe.isSelectable)
    }

    @Test func testCurrentModeOmittedByEnumerationIsIncluded() {
        #expect(DisplayMenu.sections([display(current: mode(99), modes: [])])
            .first?.modes.contains(mode(99)) == true)
    }

    @Test func testMultipleDisplaysMainFirstAndDuplicateNamesDistinct() {
        var main = display(2); main.isMain = true
        let sections = DisplayMenu.sections([display(), main])
        #expect(sections.map { $0.display.id } == [2, 1])
        #expect(Set(sections.map(\.title)).count == 2)
        #expect(sections.first?.title.contains("Main") == true)
    }

    @Test func testInactiveDisplaysHiddenAndMirroredPrimaryDisabled() {
        var primary = display(); primary.isMirrored = true
        var secondary = display(2); secondary.isActive = false
        secondary.isMirrored = true; secondary.mirrorPrimary = 1
        let sections = DisplayMenu.sections([primary, secondary])
        #expect(sections.count == 1)
        #expect(sections.first?.modes.count == 0)
        #expect(sections.first?.explanation?.contains("mirroring") == true)
    }

    @Test func testNoDisplaysReturnsEmptySections() {
        #expect(DisplayMenu.sections([]).isEmpty)
    }
}
