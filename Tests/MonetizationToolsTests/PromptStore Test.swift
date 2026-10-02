//
//  PromptStore Test.swift
//  MonetizationTools
//
//  Created by Ky directing Claude Sonnet 5 on 2026-09-20.
//

import Foundation
import Testing
@testable import MonetizationTools



/// Checks that prompts are remembered correctly, and stay quiet when what's remembered can't be trusted.
///
/// Every test uses its own throwaway defaults database, so nothing here touches the standard defaults.
@MainActor
struct PromptStoreTest {
    
    /// A prompt declared the way an app would declare it
    private func descriptor(_ identifier: MonetizationPrompt.Identifier = "com.example.test",
                            atMost interval: PromptInterval = .monthly) -> MonetizationPrompt.Descriptor {
        MonetizationPrompt.Descriptor(identifier, atMost: interval, action: StubAction())
    }
    
    
    /// The key is a compatibility promise: if it ever changes, everyone who declined is asked again. This is the one
    /// test which must never be edited to match the code.
    @Test func keyNeverChanges() {
        #expect("MonetizationTools.prompt.com.example.test" == PromptStore.key(for: "com.example.test"))
    }
    
    
    /// Nothing is stored until something happens
    @Test func newPromptReadsAsNeverChecked() async throws {
        try await withEphemeralDefaults { defaults in
            let store = PromptStore(defaults: defaults)
            
            #expect(store.lookUpState(for: "com.example.test").isNeverChecked)
        }
    }
    
    
    /// The very first check is when the cadence is locked in, and the prompt stays hidden
    @Test func firstCheckLocksInTheCadenceAndStaysHidden() async throws {
        try await withEphemeralDefaults { defaults in
            let store = PromptStore(defaults: defaults)
            let now = try Date.noon(year: 2026, month: 9, day: 20)
            let expectedNextEligible = try Date.noon(year: 2026, month: 10, day: 20)
            
            let decision = store.check(descriptor(), at: now, in: .testing)
            
            #expect(PromptDecision.hide == decision)
            #expect(PromptState.scheduled(interval: .monthly, nextEligible: expectedNextEligible) == store.lookUpState(for: "com.example.test").recordedState)
        }
    }
    
    
    /// After the wait is over, the prompt shows, and checking it again changes nothing
    @Test func promptIsDueAfterItsWaitAndStaysDue() async throws {
        try await withEphemeralDefaults { defaults in
            let store = PromptStore(defaults: defaults)
            _ = store.check(descriptor(), at: try Date.noon(year: 2026, month: 9, day: 20), in: .testing)
            
            let dueDate = try Date.noon(year: 2026, month: 10, day: 20)
            let later = try Date.noon(year: 2026, month: 12, day: 25)
            
            #expect(PromptDecision.show == store.check(descriptor(), at: dueDate, in: .testing))
            #expect(PromptDecision.show == store.check(descriptor(), at: later, in: .testing))
        }
    }
    
    
    /// Asking for later hides the prompt for one full interval, counted from that moment
    @Test func snoozingHidesThePromptForAFullInterval() async throws {
        try await withEphemeralDefaults { defaults in
            let store = PromptStore(defaults: defaults)
            _ = store.check(descriptor(), at: try Date.noon(year: 2026, month: 9, day: 20), in: .testing)
            
            let snoozedAt = try Date.noon(year: 2026, month: 10, day: 25)
            store.snooze(descriptor(), at: snoozedAt, in: .testing)
            
            #expect(PromptDecision.hide == store.check(descriptor(), at: try Date.noon(year: 2026, month: 11, day: 24), in: .testing))
            #expect(PromptDecision.show == store.check(descriptor(), at: try Date.noon(year: 2026, month: 11, day: 25), in: .testing))
        }
    }
    
    
    /// The README promises that changing a declared interval in a later version of an app can't change anyone's
    /// cadence once they've been checked, including when they snooze
    @Test func declaredIntervalIsIgnoredAfterTheFirstCheck() async throws {
        try await withEphemeralDefaults { defaults in
            let store = PromptStore(defaults: defaults)
            _ = store.check(descriptor(atMost: .weekly), at: try Date.noon(year: 2026, month: 9, day: 20), in: .testing)
            
            store.snooze(descriptor(atMost: .yearly), at: try Date.noon(year: 2026, month: 10, day: 1), in: .testing)
            
            let expectedNextEligible = try Date.noon(year: 2026, month: 10, day: 8)
            #expect(PromptState.scheduled(interval: .weekly, nextEligible: expectedNextEligible) == store.lookUpState(for: "com.example.test").recordedState)
        }
    }
    
    
    /// A retired prompt is stored as exactly `{"state":"done"}`, as the README promises, and is never due again
    @Test func retiredPromptIsStoredMinimallyAndNeverDue() async throws {
        try await withEphemeralDefaults { defaults in
            let store = PromptStore(defaults: defaults)
            
            store.retire("com.example.test")
            
            #expect("{\"state\":\"done\"}" == defaults.string(forKey: PromptStore.key(for: "com.example.test")))
            let noon21260101 = try Date.noon(year: 2126, month: 1, day: 1)
            #expect(PromptDecision.hide == store.check(descriptor(), at: noon21260101, in: .testing))
        }
    }
    
    
    /// A pending prompt stays hidden, even long after its schedule would have made it due, and asks for its result
    @Test func pendingPromptIsNeverDue() async throws {
        try await withEphemeralDefaults { defaults in
            let store = PromptStore(defaults: defaults)
            _ = store.check(descriptor(), at: try Date.noon(year: 2026, month: 9, day: 20), in: .testing)
            
            store.persist(.pending(interval: .monthly, since: try Date.noon(year: 2026, month: 10, day: 20)), for: "com.example.test")
            
            #expect(PromptDecision.checkPending == store.check(descriptor(), at: try Date.noon(year: 2126, month: 1, day: 1), in: .testing))
        }
    }
    
    
    /// An update reads what's stored when it runs, and stores only what the transition returns
    @Test func updateStoresOnlyWhatTheTransitionReturns() async throws {
        try await withEphemeralDefaults { defaults in
            let store = PromptStore(defaults: defaults)
            store.retire("com.example.test")
            
            let unchanged = store.update("com.example.test") { _ in nil }
            
            #expect(nil == unchanged)
            #expect(PromptState.done == store.lookUpState(for: "com.example.test").recordedState)
            
            let since = try Date.noon(year: 2026, month: 10, day: 1)
            let changed = store.update("com.example.test") { lookup in
                if PromptState.done == lookup.recordedState {
                    return .pending(interval: .weekly, since: since)
                }
                else {
                    return nil
                }
            }
            
            #expect(PromptState.pending(interval: .weekly, since: since) == changed)
            #expect(PromptState.pending(interval: .weekly, since: since) == store.lookUpState(for: "com.example.test").recordedState)
        }
    }
    
    
    /// Prompts keep separate states
    @Test func promptsDontAffectEachOther() async throws {
        try await withEphemeralDefaults { defaults in
            let store = PromptStore(defaults: defaults)
            
            store.retire("com.example.one")
            
            #expect(store.lookUpState(for: "com.example.two").isNeverChecked)
        }
    }
    
    
    /// Text which isn't a state means nobody knows what the person said, so the prompt never shows
    @Test func garbageInStorageMeansTheStateIsUnreadableAndThePromptStaysHidden() async throws {
        try await withEphemeralDefaults { defaults in
            let store = PromptStore(defaults: defaults)
            defaults.set("not json", forKey: PromptStore.key(for: "com.example.test"))
            
            #expect(store.lookUpState(for: "com.example.test").isUnreadable)
            let noon21260101 = try Date.noon(year: 2126, month: 1, day: 1)
            #expect(PromptDecision.hide == store.check(descriptor(), at: noon21260101, in: .testing))
        }
    }
    
    
    /// Storage holds any type, so a value which isn't text is just as unreadable
    @Test func nonStringInStorageIsUnreadable() async throws {
        try await withEphemeralDefaults { defaults in
            let store = PromptStore(defaults: defaults)
            defaults.set(42, forKey: PromptStore.key(for: "com.example.test"))
            
            #expect(store.lookUpState(for: "com.example.test").isUnreadable)
        }
    }
    
    
    /// An unreadable state can't be snoozed, since that would invent a schedule for someone whose answer is unknown
    @Test func unreadableStateIsNotOverwrittenBySnoozing() async throws {
        try await withEphemeralDefaults { defaults in
            let store = PromptStore(defaults: defaults)
            defaults.set("not json", forKey: PromptStore.key(for: "com.example.test"))
            
            store.snooze(descriptor(), at: try Date.noon(year: 2026, month: 11, day: 3), in: .testing)
            
            #expect(store.lookUpState(for: "com.example.test").isUnreadable)
        }
    }
    
    
    /// Declining is a person's clear answer, so it replaces an unreadable state
    @Test func retiringRepairsAnUnreadableState() async throws {
        try await withEphemeralDefaults { defaults in
            let store = PromptStore(defaults: defaults)
            defaults.set("not json", forKey: PromptStore.key(for: "com.example.test"))
            
            store.retire("com.example.test")
            
            #expect(PromptState.done == store.lookUpState(for: "com.example.test").recordedState)
        }
    }
    
    
    #if DEBUG
    /// Resetting returns a prompt to how it was before its first check, even after it was retired
    @Test func resettingReturnsARetiredPromptToNeverChecked() async throws {
        try await withEphemeralDefaults { defaults in
            let store = PromptStore(defaults: defaults)
            store.retire("com.example.test")
            
            store.reset("com.example.test")
            
            #expect(store.lookUpState(for: "com.example.test").isNeverChecked)
        }
    }
    
    
    /// After resetting, the next check is a true first check: hidden, and the cadence locked in again from the
    /// interval the descriptor declares now
    @Test func checkAfterResettingActsLikeTheFirstCheck() async throws {
        try await withEphemeralDefaults { defaults in
            let store = PromptStore(defaults: defaults)
            _ = store.check(descriptor(atMost: .weekly), at: try Date.noon(year: 2026, month: 9, day: 20), in: .testing)
            
            store.reset("com.example.test")
            let decision = store.check(descriptor(atMost: .monthly), at: try Date.noon(year: 2026, month: 10, day: 1), in: .testing)
            
            let expectedNextEligible = try Date.noon(year: 2026, month: 11, day: 1)
            #expect(PromptDecision.hide == decision)
            #expect(PromptState.scheduled(interval: .monthly, nextEligible: expectedNextEligible) == store.lookUpState(for: "com.example.test").recordedState)
        }
    }
    
    
    /// Resetting one prompt leaves the others alone
    @Test func resettingOnePromptLeavesOthersAlone() async throws {
        try await withEphemeralDefaults { defaults in
            let store = PromptStore(defaults: defaults)
            store.retire("com.example.one")
            store.retire("com.example.two")
            
            store.reset("com.example.one")
            
            #expect(PromptState.done == store.lookUpState(for: "com.example.two").recordedState)
        }
    }
    #endif
}
