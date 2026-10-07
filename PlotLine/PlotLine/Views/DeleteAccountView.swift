//
//  DeleteAccountView.swift
//  PlotLine
//
import SwiftUI
import StoreKit
import AuthenticationServices

// Permanently delete the signed-in account (App Store rule 5.1.1(v))
struct DeleteAccountView: View {
    @EnvironmentObject var session: AuthViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @State private var showConfirm = false
    @State private var showManageSubscriptions = false

    private let deletedItems: [(String, String)] = [
        ("person.crop.circle", "Your profile, username and sign-in"),
        ("chart.line.uptrend.xyaxis", "Budgets and spending, and linked banks get disconnected"),
        ("leaf.fill", "Nutrition logs, meals and grocery lists"),
        ("calendar", "Calendar events, goals and chats"),
        ("person.2.fill", "Friends, posts, and your spot on shared lists"),
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: AuthStyle.spacing) {
                    VStack(spacing: 10) {
                        Image(systemName: "person.crop.circle.badge.xmark")
                            .font(.system(size: 34))
                            .foregroundColor(AuthStyle.danger)
                            .frame(width: 72, height: 72)
                            .background(AuthStyle.danger.opacity(0.12))
                            .clipShape(Circle())
                        Text("Delete your account")
                            .font(.system(size: 26, weight: .bold, design: .rounded))
                        Text("This permanently deletes your PlotLine account and everything in it. It can't be undone.")
                            .font(.callout)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 8)

                    VStack(alignment: .leading, spacing: 14) {
                        Text("What gets deleted")
                            .font(.headline)
                        ForEach(deletedItems, id: \.1) { icon, text in
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: icon)
                                    .foregroundColor(AuthStyle.danger)
                                    .frame(width: 22)
                                Text(text)
                                    .font(.subheadline)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .authCard()

                    VStack(alignment: .leading, spacing: 10) {
                        AuthMessage(text: "App Store subscriptions aren't canceled automatically. Cancel yours first so you aren't charged again.",
                                    kind: .info)
                        Button("Manage Subscriptions") { showManageSubscriptions = true }
                            .font(.footnote.weight(.semibold))
                            .foregroundColor(AuthStyle.accent)
                            .padding(.leading, 4)
                    }

                    if let error = session.deleteAccountErrorMessage {
                        AuthMessage(text: error)
                        if session.deleteNeedsFreshSignIn {
                            AuthPrimaryButton(title: "Sign Out", tint: .blue) {
                                session.signOut()
                                dismiss()
                            }
                        }
                    }

                    if session.deleteNeedsAppleConfirmation {
                        VStack(spacing: 10) {
                            Text("Confirm with Apple to finish. This also disconnects PlotLine from your Apple ID.")
                                .font(.footnote)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                            SignInWithAppleButton(.continue,
                                                  onRequest: { session.prepareAppleDeleteConfirmation($0) },
                                                  onCompletion: { session.handleAppleDeleteConfirmation($0) })
                                .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
                                .frame(height: AuthStyle.controlHeight)
                                .clipShape(RoundedRectangle(cornerRadius: AuthStyle.radius))
                                .id(colorScheme)
                                .disabled(session.deleteAccountInFlight)
                        }
                    } else if !session.deleteNeedsFreshSignIn {
                        AuthPrimaryButton(title: "Delete My Account",
                                          isLoading: session.deleteAccountInFlight,
                                          tint: AuthStyle.danger) {
                            showConfirm = true
                        }
                    }
                }
                .padding(.horizontal, AuthStyle.spacing)
                .padding(.bottom, AuthStyle.spacing)
                .animation(.easeOut(duration: 0.2), value: session.deleteAccountErrorMessage)
                .animation(.easeOut(duration: 0.2), value: session.deleteNeedsAppleConfirmation)
            }
            .navigationTitle("Delete Account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(session.deleteAccountInFlight)
                }
            }
            .confirmationDialog("Delete your PlotLine account?", isPresented: $showConfirm, titleVisibility: .visible) {
                Button("Delete Account", role: .destructive) { session.deleteAccount() }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("All of your data will be permanently deleted.")
            }
            .manageSubscriptionsSheet(isPresented: $showManageSubscriptions)
        }
        .interactiveDismissDisabled(session.deleteAccountInFlight)
        .onAppear {
            session.deleteAccountErrorMessage = nil
            session.deleteNeedsAppleConfirmation = false
            session.deleteNeedsFreshSignIn = false
        }
        .onChange(of: session.isLoggedIn) { _, loggedIn in
            if !loggedIn { dismiss() }
        }
    }
}

#Preview {
    DeleteAccountView()
        .environmentObject(AuthViewModel())
}
