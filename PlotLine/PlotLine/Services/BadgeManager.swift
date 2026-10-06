//
//  BadgeManager.swift
//  PlotLine
//
//  The red number on the app icon = things waiting on you: friend requests, shared grocery
//  list invites, calendar-sharing invites, events waiting for your approval or RSVP, and
//  detected subscriptions you haven't confirmed. It's recounted whenever you leave the app,
//  so it goes down as you handle things. (Without server push it can't go up while the app
//  is closed; that needs push notifications.)
//
import UIKit
import UserNotifications

@MainActor
enum BadgeManager {

    /// Recurring-charge prompts are expensive to recompute (Plaid analysis), so the screen that
    /// loads them saves how many are still waiting here.
    static let pendingRecurringPromptsKey = "pendingRecurringChargePrompts"

    static func refresh() async {
        guard KeychainManager.loadToken() != nil,
              let username = UserDefaults.standard.string(forKey: "loggedInUsername"),
              !username.isEmpty else {
            await setBadge(0)
            return
        }

        async let friendRequests = try? FriendsAPI.fetchFriendRequests(username: username)
        async let groceryInvites = try? GroceryListAPI.getPendingInvites(username: username)
        async let calendarAccess = try? CalendarAccessAPI.getAccessData(username: username)
        async let events = try? CalendarAPI.getEvents(username: username)

        let requestCount: Int = await friendRequests?.pendingRequests.count ?? 0
        let groceryCount: Int = await groceryInvites?.count ?? 0
        let calendarAccessCount: Int = await calendarAccess?.pendingIncoming.count ?? 0
        let eventCount: Int = await events?.filter { $0.status == "pending" || $0.status == "invite-pending" }.count ?? 0
        let subscriptionCount: Int = UserDefaults.standard.integer(forKey: pendingRecurringPromptsKey)

        await setBadge(requestCount + groceryCount + calendarAccessCount + eventCount + subscriptionCount)
    }

    /// Recount when the app goes to the background (that's when the icon is visible again),
    /// asking iOS for a few seconds to finish the requests.
    static func refreshInBackground() {
        let taskID = UIApplication.shared.beginBackgroundTask(withName: "Refresh app badge")
        Task {
            await refresh()
            UIApplication.shared.endBackgroundTask(taskID)
        }
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: pendingRecurringPromptsKey)
        Task { await setBadge(0) }
    }

    private static func setBadge(_ count: Int) async {
        try? await UNUserNotificationCenter.current().setBadgeCount(max(0, count))
    }
}
