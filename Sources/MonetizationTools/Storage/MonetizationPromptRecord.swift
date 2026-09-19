//
//  MonetizationPromptRecord.swift
//  MonetizationTools
//
//  Created by Ky directing Claude Opus 5 on 2026-09-14.
//

import Foundation



/// Everything this package remembers about one prompt.
///
/// A prompt which will never be shown again needs no bookkeeping at all, so ``done`` deliberately carries none. It
/// encodes as `{"done":true}` and nothing else, so a person who never wanted any of this can't have their storage grow
/// beyond a handful of bytes per prompt they dismissed.
internal enum MonetizationPromptRecord: Sendable, Hashable {
    
    /// This prompt has been declined or fulfilled. It will never be shown again, and nothing further is worth knowing.
    case done
    
    /// This prompt is still live.
    ///
    /// - Parameters:
    ///   - interval:     The cadence, as it was the first time this prompt was ever checked. Locked from that moment
    ///                   on: later changes to the descriptor don't touch it, so nobody's cadence can be quietly
    ///                   ratcheted up by an app update.
    ///   - nextEligible: The earliest moment this prompt may appear again
    case tracking(interval: PromptInterval, nextEligible: Date)
}



// MARK: - Codable

/// ``done`` encodes as:
/// ```json
/// {"done":true}
/// ```
///
/// ``tracking(interval:nextEligible:)`` encodes as:
/// ```json
/// {"interval":"monthly","next":847972800}
/// ```
/// That number is `nextEligible` encoded the way `Date` always encodes without a custom strategy: seconds since the
/// Cocoa reference date of 2001-01-01, not the Unix epoch. It'll look unfamiliar next to a Unix timestamp; that's
/// expected, not a bug.
extension MonetizationPromptRecord: Codable {
    
    private enum CodingKeys: String, CodingKey {
        case done
        case interval
        case nextEligible = "next"
    }
    
    
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        if true == (try container.decodeIfPresent(Bool.self, forKey: .done)) {
            self = .done
        }
        else {
            self = .tracking(
                interval: try container.decode(PromptInterval.self, forKey: .interval),
                nextEligible: try container.decode(Date.self, forKey: .nextEligible)
            )
        }
    }
    
    
    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        switch self {
        case .done:
            try container.encode(true, forKey: .done)
            
        case .tracking(let interval, let nextEligible):
            try container.encode(interval, forKey: .interval)
            try container.encode(nextEligible, forKey: .nextEligible)
        }
    }
}
