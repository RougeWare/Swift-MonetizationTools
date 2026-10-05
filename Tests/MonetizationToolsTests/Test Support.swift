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



extension PromptStateLookup {
    
    /// Whether nothing was stored
    var isNeverChecked: Bool {
        switch self {
        case .none:
            return true
            
        case .some(.success):
            return false
            
        case .some(.failure):
            return false
        }
    }
    
    
    /// The state which was read, or `nil` if there wasn't a readable one
    var recordedState: PromptState? {
        switch self {
        case .none:
            return nil
            
        case .some(.success(let state)):
            return state
            
        case .some(.failure):
            return nil
        }
    }
    
    
    /// Whether something was stored which couldn't be read
    var isUnreadable: Bool {
        switch self {
        case .none:
            return false
            
        case .some(.success):
            return false
            
        case .some(.failure):
            return true
        }
    }
}



// MARK: - Actions

/// A stand-in for a real action, which does whatever a test tells it to and records what it was asked to do
struct StubAction: PaymentHandler {
    
    /// What happened when this action ran, for a test to choose
    let result: Result<PaymentOutcome, StubError>
    
    /// What `checkPending` reports, for a test to choose
    let pendingResult: PaymentOutcome
    
    /// How long to keep checking a pending attempt, or `nil` to use the protocol's default
    let maxCheckingTime: Duration?
    
    /// Records each time this action is asked to do something
    let counter: Counter
    
    
    /// Makes a stub which finishes with the given results
    ///
    /// - Parameters:
    ///   - result:          What running the action does. Defaults to succeeding.
    ///   - pendingResult:   _optional_ - What `checkPending` reports. Defaults to `.currentStateUnknown`.
    ///   - maxCheckingTime: _optional_ - How long to keep checking a pending attempt. Defaults to the protocol's default.
    ///   - counter:         _optional_ - Records what the action was asked. Defaults to a counter which nobody reads.
    @MainActor
    init(_ result: Result<PaymentOutcome, StubError> = .success(.succeeded),
         pendingResult: PaymentOutcome = .currentStateUnknown,
         maxCheckingTime: Duration? = nil,
         counter: Counter = Counter()) {
        self.result = result
        self.pendingResult = pendingResult
        self.maxCheckingTime = maxCheckingTime
        self.counter = counter
    }
    
    
    @MainActor
    func launch(id identifier: MonetizationPrompt.Identifier,
                in environment: EnvironmentValues) async throws -> Outcome {
        counter.count += 1
        counter.events.append(.perform)
        counter.onPerform?()
        await Task.yield()
        return try result.get()
    }
    
    
    func checkPending(id identifier: MonetizationPrompt.Identifier) async -> Outcome {
        await counter.record(.checkPending)
        return pendingResult
    }
    
    
    func handleSuccess(id identifier: MonetizationPrompt.Identifier) async {
        await counter.record(.acknowledgeSuccess)
    }
    
    
    func maxTimeToCheckPendingTransactions(whenPromptAppears interval: PromptInterval) -> Duration {
        maxCheckingTime ?? (interval.duration(since: .now) / 4)
    }
    
    
    /// Records what a ``StubAction`` was asked to do
    @MainActor
    final class Counter {
        
        /// How many times the action's `launch` has run
        var count = 0
        
        /// Everything the action was asked to do, in order
        var events: [Event] = []
        
        /// Runs inside `launch`, so a test can look at storage while the action is running
        var onPerform: (@MainActor () -> Void)? = nil
        
        /// Runs inside `acknowledgeSuccess`, so a test can look at storage while the action is running
        var onAcknowledgeSuccess: (@MainActor () -> Void)? = nil
        
        
        /// Records one request, and runs its hook if it has one
        ///
        /// - Parameter event: What the action was asked to do
        func record(_ event: Event) {
            events.append(event)
            
            if Event.acknowledgeSuccess == event {
                onAcknowledgeSuccess?()
            }
        }
        
        
        /// One thing a ``StubAction`` can be asked to do
        enum Event: Equatable, Sendable {
            case perform
            case checkPending
            case acknowledgeSuccess
        }
    }
    
    
    /// The failure a ``StubAction`` throws when a test asks it to
    struct StubError: Error, Equatable {}
}



/// An action which implements only `launch`, so tests can check the protocol's default implementations
struct MinimalPaymentHandler: PaymentHandler {
    
    @MainActor
    func launch(id identifier: MonetizationPrompt.Identifier,
                in environment: EnvironmentValues) async throws -> Outcome {
        .pending
    }
}



/// Waits for a condition, by yielding to other tasks until it's true or a limit is reached
///
/// - Parameter condition: What to wait for
@MainActor
func waitUntil(_ condition: @MainActor () -> Bool) async {
    for _ in 0 ..< 1_000 {
        if condition() {
            return
        }
        
        await Task.yield()
    }
}
