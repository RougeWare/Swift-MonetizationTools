//
//  MonetizationPrompt + Descriptor.swift
//  MonetizationTools
//
//  Created by Ky directing Claude Opus 5 on 2026-09-14.
//

import Foundation



public extension MonetizationPrompt {
    
    /// Everything which defines one monetization prompt: how often it may appear, how far its memory reaches, and what happens when someone takes it up on its offer.
    ///
    /// Declare these once, as static members, and refer to them by dot-shorthand wherever the prompt appears:
    ///
    /// ```swift
    /// extension MonetizationPrompt.Descriptor {
    ///     static let licensePurchase = Self(
    ///         "com.example.licensePurchaseNotice",
    ///         atMost: .monthly,
    ///         action: .storeKitPurchase
    ///     )
    /// }
    /// ```
    ///
    /// Declaring one inline at the call site works too, but a prompt shown from more than one screen should be declared
    /// once so its cadence can't drift between copies.
    struct Descriptor: Sendable {
        
        /// Uniquely and permanently identifies this prompt
        public let identifier: MonetizationPromptIdentifier
        
        /// How long this prompt waits before its first appearance, and between every appearance after that.
        ///
        /// Only the very first check of this prompt ever reads this value. From then on, whatever it was at that
        /// first check is what's used, for as long as the prompt exists — including for someone whose first check
        /// already happened but who hasn't been shown the prompt yet, since they're still waiting on that same locked-in
        /// value. Changing this in a later version of your app only reaches people who have never once been checked
        /// for this prompt before.
        public let interval: PromptInterval
        
        /// Whether this prompt's history is kept for this app alone, or shared with the rest of an App Group
        public let scope: MonetizationPromptScope
        
        /// What happens when someone takes this prompt up on its offer
        public let action: any MonetizationPromptAction
        
        
        /// - Parameters:
        ///   - identifier: Uniquely and permanently identifies this prompt. Reverse-DNS is the intended shape. Never
        ///                 change it once shipped.
        ///   - interval:   _optional_ - How long to wait before the first appearance, and between appearances after
        ///                 that. Defaults to ``PromptInterval/monthly``.
        ///   - scope:      _optional_ - How far this prompt's memory reaches. Defaults to
        ///                 ``MonetizationPromptScope/perApp``.
        ///   - action:     What happens when someone takes this prompt up on its offer. This runs when someone taps
        ///                 into your own button and calls ``MonetizationPromptFlow/present()`` — before whatever the
        ///                 action itself shows. For ``StoreKitPurchaseAction``, that means before Apple's own
        ///                 payment sheet appears, since presenting that sheet is what this action does.
        public init(
            _ identifier: MonetizationPromptIdentifier,
            atMost interval: PromptInterval = .monthly,
            scope: MonetizationPromptScope = .perApp,
            action: any MonetizationPromptAction
        ) {
            self.identifier = identifier
            self.interval = interval
            self.scope = scope
            self.action = action
        }
    }
}
