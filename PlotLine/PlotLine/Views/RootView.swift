//
//  RootView.swift
//  PlotLine
//
//  Created by Alex Younkers on 2/5/25.
//

import SwiftUI



struct RootView: View {
    
    @EnvironmentObject var session: AuthViewModel
    @EnvironmentObject var calendarVM: CalendarViewModel
    @EnvironmentObject var friendsVM : FriendsViewModel
    @EnvironmentObject var chatVM : ChatViewModel
    @ObservedObject private var membership = MembershipManager.shared
    
    var body: some View {
        if session.isLoggedIn && session.needsTermsAcceptance {
            // agree to the current Terms first (Apple/Google sign-ups, existing users, updated terms)
            TermsAcceptanceView()
                .environmentObject(session)
        } else if session.isLoggedIn && session.needVerification != true {
            // PlotLine is subscription-only (the first 1,000 accounts are free forever)
            switch membership.access {
            case .unlocked:
                ContentView()
                    .environmentObject(session)
                    .environmentObject(calendarVM)
                    .environmentObject(friendsVM)
                    .environmentObject(chatVM)
                    .safeAreaInset(edge: .top, spacing: 0) {
                        FreeWeekBanner()
                            .environmentObject(session)
                    }
            case .locked:
                PaywallView()
                    .environmentObject(session)
            case .unknown:
                MembershipCheckView()
                    .environmentObject(session)
            }
            
        } else if (session.needVerification == true) {
            PhoneVerificationView()
                .environmentObject(session)
        } else {
            // No auth, signin page display
            AuthView()
                .environmentObject(session)
        }
        
        
    }
}

// the last 3 days of the free week: how long is left, and a way to subscribe
struct FreeWeekBanner: View {
    @EnvironmentObject var session: AuthViewModel
    @ObservedObject private var membership = MembershipManager.shared
    @State private var showPaywall = false

    var body: some View {
        if let status = membership.status, status.isFreeWeek,
           let days = status.daysLeft(), days <= 3 {
            HStack(spacing: 10) {
                Image(systemName: "hourglass")
                Text(Self.message(daysLeft: days))
                    .font(.footnote.weight(.semibold))
                Spacer(minLength: 8)
                Button("Subscribe") { showPaywall = true }
                    .font(.footnote.weight(.bold))
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
            .foregroundColor(.primary)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color.orange.opacity(0.18))
            .sheet(isPresented: $showPaywall) {
                PaywallView(isSheet: true)
                    .environmentObject(session)
            }
        }
    }

    static func message(daysLeft: Int) -> String {
        switch daysLeft {
        case ...0: return "Your free week ends today"
        case 1: return "1 day left in your free week"
        default: return "\(daysLeft) days left in your free week"
        }
    }
}

// first launch after signing in: asks the server whether this account has a membership
private struct MembershipCheckView: View {
    @EnvironmentObject var session: AuthViewModel
    @ObservedObject private var membership = MembershipManager.shared

    var body: some View {
        VStack(spacing: AuthStyle.spacing) {
            if membership.checkFailed {
                AuthMessage(text: "Couldn't reach PlotLine. Check your connection and try again.")
                AuthPrimaryButton(title: "Try again") {
                    Task { await membership.refresh() }
                }
                Button("Sign out") { session.signOut() }
                    .font(.footnote.weight(.semibold))
                    .foregroundColor(.secondary)
            } else {
                ProgressView()
            }
        }
        .padding(AuthStyle.spacing)
        .task { await membership.refresh() }
    }
}

#Preview {
    RootView()
        .environmentObject(AuthViewModel())
}
