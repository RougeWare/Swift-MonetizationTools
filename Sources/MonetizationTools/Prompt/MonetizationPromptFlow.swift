//
//  MonetizationPromptFlow.swift
//  MonetizationTools
//
//  Created by Ky on 2026-09-14.
//

import Foundation



/// The three things a person can do about a monetization prompt, handed to you so your own buttons can do them.
///
/// Nothing here is required, but a prompt offering no ``decline()`` is a prompt nobody can ever be rid of.
@MainActor
public struct MonetizationPromptFlow {
    
    /// The prompt this flow acts upon
    public let descriptor: MonetizationPrompt.Descriptor
    
    /// Takes this prompt off the screen it's currently on, without touching what's persisted
    private let dismiss: @MainActor () -> Void
    
    
    internal init(descriptor: MonetizationPrompt.Descriptor, dismiss: @escaping @MainActor () -> Void) {
        self.descriptor = descriptor
        self.dismiss = dismiss
    }
}



public extension MonetizationPromptFlow {
    
    /// Takes this prompt up on its offer, doing whatever its action does.
    ///
    /// On ``MonetizationPromptActionOutcome/succeeded``, the prompt retires permanently and disappears. On
    /// ``MonetizationPromptActionOutcome/pending`` or ``MonetizationPromptActionOutcome/notCompleted``, nothing is
    /// recorded and the prompt keeps its existing schedule. Backing out of an offer is not the same as asking not to be
    /// asked.
    ///
    /// - Returns: What became of the action
    /// - Throws: Whatever the action threw
    @discardableResult
    func present() async throws -> MonetizationPromptActionOutcome {
        let outcome = try await descriptor.action.perform(for: descriptor.identifier)
        
        if .succeeded == outcome {
            store.retire(descriptor)
            dismiss()
        }
        
        return outcome
    }
    
    
    /// Not now. Pushes this prompt out by one of its own intervals and takes it off the screen.
    func snooze() {
        store.snooze(descriptor)
        dismiss()
    }
    
    
    /// Not ever. Retires this prompt permanently and takes it off the screen.
    func decline() {
        store.retire(descriptor)
        dismiss()
    }
}



private extension MonetizationPromptFlow {
    
    /// The store which remembers this prompt
    var store: MonetizationPromptStore {
        .store(for: descriptor.scope)
    }
}
