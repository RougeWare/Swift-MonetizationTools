//
//  StoreKitPurchaseAction.swift
//  MonetizationTools
//
//  Created by Ky directing Claude Opus 5 on 2026-09-14.
//

import Foundation
import StoreKit

import SimpleLogging



/// Presents the system purchase sheet for a StoreKit product.
///
/// Use this when a prompt's offer is "buy this thing." It handles the whole purchase, including the Ask to Buy case
/// where a parent has to approve it later, without you having to write any StoreKit code of your own.
public struct StoreKitPurchaseAction: MonetizationPromptAction {
    
    /// The product to offer. When `nil`, the prompt's own identifier is used as the product ID, for the common case
    /// where the two are the same string and typing it twice would be silly.
    public let productId: String?
    
    
    /// - Parameter productId: _optional_ - The product to offer. Defaults to `nil`, meaning "use the prompt's own
    ///                        identifier".
    public init(productId: String? = nil) {
        self.productId = productId
    }
    
    
    @MainActor
    public func perform(id identifier: MonetizationPromptIdentifier) async throws -> MonetizationPromptActionOutcome {
        let productId = productId ?? identifier.withoutTypeSafety()
        
        guard let product = try await Product.products(for: [productId]).first else {
            throw StoreKitPurchaseActionError.noSuchProduct(productId: productId)
        }
        
        switch try await product.purchase() {
        case .success(let verification):
            switch verification {
            case .verified(let transaction):
                await transaction.finish()
                return .succeeded
                
            case .unverified(let transaction, let error):
                await transaction.finish()
                throw StoreKitPurchaseActionError.unverifiedTransaction(underlyingError: error)
            }
            
        case .pending:
            // This purchase hasn't resolved yet — most commonly Ask to Buy, where a parent has to approve it. Apple
            // delivers the eventual result through `Transaction.updates`, not through this call, which has already
            // returned by the time that happens. Without a listener for it, an approved purchase would never get
            // `finish()` called on it and its prompt would never retire, even though the person paid.
            await PendingPurchaseTracker.shared.track(productId: productId, identifier: identifier)
            return .pending
            
        case .userCancelled:
            return .abandoned
            
        @unknown default:
            return .abandoned
        }
    }
}



/// What can go wrong while performing a ``StoreKitPurchaseAction``
public enum StoreKitPurchaseActionError: Error {
    
    /// The App Store has no product by that ID. Usually a typo, or a product which isn't approved yet.
    case noSuchProduct(productId: String)
    
    /// The App Store returned a transaction whose signature didn't check out. Treat it as no purchase at all.
    case unverifiedTransaction(underlyingError: any Error)
}



public extension MonetizationPromptAction where Self == StoreKitPurchaseAction {
    
    /// Offers a StoreKit product whose ID is the same as the prompt's own identifier
    static var storeKitPurchase: Self { .init() }
    
    
    /// Offers the given StoreKit product
    ///
    /// - Parameter productId: The App Store product ID to offer
    static func storeKitPurchase(productId: String) -> Self { .init(productId: productId) }
}



// MARK: - Pending purchase tracking

/// Finishes StoreKit transactions that resolve after ``StoreKitPurchaseAction/perform(id:)`` has already returned
/// — namely Ask to Buy approvals — and retires the prompt they belong to.
///
/// Apple's own guidance is a long-running listener on `Transaction.updates` that verifies and finishes each
/// transaction as it arrives: <https://developer.apple.com/forums/thread/787431>. This actor is that listener. It
/// starts the first time any purchase resolves as ``MonetizationPromptActionOutcome/pending``, and keeps a small
/// table of product ID to prompt identifier so it knows which prompt to retire once the real transaction shows up.
private actor PendingPurchaseTracker {
    
    static let shared = PendingPurchaseTracker()
    
    /// The prompt identifier waiting on each product ID's eventual transaction
    private var waitingIdentifiers: [String : MonetizationPromptIdentifier] = [:]
    
    /// The listener task, once started. `nil` until the first pending purchase.
    private var listenerTask: Task<Void, Never>?
    
    
    /// Remembers that the given prompt is waiting on the given product's transaction, and starts listening for it if
    /// nothing is listening yet.
    func track(productId: String, identifier: MonetizationPromptIdentifier) {
        waitingIdentifiers[productId] = identifier
        
        guard nil == listenerTask else {
            return
        }
        
        listenerTask = Task { [weak self] in
            for await update in Transaction.updates {
                guard case .verified(let transaction) = update else {
                    continue // Signature didn't check out; nothing to deliver, nothing to retire.
                }
                
                await transaction.finish()
                await self?.retirePrompt(forProductId: transaction.productID)
            }
        }
    }
    
    
    /// Retires the prompt waiting on the given product ID, if one is still waiting
    private func retirePrompt(forProductId productId: String) async {
        guard let identifier = waitingIdentifiers.removeValue(forKey: productId) else {
            return // Nothing was waiting on this product; not this tracker's concern.
        }
        
        guard let descriptor = await MonetizationPromptStore.descriptor(for: identifier) else {
            log(error: "A pending purchase for product '\(productId)' resolved, but no descriptor is registered for "
                     + "identifier '\(identifier)' anymore, so its prompt couldn't be retired.")
            return
        }
        
        await MonetizationPromptStore.store(for: descriptor.scope).retire(descriptor)
    }
}
