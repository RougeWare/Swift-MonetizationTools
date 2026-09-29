//
//  MonetizationPrompt + Action.swift
//  MonetizationTools
//
//  Created by Ky directing Claude Opus 5 on 2026-09-14.
//

import Foundation
import SwiftUI



public extension MonetizationPrompt {
    
    /// The actual action that is performed when a user chooses to proceed with a monetization prompt
    protocol Action: Sendable {
        
        /// What happened when this action ran. See ``MonetizationPrompt/ActionOutcome``.
        typealias Outcome = MonetizationPrompt.ActionOutcome
        
        
        /// Carries out the action
        ///
        /// This is called when the user chooses to proceed with the monetization prompt's offer, before whatever your action itself shows.
        /// This is what actually makes the payment/donation UI appear.
        ///
        /// - Parameters:
        ///   - identifier:  Identifies the prompt this action belongs to
        ///   - scope:       The prompt's scope. An action which needs to find its own stored state again later, like a
        ///                  StoreKit purchase waiting on Ask to Buy, needs this.
        ///   - environment: The environment of the view showing the prompt. Use it for whatever only SwiftUI can do
        ///                  correctly from here, such as `purchase` (which presents in the right window) or `openURL`.
        ///
        /// - Returns: What happened
        /// - Throws: Anything which went wrong. Treated the same as ``MonetizationPrompt/ActionOutcome/abandoned``, but
        ///           lets the caller show the error.
        @MainActor
        func perform(id identifier: MonetizationPrompt.Identifier,
                     scope: MonetizationPrompt.Scope,
                     in environment: EnvironmentValues) async throws -> Outcome
    }
    
    
    
    /// What happened when a ``MonetizationPrompt/Action`` ran.
    enum ActionOutcome: Sendable, Hashable {
        
        /// The person completed what the prompt offered. The prompt is retired: it won't show again.
        case succeeded
        
        /// Something outside this package has to happen before this is settled, like a parent approving an Ask to
        /// Buy request. The prompt is hidden, and its schedule is ignored, until that's resolved.
        case pending
        
        /// The person didn't complete it, or backed out. Nothing changes; the prompt keeps its schedule.
        case abandoned
    }
}
