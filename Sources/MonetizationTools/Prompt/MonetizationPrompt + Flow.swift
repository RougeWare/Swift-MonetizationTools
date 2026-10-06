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
    /// Every button in a prompt calls **one** of these three:
    ///
    /// - ``present()`` when they want what the prompt offers
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
        
        /// Whether the prompt's controls should reject user input (e.g. the user just tapped "pay", so disable them all to avoid double-taps or accidental dismissal)
        private let disablePrompt: Binding<Bool>
        
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
        ///   - disablePrompt: Whether the prompt's controls should reject user input (e.g. the user just tapped "pay", so disable them all to avoid double-taps or accidental dismissal)
        ///   - isPresenting:  Whether a presentation is currently running
        ///   - statusMessage: The status message shown in place of the prompt's content, or `nil` to show the content
        ///   - limiter:       Keeps attempts and checks for this prompt to one at a time, and spaces checks apart
        internal init(
            descriptor: MonetizationPrompt.Descriptor,
            store: PromptStore?,
            environment: EnvironmentValues,
            isShowing: Binding<Bool>,
            disablePrompt: Binding<Bool>,
            isPresenting: Binding<Bool>,
            statusMessage: Binding<PromptStatusMessage?>,
            limiter: PendingCheckLimiter,
        ) {
            self.descriptor = descriptor
            self.store = store
            self.environment = environment
            self.isShowing = isShowing
            self.isPresenting = isPresenting
            self.disablePrompt = disablePrompt
            self.statusMessage = statusMessage
            self.limiter = limiter
        }
    }
}



// MARK: - API

public extension MonetizationPrompt.Flow {
    
    /// The user indicated they want to pay.
    ///
    /// This presents the user-facing payment flow, like a purchase sheet.
    ///
    /// Call this from your button which they tap to proceed with the payment.
    /// It returns once the user is finished with the payment flow.
    ///
    /// If you want to ignore payment errors, you may omit `try await` from the call. Otherwise, you must `await` this so that any late-stage errors are reported.
    ///
    /// If an error occurs which prevents a successful payment, nothing changes and the prompt stays on screen. The exact error depends on the payment handler you choose for the prompt's description. You may reflect the error in your UI if you like.
    ///
    /// Calling this while a previous call (or a check for the same prompt) is still running does nothing, so a double tap can't start two purchases.
    func present() async throws {
        try await performPresent()
    }
    
    
    /// The user indicated they want to pay.
    ///
    /// This presents the user-facing payment flow, like a purchase sheet.
    ///
    /// Call this from your button which they tap to proceed with the payment.
    /// It returns once the user is finished with the payment flow.
    ///
    /// If you want to ignore payment errors, you may omit `try await` from the call. Otherwise, you must `await` this so that any late-stage errors are reported.
    ///
    /// If an error occurs which prevents a successful payment, nothing changes and the prompt stays on screen. The exact error depends on the payment handler you choose for the prompt's description. You may reflect the error in your UI if you like.
    ///
    /// Calling this while a previous call (or a check for the same prompt) is still running does nothing, so a double tap can't start two purchases.
    func present() {
        Task {
            do {
                try await performPresent()
            }
            catch {
                log(warning: "A monetization prompt's payment handler failed: \(error)")
            }
        }
    }
    
    
    /// Hides the prompt for now
    ///
    /// After one full interval, the prompt will appear again when appropriate. See ``MonetizationPrompt/Descriptor/interval`` for details.
    ///
    /// Call this from the button the user taps to say "later"/"dismiss".
    func snooze() {
        store?.snooze(descriptor)
        isShowing.wrappedValue = false
    }
    
    
    /// Hides the prompt forever. It never shows again, in any app in-scope.
    ///
    /// Call this from the button they tap to say "never ask me again".
    func decline() {
        retireAndHide()
    }
    
    
    #if DEBUG
    /// Permanently deletes this prompt's stored state, so it behaves like a fresh install.
    ///
    /// Call this from a button in the prompt's UI, just like the other methods.
    ///
    /// - Note: This doesn't hide the prompt; the prompt will behave identical to how it would at first-launch.
    ///
    /// - Note: This exists only for debugging during development.
    func reset() {
        store?.reset(descriptor.identifier)
        limiter.forget(limiterKey)
    }
    #endif
}



// MARK: - Pending attempts

internal extension MonetizationPrompt.Flow {
    
    /// Checks with the payment handler to see how a pending payment is going.
    ///
    /// If another check for this flow's identifier is already running, or ran recently, then this returns immediately without doing anything.
    func checkPending() async {
        let key = limiterKey
        guard limiter.begin(key, at: .now, isCheck: true) else {
            return
        }
        
        defer { limiter.end(key, at: .now, isCheck: true) }
        
        let outcome = await descriptor.paymentHandler.checkPending(id: descriptor.identifier)
        
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
                maxDuration: descriptor.paymentHandler.maxTimeToCheckPendingTransactions(whenPromptAppears: interval),
                spacing: PendingCheckLimiter.spacing
            )
            
            if giveUpDate <= .now {
                store.update(descriptor.identifier) { $0.givingUp(at: .now) }
            }
        }
    }
    
    
    /// Finishes recording a success which was interrupted: calls the payment handler's `handleSuccess`, then stores `.done`.
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
        
        await descriptor.paymentHandler.handleSuccess(id: descriptor.identifier)
        store.retire(descriptor.identifier)
    }
}



// MARK: - Presenting and retiring

private extension MonetizationPrompt.Flow {
    
    /// Allows the limiter to uniquely identify this flow
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
        
        let outcome: PaymentOutcome
        do {
            outcome = try await launchPaymentHandler()
        }
        catch {
            endAttempt(key)
            throw error
        }
        
        endAttempt(key)
        
        if PaymentOutcome.pending == outcome {
            Task {
                await checkPending()
            }
        }
    }
    
    
    /// Launches the payment handler.
    ///
    /// This first records a prompt state noting that an attempt is starting, then tells the handler to launch. This way crashes don't put the user in an unexpected state. See ``PersistedPromptState/startingAttempt(declaring:at:)`` for more detail.
    ///
    /// - Returns: What the payment handler reported
    /// - Throws: Whatever the payment handler threw, after putting the prompt back to due
    func launchPaymentHandler() async throws -> PaymentOutcome {
        store?.update(descriptor.identifier) { $0.startingAttempt(declaring: descriptor.interval, at: .now) }
        
        let outcome: PaymentOutcome
        do {
            outcome = try await descriptor.paymentHandler.launch(id: descriptor.identifier, in: environment)
        }
        catch {
            store?.update(descriptor.identifier) { $0.cancellingAttempt(at: .now) }
            throw error
        }
        
        switch outcome {
        case .succeeded:
            await recordSuccess()
            
        case .pending:
            store?.update(descriptor.identifier) { _ in .pending(interval: descriptor.interval, since: .now) }
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
    
    
    /// Records a success: stores `.resolving`, calls the payment handler's `handleSuccess`, stores `.done`, then hides the
    /// prompt. If the pending status message is on screen, it shows the completed message instead of hiding.
    func recordSuccess() async {
        store?.update(descriptor.identifier) { $0.recordingSuccess() }
        await descriptor.paymentHandler.handleSuccess(id: descriptor.identifier)
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
