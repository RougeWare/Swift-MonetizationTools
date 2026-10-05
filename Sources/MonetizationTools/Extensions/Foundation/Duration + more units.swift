//
//  Duration + more units.swift
//  MonetizationTools
//
//  Created by Ky on 2026-10-05.
//

import Foundation



internal extension Duration {
    
    // MARK: Minutes
    
    /// Construct a `Duration` given a number of minutes represented as a `BinaryInteger`.
    ///
    ///       let d: Duration = .minutes(67)
    ///
    /// - Returns: A `Duration` representing a given number of minutes
    @inline(__always)
    static func minutes<I: BinaryInteger>(_ minutes: I) -> Self {
        .seconds(minutes * 60)
    }
    
    
    /// Construct a `Duration` given a number of minutes represented as a `Double` by converting the value into the closest attosecond scale value.
    ///
    ///       let d: Duration = .minutes(42.67)
    ///
    /// - Returns: A `Duration` representing a given number of minutes
    @inline(__always)
    static func minutes(_ minutes: Double) -> Self {
        .seconds(minutes * 60)
    }
    
    
    // MARK: Hours
    
    /// Construct a `Duration` given a number of hours represented as a `BinaryInteger`.
    ///
    ///       let d: Duration = .hours(11)
    ///
    /// - Returns: A `Duration` representing a given number of hours
    @inline(__always)
    static func hours<I: BinaryInteger>(_ hours: I) -> Self {
        .minutes(hours * 60)
    }
    
    
    /// Construct a `Duration` given a number of hours represented as a `Double` by converting the value into the closest attosecond scale value.
    ///
    ///       let d: Duration = .hours(11.69)
    ///
    /// - Returns: A `Duration` representing a given number of hours
    @inline(__always)
    static func hours(_ hours: Double) -> Self {
        .minutes(hours * 60)
    }
    
    
    // MARK: Days
    
    /// Construct a `Duration` given a number of days represented as a `BinaryInteger`.
    ///
    ///       let d: Duration = .days(69)
    ///
    /// - Returns: A `Duration` representing a given number of days
    @inline(__always)
    static func days<I: BinaryInteger>(_ days: I) -> Self {
        .hours(days * 24)
    }
    
    
    /// Construct a `Duration` given a number of days represented as a `Double` by converting the value into the closest attosecond scale value.
    ///
    ///       let d: Duration = .days(69.420)
    ///
    /// - Returns: A `Duration` representing a given number of days
    @inline(__always)
    static func days(_ days: Double) -> Self {
        .hours(days * 24)
    }
}
