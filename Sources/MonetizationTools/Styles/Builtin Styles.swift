//
//  Builtin Styles.swift
//  MonetizationTools
//
//  Created by Ky directing Claude Opus 5 on 2026-09-14.
//

import SwiftUI



// MARK: - Default

/// Lays the prompt's contents out in a rounded rectangle with a secondary background. Deliberately plain; it's meant to
/// sit inside somebody else's design without arguing with it.
public struct DefaultMonetizationPromptStyle: MonetizationPromptStyle {
    
    public init() {}
    
    
    public func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            configuration.content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.background.secondary, in: .rect(cornerRadius: 12))
    }
}



public extension MonetizationPromptStyle where Self == DefaultMonetizationPromptStyle {
    
    /// Lays the prompt's contents out in a rounded rectangle with a secondary background. Deliberately plain; it's
    /// meant to sit inside somebody else's design without arguing with it.
    static var `default`: Self { .init() }
}



// MARK: - Plain

/// Applies nothing at all. The contents are on their own, for when the prompt's looks are entirely your business.
public struct PlainMonetizationPromptStyle: MonetizationPromptStyle {
    
    public init() {}
    
    
    public func makeBody(configuration: Configuration) -> some View {
        configuration.content
    }
}



public extension MonetizationPromptStyle where Self == PlainMonetizationPromptStyle {
    
    /// Applies nothing at all. The contents are on their own, for when the prompt's looks are entirely your business.
    static var plain: Self { .init() }
}
