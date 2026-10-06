//
//  MonetizationPrompt + Debug.swift
//  MonetizationTools
//
//  Created by Ky directing Claude Opus 5 on 2026-09-21.
//

#if DEBUG
import SwiftUI



public extension MonetizationPrompt {
    
    /// Something about a ``MonetizationPrompt`` which can be watched and controlled while developing, with
    /// ``MonetizationPrompt/debug(monetizationPrompt:_:)``.
    ///
    /// This exists only in debug builds. Code which uses it has to be wrapped in `#if DEBUG`, so it can't reach a release
    /// build by accident.
    ///
    /// - Parameter Debuggable: The type of the value being watched and controlled
    struct DebugAspect<Debuggable> {
        
        /// Where the dev's binding for this aspect is kept in the environment
        fileprivate let keyPath: WritableKeyPath<EnvironmentValues, Binding<Debuggable>?>
        
        
        /// Makes an aspect which keeps its binding at the given place in the environment
        ///
        /// - Parameter keyPath: Where the dev's binding for this aspect is kept
        fileprivate init(keyPath: WritableKeyPath<EnvironmentValues, Binding<Debuggable>?>) {
            self.keyPath = keyPath
        }
    }
}



public extension MonetizationPrompt.DebugAspect where Debuggable == Bool {
    
    /// Whether the prompt is on screen.
    ///
    /// Setting the bound value shows or hides the prompt right now, without changing its stored state. The bound
    /// value also follows the prompt: it changes whenever the prompt shows or hides for a real reason. Each time the
    /// prompt's view appears, it's set to what the real schedule says.
    static var isShowing: Self {
        Self(keyPath: \.monetizationPromptDebugIsShowing)
    }
}



public extension MonetizationPrompt {
    
    /// Binds something about this prompt to your own value, both ways, while developing.
    ///
    /// ```swift
    /// MonetizationPrompt(for: .licensePurchase) { flow in
    ///     // …
    /// }
    /// #if DEBUG
    /// .debug(monetizationPrompt: .isShowing, $isShowingPrompt)
    /// #endif
    /// ```
    ///
    /// This exists only in debug builds. Code which uses it has to be wrapped in `#if DEBUG`, so it can't reach a
    /// release build by accident.
    ///
    /// - Parameters:
    ///   - aspect:     What to watch and control, like ``MonetizationPrompt/DebugAspect/isShowing``
    ///   - debuggable: Your value, which controls the aspect and follows it
    func debug<Debuggable>(monetizationPrompt aspect: DebugAspect<Debuggable>,
                           _ debuggable: Binding<Debuggable>)
    -> some View {
        environment(aspect.keyPath, debuggable)
    }
}



internal extension EnvironmentValues {
    
    /// The dev's binding for ``MonetizationPrompt/DebugAspect/isShowing``, or `nil` when none is attached.
    ///
    /// Only ``MonetizationPrompt/debug(monetizationPrompt:_:)`` sets this, and that only exists on `MonetizationPrompt`
    /// itself, so it can't be set on a whole screen. It reaches the prompt it's called on, plus any prompt nested inside
    /// that prompt's own content.
    @Entry var monetizationPromptDebugIsShowing: Binding<Bool>? = nil
}
#endif
