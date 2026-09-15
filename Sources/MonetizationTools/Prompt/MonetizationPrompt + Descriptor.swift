//
//  MonetizationPrompt + Descriptor.swift
//  MonetizationTools
//
//  Created by Ky on 2026-09-14.
//

import Foundation



public extension MonetizationPrompt {
    
    /// Everything which defines one monetization prompt: who it is, how often it may appear, how far its memory
    /// reaches, and what happens when someone says yes.
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
        /// This is only read once, the very first time this prompt is checked; from then on the value recorded at that
        /// moment is the one which governs. Changing it in a later version of your app doesn't affect anyone who
        /// already has the old one.
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
        ///   - action:     What happens when someone says yes
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
