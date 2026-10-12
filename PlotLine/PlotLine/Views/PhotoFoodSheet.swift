//
//  PhotoFoodSheet.swift
//  PlotLine
//
//  After taking (or picking) a photo of a meal: add an optional note, analyze, then review what
//  was found — change how many grams of each, remove anything wrong — and add it to the meal.
//

import SwiftUI

struct PhotoFoodSheet: View {
    let image: UIImage
    let mealType: FoodItem.MealType
    /// gets the foods to log
    let onAdd: ([FoodItem]) -> Void

    @Environment(\.dismiss) private var dismiss

    private enum Stage { case note, analyzing, results, failed(String) }
    @State private var stage: Stage = .note
    @State private var note = ""
    @State private var foods: [PhotoFood] = []
    @FocusState private var noteFocused: Bool

    /// `previewFoods` opens straight on the results (Xcode previews)
    init(image: UIImage, mealType: FoodItem.MealType, previewFoods: [PhotoFood]? = nil, onAdd: @escaping ([FoodItem]) -> Void) {
        self.image = image
        self.mealType = mealType
        self.onAdd = onAdd
        if let previewFoods {
            _foods = State(initialValue: previewFoods)
            _stage = State(initialValue: .results)
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                switch stage {
                case .note: noteView
                case .analyzing: analyzingView
                case .results: resultsView
                case .failed(let message): failedView(message)
                }
            }
            .navigationTitle("Meal Photo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .tint(PLColor.accent)
    }

    // MARK: - Before analyzing

    private var photo: some View {
        Image(uiImage: image)
            .resizable()
            .scaledToFill()
            .frame(height: 200)
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .accessibilityLabel("Your meal photo")
    }

    private var noteView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: PLSpacing.md) {
                photo
                Text("Anything the photo can't show? (optional)")
                    .font(.subheadline.weight(.semibold))
                TextField("e.g. chicken thigh, cooked in olive oil; 2 cups of rice", text: $note, axis: .vertical)
                    .lineLimit(2...4)
                    .textFieldStyle(.roundedBorder)
                    .focused($noteFocused)
                Text("Hidden ingredients (oil, butter, sauces) and portion sizes make the biggest difference.")
                    .font(.caption)
                    .foregroundColor(PLColor.textSecondary)
                Button(action: analyze) {
                    Label("Analyze", systemImage: "sparkles")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryButton())
                .padding(.top, PLSpacing.sm)
            }
            .padding(PLSpacing.lg)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private var analyzingView: some View {
        VStack(spacing: PLSpacing.md) {
            photo.padding(.horizontal, PLSpacing.lg)
            ProgressView()
            Text("Finding the foods and weighing each portion…")
                .foregroundColor(PLColor.textSecondary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .padding(.top, PLSpacing.lg)
    }

    private func failedView(_ message: String) -> some View {
        VStack(spacing: PLSpacing.md) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 44))
                .foregroundColor(.orange)
            Text(message)
                .multilineTextAlignment(.center)
            Button("Try Again", action: analyze)
                .buttonStyle(PrimaryButton())
            Button("Edit Note") { stage = .note }
                .foregroundColor(PLColor.textSecondary)
        }
        .padding(PLSpacing.lg)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Results

    private var totals: (cal: Double, p: Double, c: Double, f: Double) {
        let items = foods.map { $0.foodItem(mealType: mealType) }
        return (items.reduce(0) { $0 + $1.calories }, items.reduce(0) { $0 + $1.protein },
                items.reduce(0) { $0 + $1.carbs }, items.reduce(0) { $0 + $1.fat })
    }

    private var resultsView: some View {
        List {
            Section {
                HStack(alignment: .firstTextBaseline) {
                    Text("\(Int(totals.cal))").font(.largeTitle.bold())
                    Text("cal").foregroundColor(PLColor.textSecondary)
                    Spacer()
                    Text("P \(Int(totals.p))g · C \(Int(totals.c))g · F \(Int(totals.f))g")
                        .font(.subheadline)
                        .foregroundColor(PLColor.textSecondary)
                }
            } footer: {
                Text("Adding to \(mealType.displayName). Change the grams if a portion looks off, or swipe to remove a food.")
            }

            Section("Found in your photo") {
                ForEach($foods) { $food in
                    foodRow($food)
                }
                .onDelete { foods.remove(atOffsets: $0) }
            }
        }
        .listStyle(.insetGrouped)
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom) {
            Button(action: add) {
                Text("Add \(foods.count) item\(foods.count == 1 ? "" : "s") to \(mealType.displayName)")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(PrimaryButton())
            .disabled(foods.isEmpty)
            .padding(PLSpacing.lg)
            .background(.bar)
        }
    }

    private func foodRow(_ food: Binding<PhotoFood>) -> some View {
        let item = food.wrappedValue.foodItem(mealType: mealType)
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(food.wrappedValue.name).font(.headline)
                Spacer()
                Text("\(Int(item.calories)) cal").font(.subheadline.weight(.semibold))
            }
            HStack(spacing: PLSpacing.sm) {
                TextField("g", value: food.grams, format: .number.precision(.fractionLength(0)))
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 64)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("Grams of \(food.wrappedValue.name)")
                Text("g").foregroundColor(PLColor.textSecondary)
                Stepper("", value: food.grams, in: 0...3000, step: 10)
                    .labelsHidden()
                Spacer()
                Text("P \(Int(item.protein)) · C \(Int(item.carbs)) · F \(Int(item.fat))")
                    .font(.caption)
                    .foregroundColor(PLColor.textSecondary)
            }
            Text(source(of: food.wrappedValue))
                .font(.caption2)
                .foregroundColor(PLColor.textSecondary)
                .lineLimit(2)
        }
        .padding(.vertical, 4)
    }

    private func source(of food: PhotoFood) -> String {
        let portion = food.servingSize.contains("(") ? "Looks like " + food.servingSize + ". " : ""
        if food.basis == "usda", let usda = food.usdaName { return portion + "USDA: \(usda)" }
        return portion + "Estimated (no close USDA match)"
    }

    // MARK: - Actions

    private func analyze() {
        noteFocused = false
        stage = .analyzing
        Task {
            do {
                let found = try await NutritionAPI.shared.analyzeFoodPhoto(image, note: note)
                foods = found
                stage = found.isEmpty
                    ? .failed("Couldn't find any food in this photo. Try another angle, add a note, or enter it manually.")
                    : .results
            } catch let limit as AILimitError {
                stage = .failed(limit.message)
            } catch {
                stage = .failed("Couldn't analyze the photo. Check your connection and try again.")
            }
        }
    }

    private func add() {
        let items = foods.filter { $0.grams > 0 }.map { $0.foodItem(mealType: mealType) }
        guard !items.isEmpty else { return }
        onAdd(items)
        dismiss()
    }
}
