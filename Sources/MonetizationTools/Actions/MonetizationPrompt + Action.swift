//
//  MonetizationPrompt + Action.swift
//  MonetizationTools
//
//  Created by Ky directing Claude Opus 5 on 2026-09-14.
//

import Foundation
import SwiftUI
import SimpleLogging



public extension MonetizationPrompt {
    
    /// What a prompt does when a person accepts it, and how the prompt finds out later whether that worked.
    ///
    /// A conforming type has two main jobs. `perform` starts the offer. `checkPending` reports the result of an offer
    /// which couldn't finish right away. `checkPending` is the more important one. After `perform` returns `.pending`, it's
    /// the only way this package learns what happened. A mistake in it decides whether people who paid are asked to pay
    /// again, and whether people who didn't pay are left alone. Getting it right is your responsibility, and nothing else
    /// in this package depends on your code as much. Read its documentation before you write one.
    ///
    /// Put a button that calls the flow's `decline()` in your prompt's content. A person who already paid, and who sees
    /// the prompt again anyway, can use it to end the prompt for good.
    protocol Action: Sendable {
        
        /// What happened when this action ran. See ``MonetizationPrompt/ActionOutcome``.
        typealias Outcome = MonetizationPrompt.ActionOutcome
        
        
        /// Starts the offer, for example by presenting a purchase sheet.
        ///
        /// The package calls this when the person taps the prompt's accept button, after it has stored that an attempt is
        /// pending. Return what happened right now:
        /// - `.succeeded` if the person completed it.
        /// - `.abandoned` if they backed out.
        /// - `.pending` if it started, but something outside your control has to happen before it finishes. The package
        ///   then asks `checkPending` for the result later.
        ///
        /// - Parameters:
        ///   - identifier:  Identifies the prompt this action belongs to
        ///   - environment: The environment of the view showing the prompt. Use it for whatever only SwiftUI can do
        ///                  correctly from here, such as `purchase` (which presents in the right window) or `openURL`.
        ///
        /// - Returns: What happened
        /// - Throws: Anything which went wrong. The package treats it like `.abandoned`, and passes the error to whoever
        ///           called `present()`, so they can show it.
        @MainActor
        func perform(id identifier: MonetizationPrompt.Identifier,
                     in environment: EnvironmentValues) async throws -> Outcome
        
        
        /// Reports what happened to an offer which `perform` left pending.
        ///
        /// The package calls this when the prompt's view appears while the prompt's stored state is pending. Calls for the
        /// same prompt never overlap, and they are spaced apart. Nothing is on screen for the person to act on when this
        /// runs, so don't present any UI from here.
        ///
        /// Return:
        /// - `.succeeded` if the person completed it.
        /// - `.abandoned` only if you know for certain that it did not and will not complete, because the payment system
        ///   told you so.
        /// - `.currentStateUnknown` in every other case. That includes a request that failed, a server you couldn't
        ///   reach, and anything else where you can't tell what happened.
        ///
        /// Never return `.abandoned` because something went wrong. `.abandoned` makes the prompt available to show again.
        /// If the person's first attempt is still open, they would be asked to pay while it's still open. If you don't
        /// know, return `.currentStateUnknown`.
        ///
        /// This method can't throw, so handle every failure inside it and report it as `.currentStateUnknown`.
        ///
        /// If this keeps returning `.currentStateUnknown`, the package eventually stops waiting and treats the attempt as
        /// abandoned. How long it waits comes from `maxTimeToCheckPendingTransactions(whenPromptAppears:)`.
        ///
        /// The default implementation returns `.currentStateUnknown` and logs a warning, because an action that can leave
        /// an offer pending but can't check on it can never learn the result.
        ///
        /// - Parameter identifier: Identifies the prompt this action belongs to
        ///
        /// - Returns: What happened
        func checkPending(id identifier: MonetizationPrompt.Identifier) async -> Outcome
        
        
        /// Tells the payment system that the package has recorded a success, so the action can do its last step.
        ///
        /// The package calls this after every `.succeeded` outcome, from both `perform` and `checkPending`, once it has
        /// stored that the success is being recorded. StoreKit's action calls `transaction.finish()` here.
        ///
        /// After a crash, the package calls this again for the same offer. Make it safe to call more than once, and make
        /// it do nothing when there's nothing left to do.
        ///
        /// The default implementation does nothing.
        ///
        /// - Parameter identifier: Identifies the prompt this action belongs to
        func acknowledgeSuccess(id identifier: MonetizationPrompt.Identifier) async
        
        
        /// How long after an attempt starts the package keeps asking `checkPending`, before it treats the attempt as
        /// abandoned.
        ///
        /// The package limits the result to between zero and one interval minus the spacing between two checks, so
        /// waiting always ends before the prompt would otherwise be due again. The default is a fixed fraction of
        /// `interval`.
        ///
        /// Don't promise this duration to anyone. It's an implementation detail and can change.
        ///
        /// - Parameter interval: The interval the prompt locked in at its first check
        ///
        /// - Returns: How long to keep checking, counted from when the attempt started
        func maxTimeToCheckPendingTransactions(whenPromptAppears interval: PromptInterval) -> TimeInterval
    }
    
    
    
    /// What happened when a ``MonetizationPrompt/Action`` ran.
    enum ActionOutcome: Sendable, Hashable {
        
        /// The person completed what the prompt offered. The package records it, calls `acknowledgeSuccess`, and retires
        /// the prompt for good.
        case succeeded
        
        /// The offer started, but isn't finished, and something outside this package has to happen first, such as a
        /// parent approving an Ask to Buy request. The prompt's content is replaced by a short status message. On later
        /// appearances the prompt is hidden, and the package asks `checkPending` for the result. A success retires the
        /// prompt. A failure, or the package giving up waiting, makes the prompt come back later.
        case pending
        
        /// The person didn't complete it. From `perform`, nothing changes and the prompt stays on screen. From
        /// `checkPending`, the prompt comes back later.
        case abandoned
    }
}



public extension MonetizationPrompt.ActionOutcome {
    
    /// The same as `.pending`, named for the case where you can't tell what happened. Return this from `checkPending`
    /// whenever you don't know. If the package later treats "unknown" differently from "pending," code which returns this
    /// picks that up without changes.
    static var currentStateUnknown: Self {
        .pending
    }
}



// MARK: - Defaults

public extension MonetizationPrompt.Action {
    
    /// Returns `.currentStateUnknown` and logs a warning, because an action that can leave an offer pending but can't
    /// check on it can never learn the result.
    func checkPending(id identifier: MonetizationPrompt.Identifier) async -> Outcome {
        log(warning: "The action for the prompt \(identifier) can't check on a pending attempt, so its result can never be known")
        return .currentStateUnknown
    }
    
    
    /// Does nothing
    func acknowledgeSuccess(id identifier: MonetizationPrompt.Identifier) async {
    }
    
    
    /// A fixed fraction of `interval`
    func maxTimeToCheckPendingTransactions(whenPromptAppears interval: PromptInterval) -> TimeInterval {
        interval.quarterDuration(from: .now)
    }
}
