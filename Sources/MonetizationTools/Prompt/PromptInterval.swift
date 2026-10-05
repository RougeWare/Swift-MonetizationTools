//
//  PromptInterval.swift
//  MonetizationTools
//
//  Created by Ky directing Claude Opus 5 on 2026-09-14.
//

import Foundation



/// How long before a monetization prompt appears (again).
///
/// This is for both before its very first appearance, and between each appearance after that.
///
/// Intervals are calendar-correct rather than a fixed number of seconds, so "monthly" from January 20th means February 20th, not 30 days later. This uses ``Calendar``, so edge cases are handled how it handles them: January 31st + 1 month is the last day of February, not the 2nd or 3rd of March, etc..
public enum PromptInterval: String, Sendable, Hashable, Codable, CaseIterable {
    
    /// Once every week
    case weekly
    
    /// Once every month, on the same day-of-month
    case monthly
    
    /// Once every three months, on the same day-of-month
    case quarterly
    
    /// Once every year, on the same month and day-of-month
    case yearly
}



internal extension PromptInterval {
    
    /// This interval expressed as date components, for feeding to `Calendar`
    var dateComponents: DateComponents {
        switch self {
        case .weekly:    DateComponents(weekOfYear: 1)
        case .monthly:   DateComponents(month: 1)
        case .quarterly: DateComponents(month: 3)
        case .yearly:    DateComponents(year: 1)
        }
    }
    
    
    /// Advances the given date by this interval's amount
    /// 
    /// - Parameters:
    ///   - previousDate: The reference date
    ///   - calendar:     _optional_ - The calendar which decides what "a month" means here. Defaults to the current calendar.
    ///
    /// - Returns: One interval after the reference date
    func date(after previousDate: Date, in calendar: Calendar = .current) -> Date {
        calendar.date(byAdding: dateComponents, to: previousDate)
            ?? (previousDate + approximateDuration) // Only reachable if the calendar can't represent the result
    }
    
    
    /// A rough number of seconds in this interval, used only as a fallback when calendar math fails outright.
    ///
    /// `.yearly` uses the mean tropical year (365.24219 days), and `.monthly` & `.quarterly` are defined based off that
    @inline(__always)
    private var approximateDuration: Duration {
        switch self {
        case .weekly:    .days(7)
        case .monthly:   Self.yearly.approximateDuration / 12
        case .quarterly: Self.yearly.approximateDuration / 4
        case .yearly:    .days(365.24219) // 1 mean tropical year
        }
    }
}
