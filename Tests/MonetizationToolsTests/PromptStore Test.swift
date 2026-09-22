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
    private func descriptor(_ identifier: MonetizationPromptIdentifier = "com.example.test",
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
            
            #expect(store.reading(for: "com.example.test").isNeverChecked)
        }
    }
    
    
    /// The very first check is when the cadence is locked in, and the prompt stays hidden
    @Test func firstCheckLocksInTheCadenceAndStaysHidden() async throws {
        try await withEphemeralDefaults { defaults in
            let store = PromptStore(defaults: defaults)
            let now = try Date.noon(year: 2026, month: 9, day: 20)
            let expectedNextEligible = try Date.noon(year: 2026, month: 10, day: 20)
            
            let isDue = store.check(descriptor(), at: now, in: .testing)
            
            #expect(false == isDue)
            #expect(PromptHistory.tracking(interval: .monthly, nextEligible: expectedNextEligible) == store.reading(for: "com.example.test").recordedHistory)
        }
    }
    
    
    /// After the wait is over, the prompt shows, and checking it again changes nothing
    @Test func promptIsDueAfterItsWaitAndStaysDue() async throws {
        try await withEphemeralDefaults { defaults in
            let store = PromptStore(defaults: defaults)
            _ = store.check(descriptor(), at: try Date.noon(year: 2026, month: 9, day: 20), in: .testing)
            
            let dueDate = try Date.noon(year: 2026, month: 10, day: 20)
            let later = try Date.noon(year: 2026, month: 12, day: 25)
            
            #expect(store.check(descriptor(), at: dueDate, in: .testing))
            #expect(store.check(descriptor(), at: later, in: .testing))
        }
    }
    
    
    /// Asking for later hides the prompt for one full interval, counted from that moment
    @Test func snoozingHidesThePromptForAFullInterval() async throws {
        try await withEphemeralDefaults { defaults in
            let store = PromptStore(defaults: defaults)
            _ = store.check(descriptor(), at: try Date.noon(year: 2026, month: 9, day: 20), in: .testing)
            
            let snoozedAt = try Date.noon(year: 2026, month: 10, day: 25)
            store.snooze(descriptor(), at: snoozedAt, in: .testing)
            
            #expect(false == store.check(descriptor(), at: try Date.noon(year: 2026, month: 11, day: 24), in: .testing))
            #expect(store.check(descriptor(), at: try Date.noon(year: 2026, month: 11, day: 25), in: .testing))
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
            #expect(PromptHistory.tracking(interval: .weekly, nextEligible: expectedNextEligible) == store.reading(for: "com.example.test").recordedHistory)
        }
    }
    
    
    /// A retired prompt is stored as exactly `{"done":true}`, as the README promises, and is never due again
    @Test func retiredPromptIsStoredMinimallyAndNeverDue() async throws {
        try await withEphemeralDefaults { defaults in
            let store = PromptStore(defaults: defaults)
            
            store.retire("com.example.test")
            
            #expect("{\"done\":true}" == defaults.string(forKey: PromptStore.key(for: "com.example.test")))
            let noon21260101 = try Date.noon(year: 2126, month: 1, day: 1)
            #expect(false == store.check(descriptor(), at: noon21260101, in: .testing))
        }
    }
    
    
    /// Prompts keep separate histories
    @Test func promptsDontAffectEachOther() async throws {
        try await withEphemeralDefaults { defaults in
            let store = PromptStore(defaults: defaults)
            
            store.retire("com.example.one")
            
            #expect(store.reading(for: "com.example.two").isNeverChecked)
        }
    }
    
    
    /// Text which isn't a history means nobody knows what the person said, so the prompt never shows
    @Test func garbageInStorageMeansTheHistoryIsUnreadableAndThePromptStaysHidden() async throws {
        try await withEphemeralDefaults { defaults in
            let store = PromptStore(defaults: defaults)
            defaults.set("not json", forKey: PromptStore.key(for: "com.example.test"))
            
            #expect(store.reading(for: "com.example.test").isUnreadable)
            let noon21260101 = try Date.noon(year: 2126, month: 1, day: 1)
            #expect(false == store.check(descriptor(), at: noon21260101, in: .testing))
        }
    }
    
    
    /// Storage holds any type, so a value which isn't text is just as unreadable
    @Test func nonStringInStorageIsUnreadable() async throws {
        try await withEphemeralDefaults { defaults in
            let store = PromptStore(defaults: defaults)
            defaults.set(42, forKey: PromptStore.key(for: "com.example.test"))
            
            #expect(store.reading(for: "com.example.test").isUnreadable)
        }
    }
    
    
    /// An unreadable history can't be snoozed, since that would invent a schedule for someone whose answer is unknown
    @Test func unreadableHistoryIsNotOverwrittenBySnoozing() async throws {
        try await withEphemeralDefaults { defaults in
            let store = PromptStore(defaults: defaults)
            defaults.set("not json", forKey: PromptStore.key(for: "com.example.test"))
            
            store.snooze(descriptor(), at: try Date.noon(year: 2026, month: 11, day: 3), in: .testing)
            
            #expect(store.reading(for: "com.example.test").isUnreadable)
        }
    }
    
    
    /// Declining is a person's clear answer, so it replaces an unreadable history
    @Test func retiringRepairsAnUnreadableHistory() async throws {
        try await withEphemeralDefaults { defaults in
            let store = PromptStore(defaults: defaults)
            defaults.set("not json", forKey: PromptStore.key(for: "com.example.test"))
            
            store.retire("com.example.test")
            
            #expect(PromptHistory.done == store.reading(for: "com.example.test").recordedHistory)
        }
    }
    
    
    #if DEBUG
    /// Forgetting returns a prompt to how it was before its first check, even after it was retired
    @Test func forgettingReturnsARetiredPromptToNeverChecked() async throws {
        try await withEphemeralDefaults { defaults in
            let store = PromptStore(defaults: defaults)
            store.retire("com.example.test")
            
            store.forget("com.example.test")
            
            #expect(store.reading(for: "com.example.test").isNeverChecked)
        }
    }
    
    
    /// After forgetting, the next check is a true first check: hidden, and the cadence locked in again from the
    /// interval the descriptor declares now
    @Test func checkAfterForgettingActsLikeTheFirstCheck() async throws {
        try await withEphemeralDefaults { defaults in
            let store = PromptStore(defaults: defaults)
            _ = store.check(descriptor(atMost: .weekly), at: try Date.noon(year: 2026, month: 9, day: 20), in: .testing)
            
            store.forget("com.example.test")
            let isDue = store.check(descriptor(atMost: .monthly), at: try Date.noon(year: 2026, month: 10, day: 1), in: .testing)
            
            let expectedNextEligible = try Date.noon(year: 2026, month: 11, day: 1)
            #expect(false == isDue)
            #expect(PromptHistory.tracking(interval: .monthly, nextEligible: expectedNextEligible) == store.reading(for: "com.example.test").recordedHistory)
        }
    }
    
    
    /// Forgetting one prompt leaves the others alone
    @Test func forgettingOnePromptLeavesOthersAlone() async throws {
        try await withEphemeralDefaults { defaults in
            let store = PromptStore(defaults: defaults)
            store.retire("com.example.one")
            store.retire("com.example.two")
            
            store.forget("com.example.one")
            
            #expect(PromptHistory.done == store.reading(for: "com.example.two").recordedHistory)
        }
    }
    #endif
}
