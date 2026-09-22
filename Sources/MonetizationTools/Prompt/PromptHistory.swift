//
//  PromptHistory.swift
//  MonetizationTools
//
//  Created by Ky directing Claude Sonnet 5 on 2026-09-20.
//

import Foundation



/// Everything one prompt remembers about how a person has treated it. This is all that's ever stored for a prompt.
///
/// It's a closed two-case type so the stored form stays tiny: someone who wants nothing to do with a prompt costs a few
/// bytes of storage, and can't be made to cost more.
///
/// The stored form is JSON. A retired prompt is exactly `{"done":true}`, which the README promises, so don't change
/// that form without changing what the README says.
internal enum PromptHistory: Sendable, Hashable {
    
    /// The prompt hasn't been retired. It's either waiting to become due, or it's due.
    ///
    /// - Parameters:
    ///   - interval:     How long this prompt waits before its first appearance, and again each time someone asks for
    ///                   it later. This is the value declared when the prompt was first ever checked, and it never
    ///                   changes afterward.
    ///   - nextEligible: The earliest moment at which this prompt is due
    case tracking(interval: PromptInterval, nextEligible: Date)
    
    /// The person declined this prompt or fulfilled it, so it never appears again
    case done
}



// MARK: - Codable

extension PromptHistory: Codable {
    
    /// The keys of the stored JSON. `done` alone marks a retired prompt; `interval` and `nextEligible` together mark a
    /// tracked one.
    private enum CodingKeys: String, CodingKey {
        case done
        case interval
        case nextEligible
    }
    
    
    /// Reads a stored history.
    ///
    /// Only the two shapes this type writes are accepted. That way a damaged record can never be mistaken for a valid
    /// one; it throws instead, and the caller decides what a broken record means.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        if container.contains(.done) {
            let isDone = try container.decode(Bool.self, forKey: .done)
            
            guard isDone else {
                throw DecodingError.dataCorruptedError(
                    forKey: .done,
                    in: container,
                    debugDescription: "A retired prompt's `done` must be `true`"
                )
            }
            
            self = .done
        }
        else {
            self = .tracking(
                interval: try container.decode(PromptInterval.self, forKey: .interval),
                nextEligible: try container.decode(Date.self, forKey: .nextEligible)
            )
        }
    }
    
    
    /// Writes the stored form. A retired prompt is written as `{"done":true}` and nothing else.
    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        switch self {
        case .tracking(interval: let interval, nextEligible: let nextEligible):
            try container.encode(interval, forKey: .interval)
            try container.encode(nextEligible, forKey: .nextEligible)
            
        case .done:
            try container.encode(true, forKey: .done)
        }
    }
}
