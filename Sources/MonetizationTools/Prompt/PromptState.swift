//
//  PromptState.swift
//  MonetizationTools
//
//  Created by Ky directing Claude Sonnet 5 on 2026-09-20.
//

import Foundation



/// The stored state of one prompt: waiting to become due, waiting on an attempt's result, being recorded as a success, or
/// retired for good. This is all that's ever stored for a prompt.
///
/// The stored form is JSON tagged with a `"state"` field naming which of these four it is, so the four are mutually
/// exclusive: nothing stored can claim to be two of them at once.
internal enum PromptState: Sendable, Hashable {
    
    /// Waiting to become due. `interval` is locked in from whichever value was declared the first time this prompt was
    /// ever checked, and never changes after that, even if the descriptor declares a different one later.
    /// `nextEligible` is the earliest moment this prompt is due.
    ///
    /// Stored as `{"state":"scheduled","interval":"<case name>","nextEligible":"<ISO 8601 date>"}`, for example
    /// `{"state":"scheduled","interval":"monthly","nextEligible":"2026-12-20T12:00:00Z"}`.
    ///
    /// - Parameters:
    ///   - interval:     How long this prompt waits before showing again
    ///   - nextEligible: The earliest moment this prompt is due
    case scheduled(interval: PromptInterval, nextEligible: Date)
    
    /// An attempt started, and its result isn't known yet. The prompt stays hidden, and its schedule is ignored, while
    /// the package asks the action for the result. `interval` is the locked-in interval, kept so the prompt can be
    /// scheduled again if the attempt is abandoned. `since` is when the attempt started. The give-up time is counted
    /// from it.
    ///
    /// Stored as `{"state":"pending","interval":"<case name>","since":"<ISO 8601 date>"}`, for example
    /// `{"state":"pending","interval":"monthly","since":"2026-09-30T12:34:00Z"}`.
    ///
    /// - Parameters:
    ///   - interval: The locked-in interval
    ///   - since:    When the attempt started
    case pending(interval: PromptInterval, since: Date)
    
    /// An attempt succeeded, and the package is in the middle of recording that. It's stored before the action's
    /// `acknowledgeSuccess` runs, and replaced by `.done` after. If the app dies in between, the next appearance repeats
    /// `acknowledgeSuccess` and stores `.done`.
    ///
    /// Stored as `{"state":"resolving","interval":"<case name>","since":"<ISO 8601 date>"}`, for example
    /// `{"state":"resolving","interval":"monthly","since":"2026-09-30T12:34:00Z"}`.
    ///
    /// - Parameters:
    ///   - interval: The locked-in interval
    ///   - since:    When the attempt started
    case resolving(interval: PromptInterval, since: Date)
    
    /// The person completed this prompt, or declined it for good. It never shows again.
    ///
    /// Stored as `{"state":"done"}`.
    case done
}



// MARK: - Codable

// The four stored forms, exactly as a person's device holds them:
//
//     Scheduled: {"state":"scheduled","interval":"monthly","nextEligible":"2026-12-20T12:00:00Z"}
//     Pending:   {"state":"pending","interval":"monthly","since":"2026-09-30T12:34:00Z"}
//     Resolving: {"state":"resolving","interval":"monthly","since":"2026-09-30T12:34:00Z"}
//     Done:      {"state":"done"}

extension PromptState: Codable {
    
    /// The keys of the stored JSON
    private enum CodingKeys: String, CodingKey {
        case state
        case interval
        case nextEligible
        case since
    }
    
    
    /// The values of the `"state"` key, one per case
    private enum Kind: String, Codable {
        case scheduled
        case pending
        case resolving
        case done
    }
    
    
    /// Reads a stored state.
    ///
    /// Only the four shapes this type writes are accepted, so a damaged record can never be mistaken for a valid one; it
    /// throws instead, and the caller decides what a broken record means.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        switch try container.decode(Kind.self, forKey: .state) {
        case .scheduled:
            self = .scheduled(
                interval: try container.decode(PromptInterval.self, forKey: .interval),
                nextEligible: try container.decode(Date.self, forKey: .nextEligible)
            )
            
        case .pending:
            self = .pending(
                interval: try container.decode(PromptInterval.self, forKey: .interval),
                since: try container.decode(Date.self, forKey: .since)
            )
            
        case .resolving:
            self = .resolving(
                interval: try container.decode(PromptInterval.self, forKey: .interval),
                since: try container.decode(Date.self, forKey: .since)
            )
            
        case .done:
            self = .done
        }
    }
    
    
    // Never change how any of these four cases encode: doing so re-asks, or re-blocks, every prompt already stored on
    // someone's device.
    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        switch self {
        case .scheduled(interval: let interval, nextEligible: let nextEligible):
            try container.encode(Kind.scheduled, forKey: .state)
            try container.encode(interval, forKey: .interval)
            try container.encode(nextEligible, forKey: .nextEligible)
            
        case .pending(interval: let interval, since: let since):
            try container.encode(Kind.pending, forKey: .state)
            try container.encode(interval, forKey: .interval)
            try container.encode(since, forKey: .since)
            
        case .resolving(interval: let interval, since: let since):
            try container.encode(Kind.resolving, forKey: .state)
            try container.encode(interval, forKey: .interval)
            try container.encode(since, forKey: .since)
            
        case .done:
            try container.encode(Kind.done, forKey: .state)
        }
    }
}



// MARK: - Lookup

/// What was found in storage for one prompt: nothing yet, a state that was read successfully, or something stored which
/// couldn't be read.
///
/// The unreadable case has to behave differently from never-checked: the first is someone meeting the prompt for the
/// first time; the second is a prompt which has to stay quiet, since nobody knows what that person already said to it.
internal typealias PromptStateLookup = Result<PromptState, any Error>?



// MARK: - Decisions

/// What a prompt's view should do when it appears.
internal enum PromptDecision: Sendable, Hashable {
    
    /// The prompt is due. Show its content.
    case show
    
    /// The prompt isn't due, is retired, or can't be read. Show nothing.
    case hide
    
    /// An attempt is pending. Show nothing, and ask the action for the result.
    case checkPending
    
    /// A success is being recorded. Show nothing, and finish recording it.
    case finishResolving
}



// MARK: - Scheduling

internal extension PromptStateLookup {
    
    /// Decides what a prompt's view does when it appears, and whether this check needs to be remembered.
    ///
    /// The very first check of a prompt is never due. It's remembered, which locks in the interval the prompt declared,
    /// and the prompt waits that long before its first appearance. After that, a scheduled prompt shows once its
    /// `nextEligible` has arrived. A pending prompt never shows, and reports that its result is needed. A resolving prompt
    /// never shows, and reports that its recording needs to finish. A retired or unreadable prompt never shows.
    ///
    /// - Parameters:
    ///   - declaredInterval: The interval the prompt's descriptor declares. Only used on the very first check; afterward
    ///                       the stored, locked-in interval governs.
    ///   - now:              The moment being checked
    ///   - calendar:         _optional_ - The calendar which decides what "a month" means. Defaults to the current
    ///                       calendar.
    ///
    /// - Returns: What to do, and the state to remember, only on the very first check
    func check(declaring declaredInterval: PromptInterval,
               at now: Date,
               in calendar: Calendar = .current)
    -> (decision: PromptDecision, stateToRemember: PromptState?) {
        switch self {
        case .none:
            let firstState = PromptState.scheduled(
                interval: declaredInterval,
                nextEligible: declaredInterval.date(after: now, in: calendar)
            )
            return (decision: .hide, stateToRemember: firstState)
            
        case .some(.success(.scheduled(interval: _, nextEligible: let nextEligible))):
            if nextEligible <= now {
                return (decision: .show, stateToRemember: nil)
            }
            else {
                return (decision: .hide, stateToRemember: nil)
            }
            
        case .some(.success(.pending)):
            return (decision: .checkPending, stateToRemember: nil)
            
        case .some(.success(.resolving)):
            return (decision: .finishResolving, stateToRemember: nil)
            
        case .some(.success(.done)):
            return (decision: .hide, stateToRemember: nil)
            
        case .some(.failure):
            return (decision: .hide, stateToRemember: nil)
        }
    }
    
    
    /// Decides what to store after someone asks for a prompt later.
    ///
    /// Asking for later starts a new wait, one full interval long, counted from `now`, using the interval which was
    /// locked in at the prompt's first check.
    ///
    /// - Parameters:
    ///   - declaredInterval: The interval the prompt's descriptor declares. Only used if nothing is stored, which can
    ///                       only happen if storage was cleared while the prompt was showing.
    ///   - now:              The moment they asked
    ///   - calendar:         _optional_ - The calendar which decides what "a month" means. Defaults to the current
    ///                       calendar.
    ///
    /// - Returns: The state to store, or `nil` when there's nothing to change, because the prompt is pending, resolving,
    ///            already retired, or its stored state can't be read
    func snoozed(declaring declaredInterval: PromptInterval,
                 at now: Date,
                 in calendar: Calendar = .current)
    -> PromptState? {
        switch self {
        case .none:
            return .scheduled(
                interval: declaredInterval,
                nextEligible: declaredInterval.date(after: now, in: calendar)
            )
            
        case .some(.success(.scheduled(interval: let interval, nextEligible: _))):
            return .scheduled(
                interval: interval,
                nextEligible: interval.date(after: now, in: calendar)
            )
            
        case .some(.success(.pending)):
            return nil
            
        case .some(.success(.resolving)):
            return nil
            
        case .some(.success(.done)):
            return nil
            
        case .some(.failure):
            return nil
        }
    }
}



// MARK: - Attempts

internal extension PromptStateLookup {
    
    /// The state to store just before an attempt starts, or `nil` when nothing should be stored.
    ///
    /// A scheduled prompt becomes pending, keeping its locked-in interval. A prompt with nothing stored becomes pending
    /// with the declared interval; that only happens when the debug override showed the prompt. Every other state is left
    /// alone, so a retired prompt is never brought back.
    ///
    /// - Parameters:
    ///   - declaredInterval: The interval the prompt's descriptor declares. Only used if nothing is stored.
    ///   - now:              The moment the attempt starts
    ///
    /// - Returns: The state to store, or `nil`
    func startingAttempt(declaring declaredInterval: PromptInterval, at now: Date) -> PromptState? {
        switch self {
        case .none:
            return .pending(interval: declaredInterval, since: now)
            
        case .some(.success(.scheduled(interval: let interval, nextEligible: _))):
            return .pending(interval: interval, since: now)
            
        case .some(.success(.pending)):
            return nil
            
        case .some(.success(.resolving)):
            return nil
            
        case .some(.success(.done)):
            return nil
            
        case .some(.failure):
            return nil
        }
    }
    
    
    /// The state to store when an attempt ends with nothing recorded, for example because the person cancelled. The
    /// prompt becomes due at `now`. `nil` unless the stored state is pending.
    ///
    /// - Parameter now: The moment the attempt ended
    ///
    /// - Returns: The state to store, or `nil`
    func cancellingAttempt(at now: Date) -> PromptState? {
        guard case .some(.success(.pending(interval: let interval, since: _))) = self else {
            return nil
        }
        
        return .scheduled(interval: interval, nextEligible: now)
    }
    
    
    /// The state to store when an attempt's success is about to be recorded. `nil` unless the stored state is pending.
    ///
    /// - Returns: The state to store, or `nil`
    func recordingSuccess() -> PromptState? {
        guard case .some(.success(.pending(interval: let interval, since: let since))) = self else {
            return nil
        }
        
        return .resolving(interval: interval, since: since)
    }
    
    
    /// The state to store when the package learns an attempt was abandoned, or gives up waiting. The prompt is scheduled
    /// again, one interval after `now`, using the locked-in interval. `nil` unless the stored state is pending.
    ///
    /// - Parameters:
    ///   - now:      The moment the package learned it, or gave up
    ///   - calendar: _optional_ - The calendar which decides what "a month" means. Defaults to the current calendar.
    ///
    /// - Returns: The state to store, or `nil`
    func givingUp(at now: Date, in calendar: Calendar = .current) -> PromptState? {
        guard case .some(.success(.pending(interval: let interval, since: _))) = self else {
            return nil
        }
        
        return .scheduled(interval: interval, nextEligible: interval.date(after: now, in: calendar))
    }
}



// MARK: - Giving up

internal extension PromptInterval {
    
    /// When the package stops waiting for an attempt's result.
    ///
    /// Counted from `since`. `maxDuration` is limited to between zero and the time from `since` to one interval later,
    /// minus `spacing`. A calendar month counts as its real length.
    ///
    /// - Parameters:
    ///   - since:       When the attempt started
    ///   - maxDuration: How long the action wants to keep checking
    ///   - spacing:     The minimum time between two checks
    ///   - calendar:    _optional_ - The calendar which decides what "a month" means. Defaults to the current calendar.
    ///
    /// - Returns: The give-up time
    func giveUpDate(since: Date,
                    maxDuration: TimeInterval,
                    spacing: TimeInterval,
                    in calendar: Calendar = .current)
    -> Date {
        let span = date(after: since, in: calendar).timeIntervalSince(since)
        let upperLimit = max(0, span - spacing)
        let duration = min(max(0, maxDuration), upperLimit)
        return since.addingTimeInterval(duration)
    }
    
    
    /// A quarter of this interval, counted from `reference`. This is the default for
    /// `maxTimeToCheckPendingTransactions(whenPromptAppears:)`.
    ///
    /// - Parameters:
    ///   - reference: The date to count from
    ///   - calendar:  _optional_ - The calendar which decides what "a month" means. Defaults to the current calendar.
    ///
    /// - Returns: A quarter of the interval, in seconds
    func quarterDuration(from reference: Date, in calendar: Calendar = .current) -> TimeInterval {
        date(after: reference, in: calendar).timeIntervalSince(reference) / 4
    }
}
