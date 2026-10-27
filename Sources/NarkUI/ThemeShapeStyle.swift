import SwiftTUI

/// A semantic paint resolved by SwiftTUI against the terminal's active theme.
/// Explicit light and dark paints are available for previews and local overrides.
public struct ThemeShapeStyle: ShapeStyle, Equatable {

    private enum Appearance {
        case automatic
        case light
        case dark
    }

    private let role: SemanticStyleRole
    private let appearance: Appearance

    private init(_ role: SemanticStyleRole = .foreground, appearance: Appearance = .automatic) {
        self.role = role
        self.appearance = appearance
    }

    public var foreground: Self {
        paint(.foreground)
    }

    public var background: Self {
        paint(.background)
    }

    public var tint: Self {
        paint(.tint)
    }

    public var separator: Self {
        paint(.separator)
    }

    public var selection: Self {
        paint(.selection)
    }

    public var placeholder: Self {
        paint(.placeholder)
    }

    public var link: Self {
        paint(.link)
    }

    public var fill: Self {
        paint(.fill)
    }

    public var windowBackground: Self {
        paint(.windowBackground)
    }

    public var success: Self {
        paint(.success)
    }

    public var warning: Self {
        paint(.warning)
    }

    public var danger: Self {
        paint(.danger)
    }

    public var info: Self {
        paint(.info)
    }

    public var muted: Self {
        paint(.muted)
    }

    public var upload: Self {
        info
    }

    public var download: Self {
        link
    }

    public func eraseToAnyShapeStyle() -> AnyShapeStyle {
        switch appearance {
            case .automatic:
                .semantic(role)
            case .light:
                Theme.light.style(for: role)
            case .dark:
                Theme.dark.style(for: role)
        }
    }

    private func paint(_ role: SemanticStyleRole) -> Self {
        Self(role, appearance: appearance)
    }

    public static let automatic = Self()
    public static let light = Self(appearance: .light)
    public static let dark = Self(appearance: .dark)
}

public extension ShapeStyle where Self == ThemeShapeStyle {

    static var theme: Self {
        .automatic
    }

    static var light: Self {
        ThemeShapeStyle.light
    }

    static var dark: Self {
        ThemeShapeStyle.dark
    }
}

public extension Theme {

    static let light = Theme(
        foreground: Color(hexRGB: 0x1c2c3a),
        background: Color(hexRGB: 0xf4f6f8),
        tint: Color(hexRGB: 0x007787),
        separator: Color(hexRGB: 0x6e7d88),
        selection: Color(hexRGB: 0xd5e5ee),
        placeholder: Color(hexRGB: 0x566773),
        link: Color(hexRGB: 0x0062a8),
        fill: Color(hexRGB: 0xe5ebf0),
        windowBackground: Color(hexRGB: 0xf4f6f8),
        success: Color(hexRGB: 0x226b37),
        warning: Color(hexRGB: 0x7c5700),
        danger: Color(hexRGB: 0xb02b32),
        info: Color(hexRGB: 0x6f359b),
        muted: Color(hexRGB: 0x566773)
    )

    static let dark = Theme(
        foreground: Color(hexRGB: 0xd8e6eb),
        background: Color(hexRGB: 0x101820),
        tint: Color(hexRGB: 0x61d6df),
        separator: Color(hexRGB: 0x8196a3),
        selection: Color(hexRGB: 0x344955),
        placeholder: Color(hexRGB: 0x8196a3),
        link: Color(hexRGB: 0x61b6ff),
        fill: Color(hexRGB: 0x263b48),
        windowBackground: Color(hexRGB: 0x101820),
        success: Color(hexRGB: 0x99d78c),
        warning: Color(hexRGB: 0xe9c46a),
        danger: Color(hexRGB: 0xf08080),
        info: Color(hexRGB: 0xd28af2),
        muted: Color(hexRGB: 0x8196a3)
    )
}
