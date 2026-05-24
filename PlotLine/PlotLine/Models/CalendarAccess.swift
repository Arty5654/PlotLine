import Foundation

struct CalendarInvite: Codable, Identifiable {
    let id: String
    let fromUsername: String
    let toUsername: String
    let level: String        // "view" or "add"
    let requireApproval: Bool
    let sentAt: String
}

struct CalendarAccessGrant: Codable {
    let friendUsername: String
    let level: String        // "view" or "add"
    let requireApproval: Bool
    let grantedAt: String
}

struct CalendarAccessData: Codable {
    var granted: [CalendarAccessGrant]
    var receivedAccess: [CalendarAccessGrant]
    var pendingOutgoing: [CalendarInvite]
    var pendingIncoming: [CalendarInvite]

    init() {
        granted = []
        receivedAccess = []
        pendingOutgoing = []
        pendingIncoming = []
    }
}
