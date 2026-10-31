import Testing
@testable import ResolutionCore

struct ConnectionLedgerTests {
    @Test func receivedInvalidationChangesTokenBeforeQueuedUIWork() {
        let ledger = ConnectionLedger()
        let original = ledger.token(id: 1, identity: "same-hardware")
        let other = ledger.token(id: 2, identity: "other-hardware")
        ledger.invalidate(id: 1)
        #expect(ledger.token(id: 1, identity: "same-hardware") != original)
        #expect(ledger.token(id: 2, identity: "other-hardware") == other)
    }

    @Test func stableConnectionsKeepTokensAndHardwareReplacementChangesThem() {
        let ledger = ConnectionLedger()
        let original = ledger.token(id: 1, identity: "original")
        #expect(ledger.token(id: 1, identity: "original") == original)
        #expect(ledger.token(id: 1, identity: "replacement") != original)
    }
}
