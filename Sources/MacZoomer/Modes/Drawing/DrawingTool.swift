import Foundation

/// Which kind of mark a press-and-drag creates. Distinct from the underlying
/// shape constraint (line vs. rectangle, etc.) — `tool` is the *medium*, while
/// `ShapeConstraint` is the *shape*.
public enum DrawingTool: String, Sendable, Equatable {
    /// Standard colored pen (default). Shape comes from modifier keys.
    case ink
    /// Gaussian blur over the frozen background. No color; only width matters.
    case blur
    /// Click to place a caret, type to fill, Enter/Esc to commit.
    case text

    public var displayName: String {
        switch self {
        case .ink:  return "Pen"
        case .blur: return "Blur"
        case .text: return "Text"
        }
    }

    /// Single-character shortcut that selects this tool. Returns nil for the
    /// default (`.ink`) since selecting "back to pen" is "I" but you also get
    /// there implicitly by pressing a color key.
    public var shortcutCharacter: Character? {
        switch self {
        case .ink:  return "i"
        case .blur: return "b"
        case .text: return "t"
        }
    }
}
