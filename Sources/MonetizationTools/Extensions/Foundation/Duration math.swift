//
//  Duration math.swift
//  MonetizationTools
//
//  Created by Ky on 2026-10-05.
//

import Foundation



internal extension Duration {
    
    /// Negates the duration
    static prefix func - (rhs: Self) -> Self {
        if #available(
            macOS 15,
            iOS 18,
            tvOS 18,
            watchOS 11,
            visionOS 2,
            *)
        {
            return .init(attoseconds: -rhs.attoseconds)
        }
        else {
            let (seconds, attoseconds) = rhs.components
            return .init(secondsComponent: -seconds, attosecondsComponent: attoseconds)
        }
    }
    
    
    /// Infinite duration
    ///
    /// This encodes the maximum positive duration (~20x the age of the universe at time of writing)
    static var infinity: Self {
        return .init(secondsComponent: .max, attosecondsComponent: .max)
    }
}
