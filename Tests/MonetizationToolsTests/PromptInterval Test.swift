//
//  PromptInterval Test.swift
//  MonetizationTools
//
//  Created by Ky directing Claude Sonnet 5 on 2026-09-20.
//

import Foundation
import Testing
@testable import MonetizationTools



/// Checks that every interval means what the README says: calendar-correct, never a fixed number of seconds
struct PromptIntervalTest {
    
    /// A week has no length to clamp, so this is plain
    @Test func weeklyIsSevenDays() throws {
        let start = try Date.noon(year: 2026, month: 9, day: 20)
        let expected = try Date.noon(year: 2026, month: 9, day: 27)
        
        #expect(expected == PromptInterval.weekly.date(after: start, in: .testing))
    }
    
    
    /// January 31st has no matching day a month later, so it clamps to the end of February, as the README promises
    @Test func monthlyClampsToTheEndOfAShorterMonth() throws {
        let start = try Date.noon(year: 2026, month: 1, day: 31)
        let expected = try Date.noon(year: 2026, month: 2, day: 28)
        
        #expect(expected == PromptInterval.monthly.date(after: start, in: .testing))
    }
    
    
    /// The clamp lands on February 29th in a leap year
    @Test func monthlyClampsToLeapDay() throws {
        let start = try Date.noon(year: 2028, month: 1, day: 31)
        let expected = try Date.noon(year: 2028, month: 2, day: 29)
        
        #expect(expected == PromptInterval.monthly.date(after: start, in: .testing))
    }
    
    
    /// Three months from November 30th is a February which has no 30th
    @Test func quarterlyClampsToTheEndOfAShorterMonth() throws {
        let start = try Date.noon(year: 2025, month: 11, day: 30)
        let expected = try Date.noon(year: 2026, month: 2, day: 28)
        
        #expect(expected == PromptInterval.quarterly.date(after: start, in: .testing))
    }
    
    
    /// A year from a leap day is a year with no leap day
    @Test func yearlyClampsFromLeapDay() throws {
        let start = try Date.noon(year: 2028, month: 2, day: 29)
        let expected = try Date.noon(year: 2029, month: 2, day: 28)
        
        #expect(expected == PromptInterval.yearly.date(after: start, in: .testing))
    }
    
    
    /// The README promises that nothing can be spelled which is more frequent than weekly. Every interval must be at
    /// least a week long, so a new case can't quietly break that.
    @Test(arguments: PromptInterval.allCases)
    func everyIntervalIsAtLeastAWeek(interval: PromptInterval) throws {
        let start = try Date.noon(year: 2026, month: 9, day: 20)
        let week = try Date.noon(year: 2026, month: 9, day: 27)
        
        #expect(week <= interval.date(after: start, in: .testing))
    }
}
