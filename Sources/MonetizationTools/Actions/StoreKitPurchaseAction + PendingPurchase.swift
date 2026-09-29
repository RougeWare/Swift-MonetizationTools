//
//  StoreKitPurchaseAction + PendingPurchase.swift
//  MonetizationTools
//
//  Created by Ky directing Claude Opus 5 on 2026-09-26.
//

import Foundation
import StoreKit
import SerializationTools
import SimpleLogging



/// One purchase `StoreKitPurchaseAction` is still waiting to hear back about, like an Ask to Buy request.
///
/// This is separate from any prompt's own stored state because resolving a purchase only ever tells us a product
/// identifier, and a product identifier isn't always the prompt identifier that requested it. See
/// ``MonetizationPrompt/Action/storeKitPurchase(productId:)``.
internal struct PendingPurchase: Codable, Hashable, Sendable {
    
    /// The product identifier this purchase is for
    let productId: String
    
    /// The prompt which requested it
    let promptIdentifier: MonetizationPrompt.Identifier
    
    /// Where that prompt's stored state lives
    let scope: MonetizationPrompt.Scope
}



/// Every purchase this app is still waiting to hear back about.
///
/// Backed by `UserDefaults.standard`, regardless of any individual prompt's own scope. A purchase can only ever be
/// started by this app's own process, using this app's own product catalog, so there's nothing to share across an App
/// Group here.
@MainActor
internal struct PendingPurchaseIndex {
    
    // Never change this key: every purchase already being waited on is recorded under it.
    private static let key = "MonetizationTools.pendingPurchases"
    
    /// The database which holds the index
    private let defaults: UserDefaults
    
    
    /// Makes an index backed by the given database.
    ///
    /// - Parameter defaults: _optional_ - The database to keep the index in. Tests use a throwaway one; everything else
    ///                       uses the default.
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }
    
    
    /// Every purchase currently being waited on. Corrupted or missing data reads as empty, so a listener with nothing
    /// readable to check does nothing, which is the safe failure here.
    var all: [PendingPurchase] {
        guard let stored = defaults.string(forKey: Self.key) else {
            return []
        }
        
        do {
            return try [PendingPurchase](jsonString: stored)
        }
        catch {
            log(error: error, "The index of pending purchases can't be read, so it's treated as empty")
            return []
        }
    }
    
    
    /// Starts waiting on a purchase.
    ///
    /// - Parameter purchase: The purchase to wait on
    func add(_ purchase: PendingPurchase) {
        var purchases = all
        
        guard false == purchases.contains(purchase) else {
            return
        }
        
        purchases.append(purchase)
        write(purchases)
    }
    
    
    /// Stops waiting on every purchase for the given product, because one of them just resolved.
    ///
    /// - Parameter productId: The product identifier which resolved
    func remove(productId: String) {
        write(all.filter { productId != $0.productId })
    }
    
    
    /// Replaces the stored index. If it can't be encoded, that's logged and nothing changes.
    ///
    /// - Parameter purchases: Every purchase to keep waiting on
    private func write(_ purchases: [PendingPurchase]) {
        do {
            defaults.set(try purchases.jsonString(), forKey: Self.key)
        }
        catch {
            log(error: error, "The index of pending purchases can't be stored")
        }
    }
}



/// Watches for StoreKit purchases which resolve after this app stopped waiting for them, like an Ask to Buy request a
/// parent approves after the child has closed the app.
///
/// Starts the first time a ``StoreKitPurchaseAction`` is made, and keeps running for the rest of the process. Nothing
/// about this needs setup: every purchase this action makes is already tracked in ``PendingPurchaseIndex``.
///
/// This only ever acts on a transaction whose product identifier is in that index. Anything else, a subscription, a
/// purchase from a dev's own separate StoreKit code, is left completely alone: not read, not finished, not touched.
internal enum PendingPurchaseListener {
    
    /// The running listener. A `static let` is created once, the first time it's touched, so it only ever starts once.
    ///
    /// It watches `Transaction.updates` for anything arriving while the app runs, and also reads `Transaction.unfinished`
    /// once. StoreKit hands unfinished transactions to `updates` only once, at launch, so a listener which starts later
    /// than that would otherwise miss a purchase approved while the app was closed.
    private static let listener: Task<Void, Never> = Task.detached(priority: .background) {
        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                for await update in StoreKit.Transaction.updates {
                    await handle(update)
                }
            }
            
            group.addTask {
                for await unfinished in StoreKit.Transaction.unfinished {
                    await handle(unfinished)
                }
            }
        }
    }
    
    
    /// Makes sure the listener is running. Safe to call any number of times.
    static func start() {
        _ = listener
    }
    
    
    /// Retires every prompt waiting on the given transaction's product, then finishes the transaction.
    ///
    /// Does nothing for a transaction which can't be verified, or whose product nobody is waiting on. The same
    /// transaction can arrive from both `updates` and `unfinished`; the second arrival finds nothing waiting on it, so
    /// it does nothing.
    ///
    /// - Parameter update: A transaction from StoreKit
    @MainActor
    private static func handle(_ update: VerificationResult<StoreKit.Transaction>) async {
        guard case .verified(let transaction) = update else {
            return
        }
        
        let index = PendingPurchaseIndex()
        let resolved = index.all.filter { transaction.productID == $0.productId }
        
        guard false == resolved.isEmpty else {
            return
        }
        
        for pending in resolved {
            PromptStore(scope: pending.scope)?.retire(pending.promptIdentifier)
        }
        
        index.remove(productId: transaction.productID)
        await transaction.finish()
    }
}
