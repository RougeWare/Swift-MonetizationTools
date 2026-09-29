//
//  PromptState Test.swift
//  MonetizationTools
//
//  Created by Ky directing Claude Sonnet 5 on 2026-09-20.
//

import Foundation
import Testing
@testable import MonetizationTools



/// Checks the stored form of a prompt's state, since people's devices will hold it for years
struct PromptStateTest {
    
    /// The README promises this exact form for a retired prompt, and that it costs nothing more
    @Test func retiredPromptIsStoredAsExactlyStateDone() throws {
        let data = try JSONEncoder().encode(PromptState.done)
        
        #expect("{\"state\":\"done\"}" == String(decoding: data, as: UTF8.self))
    }
    
    
    /// A pending prompt is stored as exactly its tag and nothing else
    @Test func pendingPromptIsStoredAsExactlyStatePending() throws {
        let data = try JSONEncoder().encode(PromptState.pending)
        
        #expect("{\"state\":\"pending\"}" == String(decoding: data, as: UTF8.self))
    }
    
    
    /// Every state reads back as itself
    @Test(arguments: [
        PromptState.done,
        PromptState.pending,
        PromptState.scheduled(interval: .quarterly, nextEligible: Date(timeIntervalSince1970: 1_797_768_000)),
    ])
    func stateRoundTrips(state: PromptState) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        
        let data = try encoder.encode(state)
        
        #expect(state == (try decoder.decode(PromptState.self, from: data)))
    }
    
    
    /// The documented example of a scheduled prompt reads as exactly what it says
    @Test func documentedScheduledFormReads() throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let stored = "{\"state\":\"scheduled\",\"interval\":\"monthly\",\"nextEligible\":\"2026-12-20T12:00:00Z\"}"
        
        let state = try decoder.decode(PromptState.self, from: Data(stored.utf8))
        
        #expect(PromptState.scheduled(interval: .monthly, nextEligible: try Date.noon(year: 2026, month: 12, day: 20)) == state)
    }
    
    
    /// Anything which isn't one of the three shapes this type writes must fail to read, so a damaged record can't be
    /// mistaken for a valid one. That includes the untagged forms, which no build of this package ever stored.
    @Test(arguments: [
        "{}",
        "{\"state\":\"retired\"}",
        "{\"state\":true}",
        "{\"state\":\"scheduled\"}",
        "{\"state\":\"scheduled\",\"interval\":\"monthly\"}",
        "{\"state\":\"scheduled\",\"interval\":\"fortnightly\",\"nextEligible\":\"2026-12-20T12:00:00Z\"}",
        "{\"done\":true}",
        "{\"pending\":true}",
        "{\"interval\":\"monthly\",\"nextEligible\":\"2026-12-20T12:00:00Z\"}",
        "[]",
        "true",
        "",
    ])
    func damagedRecordFailsToRead(stored: String) {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        
        #expect(throws: (any Error).self) {
            try decoder.decode(PromptState.self, from: Data(stored.utf8))
        }
    }
}



/// Checks the rules which decide when a prompt shows. They read no clock and no storage, so every case here can be
/// checked at any moment in history.
struct PromptSchedulingTest {
    
    /// Nobody has ever been shown a prompt on their first check
    @Test func firstCheckIsNeverDue() throws {
        let now = try Date.noon(year: 2026, month: 9, day: 20)
        
        let result = PromptStateLookup.none.check(declaring: .monthly, at: now, in: .testing)
        
        #expect(false == result.isDue)
    }
    
    
    /// The first check locks in the cadence, and starts the wait before the first appearance
    @Test func firstCheckRemembersTheDeclaredIntervalAndWaits() throws {
        let now = try Date.noon(year: 2026, month: 9, day: 20)
        let expectedNextEligible = try Date.noon(year: 2026, month: 10, day: 20)
        
        let result = PromptStateLookup.none.check(declaring: .monthly, at: now, in: .testing)
        
        #expect(PromptState.scheduled(interval: .monthly, nextEligible: expectedNextEligible) == result.stateToRemember)
    }
    
    
    /// Before its moment, a prompt stays hidden and changes nothing
    @Test func promptIsNotDueBeforeItsNextEligibleMoment() throws {
        let nextEligible = try Date.noon(year: 2026, month: 10, day: 20)
        let now = try Date.noon(year: 2026, month: 10, day: 19)
        let reading = PromptStateLookup.some(.success(.scheduled(interval: .monthly, nextEligible: nextEligible)))
        
        let result = reading.check(declaring: .monthly, at: now, in: .testing)
        
        #expect(false == result.isDue)
        #expect(nil == result.stateToRemember)
    }
    
    
    /// The moment itself counts, so nobody waits longer than the interval
    @Test func promptIsDueAtExactlyItsNextEligibleMoment() throws {
        let nextEligible = try Date.noon(year: 2026, month: 10, day: 20)
        let reading = PromptStateLookup.some(.success(.scheduled(interval: .monthly, nextEligible: nextEligible)))
        
        let result = reading.check(declaring: .monthly, at: nextEligible, in: .testing)
        
        #expect(result.isDue)
    }
    
    
    /// Being due changes nothing on its own. Only a person asking for later moves a prompt's schedule, so ignoring a
    /// prompt leaves it due.
    @Test func duePromptChangesNothing() throws {
        let nextEligible = try Date.noon(year: 2026, month: 10, day: 20)
        let now = try Date.noon(year: 2027, month: 3, day: 1)
        let reading = PromptStateLookup.some(.success(.scheduled(interval: .monthly, nextEligible: nextEligible)))
        
        let result = reading.check(declaring: .monthly, at: now, in: .testing)
        
        #expect(result.isDue)
        #expect(nil == result.stateToRemember)
    }
    
    
    /// A prompt waiting on something else, like a parent's approval, stays hidden however long it waits
    @Test func pendingPromptIsNeverDue() throws {
        let now = try Date.noon(year: 2126, month: 1, day: 1)
        
        let result = PromptStateLookup.some(.success(.pending)).check(declaring: .weekly, at: now, in: .testing)
        
        #expect(false == result.isDue)
        #expect(nil == result.stateToRemember)
    }
    
    
    /// A declined or fulfilled prompt never appears again, however long ago that was
    @Test func retiredPromptIsNeverDue() throws {
        let now = try Date.noon(year: 2126, month: 1, day: 1)
        
        let result = PromptStateLookup.some(.success(.done)).check(declaring: .weekly, at: now, in: .testing)
        
        #expect(false == result.isDue)
        #expect(nil == result.stateToRemember)
    }
    
    
    /// When nobody knows what a person already said, the prompt stays quiet
    @Test func unreadablePromptIsNeverDue() throws {
        let now = try Date.noon(year: 2126, month: 1, day: 1)
        let reading = PromptStateLookup.some(.failure(StubAction.StubError()))
        
        let result = reading.check(declaring: .weekly, at: now, in: .testing)
        
        #expect(false == result.isDue)
        #expect(nil == result.stateToRemember)
    }
    
    
    /// Asking for later starts a full new wait, counted from the moment of asking
    @Test func snoozingStartsANewWaitFromNow() throws {
        let nextEligible = try Date.noon(year: 2026, month: 10, day: 20)
        let now = try Date.noon(year: 2026, month: 11, day: 3)
        let expectedNextEligible = try Date.noon(year: 2026, month: 12, day: 3)
        let reading = PromptStateLookup.some(.success(.scheduled(interval: .monthly, nextEligible: nextEligible)))
        
        let snoozed = reading.snoozed(declaring: .monthly, at: now, in: .testing)
        
        #expect(PromptState.scheduled(interval: .monthly, nextEligible: expectedNextEligible) == snoozed)
    }
    
    
    /// The README promises that nobody's cadence can be ratcheted up by an update, so the interval locked in at the
    /// first check governs, whatever the descriptor declares now
    @Test func snoozingUsesTheLockedInInterval() throws {
        let nextEligible = try Date.noon(year: 2026, month: 10, day: 20)
        let now = try Date.noon(year: 2026, month: 11, day: 3)
        let expectedNextEligible = try Date.noon(year: 2026, month: 11, day: 10)
        let reading = PromptStateLookup.some(.success(.scheduled(interval: .weekly, nextEligible: nextEligible)))
        
        let snoozed = reading.snoozed(declaring: .yearly, at: now, in: .testing)
        
        #expect(PromptState.scheduled(interval: .weekly, nextEligible: expectedNextEligible) == snoozed)
    }
    
    
    /// If storage was cleared while a prompt was showing, asking for later is treated as the first check
    @Test func snoozingWithNothingStoredStartsTheWaitFromTheDeclaredInterval() throws {
        let now = try Date.noon(year: 2026, month: 11, day: 3)
        let expectedNextEligible = try Date.noon(year: 2026, month: 12, day: 3)
        
        let snoozed = PromptStateLookup.none.snoozed(declaring: .monthly, at: now, in: .testing)
        
        #expect(PromptState.scheduled(interval: .monthly, nextEligible: expectedNextEligible) == snoozed)
    }
    
    
    /// Asking for later can't schedule a prompt which is waiting on something else
    @Test func snoozingAPendingPromptChangesNothing() throws {
        let now = try Date.noon(year: 2026, month: 11, day: 3)
        
        let snoozed = PromptStateLookup.some(.success(.pending)).snoozed(declaring: .monthly, at: now, in: .testing)
        
        #expect(nil == snoozed)
    }
    
    
    /// A retired prompt can't be brought back by asking for later
    @Test func snoozingARetiredPromptChangesNothing() throws {
        let now = try Date.noon(year: 2026, month: 11, day: 3)
        
        let snoozed = PromptStateLookup.some(.success(.done)).snoozed(declaring: .monthly, at: now, in: .testing)
        
        #expect(nil == snoozed)
    }
    
    
    /// A state which can't be read isn't overwritten by asking for later
    @Test func snoozingAnUnreadablePromptChangesNothing() throws {
        let now = try Date.noon(year: 2026, month: 11, day: 3)
        let reading = PromptStateLookup.some(.failure(StubAction.StubError()))
        
        let snoozed = reading.snoozed(declaring: .monthly, at: now, in: .testing)
        
        #expect(nil == snoozed)
    }
}
