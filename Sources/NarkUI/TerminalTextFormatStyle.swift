import Foundation

/// Formats terminal display text by removing Unicode control characters.
public struct TerminalTextFormatStyle: FormatStyle {

    public init() {}

    public func format(_ value: String) -> String {
        String(String.UnicodeScalarView(value.unicodeScalars.filter {
            !CharacterSet.controlCharacters.contains($0)
        }))
    }
}

public extension FormatStyle where Self == TerminalTextFormatStyle {

    static var terminalText: Self {
        .init()
    }
}
