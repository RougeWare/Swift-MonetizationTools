//
//  PromptState.swift
//  MonetizationTools
//
//  Created by Ky directing Claude Sonnet 5 on 2026-09-20.
//

import Foundation



/// The stored state of one prompt: waiting to become due, waiting on something external to resolve, or retired for
/// good. This is all that's ever stored for a prompt.
///
/// The stored form is JSON, tagged with a `"state"` field naming which of these three it is, so the three are mutually
/// exclusive: nothing stored can ever claim to be two of these at once.
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
    
    /// Something outside this package has to happen before this prompt's outcome is known, like a parent approving an
    /// Ask to Buy request. The prompt stays hidden and its schedule is ignored until that's resolved.
    ///
    /// Stored as `{"state":"pending"}`.
    case pending
    
    /// The person completed this prompt, or declined it for good. It never shows again.
    ///
    /// Stored as `{"state":"done"}`.
    case done
}



// MARK: - Codable

// The three stored forms, exactly as a person's device holds them:
//
//     Scheduled: {"state":"scheduled","interval":"monthly","nextEligible":"2026-12-20T12:00:00Z"}
//     Pending:   {"state":"pending"}
//     Done:      {"state":"done"}

extension PromptState: Codable {
    
    /// The keys of the stored JSON
    private enum CodingKeys: String, CodingKey {
        case state
        case interval
        case nextEligible
    }
    
    
    /// The values of the `"state"` key, one per case
    private enum Kind: String, Codable {
        case scheduled
        case pending
        case done
    }
    
    
    /// Reads a stored state.
    ///
    /// Only the three shapes this type writes are accepted, so a damaged record can never be mistaken for a valid one;
    /// it throws instead, and the caller decides what a broken record means.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        switch try container.decode(Kind.self, forKey: .state) {
        case .scheduled:
            self = .scheduled(
                interval: try container.decode(PromptInterval.self, forKey: .interval),
                nextEligible: try container.decode(Date.self, forKey: .nextEligible)
            )
            
        case .pending:
            self = .pending
            
        case .done:
            self = .done
        }
    }
    
    
    // Never change how any of these three cases encode: doing so re-asks, or re-blocks, every prompt already stored on
    // someone's device.
    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        switch self {
        case .scheduled(interval: let interval, nextEligible: let nextEligible):
            try container.encode(Kind.scheduled, forKey: .state)
            try container.encode(interval, forKey: .interval)
            try container.encode(nextEligible, forKey: .nextEligible)
            
        case .pending:
            try container.encode(Kind.pending, forKey: .state)
            
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



// MARK: - Scheduling

internal extension PromptStateLookup {
    
    /// Decides whether a prompt is due right now, and whether this check needs to be remembered.
    ///
    /// The very first check of a prompt is never due. It's remembered, which locks in the interval the prompt declared,
    /// and the prompt waits that long before its first appearance. Every check after that is due once its stored
    /// `nextEligible` has arrived. A pending, retired, or unreadable prompt is never due.
    ///
    /// - Parameters:
    ///   - declaredInterval: The interval the prompt's descriptor declares. Only used on the very first check;
    ///                       afterward the stored, locked-in interval governs.
    ///   - now:              The moment being checked
    ///   - calendar:         _optional_ - The calendar which decides what "a month" means. Defaults to the current
    ///                       calendar.
    ///
    /// - Returns: Whether the prompt is due, and the state to remember, only on the very first check
    func check(declaring declaredInterval: PromptInterval,
               at now: Date,
               in calendar: Calendar = .current)
    -> (isDue: Bool, stateToRemember: PromptState?) {
        switch self {
        case .none:
            let firstState = PromptState.scheduled(
                interval: declaredInterval,
                nextEligible: declaredInterval.date(after: now, in: calendar)
            )
            return (isDue: false, stateToRemember: firstState)
            
        case .some(.success(.scheduled(interval: _, nextEligible: let nextEligible))):
            return (isDue: nextEligible <= now, stateToRemember: nil)
            
        case .some(.success(.pending)):
            return (isDue: false, stateToRemember: nil)
            
        case .some(.success(.done)):
            return (isDue: false, stateToRemember: nil)
            
        case .some(.failure):
            return (isDue: false, stateToRemember: nil)
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
    /// - Returns: The state to store, or `nil` when there's nothing to change, because the prompt is pending, already
    ///            retired, or its stored state can't be read
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
            
        case .some(.success(.done)):
            return nil
            
        case .some(.failure):
            return nil
        }
    }
}
