//
//  InvestingTests.swift
//  PlotLineTests
//
//  Investing page: turning the AI's portfolio text into holdings.
//

import Testing
import Foundation
@testable import PlotLine

struct InvestingTests {

    @Test("Edited-format portfolio text becomes holdings")
    func editedFormat() {
        let saved = SavedPortfolio(username: "alex", portfolio: """
        **VTI** - 60% - $300
        **VXUS** - 30% - $150
        **BND** - 10% - $50
        """, riskTolerance: "Medium")
        let assets = saved.parsedAssets
        #expect(assets.map(\.name) == ["VTI", "VXUS", "BND"])
        #expect(assets.map(\.percentage) == [60, 30, 10])
        #expect(assets.map(\.amount) == [300, 150, 50])
    }

    @Test("An edited symbol with a dot (BRK.B) still shows")
    func dottedSymbol() {
        let saved = SavedPortfolio(username: "alex", portfolio: "**BRK.B** - 20% - $40\n**VTI** - 80% - $160",
                                   riskTolerance: "Edited")
        #expect(saved.parsedAssets.map(\.name) == ["BRK.B", "VTI"])
    }

    @Test("The quiz is for the tab it was opened from")
    func quizAccount() {
        #expect(StockView.ViewAccount.rothIRA.apiValue == "ROTH_IRA")
        #expect(InvestmentQuizView(account: .rothIRA).account == .rothIRA)
        #expect(InvestmentQuizView(account: .brokerage).account.rawValue == "Brokerage")
    }

    @Test("Quiz-format portfolio text becomes holdings")
    func quizFormat() {
        let saved = SavedPortfolio(username: "alex", portfolio: """
        **VTI - 70%%** Broad US market. **Allocation:** $350
        **BND - 30%%** Bonds for stability. **Allocation:** $150
        """, riskTolerance: "Low")
        #expect(saved.parsedAssets.map(\.name) == ["VTI", "BND"])
        #expect(saved.parsedAssets.map(\.amount) == [350, 150])
    }

    @Test("The AI's single % and amounts with commas still parse")
    func singlePercent() {
        let saved = SavedPortfolio(username: "a", portfolio: "**VTI - 100%**\n- **Allocation:** $1,250.00", riskTolerance: "Low")
        #expect(saved.parsedAssets.map(\.amount) == [1250])
    }

    @Test("Text without holdings gives an empty list instead of crashing")
    func unparseable() {
        #expect(SavedPortfolio(username: "a", portfolio: "Sorry, try again", riskTolerance: "Low").parsedAssets.isEmpty)
    }

    @Test("Investment frequency is read from the text, defaulting to monthly")
    func frequency() {
        #expect(SavedPortfolio(username: "a", portfolio: "Invest weekly", riskTolerance: "Low").investmentFrequency == "Weekly")
        #expect(SavedPortfolio(username: "a", portfolio: "No schedule", riskTolerance: "Low").investmentFrequency == "Monthly")
    }
}

struct InvestingQuizTests {
    private typealias A = InvestingAnswers

    @Test("Each quiz sends only its own questions; the drop answer sets the risk")
    func payload() {
        var a = A()
        a.age = "26"; a.experience = "Beginner"; a.dropReaction = "Buy more while it's cheaper"; a.style = "One fund"
        #expect(!a.isComplete(for: .rothIRA))
        a.filingStatus = "Single"; a.workplacePlan = "Full match"; a.earlyAccess = "Very unlikely"; a.contributedThisYear = "$1,500"
        #expect(a.isComplete(for: .rothIRA))
        #expect(!a.isComplete(for: .brokerage))

        let roth = a.payload(username: "alex", account: .rothIRA, emergencySaved: 4200.4)
        #expect(roth["account"] == "ROTH_IRA")
        #expect(roth["riskTolerance"] == "High")
        #expect(roth["contributedThisYear"] == "1500")
        #expect(roth["retireAge"] == "65")
        #expect(roth["emergencySaved"] == "4200")
        #expect(roth["purpose"] == nil)

        a.purpose = "A home"; a.horizon = "3-5 years"
        let brokerage = a.payload(username: "alex", account: .brokerage, emergencySaved: nil)
        #expect(brokerage["taxBracket"] == "Not sure")
        #expect(brokerage["workplacePlan"] == nil)
        #expect(brokerage["emergencySaved"] == nil)
    }

    @Test("Last time's answers fill in what's blank; the bracket comes from the salary; Roth room counts the catch-up")
    func prefill() throws {
        let facts = try TestJSON.decode(InvestingFacts.self, #"""
        {"yearlyIncome": 85000, "monthlyAmount": 400, "federalBracket": 22, "emergencySaved": -1,
         "answers": {"age": "51", "experience": "Intermediate", "retireAge": "62", "esg": "Yes"},
         "ira": {"year": 2026, "limit": 7500, "catchUpAge": 50, "catchUp": 1100, "rothSingle": [153000, 168000], "rothJoint": [242000, 252000]}}
        """#)
        var a = A()
        a.experience = "Advanced"
        a.prefill(from: facts)
        #expect(a.age == "51")
        #expect(a.experience == "Advanced")      // what they already picked stays
        #expect(a.retireAge == 62)
        #expect(a.esg)
        #expect(a.taxBracket == "22–24%")
        a.contributedThisYear = "2000"
        #expect(a.rothRoom(try #require(facts.ira)) == 6600)

        // an older server's reply without most fields still decodes
        let bare = try TestJSON.decode(InvestingFacts.self, #"{"monthlyAmount": 100}"#)
        #expect(bare.monthlyAmount == 100)
        #expect(bare.emergencySaved == -1)
        #expect(bare.ira == nil)
    }
}
