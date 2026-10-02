//
//  MonetizationPrompt + Flow.swift
//  MonetizationTools
//
//  Created by Ky directing Claude Sonnet 5 on 2026-09-20.
//

import SwiftUI
import SimpleLogging



public extension MonetizationPrompt {
    
    /// The things a person can do about a monetization prompt, handed to the content you put in it.
    ///
    /// Every button in a prompt calls one of these three, and nothing else about the prompt needs your code:
    ///
    /// - `present()` when they want what the prompt offers
    /// - ``snooze()`` when they want to be asked again later
    /// - ``decline()`` when they never want to be asked again
    ///
    /// You don't make one of these; ``MonetizationPrompt`` gives you one. It already knows about the view it's in, so
    /// there's nothing to pass to it.
    ///
    /// It only does what a person asked for. If they do none of the three, nothing changes, and the prompt stays where it is.
    @MainActor
    struct Flow {
        
        /// Describes the prompt this flow acts on
        private let descriptor: MonetizationPrompt.Descriptor
        
        /// Where this prompt's state is kept. It's `nil` only when the prompt's App Group can't be opened, and then the
        /// prompt was never on screen for anyone to act on it.
        private let store: PromptStore?
        
        /// The environment of the view which shows the prompt. Actions use it to do things which only SwiftUI can do
        /// correctly, like presenting a purchase sheet in the right window.
        private let environment: EnvironmentValues
        
        /// Whether the prompt is on screen. This flow turns it off when a person is done with the prompt.
        private let isShowing: Binding<Bool>
        
        /// Whether a presentation is currently running. A prompt owns this, since a flow is remade each time the
        /// prompt's view is, so this is what lets a double tap start only one purchase.
        private let isPresenting: Binding<Bool>
        
        /// The status message shown in place of the prompt's content, or `nil` to show the content
        private let statusMessage: Binding<PromptStatusMessage?>
        
        /// Keeps attempts and checks for this prompt to one at a time, and spaces checks apart
        private let limiter: PendingCheckLimiter
        
        
        /// Makes the flow for one prompt.
        ///
        /// - Parameters:
        ///   - descriptor:    Describes the prompt this flow acts on
        ///   - store:         Where this prompt's state is kept
        ///   - environment:   The environment of the view which shows the prompt
        ///   - isShowing:     Whether the prompt is on screen
        ///   - isPresenting:  Whether a presentation is currently running
        ///   - statusMessage: The status message shown in place of the prompt's content, or `nil` to show the content
        ///   - limiter:       Keeps attempts and checks for this prompt to one at a time, and spaces checks apart
        internal init(descriptor: MonetizationPrompt.Descriptor,
                      store: PromptStore?,
                      environment: EnvironmentValues,
                      isShowing: Binding<Bool>,
                      isPresenting: Binding<Bool>,
                      statusMessage: Binding<PromptStatusMessage?>,
                      limiter: PendingCheckLimiter) {
            self.descriptor = descriptor
            self.store = store
            self.environment = environment
            self.isShowing = isShowing
            self.isPresenting = isPresenting
            self.statusMessage = statusMessage
            self.limiter = limiter
        }
    }
}



// MARK: - What a person can do

public extension MonetizationPrompt.Flow {
    
    /// Gives the person what the prompt offers, like a purchase sheet.
    ///
    /// Call this from the button they tap to accept. It's `async`, so call it from a `Task`, or call the non-throwing
    /// version of this instead if the caller doesn't need to react to failure. It returns once they've finished with
    /// whatever it showed, or once whatever it's waiting on has been recorded.
    ///
    /// - If they complete it, the prompt goes away and never shows again.
    /// - If it's still waiting on something else, like a parent's approval, the prompt's content is replaced by a short
    ///   status message. On later appearances the prompt is hidden, and the package keeps asking the action for the
    ///   result. A success retires the prompt. A failure, or the package giving up waiting, makes it come back later.
    /// - If they back out, nothing changes and the prompt stays on screen.
    /// - If it throws, nothing changes and the prompt stays on screen. Show the error if you like; what it is depends on
    ///   the prompt's action.
    ///
    /// Calling this while a previous call, or a check for the same prompt, is still running does nothing, so a double tap
    /// can't start two purchases.
    func present() async throws {
        try await performPresent()
    }
    
    
    /// Gives the person what the prompt offers, without `Task` or `try` at the call site.
    ///
    /// Starts the same work as the throwing version and returns immediately without waiting for it. A failure is logged
    /// as a warning and otherwise dropped; use the throwing version instead if the caller needs to know when something
    /// goes wrong.
    func present() {
        Task {
            do {
                try await performPresent()
            }
            catch {
                log(warning: "A monetization prompt's action failed: \(error)")
            }
        }
    }
    
    
    /// Hides the prompt for now, and starts a new wait of one full interval before it can show again.
    ///
    /// Call this from the button they tap to say "later".
    func snooze() {
        store?.snooze(descriptor)
        isShowing.wrappedValue = false
    }
    
    
    /// Hides the prompt for good. It never shows again, in any app which shares its scope.
    ///
    /// Call this from the button they tap to say "never".
    func decline() {
        retireAndHide()
    }
    
    
    #if DEBUG
    /// Erases this prompt's stored state, so its next check behaves like the first one after a fresh install. It also
    /// clears the spacing between checks for this prompt.
    ///
    /// It doesn't hide the prompt. Call it from a button, not directly in the prompt's content, since content is built
    /// again each time the view updates.
    ///
    /// This exists only in debug builds. Code which uses it has to be wrapped in `#if DEBUG`, so it can't reach a
    /// release build by accident.
    func reset() {
        store?.reset(descriptor.identifier)
        limiter.forget(limiterKey)
    }
    #endif
}



// MARK: - Pending attempts

internal extension MonetizationPrompt.Flow {
    
    /// Asks the action for the result of a pending attempt, and records what it says. Does nothing if an attempt or a
    /// check for this prompt is running, or the last check was too recent.
    func checkPending() async {
        let key = limiterKey
        guard limiter.begin(key, at: .now, isCheck: true) else {
            return
        }
        
        defer { limiter.end(key, at: .now, isCheck: true) }
        
        let outcome = await descriptor.action.checkPending(id: descriptor.identifier)
        
        guard let store,
              case .some(.success(.pending(interval: let interval, since: let since))) = store.lookUpState(for: descriptor.identifier)
        else {
            return
        }
        
        switch outcome {
        case .succeeded:
            await recordSuccess()
            
        case .abandoned:
            store.update(descriptor.identifier) { $0.givingUp(at: .now) }
            
        case .pending:
            let giveUpDate = interval.giveUpDate(
                since: since,
                maxDuration: descriptor.action.maxTimeToCheckPendingTransactions(whenPromptAppears: interval),
                spacing: PendingCheckLimiter.spacing
            )
            
            if giveUpDate <= .now {
                store.update(descriptor.identifier) { $0.givingUp(at: .now) }
            }
        }
    }
    
    
    /// Finishes recording a success which was interrupted: calls the action's `acknowledgeSuccess`, then stores `.done`.
    func finishResolving() async {
        let key = limiterKey
        guard limiter.begin(key, at: .now, isCheck: false) else {
            return
        }
        
        defer { limiter.end(key, at: .now, isCheck: false) }
        
        guard let store,
              case .some(.success(.resolving)) = store.lookUpState(for: descriptor.identifier)
        else {
            return
        }
        
        await descriptor.action.acknowledgeSuccess(id: descriptor.identifier)
        store.retire(descriptor.identifier)
    }
}



// MARK: - Presenting and retiring

private extension MonetizationPrompt.Flow {
    
    /// This prompt's key in the limiter
    var limiterKey: String {
        PendingCheckLimiter.key(for: descriptor.identifier, scope: descriptor.scope)
    }
    
    
    /// The one implementation behind both versions of `present()`
    func performPresent() async throws {
        guard !isPresenting.wrappedValue else {
            return
        }
        
        let key = limiterKey
        guard limiter.begin(key, at: .now, isCheck: false) else {
            return
        }
        
        isPresenting.wrappedValue = true
        
        let outcome: MonetizationPrompt.ActionOutcome
        do {
            outcome = try await attempt()
        }
        catch {
            endAttempt(key)
            throw error
        }
        
        endAttempt(key)
        
        if MonetizationPrompt.ActionOutcome.pending == outcome {
            Task {
                await checkPending()
            }
        }
    }
    
    
    /// Runs one attempt: stores that it's pending, runs the action, and records what the action reported.
    ///
    /// - Returns: What the action reported
    /// - Throws: Whatever the action threw, after putting the prompt back to due
    func attempt() async throws -> MonetizationPrompt.ActionOutcome {
        store?.update(descriptor.identifier) { $0.startingAttempt(declaring: descriptor.interval, at: .now) }
        
        let outcome: MonetizationPrompt.ActionOutcome
        do {
            outcome = try await descriptor.action.perform(id: descriptor.identifier, in: environment)
        }
        catch {
            store?.update(descriptor.identifier) { $0.cancellingAttempt(at: .now) }
            throw error
        }
        
        switch outcome {
        case .succeeded:
            await recordSuccess()
            
        case .pending:
            statusMessage.wrappedValue = .pending
            
        case .abandoned:
            store?.update(descriptor.identifier) { $0.cancellingAttempt(at: .now) }
        }
        
        return outcome
    }
    
    
    /// Ends an attempt which ``performPresent()`` started
    ///
    /// - Parameter key: This prompt's key in the limiter
    func endAttempt(_ key: String) {
        isPresenting.wrappedValue = false
        limiter.end(key, at: .now, isCheck: false)
    }
    
    
    /// Records a success: stores `.resolving`, calls the action's `acknowledgeSuccess`, stores `.done`, then hides the
    /// prompt. If the pending status message is on screen, it shows the completed message instead of hiding.
    func recordSuccess() async {
        store?.update(descriptor.identifier) { $0.recordingSuccess() }
        await descriptor.action.acknowledgeSuccess(id: descriptor.identifier)
        store?.retire(descriptor.identifier)
        
        if PromptStatusMessage.pending == statusMessage.wrappedValue {
            statusMessage.wrappedValue = .completed
        }
        else {
            isShowing.wrappedValue = false
        }
    }
    
    
    /// Ends this prompt for good: it's remembered as done, and it leaves the screen. A declined prompt and a fulfilled
    /// one end the same way.
    func retireAndHide() {
        store?.retire(descriptor.identifier)
        isShowing.wrappedValue = false
    }
}
