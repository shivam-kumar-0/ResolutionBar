import Foundation

/// A callback can invalidate a connection before the main queue processes its UI refresh.
public final class ConnectionLedger: @unchecked Sendable {
    private let lock = NSLock()
    private var tokens: [UInt32: (identity: String, token: String)] = [:]
    public init() {}
    public func token(id: UInt32, identity: String) -> String {
        lock.lock(); defer { lock.unlock() }
        if tokens[id]?.identity != identity { tokens[id] = (identity, UUID().uuidString) }
        return tokens[id]!.token
    }
    public func invalidate(id: UInt32) {
        lock.lock(); defer { lock.unlock() }
        tokens[id] = nil
    }
}
