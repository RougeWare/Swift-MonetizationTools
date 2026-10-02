//
//  MonetizationPrompt + Identifier.swift
//  MonetizationTools
//
//  Created by Ky directing Claude Opus 5 on 2026-09-14.
//

import SpecialString



public extension MonetizationPrompt {
    
    /// The special type for ``MonetizationPrompt/Identifier``
    struct IdentifierSpecialType: SpecialStringSpecialType, Sendable {}
    
    
    
    /// Uniquely identifies one monetization prompt, stably, across every launch of the app for the rest of time.
    ///
    /// Reverse-DNS is the intended shape (`"com.example.licensePurchaseNotice"`), but nothing enforces that; the only real
    /// requirement is that it never changes once shipped, since it's the key under which this prompt's history is kept.
    ///
    /// Use one identifier for one offer. If two prompts offer the same product, give them the same identifier. Two
    /// identifiers for one product is a mistake in your code, and this package doesn't detect it or work around it.
    ///
    /// You can use one identifier for more than one `MonetizationPrompt` view, for example the same prompt on two
    /// different screens. They share one stored state. If more than one of them is on screen at the same time and the
    /// person acts on one, what the others show isn't defined until they next appear.
    typealias Identifier = SpecialString<IdentifierSpecialType>
}
