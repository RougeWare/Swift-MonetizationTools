//
//  StoreKitPaymentHandler.swift
//  MonetizationTools
//
//  Created by Ky directing Claude Sonnet 5 on 2026-09-20.
//

import StoreKit
import SwiftUI
import SimpleLogging



/// Handles making payments through StoreKit.
///
/// To use this, put ``PaymentHandler/storeKitPurchase`` (or ``PaymentHandler/storeKitPurchase(productId:)``) when you make a ``MonetizationPrompt/Descriptor`` to make the prompt present a StoreKit purchase sheet and handle its results.
///
/// - Attention: For "consumable" IAPs, make sure you only use this package, or only use your own custom handling. Mixing your custom handling of the same "consumable" IAP that you've asked this package to handle, results in undefined behavior.
///               For "non-consumable" IAPs, you may mix the two; this package and StoreKit both handle that well.
///
/// - Note: This package doesn't currently listen to `Transaction.updates`, so you can still listen to that for other IAPs.
public struct StoreKitPaymentHandler: PaymentHandler {
    
    /// Double the roughly 24 hours that developers report for Ask to Buy requests to expire, in case Apple lengthens it.
    private static let maxTimeToCheckPendingPurchases: Duration = .days(2)
    
    /// The product's identifier in App Store Connect.
    ///
    /// When this is `nil`, the prompt identifier is used
    private let productId: String?
    
    
    /// Create a StoreKIt payment handler for the IAP product with the given identifier
    ///
    /// - Parameter productId: The product's IAP identifier in App Store Connect, or `nil` to use the prompt identifier instead
    internal init(productId: String?) {
        self.productId = productId
    }
    
    
    /// Begin the purchase flow by using a StoreKit purchase sheet.
    ///
    /// This first looks up the product, then presents Apple's purchase sheet for it.
    ///
    /// - Returns: One of the following:
    ///     - ``PaymentOutcome/succeeded`` means the StoreKit purchase was verified to be successful.
    ///     - ``PaymentOutcome/pending`` means the user requested the puchase, but Ask to Buy is waiting for a third party (e.g. a parent) to approve the payment first.
    ///     - ``PaymentOutcome/abandoned`` means the user cancelled the purchase, perhaps because it was declined.
    ///
    /// - Throws: if the purchase can't be verified and isn't finished
    @MainActor
    public func launch(id identifier: MonetizationPrompt.Identifier,
                       in environment: EnvironmentValues) async throws -> Outcome {
        let productId = appStoreProductId(for: identifier)
        
        guard let product = try await Product.products(for: [productId]).first else {
            log(error: "The App Store has no product with the identifier \(productId)")
            throw Product.PurchaseError.productUnavailable
        }
        
        let result = try await environment.purchase(product)
        return try Outcome(result)
    }
    
    
    /// Checks to see if the given purchase has completed yet.
    /// 
    /// Since this is handling pending StoreKit transactions, this first looks in `Transaction.unfinished`, then `Transaction.currentEntitlements`. If neither has it, this returns `.currentStateUnknown`.
    ///
    /// - Returns: ``PurchaseOutcome/succeeded`` iff StoreKit contains a verified transaction record for the given identifier.
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
    
    
    /// Handle successful StoreKit payments.
    ///
    /// This finishes every verified unfinished transaction matching this handler's identifier (or the given identifier).
    ///
    /// This does nothing if there are none to verify, so repeating it after a crash is safe.
    public func handleSuccess(id identifier: MonetizationPrompt.Identifier) async {
        let productId = appStoreProductId(for: identifier)
        
        for await unfinished in StoreKit.Transaction.unfinished {
            if case .verified(let transaction) = unfinished,
               productId == transaction.productID
            {
                await transaction.finish()
            }
        }
    }
    
    
    /// Gives up after a fixed time, regardless of the given interval, because Ask to Buy requests are known to expire within a day or so.
    public func maxTimeToCheckPendingTransactions(whenPromptAppears _: PromptInterval) -> Duration {
        Self.maxTimeToCheckPendingPurchases
    }
}



// MARK: - Results

internal extension PaymentOutcome {
    
    /// Convert a StoreKit purchase result to a MonetizationTools payment outcome
    ///
    /// - Returns:
    ///     - ``PaymentOutcome/succeeded`` for a verified successful purchase
    ///     - ``PaymentOutcome/pending`` for Ask to Buy or any other deferred purchase
    ///     - ``PaymentOutcome/abandoned`` for a cancelled purchase
    ///
    /// - Throws: A verification error, if `result` is an unverified successful purchase
    init(_ result: Product.PurchaseResult) throws(VerificationResult<StoreKit.Transaction>.VerificationError) {
        switch result {
        case .success(let verification):
            switch verification {
            case .verified:
                self = .succeeded
                
            case .unverified(_, let verificationError):
                throw verificationError
            }
            
        case .pending:
            self = .pending
            
        case .userCancelled:
            self = .abandoned
            
        @unknown default:
            log(warning: "StoreKit reported a purchase result this package doesn't know, so it was treated as abandoned")
            self = .abandoned
        }
    }
}



// MARK: - Product identifiers

private extension StoreKitPaymentHandler {
    
    /// The product's identifier in App Store Connect, for the prompt with the given identifier
    ///
    /// - Parameter identifier: Identifies the prompt this paymentHandler belongs to
    func appStoreProductId(for identifier: MonetizationPrompt.Identifier) -> String {
        productId ?? identifier.withoutTypeSafety()
    }
}



// MARK: - Shorthand

public extension PaymentHandler where Self == StoreKitPaymentHandler {
    
    /// Presents Apple's purchase sheet for the product whose identifier is this prompt's own identifier, so a matching
    /// pair doesn't have to be typed twice.
    ///
    /// ```swift
    /// static let licensePurchase = Self(
    ///     "com.example.licensePurchase",
    ///     paymentHandler: .storeKitPurchase
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
