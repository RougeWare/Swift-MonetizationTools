//
//  PaymentHandler.swift
//  MonetizationTools
//
//  Created by Ky on 2026-09-14.
//

import Foundation
import SwiftUI

import SimpleLogging



/// Handles the presentation & flow of accepting payments from the user.
///
/// A monetization prompt is designed to advertise one-time-only payments to the user. As such, this payment handler is designed to handle a single payment, or if it fails, future attempts at that same payment.
///
/// Obviously, payment handlers are the most important code to get right, since they handle the actual money changing hands. **Spend extra time and effort ensuring your code is bulletproof!**
///
///
/// ### Required methods
///
/// Conforming types MUST implement ``launch(id:in:)``. You're encouraged to implement the other methods on this protocol, but that's optional for now. If you choose not to implement them, a reasonable default will assume the behavior that's best for your payment handler.
///
///
/// ### Call flow
///
/// If ``launch(id:in:)`` returns `.pending`, then ``checkPending(id:)`` will periodically be called to check whether the pending purchase has resolved. Those checks will continue at regular intervals, until ``maxTimeToCheckPendingTransactions(whenPromptAppears:)`` has elapsed.
///
/// If any function returns ``PaymentOutcome/succeeded``, then ``handleSuccess(id:)`` is called to wrap up any further work needed after a successful payment (e.g. a StoreKit `transaction.finish()`).
///
///
/// - Attention: Payment handlers are the most important code to get right, since they handle the actual money changing hands. **Spend extra time and effort ensuring your code is bulletproof!**
public protocol PaymentHandler: Sendable {
    
    /// What happened when this paymentHandler ran. See ``PaymentOutcome``.
    typealias Outcome = PaymentOutcome
    
    
    /// Launches the payment flow (e.g. presents a purchase sheet) and returns the result.
    ///
    /// This function actually starts presenting the user with the payment UI, which then allows the user to make and complete the payment, or to cancel out of it. etc.. For example, a StoreKit purchase sheet, or a website which accepts a Stripe payment.
    /// That payment flow then informs the implementation of this function of the result, which this function transforms into its return value or a thrown error.
    ///
    /// This is called when the user presses a button that calls ``MonetizationPrompt/Flow/present()-9toqh``.
    ///
    /// Use `await` to pause this function while the user is interacting with the presented offer.
    ///
    /// - Attention: This method **MUST NEVER** return/throw until the payment flow is complete! Returning from this function while the user is still in the middle of the payment flow is undefined behavior, and may result in lost sales! Instead, use `await` to pause this function while the user is still making the payment.
    ///
    /// - Parameters:
    ///   - identifier:  Identifies the prompt whose payment to make
    ///   - environment: The current SwiftUI environment in which this is launching
    ///
    /// - Returns: A description of the user's final paymentHandler in this payment flow, as a value describing their final paymentHandler:
    ///     - ``PaymentOutcome/succeeded`` if the user completed the payment
    ///     - ``PaymentOutcome/abandoned`` if the user chose to not complete the payment, or the payment failed
    ///     - ``PaymentOutcome/pending`` if the user chose to proceed with the payment but something external must happen first, such as bank or parental approval. ``checkPending(id:)`` will be periodically called to check back and discover whether the payment has yet succeeded or been abandoned.
    ///
    ///     While this method may return ``PaymentOutcome/currentStateUnknown``, that's discouraged for this method.
    ///
    /// - Throws: Anything which went wrong during this payment flow
    @MainActor
    func launch(id identifier: MonetizationPrompt.Identifier,
                in environment: EnvironmentValues) async throws -> Outcome
    
    
    /// This method is called periodically while a payment is still pending.
    ///
    /// If ``launch(id:in)`` returns `.pending`, then (starting at some point in the future), this function will be called periodically to check whether that pending status has resolved.
    ///
    /// The number of times that this is called depends on the return value of ``maxTimeToCheckPendingTransactions(whenPromptAppears:)``.
    ///
    /// - Note: This package guarantees that it will not call this method for the same ID concurrently; it will wait for you to finish checking that ID, and then wait some additional time before checking again.
    ///
    /// - Note: Since this method isn't `throws`, you may return `.currentStateUnknown` instead of throwing an error. You're encoruaged to do additional error handling as well (e.g. log the error).
    ///
    /// - SeeAlso: ``maxTimeToCheckPendingTransactions(whenPromptAppears:)``
    ///
    /// - Parameter identifier: Identifies the prompt whose payment to check up on
    ///
    /// - Returns: One of the following values:
    ///     - ``PaymentOutcome/succeeded`` if the payment ended up successfully being processed
    ///     - ``PaymentOutcome/abandoned`` if the payment ended up being declined, cancelled, expired, etc.
    ///     - ``PaymentOutcome/pending`` if the payment is still pending
    ///     - ``PaymentOutcome/currentStateUnknown`` if the current state of the payment could not be determined (e.g. the device is offline, the payment processor returned a `500` error, records of the payment could not be found, etc.)
    func checkPending(id identifier: MonetizationPrompt.Identifier) async -> Outcome
    
    
    /// Wrap up anything remaining _after_ a successful payment has been completed. For example, a StoreKit `transaction.finish()`.
    ///
    /// The package calls this only after a `.succeeded` outcome, and only after wrapping up its duties for handling a success.
    ///
    /// - Note: While this is normally called exactly once for a given identifier, in the event of a crash (or force-quit, dead battery, etc.) while running this function, this package calls this again for that same identifier. Plan for this to be called a second time, perhaps with nothing to do because it did its duties the first time, perhaps with a lot of cleanup because its duties were interrupted.
    ///
    /// - Parameter identifier: Identifies the prompt whose payment to wrap up
    func handleSuccess(id identifier: MonetizationPrompt.Identifier) async
    
    
    /// How long until this package stops calling ``checkPending(id:)``.
    ///
    /// If ``launch(id:in:)`` returns ``PaymentOutcome/pending``, then this package will periodically call ``checkPending(id:)``. This function tells the package how long to keep calling that function before it gives up and considers the purchase abandoned. The first check is some amount of time after ``launch(id:in:)`` returned ``PaymentOutcome/pending``.
    ///
    /// If the pending purchase is never resolved by ``checkPending(id:)``, then this package may choose to someday present that same monetization prompt to that same user again, to attempt the payment once more. If the duration this returns is less than the amount of time between those calls to ``launch(id:in)``, then this package clamps this duration to be shorter than that timespan.
    ///
    /// A `0` duration tells this package to disable or minimize those checks.
    /// Negative durations mean the same thing as `0` duration.
    ///
    /// - Note: If you don't care about this, then don't implement it; a reasonable default will be chosen then.
    /// - Note: Because this package uses the returned duration as a suggestion, you cannot promise any guarantees about such durations to your users.
    ///
    /// - Parameter interval: The minimum time between a monetization prompt being temporarily dismissed and it appearing again.
    /// - Returns: A duration between ``Duration/zero`` and the amount of time before the prompt is shown again. You may return an (effectively) infinite duration if you want this package to keep checking as many times as possible.
    func maxTimeToCheckPendingTransactions(whenPromptAppears interval: PromptInterval) -> Duration
}



/// The result of asking the user to make a payment
public enum PaymentOutcome: Sendable, Hashable {
    
    /// The user successfully completed the payment
    case succeeded
    
    /// The user completed their end of the payment, and some third party must then approve or decline it.
    ///
    /// For example, this might be a parent approving an Ask to Buy request, a bank needing to manually approve a payment, etc..
    /// See ``PaymentHandler/checkPending(id:)`` for details on how this is handled.
    case pending
    
    /// The user didn't complete the payment.
    ///
    /// Perhaps the payment was declined, or the user backed out, or the service no longer exists, etc..
    case abandoned
    
    /// It's unclear what the outcome of the paymentHandler was.
    ///
    /// Return this from ``PaymentHandler/checkPending(id:)`` or ``PaymentHandler/launch(id:in:)`` if you're unsure what the final state of the transaction might've been (for example: an error occurred, or an authoritative source is returning ambiguous information).
    static var currentStateUnknown: Self { .pending } // Currently, we just use `pending` to fill this need, but we might make this its own case in the future.
}



// MARK: - Defaults

public extension PaymentHandler {
    
    func checkPending(id identifier: MonetizationPrompt.Identifier) async -> Outcome {
        log(warning: "The paymentHandler for the prompt \(identifier) can't check on a pending attempt, so its result can never be known")
        return .currentStateUnknown
    }
    
    
    func handleSuccess(id identifier: MonetizationPrompt.Identifier) async {
        // Nothing to do in the default implementation
        log(info: "Payment completed successfully: \(identifier)")
    }
    
    
    func maxTimeToCheckPendingTransactions(whenPromptAppears interval: PromptInterval) -> Duration {
        interval.duration(since: .now) / 4
    }
}
