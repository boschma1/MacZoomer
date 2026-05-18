import AppKit

/// Set of colors the user can pick during drawing, mapped from the ZoomIt
/// palette (R G B Y O P). Each color has an opaque "pen" variant and a
/// translucent "highlight" variant accessed via Shift+letter.
public enum PenColor: String, CaseIterable, Codable, Sendable {
    case red
    case green
    case blue
    case yellow
    case orange
    case pink

    public var displayName: String {
        rawValue.capitalized
    }

    /// Single-character keyboard shortcut that selects this color.
    public var shortcutCharacter: Character {
        switch self {
        case .red:    return "r"
        case .green:  return "g"
        case .blue:   return "b"
        case .yellow: return "y"
        case .orange: return "o"
        case .pink:   return "p"
        }
    }

    public var nsColor: NSColor {
        switch self {
        case .red:    return NSColor(srgbRed: 0.95, green: 0.20, blue: 0.20, alpha: 1.0)
        case .green:  return NSColor(srgbRed: 0.20, green: 0.75, blue: 0.30, alpha: 1.0)
        case .blue:   return NSColor(srgbRed: 0.20, green: 0.50, blue: 0.95, alpha: 1.0)
        case .yellow: return NSColor(srgbRed: 0.98, green: 0.83, blue: 0.20, alpha: 1.0)
        case .orange: return NSColor(srgbRed: 0.98, green: 0.55, blue: 0.10, alpha: 1.0)
        case .pink:   return NSColor(srgbRed: 0.96, green: 0.40, blue: 0.65, alpha: 1.0)
        }
    }
}

/// Drawing style: which color, how thick, and whether it's a translucent
/// highlight pen.
public struct PenStyle: Equatable, Sendable {
    public let color: PenColor
    public let width: CGFloat
    public let isHighlight: Bool

    public init(color: PenColor, width: CGFloat, isHighlight: Bool = false) {
        self.color = color
        self.width = width
        self.isHighlight = isHighlight
    }

    public var renderingColor: NSColor {
        let base = color.nsColor
        return isHighlight ? base.withAlphaComponent(0.35) : base
    }

    public var renderingWidth: CGFloat {
        isHighlight ? max(width * 2.5, 8) : width
    }
}

public extension PenStyle {
    static let defaultWidth: CGFloat = 4.0
    static let minWidth: CGFloat = 1.0
    static let maxWidth: CGFloat = 48.0
    static let widthStep: CGFloat = 1.0
}
