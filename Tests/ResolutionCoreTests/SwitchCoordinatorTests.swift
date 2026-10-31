import Testing
@testable import ResolutionCore

@MainActor final class FakeDisplayService: DisplayService {
    var displays: [DisplaySnapshot] = [display()]
    var calls: [(UInt32, UInt32, ChangeScope)] = []
    var failOnCalls: Set<Int> = []
    var onApply: (() throws -> Void)?
    var onSnapshot: (() -> Void)?
    func snapshot() throws -> [DisplaySnapshot] { onSnapshot?(); return displays }
    func apply(display expected: DisplaySnapshot, mode: DisplayMode, scope: ChangeScope) throws {
        calls.append((expected.id, mode.id, scope))
        if failOnCalls.contains(calls.count) { throw SwitchFailure("Simulated display failure") }
        guard let index = displays.firstIndex(where: { $0.sameConnection(as: expected) }),
              displays[index].currentMode == expected.currentMode,
              displays[index].modes.contains(mode) else { throw SwitchFailure("Stale display") }
        displays[index].currentMode = mode
        displays[index].frame.width = Double(mode.width)
        try onApply?()
    }
}

@MainActor final class TestClock { var time: Double = 100 }

@MainActor struct SwitchCoordinatorTests {
    func setup() -> (FakeDisplayService, TestClock, SwitchCoordinator) {
        let service = FakeDisplayService(); let clock = TestClock()
        return (service, clock, SwitchCoordinator(service: service, now: { clock.time }))
    }

    @Test func previewChangesOnlySelectedDisplayAndStarts15SecondDeadline() throws {
        let (service, clock, subject) = setup()
        service.displays.append(display(2))
        #expect(try subject.select(display: service.displays[0], mode: mode(2, width: 2560)))
        #expect(subject.pending != nil)
        #expect(subject.remainingSeconds == 15)
        #expect(service.displays[0].currentMode?.id == 2)
        #expect(service.displays[1].currentMode?.id == 1)
        clock.time += 14
        try subject.tick()
        #expect(subject.pending != nil)
    }

    @Test func keepRequestsPermanentScopeAndEndsPreview() throws {
        let (service, _, subject) = setup()
        try subject.select(display: service.displays[0], mode: mode(2, width: 2560))
        try subject.keep()
        #expect(subject.pending == nil)
        #expect(service.displays[0].currentMode?.id == 2)
        #expect(service.calls.last?.2 == .permanent)
    }

    @Test func expiryRestoresPreviousTargetMode() throws {
        let (service, clock, subject) = setup()
        try subject.select(display: service.displays[0], mode: mode(2, width: 2560))
        clock.time += 15
        try subject.tick()
        #expect(subject.pending == nil)
        #expect(service.displays[0].currentMode?.id == 1)
    }

    @Test func keepAfterSleepDeadlineCannotCommit() throws {
        let (service, clock, subject) = setup()
        try subject.select(display: service.displays[0], mode: mode(2, width: 2560))
        clock.time += 3600
        #expect(throws: (any Error).self) { try subject.keep() }
        #expect(service.displays[0].currentMode?.id == 1)
        #expect(!service.calls.contains { $0.2 == .permanent })
    }

    @Test func currentSelectionIsNoOp() throws {
        let (service, _, subject) = setup()
        #expect(try subject.select(display: service.displays[0], mode: mode()) == false)
        #expect(service.calls.isEmpty)
    }

    @Test func preventsOverlappingPreviews() throws {
        let (service, _, subject) = setup()
        try subject.select(display: service.displays[0], mode: mode(2, width: 2560))
        #expect(throws: (any Error).self) { try subject.select(display: service.displays[0], mode: mode()) }
        #expect(subject.pending?.desired.id == 2)
    }

    @Test func staleConnectionAndUnavailableModeAreRejected() throws {
        let (service, _, subject) = setup()
        let old = service.displays[0]
        service.displays[0].generation = "replacement"
        #expect(throws: (any Error).self) { try subject.select(display: old, mode: mode(2, width: 2560)) }
        #expect(throws: (any Error).self) { try subject.select(display: service.displays[0], mode: mode(99)) }
        #expect(service.calls.isEmpty)
    }

    @Test func mirroredAndUnsafeSelectionsAreRejected() throws {
        let (service, _, subject) = setup()
        service.displays[0].isMirrored = true
        #expect(throws: (any Error).self) { try subject.select(display: service.displays[0], mode: mode(2, width: 2560)) }
        service.displays[0].isMirrored = false
        let unsafe = mode(3, interlaced: true)
        service.displays[0].modes.append(unsafe)
        #expect(throws: (any Error).self) { try subject.select(display: service.displays[0], mode: unsafe) }
        #expect(service.calls.isEmpty)
    }

    @Test func ownSynchronousCallbackAndSettledNotificationDoNotCancelPreview() throws {
        let (service, _, subject) = setup()
        service.onApply = { () throws -> Void in
            #expect(subject.isBusy)
            let cancelled = try subject.reconcile()
            #expect(cancelled == false)
        }
        try subject.select(display: service.displays[0], mode: mode(2, width: 2560))
        #expect(try subject.reconcile() == false)
        #expect(subject.pending != nil)
    }

    @Test func disconnectedDisplayCancelsWithoutApplyingToReplacement() throws {
        let (service, _, subject) = setup()
        try subject.select(display: service.displays[0], mode: mode(2, width: 2560))
        service.displays[0].generation = "new-connection"
        #expect(try subject.reconcile())
        #expect(subject.pending == nil)
        #expect(service.calls.count == 1)
        #expect(service.displays[0].currentMode?.id == 2)
    }

    @Test func externalModeChangeIsNeverOverwritten() throws {
        let (service, _, subject) = setup()
        try subject.select(display: service.displays[0], mode: mode(2, width: 2560))
        service.displays[0].currentMode = mode(3, width: 3000)
        #expect(try subject.reconcile())
        #expect(service.displays[0].currentMode?.id == 3)
        #expect(subject.pending == nil)
    }

    @Test func externalArrangementChangeCancelsAndRestoresOnlyTargetMode() throws {
        let (service, _, subject) = setup()
        service.displays.append(display(2))
        try subject.select(display: service.displays[0], mode: mode(2, width: 2560))
        service.displays[1].frame.x = 4000
        #expect(try subject.reconcile())
        #expect(service.displays[0].currentMode?.id == 1)
        #expect(service.displays[1].frame.x == 4000)
    }

    @Test func externalChangeBeforeKeepCannotBeSaved() throws {
        let (service, _, subject) = setup()
        try subject.select(display: service.displays[0], mode: mode(2, width: 2560))
        service.displays[0].isMirrored = true
        #expect(throws: (any Error).self) { try subject.keep() }
        #expect(subject.pending == nil)
        #expect(!service.calls.contains { $0.2 == .permanent })
    }

    @Test func failedPreviewDoesNotLeavePendingConfirmation() {
        let (service, _, subject) = setup()
        service.failOnCalls = [1]
        #expect(throws: (any Error).self) { try subject.select(display: service.displays[0], mode: mode(2, width: 2560)) }
        #expect(subject.pending == nil)
        #expect(service.displays[0].currentMode?.id == 1)
    }

    @Test func failedSaveRevertsAndEndsPreview() throws {
        let (service, _, subject) = setup()
        try subject.select(display: service.displays[0], mode: mode(2, width: 2560))
        service.failOnCalls = [2]
        #expect(throws: (any Error).self) { try subject.keep() }
        #expect(service.displays[0].currentMode?.id == 1)
        #expect(subject.pending == nil)
    }

    @Test func failedSaveAndRollbackAreBothReported() throws {
        let (service, _, subject) = setup()
        try subject.select(display: service.displays[0], mode: mode(2, width: 2560))
        service.failOnCalls = [2, 3]
        do { try subject.keep(); Issue.record("Expected save to fail") }
        catch { #expect(error.localizedDescription.contains("restore")) }
        #expect(subject.pending == nil)
    }
}
