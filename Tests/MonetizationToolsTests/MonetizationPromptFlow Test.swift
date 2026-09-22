//
//  MonetizationPromptFlow Test.swift
//  MonetizationTools
//
//  Created by Ky directing Claude Sonnet 5 on 2026-09-20.
//

import Foundation
import SwiftUI
import Testing
@testable import MonetizationTools



/// Checks that a flow changes a prompt's memory only for the things a person actually asked for
@MainActor
struct MonetizationPromptFlowTest {
    
    /// The identifier every prompt in these tests uses
    private static let identifier: MonetizationPromptIdentifier = "com.example.flow"
    
    
    /// Stands in for the state which a prompt's view owns and its flow changes
    @MainActor
    final class ViewState {
        
        /// Whether the prompt is on screen. It starts on screen, since a flow only exists for a prompt which is.
        var isShowing = true
        
        /// Whether `present()` is running
        var isPresenting = false
    }
    
    
    /// Makes a flow which acts on the given state and store, and runs the given action
    private func flow(running action: StubAction,
                       store: PromptStore,
                       state: ViewState) -> MonetizationPromptFlow {
        MonetizationPromptFlow(
            descriptor: MonetizationPrompt.Descriptor(Self.identifier, atMost: .monthly, action: action),
            store: store,
            environment: EnvironmentValues(),
            isShowing: Binding(get: { state.isShowing }, set: { state.isShowing = $0 }),
            isPresenting: Binding(get: { state.isPresenting }, set: { state.isPresenting = $0 })
        )
    }
    
    
    /// A completed offer is one of the only two things which end a prompt
    @Test func succeedingRetiresAndHidesThePrompt() async throws {
        try await withEphemeralDefaults { defaults in
            let store = PromptStore(defaults: defaults)
            let state = ViewState()
            
            try await flow(running: StubAction(.success(.succeeded)), store: store, state: state).present()
            
            #expect(false == state.isShowing)
            #expect(PromptHistory.done == store.reading(for: Self.identifier).recordedHistory)
        }
    }
    
    
    /// Backing out isn't refusing: nothing is recorded and the prompt stays on screen
    @Test func abandoningChangesNothing() async throws {
        try await withEphemeralDefaults { defaults in
            let store = PromptStore(defaults: defaults)
            let state = ViewState()
            
            try await flow(running: StubAction(.success(.abandoned)), store: store, state: state).present()
            
            #expect(state.isShowing)
            #expect(store.reading(for: Self.identifier).isNeverChecked)
        }
    }
    
    
    /// A failure reaches the dev to show however they like, and changes nothing
    @Test func throwingChangesNothingAndReachesTheCaller() async throws {
        try await withEphemeralDefaults { defaults in
            let store = PromptStore(defaults: defaults)
            let state = ViewState()
            let failingFlow = flow(running: StubAction(.failure(StubAction.StubError())), store: store, state: state)
            
            await #expect(throws: StubAction.StubError.self) {
                try await failingFlow.present()
            }
            
            #expect(state.isShowing)
            #expect(false == state.isPresenting)
            #expect(store.reading(for: Self.identifier).isNeverChecked)
        }
    }
    
    
    /// Once a call finishes, the next one is allowed to run
    @Test func presentingCanBeRepeatedAfterBackingOut() async throws {
        try await withEphemeralDefaults { defaults in
            let store = PromptStore(defaults: defaults)
            let state = ViewState()
            let counter = StubAction.Counter()
            let backingOutFlow = flow(running: StubAction(.success(.abandoned), counter: counter), store: store, state: state)
            
            try await backingOutFlow.present()
            try await backingOutFlow.present()
            
            #expect(2 == counter.count)
        }
    }
    
    
    /// A double tap must not start two purchases
    @Test func secondCallWhileFirstIsRunningDoesNothing() async throws {
        try await withEphemeralDefaults { defaults in
            let store = PromptStore(defaults: defaults)
            let state = ViewState()
            let counter = StubAction.Counter()
            let doubleTappedFlow = flow(running: StubAction(.success(.succeeded), counter: counter), store: store, state: state)
            
            async let first: Void = doubleTappedFlow.present()
            try await doubleTappedFlow.present()
            try await first
            
            #expect(1 == counter.count)
        }
    }
    
    
    /// Asking for later hides the prompt and starts a new wait, but doesn't end the prompt
    @Test func snoozingHidesAndStartsANewWait() async throws {
        try await withEphemeralDefaults { defaults in
            let store = PromptStore(defaults: defaults)
            let state = ViewState()
            
            flow(running: StubAction(), store: store, state: state).snooze()
            
            #expect(false == state.isShowing)
            
            guard case .tracking(interval: let interval, nextEligible: _) = try #require(store.reading(for: Self.identifier).recordedHistory) else {
                Issue.record("Snoozing should leave the prompt tracked, not retired")
                return
            }
            #expect(PromptInterval.monthly == interval)
        }
    }
    
    
    /// Declining is the person's own "never", the other thing which ends a prompt
    @Test func decliningRetiresAndHidesThePrompt() async throws {
        try await withEphemeralDefaults { defaults in
            let store = PromptStore(defaults: defaults)
            let state = ViewState()
            
            flow(running: StubAction(), store: store, state: state).decline()
            
            #expect(false == state.isShowing)
            #expect(PromptHistory.done == store.reading(for: Self.identifier).recordedHistory)
        }
    }
    
    
    #if DEBUG
    /// Resetting erases the history, but leaves the prompt on screen
    @Test func resettingErasesTheHistoryAndLeavesThePromptShowing() async throws {
        try await withEphemeralDefaults { defaults in
            let store = PromptStore(defaults: defaults)
            let state = ViewState()
            store.retire(Self.identifier)
            
            flow(running: StubAction(), store: store, state: state).reset()
            
            #expect(state.isShowing)
            #expect(store.reading(for: Self.identifier).isNeverChecked)
        }
    }
    #endif
}
