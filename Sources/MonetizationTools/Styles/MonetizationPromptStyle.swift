//
//  MonetizationPromptStyle.swift
//  MonetizationTools
//
//  Created by Ky on 2026-09-14.
//

import SwiftUI



/// Dresses a ``MonetizationPrompt``, the way `ButtonStyle` dresses a button.
///
/// The contents are always the developer's own; a style decides everything around them. Write one when every prompt in
/// your app should look the same without every call site repeating itself.
public protocol MonetizationPromptStyle {
    
    /// What this style produces
    associatedtype Body: View
    
    /// Dresses the given prompt
    ///
    /// - Parameter configuration: The prompt's contents, and anything else worth knowing about it
    @ViewBuilder @MainActor
    func makeBody(configuration: Configuration) -> Body
    
    
    /// Everything a style is given to work with
    typealias Configuration = MonetizationPromptStyleConfiguration
}



/// Everything a ``MonetizationPromptStyle`` is given to work with
public struct MonetizationPromptStyleConfiguration {
    
    /// The prompt's contents, exactly as the developer wrote them
    public let content: Content
    
    
    internal init(content: Content) {
        self.content = content
    }
    
    
    /// The prompt's contents, exactly as the developer wrote them.
    ///
    /// Place this wherever the contents belong within your style. Its internals are not yours to reach into; that's the
    /// point of it being opaque.
    public struct Content: View {
        
        /// What the developer wrote, held until a style decides where to put it
        internal let wrapped: AnyView
        
        public var body: some View { wrapped }
    }
}



// MARK: - Environment

/// A ``MonetizationPromptStyle`` with its type forgotten, so it can ride in the environment
internal struct AnyMonetizationPromptStyle {
    
    private let _makeBody: @MainActor (MonetizationPromptStyleConfiguration) -> AnyView
    
    
    init(_ style: some MonetizationPromptStyle) {
        self._makeBody = { AnyView(style.makeBody(configuration: $0)) }
    }
    
    
    @MainActor
    func makeBody(configuration: MonetizationPromptStyleConfiguration) -> AnyView {
        _makeBody(configuration)
    }
}



internal extension EnvironmentValues {
    
    /// How monetization prompts in this part of the hierarchy are dressed
    @Entry var monetizationPromptStyle = AnyMonetizationPromptStyle(DefaultMonetizationPromptStyle())
}



public extension View {
    
    /// Dresses every ``MonetizationPrompt`` in this part of the hierarchy with the given style
    ///
    /// - Parameter style: The style to use
    func monetizationPromptStyle(_ style: some MonetizationPromptStyle) -> some View {
        environment(\.monetizationPromptStyle, AnyMonetizationPromptStyle(style))
    }
}
