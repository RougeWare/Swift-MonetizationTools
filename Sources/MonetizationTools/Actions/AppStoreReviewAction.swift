//
//  AppStoreReviewAction.swift
//  MonetizationTools
//
//  Created by Ky directing Claude Opus 5 on 2026-09-14.
//

import Foundation
import StoreKit

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif



/// Asks the system to present its review-request prompt.
///
/// Use this when a prompt's offer is "please review the app" rather than a purchase. Apple never reports whether a
/// review was actually left, so this package can't either — having asked is treated as the whole job, and the
/// prompt retires either way.
public struct AppStoreReviewAction: MonetizationPromptAction {
    
    #if canImport(UIKit) && !os(watchOS)
    /// Where to present the review request. `nil` means "figure out the active scene automatically."
    ///
    /// Override this only if your app needs a specific scene — a specific window in a multi-window app, for
    /// instance. Most apps can leave this as `nil`.
    private let scene: (@MainActor () -> UIWindowScene?)?
    
    
    /// - Parameter scene: _optional_ - Where to present the review request. Defaults to `nil`, meaning "find the
    ///                    active scene automatically." Override this only if your app needs a specific scene.
    public init(scene: (@MainActor () -> UIWindowScene?)? = nil) {
        self.scene = scene
    }
    
    #elseif canImport(AppKit)
    /// Where to present the review request. `nil` means "figure out the active window's view controller
    /// automatically."
    ///
    /// Override this only if your app needs a specific view controller — a specific window in a multi-window app,
    /// or an app with no visible window at all. Most apps can leave this as `nil`.
    private let viewController: (@MainActor () -> NSViewController?)?
    
    
    /// - Parameter viewController: _optional_ - Where to present the review request. Defaults to `nil`, meaning
    ///                             "find the active window's view controller automatically." Override this only if
    ///                             your app needs a specific view controller — a specific window in a multi-window
    ///                             app, or an app with no visible window at all.
    public init(viewController: (@MainActor () -> NSViewController?)? = nil) {
        self.viewController = viewController
    }
    
    #else
    public init() {}
    #endif
    
    
    @MainActor
    public func perform(id identifier: MonetizationPromptIdentifier) async throws -> MonetizationPromptActionOutcome {
        #if canImport(UIKit) && !os(watchOS)
        guard let scene = scene?() ?? Self.activeScene else {
            return .abandoned
        }
        
        AppStore.requestReview(in: scene)
        return .succeeded
        
        #elseif canImport(AppKit)
        // There is no scene-less overload on macOS; a view controller is required, the same as a UIWindowScene is
        // required on iOS. https://developer.apple.com/forums/tags/storekit confirms this is Apple's own design, not
        // an oversight here, however inconvenient it is for windowless or menu-bar-only apps.
        guard let viewController = viewController?() ?? Self.activeViewController else {
            return .abandoned
        }
        
        AppStore.requestReview(in: viewController)
        return .succeeded
        
        #else
        return .abandoned
        #endif
    }
    
    
    #if canImport(UIKit) && !os(watchOS)
    /// The scene to present the review request in, if there is one and no override was given
    @MainActor
    private static var activeScene: UIWindowScene? {
        UIApplication.shared.connectedScenes
            .lazy
            .compactMap { $0 as? UIWindowScene }
            .first { .foregroundActive == $0.activationState }
    }
    
    #elseif canImport(AppKit)
    /// The view controller to present the review request in, if there is one and no override was given
    @MainActor
    private static var activeViewController: NSViewController? {
        (NSApplication.shared.keyWindow ?? NSApplication.shared.mainWindow)?.contentViewController
    }
    #endif
}



public extension MonetizationPromptAction where Self == AppStoreReviewAction {
    
    /// Asks the system to present its review-request prompt
    static var appStoreReview: Self { .init() }
}
