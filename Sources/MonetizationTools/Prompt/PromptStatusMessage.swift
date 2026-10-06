//
//  PromptStatusMessage.swift
//  MonetizationTools
//
//  Created by Ky directing Claude Opus 5.5 on 2026-10-01.
//

import Foundation



/// A short message which a prompt shows in place of its content, after an attempt is pending or once it completes
internal enum PromptStatusMessage: Sendable, Hashable {
    
    /// The attempt started, and is waiting on something outside this package, such as a parent's approval
    case pending
    
    /// The attempt which was pending has completed
    case completed
}



internal extension PromptStatusMessage {
    
    /// The localized text of this message
    var text: LocalizedStringResource {
        switch self {
        case .pending:
            return .pendingStatus
            
        case .completed:
            return .completedStatus
        }
    }
}



// MARK: - Localization

internal extension LocalizedStringResource.BundleDescription {
    
    /// This package's own bundle, for looking up its translations
    static let module: LocalizedStringResource.BundleDescription = .atURL(Bundle.module.bundleURL)
}



internal extension LocalizedStringResource {
    
    /// Shown in place of a prompt after the person asked to buy something which needs approval first
    static var pendingStatus: LocalizedStringResource {
        LocalizedStringResource(
            "status.pending",
            defaultValue: "Thank you. Your purchase request has been sent and is awaiting approval.",
            bundle: .module,
            comment: "Shown in place of a prompt after the person asked to buy something which needs approval first, such as a parent approving an Ask to Buy request."
        )
    }
    
    
    /// Shown in place of a pending status message once the purchase completes
    static var completedStatus: LocalizedStringResource {
        LocalizedStringResource(
            "status.completed",
            defaultValue: "Thank you. Your purchase is complete.",
            bundle: .module,
            comment: "Shown in place of the previous message once the purchase is complete. Keep it no longer than the previous message."
        )
    }
}
