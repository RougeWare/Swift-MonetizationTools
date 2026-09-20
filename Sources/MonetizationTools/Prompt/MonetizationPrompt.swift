//
//  MonetizationPrompt.swift
//  MonetizationTools
//
//  Created by Ky directing Claude Opus 5 on 2026-09-14.
//

import SwiftUI



/// A voluntary, dismissable prompt for payment.
///
/// This prompt will automatically show only as its descriptor allows, and never inserts itself under the user's finger.
///
/// Initialize this in your SwiftUI view, giving it a descriptor and the view content you want in it.
/// This will decide when they're on screen, taking into account everything required by the descriptor and what actions the user has taken in the past.
///
/// ```swift
/// MonetizationPrompt(for: .licensePurchase) { flow in
///     Text("Purchase a license?")
///     Button("Purchase now") {
///         do {
///             try flow.present()         // Required:   You should _always_ include a button which can call
///                                        // `flow.present()`. This is what actually presents the user with the
///                                        // ability to pay you.
///         }
///     }
///     Button("Later") { flow.snooze() }  // Encouraged: You may include a button which allows the user to temporarily
///                                        // make this prompt disappear. The prompt will automatically reapper when it
///                                        // decides that's appropriate.
///
///     Button("Never") { flow.decline() } // Optional:   You may include a button which allows the user to
///                                        // permanently make this prompt disappear. The prompt will never appear ever
///                                        // again, unless all UserDefaults are reset
///                                        // (e.g. the user deletes & re-installs the app).
/// }
/// .monetizationPromptStyle(.default)
/// ```
///
/// - Attention: Each descriptor is **only read once**, the first time it's passed to a `MonetizationPrompt`. Then it's saved to the user's device, and that saved copy is what's used later.
///              This means that any changes to the descriptor across runtimes and view changes won't take effect.
public struct MonetizationPrompt: View {
    
    /// Identifies the prompt and describes its behavior
    private let descriptor: Descriptor
    
    /// The prompt content the dev provided
    private let content: (MonetizationPromptFlow) -> AnyView
    
    /// This styles the prompt
    @Environment(\.monetizationPromptStyle) private var style
    
    /// Whether the prompt is currently added to the view hierarchy
    @State private var isShowing = false
    
    
    /// Create a monetization prompt
    ///
    /// - Parameters:
    ///   - descriptor: The prompt to show
    ///   - content:    Builds what's inside it, given the things a person can do about it
    public init<Content: View>(
        for descriptor: Descriptor,
        @ViewBuilder content: @escaping (MonetizationPromptFlow) -> Content
    ) {
        self.descriptor = descriptor
        self.content = { AnyView(content($0)) }
    }
    
    
    public var body: some View {
        Group {
            if isShowing {
                style.makeBody(configuration: .init(
                    content: .init(wrapping: content(flow))
                ))
            }
        }
        .onAppear {
            isShowing = // figure this out based on the descriptor and past appearances, dismissals, etc.
        }
    }
}
