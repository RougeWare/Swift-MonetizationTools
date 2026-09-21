//
//  MonetizationPromptStyle.swift
//  MonetizationTools
//
//  Created by Ky directing Claude Sonnet 5 on 2026-09-20.
//

import SwiftUI



/// Decides everything around a prompt's content, so the content itself can stay entirely yours.
///
/// This works the way `ButtonStyle` does for a button: a prompt hands its content to the style through a
/// ``Configuration``, and the style decides what surrounds it. Conform to this and implement ``makeBody(configuration:)``
/// to make your own, then apply it to any view with ``SwiftUI/View/monetizationPromptStyle(_:)``. It applies to every
/// prompt inside that view.
///
/// A style is never given the prompt's flow, so it can only change how a prompt looks, not whether or when it shows. It
/// has to be `Sendable` so that it can travel through the environment.
public protocol MonetizationPromptStyle: Sendable {
    
    /// The view which a style makes
    associatedtype Body: View
    
    /// What a style is given to work with. It's a prompt's content, ready to be placed wherever the style likes.
    typealias Configuration = MonetizationPromptStyleConfiguration
    
    
    /// Makes the view which surrounds a prompt's content.
    ///
    /// Only call ``MonetizationPromptStyleConfiguration/content`` in here; it's what the dev put in the prompt, and
    /// leaving it out would leave the person with no way to answer.
    ///
    /// - Parameter configuration: Holds the content to surround
    @MainActor
    @ViewBuilder
    func makeBody(configuration: Configuration) -> Body
}



/// What a ``MonetizationPromptStyle`` is given to work with
public struct MonetizationPromptStyleConfiguration {
    
    /// A prompt's content, ready to place wherever a style likes. It's a view, so a style can wrap it, pad it, or put
    /// it in a container, but it can't see inside it.
    public struct Content: View {
        
        /// The dev's content, with its type hidden, since a style can't depend on what it is
        private let wrapped: AnyView
        
        
        /// Hides the type of the given view
        ///
        /// - Parameter view: The content to wrap
        internal init(wrapping view: some View) {
            self.wrapped = AnyView(view)
        }
        
        
        public var body: some View {
            wrapped
        }
    }
    
    
    /// The prompt's content, ready to place wherever a style likes
    public let content: Content
}



// MARK: - Applying a style

public extension View {
    
    /// Styles every ``MonetizationPrompt`` inside this view.
    ///
    /// The closest style to a prompt wins, so a style set on a screen overrides one set on the whole app.
    ///
    /// - Parameter style: The style to use, like ``MonetizationPromptStyle/default`` or ``MonetizationPromptStyle/plain``
    func monetizationPromptStyle<Style: MonetizationPromptStyle>(_ style: Style) -> some View {
        environment(\.monetizationPromptStyle, AnyMonetizationPromptStyle(style))
    }
}



// MARK: - Environment

/// A ``MonetizationPromptStyle`` with its type hidden, so it can travel through the environment.
///
/// The environment has to hold one concrete type, and every style is a different one; this is that one type.
internal struct AnyMonetizationPromptStyle: Sendable {
    
    /// The style's `makeBody`, with its result type hidden
    private let makeBodyOfWrappedStyle: @MainActor @Sendable (MonetizationPromptStyleConfiguration) -> AnyView
    
    
    /// Hides the type of the given style
    ///
    /// - Parameter style: The style to wrap
    init<Style: MonetizationPromptStyle>(_ style: Style) {
        self.makeBodyOfWrappedStyle = { configuration in
            AnyView(style.makeBody(configuration: configuration))
        }
    }
    
    
    /// Makes the view which surrounds a prompt's content, using the wrapped style
    ///
    /// - Parameter configuration: Holds the content to surround
    @MainActor
    func makeBody(configuration: MonetizationPromptStyleConfiguration) -> AnyView {
        makeBodyOfWrappedStyle(configuration)
    }
}



internal extension EnvironmentValues {
    
    /// The style which every prompt in this part of the view hierarchy uses. Without one being set, this is
    /// ``MonetizationPromptStyle/default``.
    @Entry var monetizationPromptStyle: AnyMonetizationPromptStyle = AnyMonetizationPromptStyle(DefaultMonetizationPromptStyle())
}
