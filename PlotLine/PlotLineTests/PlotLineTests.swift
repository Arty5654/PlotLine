//
//  PlotLineTests.swift
//  PlotLineTests
//
//  Shared helpers for the unit tests. Each area has its own file
//  (AuthTests, CalendarTests, BudgetSpendingTests, ...).
//

import Foundation
@testable import PlotLine

enum TestJSON {
    /// Decodes JSON text the way the app's networking code does (ISO-8601 dates).
    static func decode<T: Decodable>(_ type: T.Type, _ json: String, iso8601: Bool = true) throws -> T {
        let decoder = JSONDecoder()
        if iso8601 { decoder.dateDecodingStrategy = .iso8601 }
        return try decoder.decode(T.self, from: Data(json.utf8))
    }

    static func object(_ value: some Encodable) throws -> [String: Any] {
        let data = try JSONEncoder().encode(value)
        return try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
    }

    /// A date at local midnight, for date-math tests.
    static func day(_ y: Int, _ m: Int, _ d: Int, calendar: Calendar = Calendar(identifier: .gregorian)) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d))!
    }
}
