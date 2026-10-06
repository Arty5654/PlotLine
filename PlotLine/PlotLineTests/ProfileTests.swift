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
