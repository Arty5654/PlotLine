//
//  NutritionView.swift
//  PlotLine
//

import SwiftUI
import PhotosUI

// MARK: - Design tokens
private enum PLColor {
    static let surface        = Color(.secondarySystemBackground)
    static let cardBorder     = Color.black.opacity(0.06)
    static let textPrimary    = Color.primary
    static let textSecondary  = Color.secondary
    static let accent         = Color.blue
    static let success        = Color.green
    static let warning        = Color.orange
    static let danger         = Color.red
}
private enum PLSpacing {
    static let xs: CGFloat = 6
    static let sm: CGFloat = 10
    static let md: CGFloat = 16
    static let lg: CGFloat = 20
}
private enum PLRadius { static let md: CGFloat = 12 }
private struct CardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(PLSpacing.md)
            .background(PLColor.surface)
            .clipShape(RoundedRectangle(cornerRadius: PLRadius.md))
            .overlay(RoundedRectangle(cornerRadius: PLRadius.md).stroke(PLColor.cardBorder))
    }
}
private extension View { func plCard() -> some View { modifier(CardModifier()) } }

// MARK: - Main View
struct NutritionView: View {
    @Environment(\.colorScheme) var colorScheme
    @State private var selectedDate = Date()
    @State private var entry: NutritionEntry?
    @State private var isLoading = false

    // User data (favorites & saved meals)
    @State private var userData = NutritionUserData(favorites: [], savedMeals: [])

    // Meal type selection
    @State private var selectedMealType: FoodItem.MealType = Self.suggestedMealType()

    // Sheet states
    @State private var showManualEntry = false
    @State private var showBarcodeScanner = false
    @State private var showCamera = false
    @State private var showPhotoPicker = false
    @State private var isAnalyzingPhoto = false
    @State private var showFavorites = false
    @State private var showSavedMeals = false
    @State private var showCreateMeal = false
    @State private var showGoalSettings = false

    // Barcode lookup
    @State private var scannedFood: FoodItem?
    @State private var lastScannedBarcode: String = ""
    @State private var showBarcodeResult = false
    @State private var barcodeError: String?
    @State private var showBarcodeError = false
    @State private var isLookingUpBarcode = false

    // Photo analysis
    @State private var photoFoods: [FoodItem] = []
    @State private var showPhotoResults = false
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var capturedImage: UIImage?

    // Copy/Move
    @State private var foodToCopy: FoodItem?
    @State private var showCopyDatePicker = false
    @State private var copyTargetDate = Date()
    @State private var isMoveMode = false  // true = move, false = copy

    private let api = NutritionAPI.shared

    var body: some View {
        ScrollView {
            VStack(spacing: PLSpacing.lg) {
                datePicker
                dailySummaryCard
                mealTypePicker
                addFoodButtons
                quickAccessButtons
                foodLogSection
            }
            .padding(.horizontal, PLSpacing.lg)
            .padding(.bottom, PLSpacing.lg)
        }
        .navigationTitle("Nutrition")
        .onAppear { loadEntry(); loadUserData() }
        .onChange(of: selectedDate) { _ in loadEntry() }
        .sheet(isPresented: $showManualEntry) { ManualFoodEntrySheet { food in addFood(food) } }
        .sheet(isPresented: $showBarcodeScanner) { barcodeScannerSheet }
        .sheet(isPresented: $showBarcodeResult) { barcodeResultSheet }
        .sheet(isPresented: $showPhotoResults) { photoResultsSheet }
        .sheet(isPresented: $showFavorites) { favoritesSheet }
        .sheet(isPresented: $showSavedMeals) { savedMealsSheet }
        .sheet(isPresented: $showCreateMeal) { createMealSheet }
        .sheet(isPresented: $showCopyDatePicker) { copyDatePickerSheet }
        .sheet(isPresented: $showGoalSettings) {
            NutritionGoalView(goals: $userData.goals) { newGoal in
                if newGoal.calorieGoal <= 0 {
                    userData.goals = nil
                } else {
                    userData.goals = newGoal
                }
                persistUserData()
            }
        }
        .sheet(isPresented: $showCamera) { CameraPickerView { img in handleCapturedPhoto(img) } }
        .photosPicker(isPresented: $showPhotoPicker, selection: $selectedPhoto, matching: .images)
        .onChange(of: selectedPhoto) { item in
            guard let item = item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let img = UIImage(data: data) {
                    handleCapturedPhoto(img)
                }
            }
        }
        .alert("Error", isPresented: $showBarcodeError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(barcodeError ?? "Something went wrong")
        }
        .overlay {
            if isAnalyzingPhoto || isLookingUpBarcode {
                ProgressView(isAnalyzingPhoto ? "Analyzing food..." : "Looking up product...")
                    .padding(24)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    // MARK: - Date Picker
    private var adaptiveTextColor: Color {
        colorScheme == .dark ? .white : .blue
    }

    private var datePicker: some View {
        HStack {
            Button { selectedDate = Calendar.current.date(byAdding: .day, value: -1, to: selectedDate) ?? selectedDate } label: {
                Image(systemName: "chevron.left").font(.title3.bold())
                    .foregroundColor(adaptiveTextColor)
            }
            Spacer()
            if Calendar.current.isDateInToday(selectedDate) {
                Text("Today").font(.headline)
            } else {
                Text(selectedDate, format: .dateTime.weekday(.wide).month(.abbreviated).day())
                    .font(.headline)
            }
            Spacer()
            Button { selectedDate = Calendar.current.date(byAdding: .day, value: 1, to: selectedDate) ?? selectedDate } label: {
                Image(systemName: "chevron.right").font(.title3.bold())
                    .foregroundColor(adaptiveTextColor)
            }
        }
        .padding(.top, PLSpacing.sm)
    }

    // MARK: - Summary
    private var dailySummaryCard: some View {
        VStack(spacing: PLSpacing.sm) {
            // Goal settings button
            HStack {
                Spacer()
                Button { showGoalSettings = true } label: {
                    Image(systemName: "target")
                        .font(.subheadline)
                        .foregroundColor(userData.goals != nil ? PLColor.accent : PLColor.textSecondary)
                }
            }

            if let goal = userData.goals {
                // Calorie ring + numbers
                let eaten = entry?.totalCalories ?? 0
                let remaining = max(0, goal.calorieGoal - eaten)
                let progress = min(eaten / goal.calorieGoal, 1.0)

                ZStack {
                    Circle()
                        .stroke(Color.blue.opacity(0.15), lineWidth: 10)
                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(eaten > goal.calorieGoal ? PLColor.danger : PLColor.accent, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(.easeInOut, value: progress)

                    VStack(spacing: 2) {
                        Text("\(Int(remaining))")
                            .font(.system(size: 32, weight: .bold, design: .rounded))
                            .foregroundColor(eaten > goal.calorieGoal ? PLColor.danger : PLColor.accent)
                        Text("remaining")
                            .font(.caption)
                            .foregroundColor(PLColor.textSecondary)
                    }
                }
                .frame(width: 130, height: 130)

                HStack(spacing: PLSpacing.lg) {
                    calorieInfoColumn(value: Int(eaten), label: "Eaten", color: PLColor.accent)
                    calorieInfoColumn(value: Int(goal.calorieGoal), label: "Goal", color: PLColor.textSecondary)
                }
                .font(.caption)
                .padding(.top, 2)

                HStack(spacing: PLSpacing.sm) {
                    macroColumn(label: "Protein", grams: entry?.totalProtein ?? 0, goal: goal.proteinGoal, color: .red)
                    macroColumn(label: "Carbs", grams: entry?.totalCarbs ?? 0, goal: goal.carbsGoal, color: .orange)
                    macroColumn(label: "Fat", grams: entry?.totalFat ?? 0, goal: goal.fatGoal, color: .yellow)
                }
                .padding(.top, PLSpacing.xs)
            } else {
                // No goal set
                Text("\(Int(entry?.totalCalories ?? 0))")
                    .font(.system(size: 42, weight: .bold, design: .rounded))
                    .foregroundColor(PLColor.accent)
                Text("calories")
                    .font(.subheadline)
                    .foregroundColor(PLColor.textSecondary)

                HStack(spacing: PLSpacing.lg) {
                    macroColumnSimple(label: "Protein", grams: entry?.totalProtein ?? 0, color: .red)
                    macroColumnSimple(label: "Carbs", grams: entry?.totalCarbs ?? 0, color: .orange)
                    macroColumnSimple(label: "Fat", grams: entry?.totalFat ?? 0, color: .yellow)
                }
                .padding(.top, PLSpacing.xs)

                Button { showGoalSettings = true } label: {
                    Text("Set Calorie Goal")
                        .font(.caption.bold())
                        .foregroundColor(PLColor.accent)
                }
                .padding(.top, 4)
            }
        }
        .plCard()
    }

    private func calorieInfoColumn(value: Int, label: String, color: Color) -> some View {
        VStack(spacing: 2) {
            Text("\(value)")
                .font(.system(.subheadline, design: .rounded).bold())
                .foregroundColor(color)
            Text(label)
                .font(.caption2)
                .foregroundColor(PLColor.textSecondary)
        }
    }

    private func macroColumn(label: String, grams: Double, goal: Double, color: Color) -> some View {
        VStack(spacing: 4) {
            Text("\(Int(grams))g")
                .font(.system(.subheadline, design: .rounded).bold())
            if goal > 0 {
                ProgressView(value: min(grams / goal, 1.0))
                    .tint(grams > goal ? PLColor.danger : color)
                Text("/ \(Int(goal))g")
                    .font(.caption2)
                    .foregroundColor(PLColor.textSecondary)
            }
            Text(label)
                .font(.caption)
                .foregroundColor(PLColor.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(color.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func macroColumnSimple(label: String, grams: Double, color: Color) -> some View {
        VStack(spacing: 4) {
            Text("\(Int(grams))g")
                .font(.system(.title3, design: .rounded).bold())
            Text(label)
                .font(.caption)
                .foregroundColor(PLColor.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(color.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Meal Type Picker
    private var mealTypePicker: some View {
        Picker("Meal", selection: $selectedMealType) {
            ForEach(FoodItem.MealType.allCases, id: \.self) { type in
                Text(type.displayName).tag(type)
            }
        }
        .pickerStyle(.segmented)
    }

    // MARK: - Add Food Buttons
    private var addFoodButtons: some View {
        HStack(spacing: PLSpacing.sm) {
            addButton(icon: "pencil.line", label: "Manual") { showManualEntry = true }
            addButton(icon: "barcode.viewfinder", label: "Barcode") { showBarcodeScanner = true }
            photoMenuButton
        }
    }

    private var photoMenuButton: some View {
        Menu {
            Button { showCamera = true } label: {
                Label("Take Photo", systemImage: "camera")
            }
            Button { showPhotoPicker = true } label: {
                Label("Choose from Library", systemImage: "photo.on.rectangle")
            }
        } label: {
            VStack(spacing: 6) {
                Image(systemName: "camera.fill")
                    .font(.title2)
                Text("Photo")
                    .font(.caption.bold())
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(PLColor.accent.opacity(0.1))
            .foregroundColor(PLColor.accent)
            .clipShape(RoundedRectangle(cornerRadius: PLRadius.md))
        }
    }

    // MARK: - Quick Access (Favorites, Meals, Create Meal)
    private var quickAccessButtons: some View {
        HStack(spacing: PLSpacing.sm) {
            addButton(icon: "star.fill", label: "Favorites") { showFavorites = true }
            addButton(icon: "fork.knife", label: "Meals") { showSavedMeals = true }
            addButton(icon: "plus.rectangle.on.folder", label: "New Meal") { showCreateMeal = true }
        }
    }

    private func addButton(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.title2)
                Text(label)
                    .font(.caption.bold())
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(PLColor.accent.opacity(0.1))
            .foregroundColor(PLColor.accent)
            .clipShape(RoundedRectangle(cornerRadius: PLRadius.md))
        }
    }

    // MARK: - Food Log
    private var foodLogSection: some View {
        VStack(alignment: .leading, spacing: PLSpacing.sm) {
            Text("Food Log")
                .font(.headline)

            let foods = entry?.foods ?? []
            if foods.isEmpty {
                Text("No foods logged yet")
                    .foregroundColor(PLColor.textSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, PLSpacing.lg)
            } else {
                ForEach(FoodItem.MealType.allCases, id: \.self) { mealType in
                    let mealFoods = foods.filter { ($0.mealType ?? .snack) == mealType }
                    if !mealFoods.isEmpty {
                        mealSection(type: mealType, foods: mealFoods)
                    }
                }
            }
        }
        .plCard()
    }

    private func mealSection(type: FoodItem.MealType, foods: [FoodItem]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: type.icon)
                    .font(.caption)
                    .foregroundColor(PLColor.accent)
                Text(type.displayName)
                    .font(.subheadline.bold())
                    .foregroundColor(PLColor.accent)
                Spacer()
                let totalCal = foods.reduce(0) { $0 + $1.calories }
                Text("\(Int(totalCal)) cal")
                    .font(.caption.bold())
                    .foregroundColor(PLColor.textSecondary)
            }
            .padding(.top, 4)

            ForEach(foods) { food in
                foodRow(food)
            }

            Divider()
        }
    }

    private func foodRow(_ food: FoodItem) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(food.name).font(.subheadline.bold())
                    sourceIcon(food.source)
                }
                Text("\(food.servingSize) x \(food.servings, specifier: "%.1f")")
                    .font(.caption)
                    .foregroundColor(PLColor.textSecondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(Int(food.calories)) cal")
                    .font(.subheadline.bold())
                Text("P:\(Int(food.protein)) C:\(Int(food.carbs)) F:\(Int(food.fat))")
                    .font(.caption2)
                    .foregroundColor(PLColor.textSecondary)
            }

            // Action menu
            Menu {
                Button { toggleFavorite(food) } label: {
                    let isFav = userData.favorites.contains { $0.name == food.name }
                    Label(isFav ? "Unfavorite" : "Favorite", systemImage: isFav ? "star.slash" : "star")
                }
                Button {
                    foodToCopy = food
                    isMoveMode = false
                    copyTargetDate = selectedDate
                    showCopyDatePicker = true
                } label: {
                    Label("Copy to Date", systemImage: "doc.on.doc")
                }
                Button {
                    foodToCopy = food
                    isMoveMode = true
                    copyTargetDate = selectedDate
                    showCopyDatePicker = true
                } label: {
                    Label("Move to Date", systemImage: "arrow.right.doc.on.clipboard")
                }
                Divider()
                Button(role: .destructive) { deleteFood(food) } label: {
                    Label("Delete", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.subheadline)
                    .foregroundColor(PLColor.textSecondary)
            }
            .padding(.leading, 4)
        }
        .padding(.vertical, 6)
    }

    private func sourceIcon(_ source: FoodItem.FoodSource) -> some View {
        Group {
            switch source {
            case .manual: Image(systemName: "pencil").font(.caption2)
            case .barcode: Image(systemName: "barcode").font(.caption2)
            case .photo: Image(systemName: "camera").font(.caption2)
            }
        }
        .foregroundColor(PLColor.textSecondary)
    }

    // MARK: - Barcode Scanner Sheet
    private var barcodeScannerSheet: some View {
        NavigationView {
            BarcodeScannerView { barcode in
                showBarcodeScanner = false
                lookupBarcode(barcode)
            }
            .navigationBarTitle("Scan Barcode", displayMode: .inline)
            .navigationBarItems(leading: Button("Cancel") { showBarcodeScanner = false })
        }
    }

    // MARK: - Barcode Result Sheet
    private var barcodeResultSheet: some View {
        NavigationView {
            if let food = scannedFood {
                ServingsAdjustmentSheet(food: food, barcode: lastScannedBarcode) { adjusted in
                    addFood(adjusted)
                    showBarcodeResult = false
                }
            }
        }
    }

    // MARK: - Photo Results Sheet
    private var photoResultsSheet: some View {
        NavigationView {
            List {
                Section(header: Text("Detected Foods")) {
                    ForEach(photoFoods) { food in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(food.name).font(.subheadline.bold())
                                Text("\(food.servingSize) x \(food.servings, specifier: "%.1f")")
                                    .font(.caption).foregroundColor(.secondary)
                            }
                            Spacer()
                            Text("\(Int(food.calories)) cal")
                                .font(.subheadline)
                        }
                    }
                }
            }
            .navigationBarTitle("Food Analysis", displayMode: .inline)
            .navigationBarItems(
                leading: Button("Cancel") { showPhotoResults = false },
                trailing: Button("Add All") {
                    for food in photoFoods { addFood(food) }
                    showPhotoResults = false
                }
                .bold()
            )
        }
    }

    // MARK: - Favorites Sheet
    private var favoritesSheet: some View {
        NavigationView {
            List {
                if userData.favorites.isEmpty {
                    Text("No favorites yet. Tap the menu on any food to favorite it.")
                        .foregroundColor(.secondary)
                        .padding(.vertical)
                } else {
                    ForEach(userData.favorites) { food in
                        Button {
                            var newFood = food
                            newFood.id = UUID().uuidString
                            addFood(newFood)
                            showFavorites = false
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(food.name).font(.subheadline.bold())
                                        .foregroundColor(.primary)
                                    Text("\(food.servingSize) - \(Int(food.calories)) cal")
                                        .font(.caption).foregroundColor(.secondary)
                                }
                                Spacer()
                                Text("P:\(Int(food.protein)) C:\(Int(food.carbs)) F:\(Int(food.fat))")
                                    .font(.caption2).foregroundColor(.secondary)
                            }
                        }
                    }
                    .onDelete { indices in
                        userData.favorites.remove(atOffsets: indices)
                        persistUserData()
                    }
                }
            }
            .navigationBarTitle("Favorites", displayMode: .inline)
            .navigationBarItems(leading: Button("Done") { showFavorites = false })
        }
    }

    // MARK: - Saved Meals Sheet
    private var savedMealsSheet: some View {
        NavigationView {
            List {
                if userData.savedMeals.isEmpty {
                    Text("No saved meals yet. Create one with the \"New Meal\" button.")
                        .foregroundColor(.secondary)
                        .padding(.vertical)
                } else {
                    ForEach(userData.savedMeals) { meal in
                        Button {
                            for var food in meal.foods {
                                food.id = UUID().uuidString
                                addFood(food)
                            }
                            showSavedMeals = false
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(meal.name).font(.headline).foregroundColor(.primary)
                                Text("\(meal.foods.count) item\(meal.foods.count == 1 ? "" : "s") - \(Int(meal.totalCalories)) cal")
                                    .font(.caption).foregroundColor(.secondary)
                                Text("P:\(Int(meal.totalProtein))g  C:\(Int(meal.totalCarbs))g  F:\(Int(meal.totalFat))g")
                                    .font(.caption2).foregroundColor(.secondary)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                    .onDelete { indices in
                        userData.savedMeals.remove(atOffsets: indices)
                        persistUserData()
                    }
                }
            }
            .navigationBarTitle("Saved Meals", displayMode: .inline)
            .navigationBarItems(leading: Button("Done") { showSavedMeals = false })
        }
    }

    // MARK: - Create Meal Sheet
    private var createMealSheet: some View {
        CreateMealSheet(
            todayFoods: entry?.foods ?? [],
            onSave: { meal in
                userData.savedMeals.append(meal)
                persistUserData()
                showCreateMeal = false

                // Increment nutrition-meal-creator trophy
                let username = UserDefaults.standard.string(forKey: "loggedInUsername") ?? ""
                Task { await ProfileAPI.incrementTrophy(username: username, trophyId: "nutrition-meal-creator") }
            }
        )
    }

    // MARK: - Copy/Move Date Picker Sheet
    private var copyDatePickerSheet: some View {
        NavigationView {
            Form {
                Section(header: Text(isMoveMode ? "Move to Date" : "Copy to Date")) {
                    DatePicker("Target Date", selection: $copyTargetDate, displayedComponents: .date)
                        .accentColor(colorScheme == .dark ? .white : .blue)
                }
                if let food = foodToCopy {
                    Section(header: Text("Food")) {
                        Text(food.name).font(.subheadline.bold())
                        Text("\(Int(food.calories)) cal  P:\(Int(food.protein))g  C:\(Int(food.carbs))g  F:\(Int(food.fat))g")
                            .font(.caption).foregroundColor(.secondary)
                    }
                }
            }
            .navigationBarTitle(isMoveMode ? "Move Food" : "Copy Food", displayMode: .inline)
            .navigationBarItems(
                leading: Button("Cancel") { showCopyDatePicker = false },
                trailing: Button(isMoveMode ? "Move" : "Copy") {
                    if let food = foodToCopy {
                        copyOrMoveFood(food, to: copyTargetDate, move: isMoveMode)
                    }
                    showCopyDatePicker = false
                }
                .bold()
            )
        }
    }

    // MARK: - Data Operations

    private func loadEntry() {
        isLoading = true
        Task {
            let fetched = try? await api.fetchEntries(for: selectedDate)
            await MainActor.run {
                entry = fetched ?? NutritionEntry(date: selectedDate, foods: [])
                isLoading = false
            }
        }
    }

    private func loadUserData() {
        Task {
            if let data = try? await api.fetchUserData() {
                await MainActor.run { userData = data }
            }
        }
    }

    private func addFood(_ food: FoodItem) {
        if entry == nil {
            entry = NutritionEntry(date: selectedDate, foods: [])
        }
        var foodWithMeal = food
        if foodWithMeal.mealType == nil {
            foodWithMeal.mealType = selectedMealType
        }
        entry?.foods.append(foodWithMeal)
        saveEntry()

        // Increment nutrition-logger trophy
        let username = UserDefaults.standard.string(forKey: "loggedInUsername") ?? ""
        Task { await ProfileAPI.incrementTrophy(username: username, trophyId: "nutrition-logger") }
    }

    private func deleteFood(_ food: FoodItem) {
        entry?.foods.removeAll { $0.id == food.id }
        saveEntry()
    }

    private func saveEntry() {
        guard let entry = entry else { return }
        Task { try? await api.saveEntry(entry) }
    }

    private func toggleFavorite(_ food: FoodItem) {
        if let idx = userData.favorites.firstIndex(where: { $0.name == food.name }) {
            userData.favorites.remove(at: idx)
        } else {
            // Store a clean copy as a template
            var template = food
            template.id = UUID().uuidString
            userData.favorites.append(template)
        }
        persistUserData()
    }

    private func persistUserData() {
        Task { try? await api.saveUserData(userData) }
    }

    private func copyOrMoveFood(_ food: FoodItem, to targetDate: Date, move: Bool) {
        Task {
            // Fetch or create target date entry
            var targetEntry = (try? await api.fetchEntries(for: targetDate)) ?? NutritionEntry(date: targetDate, foods: [])

            var newFood = food
            newFood.id = UUID().uuidString
            targetEntry.foods.append(newFood)
            try? await api.saveEntry(targetEntry)

            if move {
                await MainActor.run { deleteFood(food) }
            }

            // Refresh if we copied to the currently viewed date
            if Calendar.current.isDate(targetDate, inSameDayAs: selectedDate) {
                await MainActor.run { loadEntry() }
            }
        }
    }

    private func lookupBarcode(_ barcode: String) {
        lastScannedBarcode = barcode
        isLookingUpBarcode = true
        Task {
            do {
                if let food = try await api.lookupBarcode(barcode) {
                    // Increment nutrition-barcode trophy
                    let username = UserDefaults.standard.string(forKey: "loggedInUsername") ?? ""
                    await ProfileAPI.incrementTrophy(username: username, trophyId: "nutrition-barcode")

                    await MainActor.run {
                        scannedFood = food
                        isLookingUpBarcode = false
                        showBarcodeResult = true
                    }
                } else {
                    await MainActor.run {
                        isLookingUpBarcode = false
                        barcodeError = "Product not found in database. Try manual entry."
                        showBarcodeError = true
                    }
                }
            } catch {
                await MainActor.run {
                    isLookingUpBarcode = false
                    barcodeError = "Lookup failed: \(error.localizedDescription)"
                    showBarcodeError = true
                }
            }
        }
    }

    private static func suggestedMealType() -> FoodItem.MealType {
        let hour = Calendar.current.component(.hour, from: Date())
        if hour < 11 { return .breakfast }
        if hour < 15 { return .lunch }
        if hour < 17 { return .snack }
        return .dinner
    }

    private func handleCapturedPhoto(_ image: UIImage) {
        showCamera = false
        showPhotoPicker = false
        isAnalyzingPhoto = true
        Task {
            do {
                let foods = try await api.analyzeFoodPhoto(image)
                await MainActor.run {
                    photoFoods = foods
                    isAnalyzingPhoto = false
                    if foods.isEmpty {
                        barcodeError = "Could not identify any food in the photo. Try again or use manual entry."
                        showBarcodeError = true
                    } else {
                        showPhotoResults = true
                    }
                }
            } catch {
                await MainActor.run {
                    isAnalyzingPhoto = false
                    barcodeError = "Photo analysis failed: \(error.localizedDescription)"
                    showBarcodeError = true
                }
            }
        }
    }
}

// MARK: - Create Meal Sheet
struct CreateMealSheet: View {
    let todayFoods: [FoodItem]
    let onSave: (SavedMeal) -> Void
    @Environment(\.dismiss) var dismiss

    @State private var mealName = ""
    @State private var selectedFoodIds: Set<String> = []

    // Manual add fields
    @State private var showAddManual = false
    @State private var manualName = ""
    @State private var manualServing = ""
    @State private var manualServings = "1"
    @State private var manualCal = ""
    @State private var manualProtein = ""
    @State private var manualCarbs = ""
    @State private var manualFat = ""
    @State private var extraFoods: [FoodItem] = []

    private var allAvailableFoods: [FoodItem] { todayFoods + extraFoods }

    private var selectedFoods: [FoodItem] {
        allAvailableFoods.filter { selectedFoodIds.contains($0.id) }
    }

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Meal Name")) {
                    TextField("e.g. Breakfast, Chicken Bowl", text: $mealName)
                }

                Section(header: Text("Select Foods")) {
                    if allAvailableFoods.isEmpty {
                        Text("No foods logged today. Add foods manually below.")
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(allAvailableFoods) { food in
                            Button {
                                if selectedFoodIds.contains(food.id) {
                                    selectedFoodIds.remove(food.id)
                                } else {
                                    selectedFoodIds.insert(food.id)
                                }
                            } label: {
                                HStack {
                                    Image(systemName: selectedFoodIds.contains(food.id) ? "checkmark.circle.fill" : "circle")
                                        .foregroundColor(selectedFoodIds.contains(food.id) ? .blue : .secondary)
                                    Text(food.name).foregroundColor(.primary)
                                    Spacer()
                                    Text("\(Int(food.calories)) cal").font(.caption).foregroundColor(.secondary)
                                }
                            }
                        }
                    }

                    Button { showAddManual = true } label: {
                        Label("Add Food Manually", systemImage: "plus.circle")
                    }
                }

                if !selectedFoods.isEmpty {
                    Section(header: Text("Meal Summary")) {
                        let totalCal = selectedFoods.reduce(0) { $0 + $1.calories }
                        let totalP = selectedFoods.reduce(0) { $0 + $1.protein }
                        let totalC = selectedFoods.reduce(0) { $0 + $1.carbs }
                        let totalF = selectedFoods.reduce(0) { $0 + $1.fat }
                        HStack {
                            Text("\(Int(totalCal)) cal").bold()
                            Spacer()
                            Text("P:\(Int(totalP))g  C:\(Int(totalC))g  F:\(Int(totalF))g")
                                .font(.caption).foregroundColor(.secondary)
                        }
                    }
                }
            }
            .navigationBarTitle("Create Meal", displayMode: .inline)
            .navigationBarItems(
                leading: Button("Cancel") { dismiss() },
                trailing: Button("Save") {
                    let meal = SavedMeal(name: mealName.trimmingCharacters(in: .whitespacesAndNewlines), foods: selectedFoods)
                    onSave(meal)
                }
                .bold()
                .disabled(mealName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || selectedFoods.isEmpty)
            )
            .sheet(isPresented: $showAddManual) {
                ManualFoodEntrySheet { food in
                    extraFoods.append(food)
                    selectedFoodIds.insert(food.id)
                }
            }
        }
    }
}

// MARK: - Manual Food Entry Sheet
struct ManualFoodEntrySheet: View {
    @Environment(\.dismiss) var dismiss
    let onSave: (FoodItem) -> Void

    @State private var name = ""
    @State private var servingSize = ""
    @State private var servings = "1"
    @State private var calories = ""
    @State private var protein = ""
    @State private var carbs = ""
    @State private var fat = ""

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Food Info")) {
                    TextField("Food name", text: $name)
                    TextField("Serving size (e.g. 1 cup, 100g)", text: $servingSize)
                    TextField("Number of servings", text: $servings)
                        .keyboardType(.decimalPad)
                }
                Section(header: Text("Nutrition per total servings")) {
                    TextField("Calories", text: $calories).keyboardType(.decimalPad)
                    TextField("Protein (g)", text: $protein).keyboardType(.decimalPad)
                    TextField("Carbs (g)", text: $carbs).keyboardType(.decimalPad)
                    TextField("Fat (g)", text: $fat).keyboardType(.decimalPad)
                }
            }
            .navigationBarTitle("Add Food", displayMode: .inline)
            .navigationBarItems(
                leading: Button("Cancel") { dismiss() },
                trailing: Button("Save") {
                    let food = FoodItem(
                        name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                        servingSize: servingSize.isEmpty ? "1 serving" : servingSize,
                        servings: Double(servings) ?? 1,
                        calories: Double(calories) ?? 0,
                        protein: Double(protein) ?? 0,
                        carbs: Double(carbs) ?? 0,
                        fat: Double(fat) ?? 0,
                        source: .manual
                    )
                    onSave(food)
                    dismiss()
                }
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            )
        }
    }
}

// MARK: - Servings Adjustment Sheet (for barcode scanned items)
struct ServingsAdjustmentSheet: View {
    let food: FoodItem
    var barcode: String = ""
    let onSave: (FoodItem) -> Void
    @Environment(\.dismiss) var dismiss

    @State private var servings: String = "1"

    private var multiplier: Double { (Double(servings) ?? 1) / food.servings }

    var body: some View {
        Form {
            Section(header: Text("Product")) {
                Text(food.name).font(.headline)
                Text("Serving: \(food.servingSize)").foregroundColor(.secondary)
                if !barcode.isEmpty {
                    HStack {
                        Image(systemName: "barcode")
                            .foregroundColor(.secondary)
                        Text(barcode)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            Section(header: Text("How many servings?")) {
                TextField("Servings", text: $servings)
                    .keyboardType(.decimalPad)
            }
            Section(header: Text("Estimated Nutrition")) {
                HStack { Text("Calories"); Spacer(); Text("\(Int(food.calories * multiplier))") }
                HStack { Text("Protein"); Spacer(); Text("\(Int(food.protein * multiplier))g") }
                HStack { Text("Carbs"); Spacer(); Text("\(Int(food.carbs * multiplier))g") }
                HStack { Text("Fat"); Spacer(); Text("\(Int(food.fat * multiplier))g") }
            }
        }
        .navigationBarTitle("Adjust Servings", displayMode: .inline)
        .navigationBarItems(
            leading: Button("Cancel") { dismiss() },
            trailing: Button("Add") {
                var adjusted = food
                let mult = multiplier
                adjusted.servings = Double(servings) ?? 1
                adjusted.calories = food.calories * mult
                adjusted.protein = food.protein * mult
                adjusted.carbs = food.carbs * mult
                adjusted.fat = food.fat * mult
                onSave(adjusted)
            }
            .bold()
        )
        .onAppear { servings = "\(food.servings)" }
    }
}

// MARK: - Camera Picker (wraps UIImagePickerController)
struct CameraPickerView: UIViewControllerRepresentable {
    let onImageCaptured: (UIImage) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onImageCaptured: onImageCaptured) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onImageCaptured: (UIImage) -> Void
        init(onImageCaptured: @escaping (UIImage) -> Void) { self.onImageCaptured = onImageCaptured }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage {
                onImageCaptured(image)
            }
            picker.dismiss(animated: true)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            picker.dismiss(animated: true)
        }
    }
}
