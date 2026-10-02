//
//  Builtin Styles.swift
//  MonetizationTools
//
//  Created by Ky directing Claude Opus 5 on 2026-09-14.
//

import SwiftUI



// MARK: - Default

public extension MonetizationPrompt {
    
    /// The default prompt style: minimal, likely to fit into existing apps without issue
    struct DefaultStyle: Style {
        
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
}



public extension MonetizationPrompt.Style where Self == MonetizationPrompt.DefaultStyle {
    
    /// The default prompt style: minimal, likely to fit into existing apps without issue
    static var `default`: Self { .init() }
}



// MARK: - Plain

public extension MonetizationPrompt {
    
    /// The non-style; applies nothing at all. This just displays the prompt's contents unchanged
    struct PlainStyle: Style {
        
        public init() {}
        
        
        public func makeBody(configuration: Configuration) -> some View {
            configuration.content
        }
    }
}



public extension MonetizationPrompt.Style where Self == MonetizationPrompt.PlainStyle {
    
    /// The non-style; applies nothing at all. This just displays the prompt's contents unchanged
    static var plain: Self { .init() }
}
