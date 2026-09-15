//
//  MonetizationPromptScope.swift
//  MonetizationTools
//
//  Created by Ky on 2026-09-14.
//

import Foundation



/// How far a prompt's history reaches: just this app, or every app sharing an App Group.
public enum MonetizationPromptScope: Sendable, Hashable {
    
    /// This prompt's history lives in this app alone. Declining it here has no effect on any other app.
    case perApp
    
    /// This prompt's history is shared with every app in the given App Group, so declining it in one app declines it
    /// everywhere. Good for a family-wide ask, where a suite of apps collectively nagging harder than any one of them
    /// would is the thing to avoid.
    ///
    /// - Parameter identifier: The App Group identifier, e.g. `"group.org.bhstudios.deadassSimple"`. This has to be a
    ///                         group your app actually holds an entitlement for, or the shared store silently isn't
    ///                         shared.
    case appGroup(_ identifier: String)
}



internal extension MonetizationPromptScope {
    
    /// The user defaults which back this scope, or the standard ones if the App Group isn't available to this app
    var userDefaults: UserDefaults {
        switch self {
        case .perApp:
            .standard
            
        case .appGroup(let identifier):
            UserDefaults(suiteName: identifier) ?? .standard
        }
    }
}
