//
//  MonetizationPromptAction.swift
//  MonetizationTools
//
//  Created by Ky directing Claude Opus 5 on 2026-09-14.
//

import Foundation
import SwiftUI



/// The actual action that is performed when a user chooses to proceed with a monetization prompt
public protocol MonetizationPromptAction: Sendable {
    
    /// Carries out the action
    ///
    /// This is called when the user chooses to proceed with the monetization prompt's offer, before whatever your action itself shows.
    /// This is what actually makes the payment/donation UI appear.
    ///
    /// - Parameters:
    ///   - identifier:  Identifies the prompt this action belongs to.
    ///   - environment: The environment of the view which shows the prompt. Use it for whatever only SwiftUI can do
    ///                  correctly from here, such as `purchase` (which presents in the right window) or `openURL`.
    ///
    /// - Returns: A value describing the result of the action
    /// - Throws: Anything which went wrong. A thrown error is treated the same as
    ///           ``MonetizationPromptActionOutcome/abandoned``, but allows you to present the error to the user.
    @MainActor
    func perform(id identifier: MonetizationPromptIdentifier,
                 in environment: EnvironmentValues) async throws -> MonetizationPromptActionOutcome
}



/// What became of a ``MonetizationPromptAction``, and what the prompt should do next because of it.
///
/// A prompt only ever changes what it remembers when this is ``succeeded``. Every other case leaves its schedule
/// exactly as it was, so someone backing out of an offer is never treated the same as someone who actually declined.

/// The result of running a ``MonetizationPromptAction``, describing what to do next.
///
/// The monetization prompt will decide how to handle the returned outcome.
public enum MonetizationPromptActionOutcome: Sendable, Hashable {
    
    /// The user completed the transaction succesfully
    case succeeded
    
//    /// The user has started making the transaction but has not yet finished
//    case pending // Is this necessary?
    
    /// The transaction didn't happen: cancelled, dismissed, failed, whatever.
    ///
    /// Nothing is recorded and the prompt keeps its existing schedule.
    case abandoned
}
