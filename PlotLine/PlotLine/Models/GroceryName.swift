//
//  GroceryName.swift
//  PlotLine
//
//  A food from the log goes on a grocery list as what you'd buy, not what you ate: nobody buys
//  "Pasta, cooked". Store products (a brand, a scanned barcode) keep their name, because they're
//  bought as they are: a Kirkland rotisserie chicken is bought cooked.
//

import Foundation

enum GroceryName {

    /// "Pasta, cooked" → "Pasta"; "Beef, ground, 80% lean meat / 20% fat, raw" → "Ground beef (80/20)";
    /// "Grilled chicken breast" → "Chicken breast"
    static func forShopping(_ food: FoodItem) -> String {
        if food.brand != nil || food.source == .barcode { return food.name }
        return forShopping(food.name)
    }

    static func forShopping(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if keepAsIs.contains(trimmed.lowercased()) { return trimmed }

        // USDA style: the food, then details separated by commas
        var parts = trimmed.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        guard !parts.isEmpty else { return trimmed }
        var head = withoutLeadingPrep(parts.removeFirst())

        var before: [String] = []   // "ground" in "Ground beef"
        var after: [String] = []    // "long-grain" in "White rice, long-grain"
        var lean: String?
        for part in parts {
            let lower = part.lowercased()
            if let ratio = leanRatio(lower) { lean = ratio; continue }
            if isPrep(lower) { continue }
            if adjectives.contains(lower) { before.append(lower); continue }
            if cuts.contains(lower) { head += " " + lower; continue } // "Chicken, thigh" → "Chicken thigh"
            after.append(part)
        }

        var result = (before + [before.isEmpty ? head : head.lowercased()]).joined(separator: " ")
        if let lean { result += " (\(lean))" }
        if !after.isEmpty { result += ", " + after.joined(separator: ", ") }
        return result.prefix(1).uppercased() + result.dropFirst()
    }

    // MARK: - Rules

    /// bought already prepared even though the name sounds cooked
    private static let keepAsIs: Set<String> = ["baked beans", "refried beans", "roasted red peppers", "fried onions", "fried rice"]

    /// how it was cooked or served: not part of what you buy
    private static let prepWords: Set<String> = [
        "raw", "cooked", "boiled", "roasted", "grilled", "baked", "broiled", "braised", "stewed", "steamed",
        "fried", "pan-fried", "deep-fried", "stir-fried", "pan-broiled", "sauteed", "sautéed", "microwaved",
        "poached", "scrambled", "mashed", "heated", "reheated", "toasted", "prepared", "home-prepared",
        "drained", "enriched", "unenriched", "regular", "patty", "crumbles", "loaf", "hard-boiled",
        "soft-boiled", "simmered", "smothered", "flesh", "ns", "nfs",
    ]

    /// details that start this way are about cooking or serving ("skin not eaten", "without salt")
    private static let prepPrefixes = [
        "skin", "meat only", "meat and skin", "with salt", "without salt", "no salt", "without added salt",
        "with added salt", "fat added", "no added fat", "made with", "from fresh", "from frozen", "from canned",
        "dry heat", "moist heat", "broilers or fryers", "ns as to", "coated", "with sauce", "home recipe",
        "restaurant", "fast food",
    ]

    /// a detail that reads better in front ("Rice, white" → "White rice")
    private static let adjectives: Set<String> = [
        "ground", "white", "brown", "wild", "whole", "whole wheat", "whole-wheat", "whole grain", "whole-grain",
        "sweet", "red", "green", "yellow", "black", "skim", "nonfat", "low fat", "lowfat", "reduced fat",
        "extra lean", "lean", "large", "medium", "small", "baby", "fresh", "frozen", "canned", "dried",
    ]

    /// "Chicken, broilers or fryers, thigh" → "Chicken thigh"
    private static let cuts: Set<String> = ["breast", "thigh", "thighs", "wing", "wings", "drumstick", "leg", "tenderloin", "tenderloins"]

    private static func isPrep(_ part: String) -> Bool {
        let words = part.split(whereSeparator: { $0 == " " || $0 == "/" }).map(String.init)
        if !words.isEmpty, words.allSatisfy({ prepWords.contains($0) || $0 == "and" || $0 == "or" }) { return true }
        if let first = words.first, prepWords.contains(first), words.count <= 3 { return true } // "grilled with sauce"
        return prepPrefixes.contains { part.hasPrefix($0) } || part.contains("added")
    }

    /// "80% lean meat / 20% fat" → "80/20"
    private static func leanRatio(_ part: String) -> String? {
        guard let match = part.firstMatch(of: /(\d{2})% lean(?: meat)? \/ (\d{1,2})% fat/) else { return nil }
        return "\(match.1)/\(match.2)"
    }

    /// "Grilled chicken breast" → "chicken breast"; "Steamed white rice" → "white rice"
    private static func withoutLeadingPrep(_ head: String) -> String {
        var words = head.split(separator: " ").map(String.init)
        while words.count > 1, prepWords.contains(words[0].lowercased()) { words.removeFirst() }
        return words.joined(separator: " ")
    }
}
