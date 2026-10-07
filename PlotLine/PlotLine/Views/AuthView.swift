//
//  AuthView.swift
//  PlotLine
//
//  Created by Alex Younkers on 2/13/25.
//
import SwiftUI

// Welcome screen: brand header, Sign In / Create Account switch, then Apple & Google
struct AuthView: View {

    @EnvironmentObject var session: AuthViewModel
    @State private var legalPage: LegalPage?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: AuthStyle.spacing) {
                    AuthHero(title: "PlotLine",
                             subtitle: "Budget, eat well, and plan your week, all in one place.")

                    FeatureStrip()

                    Picker("Account", selection: $session.isSignin.animation(.easeInOut(duration: 0.2))) {
                        Text("Sign In").tag(true)
                        Text("Create Account").tag(false)
                    }
                    .pickerStyle(.segmented)
                    .padding(.top, 4)

                    Group {
                        if session.isSignin {
                            SignInView()
                                .transition(.opacity)
                        } else {
                            SignUpView()
                                .transition(.opacity)
                        }
                    }

                    AuthDivider(text: "or continue with")

                    SocialSignInButtons(isSignUp: !session.isSignin)

                    LegalFooterLinks()
                        .padding(.top, 4)
                }
                .padding(.horizontal, AuthStyle.spacing)
                .padding(.bottom, AuthStyle.spacing)
            }
            .scrollDismissesKeyboard(.interactively)
            .legalLinkSheet($legalPage)
            .background(Color(.systemBackground))
            // empty inline bar: invisible at the top, blurs content that scrolls under the status bar
            .navigationBarTitleDisplayMode(.inline)
            .onChange(of: session.isSignin) { _, _ in
                session.loginErrorMessage = nil
                session.signupErrorMessage = nil
            }
        }
    }
}

#Preview("Sign In") {
    let session = AuthViewModel()
    session.isSignin = true
    return AuthView().environmentObject(session)
}

#Preview("Create Account") {
    AuthView().environmentObject(AuthViewModel())
}
