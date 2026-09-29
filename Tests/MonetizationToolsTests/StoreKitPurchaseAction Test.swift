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
@MainActor
struct StoreKitPurchaseActionTest {
    
    /// Ask to Buy is waiting on someone else, so it's pending, and it's recorded so it can be found once it resolves
    @Test func pendingPurchaseIsPendingAndRecorded() async throws {
        try await withEphemeralDefaults { defaults in
            let index = PendingPurchaseIndex(defaults: defaults)
            
            let outcome = try await StoreKitPurchaseAction.outcome(of: .pending,
                                                                   identifier: "com.example.prompt",
                                                                   scope: .perApp,
                                                                   productId: "com.example.product",
                                                                   index: index)
            
            #expect(MonetizationPrompt.ActionOutcome.pending == outcome)
            #expect([PendingPurchase(productId: "com.example.product", promptIdentifier: "com.example.prompt", scope: .perApp)] == index.all)
        }
    }
    
    
    /// Cancelling the purchase sheet is backing out, not refusing, and nothing is recorded
    @Test func cancelledPurchaseIsAbandonedAndNotRecorded() async throws {
        try await withEphemeralDefaults { defaults in
            let index = PendingPurchaseIndex(defaults: defaults)
            
            let outcome = try await StoreKitPurchaseAction.outcome(of: .userCancelled,
                                                                   identifier: "com.example.prompt",
                                                                   scope: .perApp,
                                                                   productId: "com.example.product",
                                                                   index: index)
            
            #expect(MonetizationPrompt.ActionOutcome.abandoned == outcome)
            #expect(index.all.isEmpty)
        }
    }
}
