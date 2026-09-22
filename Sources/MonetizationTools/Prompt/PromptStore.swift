//
//  PromptStore.swift
//  MonetizationTools
//
//  Created by Ky directing Claude Sonnet 5 on 2026-09-20.
//

import Foundation
import SerializationTools
import SimpleLogging



/// Remembers each prompt's ``PromptHistory`` in a `UserDefaults` database.
///
/// Storage is kept here so nothing else has to know how or where anything is remembered. The prompt and its flow say
/// what happened; this decides what that means for storage. There's no setup step: whichever prompt first needs a store
/// makes one, from its own scope.
///
/// Every operation which can fail handles its own failure, by logging it and choosing the quiet outcome. A prompt which
/// can't read or write its history stays out of the way rather than risk asking someone twice.
@MainActor
internal struct PromptStore {
    
    /// The database which holds every history this store knows about
    private let defaults: UserDefaults
    
    
    /// Makes a store which keeps histories in the given database.
    ///
    /// Tests use this with a throwaway database. Everything else goes through ``init(scope:)``.
    ///
    /// - Parameter defaults: The database to keep histories in
    init(defaults: UserDefaults) {
        self.defaults = defaults
    }
    
    
    /// Makes the store which a prompt's scope calls for.
    ///
    /// - Parameter scope: The scope of the prompt which needs a store
    ///
    /// - Returns: The store, or `nil` when the scope is an App Group whose defaults can't be opened. This is a
    ///            misconfiguration, so it's also logged, and it fails an assertion in debug builds.
    init?(scope: MonetizationPromptScope) {
        guard let defaults = scope.userDefaults else {
            assertionFailure("The defaults for \(scope) can't be opened, so its prompts will never show")
            log(error: "The defaults for \(scope) can't be opened, so its prompts will never show")
            return nil
        }
        
        self.init(defaults: defaults)
    }
}



// MARK: - Keys

internal extension PromptStore {
    
    /// The start of every key this store writes, which keeps prompt histories apart from everything else in the same
    /// database
    private static let keyPrefix = "MonetizationTools.prompt."
    
    
    /// The key under which a prompt's history is kept.
    ///
    /// This is a compatibility promise. Changing how it's built means everyone who ever declined a prompt is asked
    /// again, so it must never change.
    ///
    /// - Parameter id: Identifies the prompt
    static func key(for id: MonetizationPromptIdentifier) -> String {
        keyPrefix + id.withoutTypeSafety()
    }
}



// MARK: - Reading and writing

internal extension PromptStore {
    
    /// Reads what's stored for a prompt.
    ///
    /// - Parameter id: Identifies the prompt
    ///
    /// - Returns: What was found. Anything stored which isn't a readable history, of any type, is
    ///            ``PromptHistoryReading/unreadable(cause:)`` and is logged.
    func reading(for id: MonetizationPromptIdentifier) -> PromptHistoryReading {
        switch defaults.object(forKey: Self.key(for: id)) {
        case .none:
            return .neverChecked
            
        case .some(let stored as String):
            do {
                return .recorded(history: try PromptHistory(jsonString: stored))
            }
            catch {
                log(error: error, "The history of the prompt \(id) can't be read, so it will never show")
                return .unreadable(cause: error)
            }
            
        case .some:
            log(error: "The history of the prompt \(id) isn't a string, so it will never show")
            return .unreadable(cause: ReadingError.storedValueIsNotAString)
        }
    }
    
    
    /// Stores a prompt's history, replacing whatever was stored before. If it can't be encoded, that's logged and
    /// nothing changes.
    ///
    /// - Parameters:
    ///   - history: What to store
    ///   - id:      Identifies the prompt
    func remember(_ history: PromptHistory, for id: MonetizationPromptIdentifier) {
        do {
            defaults.set(try history.jsonString(), forKey: Self.key(for: id))
        }
        catch {
            log(error: error, "The history of the prompt \(id) can't be stored")
        }
    }
}



// MARK: - What prompts need

internal extension PromptStore {
    
    /// Checks whether a prompt is due, and remembers the check if it's the very first one.
    ///
    /// This runs when a prompt's view appears. It never shows anything and it never changes a prompt's schedule, except
    /// that the very first check of a prompt locks in its cadence.
    ///
    /// - Parameters:
    ///   - descriptor: Describes the prompt being checked
    ///   - now:        _optional_ - The moment of the check. Defaults to the current moment.
    ///   - calendar:   _optional_ - The calendar which decides what "a month" means. Defaults to the current calendar.
    ///
    /// - Returns: Whether the prompt is due to be shown
    func check(_ descriptor: MonetizationPrompt.Descriptor,
               at now: Date = .now,
               in calendar: Calendar = .current)
    -> Bool {
        let result = reading(for: descriptor.identifier)
            .check(declaring: descriptor.interval, at: now, in: calendar)
        
        if let historyToRemember = result.historyToRemember {
            remember(historyToRemember, for: descriptor.identifier)
        }
        
        return result.isDue
    }
    
    
    /// Starts a prompt's next wait, because someone asked for it later
    ///
    /// - Parameters:
    ///   - descriptor: Describes the prompt being snoozed
    ///   - now:        _optional_ - The moment they asked. Defaults to the current moment.
    ///   - calendar:   _optional_ - The calendar which decides what "a month" means. Defaults to the current calendar.
    func snooze(_ descriptor: MonetizationPrompt.Descriptor,
                at now: Date = .now,
                in calendar: Calendar = .current) {
        let snoozedHistory = reading(for: descriptor.identifier)
            .snoozed(declaring: descriptor.interval, at: now, in: calendar)
        
        if let snoozedHistory {
            remember(snoozedHistory, for: descriptor.identifier)
        }
    }
    
    
    /// Retires a prompt, so it never shows again. This is for a declined prompt and a fulfilled one, and it also
    /// repairs a history which couldn't be read.
    ///
    /// - Parameter id: Identifies the prompt
    func retire(_ id: MonetizationPromptIdentifier) {
        remember(.done, for: id)
    }
    
    
    #if DEBUG
    /// Erases everything stored for a prompt, so its next check behaves like the first one after a fresh install.
    ///
    /// This is for ``MonetizationPromptFlow/reset()``, and exists only in debug builds.
    ///
    /// - Parameter id: Identifies the prompt
    func forget(_ id: MonetizationPromptIdentifier) {
        defaults.removeObject(forKey: Self.key(for: id))
    }
    #endif
}



// MARK: - Errors

private extension PromptStore {
    
    /// Why a stored value couldn't be read as a history, when that isn't a decoding failure
    enum ReadingError: Error {
        
        /// Something is stored under the prompt's key, but it isn't a string
        case storedValueIsNotAString
    }
}
