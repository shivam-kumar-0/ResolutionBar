import Foundation

public enum LaunchAtLoginStatus: Equatable {
    case disabled, enabled, requiresApproval, unavailable
}

@MainActor public protocol LaunchAtLoginService: AnyObject {
    var status: LaunchAtLoginStatus { get }
    func enable() throws
    func disable() throws
    func openSettings()
}

@MainActor public protocol LaunchNudgePreferences: AnyObject {
    var hasResponded: Bool { get set }
}

@MainActor public final class LaunchAtLoginCoordinator {
    public let service: LaunchAtLoginService
    private let preferences: LaunchNudgePreferences
    public init(service: LaunchAtLoginService, preferences: LaunchNudgePreferences) {
        self.service = service
        self.preferences = preferences
        if service.status == .enabled || service.status == .requiresApproval { preferences.hasResponded = true }
    }
    public var status: LaunchAtLoginStatus { service.status }
    public var shouldSuggest: Bool { status == .disabled && !preferences.hasResponded }
    public func dismissSuggestion() { preferences.hasResponded = true }
    public func enable() throws {
        guard status != .unavailable else { throw SwitchFailure("Launch at login is unavailable for this copy of the app.") }
        if status == .disabled { try service.enable() }
        guard status == .enabled || status == .requiresApproval else {
            throw SwitchFailure("macOS did not enable launch at login. Please try again.")
        }
        preferences.hasResponded = true
    }
    public func disable() throws {
        guard status != .unavailable else { throw SwitchFailure("Launch at login is unavailable for this copy of the app.") }
        if status != .disabled { try service.disable() }
        preferences.hasResponded = true
    }
    public func openSettings() { service.openSettings() }
}
