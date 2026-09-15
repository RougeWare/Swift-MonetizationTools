//
//  AppStoreReviewAction.swift
//  MonetizationTools
//
//  Created by Ky on 2026-09-14.
//

import Foundation
import StoreKit

#if canImport(UIKit)
import UIKit
#endif



/// Asks the system to present its review-request prompt.
///
/// Apple never reports whether a review was actually left, so there is nothing to distinguish. Having asked is treated
/// as the whole job, and the prompt retires either way.
public struct AppStoreReviewAction: MonetizationPromptAction {
    
    public init() {}
    
    
    @MainActor
    public func perform(for identifier: MonetizationPromptIdentifier) async throws -> MonetizationPromptActionOutcome {
        #if os(macOS)
        AppStore.requestReview()
        return .succeeded
        
        #elseif canImport(UIKit) && !os(watchOS)
        guard let scene = Self.activeScene else {
            return .notCompleted
        }
        
        AppStore.requestReview(in: scene)
        return .succeeded
        
        #else
        return .notCompleted
        #endif
    }
    
    
    #if canImport(UIKit) && !os(watchOS)
    /// The scene to present the review request in, if there is one
    @MainActor
    private static var activeScene: UIWindowScene? {
        UIApplication.shared.connectedScenes
            .lazy
            .compactMap { $0 as? UIWindowScene }
            .first { .foregroundActive == $0.activationState }
    }
    #endif
}



public extension MonetizationPromptAction where Self == AppStoreReviewAction {
    
    /// Asks the system to present its review-request prompt
    static var appStoreReview: Self { .init() }
}
