//
//  MonetizationPromptStore.swift
//  MonetizationTools
//
//  Created by Ky on 2026-09-14.
//

import CryptoKit
import Foundation

import SpecialString



/// Keeps track of which prompts have been shown, snoozed, declined, or fulfilled, and when each may next appear.
///
/// There is no setup step. The first time anything in this package needs a store, it makes one; that's the whole
/// configuration story.
@MainActor
internal final class MonetizationPromptStore {
    
    /// The stores which have been asked for so far, keyed by the scope which produced them
    private static var stores: [MonetizationPromptScope : MonetizationPromptStore] = [:]
    
    /// The user defaults key under which this package keeps everything it knows
    private static let storageKey = "org.bhstudios.MonetizationTools.prompts"
    
    /// Where this store's contents are persisted
    private let userDefaults: UserDefaults
    
    /// Every prompt's record, keyed by the digest of its identifier
    private var records: [String : MonetizationPromptRecord]
    
    
    private init(scope: MonetizationPromptScope) {
        self.userDefaults = scope.userDefaults
        self.records = Self.readRecords(from: userDefaults)
    }
    
    
    /// The store backing the given scope, creating it if this is the first time anyone's asked.
    ///
    /// - Parameter scope: The scope whose store is wanted
    static func store(for scope: MonetizationPromptScope) -> MonetizationPromptStore {
        if let existing = stores[scope] {
            return existing
        }
        
        let new = MonetizationPromptStore(scope: scope)
        stores[scope] = new
        return new
    }
}



// MARK: - Questions

internal extension MonetizationPromptStore {
    
    /// Whether the given prompt may be shown right now.
    ///
    /// The first time this is ever asked about a prompt, the answer is always `false`: that first check is what starts
    /// the clock, and the prompt becomes eligible one interval later. That's also the moment the prompt's cadence is
    /// locked in.
    ///
    /// This is safe to call as often as you like. The only write it performs is that first-check one, and performing it
    /// twice does nothing the second time.
    ///
    /// - Parameters:
    ///   - descriptor: The prompt in question
    ///   - now:        _optional_ - The moment to treat as the present. Defaults to right now.
    func shouldShow(_ descriptor: MonetizationPrompt.Descriptor, now: Date = .now) -> Bool {
        let key = Self.key(for: descriptor.identifier)
        
        switch records[key] {
        case .done:
            return false
            
        case .tracking(_, let nextEligible):
            return nextEligible <= now
            
        case nil:
            // First time anyone's ever asked about this prompt. Start the clock; don't show anything yet.
            write(.tracking(interval: descriptor.interval,
                            nextEligible: descriptor.interval.date(after: now)),
                  forKey: key)
            return false
        }
    }
}



// MARK: - Answers

internal extension MonetizationPromptStore {
    
    /// Pushes the given prompt out by one of its own intervals, as though it had just been shown.
    ///
    /// The interval used is the one locked in when this prompt was first checked, not whatever its descriptor says
    /// today.
    ///
    /// - Parameters:
    ///   - descriptor: The prompt to push out
    ///   - now:        _optional_ - The moment to measure from. Defaults to right now.
    func snooze(_ descriptor: MonetizationPrompt.Descriptor, now: Date = .now) {
        let key = Self.key(for: descriptor.identifier)
        
        guard case .tracking(let interval, _) = records[key] else {
            return // Already done; nothing to push out
        }
        
        write(.tracking(interval: interval, nextEligible: interval.date(after: now)), forKey: key)
    }
    
    
    /// Retires the given prompt permanently. It will never be shown again, and everything else this store knew about it
    /// is discarded.
    ///
    /// - Parameter descriptor: The prompt to retire
    func retire(_ descriptor: MonetizationPrompt.Descriptor) {
        write(.done, forKey: Self.key(for: descriptor.identifier))
    }
}



// MARK: - Persistence

private extension MonetizationPromptStore {
    
    /// Records the given record for the given key, in memory and on disk
    func write(_ record: MonetizationPromptRecord, forKey key: String) {
        records[key] = record
        flush()
    }
    
    
    /// Persists everything this store knows
    func flush() {
        guard let data = try? JSONEncoder().encode(records) else {
            return // Nothing sensible to do here; losing prompt history costs a person at most one extra ask
        }
        
        userDefaults.set(data, forKey: Self.storageKey)
    }
    
    
    /// Reads everything previously persisted, or nothing at all if this is a fresh install
    static func readRecords(from userDefaults: UserDefaults) -> [String : MonetizationPromptRecord] {
        guard
            let data = userDefaults.data(forKey: storageKey),
            let decoded = try? JSONDecoder().decode([String : MonetizationPromptRecord].self, from: data)
        else {
            return [:]
        }
        
        return decoded
    }
    
    
    /// The fixed-length storage key for the given identifier.
    ///
    /// Swift's own `Hashable` is useless for this: its seed is randomized per process launch on purpose, so the same
    /// identifier hashes differently every time the app runs. This uses SHA-256 instead, truncated to 8 bytes, which is
    /// stable forever and plenty of room for the handful of prompts any one app will ever have.
    ///
    /// - Parameter identifier: The identifier to digest
    static func key(for identifier: MonetizationPromptIdentifier) -> String {
        SHA256.hash(data: Data(identifier.withoutTypeSafety().utf8))
            .prefix(8)
            .map { String(format: "%02x", $0) }
            .joined()
    }
}
