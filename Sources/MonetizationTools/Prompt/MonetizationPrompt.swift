//
//  MonetizationPrompt.swift
//  MonetizationTools
//
//  Created by Ky on 2026-09-14.
//

import SwiftUI



/// A voluntary, dismissable ask, shown at most as often as its descriptor allows, which never inserts itself under
/// anyone's finger.
///
/// You write the contents; this decides whether they're on screen and remembers what was decided about them:
///
/// ```swift
/// MonetizationPrompt(for: .licensePurchase) { flow in
///     Text("Purchase a license?")
///     Button("Purchase now") { Task { try await flow.present() } }
///     Button("Later") { flow.snooze() }
///     Button("Never") { flow.decline() }
/// }
/// .monetizationPromptStyle(.default)
/// ```
///
/// Visibility is decided once, when this view appears, and then left alone for as long as it's on screen. A prompt
/// whose moment arrives while someone is sitting on the screen it lives on waits until the next time they arrive,
/// rather than materializing under a finger which was already on its way somewhere else.
public struct MonetizationPrompt: View {
    
    /// The prompt being shown
    private let descriptor: Descriptor
    
    /// Builds what's inside the prompt
    private let content: (MonetizationPromptFlow) -> AnyView
    
    /// How the prompt is dressed
    @Environment(\.monetizationPromptStyle) private var style
    
    /// Whether the prompt is on screen. Decided on appearance, and thereafter only by the person using the app.
    @State private var isShowing = false
    
    
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
                    content: .init(wrapped: content(flow))
                ))
            }
        }
        .onAppear {
            isShowing = MonetizationPromptStore.store(for: descriptor.scope).shouldShow(descriptor)
        }
    }
    
    
    /// The things a person can do about this prompt
    private var flow: MonetizationPromptFlow {
        .init(descriptor: descriptor) {
            isShowing = false
        }
    }
}
