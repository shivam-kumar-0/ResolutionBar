import Foundation

public enum ChangeScope { case application, permanent }

@MainActor public protocol DisplayService: AnyObject {
    func snapshot() throws -> [DisplaySnapshot]
    func apply(display: DisplaySnapshot, mode: DisplayMode, scope: ChangeScope) throws
}

public struct PendingChange {
    public let original: DisplaySnapshot
    public let desired: DisplayMode
    public var expected: [DisplaySnapshot]
    public var deadline: TimeInterval
}

public struct SwitchFailure: LocalizedError {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var errorDescription: String? { message }
}

@MainActor public final class SwitchCoordinator {
    private let service: DisplayService
    private let now: () -> TimeInterval
    public private(set) var pending: PendingChange?
    public private(set) var isBusy = false
    public private(set) var notice: String?
    public var remainingSeconds: Int {
        guard let pending, pending.deadline.isFinite else { return 0 }
        return max(0, Int(ceil(pending.deadline - now())))
    }

    public init(service: DisplayService, now: @escaping () -> TimeInterval) {
        self.service = service; self.now = now
    }
    @discardableResult public func select(display: DisplaySnapshot, mode: DisplayMode) throws -> Bool {
        guard !isBusy, pending == nil else { throw SwitchFailure("Keep or revert the current preview first.") }
        notice = nil
        let before = try service.snapshot()
        guard let target = before.first(where: { $0.sameConnection(as: display) }), target.isActive else {
            throw SwitchFailure("This display connection changed. Open the menu and choose again.")
        }
        guard !target.isMirrored else { throw SwitchFailure("Resolution switching is unavailable while mirroring.") }
        if let reason = target.unavailableReason { throw SwitchFailure(reason) }
        guard before.filter({ $0.identity == target.identity }).count == 1 else {
            throw SwitchFailure("This display cannot be identified unambiguously. Reconnect it and try again.")
        }
        guard let originalMode = target.currentMode else { throw SwitchFailure("The current resolution could not be read, so a recoverable preview is unavailable.") }
        if originalMode == mode { return false }
        guard target.modes.contains(originalMode) else {
            throw SwitchFailure("The current resolution is unavailable to restore, so switching is disabled for this display.")
        }
        guard mode.isSelectable, target.modes.contains(mode) else {
            throw SwitchFailure("This resolution is no longer available. Open the menu and choose again.")
        }
        // Set state before Core Graphics: own callbacks can occur synchronously.
        pending = PendingChange(original: target, desired: mode, expected: before, deadline: .infinity)
        isBusy = true
        do {
            try service.apply(display: target, mode: mode, scope: .application)
            let after = try service.snapshot()
            guard let actual = after.first(where: { $0.sameConnection(as: target) }),
                  actual.currentMode == mode, sameTopology(before, after, geometry: false) else {
                throw SwitchFailure("The display configuration changed while applying the resolution.")
            }
            pending?.expected = after
            pending?.deadline = now() + 15
            isBusy = false
            return true
        } catch {
            isBusy = false
            throw recover(after: error)
        }
    }

    public func keep() throws {
        guard !isBusy, let change = pending else { return }
        if now() >= change.deadline {
            try revert()
            throw SwitchFailure("The preview expired. The previous resolution was requested again.")
        }
        do {
            let current = try service.snapshot()
            guard sameTopology(change.expected, current),
                  let target = current.first(where: { $0.sameConnection(as: change.original) }),
                  target.currentMode == change.desired, !target.isMirrored else {
                throw SwitchFailure("The display settings changed during the preview. The change was not saved.")
            }
            guard target.unavailableReason == nil, current.filter({ $0.identity == target.identity }).count == 1 else {
                throw SwitchFailure("The display can no longer be identified or monitored reliably. The change was not saved.")
            }
            guard now() < change.deadline else { throw SwitchFailure("The preview expired while validating the display. The change was not saved.") }
            isBusy = true
            try service.apply(display: target, mode: change.desired, scope: .permanent)
            pending = nil
            isBusy = false
            notice = "Resolution kept."
        } catch {
            isBusy = false
            throw recover(after: error)
        }
    }

    public func revert() throws {
        guard !isBusy, let change = pending else { return }
        pending = nil
        isBusy = true
        defer { isBusy = false }
        let current = try service.snapshot()
        guard let target = current.first(where: { $0.sameConnection(as: change.original) }),
              target.isActive, !target.isMirrored, target.unavailableReason == nil,
              current.filter({ $0.identity == target.identity }).count == 1 else {
            notice = "Preview cancelled. The display connection changed, so its previous resolution could not be restored."
            return
        }
        guard target.currentMode == change.desired else {
            notice = "Preview cancelled because settings changed elsewhere. The newer settings were left in place."
            return
        }
        guard let originalMode = change.original.currentMode, target.modes.contains(originalMode) else {
            throw SwitchFailure("The previous resolution is no longer available to restore.")
        }
        do {
            try service.apply(display: target, mode: originalMode, scope: .application)
            notice = "Previous resolution restored."
        } catch {
            throw SwitchFailure("Could not restore the previous resolution. \(error.localizedDescription)")
        }
    }

    public func tick() throws {
        guard let change = pending, !isBusy, now() >= change.deadline else { return }
        try revert()
    }

    @discardableResult public func reconcile() throws -> Bool {
        guard !isBusy, let change = pending else { return false }
        let current = try service.snapshot()
        if sameTopology(change.expected, current),
           current.first(where: { $0.sameConnection(as: change.original) })?.currentMode == change.desired {
            return false
        }
        try revert()
        if notice == "Previous resolution restored." {
            notice = "Preview cancelled because the display configuration changed. The previous resolution was restored."
        }
        return true
    }

    private func recover(after failure: Error) -> Error {
        do { try revert(); return failure }
        catch { return SwitchFailure("\(failure.localizedDescription) Also unable to restore the previous resolution: \(error.localizedDescription)") }
    }

    private func sameTopology(_ lhs: [DisplaySnapshot], _ rhs: [DisplaySnapshot], geometry: Bool = true) -> Bool {
        let left = lhs.sorted { $0.id < $1.id }, right = rhs.sorted { $0.id < $1.id }
        guard left.count == right.count else { return false }
        return zip(left, right).allSatisfy { a, b in
            a.sameConnection(as: b) && a.isActive == b.isActive && a.isMain == b.isMain &&
            a.isMirrored == b.isMirrored && a.mirrorPrimary == b.mirrorPrimary &&
            (!geometry || a.frame == b.frame)
        }
    }
}
