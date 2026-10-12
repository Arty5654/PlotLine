//
//  ProfileTests.swift
//  PlotLineTests
//
//  Profile page: profiles (full and friends-only), trophies.
//

import Testing
import Foundation
@testable import PlotLine

struct ProfileTests {

    @Test("Your own or a friend's profile decodes with all details")
    func fullProfile() throws {
        let profile = try TestJSON.decode(UserProfile.self,
            #"{"username":"sam","name":"Sam Lee","birthday":"2003-04-05","city":"Columbus"}"#, iso8601: false)
        #expect(profile.name == "Sam Lee")
        #expect(profile.city == "Columbus")
    }

    @Test("A non-friend's profile (username only) still decodes")
    func limitedProfile() throws {
        let profile = try TestJSON.decode(UserProfile.self, #"{"username":"sam"}"#, iso8601: false)
        #expect(profile.username == "sam")
        #expect(profile.name == nil)
        #expect(profile.birthday == nil)
        #expect(profile.city == nil)
    }
}

/// Which trophies pop up as newly earned.
struct TrophyAlertTests {
    private func trophy(_ id: String, level: Int) -> Trophy {
        Trophy(id: id, name: id, description: "", level: level, progress: 0, thresholds: [1, 5, 10, 20], earnedDate: Date())
    }

    @Test("A level higher than last seen pops up; levels already seen don't")
    func newLevels() {
        let seen = ["grocery-lists": 1, "meal-prepper": 2]
        let awards = TrophyAlerts.newAwards([
            trophy("grocery-lists", level: 2),   // Bronze → Silver
            trophy("meal-prepper", level: 2),    // no change
            trophy("nutrition-logger", level: 1),// new trophy
            trophy("watchlist-adder", level: 0),
        ], seen: seen)
        #expect(awards.map(\.trophyId) == ["grocery-lists", "nutrition-logger"])
        #expect(awards.map(\.level) == [2, 1])
    }

    @Test("The first check on a device is the starting point: nothing pops up")
    func firstCheck() {
        #expect(TrophyAlerts.newAwards([trophy("grocery-lists", level: 3)], seen: nil).isEmpty)
    }
}
