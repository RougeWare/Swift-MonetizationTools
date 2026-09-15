//
//  MonetizationPromptIdentifier.swift
//  MonetizationTools
//
//  Created by Ky on 2026-09-14.
//

import SpecialString



/// The special type for `MonetizationPromptIdentifier`
public struct MonetizationPromptIdentifierSpecialType: SpecialStringSpecialType, Sendable {}



/// Uniquely identifies one monetization prompt, stably, across every launch of the app for the rest of time.
///
/// Reverse-DNS is the intended shape (`"com.example.licensePurchaseNotice"`), but nothing enforces that; the only real
/// requirement is that it never changes once shipped, since it's the key under which this prompt's history is kept. If
/// you change it, everyone who already declined gets asked again.
public typealias MonetizationPromptIdentifier = SpecialString<MonetizationPromptIdentifierSpecialType>
