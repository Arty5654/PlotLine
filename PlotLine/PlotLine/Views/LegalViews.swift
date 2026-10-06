//
//  LegalViews.swift
//  PlotLine
//
//  Terms of Service / Privacy Policy: links, the sign-up checkbox, and the one-time
//  acceptance screen shown to anyone who hasn't agreed to the current version.
//  The pages themselves are served by the backend (/terms, /privacy).
//
import SwiftUI
import SafariServices

enum LegalPage: String, Identifiable {
    case terms, privacy

    var id: String { rawValue }

    var url: URL {
        URL(string: "\(BackendConfig.baseURLString)/\(rawValue)")!
    }
}

// in-app browser sheet for the legal pages
struct SafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        SFSafariViewController(url: url)
    }

    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}
}

extension View {
    /// Opens Terms/Privacy links inside the app instead of switching to Safari.
    func legalLinkSheet(_ page: Binding<LegalPage?>) -> some View {
        self
            .environment(\.openURL, OpenURLAction { url in
                if let match = [LegalPage.terms, .privacy].first(where: { $0.url == url }) {
                    page.wrappedValue = match
                    return .handled
                }
                return .systemAction
            })
            .sheet(item: page) { page in
                SafariView(url: page.url).ignoresSafeArea()
            }
    }
}

// "I'm 18 or older and agree to the Terms of Service and Privacy Policy"
struct TermsAgreementToggle: View {
    @Binding var isOn: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Button {
                isOn.toggle()
            } label: {
                Image(systemName: isOn ? "checkmark.square.fill" : "square")
                    .font(.title3)
                    .foregroundColor(isOn ? AuthStyle.accent : .secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("I'm 18 or older and agree to the Terms of Service and Privacy Policy")
            .accessibilityAddTraits(isOn ? .isSelected : [])

            Text(.init("I'm 18 or older and agree to the [Terms of Service](\(LegalPage.terms.url.absoluteString)) and [Privacy Policy](\(LegalPage.privacy.url.absoluteString))."))
                .font(.footnote)
                .foregroundColor(.secondary)
                .tint(AuthStyle.accent)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// small "Terms · Privacy" footer
struct LegalFooterLinks: View {
    var body: some View {
        Text(.init("[Terms of Service](\(LegalPage.terms.url.absoluteString))  ·  [Privacy Policy](\(LegalPage.privacy.url.absoluteString))"))
            .font(.footnote)
            .tint(.secondary)
            .frame(maxWidth: .infinity)
    }
}

// Shown after sign-in to anyone who hasn't accepted the current terms
// (Apple/Google sign-ups, existing accounts, or after the terms change)
struct TermsAcceptanceView: View {
    @EnvironmentObject var session: AuthViewModel
    @State private var agreed = false
    @State private var legalPage: LegalPage?

    private let highlights: [(String, String)] = [
        ("person.badge.shield.checkmark", "You must be 18 or older to use PlotLine."),
        ("chart.line.uptrend.xyaxis", "Budgets, portfolios and nutrition info are for organizing your life, not professional financial or medical advice."),
        ("sparkles", "Some features use AI, which can make mistakes, so double-check anything important."),
        ("lock.shield", "We don't sell your data or use it for ads. Bank data comes through Plaid, read-only."),
        ("trash", "You can delete your account and data anytime from your Profile."),
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: AuthStyle.spacing) {
                AuthHero(title: "Before you continue",
                         subtitle: "Please review and agree to PlotLine's Terms of Service and Privacy Policy.",
                         logoSize: 64)
                    .padding(.top, 24)

                VStack(alignment: .leading, spacing: 14) {
                    Text("The highlights")
                        .font(.headline)
                    ForEach(highlights, id: \.1) { icon, text in
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: icon)
                                .foregroundColor(AuthStyle.accent)
                                .frame(width: 22)
                            Text(text)
                                .font(.subheadline)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    HStack(spacing: 16) {
                        Button("Read Terms of Service") { legalPage = .terms }
                        Button("Read Privacy Policy") { legalPage = .privacy }
                    }
                    .font(.footnote.weight(.semibold))
                    .foregroundColor(AuthStyle.accent)
                    .padding(.top, 4)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .authCard()

                TermsAgreementToggle(isOn: $agreed)

                if let error = session.termsErrorMessage {
                    AuthMessage(text: error)
                }

                AuthPrimaryButton(title: "Agree and Continue",
                                  isLoading: session.termsInFlight,
                                  isEnabled: agreed) {
                    session.acceptTerms()
                }

                Button("Sign out") { session.signOut() }
                    .font(.footnote.weight(.semibold))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, AuthStyle.spacing)
            .padding(.bottom, AuthStyle.spacing)
            .animation(.easeOut(duration: 0.2), value: session.termsErrorMessage)
        }
        .background(Color(.systemBackground))
        .legalLinkSheet($legalPage)
    }
}

#Preview {
    TermsAcceptanceView()
        .environmentObject(AuthViewModel())
}
