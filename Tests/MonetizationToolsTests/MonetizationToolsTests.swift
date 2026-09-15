//
//  MonetizationToolsTests.swift
//  MonetizationTools
//
//  Created by Ky on 2026-09-14.
//

import Foundation
import Testing

@testable import MonetizationTools



@Suite("Prompt intervals")
struct PromptIntervalTests {
    
    @Test("Monthly lands on the same day of the next month")
    func monthlyKeepsDayOfMonth() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "UTC"))
        
        let february20 = try #require(calendar.date(from: DateComponents(year: 2026, month: 2, day: 20)))
        let result = PromptInterval.monthly.date(after: february20, in: calendar)
        
        #expect(3 == calendar.component(.month, from: result))
        #expect(20 == calendar.component(.day, from: result))
    }
    
    
    @Test("Monthly from the 31st clamps rather than overflowing into the next month")
    func monthlyClampsShortMonths() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "UTC"))
        
        let january31 = try #require(calendar.date(from: DateComponents(year: 2026, month: 1, day: 31)))
        let result = PromptInterval.monthly.date(after: january31, in: calendar)
        
        #expect(2 == calendar.component(.month, from: result))
        #expect(28 == calendar.component(.day, from: result))
    }
    
    
    @Test("Every interval moves forward in time", arguments: PromptInterval.allCases)
    func everyIntervalMovesForward(interval: PromptInterval) {
        let now = Date.now
        #expect(interval.date(after: now) > now)
    }
}



@Suite("Prompt records")
struct MonetizationPromptRecordTests {
    
    @Test("A retired prompt encodes to almost nothing")
    func doneIsTiny() throws {
        let encoded = try JSONEncoder().encode(MonetizationPromptRecord.done)
        let json = try #require(String(data: encoded, encoding: .utf8))
        
        #expect(#"{"done":true}"# == json)
    }
    
    
    @Test("A retired prompt survives a round trip")
    func doneRoundTrips() throws {
        let encoded = try JSONEncoder().encode(MonetizationPromptRecord.done)
        let decoded = try JSONDecoder().decode(MonetizationPromptRecord.self, from: encoded)
        
        #expect(.done == decoded)
    }
    
    
    @Test("A live prompt survives a round trip")
    func trackingRoundTrips() throws {
        // Whole seconds, since JSON dates round-trip as doubles
        let nextEligible = Date(timeIntervalSince1970: 1_789_439_443)
        let original = MonetizationPromptRecord.tracking(interval: .quarterly, nextEligible: nextEligible)
        
        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(MonetizationPromptRecord.self, from: encoded)
        
        #expect(original == decoded)
    }
}
