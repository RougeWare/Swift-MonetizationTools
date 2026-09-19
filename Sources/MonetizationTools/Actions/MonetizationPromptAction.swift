//
//  MonetizationPromptAction.swift
//  MonetizationTools
//
//  Created by Ky directing Claude Opus 5 on 2026-09-14.
//

import Foundation



/// Something a monetization prompt can offer to do: a StoreKit purchase, an App Store review request, a link out to a
/// support page, anything else.
///
/// Write your own by conforming to this protocol. The prompt's scheduling, storage, and presentation don't know or
/// care what your action does; they only look at the ``MonetizationPromptActionOutcome`` it returns.
public protocol MonetizationPromptAction: Sendable {
    
    /// Does whatever this action does.
    ///
    /// This is called when someone taps into the prompt's own offer button, before whatever your action itself shows
    /// happens — for ``StoreKitPurchaseAction``, that's before Apple's payment sheet appears, since this method is
    /// what makes that sheet appear.
    ///
    /// - Parameter identifier: The identifier of the prompt this action belongs to. Use it to derive something
    ///                         action-specific (a StoreKit product ID, a URL slug) instead of making the developer
    ///                         say the same string twice.
    ///
    /// - Returns: What became of it
    /// - Throws: Anything which went wrong. A thrown error is treated the same as
    ///           ``MonetizationPromptActionOutcome/abandoned``.
    @MainActor
    func perform(id identifier: MonetizationPromptIdentifier) async throws -> MonetizationPromptActionOutcome
}



/// What became of a ``MonetizationPromptAction``, and what the prompt should do next because of it.
///
/// A prompt only ever changes what it remembers when this is ``succeeded``. Every other case leaves its schedule
/// exactly as it was, so someone backing out of an offer is never treated the same as someone who actually declined.
public enum MonetizationPromptActionOutcome: Sendable, Hashable {
    
    /// It worked. This prompt is retired permanently and will never be shown again.
    case succeeded
    
    /// It's underway but not yet resolved, like a StoreKit purchase awaiting Ask to Buy approval from a parent.
    ///
    /// Nothing is recorded here, and the prompt keeps its existing schedule. Whatever eventually finishes this
    /// purchase is responsible for retiring the prompt itself once the approval actually comes through.
    case pending
    
    /// It didn't happen: cancelled, dismissed, failed, whatever.
    ///
    /// Nothing is recorded and the prompt keeps its existing schedule.
    case abandoned
}
