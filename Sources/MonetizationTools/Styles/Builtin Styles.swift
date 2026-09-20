//
//  Builtin Styles.swift
//  MonetizationTools
//
//  Created by Ky directing Claude Opus 5 on 2026-09-14.
//

import SwiftUI



// MARK: - Default

/// The default prompt style: minimal, likely to fit into existing apps without issue
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
    
    /// The default prompt style: minimal, likely to fit into existing apps without issue
    static var `default`: Self { .init() }
}



// MARK: - Plain

/// The non-style; applies nothing at all. This just displays the prompt's contents unchanged
public struct PlainMonetizationPromptStyle: MonetizationPromptStyle {
    
    public init() {}
    
    
    public func makeBody(configuration: Configuration) -> some View {
        configuration.content
    }
}



public extension MonetizationPromptStyle where Self == PlainMonetizationPromptStyle {
    
    /// The non-style; applies nothing at all. This just displays the prompt's contents unchanged
    static var plain: Self { .init() }
}
