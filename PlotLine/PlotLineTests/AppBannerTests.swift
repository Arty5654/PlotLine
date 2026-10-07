//
//  AppBannerTests.swift
//  PlotLineTests
//
//  The app-wide error banner: what it says, and how repeated failures are shown.
//

import Testing
import Foundation
@testable import PlotLine

@MainActor
@Suite(.serialized) // one shared banner
struct AppBannerTests {

    @Test("Wording: offline gets a connection hint, other failures a plain retry, the AI limit keeps the server's message")
    func wording() {
        #expect(AppBanner.text(for: "save your meal", URLError(.notConnectedToInternet))
                == "Couldn't save your meal. Check your connection and try again.")
        #expect(AppBanner.text(for: "save your meal", URLError(.timedOut)).hasSuffix("Check your connection and try again."))
        #expect(AppBanner.text(for: "load your budget", URLError(.badServerResponse))
                == "Couldn't load your budget. Please try again.")
        #expect(AppBanner.text(for: "load your budget", nil) == "Couldn't load your budget. Please try again.")
        let limit = AILimitError(message: "You've reached today's limit for AI features. Try again in 3 hours.")
        #expect(AppBanner.text(for: "scan the receipt", limit) == limit.message)
    }

    @Test("The same problem twice, or several offline failures at once, keep the banner that's showing")
    func coalescing() {
        let banner = AppBanner.shared
        banner.dismiss()
        banner.show("Couldn't load your goals. Please try again.")
        let first = banner.message?.id
        banner.show("Couldn't load your goals. Please try again.")
        #expect(banner.message?.id == first)

        banner.show(AppBanner.text(for: "load your calendar", URLError(.notConnectedToInternet)))
        let offline = banner.message
        banner.show(AppBanner.text(for: "load your goals", URLError(.notConnectedToInternet)))
        #expect(banner.message?.id == offline?.id)
        #expect(banner.message?.text.contains("calendar") == true)

        banner.show("Couldn't delete the goal. Please try again.") // a different problem replaces it
        #expect(banner.message?.text == "Couldn't delete the goal. Please try again.")
        banner.dismiss()
        #expect(banner.message == nil)
    }

    @Test("Completion-handler requests: only 2xx counts as success")
    func reportIfFailed() async throws {
        let url = URL(string: "https://example.com/api/goals/alice")!
        func response(_ code: Int) -> HTTPURLResponse { HTTPURLResponse(url: url, statusCode: code, httpVersion: nil, headerFields: nil)! }

        #expect(AppBanner.reportIfFailed("load your goals", Data(), response(200), nil) == false)
        #expect(AppBanner.reportIfFailed("load your goals", Data(), response(204), nil) == false)
        #expect(AppBanner.reportIfFailed("load your goals", Data(), response(500), nil))
        #expect(AppBanner.reportIfFailed("load your goals", nil, nil, URLError(.notConnectedToInternet)))
        #expect(AppBanner.reportIfFailed("load your goals", nil, nil, nil)) // no response at all
        try await Task.sleep(for: .milliseconds(100)) // the banners it reported, before the next test
        #expect(AppBanner.shared.message?.text.hasPrefix("Couldn't load your goals.") == true)
        AppBanner.shared.dismiss()
    }
}
