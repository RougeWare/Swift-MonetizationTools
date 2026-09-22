//
//  PromptHistory Test.swift
//  MonetizationTools
//
//  Created by Ky directing Claude Sonnet 5 on 2026-09-20.
//

import Foundation
import Testing
@testable import MonetizationTools



/// Checks the stored form of a prompt's history, since people's devices will hold it for years
struct PromptHistoryTest {
    
    /// The README promises this exact form for a retired prompt, and that it costs nothing more
    @Test func retiredPromptIsStoredAsExactlyDoneTrue() throws {
        let data = try JSONEncoder().encode(PromptHistory.done)
        
        #expect("{\"done\":true}" == String(decoding: data, as: UTF8.self))
    }
    
    
    /// A retired prompt reads back as retired
    @Test func retiredPromptRoundTrips() throws {
        let data = try JSONEncoder().encode(PromptHistory.done)
        
        #expect(PromptHistory.done == (try JSONDecoder().decode(PromptHistory.self, from: data)))
    }
    
    
    /// A tracked prompt reads back with its locked-in interval and its next eligible moment
    @Test func trackedPromptRoundTrips() throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        
        let history = PromptHistory.tracking(interval: .quarterly, nextEligible: try Date.noon(year: 2026, month: 12, day: 20))
        let data = try encoder.encode(history)
        
        #expect(history == (try decoder.decode(PromptHistory.self, from: data)))
    }
    
    
    /// Anything which isn't one of the two shapes this type writes must fail to read, so a damaged record can't be
    /// mistaken for a valid one
    @Test(arguments: [
        "{}",
        "{\"done\":false}",
        "{\"done\":\"yes\"}",
        "{\"interval\":\"monthly\"}",
        "{\"nextEligible\":\"2026-12-20T12:00:00Z\"}",
        "{\"interval\":\"fortnightly\",\"nextEligible\":\"2026-12-20T12:00:00Z\"}",
        "[]",
        "true",
        "",
    ])
    func damagedRecordFailsToRead(stored: String) {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        
        #expect(throws: (any Error).self) {
            try decoder.decode(PromptHistory.self, from: Data(stored.utf8))
        }
    }
}



/// Checks the rules which decide when a prompt shows. They read no clock and no storage, so every case here can be
/// checked at any moment in history.
struct PromptSchedulingTest {
    
    /// Nobody has ever been shown a prompt on their first check
    @Test func firstCheckIsNeverDue() throws {
        let now = try Date.noon(year: 2026, month: 9, day: 20)
        
        let result = PromptHistoryReading.neverChecked.check(declaring: .monthly, at: now, in: .testing)
        
        #expect(false == result.isDue)
    }
    
    
    /// The first check locks in the cadence, and starts the wait before the first appearance
    @Test func firstCheckRemembersTheDeclaredIntervalAndWaits() throws {
        let now = try Date.noon(year: 2026, month: 9, day: 20)
        let expectedNextEligible = try Date.noon(year: 2026, month: 10, day: 20)
        
        let result = PromptHistoryReading.neverChecked.check(declaring: .monthly, at: now, in: .testing)
        
        #expect(PromptHistory.tracking(interval: .monthly, nextEligible: expectedNextEligible) == result.historyToRemember)
    }
    
    
    /// Before its moment, a prompt stays hidden and changes nothing
    @Test func promptIsNotDueBeforeItsNextEligibleMoment() throws {
        let nextEligible = try Date.noon(year: 2026, month: 10, day: 20)
        let now = try Date.noon(year: 2026, month: 10, day: 19)
        let reading = PromptHistoryReading.recorded(history: .tracking(interval: .monthly, nextEligible: nextEligible))
        
        let result = reading.check(declaring: .monthly, at: now, in: .testing)
        
        #expect(false == result.isDue)
        #expect(nil == result.historyToRemember)
    }
    
    
    /// The moment itself counts, so nobody waits longer than the interval
    @Test func promptIsDueAtExactlyItsNextEligibleMoment() throws {
        let nextEligible = try Date.noon(year: 2026, month: 10, day: 20)
        let reading = PromptHistoryReading.recorded(history: .tracking(interval: .monthly, nextEligible: nextEligible))
        
        let result = reading.check(declaring: .monthly, at: nextEligible, in: .testing)
        
        #expect(result.isDue)
    }
    
    
    /// Being due changes nothing on its own. Only a person asking for later moves a prompt's schedule, so ignoring a
    /// prompt leaves it due.
    @Test func duePromptChangesNothing() throws {
        let nextEligible = try Date.noon(year: 2026, month: 10, day: 20)
        let now = try Date.noon(year: 2027, month: 3, day: 1)
        let reading = PromptHistoryReading.recorded(history: .tracking(interval: .monthly, nextEligible: nextEligible))
        
        let result = reading.check(declaring: .monthly, at: now, in: .testing)
        
        #expect(result.isDue)
        #expect(nil == result.historyToRemember)
    }
    
    
    /// A declined or fulfilled prompt never appears again, however long ago that was
    @Test func retiredPromptIsNeverDue() throws {
        let now = try Date.noon(year: 2126, month: 1, day: 1)
        
        let result = PromptHistoryReading.recorded(history: .done).check(declaring: .weekly, at: now, in: .testing)
        
        #expect(false == result.isDue)
        #expect(nil == result.historyToRemember)
    }
    
    
    /// When nobody knows what a person already said, the prompt stays quiet
    @Test func unreadablePromptIsNeverDue() throws {
        let now = try Date.noon(year: 2126, month: 1, day: 1)
        let reading = PromptHistoryReading.unreadable(cause: StubAction.StubError())
        
        let result = reading.check(declaring: .weekly, at: now, in: .testing)
        
        #expect(false == result.isDue)
        #expect(nil == result.historyToRemember)
    }
    
    
    /// Asking for later starts a full new wait, counted from the moment of asking
    @Test func snoozingStartsANewWaitFromNow() throws {
        let nextEligible = try Date.noon(year: 2026, month: 10, day: 20)
        let now = try Date.noon(year: 2026, month: 11, day: 3)
        let expectedNextEligible = try Date.noon(year: 2026, month: 12, day: 3)
        let reading = PromptHistoryReading.recorded(history: .tracking(interval: .monthly, nextEligible: nextEligible))
        
        let snoozed = reading.snoozed(declaring: .monthly, at: now, in: .testing)
        
        #expect(PromptHistory.tracking(interval: .monthly, nextEligible: expectedNextEligible) == snoozed)
    }
    
    
    /// The README promises that nobody's cadence can be ratcheted up by an update, so the interval locked in at the
    /// first check governs, whatever the descriptor declares now
    @Test func snoozingUsesTheLockedInInterval() throws {
        let nextEligible = try Date.noon(year: 2026, month: 10, day: 20)
        let now = try Date.noon(year: 2026, month: 11, day: 3)
        let expectedNextEligible = try Date.noon(year: 2026, month: 11, day: 10)
        let reading = PromptHistoryReading.recorded(history: .tracking(interval: .weekly, nextEligible: nextEligible))
        
        let snoozed = reading.snoozed(declaring: .yearly, at: now, in: .testing)
        
        #expect(PromptHistory.tracking(interval: .weekly, nextEligible: expectedNextEligible) == snoozed)
    }
    
    
    /// If storage was cleared while a prompt was showing, asking for later is treated as the first check
    @Test func snoozingWithNothingStoredStartsTheWaitFromTheDeclaredInterval() throws {
        let now = try Date.noon(year: 2026, month: 11, day: 3)
        let expectedNextEligible = try Date.noon(year: 2026, month: 12, day: 3)
        
        let snoozed = PromptHistoryReading.neverChecked.snoozed(declaring: .monthly, at: now, in: .testing)
        
        #expect(PromptHistory.tracking(interval: .monthly, nextEligible: expectedNextEligible) == snoozed)
    }
    
    
    /// A retired prompt can't be brought back by asking for later
    @Test func snoozingARetiredPromptChangesNothing() throws {
        let now = try Date.noon(year: 2026, month: 11, day: 3)
        
        let snoozed = PromptHistoryReading.recorded(history: .done).snoozed(declaring: .monthly, at: now, in: .testing)
        
        #expect(nil == snoozed)
    }
    
    
    /// A history which can't be read isn't overwritten by asking for later
    @Test func snoozingAnUnreadablePromptChangesNothing() throws {
        let now = try Date.noon(year: 2026, month: 11, day: 3)
        let reading = PromptHistoryReading.unreadable(cause: StubAction.StubError())
        
        let snoozed = reading.snoozed(declaring: .monthly, at: now, in: .testing)
        
        #expect(nil == snoozed)
    }
}
