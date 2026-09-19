import SwiftUI

/// Design tokens: color, radius, spacing, layout metrics.
enum Theme {
    /// The selected accent is persisted by SettingsManager. Reading it here
    /// keeps existing Theme.accent call sites in sync when the user changes
    /// the setting without requiring a broad view-by-view refactor.
    static var accent: Color { AppThemeColor.current.color }
    static var accentDeep: Color { AppThemeColor.current.deepColor }

    static var accentGradient: LinearGradient {
        let theme = AppThemeColor.current
        return LinearGradient(
            colors: [theme.gradientStart, theme.deepColor],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
    }

    enum Radius {
        static let badge: CGFloat = 4
        static let small: CGFloat = 6
        static let standard: CGFloat = 8
        static let large: CGFloat = 12
        static let panel: CGFloat = 20
    }

    enum Layout {
        static let contentInset: CGFloat = 24
        static let cardSize: CGFloat = 160
        /// Row height for a shelf of cover cards: artwork, then up to two lines
        /// of title and one of subtitle.
        static let coverShelfHeight: CGFloat = 226
        /// Row height for a shelf of artist cards: circular artwork, one name.
        static let artistShelfHeight: CGFloat = 196
        static let sidebarWidth: CGFloat = 220
        static let playerBarHeight: CGFloat = 56
        /// Gap between the floating player bar and the window's bottom edge.
        /// Must match the bar's own `.padding(.bottom,)` in PlayerBar.
        static let playerBarBottomMargin: CGFloat = 10
        /// Bottom inset pages need so scrolled content clears the floating bar.
        static var playerChromeClearance: CGFloat { playerBarHeight + playerBarBottomMargin }
        static let minWindowWidth: CGFloat = 1020
        /// Width the split view's divider occupies between the two columns.
        static let splitDividerWidth: CGFloat = 8
        /// Window minimum while the sidebar is collapsed. The window-wide
        /// minimum is a *content* constraint, so with the sidebar hidden it
        /// lands entirely on the detail column; restoring the sidebar would
        /// then add its width on top and `.contentMinSize` would widen the
        /// window every time the now-playing page is dismissed (#19).
        /// Subtracting the sidebar here keeps the restored total at
        /// `minWindowWidth`.
        static var minWindowWidthSidebarCollapsed: CGFloat {
            minWindowWidth - sidebarWidth - splitDividerWidth
        }
        static let minWindowHeight: CGFloat = 640
        static let defaultWindowWidth: CGFloat = 1200
        static let defaultWindowHeight: CGFloat = 780
    }
}

enum AppThemeColor: String, CaseIterable, Identifiable {
    case blue
    case red
    case purple
    case green
    case orange

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .blue: return String(localized: "蓝色")
        case .red: return String(localized: "红色")
        case .purple: return String(localized: "紫色")
        case .green: return String(localized: "绿色")
        case .orange: return String(localized: "橙色")
        }
    }

    /// The app's default theme. The blue value is intentionally kept as the
    /// exact user-requested #05348B color.
    static let defaultValue: Self = .blue

    static var current: Self {
        UserDefaults.standard.string(forKey: "settings.themeColor")
            .flatMap(Self.init(rawValue:)) ?? defaultValue
    }

    var color: Color {
        switch self {
        case .blue: return Color(red: 5 / 255, green: 52 / 255, blue: 139 / 255)
        case .red: return Color(red: 236 / 255, green: 73 / 255, blue: 73 / 255)
        case .purple: return Color(red: 124 / 255, green: 58 / 255, blue: 237 / 255)
        case .green: return Color(red: 22 / 255, green: 163 / 255, blue: 74 / 255)
        case .orange: return Color(red: 234 / 255, green: 88 / 255, blue: 12 / 255)
        }
    }

    var deepColor: Color {
        switch self {
        case .blue: return Color(red: 3 / 255, green: 29 / 255, blue: 83 / 255)
        case .red: return Color(red: 201 / 255, green: 41 / 255, blue: 41 / 255)
        case .purple: return Color(red: 91 / 255, green: 33 / 255, blue: 182 / 255)
        case .green: return Color(red: 15 / 255, green: 108 / 255, blue: 48 / 255)
        case .orange: return Color(red: 180 / 255, green: 50 / 255, blue: 8 / 255)
        }
    }

    var gradientStart: Color {
        switch self {
        case .blue: return Color(red: 28 / 255, green: 83 / 255, blue: 177 / 255)
        case .red: return Color(red: 248 / 255, green: 91 / 255, blue: 91 / 255)
        case .purple: return Color(red: 167 / 255, green: 109 / 255, blue: 255 / 255)
        case .green: return Color(red: 74 / 255, green: 196 / 255, blue: 111 / 255)
        case .orange: return Color(red: 255 / 255, green: 145 / 255, blue: 61 / 255)
        }
    }
}

/// Motion tokens (mirrors kaset's `AppAnimation`).
enum AppAnimation {
    static let quick = Animation.easeOut(duration: 0.15)
    static let standard = Animation.easeInOut(duration: 0.25)
    static let smooth = Animation.easeInOut(duration: 0.35)
    static let spring = Animation.spring(response: 0.35, dampingFraction: 0.7)
    static let bouncy = Animation.spring(response: 0.4, dampingFraction: 0.6)
    static let snappy = Animation.spring(response: 0.25, dampingFraction: 0.8)

    static let staggerDelay = 0.04
    static let maxStaggerDelay = 0.4

    static func stagger(for index: Int) -> Double {
        min(Double(index) * staggerDelay, maxStaggerDelay)
    }
}

extension View {
    /// `scrollClipDisabled` is iOS 17 / macOS 14; older systems clip normally.
    @ViewBuilder
    func compatScrollClipDisabled() -> some View {
        if #available(iOS 17.0, macOS 14.0, *) { scrollClipDisabled() } else { self }
    }

    /// Hides the toolbar background; `toolbarBackgroundVisibility` is
    /// macOS 15+/iOS 18+, so iOS 17 falls back to `toolbarBackground`.
    @ViewBuilder
    func compatHiddenToolbarBackground() -> some View {
        #if os(macOS)
        toolbarBackgroundVisibility(.hidden, for: .automatic)
        #else
        if #available(iOS 18.0, *) {
            toolbarBackgroundVisibility(.hidden, for: .automatic)
        } else {
            toolbarBackground(.hidden, for: .navigationBar)
        }
        #endif
    }

    /// Glass background with a graceful material fallback on macOS 15.
    @ViewBuilder
    func compatGlass(interactive: Bool = false, in shape: some Shape) -> some View {
        #if os(macOS)
        if #available(macOS 26.0, *) {
            self.glassEffect(interactive ? .regular.interactive() : .regular, in: shape)
        } else {
            self.background(.ultraThinMaterial, in: shape)
        }
        #elseif os(iOS)
        if #available(iOS 26.0, *) {
            self.glassEffect(interactive ? .regular.interactive() : .regular, in: shape)
        } else {
            self.background(.ultraThinMaterial, in: shape)
        }
        #else
        self.background(.ultraThinMaterial, in: shape)
        #endif
    }
}
