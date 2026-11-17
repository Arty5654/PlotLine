//
//  CommuteEstimate.swift
//  PlotLine
//
//  The budget quiz's commute: how far (Apple Maps, on the phone), how often, and how you get
//  there → a monthly cost. Prices (gas, electricity, transit fares, rideshare rates, tolls) are the
//  server's cached estimates; every one can be changed in the quiz.
//

import Foundation
import MapKit

enum CommuteMode: String, CaseIterable, Identifiable, Codable {
    case drive, transit, rideshare, carpoolDriver = "carpool-driver", carpoolPassenger = "carpool-passenger", bikeWalk = "bike-walk"
    var id: String { rawValue }

    var title: String {
        switch self {
        case .drive: return "Drive"
        case .transit: return "Public transit"
        case .rideshare: return "Rideshare (Uber/Lyft)"
        case .carpoolDriver: return "Carpool (I drive)"
        case .carpoolPassenger: return "Carpool (I ride)"
        case .bikeWalk: return "Bike or walk"
        }
    }

    var needsCar: Bool { self == .drive || self == .carpoolDriver }
}

enum CarType: String, CaseIterable, Identifiable, Codable {
    case small, sedan, hybridSedan = "hybrid-sedan", suv, hybridSuv = "hybrid-suv", electric
    var id: String { rawValue }
    var title: String {
        switch self {
        case .small: return "Small car"
        case .sedan: return "Sedan"
        case .hybridSedan: return "Hybrid sedan"
        case .suv: return "SUV or truck"
        case .hybridSuv: return "Hybrid SUV"
        case .electric: return "Electric"
        }
    }
    /// typical real-world miles per gallon (electric: miles per kWh)
    var milesPerUnit: Double {
        switch self {
        case .small: return 35
        case .sedan: return 30
        case .hybridSedan: return 48   // e.g. Camry or Prius hybrids
        case .suv: return 22
        case .hybridSuv: return 37     // e.g. RAV4 or CR-V hybrids
        case .electric: return 3.5
        }
    }
}

/// what the quiz asks about getting to work
struct CommuteInputs: Equatable, Codable {
    var mode: CommuteMode = .drive
    var officeDaysPerWeek: Double = 5
    var roundTripMiles: Double = 0
    var oneWayMinutes: Double = 0
    var car: CarType = .sedan
    var fuelPrice: Double = 0              // per gallon, or per kWh for an electric car
    var parkingMonthly: Double = 0
    var tollsPerDay: Double = 0            // both ways
    var carpoolPeople: Double = 2          // including you
    var passengerWeekly: Double = 0        // what a carpool passenger chips in
    var transitMonthlyPass: Double = 0
    var transitSingleFare: Double = 0
    var rideshareBase: Double = 0          // base + booking fee per trip
    var ridesharePerMile: Double = 0
    var ridesharePerMinute: Double = 0
    var rideshareMinimum: Double = 0
}

enum CommuteCost {
    /// office days in an average month
    static func workdaysPerMonth(_ daysPerWeek: Double) -> Double { daysPerWeek * 52 / 12 }

    /// the monthly cost and a short description of how it's worked out
    static func monthly(_ c: CommuteInputs) -> (total: Double, summary: String) {
        let days = workdaysPerMonth(c.officeDaysPerWeek)
        let daysText = "\(Int(c.officeDaysPerWeek)) day\(c.officeDaysPerWeek == 1 ? "" : "s")/week"
        switch c.mode {
        case .drive, .carpoolDriver:
            let fuel = c.car.milesPerUnit > 0 ? c.roundTripMiles * days / c.car.milesPerUnit * c.fuelPrice : 0
            let tolls = c.tollsPerDay * days
            var total = fuel + tolls + c.parkingMonthly
            var summary = "drive \(Int(c.roundTripMiles.rounded())) mi round trip, \(daysText)"
            if c.tollsPerDay > 0 { summary += ", tolls" }
            if c.parkingMonthly > 0 { summary += ", parking" }
            if c.mode == .carpoolDriver, c.carpoolPeople > 1 {
                total /= c.carpoolPeople
                summary += ", split \(Int(c.carpoolPeople)) ways"
            }
            return (total, summary)
        case .carpoolPassenger:
            return (c.passengerWeekly * 52 / 12, "carpool passenger, \(daysText)")
        case .transit:
            let perRide = c.transitSingleFare * 2 * days
            if c.transitMonthlyPass > 0, c.transitMonthlyPass <= perRide || perRide == 0 {
                return (c.transitMonthlyPass, "transit monthly pass, \(daysText)")
            }
            return (perRide, "transit, \(Int(days.rounded() * 2)) rides a month")
        case .rideshare:
            let oneWay = max(c.rideshareMinimum, c.rideshareBase + c.ridesharePerMile * c.roundTripMiles / 2 + c.ridesharePerMinute * c.oneWayMinutes)
            return (oneWay * 2 * days, "rideshare both ways, \(daysText)")
        case .bikeWalk:
            return (0, "bike or walk")
        }
    }
}

extension CommuteCost {
    /// the gas part of the commute (the rest is tolls, parking, transit or rides): the budget has no
    /// Commute line, gas goes in Gas and the rest in Transportation, the way spending is tracked
    static func gas(_ c: CommuteInputs) -> Double {
        guard c.mode == .drive || c.mode == .carpoolDriver, c.car.milesPerUnit > 0 else { return 0 }
        let fuel = c.roundTripMiles * workdaysPerMonth(c.officeDaysPerWeek) / c.car.milesPerUnit * c.fuelPrice
        return c.mode == .carpoolDriver && c.carpoolPeople > 1 ? fuel / c.carpoolPeople : fuel
    }
}

/// The route from home to work, from Apple Maps on the phone (nothing about it is saved but the distance).
enum CommuteRoute {
    struct Result: Equatable {
        let roundTripMiles: Double
        let oneWayMinutes: Double
        let hasTolls: Bool
    }

    /// "Richmond, VA" → "Glen Allen, VA 23060" by car
    static func drive(from home: String, to work: String) async throws -> Result {
        async let homeItem = place(home)
        async let workItem = place(work)
        let request = MKDirections.Request()
        request.source = try await homeItem
        request.destination = try await workItem
        request.transportType = .automobile
        let response = try await MKDirections(request: request).calculate()
        guard let route = response.routes.first else { throw URLError(.cannotFindHost) }
        return Result(roundTripMiles: route.distance / 1609.344 * 2,
                      oneWayMinutes: route.expectedTravelTime / 60,
                      hasTolls: route.hasTolls)
    }

    private static func place(_ text: String) async throws -> MKMapItem {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = text
        request.resultTypes = .address
        guard let item = try await MKLocalSearch(request: request).start().mapItems.first else {
            throw URLError(.cannotFindHost)
        }
        return item
    }
}
