import SwiftUI

enum Theme {
    // MARK: - Colors

    static let accent = Color.accentColor

    static let background = Color(.systemBackground)
    static let secondaryBackground = Color(.secondarySystemBackground)
    static let groupedBackground = Color(.systemGroupedBackground)
    static let tertiaryGroupedBackground = Color(.tertiarySystemGroupedBackground)

    static let label = Color(.label)
    static let secondaryLabel = Color(.secondaryLabel)
    static let tertiaryLabel = Color(.tertiaryLabel)
    static let separator = Color(.separator)

    static let statusGreen = Color(.systemGreen)
    static let statusRed = Color(.systemRed)
    static let statusOrange = Color(.systemOrange)

    // MARK: - Spacing (8pt grid)

    static let spacing4: CGFloat = 4
    static let spacing8: CGFloat = 8
    static let spacing12: CGFloat = 12
    static let spacing16: CGFloat = 16
    static let spacing20: CGFloat = 20
    static let spacing24: CGFloat = 24
    static let spacing32: CGFloat = 32

    // MARK: - Corner Radius

    static let cornerRadius: CGFloat = 12
    static let cornerRadiusSmall: CGFloat = 8
    static let cornerRadiusLarge: CGFloat = 16
}
