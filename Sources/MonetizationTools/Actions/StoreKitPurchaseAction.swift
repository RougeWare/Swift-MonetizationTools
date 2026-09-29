//
//  StoreKitPurchaseAction.swift
//  MonetizationTools
//
//  Created by Ky directing Claude Sonnet 5 on 2026-09-20.
//

import StoreKit
import SwiftUI
import SimpleLogging



/// Presents Apple's purchase sheet for one in-app purchase, and reports what the person did with it.
///
/// You don't make one of these directly. Use ``MonetizationPrompt/Action/storeKitPurchase`` (or
/// ``MonetizationPrompt/Action/storeKitPurchase(productId:)``) as a prompt's action.
///
/// The purchase sheet is presented through the environment of the view which shows the prompt, so it appears in the
/// right window, including on visionOS and in multi-window apps, with nothing for you to set up.
///
/// - A finished purchase is ``MonetizationPrompt/ActionOutcome/succeeded``, so the prompt is retired.
/// - A purchase waiting on someone else, like Ask to Buy waiting for a parent's approval, is
///   ``MonetizationPrompt/ActionOutcome/pending``. The prompt is hidden and ignores its schedule until the purchase
///   resolves.
/// - Cancelling is ``MonetizationPrompt/ActionOutcome/abandoned``, so the prompt keeps its schedule and stays on screen.
/// - Anything which goes wrong throws. That's a `StoreKitError`, a `Product.PurchaseError`, or the verification error
///   for a purchase which couldn't be verified. The purchase isn't finished in that last case, and nothing is recorded.
///
/// A pending purchase which is approved later, even after the app was quit, retires its prompt once the approved
/// purchase reaches the app. Nothing needs to be set up for this.
public struct StoreKitPurchaseAction: MonetizationPrompt.Action {
    
    /// The product's identifier in App Store Connect. When this is `nil`, the prompt's own identifier is used, so a
    /// matching pair doesn't have to be typed twice.
    private let productId: String?
    
    
    /// Makes an action for the given product
    ///
    /// - Parameter productId: The product's identifier in App Store Connect, or `nil` to use the prompt's own identifier
    internal init(productId: String?) {
        self.productId = productId
        PendingPurchaseListener.start()
    }
    
    
    /// Looks up the product, then presents Apple's purchase sheet for it. See this type's documentation for what each
    /// result means for the prompt.
    @MainActor
    public func perform(id identifier: MonetizationPrompt.Identifier,
                        scope: MonetizationPrompt.Scope,
                        in environment: EnvironmentValues) async throws -> Outcome {
        let productId = self.productId ?? identifier.withoutTypeSafety()
        
        guard let product = try await Product.products(for: [productId]).first else {
            log(error: "The App Store has no product with the identifier \(productId)")
            throw Product.PurchaseError.productUnavailable
        }
        
        let result = try await environment.purchase(product)
        return try await Self.outcome(of: result, identifier: identifier, scope: scope, productId: productId)
    }
}



// MARK: - Results

internal extension StoreKitPurchaseAction {
    
    /// Decides what a purchase result means for a prompt, and records anything this package needs to remember to make
    /// sense of it later.
    ///
    /// Separate from ``perform(id:scope:in:)`` so it can be checked without the App Store.
    ///
    /// - Parameters:
    ///   - result:     What StoreKit reported
    ///   - identifier: The prompt this purchase belongs to
    ///   - scope:      Where that prompt's stored state lives
    ///   - productId:  The product identifier which was purchased
    ///   - index:      _optional_ - Where a pending purchase is recorded. Tests use one backed by a throwaway database;
    ///                 everything else uses the default.
    ///
    /// - Returns: ``MonetizationPrompt/ActionOutcome/succeeded`` for a verified purchase, which is also finished.
    ///            ``MonetizationPrompt/ActionOutcome/pending`` for Ask to Buy or any other deferred purchase, which is
    ///            recorded in ``PendingPurchaseIndex`` so ``PendingPurchaseListener`` can find it later. Cancelled
    ///            purchases are ``MonetizationPrompt/ActionOutcome/abandoned``.
    /// - Throws: The verification error, for a purchase which couldn't be verified
    @MainActor
    static func outcome(of result: Product.PurchaseResult,
                        identifier: MonetizationPrompt.Identifier,
                        scope: MonetizationPrompt.Scope,
                        productId: String,
                        index: PendingPurchaseIndex = PendingPurchaseIndex())
    async throws -> MonetizationPrompt.ActionOutcome {
        switch result {
        case .success(let verification):
            switch verification {
            case .verified(let transaction):
                await transaction.finish()
                return .succeeded
                
            case .unverified(_, let verificationError):
                throw verificationError
            }
            
        case .pending:
            index.add(PendingPurchase(productId: productId, promptIdentifier: identifier, scope: scope))
            return .pending
            
        case .userCancelled:
            return .abandoned
            
        @unknown default:
            log(warning: "StoreKit reported a purchase result this package doesn't know, so it was treated as abandoned")
            return .abandoned
        }
    }
}



// MARK: - Shorthand

public extension MonetizationPrompt.Action where Self == StoreKitPurchaseAction {
    
    /// Presents Apple's purchase sheet for the product whose identifier is this prompt's own identifier, so a matching
    /// pair doesn't have to be typed twice.
    ///
    /// ```swift
    /// static let licensePurchase = Self(
    ///     "com.example.licensePurchase",
    ///     action: .storeKitPurchase
    /// )
    /// ```
    ///
    /// To use a different product, see ``storeKitPurchase(productId:)``.
    static var storeKitPurchase: Self {
        Self(productId: nil)
    }
    
    
    /// Presents Apple's purchase sheet for the given product.
    ///
    /// Use this when the product's identifier in App Store Connect isn't the same as the prompt's identifier, such as
    /// when several prompts offer the same product.
    ///
    /// - Parameter productId: The product's identifier in App Store Connect
    static func storeKitPurchase(productId: String) -> Self {
        Self(productId: productId)
    }
}
