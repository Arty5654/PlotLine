import Foundation

/// The server's answer to "can this account use PlotLine?"
struct MembershipStatus: Codable, Equatable {
    /// "lifetime" (first 1,000 accounts), "free-week" (first week after sign-up, no payment),
    /// "trial" (the App Store's free month), "monthly", or "none"
    let plan: String
    let active: Bool
    /// when access ends (ISO 8601), for trial and monthly
    let expiresAt: String?
    /// nil until Apple has told the server
    let autoRenews: Bool?
    /// refunded or revoked by Apple
    let revoked: Bool?

    var isLifetime: Bool { plan == "lifetime" }
    var isFreeWeek: Bool { plan == "free-week" }
    /// subscribed through the App Store (so there's a subscription to manage)
    var isSubscribed: Bool { plan == "trial" || plan == "monthly" }

    /// whole days left (rounded up), while active
    func daysLeft(now: Date = Date()) -> Int? {
        guard active, let end = expiresDate else { return nil }
        return max(0, Int((end.timeIntervalSince(now) / 86_400).rounded(.up)))
    }

    var expiresDate: Date? {
        guard let expiresAt else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: expiresAt) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: expiresAt)
    }

    /// one line for the Membership screen and the paywall
    var summary: String {
        let date = expiresDate?.formatted(date: .abbreviated, time: .omitted)
        if isLifetime { return "Lifetime member: PlotLine is free for you forever." }
        if isFreeWeek {
            if active, let date { return "Your free week ends on \(date). Subscribe to get your first month free." }
            return "Your free week has ended. Subscribe to get your first month free."
        }
        if revoked == true { return "Your subscription was refunded, so PlotLine is locked." }
        if active, let date {
            let what = plan == "trial" ? "Free trial" : "Membership"
            return autoRenews == false ? "\(what) ends on \(date) and won't renew." : "\(what) renews on \(date)."
        }
        if plan == "trial" || plan == "monthly" { return "Your membership has ended." }
        return "Start your free trial to use PlotLine."
    }
}
