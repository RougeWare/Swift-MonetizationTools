//
//  PromptStore.swift
//  MonetizationTools
//
//  Created by Ky directing Claude Sonnet 5 on 2026-09-20.
//

import Foundation
import SerializationTools
import SimpleLogging



/// Serializes and persists each prompt's ``PromptState`` to disk, in a `UserDefaults` database.
///
/// Storage is kept here so nothing else has to know how or where anything is remembered. The prompt and its flow say
/// what happened; this decides what that means for storage. There's no setup step: whichever prompt first needs a store
/// makes one, from its own scope.
///
/// Every operation which can fail handles its own failure, by logging it and choosing the quiet outcome. A prompt which
/// can't read or write its state stays out of the way rather than risk asking someone twice.
@MainActor
internal struct PromptStore {
    
    /// The database which holds every state this store knows about
    private let defaults: UserDefaults
    
    
    /// Makes a store which keeps states in the given database.
    ///
    /// Tests use this with a throwaway database. Everything else goes through ``init(scope:)``.
    ///
    /// - Parameter defaults: The database to keep states in
    init(defaults: UserDefaults) {
        self.defaults = defaults
    }
    
    
    /// Makes the store which a prompt's scope calls for.
    ///
    /// - Parameter scope: The scope of the prompt which needs a store
    ///
    /// - Returns: The store, or `nil` when the scope is an App Group whose defaults can't be opened. This is a
    ///            misconfiguration, so it's also logged, and it fails an assertion in debug builds.
    init?(scope: MonetizationPrompt.Scope) {
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
    
    /// The start of every key this store writes, which keeps prompt states apart from everything else in the same
    /// database
    private static let keyPrefix = "MonetizationTools.prompt."
    
    
    /// The key under which a prompt's state is kept.
    ///
    /// This is a compatibility promise. Changing how it's built means everyone who ever declined a prompt is asked
    /// again, so it must never change.
    ///
    /// - Parameter id: Identifies the prompt
    static func key(for id: MonetizationPrompt.Identifier) -> String {
        keyPrefix + id.withoutTypeSafety()
    }
}



// MARK: - Reading and writing

internal extension PromptStore {
    
    /// Reads what's stored for a prompt.
    ///
    /// - Parameter id: Identifies the prompt
    ///
    /// - Returns: `nil` when nothing is stored. Anything stored which isn't a readable state, of any type, is a
    ///            `.failure` and is logged.
    func lookUpState(for id: MonetizationPrompt.Identifier) -> PromptStateLookup {
        switch defaults.object(forKey: Self.key(for: id)) {
        case .none:
            return nil
            
        case .some(let stored as String):
            do {
                return .success(try PromptState(jsonString: stored))
            }
            catch {
                log(error: error, "The state of the prompt \(id) can't be read, so it will never show")
                return .failure(error)
            }
            
        case .some:
            log(error: "The state of the prompt \(id) isn't a string, so it will never show")
            return .failure(ReadingError.storedValueIsNotAString)
        }
    }
    
    
    /// Stores a prompt's state, replacing whatever was stored before. If it can't be encoded, that's logged and
    /// nothing changes.
    ///
    /// - Parameters:
    ///   - state: What to store
    ///   - id:    Identifies the prompt
    func persist(_ state: PromptState, for id: MonetizationPrompt.Identifier) {
        do {
            defaults.set(try state.jsonString(), forKey: Self.key(for: id))
        }
        catch {
            log(error: error, "The state of the prompt \(id) can't be stored")
        }
    }
}



// MARK: - What prompts need

internal extension PromptStore {
    
    /// Decides what a prompt's view does when it appears, and remembers the check if it's the very first one.
    ///
    /// Runs once each time SwiftUI inserts the prompt's view into the screen. It only decides what the view does; it
    /// doesn't render anything. It never changes a prompt's state, except that the very first check of a prompt locks in
    /// its cadence.
    ///
    /// - Parameters:
    ///   - descriptor: Describes the prompt being checked
    ///   - now:        _optional_ - The moment of the check. Defaults to the current moment.
    ///   - calendar:   _optional_ - The calendar which decides what "a month" means. Defaults to the current calendar.
    ///
    /// - Returns: What the prompt's view should do
    func check(_ descriptor: MonetizationPrompt.Descriptor,
               at now: Date = .now,
               in calendar: Calendar = .current)
    -> PromptDecision {
        let result = lookUpState(for: descriptor.identifier)
            .check(declaring: descriptor.interval, at: now, in: calendar)
        
        if let stateToRemember = result.stateToRemember {
            persist(stateToRemember, for: descriptor.identifier)
        }
        
        return result.decision
    }
    
    
    /// Reads a prompt's stored state, asks `transition` what to store, and stores it if `transition` returned a state.
    ///
    /// The state is read when this runs, not earlier, so a result which arrives late is applied to what's stored now.
    ///
    /// - Parameters:
    ///   - id:         Identifies the prompt
    ///   - transition: Given what's stored, returns the state to store, or `nil` to store nothing
    ///
    /// - Returns: The state which was stored, or `nil` if nothing was
    @discardableResult
    func update(_ id: MonetizationPrompt.Identifier,
                using transition: (PromptStateLookup) -> PromptState?)
    -> PromptState? {
        guard let newState = transition(lookUpState(for: id)) else {
            return nil
        }
        
        persist(newState, for: id)
        return newState
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
        let snoozedState = lookUpState(for: descriptor.identifier)
            .snoozed(declaring: descriptor.interval, at: now, in: calendar)
        
        if let snoozedState {
            persist(snoozedState, for: descriptor.identifier)
        }
    }
    
    
    /// Retires a prompt, so it never shows again. This is for a declined prompt and a fulfilled one, and it also
    /// repairs a state which couldn't be read.
    ///
    /// - Parameter id: Identifies the prompt
    func retire(_ id: MonetizationPrompt.Identifier) {
        persist(.done, for: id)
    }
    
    
    #if DEBUG
    /// Erases everything stored for a prompt, so its next check behaves like the first one after a fresh install.
    ///
    /// This is for ``MonetizationPrompt/Flow/reset()``, and exists only in debug builds.
    ///
    /// - Parameter id: Identifies the prompt
    func reset(_ id: MonetizationPrompt.Identifier) {
        defaults.removeObject(forKey: Self.key(for: id))
    }
    #endif
}



// MARK: - Errors

private extension PromptStore {
    
    /// Why a stored value couldn't be read as a state, when that isn't a decoding failure
    enum ReadingError: Error {
        
        /// Something is stored under the prompt's key, but it isn't a string
        case storedValueIsNotAString
    }
}
