import Foundation
import ServiceManagement
import ResolutionCore

@MainActor final class SystemLaunchAtLoginService: LaunchAtLoginService {
    var status: LaunchAtLoginStatus {
        switch SMAppService.mainApp.status {
        case .notRegistered: return .disabled
        case .enabled: return .enabled
        case .requiresApproval: return .requiresApproval
        case .notFound: return .unavailable
        @unknown default: return .unavailable
        }
    }
    func enable() throws { try SMAppService.mainApp.register() }
    func disable() throws { try SMAppService.mainApp.unregister() }
    func openSettings() { SMAppService.openSystemSettingsLoginItems() }
}

@MainActor final class StoredLaunchNudgePreferences: LaunchNudgePreferences {
    private let defaults: UserDefaults
    private let key = "launchAtLoginSuggestionAnswered"
    init(defaults: UserDefaults = .standard) { self.defaults = defaults }
    var hasResponded: Bool {
        get { defaults.bool(forKey: key) }
        set { defaults.set(newValue, forKey: key) }
    }
}

/// Demo and smoke tests use only in-memory state, never Service Management.
@MainActor final class DemoLaunchAtLoginService: LaunchAtLoginService {
    var status: LaunchAtLoginStatus = .disabled
    private(set) var didOpenSettings = false
    func enable() throws { status = .enabled }
    func disable() throws { status = .disabled }
    func openSettings() { didOpenSettings = true }
}

@MainActor final class DemoLaunchNudgePreferences: LaunchNudgePreferences {
    var hasResponded = false
}
