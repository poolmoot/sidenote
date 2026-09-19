import SwiftUI

/// The notch's motion vocabulary, gathered in one place so every part of it moves like a single
/// object rather than a collection of independently-tuned animations.
public enum NotchMotion {
    /// Folding open and closing back up: just shy of bouncy, settling in one soft overshoot.
    public static let unfold = Animation.spring(response: 0.42, dampingFraction: 0.78)
    /// Content arriving once the shape has already started to open.
    public static let contents = Animation.spring(response: 0.36, dampingFraction: 0.82)
    /// Swapping content inside something that is already mid-motion.
    public static let crossfade = Animation.easeInOut(duration: 0.16)
}
