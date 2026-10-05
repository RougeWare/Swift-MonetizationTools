//
//  PendingCheckLimiter.swift
//  MonetizationTools
//
//  Created by Ky directing Claude Opus 5.5 on 2026-10-01.
//

import Foundation



/// Allows one attempt or check at a time for each prompt, and spaces checks apart. It lives in memory only, so a relaunch
/// starts with no spacing.
@MainActor
internal final class PendingCheckLimiter {
    
    /// The shared limiter
    static let shared = PendingCheckLimiter()
    
    /// The minimum time between the end of one check and the start of the next, for one prompt
    static let spacing: Duration = .minutes(5)
    
    /// The keys of prompts with an attempt or check running right now
    private var running: Set<String> = []
    
    /// When the last check ended, for each prompt's key
    private var lastCheckEnded: [String: Date] = [:]
    
    
    /// Makes a limiter which knows about nothing yet. Everything except tests uses ``shared``.
    init() {
    }
    
    
    /// The key for a prompt: its scope and its identifier.
    ///
    /// - Parameters:
    ///   - identifier: Identifies the prompt
    ///   - scope:      The prompt's scope
    static func key(for identifier: MonetizationPrompt.Identifier, scope: MonetizationPrompt.Scope) -> String {
        "\(scope)|\(identifier.withoutTypeSafety())"
    }
    
    
    /// Tries to start an attempt or a check for the prompt with this key.
    ///
    /// - Parameters:
    ///   - key:     The prompt's key
    ///   - now:     The moment it would start
    ///   - isCheck: `true` for a check, which also has to wait out the spacing; `false` for an attempt
    ///
    /// - Returns: `true` if it may run. `false` if one is already running, or, for a check, the last check ended too
    ///            recently.
    func begin(_ key: String, at now: Date, isCheck: Bool) -> Bool {
        guard false == running.contains(key) else {
            return false
        }
        
        if isCheck,
           let lastCheckEnded = lastCheckEnded[key],
           now < (lastCheckEnded + Self.spacing)
        {
            return false
        }
        
        running.insert(key)
        return true
    }
    
    
    /// Marks the running attempt or check for this key as ended. A check starts the spacing from `now`; an attempt
    /// doesn't.
    ///
    /// - Parameters:
    ///   - key:     The prompt's key
    ///   - now:     The moment it ended
    ///   - isCheck: `true` if it was a check
    func end(_ key: String, at now: Date, isCheck: Bool) {
        running.remove(key)
        
        if isCheck {
            lastCheckEnded[key] = now
        }
    }
    
    
    /// Forgets everything about this key. The debug `reset()` uses it, so test loops aren't delayed by the spacing.
    ///
    /// - Parameter key: The prompt's key
    func forget(_ key: String) {
        running.remove(key)
        lastCheckEnded[key] = nil
    }
}
