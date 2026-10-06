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
    
    
    /// The documented examples of a pending and a resolving prompt read as exactly what they say
    @Test(arguments: ["pending", "resolving"])
    func documentedPendingAndResolvingFormsRead(kind: String) throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let stored = "{\"state\":\"\(kind)\",\"interval\":\"monthly\",\"since\":\"2026-09-30T12:34:00Z\"}"
        let since = try #require(ISO8601DateFormatter().date(from: "2026-09-30T12:34:00Z"))
        
        let state = try decoder.decode(PromptState.self, from: Data(stored.utf8))
        
        if "pending" == kind {
            #expect(PromptState.pending(interval: .monthly, since: since) == state)
        }
        else {
            #expect(PromptState.resolving(interval: .monthly, since: since) == state)
        }
    }
    
    
    /// Every state reads back as itself
    @Test(arguments: [
        PromptState.done,
        PromptState.pending(interval: .monthly, since: Date(timeIntervalSince1970: 1_790_000_000)),
        PromptState.resolving(interval: .weekly, since: Date(timeIntervalSince1970: 1_790_000_000)),
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
    
    
    /// Anything which isn't one of the four shapes this type writes must fail to read, so a damaged record can't be
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
        "{\"state\":\"pending\"}",
        "{\"state\":\"pending\",\"interval\":\"monthly\"}",
        "{\"state\":\"pending\",\"since\":\"2026-09-30T12:34:00Z\"}",
        "{\"state\":\"resolving\",\"interval\":\"monthly\"}",
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
        
        let result = PersistedPromptState.none.check(declaring: .monthly, at: now, in: .testing)
        
        #expect(PromptLoadAction.hide == result.decision)
    }
    
    
    /// The first check locks in the cadence, and starts the wait before the first appearance
    @Test func firstCheckRemembersTheDeclaredIntervalAndWaits() throws {
        let now = try Date.noon(year: 2026, month: 9, day: 20)
        let expectedNextEligible = try Date.noon(year: 2026, month: 10, day: 20)
        
        let result = PersistedPromptState.none.check(declaring: .monthly, at: now, in: .testing)
        
        #expect(PromptState.scheduled(interval: .monthly, nextEligible: expectedNextEligible) == result.stateToRemember)
    }
    
    
    /// Before its moment, a prompt stays hidden and changes nothing
    @Test func promptIsNotDueBeforeItsNextEligibleMoment() throws {
        let nextEligible = try Date.noon(year: 2026, month: 10, day: 20)
        let now = try Date.noon(year: 2026, month: 10, day: 19)
        let reading = PersistedPromptState.some(.success(.scheduled(interval: .monthly, nextEligible: nextEligible)))
        
        let result = reading.check(declaring: .monthly, at: now, in: .testing)
        
        #expect(PromptLoadAction.hide == result.decision)
        #expect(nil == result.stateToRemember)
    }
    
    
    /// The moment itself counts, so nobody waits longer than the interval
    @Test func promptIsDueAtExactlyItsNextEligibleMoment() throws {
        let nextEligible = try Date.noon(year: 2026, month: 10, day: 20)
        let reading = PersistedPromptState.some(.success(.scheduled(interval: .monthly, nextEligible: nextEligible)))
        
        let result = reading.check(declaring: .monthly, at: nextEligible, in: .testing)
        
        #expect(PromptLoadAction.show == result.decision)
    }
    
    
    /// Being due changes nothing on its own. Only a person asking for later moves a prompt's schedule, so ignoring a
    /// prompt leaves it due.
    @Test func duePromptChangesNothing() throws {
        let nextEligible = try Date.noon(year: 2026, month: 10, day: 20)
        let now = try Date.noon(year: 2027, month: 3, day: 1)
        let reading = PersistedPromptState.some(.success(.scheduled(interval: .monthly, nextEligible: nextEligible)))
        
        let result = reading.check(declaring: .monthly, at: now, in: .testing)
        
        #expect(PromptLoadAction.show == result.decision)
        #expect(nil == result.stateToRemember)
    }
    
    
    /// A prompt waiting on something else, like a parent's approval, stays hidden however long it waits
    @Test func pendingPromptIsNeverDue() throws {
        let now = try Date.noon(year: 2126, month: 1, day: 1)
        
        let since = try Date.noon(year: 2026, month: 1, day: 1)
        let result = PersistedPromptState.some(.success(.pending(interval: .weekly, since: since))).check(declaring: .weekly, at: now, in: .testing)
        
        #expect(PromptLoadAction.checkPending == result.decision)
        #expect(nil == result.stateToRemember)
    }
    
    
    /// A declined or fulfilled prompt never appears again, however long ago that was
    @Test func retiredPromptIsNeverDue() throws {
        let now = try Date.noon(year: 2126, month: 1, day: 1)
        
        let result = PersistedPromptState.some(.success(.done)).check(declaring: .weekly, at: now, in: .testing)
        
        #expect(PromptLoadAction.hide == result.decision)
        #expect(nil == result.stateToRemember)
    }
    
    
    /// When nobody knows what a person already said, the prompt stays quiet
    @Test func unreadablePromptIsNeverDue() throws {
        let now = try Date.noon(year: 2126, month: 1, day: 1)
        let reading = PersistedPromptState.some(.failure(StubAction.StubError()))
        
        let result = reading.check(declaring: .weekly, at: now, in: .testing)
        
        #expect(PromptLoadAction.hide == result.decision)
        #expect(nil == result.stateToRemember)
    }
    
    
    /// Asking for later starts a full new wait, counted from the moment of asking
    @Test func snoozingStartsANewWaitFromNow() throws {
        let nextEligible = try Date.noon(year: 2026, month: 10, day: 20)
        let now = try Date.noon(year: 2026, month: 11, day: 3)
        let expectedNextEligible = try Date.noon(year: 2026, month: 12, day: 3)
        let reading = PersistedPromptState.some(.success(.scheduled(interval: .monthly, nextEligible: nextEligible)))
        
        let snoozed = reading.snoozed(declaring: .monthly, at: now, in: .testing)
        
        #expect(PromptState.scheduled(interval: .monthly, nextEligible: expectedNextEligible) == snoozed)
    }
    
    
    /// The README promises that nobody's cadence can be ratcheted up by an update, so the interval locked in at the
    /// first check governs, whatever the descriptor declares now
    @Test func snoozingUsesTheLockedInInterval() throws {
        let nextEligible = try Date.noon(year: 2026, month: 10, day: 20)
        let now = try Date.noon(year: 2026, month: 11, day: 3)
        let expectedNextEligible = try Date.noon(year: 2026, month: 11, day: 10)
        let reading = PersistedPromptState.some(.success(.scheduled(interval: .weekly, nextEligible: nextEligible)))
        
        let snoozed = reading.snoozed(declaring: .yearly, at: now, in: .testing)
        
        #expect(PromptState.scheduled(interval: .weekly, nextEligible: expectedNextEligible) == snoozed)
    }
    
    
    /// If storage was cleared while a prompt was showing, asking for later is treated as the first check
    @Test func snoozingWithNothingStoredStartsTheWaitFromTheDeclaredInterval() throws {
        let now = try Date.noon(year: 2026, month: 11, day: 3)
        let expectedNextEligible = try Date.noon(year: 2026, month: 12, day: 3)
        
        let snoozed = PersistedPromptState.none.snoozed(declaring: .monthly, at: now, in: .testing)
        
        #expect(PromptState.scheduled(interval: .monthly, nextEligible: expectedNextEligible) == snoozed)
    }
    
    
    /// Asking for later can't schedule a prompt which is waiting on something else
    @Test func snoozingAPendingPromptChangesNothing() throws {
        let now = try Date.noon(year: 2026, month: 11, day: 3)
        
        let since = try Date.noon(year: 2026, month: 11, day: 1)
        let snoozed = PersistedPromptState.some(.success(.pending(interval: .monthly, since: since))).snoozed(declaring: .monthly, at: now, in: .testing)
        
        #expect(nil == snoozed)
    }
    
    
    /// A retired prompt can't be brought back by asking for later
    @Test func snoozingARetiredPromptChangesNothing() throws {
        let now = try Date.noon(year: 2026, month: 11, day: 3)
        
        let snoozed = PersistedPromptState.some(.success(.done)).snoozed(declaring: .monthly, at: now, in: .testing)
        
        #expect(nil == snoozed)
    }
    
    
    /// A state which can't be read isn't overwritten by asking for later
    @Test func snoozingAnUnreadablePromptChangesNothing() throws {
        let now = try Date.noon(year: 2026, month: 11, day: 3)
        let reading = PersistedPromptState.some(.failure(StubAction.StubError()))
        
        let snoozed = reading.snoozed(declaring: .monthly, at: now, in: .testing)
        
        #expect(nil == snoozed)
    }
    
    
    /// A success being recorded never shows, and asks for its recording to be finished
    @Test func resolvingPromptFinishesResolving() throws {
        let now = try Date.noon(year: 2126, month: 1, day: 1)
        let since = try Date.noon(year: 2026, month: 1, day: 1)
        
        let result = PersistedPromptState.some(.success(.resolving(interval: .weekly, since: since))).check(declaring: .weekly, at: now, in: .testing)
        
        #expect(PromptLoadAction.finishResolving == result.decision)
        #expect(nil == result.stateToRemember)
    }
}



/// Checks what's stored as an attempt starts, ends, succeeds, or is given up on
struct PromptAttemptTest {
    
    /// A stored lookup for each kind of state, so each transition can be checked against all of them
    private static func lookups(since: Date) -> [(name: String, lookup: PersistedPromptState)] {
        [
            (name: "nothing stored", lookup: nil),
            (name: "scheduled", lookup: .some(.success(.scheduled(interval: .monthly, nextEligible: since)))),
            (name: "pending", lookup: .some(.success(.pending(interval: .monthly, since: since)))),
            (name: "resolving", lookup: .some(.success(.resolving(interval: .monthly, since: since)))),
            (name: "done", lookup: .some(.success(.done))),
            (name: "unreadable", lookup: .some(.failure(StubAction.StubError()))),
        ]
    }
    
    
    /// An attempt starts pending from a scheduled prompt, keeping its locked-in interval, and from nothing stored, using
    /// the declared interval. Nothing else changes.
    @Test func startingAnAttempt() throws {
        let since = try Date.noon(year: 2026, month: 9, day: 1)
        let now = try Date.noon(year: 2026, month: 10, day: 1)
        
        for (name, lookup) in Self.lookups(since: since) {
            let started = lookup.startingAttempt(declaring: .weekly, at: now)
            
            switch name {
            case "nothing stored":
                #expect(PromptState.scheduled(interval: .weekly, nextEligible: now) == started, "\(name)")
                
            case "scheduled":
                #expect(PromptState.scheduled(interval: .monthly, nextEligible: now) == started, "\(name)")
                
            default:
                #expect(nil == started, "\(name)")
            }
        }
    }
    
    
    /// Ending an attempt with nothing recorded makes a pending prompt due right away, and changes nothing else
    @Test func cancellingAnAttempt() throws {
        let since = try Date.noon(year: 2026, month: 9, day: 1)
        let now = try Date.noon(year: 2026, month: 10, day: 1)
        
        for (name, lookup) in Self.lookups(since: since) {
            let cancelled = lookup.cancellingAttempt(at: now)
            
            if "pending" == name {
                #expect(PromptState.scheduled(interval: .monthly, nextEligible: now) == cancelled, "\(name)")
            }
            else {
                #expect(nil == cancelled, "\(name)")
            }
        }
    }
    
    
    /// A pending prompt becomes resolving with the same fields, and nothing else changes
    @Test func recordingASuccess() throws {
        let since = try Date.noon(year: 2026, month: 9, day: 1)
        
        for (name, lookup) in Self.lookups(since: since) {
            let recorded = lookup.recordingSuccess()
            
            if "pending" == name {
                #expect(PromptState.resolving(interval: .monthly, since: since) == recorded, "\(name)")
            }
            else {
                #expect(nil == recorded, "\(name)")
            }
        }
    }
    
    
    /// Giving up schedules a pending prompt one locked-in interval after now, and changes nothing else
    @Test func givingUp() throws {
        let since = try Date.noon(year: 2026, month: 9, day: 1)
        let now = try Date.noon(year: 2026, month: 10, day: 1)
        let expectedNextEligible = try Date.noon(year: 2026, month: 11, day: 1)
        
        for (name, lookup) in Self.lookups(since: since) {
            let givenUp = lookup.givingUp(at: now, in: .testing)
            
            if "pending" == name {
                #expect(PromptState.scheduled(interval: .monthly, nextEligible: expectedNextEligible) == givenUp, "\(name)")
            }
            else {
                #expect(nil == givenUp, "\(name)")
            }
        }
    }
}



/// Checks when the package stops waiting for an attempt's result
struct GiveUpDateTest {
    
    /// A quarter of a 30-day month is 7.5 days
    @Test func quarterOfAMonth() throws {
        let reference = try Date.noon(year: 2026, month: 9, day: 1)
        
        #expect(.days(7.5) == PromptInterval.monthly.duration(since: reference, in: .testing) / 4)
    }
    
    
    /// A duration inside the limits is used as given
    @Test func durationInsideTheLimitsIsUsed() throws {
        let since = try Date.noon(year: 2026, month: 9, day: 1)
        let twoDays: Duration = .days(2)
        
        let giveUpDate = PromptInterval.weekly.giveUpDate(since: since, maxDuration: twoDays, spacing: .minutes(5), in: .testing)
        
        #expect((since + twoDays) == giveUpDate)
    }
    
    
    /// A negative duration means giving up right away
    @Test func negativeDurationIsZero() throws {
        let since = try Date.noon(year: 2026, month: 9, day: 1)
        
        let giveUpDate = PromptInterval.weekly.giveUpDate(since: since, maxDuration: .seconds(-1_000), spacing: .minutes(5), in: .testing)
        
        #expect(since == giveUpDate)
    }
    
    
    /// A duration longer than the interval stops one spacing before the interval ends
    @Test func longDurationStopsBeforeTheIntervalEnds() throws {
        let since = try Date.noon(year: 2026, month: 9, day: 1)
        let oneWeekLater = try Date.noon(year: 2026, month: 9, day: 8)
        
        let giveUpDate = PromptInterval.weekly.giveUpDate(since: since, maxDuration: .infinity, spacing: .minutes(5), in: .testing)
        
        #expect((oneWeekLater + .minutes(-5)) == giveUpDate)
    }
    
    
    /// StoreKit's fixed wait is the same for every interval, and the limits never shorten it
    @Test(arguments: PromptInterval.allCases)
    func storeKitWaitIsTheSameForEveryInterval(interval: PromptInterval) throws {
        let since = try Date.noon(year: 2026, month: 9, day: 1)
        let wait = StoreKitPaymentHandler.storeKitPurchase.maxTimeToCheckPendingTransactions(whenPromptAppears: interval)
        
        let giveUpDate = interval.giveUpDate(since: since, maxDuration: wait, spacing: .minutes(5), in: .testing)
        
        #expect((since + wait) == giveUpDate)
    }
}
