import Foundation
import Testing
@testable import Domain

/// What each plan may do, and the monthly counts behind it.
struct AccessPolicyTests {
    @Test func freeHasMeteredAIAndNoProTools() {
        let empty = UsageLedger(month: "2026-09")
        #expect(AccessPolicy.decide(.aiEdit, plan: .free, ledger: empty) == .allowed)
        #expect(AccessPolicy.decide(.stockBroll, plan: .free, ledger: empty) == .proOnly)
        #expect(AccessPolicy.decide(.soundDesign, plan: .free, ledger: empty) == .proOnly)
        #expect(AccessPolicy.decide(.videoStyle(.minimal), plan: .free, ledger: empty) == .allowed)
        #expect(AccessPolicy.decide(.videoStyle(.energetic), plan: .free, ledger: empty) == .proOnly)
    }

    @Test func limitsAreReachedAndProGoesFurther() {
        var ledger = UsageLedger(month: "2026-09")
        for _ in 0..<5 { ledger.record(.aiEdit) }
        #expect(AccessPolicy.decide(.aiEdit, plan: .free, ledger: ledger) == .limitReached(limit: 5))
        #expect(AccessPolicy.decide(.aiEdit, plan: .pro, ledger: ledger) == .allowed)
        #expect(AccessPolicy.remaining(.aiEdit, plan: .pro, ledger: ledger) == 145)
        #expect(AccessPolicy.remaining(.workflowRun, plan: .pro, ledger: ledger) == nil)
    }

    @Test func aNewMonthStartsEmpty() {
        var ledger = UsageLedger(month: "2026-08")
        ledger.record(.captionTranslation)
        let september = Calendar(identifier: .gregorian).date(from: DateComponents(timeZone: .gmt, year: 2026, month: 9, day: 2))!
        #expect(ledger.current(at: september).used(.captionTranslation) == 0)
    }

    @Test func refundsNeverGoBelowZero() {
        var ledger = UsageLedger(month: "2026-09")
        ledger.refund(.aiEdit)
        #expect(ledger.used(.aiEdit) == 0)
        ledger.record(.aiEdit)
        ledger.refund(.aiEdit)
        #expect(ledger.used(.aiEdit) == 0)
    }
}
