//
//  MonetizationPromptAction.swift
//  MonetizationTools
//
//  Created by Ky on 2026-09-14.
//

import Foundation



/// Whatever happens when someone takes a monetization prompt up on its offer: a StoreKit purchase, an App Store review
/// request, a link out to a support page, anything.
///
/// This package ships ``StoreKitPurchaseAction`` and ``AppStoreReviewAction``. Write your own by conforming to this
/// protocol; nothing about the scheduling, storage, or presentation machinery needs to know what your action does.
public protocol MonetizationPromptAction: Sendable {
    
    /// Carries this action out.
    ///
    /// - Parameter identifier: The identifier of the prompt this action belongs to. Useful for deriving something from
    ///                         it (a StoreKit product ID, a URL slug) rather than making the developer say the same
    ///                         string twice.
    ///
    /// - Returns: What became of it
    /// - Throws: Anything which went wrong. A thrown error is treated the same as ``MonetizationPromptActionOutcome/notCompleted``.
    @MainActor
    func perform(for identifier: MonetizationPromptIdentifier) async throws -> MonetizationPromptActionOutcome
}



/// What became of a ``MonetizationPromptAction``
public enum MonetizationPromptActionOutcome: Sendable, Hashable {
    
    /// It worked. This prompt is retired permanently and will never be shown again.
    case succeeded
    
    /// It's underway but unresolved, like a StoreKit purchase awaiting Ask to Buy approval.
    ///
    /// Nothing is recorded: the prompt keeps its existing schedule, and stays on screen. Marking it done would be a lie,
    /// and treating it as a refusal would be worse.
    case pending
    
    /// It didn't happen. Cancelled, dismissed, failed, whatever.
    ///
    /// Nothing is recorded and the prompt keeps its existing schedule. Backing out of an offer is not the same as
    /// asking not to be asked, so this is neither a ``MonetizationPromptFlow/snooze()`` nor a
    /// ``MonetizationPromptFlow/decline()``.
    case notCompleted
}
