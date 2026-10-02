//
//  MonetizationPrompt + Style.swift
//  MonetizationTools
//
//  Created by Ky directing Claude Sonnet 5 on 2026-09-20.
//

import SwiftUI



public extension MonetizationPrompt {
    
    /// Decides everything around a prompt's content, so the content itself can stay entirely yours.
    ///
    /// This works the way `ButtonStyle` does for a button: a prompt hands its content to the style through a
    /// ``Configuration``, and the style decides what surrounds it. Conform to this and implement ``makeBody(configuration:)``
    /// to make your own, then apply it to any view with ``SwiftUI/View/monetizationPromptStyle(_:)``. It applies to every
    /// prompt inside that view.
    ///
    /// A style is never given the prompt's flow, so it can only change how a prompt looks, not whether or when it shows. It
    /// has to be `Sendable` so that it can travel through the environment.
    protocol Style: Sendable {
        
        /// The view which a style makes
        associatedtype Body: View
        
        /// What a style is given to work with. It's a prompt's content, ready to be placed wherever the style likes.
        typealias Configuration = MonetizationPrompt.StyleConfiguration
        
        
        /// Makes the view which surrounds a prompt's content.
        ///
        /// Only call ``MonetizationPrompt/StyleConfiguration/content`` in here; it's what the dev put in the prompt, and
        /// leaving it out would leave the person with no way to answer.
        ///
        /// - Parameter configuration: Holds the content to surround
        @MainActor
        @ViewBuilder
        func makeBody(configuration: Configuration) -> Body
        
        
        /// Makes the short status message which the prompt shows in place of its content: when an attempt is pending, and
        /// when it completes.
        ///
        /// This returns `Text`, so a style can change fonts and colors, and can't add buttons or run code. Use `text` as
        /// it's given; it's already localized.
        ///
        /// The default implementation returns `Text(text)`.
        ///
        /// - Parameter text: The message to show
        ///
        /// - Returns: The message, styled
        @MainActor
        func makeStatusBody(text: LocalizedStringResource) -> Text
    }
    
    
    
    /// What a ``MonetizationPrompt/Style`` is given to work with
    struct StyleConfiguration {
        
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
}



// MARK: - Defaults

public extension MonetizationPrompt.Style {
    
    /// Returns `Text(text)`, unstyled
    @MainActor
    func makeStatusBody(text: LocalizedStringResource) -> Text {
        Text(text)
    }
}



// MARK: - Applying a style

public extension View {
    
    /// Styles every ``MonetizationPrompt`` inside this view.
    ///
    /// The closest style to a prompt wins, so a style set on a screen overrides one set on the whole app.
    ///
    /// - Parameter style: The style to use, like ``MonetizationPrompt/Style/default`` or
    ///                    ``MonetizationPrompt/Style/plain``
    func monetizationPromptStyle<Style: MonetizationPrompt.Style>(_ style: Style) -> some View {
        environment(\.monetizationPromptStyle, MonetizationPrompt.AnyStyle(style))
    }
}



// MARK: - Environment

internal extension MonetizationPrompt {
    
    /// A ``MonetizationPrompt/Style`` with its type hidden, so it can travel through the environment.
    ///
    /// The environment has to hold one concrete type, and every style is a different one; this is that one type.
    struct AnyStyle: Sendable {
        
        /// The style's `makeBody`, with its result type hidden
        private let makeBodyOfWrappedStyle: @MainActor @Sendable (MonetizationPrompt.StyleConfiguration) -> AnyView
        
        /// The style's `makeStatusBody`
        private let makeStatusBodyOfWrappedStyle: @MainActor @Sendable (LocalizedStringResource) -> Text
        
        
        /// Hides the type of the given style
        ///
        /// - Parameter style: The style to wrap
        init<WrappedStyle: MonetizationPrompt.Style>(_ style: WrappedStyle) {
            self.makeBodyOfWrappedStyle = { configuration in
                AnyView(style.makeBody(configuration: configuration))
            }
            self.makeStatusBodyOfWrappedStyle = { text in
                style.makeStatusBody(text: text)
            }
        }
        
        
        /// Makes the view which surrounds a prompt's content, using the wrapped style
        ///
        /// - Parameter configuration: Holds the content to surround
        @MainActor
        func makeBody(configuration: MonetizationPrompt.StyleConfiguration) -> AnyView {
            makeBodyOfWrappedStyle(configuration)
        }
        
        
        /// Makes a status message, using the wrapped style
        ///
        /// - Parameter text: The message to show
        @MainActor
        func makeStatusBody(text: LocalizedStringResource) -> Text {
            makeStatusBodyOfWrappedStyle(text)
        }
    }
}



internal extension EnvironmentValues {
    
    /// The style which every prompt in this part of the view hierarchy uses. Without one being set, this is
    /// ``MonetizationPrompt/Style/default``.
    @Entry var monetizationPromptStyle: MonetizationPrompt.AnyStyle = MonetizationPrompt.AnyStyle(MonetizationPrompt.DefaultStyle())
}
