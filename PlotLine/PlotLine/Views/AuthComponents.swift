//
//  AuthComponents.swift
//  PlotLine
//
//  Shared look for the account screens (sign in, create account, phone verification,
//  password reset, delete account). Same language as the rest of the app: gray cards with
//  a hairline border, blue accent (white in dark mode, like Nutrition), rounded bold
//  numbers/titles, tinted tiles, and a green primary button.
//
import SwiftUI
import AuthenticationServices

enum AuthStyle {
    static let surface    = Color(.secondarySystemBackground)
    static let field      = Color(.systemBackground)
    static let cardBorder = Color.black.opacity(0.06)
    static let success    = Color.green
    static let danger     = Color.red
    // blue in light mode, white in dark mode
    static let accent     = Color(UIColor { $0.userInterfaceStyle == .dark ? .white : .systemBlue })

    static let spacing: CGFloat = 20
    static let radius: CGFloat = 12
    static let controlHeight: CGFloat = 50
}

extension View {
    func authCard() -> some View {
        self
            .padding(AuthStyle.spacing)
            .background(AuthStyle.surface)
            .clipShape(RoundedRectangle(cornerRadius: AuthStyle.radius))
            .overlay(RoundedRectangle(cornerRadius: AuthStyle.radius).stroke(AuthStyle.cardBorder))
    }
}

// MARK: - Header

struct AuthHero: View {
    let title: String
    var subtitle: String? = nil
    var logoSize: CGFloat = 76

    var body: some View {
        VStack(spacing: 8) {
            Image("PlotLineLogo")
                .resizable()
                .scaledToFit()
                .frame(width: logoSize, height: logoSize)
                .shadow(color: .black.opacity(0.1), radius: 6, y: 3)
                .accessibilityHidden(true)

            Text(title)
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .foregroundColor(AuthStyle.accent)
                .multilineTextAlignment(.center)

            if let subtitle {
                Text(subtitle)
                    .font(.callout)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

// The app's four areas, as tinted tiles like the Nutrition quick actions
struct FeatureStrip: View {
    private let features: [(String, String, Color)] = [
        ("Budget", "chart.line.uptrend.xyaxis", .blue),
        ("Nutrition", "leaf.fill", .green),
        ("Calendar", "calendar", .orange),
        ("Goals", "target", .red),
    ]

    var body: some View {
        HStack(spacing: 10) {
            ForEach(features, id: \.0) { name, icon, color in
                VStack(spacing: 6) {
                    Image(systemName: icon)
                        .font(.title3)
                    Text(name)
                        .font(.caption.bold())
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .foregroundColor(color)
                .background(color.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: AuthStyle.radius))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Budget, nutrition, calendar and goals in one app")
    }
}

// MARK: - Fields

struct AuthField<Field: Hashable>: View {
    let icon: String
    let placeholder: String
    @Binding var text: String
    var focus: FocusState<Field?>.Binding
    let field: Field
    var isSecure: Bool = false
    var contentType: UITextContentType? = nil
    var keyboard: UIKeyboardType = .default
    var submitLabel: SubmitLabel = .next
    var isInvalid: Bool = false
    var trailing: AnyView? = nil
    var onSubmit: () -> Void = {}

    @State private var isRevealed = false

    private var isFocused: Bool { focus.wrappedValue == field }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundColor(isFocused ? AuthStyle.accent : .secondary)
                .frame(width: 20)
                .accessibilityHidden(true)

            Group {
                if isSecure && !isRevealed {
                    SecureField(placeholder, text: $text)
                } else {
                    TextField(placeholder, text: $text)
                }
            }
            .textContentType(contentType)
            .keyboardType(keyboard)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .submitLabel(submitLabel)
            .focused(focus, equals: field)
            .onSubmit(onSubmit)

            if let trailing { trailing }

            if isSecure {
                Button { isRevealed.toggle() } label: {
                    Image(systemName: isRevealed ? "eye.slash" : "eye")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isRevealed ? "Hide password" : "Show password")
            }
        }
        .padding(.horizontal, 14)
        .frame(minHeight: AuthStyle.controlHeight)
        .background(AuthStyle.field)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(isInvalid ? AuthStyle.danger : (isFocused ? AuthStyle.accent : AuthStyle.cardBorder),
                        lineWidth: isInvalid || isFocused ? 1.5 : 1)
        )
        .contentShape(Rectangle())
        .onTapGesture { focus.wrappedValue = field }
        .animation(.easeOut(duration: 0.15), value: isFocused)
    }
}

// small red hint shown under a field
struct FieldHint: View {
    let text: String
    var body: some View {
        Label(text, systemImage: "exclamationmark.circle.fill")
            .font(.caption)
            .foregroundColor(AuthStyle.danger)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 4)
    }
}

// live password rules: tick green as they're met
struct PasswordChecklist: View {
    let password: String

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)],
                  alignment: .leading, spacing: 6) {
            ForEach(AuthViewModel.passwordRules) { rule in
                let met = rule.isMet(password)
                Label(rule.id, systemImage: met ? "checkmark.circle.fill" : "circle")
                    .font(.caption)
                    .foregroundColor(met ? AuthStyle.success : .secondary)
                    .accessibilityLabel("\(rule.id), \(met ? "done" : "not yet")")
            }
        }
        .padding(.horizontal, 4)
        .animation(.easeOut(duration: 0.15), value: password)
    }
}

// MARK: - Buttons & messages

struct AuthPrimaryButton: View {
    let title: String
    var isLoading: Bool = false
    var isEnabled: Bool = true
    var tint: Color = AuthStyle.success
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Text(title).opacity(isLoading ? 0 : 1)
                if isLoading { ProgressView().tint(.white) }
            }
            .font(.headline)
            .foregroundColor(.white)
            .frame(maxWidth: .infinity, minHeight: AuthStyle.controlHeight)
            .background(tint.opacity(isEnabled ? 1 : 0.45))
            .clipShape(RoundedRectangle(cornerRadius: AuthStyle.radius))
        }
        .buttonStyle(PressableStyle())
        .disabled(!isEnabled || isLoading)
    }
}

struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct AuthMessage: View {
    enum Kind { case error, info, success }
    let text: String
    var kind: Kind = .error

    private var color: Color {
        switch kind {
        case .error: return AuthStyle.danger
        case .info: return .blue
        case .success: return AuthStyle.success
        }
    }
    private var icon: String {
        switch kind {
        case .error: return "exclamationmark.triangle.fill"
        case .info: return "info.circle.fill"
        case .success: return "checkmark.circle.fill"
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .font(.footnote.weight(.medium))
        .foregroundColor(color)
        .padding(12)
        .background(color.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .transition(.opacity.combined(with: .move(edge: .top)))
    }
}

struct AuthDivider: View {
    let text: String
    var body: some View {
        HStack(spacing: 10) {
            Rectangle().frame(height: 1).foregroundColor(Color(.separator))
            Text(text).font(.footnote).foregroundColor(.secondary).fixedSize()
            Rectangle().frame(height: 1).foregroundColor(Color(.separator))
        }
    }
}

// Apple + Google, same size, stacked
struct SocialSignInButtons: View {
    @EnvironmentObject var session: AuthViewModel
    var isSignUp: Bool = false

    var body: some View {
        VStack(spacing: 10) {
            AppleSignInButton(label: isSignUp ? .signUp : .signIn)
                // the Apple button doesn't update its label in place
                .id(isSignUp)

            GoogleButton(title: isSignUp ? "Sign up with Google" : "Sign in with Google") {
                session.googleSignIn()
            }
        }
        .disabled(session.isAuthenticating)
        .opacity(session.isAuthenticating ? 0.6 : 1)
    }
}

// Google's button, sized to match Apple's. Colors and logo follow Google's branding guidelines.
struct GoogleButton: View {
    let title: String
    let action: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    private var isDark: Bool { colorScheme == .dark }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image("GoogleLogo")
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 18, height: 18)
                    .accessibilityHidden(true)
                Text(title)
                    .font(.system(size: 19, weight: .medium))
            }
            .foregroundColor(isDark ? Color(red: 0.89, green: 0.89, blue: 0.89) : Color(red: 0.12, green: 0.12, blue: 0.12))
            .frame(maxWidth: .infinity, minHeight: AuthStyle.controlHeight)
            .background(isDark ? Color(red: 0.075, green: 0.075, blue: 0.08) : .white)
            .clipShape(RoundedRectangle(cornerRadius: AuthStyle.radius))
            .overlay(
                RoundedRectangle(cornerRadius: AuthStyle.radius)
                    .stroke(isDark ? Color(red: 0.56, green: 0.57, blue: 0.56) : Color(red: 0.45, green: 0.47, blue: 0.46), lineWidth: 1)
            )
        }
        .buttonStyle(PressableStyle())
    }
}
