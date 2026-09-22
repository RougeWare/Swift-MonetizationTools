//
//  MonetizationPromptScope.swift
//  MonetizationTools
//
//  Created by Ky directing Claude Sonnet 5 on 2026-09-20.
//

import Foundation



/// How far one monetization prompt's memory reaches: this app alone, or every app in an App Group.
///
/// Sharing across a family of apps means declining a prompt in one app declines it in all of them, so a suite can't
/// collectively nag harder than any one of its members would.
///
/// On macOS, an app distributed outside the Mac App Store should name its group with its Team ID as the prefix (like
/// `"ABCDE12345.org.example.apps"`) instead of `group.…`. Otherwise macOS 15 and later can show the person an alert
/// saying the app "would like to access data from other apps", which this package can neither detect nor prevent.
public enum MonetizationPromptScope: Sendable, Hashable {
    
    /// This prompt's history is kept for this app alone. Nothing needs to be set up for this.
    case perApp
    
    /// This prompt's history is kept in an App Group's shared defaults, so every app in the group agrees about it.
    ///
    /// Every app which shares the prompt must declare the same group in its entitlements, and use the same prompt
    /// identifier. If the group's defaults can't be opened, the prompt never shows, since falling back to this app's
    /// own history would let a suite nag harder than one app could.
    ///
    /// - Parameter id: The App Group's identifier, exactly as it's written in the entitlements. Never change it once
    ///                 shipped, since everyone who already declined would be asked again.
    case appGroup(id: String)
}



// MARK: - Storage

internal extension MonetizationPromptScope {
    
    /// The defaults database which holds the histories of every prompt in this scope.
    ///
    /// This is `nil` only when an App Group's defaults can't be opened. Nothing checks whether this app actually
    /// belongs to the group, so a group missing from the entitlements isn't caught here.
    var userDefaults: UserDefaults? {
        switch self {
        case .perApp:
            return .standard
            
        case .appGroup(id: let id):
            return UserDefaults(suiteName: id)
        }
    }
}
