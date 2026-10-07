//
//  DesignSystem.swift
//  PlotLine
//
//  The app's shared look: colors, spacing, cards and buttons. Screens use these instead of
//  their own copies, so a change here changes every screen. The sign-in screens have their
//  own matching set in AuthComponents.swift (AuthStyle).
//

import SwiftUI

enum PLColor {
    static let surface        = Color(.secondarySystemBackground)
    static let cardBorder     = Color.black.opacity(0.06)
    static let textPrimary    = Color.primary
    static let textSecondary  = Color.secondary
    /// fills: buttons, badges, "today" (stays blue so white text on it is readable)
    static let accent         = Color.blue
    /// text, icons, links and outlines: white in dark mode, blue in light (matches sign-in and Nutrition)
    static let tint           = Color(UIColor { $0.userInterfaceStyle == .dark ? .white : .systemBlue })
    static let success        = Color.green
    static let warning        = Color.orange
    static let danger         = Color.red
}

enum PLSpacing {
    static let xs: CGFloat = 6
    static let sm: CGFloat = 10
    static let md: CGFloat = 16
    static let lg: CGFloat = 20
}

enum PLRadius {
    static let md: CGFloat = 12
}

/// A rounded, softly bordered card on the secondary background.
struct PLCardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(PLSpacing.md)
            .background(PLColor.surface)
            .clipShape(RoundedRectangle(cornerRadius: PLRadius.md))
            .overlay(RoundedRectangle(cornerRadius: PLRadius.md).stroke(PLColor.cardBorder))
    }
}

extension View {
    func plCard() -> some View { modifier(PLCardModifier()) }
}

/// A full-width filled button (blue by default; pass a color for green/red ones).
struct PrimaryButton: ButtonStyle {
    var color: Color = PLColor.accent

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(color.opacity(configuration.isPressed ? 0.85 : 1))
            .clipShape(RoundedRectangle(cornerRadius: PLRadius.md))
    }
}

/// A full-width outlined button in the given color.
struct OutlineButton: ButtonStyle {
    let tint: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundColor(tint)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .overlay(
                RoundedRectangle(cornerRadius: PLRadius.md)
                    .stroke(tint.opacity(configuration.isPressed ? 0.6 : 1))
            )
            .clipShape(RoundedRectangle(cornerRadius: PLRadius.md))
    }
}

/// A small gray caption above a card or group ("PROFILE", "ACCOUNT").
struct PLSectionHeader: View {
    let title: String

    var body: some View {
        Text(title.uppercased())
            .font(.footnote.weight(.semibold))
            .foregroundColor(PLColor.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)
    }
}

/// A settings-style row: colored icon tile, title, optional value, chevron. Use inside a card.
struct PLRow: View {
    let icon: String
    var tint: Color = PLColor.accent
    let title: String
    var value: String? = nil
    var showsChevron = true

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.white)
                .frame(width: 30, height: 30)
                .background(tint)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            Text(title)
                .foregroundColor(PLColor.textPrimary)
            Spacer(minLength: 8)
            if let value {
                Text(value)
                    .foregroundColor(PLColor.textSecondary)
                    .lineLimit(1)
            }
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundColor(Color(.tertiaryLabel))
            }
        }
        .contentShape(Rectangle())
        .padding(.vertical, 4)
    }
}

/// A labeled value you edit in place (label on the left, text field on the right). Use inside a card.
struct PLFieldRow: View {
    let label: String
    let placeholder: String
    @Binding var text: String

    var body: some View {
        HStack(spacing: 12) {
            Text(label)
                .foregroundColor(PLColor.textPrimary)
            TextField(placeholder, text: $text)
                .multilineTextAlignment(.trailing)
                .foregroundColor(PLColor.textSecondary)
        }
        .padding(.vertical, 6)
    }
}
