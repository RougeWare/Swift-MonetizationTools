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



/// Checks that a flow changes a prompt's memory only for the things a person actually asked for, and records every
/// attempt in an order which survives a crash
@MainActor
struct MonetizationPromptFlowTest {
    
    /// The identifier every prompt in these tests uses
    private static let identifier: MonetizationPrompt.Identifier = "com.example.flow"
    
    
    /// Stands in for the state which a prompt's view owns and its flow changes
    @MainActor
    final class ViewState {
        
        /// Whether the prompt is on screen. It starts on screen, since a flow only exists for a prompt which is.
        var isShowing = true
        
        /// Whether `present()` is running
        var isPresenting = false
        
        /// The status message in place of the prompt's content, if any
        var statusMessage: PromptStatusMessage? = nil
    }
    
    
    /// Makes a flow which acts on the given state and store, and runs the given paymentHandler
    private func flow(running action: StubAction,
                       store: PromptStore,
                       state: ViewState,
                       limiter: PendingCheckLimiter = PendingCheckLimiter()) -> MonetizationPrompt.Flow {
        MonetizationPrompt.Flow(
            descriptor: MonetizationPrompt.Descriptor(Self.identifier, atMost: .weekly, action: action),
            store: store,
            environment: EnvironmentValues(),
            isShowing: Binding(get: { state.isShowing }, set: { state.isShowing = $0 }),
            disablePrompt: .constant(false),
            isPresenting: Binding(get: { state.isPresenting }, set: { state.isPresenting = $0 }),
            statusMessage: Binding(get: { state.statusMessage }, set: { state.statusMessage = $0 }),
            limiter: limiter
        )
    }
    
    
    /// Stores the state a prompt has when it's due and on screen
    private func storeDuePrompt(in store: PromptStore) throws {
        store.persist(.scheduled(interval: .weekly, nextEligible: try Date.noon(year: 2026, month: 1, day: 1)), for: Self.identifier)
    }
    
    
    // MARK: Attempts
    
    /// The attempt is stored as pending before the paymentHandler runs, so a crash during it leaves a state that says so
    @Test func stateIsPendingWhileTheActionRuns() async throws {
        try await withEphemeralDefaults { defaults in
            let store = PromptStore(defaults: defaults)
            let state = ViewState()
            let counter = StubAction.Counter()
            try storeDuePrompt(in: store)
            var stateDuringPerform: PromptState? = nil
            counter.onLaunch = { stateDuringPerform = store.lookUpState(for: Self.identifier).recordedState }
            
            try await flow(running: StubAction(.success(.abandoned), counter: counter), store: store, state: state).present()
            
            guard case .some(.resolving(interval: let interval, since: _)) = stateDuringPerform else {
                Issue.record("The state should be pending while the paymentHandler runs, but it was \(String(describing: stateDuringPerform))")
                return
            }
            #expect(PromptInterval.weekly == interval)
        }
    }
    
    
    /// A success is stored as resolving, then acknowledged, then stored as done, in that order
    @Test func succeedingRecordsResolvingThenAcknowledgesThenRetires() async throws {
        try await withEphemeralDefaults { defaults in
            let store = PromptStore(defaults: defaults)
            let state = ViewState()
            let counter = StubAction.Counter()
            try storeDuePrompt(in: store)
            var stateDuringAcknowledgment: PromptState? = nil
            counter.onHandleSuccess = { stateDuringAcknowledgment = store.lookUpState(for: Self.identifier).recordedState }
            
            try await flow(running: StubAction(.success(.succeeded), counter: counter), store: store, state: state).present()
            
            guard case .some(.resolving) = stateDuringAcknowledgment else {
                Issue.record("The state should be resolving during success handling, but it was \(String(describing: stateDuringAcknowledgment))")
                return
            }
            #expect([.launch, .handleSuccess] == counter.events)
            #expect(false == state.isShowing)
            #expect(PromptState.done == store.lookUpState(for: Self.identifier).recordedState)
        }
    }
    
    
    /// Backing out isn't refusing: the prompt stays on screen, and is due again right away
    @Test func abandoningLeavesThePromptDue() async throws {
        try await withEphemeralDefaults { defaults in
            let store = PromptStore(defaults: defaults)
            let state = ViewState()
            try storeDuePrompt(in: store)
            
            try await flow(running: StubAction(.success(.abandoned)), store: store, state: state).present()
            
            #expect(state.isShowing)
            #expect(PromptLoadAction.show == store.check(MonetizationPrompt.Descriptor(Self.identifier, atMost: .weekly, action: StubAction())))
        }
    }
    
    
    /// A failure reaches the dev to show however they like, and leaves the prompt due and on screen
    @Test func throwingLeavesThePromptDueAndReachesTheCaller() async throws {
        try await withEphemeralDefaults { defaults in
            let store = PromptStore(defaults: defaults)
            let state = ViewState()
            try storeDuePrompt(in: store)
            let failingFlow = flow(running: StubAction(.failure(StubAction.StubError())), store: store, state: state)
            
            await #expect(throws: StubAction.StubError.self) {
                try await failingFlow.present()
            }
            
            #expect(state.isShowing)
            #expect(false == state.isPresenting)
            #expect(PromptLoadAction.show == store.check(MonetizationPrompt.Descriptor(Self.identifier, atMost: .weekly, action: StubAction())))
        }
    }
    
    
    /// Waiting on someone else keeps the prompt on screen with the pending message, and starts one check right away
    @Test func pendingShowsTheStatusAndStartsACheck() async throws {
        try await withEphemeralDefaults { defaults in
            let store = PromptStore(defaults: defaults)
            let state = ViewState()
            let counter = StubAction.Counter()
            try storeDuePrompt(in: store)
            
            try await flow(running: StubAction(.success(.pending), counter: counter), store: store, state: state).present()
            await waitUntil { counter.events.contains(.checkPending) }
            
            #expect(state.isShowing)
            #expect(PromptStatusMessage.pending == state.statusMessage)
            #expect(counter.events.contains(.checkPending))
            guard case .some(.pending) = store.lookUpState(for: Self.identifier).recordedState else {
                Issue.record("The state should still be pending")
                return
            }
        }
    }
    
    
    /// A pending attempt which succeeds while its message is on screen swaps to the completed message, and doesn't hide
    @Test func successWhileThePendingMessageShowsSwapsToCompleted() async throws {
        try await withEphemeralDefaults { defaults in
            let store = PromptStore(defaults: defaults)
            let state = ViewState()
            let counter = StubAction.Counter()
            try storeDuePrompt(in: store)
            
            try await flow(running: StubAction(.success(.pending), pendingResult: .succeeded, counter: counter), store: store, state: state).present()
            await waitUntil { PromptState.done == store.lookUpState(for: Self.identifier).recordedState }
            
            #expect(state.isShowing)
            #expect(PromptStatusMessage.completed == state.statusMessage)
            #expect(PromptState.done == store.lookUpState(for: Self.identifier).recordedState)
        }
    }
    
    
    /// Once a call finishes, the next one is allowed to run
    @Test func presentingCanBeRepeatedAfterBackingOut() async throws {
        try await withEphemeralDefaults { defaults in
            let store = PromptStore(defaults: defaults)
            let state = ViewState()
            let counter = StubAction.Counter()
            try storeDuePrompt(in: store)
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
            try storeDuePrompt(in: store)
            let doubleTappedFlow = flow(running: StubAction(.success(.succeeded), counter: counter), store: store, state: state)
            
            async let first: Void = try await doubleTappedFlow.present()
            try await doubleTappedFlow.present()
            try await first
            
            #expect(1 == counter.count)
        }
    }
    
    
    /// The version without `try` or `await` does the same work as the throwing one
    @Test func presentingWithoutWaitingDoesTheSameWork() async throws {
        try await withEphemeralDefaults { defaults in
            let store = PromptStore(defaults: defaults)
            let state = ViewState()
            let counter = StubAction.Counter()
            try storeDuePrompt(in: store)
            let fireAndForgetFlow = flow(running: StubAction(.success(.succeeded), counter: counter), store: store, state: state)
            
            let presentWithoutWaiting: @MainActor () -> Void = fireAndForgetFlow.present
            presentWithoutWaiting()
            await waitUntil { PromptState.done == store.lookUpState(for: Self.identifier).recordedState }
            
            #expect(false == state.isShowing)
            #expect(PromptState.done == store.lookUpState(for: Self.identifier).recordedState)
        }
    }
    
    
    // MARK: Checks
    
    /// A check which learns of a success retires the prompt
    @Test func checkThatSucceedsRetires() async throws {
        try await withEphemeralDefaults { defaults in
            let store = PromptStore(defaults: defaults)
            let state = ViewState()
            let counter = StubAction.Counter()
            store.persist(.pending(interval: .weekly, since: .now), for: Self.identifier)
            
            await flow(running: StubAction(pendingResult: .succeeded, counter: counter), store: store, state: state).checkPending()
            
            #expect([.checkPending, .handleSuccess] == counter.events)
            #expect(PromptState.done == store.lookUpState(for: Self.identifier).recordedState)
        }
    }
    
    
    /// A check which learns of an abandoned attempt schedules the prompt one interval later
    @Test func checkThatAbandonsSchedulesOneIntervalLater() async throws {
        try await withEphemeralDefaults { defaults in
            let store = PromptStore(defaults: defaults)
            let state = ViewState()
            store.persist(.pending(interval: .weekly, since: .now), for: Self.identifier)
            
            await flow(running: StubAction(pendingResult: .abandoned), store: store, state: state).checkPending()
            
            guard case .some(.scheduled(interval: .weekly, nextEligible: let nextEligible)) = store.lookUpState(for: Self.identifier).recordedState else {
                Issue.record("The prompt should be scheduled again")
                return
            }
            #expect(Date.now.addingTimeInterval(6 * 24 * 60 * 60) < nextEligible)
        }
    }
    
    
    /// A check which still doesn't know, before the give-up time, changes nothing
    @Test func unknownBeforeGivingUpChangesNothing() async throws {
        try await withEphemeralDefaults { defaults in
            let store = PromptStore(defaults: defaults)
            let state = ViewState()
            let since = Date(timeIntervalSince1970: Date.now.timeIntervalSince1970.rounded(.down)) // Stored dates keep whole seconds
            store.persist(.pending(interval: .weekly, since: since), for: Self.identifier)
            
            await flow(running: StubAction(pendingResult: .currentStateUnknown), store: store, state: state).checkPending()
            
            #expect(PromptState.pending(interval: .weekly, since: since) == store.lookUpState(for: Self.identifier).recordedState)
        }
    }
    
    
    /// A check which still doesn't know, after the give-up time, schedules the prompt one interval later
    @Test func unknownAfterGivingUpSchedulesOneIntervalLater() async throws {
        try await withEphemeralDefaults { defaults in
            let store = PromptStore(defaults: defaults)
            let state = ViewState()
            store.persist(.pending(interval: .weekly, since: .now + .days(-3)), for: Self.identifier)
            
            await flow(running: StubAction(pendingResult: .currentStateUnknown, maxCheckingTime: .days(1)), store: store, state: state).checkPending()
            
            guard case .some(.scheduled(interval: .weekly, nextEligible: _)) = store.lookUpState(for: Self.identifier).recordedState else {
                Issue.record("The prompt should be scheduled again")
                return
            }
        }
    }
    
    
    /// A result for a prompt which is no longer pending is ignored
    @Test func resultForAPromptNoLongerPendingIsIgnored() async throws {
        try await withEphemeralDefaults { defaults in
            let store = PromptStore(defaults: defaults)
            let state = ViewState()
            let counter = StubAction.Counter()
            store.retire(Self.identifier)
            
            await flow(running: StubAction(pendingResult: .abandoned, counter: counter), store: store, state: state).checkPending()
            
            #expect(PromptState.done == store.lookUpState(for: Self.identifier).recordedState)
            #expect(false == counter.events.contains(.handleSuccess))
        }
    }
    
    
    /// A second check soon after the first does nothing
    @Test func checksAreSpacedApart() async throws {
        try await withEphemeralDefaults { defaults in
            let store = PromptStore(defaults: defaults)
            let state = ViewState()
            let counter = StubAction.Counter()
            store.persist(.pending(interval: .weekly, since: .now), for: Self.identifier)
            let checkingFlow = flow(running: StubAction(counter: counter), store: store, state: state)
            
            await checkingFlow.checkPending()
            await checkingFlow.checkPending()
            
            #expect([.checkPending] == counter.events)
        }
    }
    
    
    /// An interrupted success is finished on the next appearance, without asking the paymentHandler again what happened
    @Test func resolvingIsFinishedWithoutCheckingAgain() async throws {
        try await withEphemeralDefaults { defaults in
            let store = PromptStore(defaults: defaults)
            let state = ViewState()
            let counter = StubAction.Counter()
            store.persist(.resolving(interval: .weekly, since: .now), for: Self.identifier)
            
            await flow(running: StubAction(counter: counter), store: store, state: state).finishResolving()
            
            #expect([.handleSuccess] == counter.events)
            #expect(PromptState.done == store.lookUpState(for: Self.identifier).recordedState)
        }
    }
    
    
    /// An paymentHandler which doesn't implement checking reports that it doesn't know, and acknowledging does nothing
    @Test func defaultsDontKnowAndDoNothing() async {
        let action = MinimalPaymentHandler()
        
        let outcome = await action.checkPending(id: Self.identifier)
        await action.handleSuccess(id: Self.identifier)
        
        #expect(PaymentOutcome.currentStateUnknown == outcome)
    }
    
    
    // MARK: Snoozing and declining
    
    /// Asking for later hides the prompt and starts a new wait, but doesn't end the prompt
    @Test func snoozingHidesAndStartsANewWait() async throws {
        try await withEphemeralDefaults { defaults in
            let store = PromptStore(defaults: defaults)
            let state = ViewState()
            
            flow(running: StubAction(), store: store, state: state).snooze()
            
            #expect(false == state.isShowing)
            
            guard case .scheduled(interval: let interval, nextEligible: _) = try #require(store.lookUpState(for: Self.identifier).recordedState) else {
                Issue.record("Snoozing should leave the prompt scheduled, not retired")
                return
            }
            #expect(PromptInterval.weekly == interval)
        }
    }
    
    
    /// Declining is the person's own "never", the other thing which ends a prompt
    @Test func decliningRetiresAndHidesThePrompt() async throws {
        try await withEphemeralDefaults { defaults in
            let store = PromptStore(defaults: defaults)
            let state = ViewState()
            
            flow(running: StubAction(), store: store, state: state).decline()
            
            #expect(false == state.isShowing)
            #expect(PromptState.done == store.lookUpState(for: Self.identifier).recordedState)
        }
    }
    
    
    #if DEBUG
    /// Resetting erases the stored state and the spacing between checks, but leaves the prompt on screen
    @Test func resettingErasesTheStateAndTheSpacing() async throws {
        try await withEphemeralDefaults { defaults in
            let store = PromptStore(defaults: defaults)
            let state = ViewState()
            let counter = StubAction.Counter()
            let limiter = PendingCheckLimiter()
            store.persist(.pending(interval: .weekly, since: .now), for: Self.identifier)
            let resettingFlow = flow(running: StubAction(counter: counter), store: store, state: state, limiter: limiter)
            await resettingFlow.checkPending()
            
            resettingFlow.reset()
            store.persist(.pending(interval: .weekly, since: .now), for: Self.identifier)
            await resettingFlow.checkPending()
            
            #expect(state.isShowing)
            #expect([.checkPending, .checkPending] == counter.events)
        }
    }
    #endif
}
