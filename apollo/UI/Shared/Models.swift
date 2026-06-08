
import SwiftUI

// MARK: - Lightweight Page Models
enum IslandPage: Int, CaseIterable, Identifiable {
    case clipboard = 0
    case jot = 1
    case box = 2
    case chrono = 3
    case calendar = 4
    case launcher = 5
    case bookmarks = 6
    case customCombined = 7

    var id: Int { rawValue }
}

enum TitleAlignmentOption: Int, CaseIterable {
    case left = 0
    case right = 1

    var label: String {
        switch self {
        case .left: return "Left"
        case .right: return "Right"
        }
    }

    var alignment: Alignment {
        switch self {
        case .left: return .leading
        case .right: return .trailing
        }
    }
}

enum ClipboardActionOption: Int, CaseIterable {
    case copy = 0
    case paste = 1

    var label: String {
        switch self {
        case .copy: return "Copy to clipboard"
        case .paste: return "Paste at cursor"
        }
    }
}

enum HoverPreviewFocus {
    case all
    case islandSize
    case notchEdge
    case approach
    case clipboardLimit
    case titleSize
    case cornerRadius
    case sensitivityCarousel
    case sensitivityClose
    case animationNotch
    case animationCarousel
    case animationSwipe
    case delayApproach
    case delayHoverClose
    case delaySwipeClose
}
