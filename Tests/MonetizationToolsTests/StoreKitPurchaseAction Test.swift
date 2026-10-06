//
//  StoreKitPurchaseAction Test.swift
//  MonetizationTools
//
//  Created by Ky directing Claude Sonnet 5 on 2026-09-20.
//

import Foundation
import StoreKit
import Testing
@testable import MonetizationTools



/// Checks what StoreKit's results mean for a prompt. Transactions can't be built without the App Store, so a verified
/// purchase, `checkPending`, and `handleSuccess` need manual tests in an app with a StoreKit configuration file.
struct StoreKitPurchaseActionTest {
    
    /// Ask to Buy is waiting on someone else, so it's pending
    @Test func pendingPurchaseIsPending() throws {
        let outcome = try PaymentOutcome(.pending)
        
        #expect(PaymentOutcome.pending == outcome)
    }
    
    
    /// Cancelling the purchase sheet is backing out, not refusing
    @Test func cancelledPurchaseIsAbandoned() throws {
        let outcome = try PaymentOutcome(.userCancelled)
        
        #expect(PaymentOutcome.abandoned == outcome)
    }
    
    
    /// StoreKit stops waiting after the same fixed time, whatever the prompt's interval
    @Test(arguments: PromptInterval.allCases)
    func waitIsFixed(interval: PromptInterval) {
        let wait = StoreKitPaymentHandler.storeKitPurchase.maxTimeToCheckPendingTransactions(whenPromptAppears: interval)
        
        #expect(.days(2) == wait)
    }
}
