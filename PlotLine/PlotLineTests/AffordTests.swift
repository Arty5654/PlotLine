//
//  AffordTests.swift
//  PlotLineTests
//
//  Budget → Plan → "Can I afford it?": the answer from the server, and a goal keeping its cuts.
//

import Testing
import Foundation
@testable import PlotLine

struct AffordTests {
    private let json = #"""
    {"verdict": "notYet", "headline": "Not yet: about March 2027", "detail": "…",
     "sources": [{"kind": "unassigned", "label": "Take-home your budget doesn't assign yet", "amount": 100},
                 {"kind": "savings", "label": "This month's Savings", "amount": 200}],
     "availableNow": 300, "perMonth": 300, "readyBy": "2027-03", "hoursOfWork": 69.3,
     "interest": null, "payIn4": null, "warnings": [],
     "cutPlan": {"monthlyNeeded": 150, "months": 3, "cutsTotal": 140, "readyBy": "2027-02",
                 "cuts": [{"kind": "trim", "line": "Eating Out", "label": "Eating Out: $300 → $195 a month", "amount": 105,
                           "note": null, "applies": true, "suggested": true},
                          {"kind": "subscription", "line": "", "label": "Pause Spotify", "amount": 12,
                           "note": "Cancel or pause it", "applies": false, "suggested": false}]}}
    """#

    @Test("The answer decodes; ready-by moves with the cuts picked")
    func decode() throws {
        let r = try TestJSON.decode(AffordResult.self, json)
        #expect(r.tone == .caution)
        #expect(!r.fitsNow)
        #expect(r.cutPlan?.cuts.first?.suggested == true)
        #expect(r.cutPlan?.cuts.last?.applies == false)
        // a subscription is picked by name (several share the Subscriptions line), the rest by line
        #expect(r.cutPlan?.cuts.first?.pick == "Eating Out")
        var spotify = try #require(r.cutPlan?.cuts.last)
        spotify.name = "Spotify"
        #expect(spotify.pick == "subscription:Spotify")
        let paused = try TestJSON.decode(SubscriptionData.self,
            #"{"name":"Netflix","cost":"17.99","dueDate":"2026-12-06T12:00:00.000Z","pausedFor":"G1","pausedForName":"Laptop"}"#)
        #expect(paused.pausedForName == "Laptop")
        #expect(SubscriptionItem(name: "Netflix", cost: "17.99", dueDate: Date(), pausedFor: paused.pausedFor).isPaused)
        let now = Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 10))!
        // $1,200 at $300 a month, starting now: 4 months; with $150 more ($450): 3 months
        #expect(r.readyBy(price: 1200, cutsPerMonth: 0, now: now) == "2027-03")
        #expect(r.readyBy(price: 1200, cutsPerMonth: 150, now: now) == "2027-02")
        #expect(AffordResult.monthName("2027-03") == "March 2027")
    }

    @Test("The purchase is sent with only what applies; a goal from Save for It keeps its cuts through a plan save")
    func requestAndCuts() throws {
        let card = AffordRequest(item: "TV", price: 900, by: nil, payment: .cardBalance, apr: 22, monthly: false)
        let sent = try JSONSerialization.jsonObject(with: JSONEncoder().encode(card)) as? [String: Any]
        #expect(sent?["payment"] as? String == "card-balance")
        #expect(sent?["by"] == nil)

        let goal = try TestJSON.decode(SavingsGoal.self,
            #"{"id": "g1", "name": "Laptop", "target": 1200, "saved": 0, "cuts": [{"line": "Eating Out", "amount": 105}]}"#)
        #expect(goal.cuts == [SavingsGoal.GoalCut(line: "Eating Out", amount: 105)])
        let again = try JSONDecoder().decode(SavingsGoal.self, from: JSONEncoder().encode(goal))
        #expect(again.cuts?.first?.line == "Eating Out")
    }

    @Test("Ongoing costs go with the purchase; the wishlist and the emergency floor are saved with the plan (old plans still load)")
    func phase3() throws {
        var car = AffordRequest(item: "Car", price: 8000)
        car.ongoingCosts = [OngoingCost(name: "Insurance", monthly: 150)]
        let sent = try JSONSerialization.jsonObject(with: JSONEncoder().encode(car)) as? [String: Any]
        #expect((sent?["ongoingCosts"] as? [[String: Any]])?.first?["monthly"] as? Double == 150)

        let old = try TestJSON.decode(Plan.self, #"{"emergencyFund": {"months": 3, "saved": 500}, "savingsGoals": []}"#)
        #expect(old.wishlist.isEmpty)
        #expect(old.emergencyFund.saved == 500)
        #expect(old.emergencyFund.floor == nil)

        let plan = try TestJSON.decode(Plan.self, #"""
        {"emergencyFund": {"months": 3, "saved": 2000, "floor": 1000},
         "wishlist": [{"id": "w1", "item": "Headphones", "price": 300, "addedOn": "2026-11-24", "remindOn": "2026-11-26", "goalId": "g1"}]}
        """#)
        #expect(plan.emergencyFund.floor == 1000)
        #expect(plan.wishlist.first?.goalId == "g1")
        let again = try JSONDecoder().decode(Plan.self, from: JSONEncoder().encode(plan))
        #expect(again == plan)

        let wish = plan.wishlist[0]
        #expect(!wish.readyToDecide(now: Plan.day("2026-11-25")!))
        #expect(wish.readyToDecide(now: Plan.day("2026-11-26")!))
    }

    @MainActor
    @Test("Adding to the wishlist sets when to decide; removing takes it off")
    func wishlist() {
        let model = PlanViewModel(preview: Plan())
        let now = Plan.day("2026-11-24")!
        model.addToWishlist(item: "Headphones", price: 300, days: 30, now: now)
        #expect(model.plan.wishlist.count == 1)
        #expect(model.plan.wishlist[0].addedOn == "2026-11-24")
        #expect(model.plan.wishlist[0].remindOn == "2026-12-24")
        model.removeFromWishlist(model.plan.wishlist[0].id)
        #expect(model.plan.wishlist.isEmpty)

        // the monthly costs they kept are saved with the item (no new AI call when it's opened again)
        model.addToWishlist(item: "Car", price: 9000, days: 2, ongoingCosts: [OngoingCost(name: "Insurance", monthly: 150)], now: now)
        let car = model.plan.wishlist[0]
        #expect(car.ongoingCosts == [OngoingCost(name: "Insurance", monthly: 150)])
        #expect(OngoingEstimate(saved: car.ongoingCosts ?? []).costs.first?.monthly == 150)
        let roundTrip = try? JSONDecoder().decode(WishItem.self, from: JSONEncoder().encode(car))
        #expect(roundTrip == car)
        // an item saved before this has none, and still loads
        let old = try? JSONDecoder().decode(WishItem.self, from: Data(#"{"id":"w","item":"Shoes","price":80,"addedOn":"2026-11-24","remindOn":"2026-11-26"}"#.utf8))
        #expect(old?.ongoingCosts == nil)
    }
}
