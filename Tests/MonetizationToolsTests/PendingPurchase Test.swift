//
//  PendingPurchase Test.swift
//  MonetizationTools
//
//  Created by Ky directing Claude Opus 5 on 2026-09-26.
//

import Foundation
import Testing
@testable import MonetizationTools



/// Checks the record of purchases still being waited on, since it has to survive the app being quit for days
@MainActor
struct PendingPurchaseIndexTest {
    
    /// A purchase for the given product, from the given prompt, in the given scope
    private func purchase(_ productId: String,
                          from promptIdentifier: MonetizationPrompt.Identifier = "com.example.prompt",
                          in scope: MonetizationPrompt.Scope = .perApp)
    -> PendingPurchase {
        PendingPurchase(productId: productId, promptIdentifier: promptIdentifier, scope: scope)
    }
    
    
    /// Nothing is waited on until something is added
    @Test func newIndexIsEmpty() async throws {
        try await withEphemeralDefaults { defaults in
            #expect(PendingPurchaseIndex(defaults: defaults).all.isEmpty)
        }
    }
    
    
    /// What's added is still there when read by a new index, the way it would be after a relaunch
    @Test func addedPurchasesSurviveANewIndex() async throws {
        try await withEphemeralDefaults { defaults in
            PendingPurchaseIndex(defaults: defaults).add(purchase("com.example.one", in: .appGroup(id: "group.com.example")))
            
            #expect([purchase("com.example.one", in: .appGroup(id: "group.com.example"))] == PendingPurchaseIndex(defaults: defaults).all)
        }
    }
    
    
    /// The same purchase added twice is only waited on once
    @Test func addingTheSamePurchaseTwiceKeepsOne() async throws {
        try await withEphemeralDefaults { defaults in
            let index = PendingPurchaseIndex(defaults: defaults)
            
            index.add(purchase("com.example.one"))
            index.add(purchase("com.example.one"))
            
            #expect(1 == index.all.count)
        }
    }
    
    
    /// Resolving a product stops waiting on every prompt waiting on it, and only those
    @Test func removingAProductRemovesEveryPurchaseForItAndNothingElse() async throws {
        try await withEphemeralDefaults { defaults in
            let index = PendingPurchaseIndex(defaults: defaults)
            index.add(purchase("com.example.one", from: "com.example.promptA"))
            index.add(purchase("com.example.one", from: "com.example.promptB"))
            index.add(purchase("com.example.two"))
            
            index.remove(productId: "com.example.one")
            
            #expect([purchase("com.example.two")] == index.all)
        }
    }
    
    
    /// A damaged index reads as empty, so the listener does nothing rather than act on bad data
    @Test func damagedIndexReadsAsEmpty() async throws {
        try await withEphemeralDefaults { defaults in
            defaults.set("not json", forKey: "MonetizationTools.pendingPurchases")
            
            #expect(PendingPurchaseIndex(defaults: defaults).all.isEmpty)
        }
    }
}
