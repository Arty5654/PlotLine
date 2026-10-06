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

    @Test("Quiz-format portfolio text becomes holdings")
    func quizFormat() {
        let saved = SavedPortfolio(username: "alex", portfolio: """
        **VTI - 70%%** Broad US market. **Allocation:** $350
        **BND - 30%%** Bonds for stability. **Allocation:** $150
        """, riskTolerance: "Low")
        #expect(saved.parsedAssets.map(\.name) == ["VTI", "BND"])
        #expect(saved.parsedAssets.map(\.amount) == [350, 150])
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
