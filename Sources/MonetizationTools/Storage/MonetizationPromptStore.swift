//
//  MonetizationPromptStore.swift
//  MonetizationTools
//
//  Created by Ky directing Claude Opus 5 on 2026-09-14.
//

import CryptoKit
import Foundation

import SerializationTools
import SimpleLogging
import SpecialString



/// Keeps track of which prompts have been shown, snoozed, declined, or fulfilled, and when each may next appear.
///
/// There is no setup step. The first time anything in this package needs a store, it makes one; that's the whole
/// configuration story.
@MainActor
internal final class MonetizationPromptStore {
    
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
        Self.knownDescriptors[key] = descriptor
        
        switch records[key] {
        case .done:
            return false
            
        case .tracking(interval: _, nextEligible: let nextEligible):
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
        
        guard case .tracking(interval: let interval, nextEligible: _) = records[key] else {
            // A prompt can only be snoozed from a screen where it's already showing, and it can only be showing once
            // `shouldShow` has already written a `.tracking` record for it. Landing here means that record is gone or
            // was never written — state this package didn't expect — so there's nothing safe to push out.
            log(error: "Told to snooze prompt '\(descriptor.identifier)', but its stored record is "
                     + "\(records[key].map(String.init(describing:)) ?? "missing"), not tracking. Doing nothing.")
            return
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



// MARK: - Descriptor registry

internal extension MonetizationPromptStore {
    
    /// The descriptor last used to check each identifier, so code that only has an identifier later — like a
    /// StoreKit transaction listener resolving an Ask to Buy approval — can look up the full descriptor it belongs to.
    static func descriptor(for identifier: MonetizationPromptIdentifier) -> MonetizationPrompt.Descriptor? {
        knownDescriptors[key(for: identifier)]
    }
}



// MARK: - Static state

private extension MonetizationPromptStore {
    
    /// The stores which have been asked for so far, keyed by the scope which produced them
    static var stores: [MonetizationPromptScope : MonetizationPromptStore] = [:]
    
    /// The descriptor last seen for each identifier, keyed the same way as ``records`` so it needs nothing extra
    /// from ``MonetizationPromptIdentifier`` itself. See ``descriptor(for:)``.
    static var knownDescriptors: [String : MonetizationPrompt.Descriptor] = [:]
}



// MARK: - Persistence

private extension MonetizationPromptStore {
    
    /// The user defaults key under which this package keeps everything it knows
    static let storageKey = "org.bhstudios.MonetizationTools.prompts"
    
    
    /// Records the given record for the given key, in memory and on disk
    func write(_ record: MonetizationPromptRecord, forKey key: String) {
        records[key] = record
        flush()
    }
    
    
    /// Persists everything this store knows
    func flush() {
        do {
            userDefaults.set(try records.jsonData(), forKey: Self.storageKey)
        }
        catch {
            log(error: "Couldn't persist prompt history: \(error). Losing it costs a person at most one extra ask; "
                     + "nothing else depends on this write succeeding.")
        }
    }
    
    
    /// Reads everything previously persisted, or nothing at all if this is a fresh install.
    ///
    /// Each record is decoded on its own, so one corrupted entry only costs that one prompt its history — never
    /// everyone else's. A record that fails to decode is dropped rather than guessed at, which asking for it again
    /// naturally turns into: the same "first time this was ever checked" path a fresh install takes, which starts the
    /// clock over using the descriptor's own current interval and doesn't show anything until a full interval has
    /// passed. That's deliberately the same outcome as "this was just dismissed," never "this was already paid for."
    ///
    /// - Parameter userDefaults: Where to read from
    static func readRecords(from userDefaults: UserDefaults) -> [String : MonetizationPromptRecord] {
        guard let data = userDefaults.data(forKey: storageKey) else {
            return [:]
        }
        
        guard let rawEntries = try? JSONSerialization.jsonObject(with: data) as? [String : Any] else {
            log(error: "Prompt history couldn't be parsed as JSON at all. Starting fresh; every prompt gets asked "
                     + "again at most once because of this.")
            return [:]
        }
        
        var records: [String : MonetizationPromptRecord] = [:]
        
        for (key, rawEntry) in rawEntries {
            do {
                let entryData = try JSONSerialization.data(withJSONObject: rawEntry)
                records[key] = try MonetizationPromptRecord(jsonData: entryData)
            }
            catch {
                log(error: "Dropped one corrupted prompt record (key '\(key)'): \(error). Only that one prompt is "
                         + "affected; it starts its clock over as though just checked for the first time.")
            }
        }
        
        return records
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
            .prefix(8) // Full SHA-256 is 32 bytes; this package will never have enough prompts in one app for a
                       // collision to be a realistic concern, and a shorter key keeps storage tiny.
            .map { String(format: "%02x", $0) }
            .joined()
    }
}
