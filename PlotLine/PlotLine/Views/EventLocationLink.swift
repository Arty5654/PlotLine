//
//  EventLocationLink.swift
//  PlotLine
//
//  An event's location with a pin; tapping it opens the place in Maps.
//

import SwiftUI

struct EventLocationLink: View {
    let location: String
    var font: Font = .subheadline

    var body: some View {
        if let url = Self.mapsURL(for: location) {
            Link(destination: url) { label }
                .accessibilityHint("Opens in Maps")
        } else {
            label
        }
    }

    private var label: some View {
        Label(location, systemImage: "mappin.and.ellipse")
            .font(font)
            .foregroundColor(PLColor.accent)
            .multilineTextAlignment(.leading)
    }

    /// Apple Maps search for the place ("Starbucks, 123 Main St")
    static func mapsURL(for location: String) -> URL? {
        var components = URLComponents(string: "https://maps.apple.com/")
        components?.queryItems = [URLQueryItem(name: "q", value: location)]
        return components?.url
    }
}
