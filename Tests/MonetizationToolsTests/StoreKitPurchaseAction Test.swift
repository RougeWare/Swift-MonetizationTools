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



/// Checks what StoreKit's results mean for a prompt. A verified purchase can't be built without the App Store, so
/// that case needs a manual test in an app with a StoreKit configuration file.
struct StoreKitPurchaseActionTest {
    
    /// Ask to Buy is waiting on someone else, so the person has neither refused nor finished
    @Test func pendingPurchaseIsAbandoned() async throws {
        let outcome = try await StoreKitPurchaseAction.outcome(of: .pending)
        
        #expect(MonetizationPromptActionOutcome.abandoned == outcome)
    }
    
    
    /// Cancelling the purchase sheet is backing out, not refusing
    @Test func cancelledPurchaseIsAbandoned() async throws {
        let outcome = try await StoreKitPurchaseAction.outcome(of: .userCancelled)
        
        #expect(MonetizationPromptActionOutcome.abandoned == outcome)
    }
}
