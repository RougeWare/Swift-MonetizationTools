//
//  Date + Duration.swift
//  MonetizationTools
//
//  Created by Ky on 2026-10-04.
//

import Foundation



internal extension Date {
    
    /// Add the given duration to the given date and return the resulting date
    ///
    /// - Parameters:
    ///   - lhs: The base date
    ///   - rhs: The duration after the base date that the returned one is
    ///
    /// - Returns: A date `rhs` into the future of `lhs`
    static func + (lhs: Date, rhs: Duration) -> Date {
        .init(timeInterval: rhs.timeInterval, since: lhs)
    }
    
    
    /// Subtract the given duration from the given date and return the resulting date
    ///
    /// - Parameters:
    ///   - lhs: The base date
    ///   - rhs: The duration before the base date that the returned one is
    ///
    /// - Returns: A date `rhs` into the past of `lhs`
    static func - (lhs: Date, rhs: Duration) -> Date {
        lhs + -rhs
    }
    
    
    /// The duration from the given date to this date
    ///
    /// - Parameter previousDate: The start date to measure this end date against
    /// - Returns: The duration from `self` to `previousDate`
    func duration(since previousDate: Date) -> Duration {
        .seconds(timeIntervalSince(previousDate))
    }
}
