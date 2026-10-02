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
///         flow.present()                 // Required:   You should _always_ include a button which can call
///                                        // `flow.present()`. This is what actually presents the user with the
///                                        // ability to pay you.
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
    private let content: (Flow) -> AnyView
    
    /// This styles the prompt
    @Environment(\.monetizationPromptStyle) private var style
    
    /// Whether the prompt is currently added to the view hierarchy
    @State private var isShowing = false
    
    /// Whether the flow's `present()` is currently running. It lives here because the flow is remade each time this
    /// view is.
    @State private var isPresenting = false
    
    /// The status message shown in place of the prompt's content, or `nil` to show the content. It's cleared each time
    /// this view appears, so a status message only ever shows during the appearance where the attempt went pending.
    @State private var statusMessage: PromptStatusMessage? = nil
    
    /// The height of the first status message shown during this appearance. Later status messages are laid out at this
    /// height and clipped, so swapping one for another never moves anything around them.
    @State private var statusHeight: CGFloat? = nil
    
    /// The environment of this view, which the flow passes to the prompt's action
    @Environment(\.self) private var environment
    
    #if DEBUG
    /// The dev's binding from ``debug(monetizationPrompt:_:)``, or `nil` when none is attached
    @Environment(\.monetizationPromptDebugIsShowing) private var debugIsShowingOverride
    #endif
    
    
    /// Create a monetization prompt
    ///
    /// - Parameters:
    ///   - descriptor: The prompt to show
    ///   - content:    Builds what's inside it, given the things a person can do about it
    public init<Content: View>(
        for descriptor: Descriptor,
        @ViewBuilder content: @escaping (Flow) -> Content
    ) {
        self.descriptor = descriptor
        self.content = { AnyView(content($0)) }
    }
    
    
    /// Whether the prompt is on screen. Everything which reads or changes that goes through here.
    ///
    /// In release builds this is just `isShowing`. In debug builds, a binding attached with
    /// ``debug(monetizationPrompt:_:)`` decides what's shown, and every change is copied to it too, so it always matches.
    private var effectiveIsShowing: Binding<Bool> {
        Binding(
            get: {
                #if DEBUG
                return debugIsShowingOverride?.wrappedValue ?? isShowing
                #else
                return isShowing
                #endif
            },
            set: { newValue in
                isShowing = newValue
                #if DEBUG
                if let debugIsShowingOverride {
                    debugIsShowingOverride.wrappedValue = newValue
                }
                #endif
            }
        )
    }
    
    
    /// What a person can do about this prompt, handed to the dev's content
    private var flow: Flow {
        Flow(
            descriptor: descriptor,
            store: PromptStore(scope: descriptor.scope),
            environment: environment,
            isShowing: effectiveIsShowing,
            isPresenting: $isPresenting,
            statusMessage: $statusMessage,
            limiter: .shared
        )
    }
    
    
    /// The prompt's content in its style while it's showing, its status message in place of that content while there is
    /// one, or nothing while it isn't showing
    private var presentedContent: AnyView {
        if effectiveIsShowing.wrappedValue {
            if let statusMessage {
                return AnyView(statusView(for: statusMessage))
            }
            else {
                return style.makeBody(configuration: .init(
                    content: .init(wrapping: content(flow))
                ))
            }
        }
        else {
            return AnyView(EmptyView())
        }
    }
    
    
    /// A status message, made by the style.
    ///
    /// The first one shown during an appearance is measured. Every one after it is laid out at that measured height and
    /// clipped, so it never grows and moves what's below it.
    ///
    /// - Parameter message: The message to show
    @ViewBuilder
    private func statusView(for message: PromptStatusMessage) -> some View {
        let text = style.makeStatusBody(text: message.text)
        
        if let statusHeight {
            text
                .frame(height: statusHeight, alignment: .topLeading)
                .clipped()
        }
        else {
            text
                .background(GeometryReader { geometry in
                    Color.clear
                        .onAppear {
                            statusHeight = geometry.size.height
                        }
                })
        }
    }
    
    
    /// Decides what to show when this view appears, and starts whatever a pending or resolving prompt needs
    private func handleAppearance() {
        statusMessage = nil
        statusHeight = nil
        
        let decision = PromptStore(scope: descriptor.scope)?.check(descriptor) ?? .hide
        
        switch decision {
        case .show:
            effectiveIsShowing.wrappedValue = true
            
        case .hide:
            effectiveIsShowing.wrappedValue = false
            
        case .checkPending:
            effectiveIsShowing.wrappedValue = false
            Task {
                await flow.checkPending()
            }
            
        case .finishResolving:
            effectiveIsShowing.wrappedValue = false
            Task {
                await flow.finishResolving()
            }
        }
    }
    
    
    public var body: some View {
        presentedContent
        .onAppear {
            handleAppearance()
        }
    }
}
