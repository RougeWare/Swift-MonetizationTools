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

/// A ``MonetizationPromptStyle`` with its type forgotten, so it can ride in the environment.
///
/// This erases through a generic box rather than a stored closure. A closure typed as `@MainActor` is itself a
/// commitment about where it runs, and forming one requires already being on the main actor at the point of capture —
/// but this type's `init` is reached from `@Entry`'s synthesized default value below, which is not main-actor-isolated,
/// so that commitment can't be made honestly at construction time. A box defers the isolated part to a method call
/// instead, which only ever happens from `makeBody(configuration:)`, already correctly isolated below, so nothing here
/// needs to be Sendable and nothing needs to be sent anywhere.
internal struct AnyMonetizationPromptStyle {
    
    private let box: any MonetizationPromptStyleBox
    
    
    init(_ style: some MonetizationPromptStyle) {
        self.box = ConcreteMonetizationPromptStyleBox(style: style)
    }
    
    
    @MainActor
    func makeBody(configuration: MonetizationPromptStyleConfiguration) -> AnyView {
        box.makeBody(configuration: configuration)
    }
}



/// Holds one ``MonetizationPromptStyle``, generically, behind a non-generic interface
private protocol MonetizationPromptStyleBox {
    @MainActor func makeBody(configuration: MonetizationPromptStyleConfiguration) -> AnyView
}



private struct ConcreteMonetizationPromptStyleBox<Style: MonetizationPromptStyle>: MonetizationPromptStyleBox {
    
    let style: Style
    
    
    @MainActor
    func makeBody(configuration: MonetizationPromptStyleConfiguration) -> AnyView {
        AnyView(style.makeBody(configuration: configuration))
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
