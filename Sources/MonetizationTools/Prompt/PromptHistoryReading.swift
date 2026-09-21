//
//  PromptHistoryReading.swift
//  MonetizationTools
//
//  Created by Ky directing Claude Sonnet 5 on 2026-09-20.
//

import Foundation



/// What was found in storage for one prompt.
///
/// This is its own type instead of an optional history because "nothing stored" and "something stored which can't be
/// read" need opposite behavior. The first is someone meeting the prompt for the first time. The second is a prompt
/// which has to stay quiet, since nobody knows what that person already said to it.
internal enum PromptHistoryReading: Sendable {
    
    /// Nothing is stored, so this prompt has never been checked
    case neverChecked
    
    /// A history was stored, and it was read successfully
    case recorded(history: PromptHistory)
    
    /// Something is stored, but it couldn't be read
    case unreadable(cause: any Error)
}



// MARK: - Scheduling

/// The decisions which govern when a prompt shows. Nothing here reads a clock, a calendar, or storage; those are all
/// inputs, so any moment in history can be checked without waiting for it.
internal extension PromptHistoryReading {
    
    /// Decides whether a prompt is due right now, and whether this check needs to be remembered.
    ///
    /// The very first check of a prompt is never due. It's remembered, which locks in the interval the prompt declared,
    /// and the prompt waits that long before its first appearance. Every check after that is due once its stored
    /// `nextEligible` has arrived. A retired prompt is never due, and neither is one whose stored history can't be read.
    ///
    /// - Parameters:
    ///   - declaredInterval: The interval the prompt's descriptor declares. It's only used on the very first check;
    ///                       afterward the stored, locked-in interval governs.
    ///   - now:              The moment being checked
    ///   - calendar:         _optional_ - The calendar which decides what "a month" means. Defaults to the current
    ///                       calendar.
    ///
    /// - Returns: Whether the prompt is due, and the history to remember (only on the very first check)
    func check(declaring declaredInterval: PromptInterval,
               at now: Date,
               in calendar: Calendar = .current)
    -> (isDue: Bool, historyToRemember: PromptHistory?) {
        switch self {
        case .neverChecked:
            let firstHistory = PromptHistory.tracking(
                interval: declaredInterval,
                nextEligible: declaredInterval.date(after: now, in: calendar)
            )
            return (isDue: false, historyToRemember: firstHistory)
            
        case .recorded(history: .tracking(interval: _, nextEligible: let nextEligible)):
            return (isDue: nextEligible <= now, historyToRemember: nil)
            
        case .recorded(history: .done):
            return (isDue: false, historyToRemember: nil)
            
        case .unreadable(cause: _):
            return (isDue: false, historyToRemember: nil)
        }
    }
    
    
    /// Decides what to store after someone asks for a prompt later.
    ///
    /// Asking for later starts a new wait, one full interval long, counted from `now`. It uses the interval which was
    /// locked in at the prompt's first check, so nothing can shorten it after the fact.
    ///
    /// - Parameters:
    ///   - declaredInterval: The interval the prompt's descriptor declares. It's only used if nothing is stored, which
    ///                       can only happen if storage was cleared while the prompt was showing; then this is treated
    ///                       as the first check.
    ///   - now:              The moment they asked
    ///   - calendar:         _optional_ - The calendar which decides what "a month" means. Defaults to the current
    ///                       calendar.
    ///
    /// - Returns: The history to store, or `nil` when there's nothing to change because the prompt is already retired
    ///            or its stored history can't be read
    func snoozed(declaring declaredInterval: PromptInterval,
                 at now: Date,
                 in calendar: Calendar = .current)
    -> PromptHistory? {
        switch self {
        case .neverChecked:
            return .tracking(
                interval: declaredInterval,
                nextEligible: declaredInterval.date(after: now, in: calendar)
            )
            
        case .recorded(history: .tracking(interval: let interval, nextEligible: _)):
            return .tracking(
                interval: interval,
                nextEligible: interval.date(after: now, in: calendar)
            )
            
        case .recorded(history: .done):
            return nil
            
        case .unreadable(cause: _):
            return nil
        }
    }
}
