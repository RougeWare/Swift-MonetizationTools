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
    typealias Identifier = SpecialString<IdentifierSpecialType>
}
