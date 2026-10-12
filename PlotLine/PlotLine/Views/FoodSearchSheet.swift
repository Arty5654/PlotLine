//
//  FoodSearchSheet.swift
//  PlotLine
//
//  Nutrition → Search. Results come from USDA: detailed generic foods first ("Beef, ground, 80% lean
//  meat / 20% fat, raw", "Pasta, cooked"), then store brands. Tap one to say how much you ate, in
//  grams, ounces, pounds or one of the food's own portions ("1 cup, cooked"), and add it.
//

import SwiftUI

/// one search result (values per 100 g; portions are household measures with their weight)
struct SearchFood: Decodable, Identifiable, Hashable {
    struct Per100: Decodable, Hashable {
        let calories: Double
        let protein: Double
        let carbs: Double
        let fat: Double
    }

    struct Portion: Decodable, Hashable {
        let label: String
        let grams: Double
    }

    let id: String
    let name: String
    let brand: String?
    let kind: String          // "generic" or "branded"
    let per100g: Per100
    let portions: [Portion]

    var isBranded: Bool { kind == "branded" }

    /// the food as logged, for this many grams; `amountLabel` describes the amount ("1 cup, cooked (140 g)")
    func foodItem(grams: Double, amountLabel: String) -> FoodItem {
        let f = grams / 100
        return FoodItem(name: brand.map { "\(name) (\($0))" } ?? name, servingSize: amountLabel, servings: 1,
                        calories: (per100g.calories * f).rounded(), protein: per100g.protein * f,
                        carbs: per100g.carbs * f, fat: per100g.fat * f, source: .search, brand: brand)
    }
}

struct FoodSearchSheet: View {
    /// e.g. "Add to Dinner" or "Add to Meal"
    var addLabel: String = "Add"
    let onSelect: (FoodItem) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var query = ""
    @State private var results: [SearchFood] = []
    @State private var isSearching = false
    @State private var hasSearched = false
    @State private var chosen: SearchFood?
    @State private var searchTask: Task<Void, Never>?

    /// `previewResults` opens with results already shown (Xcode previews)
    init(addLabel: String = "Add", previewQuery: String = "", previewResults: [SearchFood] = [],
         onSelect: @escaping (FoodItem) -> Void) {
        self.addLabel = addLabel
        self.onSelect = onSelect
        _query = State(initialValue: previewQuery)
        _results = State(initialValue: previewResults)
        _hasSearched = State(initialValue: !previewResults.isEmpty)
    }

    private var generic: [SearchFood] { results.filter { !$0.isBranded } }
    private var branded: [SearchFood] { results.filter(\.isBranded) }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                searchBar
                if isSearching && results.isEmpty {
                    Spacer()
                    ProgressView("Searching…")
                    Spacer()
                } else if results.isEmpty {
                    emptyState
                } else {
                    List {
                        if !generic.isEmpty {
                            Section {
                                ForEach(generic) { row($0) }
                            } header: {
                                Text("Foods")
                            } footer: {
                                Text("From USDA. Pick the one that matches how it was prepared (raw, cooked, dry) and, for meat, the lean %.")
                            }
                        }
                        if !branded.isEmpty {
                            Section("Brands") {
                                ForEach(branded) { row($0) }
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                    .scrollDismissesKeyboard(.immediately)
                }
            }
            .navigationTitle("Search Food")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
            .sheet(item: $chosen) { food in
                FoodAmountSheet(food: food, addLabel: addLabel) { item in
                    onSelect(item)
                    chosen = nil
                    dismiss()
                }
            }
            .onChange(of: query) { _, _ in scheduleSearch() }
        }
        .tint(PLColor.accent)
    }

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundColor(.secondary)
            TextField("e.g. ground beef 80/20, pasta cooked", text: $query)
                .textInputAutocapitalization(.never)
                .disableAutocorrection(true)
                .submitLabel(.search)
                .onSubmit { performSearch() }
            if isSearching { ProgressView().controlSize(.small) }
            if !query.isEmpty {
                Button { query = ""; results = []; hasSearched = false } label: {
                    Image(systemName: "xmark.circle.fill").foregroundColor(.secondary)
                }
                .accessibilityLabel("Clear search")
            }
        }
        .padding(12)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: hasSearched ? "magnifyingglass" : "fork.knife")
                .font(.largeTitle)
                .foregroundColor(.secondary)
            Text(hasSearched ? "No results found" : "Search for any food or product")
                .font(.headline)
                .foregroundColor(.secondary)
            Text("Details help: \"cooked\" or \"raw\", the lean % (\"80/20\"), or a brand.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, PLSpacing.lg)
            Spacer()
        }
    }

    private func row(_ food: SearchFood) -> some View {
        Button { chosen = food } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(food.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.leading)
                if let brand = food.brand {
                    Text(brand).font(.caption).foregroundColor(PLColor.tint)
                }
                Text("\(Int(food.per100g.calories)) cal per 100 g · P \(Int(food.per100g.protein))g · C \(Int(food.per100g.carbs))g · F \(Int(food.per100g.fat))g")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.vertical, 2)
        }
    }

    // MARK: - Searching

    private func scheduleSearch() {
        searchTask?.cancel()
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            results = []
            hasSearched = false
            return
        }
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 500_000_000) // wait until typing stops
            guard !Task.isCancelled else { return }
            performSearch()
        }
    }

    private func performSearch() {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        isSearching = true
        Task {
            do {
                let found = try await NutritionAPI.shared.searchFoods(text)
                guard text == query.trimmingCharacters(in: .whitespacesAndNewlines) else { return } // typed on
                results = found
                hasSearched = true
            } catch {
                hasSearched = false // a failed search isn't "no results"
                AppBanner.report("search foods", error, retry: { performSearch() })
            }
            isSearching = false
        }
    }
}

/// How much of a search result you ate.
struct FoodAmountSheet: View {
    let food: SearchFood
    let addLabel: String
    let onAdd: (FoodItem) -> Void

    @Environment(\.dismiss) private var dismiss

    enum Unit: Hashable {
        case grams, ounces, pounds
        case portion(SearchFood.Portion)

        func label(_ amount: Double) -> String {
            switch self {
            case .grams: return "g"
            case .ounces: return "oz"
            case .pounds: return "lb"
            case .portion(let p): return p.label
            }
        }

        var gramsEach: Double {
            switch self {
            case .grams: return 1
            case .ounces: return 28.3495
            case .pounds: return 453.592
            case .portion(let p): return p.grams
            }
        }
    }

    @State private var amount: Double
    @State private var unit: Unit

    init(food: SearchFood, addLabel: String, onAdd: @escaping (FoodItem) -> Void) {
        self.food = food
        self.addLabel = addLabel
        self.onAdd = onAdd
        // start from the food's own serving when it has one ("4 oz (112 g)", "1 cup, cooked"), else 100 g
        if let first = food.portions.first {
            _unit = State(initialValue: .portion(first))
            _amount = State(initialValue: 1)
        } else {
            _unit = State(initialValue: .grams)
            _amount = State(initialValue: 100)
        }
    }

    private var units: [Unit] { food.portions.map { .portion($0) } + [.grams, .ounces, .pounds] }
    private var grams: Double { max(0, amount) * unit.gramsEach }

    private var amountLabel: String {
        let n = amount.formatted(.number.precision(.fractionLength(0...2)))
        switch unit {
        case .grams: return "\(n) g"
        case .portion(let p):
            let weight = "\(Int(grams.rounded())) g"
            let withWeight = p.label.contains("(") ? p.label : "\(p.label) (\(weight))"
            return amount == 1 ? withWeight : "\(n) × \(withWeight)"
        default: return "\(n) \(unit.label(amount)) (\(Int(grams.rounded())) g)"
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(food.name).font(.headline)
                        if let brand = food.brand { Text(brand).font(.subheadline).foregroundColor(PLColor.tint) }
                    }
                }

                Section("How much?") {
                    HStack {
                        TextField("Amount", value: $amount, format: .number.precision(.fractionLength(0...2)))
                            .keyboardType(.decimalPad)
                            .frame(maxWidth: 90)
                            .textFieldStyle(.roundedBorder)
                            .accessibilityLabel("Amount")
                        Picker("Unit", selection: $unit) {
                            ForEach(units, id: \.self) { u in
                                Text(u.label(amount)).tag(u)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        Spacer(minLength: 0)
                    }
                    if unit != .grams {
                        Text("= \(Int(grams.rounded())) g").font(.caption).foregroundColor(.secondary)
                    }
                }

                Section("Nutrition") {
                    let item = food.foodItem(grams: grams, amountLabel: amountLabel)
                    HStack {
                        Text("\(Int(item.calories))").font(.title.bold())
                        Text("cal").foregroundColor(.secondary)
                        Spacer()
                        Text("P \(Int(item.protein))g · C \(Int(item.carbs))g · F \(Int(item.fat))g")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle("Add Food")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Back") { dismiss() } }
            }
            .safeAreaInset(edge: .bottom) {
                Button {
                    onAdd(food.foodItem(grams: grams, amountLabel: amountLabel))
                } label: {
                    Text(addLabel).frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryButton())
                .disabled(grams <= 0)
                .padding(PLSpacing.lg)
                .background(.bar)
            }
        }
        .tint(PLColor.accent)
    }
}
