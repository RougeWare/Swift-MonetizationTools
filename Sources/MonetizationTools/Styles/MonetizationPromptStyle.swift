//
//  MonetizationPromptStyle.swift
//  MonetizationTools
//
//  Created by Ky directing Claude Opus 5 on 2026-09-14.
//

import SwiftUI



/// Controls how a ``MonetizationPrompt`` is laid out and decorated, the way `ButtonStyle` controls how a button
/// looks, separately from the button's own label.
///
/// You write the prompt's contents; a style decides the frame, background, spacing, and anything else around them.
/// The same style can be reused across every prompt in your app, applied per-screen, or written just to keep one
/// prompt's own view code tidy — none of that changes what this protocol does or requires of you. A style never
/// touches or knows about the copy, buttons, or layout choices inside the prompt itself; it only wraps them.
public protocol MonetizationPromptStyle {
    
    /// What this style produces
    associatedtype Body: View
    
    /// Builds this style's view for the given prompt
    ///
    /// - Parameter configuration: The prompt's contents, and anything else worth knowing about it
    @ViewBuilder @MainActor
    func makeBody(configuration: Configuration) -> Body
    
    
    /// Everything a style is given to work with
    typealias Configuration = MonetizationPromptStyleConfiguration
}



/// Everything a ``MonetizationPromptStyle`` is given to work with
public struct MonetizationPromptStyleConfiguration {
    
    /// The prompt's contents, exactly as the developer wrote them.
    ///
    /// Place this wherever the contents belong within your style. Its internals are not accessible to you; a style
    /// arranges the contents, it doesn't inspect or alter them.
    public let content: Content
    
    
    internal init(content: Content) {
        self.content = content
    }
    
    
    /// The prompt's contents, exactly as the developer wrote them
    public struct Content: View {
        
        /// What the developer wrote, held until a style decides where to put it
        internal let wrapped: AnyView
        
        public var body: some View { wrapped }
    }
}



// MARK: - Environment

/// A type-erased ``MonetizationPromptStyle``, so one concrete style can be stored in the environment regardless of
/// which type actually implements it.
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



/// The concrete implementation of ``MonetizationPromptStyleBox``, holding one specific, generic `Style`.
///
/// This is the other half of the type-erasure `AnyMonetizationPromptStyle` performs: `AnyMonetizationPromptStyle`
/// itself can't store a generic `Style` directly without becoming generic, which would defeat the point of erasing it
/// in the first place, so it stores this instead, behind the non-generic `MonetizationPromptStyleBox` protocol.
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
    
    /// Applies the given style to every ``MonetizationPrompt`` in this part of the hierarchy
    ///
    /// - Parameter style: The style to use
    func monetizationPromptStyle(_ style: some MonetizationPromptStyle) -> some View {
        environment(\.monetizationPromptStyle, AnyMonetizationPromptStyle(style))
    }
}
