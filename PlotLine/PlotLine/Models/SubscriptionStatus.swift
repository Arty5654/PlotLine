import Foundation

struct SubscriptionStatus: Codable {
    let plan: String
    let monthlyPrice: Double
    let trialEndsAt: String?
    let autoRenews: Bool
    let message: String?
}
