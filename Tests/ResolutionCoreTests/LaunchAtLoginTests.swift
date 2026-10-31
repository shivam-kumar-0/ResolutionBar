import Testing
@testable import ResolutionCore

@MainActor private final class FakeLoginService: LaunchAtLoginService {
    var status: LaunchAtLoginStatus = .disabled
    var nextStatus: LaunchAtLoginStatus = .enabled
    var enableFails = false
    var enableCalls = 0
    var disableCalls = 0
    func enable() throws {
        enableCalls += 1
        if enableFails { throw SwitchFailure("Registration failed") }
        status = nextStatus
    }
    func disable() throws { disableCalls += 1; status = .disabled }
    func openSettings() {}
}

@MainActor private final class MemoryPreferences: LaunchNudgePreferences {
    var hasResponded = false
}

@MainActor struct LaunchAtLoginTests {
    @Test func suggestionIsDismissibleAndDoesNotRegisterAutomatically() {
        let service = FakeLoginService(); let preferences = MemoryPreferences()
        let coordinator = LaunchAtLoginCoordinator(service: service, preferences: preferences)
        #expect(coordinator.shouldSuggest)
        #expect(service.enableCalls == 0)
        coordinator.dismissSuggestion()
        #expect(!coordinator.shouldSuggest)
        #expect(service.status == .disabled)
        let reopened = LaunchAtLoginCoordinator(service: service, preferences: preferences)
        #expect(!reopened.shouldSuggest)
    }

    @Test func enableAndDisableFollowExplicitActions() throws {
        let service = FakeLoginService(); let preferences = MemoryPreferences()
        let coordinator = LaunchAtLoginCoordinator(service: service, preferences: preferences)
        try coordinator.enable()
        #expect(coordinator.status == .enabled)
        #expect(!coordinator.shouldSuggest)
        try coordinator.disable()
        #expect(coordinator.status == .disabled)
        #expect(!coordinator.shouldSuggest)
        #expect(service.enableCalls == 1 && service.disableCalls == 1)
    }

    @Test func approvalRequiredIsReportedRatherThanClaimingEnabled() throws {
        let service = FakeLoginService(); service.nextStatus = .requiresApproval
        let coordinator = LaunchAtLoginCoordinator(service: service, preferences: MemoryPreferences())
        try coordinator.enable()
        #expect(coordinator.status == .requiresApproval)
        #expect(!coordinator.shouldSuggest)
        try coordinator.disable()
        #expect(coordinator.status == .disabled)
    }

    @Test func failureIsReportedAndDoesNotHideTheSuggestion() {
        let service = FakeLoginService(); service.enableFails = true
        let coordinator = LaunchAtLoginCoordinator(service: service, preferences: MemoryPreferences())
        #expect(throws: (any Error).self) { try coordinator.enable() }
        #expect(coordinator.status == .disabled)
        #expect(coordinator.shouldSuggest)
    }

    @Test func alreadyConfiguredOrUnavailableDoesNotNag() {
        let service = FakeLoginService(); service.status = .enabled
        let preferences = MemoryPreferences()
        let coordinator = LaunchAtLoginCoordinator(service: service, preferences: preferences)
        #expect(!coordinator.shouldSuggest)
        service.status = .disabled
        #expect(!coordinator.shouldSuggest)
        let unavailable = FakeLoginService(); unavailable.status = .unavailable
        #expect(!LaunchAtLoginCoordinator(service: unavailable, preferences: MemoryPreferences()).shouldSuggest)
    }

    @Test func registrationThatDoesNotBecomeActiveIsNotReportedAsEnabled() {
        let service = FakeLoginService(); service.nextStatus = .disabled
        let coordinator = LaunchAtLoginCoordinator(service: service, preferences: MemoryPreferences())
        #expect(throws: (any Error).self) { try coordinator.enable() }
        #expect(coordinator.shouldSuggest)
    }
}
