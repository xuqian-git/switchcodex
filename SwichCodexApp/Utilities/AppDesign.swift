import SwiftUI

enum AppSpacing {
    static let xxs: CGFloat = 4
    static let xs: CGFloat = 8
    static let sm: CGFloat = 12
    static let md: CGFloat = 16
    static let lg: CGFloat = 20
    static let xl: CGFloat = 24
    static let xxl: CGFloat = 32
}

enum AppCornerRadius {
    static let shell: CGFloat = 24
    static let panel: CGFloat = 18
    static let card: CGFloat = 16
    static let compactCard: CGFloat = 14
    static let badge: CGFloat = 999
}

enum AppSemanticColor {
    static let accent = Color.accentColor
    static let success = Color.green
    static let warning = Color.orange
    static let danger = Color.red
    static let subtleBorder = Color.primary.opacity(0.08)
    static let elevatedFill = Color.primary.opacity(0.04)
    static let mutedFill = Color.primary.opacity(0.025)
}

struct AppPanelStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(.thinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: AppCornerRadius.panel, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: AppCornerRadius.panel, style: .continuous)
                    .strokeBorder(AppSemanticColor.subtleBorder)
            )
    }
}

extension View {
    func appPanelStyle() -> some View {
        modifier(AppPanelStyle())
    }
}
