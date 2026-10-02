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
/// You don't make one of these directly. Use ``MonetizationPrompt/Action/storeKitPurchase`` or
/// ``MonetizationPrompt/Action/storeKitPurchase(productId:)`` as a prompt's action.
///
/// The purchase sheet is presented through the environment of the view which shows the prompt, so it appears in the right
/// window, including on visionOS and in multi-window apps, with nothing for you to set up.
///
/// - A verified purchase is `.succeeded`. The transaction is finished in `acknowledgeSuccess`, after the package has
///   stored the success.
/// - A purchase waiting on someone else, such as Ask to Buy waiting for a parent, is `.pending`.
/// - Cancelling is `.abandoned`.
/// - A purchase which can't be verified throws the verification error, and isn't finished.
///
/// While a purchase is pending, `checkPending` looks for it in `Transaction.unfinished`, and for a verified entitlement in
/// `Transaction.currentEntitlements`. If neither has it, it returns `.currentStateUnknown`. An Ask to Buy request which is
/// approved after the app was quit is found the next time the prompt appears. This package doesn't listen to
/// `Transaction.updates`.
///
/// If the product is a consumable, don't also offer it through your own StoreKit code. Your code can finish its
/// transaction before this action looks for it, and the action then can't tell that the purchase happened. For a
/// non-consumable this is handled, because ownership is checked too.
public struct StoreKitPurchaseAction: MonetizationPrompt.Action {
    
    // Double the roughly 24 hours that developers report for Ask to Buy requests to expire, in case Apple lengthens it.
    private static let maxTimeToCheckPendingPurchases: TimeInterval = 48 * 60 * 60
    
    /// The product's identifier in App Store Connect. When this is `nil`, the prompt's own identifier is used, so a
    /// matching pair doesn't have to be typed twice.
    private let productId: String?
    
    
    /// Makes an action for the given product
    ///
    /// - Parameter productId: The product's identifier in App Store Connect, or `nil` to use the prompt's own identifier
    internal init(productId: String?) {
        self.productId = productId
    }
    
    
    /// Looks up the product, then presents Apple's purchase sheet for it. See this type's documentation for what each
    /// result means for the prompt.
    @MainActor
    public func perform(id identifier: MonetizationPrompt.Identifier,
                        in environment: EnvironmentValues) async throws -> Outcome {
        let productId = appStoreProductId(for: identifier)
        
        guard let product = try await Product.products(for: [productId]).first else {
            log(error: "The App Store has no product with the identifier \(productId)")
            throw Product.PurchaseError.productUnavailable
        }
        
        let result = try await environment.purchase(product)
        return try Self.outcome(of: result)
    }
    
    
    /// Looks for this prompt's product in `Transaction.unfinished`, then in `Transaction.currentEntitlements`. Returns
    /// `.succeeded` if either has a verified transaction for it. Otherwise returns `.currentStateUnknown`.
    public func checkPending(id identifier: MonetizationPrompt.Identifier) async -> Outcome {
        let productId = appStoreProductId(for: identifier)
        
        for await unfinished in StoreKit.Transaction.unfinished {
            if case .verified(let transaction) = unfinished,
               productId == transaction.productID,
               nil == transaction.revocationDate
            {
                return .succeeded
            }
        }
        
        for await entitlement in StoreKit.Transaction.currentEntitlements {
            if case .verified(let transaction) = entitlement,
               productId == transaction.productID
            {
                return .succeeded
            }
        }
        
        return .currentStateUnknown
    }
    
    
    /// Finishes every verified unfinished transaction for this prompt's product. Does nothing if there are none, so
    /// repeating it after a crash is safe.
    public func acknowledgeSuccess(id identifier: MonetizationPrompt.Identifier) async {
        let productId = appStoreProductId(for: identifier)
        
        for await unfinished in StoreKit.Transaction.unfinished {
            if case .verified(let transaction) = unfinished,
               productId == transaction.productID
            {
                await transaction.finish()
            }
        }
    }
    
    
    /// Gives up after a fixed time, whatever `interval` is, because Ask to Buy requests are known to expire within a day
    /// or so.
    public func maxTimeToCheckPendingTransactions(whenPromptAppears interval: PromptInterval) -> TimeInterval {
        Self.maxTimeToCheckPendingPurchases
    }
}



// MARK: - Results

internal extension StoreKitPurchaseAction {
    
    /// Decides what a purchase result means for a prompt.
    ///
    /// Separate from `perform` so it can be checked without the App Store.
    ///
    /// - Parameter result: What StoreKit reported
    ///
    /// - Returns: ``MonetizationPrompt/ActionOutcome/succeeded`` for a verified purchase, which isn't finished yet;
    ///            `acknowledgeSuccess` finishes it. ``MonetizationPrompt/ActionOutcome/pending`` for Ask to Buy or any other
    ///            deferred purchase. ``MonetizationPrompt/ActionOutcome/abandoned`` for a cancelled purchase.
    /// - Throws: The verification error, for a purchase which couldn't be verified
    static func outcome(of result: Product.PurchaseResult) throws -> MonetizationPrompt.ActionOutcome {
        switch result {
        case .success(let verification):
            switch verification {
            case .verified:
                return .succeeded
                
            case .unverified(_, let verificationError):
                throw verificationError
            }
            
        case .pending:
            return .pending
            
        case .userCancelled:
            return .abandoned
            
        @unknown default:
            log(warning: "StoreKit reported a purchase result this package doesn't know, so it was treated as abandoned")
            return .abandoned
        }
    }
}



// MARK: - Product identifiers

private extension StoreKitPurchaseAction {
    
    /// The product's identifier in App Store Connect, for the prompt with the given identifier
    ///
    /// - Parameter identifier: Identifies the prompt this action belongs to
    func appStoreProductId(for identifier: MonetizationPrompt.Identifier) -> String {
        productId ?? identifier.withoutTypeSafety()
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
    /// Use this when the product's identifier in App Store Connect isn't the identifier you want for the prompt.
    ///
    /// A product should always be offered under the same prompt identifier. Offering one product under two identifiers is
    /// a mistake in your code. This package doesn't detect it or work around it.
    ///
    /// - Parameter productId: The product's identifier in App Store Connect
    static func storeKitPurchase(productId: String) -> Self {
        Self(productId: productId)
    }
}
