//
//  Test Support.swift
//  MonetizationTools
//
//  Created by Ky directing Claude Sonnet 5 on 2026-09-20.
//

import Foundation
import SwiftUI
import Testing
@testable import MonetizationTools



// MARK: - Dates

extension Calendar {
    
    /// A calendar which behaves the same wherever and whenever the tests run
    static var testing: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        return calendar
    }
}



extension Date {
    
    /// Noon in `Calendar.testing` on the given day, so date math never lands near a day boundary
    ///
    /// - Parameters:
    ///   - year:  The year
    ///   - month: The month, starting at 1
    ///   - day:   The day of the month, starting at 1
    static func noon(year: Int, month: Int, day: Int) throws -> Date {
        try #require(Calendar.testing.date(from: DateComponents(year: year, month: month, day: day, hour: 12)))
    }
}



// MARK: - Storage

/// Runs the given work against a throwaway defaults database, and deletes it afterward.
///
/// Tests use this instead of the standard defaults so they can't affect each other, or the app hosting them.
///
/// - Parameter body: The work to run
@MainActor
func withEphemeralDefaults(_ body: @MainActor (UserDefaults) async throws -> Void) async throws {
    let suiteName = "MonetizationToolsTest.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    
    try await body(defaults)
}



extension PromptHistoryReading {
    
    /// Whether nothing was stored
    var isNeverChecked: Bool {
        switch self {
        case .neverChecked:
            return true
            
        case .recorded(history: _):
            return false
            
        case .unreadable(cause: _):
            return false
        }
    }
    
    
    /// The history which was read, or `nil` if there wasn't a readable one
    var recordedHistory: PromptHistory? {
        switch self {
        case .neverChecked:
            return nil
            
        case .recorded(history: let history):
            return history
            
        case .unreadable(cause: _):
            return nil
        }
    }
    
    
    /// Whether something was stored which couldn't be read
    var isUnreadable: Bool {
        switch self {
        case .neverChecked:
            return false
            
        case .recorded(history: _):
            return false
            
        case .unreadable(cause: _):
            return true
        }
    }
}



// MARK: - Actions

/// A stand-in for a real action, which does whatever a test tells it to and counts how often it was asked
struct StubAction: MonetizationPromptAction {
    
    /// What happened when this action ran, for a test to choose
    let result: Result<MonetizationPromptActionOutcome, StubError>
    
    /// Counts each time this action runs
    let counter: Counter
    
    
    /// Makes a stub which finishes with the given result
    ///
    /// - Parameters:
    ///   - result:  What running the action does. Defaults to succeeding.
    ///   - counter: _optional_ - Counts runs. Defaults to a counter which nobody reads.
    @MainActor
    init(_ result: Result<MonetizationPromptActionOutcome, StubError> = .success(.succeeded),
         counter: Counter = Counter()) {
        self.result = result
        self.counter = counter
    }
    
    
    @MainActor
    func perform(id identifier: MonetizationPromptIdentifier,
                 in environment: EnvironmentValues) async throws -> MonetizationPromptActionOutcome {
        counter.count += 1
        await Task.yield()
        return try result.get()
    }
    
    
    /// Counts how often a ``StubAction`` ran
    @MainActor
    final class Counter {
        
        /// How many times the action has run
        var count = 0
    }
    
    
    /// The failure a ``StubAction`` throws when a test asks it to
    struct StubError: Error, Equatable {}
}
