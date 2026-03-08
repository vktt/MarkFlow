import Foundation

public struct RenderOptions: Sendable, Equatable {
    public enum Theme: String, Sendable {
        case system
        case light
        case dark
    }

    public var theme: Theme
    public var syntaxHighlighting: Bool
    public var softWrap: Bool
    public var smartTypography: Bool

    public init(
        theme: Theme = .system,
        syntaxHighlighting: Bool = true,
        softWrap: Bool = true,
        smartTypography: Bool = true
    ) {
        self.theme = theme
        self.syntaxHighlighting = syntaxHighlighting
        self.softWrap = softWrap
        self.smartTypography = smartTypography
    }
}
