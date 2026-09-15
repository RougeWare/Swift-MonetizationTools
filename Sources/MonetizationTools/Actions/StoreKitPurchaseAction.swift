//
//  StoreKitPurchaseAction.swift
//  MonetizationTools
//
//  Created by Ky on 2026-09-14.
//

import Foundation
import StoreKit



/// Presents the system purchase sheet for a StoreKit product.
///
/// Transactions are always finished, whatever they turn out to be, so nothing is ever left unfinished in the queue to
/// be re-delivered on next launch.
public struct StoreKitPurchaseAction: MonetizationPromptAction {
    
    /// The product to offer. When `nil`, the prompt's own identifier is used as the product ID, for the common case
    /// where the two are the same string and saying it twice would be silly.
    public let productID: String?
    
    
    /// - Parameter productID: _optional_ - The product to offer. Defaults to `nil`, meaning "use the prompt's own
    ///                        identifier".
    public init(productID: String? = nil) {
        self.productID = productID
    }
    
    
    @MainActor
    public func perform(for identifier: MonetizationPromptIdentifier) async throws -> MonetizationPromptActionOutcome {
        let effectiveProductID = productID ?? identifier.withoutTypeSafety()
        
        guard let product = try await Product.products(for: [effectiveProductID]).first else {
            throw StoreKitPurchaseActionError.noSuchProduct(productID: effectiveProductID)
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
            return .pending
            
        case .userCancelled:
            return .notCompleted
            
        @unknown default:
            return .notCompleted
        }
    }
}



/// What can go wrong while performing a ``StoreKitPurchaseAction``
public enum StoreKitPurchaseActionError: Error {
    
    /// The App Store has no product by that ID. Usually a typo, or a product which isn't approved yet.
    case noSuchProduct(productID: String)
    
    /// The App Store returned a transaction whose signature didn't check out. Treat it as no purchase at all.
    case unverifiedTransaction(underlyingError: any Error)
}



public extension MonetizationPromptAction where Self == StoreKitPurchaseAction {
    
    /// Offers a StoreKit product whose ID is the same as the prompt's own identifier
    static var storeKitPurchase: Self { .init() }
    
    
    /// Offers the given StoreKit product
    ///
    /// - Parameter productID: The App Store product ID to offer
    static func storeKitPurchase(productID: String) -> Self { .init(productID: productID) }
}
