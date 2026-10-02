//
//  PendingCheckLimiter Test.swift
//  MonetizationTools
//
//  Created by Ky directing Claude Opus 5.5 on 2026-10-01.
//

import Foundation
import Testing
@testable import MonetizationTools



/// Checks that attempts and checks for one prompt run one at a time, and that checks are spaced apart
@MainActor
struct PendingCheckLimiterTest {
    
    /// Only one attempt or check runs for a prompt at a time
    @Test func oneAtATimePerPrompt() {
        let limiter = PendingCheckLimiter()
        let now = Date.now
        
        #expect(limiter.begin("a", at: now, isCheck: false))
        #expect(false == limiter.begin("a", at: now, isCheck: true))
        #expect(false == limiter.begin("a", at: now, isCheck: false))
    }
    
    
    /// Different prompts don't affect each other
    @Test func promptsAreIndependent() {
        let limiter = PendingCheckLimiter()
        let now = Date.now
        
        #expect(limiter.begin("a", at: now, isCheck: true))
        #expect(limiter.begin("b", at: now, isCheck: true))
    }
    
    
    /// A check can't start until the spacing has passed since the last check ended
    @Test func checksAreSpacedApart() {
        let limiter = PendingCheckLimiter()
        let now = Date.now
        
        #expect(limiter.begin("a", at: now, isCheck: true))
        limiter.end("a", at: now, isCheck: true)
        
        #expect(false == limiter.begin("a", at: now.addingTimeInterval(PendingCheckLimiter.spacing - 1), isCheck: true))
        #expect(limiter.begin("a", at: now.addingTimeInterval(PendingCheckLimiter.spacing), isCheck: true))
    }
    
    
    /// An attempt doesn't start the spacing, so a check can follow it right away, and attempts never wait for it
    @Test func attemptsDontUseTheSpacing() {
        let limiter = PendingCheckLimiter()
        let now = Date.now
        
        #expect(limiter.begin("a", at: now, isCheck: false))
        limiter.end("a", at: now, isCheck: false)
        #expect(limiter.begin("a", at: now, isCheck: true))
        limiter.end("a", at: now, isCheck: true)
        
        #expect(limiter.begin("a", at: now, isCheck: false))
    }
    
    
    /// Forgetting a prompt clears both its running mark and its spacing
    @Test func forgettingClearsEverything() {
        let limiter = PendingCheckLimiter()
        let now = Date.now
        #expect(limiter.begin("a", at: now, isCheck: true))
        limiter.end("a", at: now, isCheck: true)
        #expect(limiter.begin("b", at: now, isCheck: false))
        
        limiter.forget("a")
        limiter.forget("b")
        
        #expect(limiter.begin("a", at: now, isCheck: true))
        #expect(limiter.begin("b", at: now, isCheck: false))
    }
    
    
    /// The same identifier in two scopes gets two different keys
    @Test func keysIncludeTheScope() {
        let perApp = PendingCheckLimiter.key(for: "com.example.prompt", scope: .perApp)
        let appGroup = PendingCheckLimiter.key(for: "com.example.prompt", scope: .appGroup(id: "group.com.example"))
        
        #expect(perApp != appGroup)
    }
}
