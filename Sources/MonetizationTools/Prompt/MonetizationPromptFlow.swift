//
//  MonetizationPromptFlow.swift
//  MonetizationTools
//
//  Created by Ky directing Claude Sonnet 5 on 2026-09-20.
//

import SwiftUI



/// The things a person can do about a monetization prompt, handed to the content you put in it.
///
/// Every button in a prompt calls one of these three, and nothing else about the prompt needs your code:
///
/// - ``present()`` when they want what the prompt offers
/// - ``snooze()`` when they want to be asked again later
/// - ``decline()`` when they never want to be asked again
///
/// You don't make one of these; ``MonetizationPrompt`` gives you one. It already knows about the view it's in, so
/// there's nothing to pass to it.
///
/// It only does what a person asked for. If they do none of the three, nothing changes, and the prompt stays where it is.
@MainActor
public struct MonetizationPromptFlow {
    
    /// Describes the prompt this flow acts on
    private let descriptor: MonetizationPrompt.Descriptor
    
    /// Where this prompt's history is kept. It's `nil` only when the prompt's App Group can't be opened, and then the
    /// prompt was never on screen for anyone to act on it.
    private let store: PromptStore?
    
    /// The environment of the view which shows the prompt. Actions use it to do things which only SwiftUI can do
    /// correctly, like presenting a purchase sheet in the right window.
    private let environment: EnvironmentValues
    
    /// Whether the prompt is on screen. This flow turns it off when a person is done with the prompt.
    private let isShowing: Binding<Bool>
    
    /// Whether ``present()`` is currently running. A prompt owns this, since a flow is remade each time the prompt's
    /// view is, so this is what lets a double tap start only one purchase.
    private let isPresenting: Binding<Bool>
    
    
    /// Makes the flow for one prompt.
    ///
    /// - Parameters:
    ///   - descriptor:   Describes the prompt this flow acts on
    ///   - store:        Where this prompt's history is kept
    ///   - environment:  The environment of the view which shows the prompt
    ///   - isShowing:    Whether the prompt is on screen
    ///   - isPresenting: Whether ``present()`` is currently running
    internal init(descriptor: MonetizationPrompt.Descriptor,
                  store: PromptStore?,
                  environment: EnvironmentValues,
                  isShowing: Binding<Bool>,
                  isPresenting: Binding<Bool>) {
        self.descriptor = descriptor
        self.store = store
        self.environment = environment
        self.isShowing = isShowing
        self.isPresenting = isPresenting
    }
}



// MARK: - What a person can do

public extension MonetizationPromptFlow {
    
    /// Gives the person what the prompt offers, like a purchase sheet.
    ///
    /// Call this from the button they tap to accept. It's `async`, so call it from a `Task`. It returns once they've
    /// finished with whatever it showed.
    ///
    /// - If they complete it, the prompt goes away and never shows again.
    /// - If they back out, nothing changes and the prompt stays on screen.
    /// - If it throws, nothing changes and the prompt stays on screen. Show the error if you like; what it is depends on
    ///   the prompt's action.
    ///
    /// Calling this while a previous call is still running does nothing, so a double tap can't start two purchases.
    func present() async throws {
        if isPresenting.wrappedValue {
            return
        }
        
        isPresenting.wrappedValue = true
        defer { isPresenting.wrappedValue = false }
        
        let outcome = try await descriptor.action.perform(id: descriptor.identifier, in: environment)
        
        switch outcome {
        case .succeeded:
            retireAndHide()
            
        case .abandoned:
            break
        }
    }
    
    
    /// Hides the prompt for now, and starts a new wait of one full interval before it can show again.
    ///
    /// Call this from the button they tap to say "later".
    func snooze() {
        store?.snooze(descriptor)
        isShowing.wrappedValue = false
    }
    
    
    /// Hides the prompt for good. It never shows again, in any app which shares its scope.
    ///
    /// Call this from the button they tap to say "never".
    func decline() {
        retireAndHide()
    }
}



// MARK: - Retiring

private extension MonetizationPromptFlow {
    
    /// Ends this prompt for good: it's remembered as done, and it leaves the screen. A declined prompt and a fulfilled
    /// one end the same way.
    func retireAndHide() {
        store?.retire(descriptor.identifier)
        isShowing.wrappedValue = false
    }
}
