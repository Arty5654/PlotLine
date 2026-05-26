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
    @State private var showFoodSearch = false
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

    // Edit logged food
    @State private var foodToEdit: FoodItem?

    // Add to grocery list
    @State private var foodToAddToGrocery: FoodItem?
    @State private var showGroceryPicker = false

    // Shop for meal
    @State private var isShoppingForMeal = false
    @State private var shopMealSuccess: String?
    @State private var showShopMealAlert = false

    // Edit saved meal
    @State private var mealToEdit: SavedMeal?

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
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            loadEntry(); loadUserData()
        }
        .sheet(isPresented: $showFoodSearch) { FoodSearchSheet { food in addFood(food) } }
        .sheet(isPresented: $showManualEntry) { ManualFoodEntrySheet { food in addFood(food) } }
        .sheet(item: $foodToEdit) { food in
            NavigationView {
                ServingsAdjustmentSheet(food: food) { updated in
                    updateFood(updated)
                    foodToEdit = nil
                }
            }
        }
        .sheet(isPresented: $showBarcodeScanner) { barcodeScannerSheet }
        .sheet(item: $scannedFood) { food in
            NavigationView {
                ServingsAdjustmentSheet(food: food, barcode: lastScannedBarcode) { adjusted in
                    addFood(adjusted)
                    scannedFood = nil
                }
            }
        }
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
                    let username = UserDefaults.standard.string(forKey: "loggedInUsername") ?? ""
                    Task { await ProfileAPI.incrementTrophy(username: username, trophyId: "nutrition-goal-setter") }
                }
                persistUserData()
            }
        }
        .sheet(isPresented: $showGroceryPicker) {
            if let food = foodToAddToGrocery {
                AddFoodToGrocerySheet(food: food)
            }
        }
        .alert("Grocery List Created", isPresented: $showShopMealAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(shopMealSuccess ?? "")
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
                        .foregroundColor(userData.goals != nil ? adaptiveTextColor : PLColor.textSecondary)
                }
            }

            if let goal = userData.goals {
                // Calorie ring + numbers
                let eaten = entry?.totalCalories ?? 0
                let remaining = max(0, goal.calorieGoal - eaten)
                let progress = min(eaten / goal.calorieGoal, 1.0)

                ZStack {
                    Circle()
                        .stroke(adaptiveTextColor.opacity(0.15), lineWidth: 10)
                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(eaten > goal.calorieGoal ? PLColor.danger : PLColor.accent, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(.easeInOut, value: progress)

                    VStack(spacing: 2) {
                        Text("\(Int(remaining))")
                            .font(.system(size: 32, weight: .bold, design: .rounded))
                            .foregroundColor(eaten > goal.calorieGoal ? PLColor.danger : adaptiveTextColor)
                        Text("remaining")
                            .font(.caption)
                            .foregroundColor(PLColor.textSecondary)
                    }
                }
                .frame(width: 130, height: 130)

                HStack(spacing: PLSpacing.lg) {
                    calorieInfoColumn(value: Int(eaten), label: "Eaten", color: adaptiveTextColor)
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
                    .foregroundColor(adaptiveTextColor)
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
                        .foregroundColor(adaptiveTextColor)
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
            addButton(icon: "magnifyingglass", label: "Search") { showFoodSearch = true }
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
            .background(adaptiveTextColor.opacity(0.1))
            .foregroundColor(adaptiveTextColor)
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
            .background(adaptiveTextColor.opacity(0.1))
            .foregroundColor(adaptiveTextColor)
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
                    .foregroundColor(adaptiveTextColor)
                Text(type.displayName)
                    .font(.subheadline.bold())
                    .foregroundColor(adaptiveTextColor)
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
            Button {
                foodToEdit = food
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(food.name).font(.subheadline.bold())
                        sourceIcon(food.source)
                    }
                    Text("\(food.servingSize) x \(food.servings, specifier: "%.1f")")
                        .font(.caption)
                        .foregroundColor(PLColor.textSecondary)
                }
            }
            .buttonStyle(.plain)

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
                Button {
                    foodToEdit = food
                } label: {
                    Label("Edit", systemImage: "pencil")
                }
                Button { toggleFavorite(food) } label: {
                    let isFav = userData.favorites.contains { $0.name == food.name }
                    Label(isFav ? "Unfavorite" : "Favorite", systemImage: isFav ? "star.slash" : "star")
                }
                Button {
                    foodToAddToGrocery = food
                    showGroceryPicker = true
                } label: {
                    Label("Add to Grocery List", systemImage: "cart.badge.plus")
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
            case .search: Image(systemName: "magnifyingglass").font(.caption2)
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
                    addFoods(photoFoods)
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
                            addFoods(meal.foods)
                            showSavedMeals = false
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(meal.name).font(.headline).foregroundColor(.primary)
                                Text("\(meal.foods.count) item\(meal.foods.count == 1 ? "" : "s") · \(Int(meal.totalCalories)) cal")
                                    .font(.caption).foregroundColor(.secondary)
                                Text("P:\(Int(meal.totalProtein))g  C:\(Int(meal.totalCarbs))g  F:\(Int(meal.totalFat))g")
                                    .font(.caption2).foregroundColor(.secondary)
                            }
                            .padding(.vertical, 4)
                        }
                        .buttonStyle(.plain)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                if let idx = userData.savedMeals.firstIndex(where: { $0.id == meal.id }) {
                                    userData.savedMeals.remove(at: idx)
                                    persistUserData()
                                }
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                            Button {
                                shopForMeal(meal)
                            } label: {
                                Label("Shop", systemImage: "cart.badge.plus")
                            }
                            .tint(.green)
                            .disabled(isShoppingForMeal)
                            Button {
                                mealToEdit = meal
                            } label: {
                                Label("Edit", systemImage: "pencil")
                            }
                            .tint(.blue)
                        }
                    }
                }
            }
            .navigationBarTitle("Saved Meals", displayMode: .inline)
            .navigationBarItems(leading: Button("Done") { showSavedMeals = false })
            .sheet(item: $mealToEdit) { meal in
                CreateMealSheet(
                    todayFoods: entry?.foods ?? [],
                    favorites: userData.favorites,
                    editingMeal: meal,
                    onSave: { updated in
                        if let idx = userData.savedMeals.firstIndex(where: { $0.id == meal.id }) {
                            var saved = updated
                            saved.id = meal.id
                            userData.savedMeals[idx] = saved
                        }
                        persistUserData()
                        mealToEdit = nil
                    }
                )
            }
        }
    }

    // MARK: - Create Meal Sheet
    private var createMealSheet: some View {
        CreateMealSheet(
            todayFoods: entry?.foods ?? [],
            favorites: userData.favorites,
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

    // MARK: - Grocery Integration

    private func shopForMeal(_ meal: SavedMeal) {
        guard !isShoppingForMeal else { return }
        isShoppingForMeal = true
        Task {
            do {
                let listId = try await GroceryListAPI.createGroceryList(name: meal.name)
                let trimmedId = listId.trimmingCharacters(in: .whitespacesAndNewlines)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
                guard let listUUID = UUID(uuidString: trimmedId) else {
                    await MainActor.run { isShoppingForMeal = false }
                    return
                }
                for food in meal.foods {
                    let item = GroceryItem(
                        listId: listUUID,
                        id: UUID(),
                        name: food.name,
                        quantity: 1,
                        checked: false
                    )
                    try await GroceryListAPI.addItem(listId: trimmedId, item: item)
                }
                await MainActor.run {
                    isShoppingForMeal = false
                    shopMealSuccess = "Added \(meal.foods.count) item\(meal.foods.count == 1 ? "" : "s") to \"\(meal.name)\" grocery list."
                    showShopMealAlert = true
                }
            } catch {
                await MainActor.run { isShoppingForMeal = false }
            }
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
                writeNutritionToWidget()
            }
        }
    }

    private func writeNutritionToWidget() {
        guard Calendar.current.isDateInToday(selectedDate) else { return }
        let e = entry
        let g = userData.goals
        WidgetDataWriter.writeNutrition(
            calories:    e?.totalCalories ?? 0,
            protein:     e?.totalProtein  ?? 0,
            carbs:       e?.totalCarbs    ?? 0,
            fat:         e?.totalFat      ?? 0,
            calorieGoal: g?.calorieGoal   ?? 0,
            proteinGoal: g?.proteinGoal   ?? 0,
            carbsGoal:   g?.carbsGoal     ?? 0,
            fatGoal:     g?.fatGoal       ?? 0
        )
        WidgetDataWriter.reloadWidgets()
    }

    private func loadUserData() {
        Task {
            if let data = try? await api.fetchUserData() {
                await MainActor.run {
                    userData = data
                    writeNutritionToWidget()
                }
            }
        }
    }

    private func addFood(_ food: FoodItem) {
        addFoods([food])
    }

    // Appends all foods and saves exactly once — avoids the race condition where
    // looping addFood() fires concurrent PUTs that overwrite each other on the server.
    private func addFoods(_ foods: [FoodItem]) {
        if entry == nil {
            entry = NutritionEntry(date: selectedDate, foods: [])
        }
        for food in foods {
            var f = food
            f.id = UUID().uuidString
            if f.mealType == nil { f.mealType = selectedMealType }
            entry?.foods.append(f)
        }
        saveEntry()
        writeNutritionToWidget()

        let username = UserDefaults.standard.string(forKey: "loggedInUsername") ?? ""
        Task { await ProfileAPI.incrementTrophy(username: username, trophyId: "nutrition-logger") }
        checkDailyNutritionTrophies()
    }

    private func deleteFood(_ food: FoodItem) {
        entry?.foods.removeAll { $0.id == food.id }
        saveEntry()
        writeNutritionToWidget()
        checkDailyNutritionTrophies()
    }

    private func updateFood(_ updated: FoodItem) {
        guard let idx = entry?.foods.firstIndex(where: { $0.id == updated.id }) else { return }
        entry?.foods[idx] = updated
        saveEntry()
        writeNutritionToWidget()
        checkDailyNutritionTrophies()
    }

    private func saveEntry() {
        guard let entry = entry else { return }
        Task { try? await api.saveEntry(entry) }
    }

    private func checkDailyNutritionTrophies() {
        guard Calendar.current.isDateInToday(selectedDate) else { return }
        let username = UserDefaults.standard.string(forKey: "loggedInUsername") ?? ""
        guard !username.isEmpty else { return }

        let todayStr = {
            let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
            return f.string(from: Date())
        }()

        let foods = entry?.foods ?? []

        // Streak: first time logging food today
        if !foods.isEmpty {
            let streakKey = "nutritionStreakDate_\(username)"
            if UserDefaults.standard.string(forKey: streakKey) != todayStr {
                UserDefaults.standard.set(todayStr, forKey: streakKey)
                Task { await ProfileAPI.incrementTrophy(username: username, trophyId: "nutrition-streak") }
            }
        }

        // Under goal: logged food and total calories ≤ calorie goal
        if let goal = userData.goals, goal.calorieGoal > 0, !foods.isEmpty {
            let total = entry?.totalCalories ?? 0
            if total > 0 && total <= goal.calorieGoal {
                let underGoalKey = "nutritionUnderGoalDate_\(username)"
                if UserDefaults.standard.string(forKey: underGoalKey) != todayStr {
                    UserDefaults.standard.set(todayStr, forKey: underGoalKey)
                    Task { await ProfileAPI.incrementTrophy(username: username, trophyId: "nutrition-under-goal") }
                }
            }
        }
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
            var targetEntry = (try? await api.fetchEntries(for: targetDate)) ?? NutritionEntry(date: targetDate, foods: [])
            var newFood = food
            newFood.id = UUID().uuidString
            targetEntry.foods.append(newFood)

            do {
                try await api.saveEntry(targetEntry)
                if move {
                    await MainActor.run { deleteFood(food) }
                }
            } catch {
                // Save failed — leave source untouched
            }

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

// MARK: - Create / Edit Meal Sheet
struct CreateMealSheet: View {
    let todayFoods: [FoodItem]
    let favorites: [FoodItem]
    var editingMeal: SavedMeal? = nil
    let onSave: (SavedMeal) -> Void
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme
    private var adaptiveTextColor: Color { colorScheme == .dark ? .white : .blue }
    private var isEditing: Bool { editingMeal != nil }

    @State private var mealName = ""
    @State private var selectedFoodIds: Set<String> = []
    @State private var foodBeingEdited: FoodItem?

    // Add food options
    @State private var showAddManual = false
    @State private var showAddSearch = false
    @State private var showAddBarcode = false
    @State private var scannedFood: FoodItem?
    @State private var manualName = ""
    @State private var manualServing = ""
    @State private var manualServings = "1"
    @State private var manualCal = ""
    @State private var manualProtein = ""
    @State private var manualCarbs = ""
    @State private var manualFat = ""
    @State private var extraFoods: [FoodItem] = []

    private var selectedFoods: [FoodItem] {
        (todayFoods + favorites + extraFoods).filter { selectedFoodIds.contains($0.id) }
    }

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Meal Name")) {
                    TextField("e.g. Breakfast, Chicken Bowl", text: $mealName)
                        .tint(adaptiveTextColor)
                }

                if !todayFoods.isEmpty {
                    Section(header: Text("Today's Log")) {
                        ForEach(todayFoods) { food in foodToggleRow(food) }
                    }
                }

                if !favorites.isEmpty {
                    Section(header: Text("Favorites")) {
                        ForEach(favorites) { food in foodToggleRow(food) }
                    }
                }

                if !extraFoods.isEmpty {
                    Section(header: Text(isEditing ? "Meal Foods" : "Added")) {
                        ForEach(extraFoods) { food in
                            if isEditing {
                                mealFoodEditRow(food)
                            } else {
                                foodToggleRow(food)
                            }
                        }
                    }
                }

                if todayFoods.isEmpty && favorites.isEmpty && extraFoods.isEmpty {
                    Section {
                        Text("Use the button below to add foods to your meal.")
                            .foregroundColor(.secondary)
                    }
                }

                Section {
                    Menu {
                        Button { showAddSearch = true } label: {
                            Label("Search Food", systemImage: "magnifyingglass")
                        }
                        Button { showAddBarcode = true } label: {
                            Label("Scan Barcode", systemImage: "barcode.viewfinder")
                        }
                        Button { showAddManual = true } label: {
                            Label("Enter Manually", systemImage: "pencil.line")
                        }
                    } label: {
                        Label("Add Food", systemImage: "plus.circle")
                            .foregroundColor(adaptiveTextColor)
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
            .navigationBarTitle(isEditing ? "Edit Meal" : "Create Meal", displayMode: .inline)
            .navigationBarItems(
                leading: Button("Cancel") { dismiss() },
                trailing: Button(isEditing ? "Update" : "Save") {
                    let meal = SavedMeal(name: mealName.trimmingCharacters(in: .whitespacesAndNewlines), foods: selectedFoods)
                    onSave(meal)
                }
                .bold()
                .disabled(mealName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || selectedFoods.isEmpty)
            )
            .onAppear {
                guard let meal = editingMeal else { return }
                mealName = meal.name
                extraFoods = meal.foods
                selectedFoodIds = Set(meal.foods.map { $0.id })
            }
            .sheet(isPresented: $showAddManual) {
                ManualFoodEntrySheet { food in
                    extraFoods.append(food)
                    selectedFoodIds.insert(food.id)
                }
            }
            .sheet(isPresented: $showAddSearch) {
                FoodSearchSheet { food in
                    extraFoods.append(food)
                    selectedFoodIds.insert(food.id)
                }
            }
            .sheet(isPresented: $showAddBarcode) {
                NavigationView {
                    BarcodeScannerView { barcode in
                        showAddBarcode = false
                        lookupBarcode(barcode)
                    }
                    .navigationBarTitle("Scan Barcode", displayMode: .inline)
                    .navigationBarItems(leading: Button("Cancel") { showAddBarcode = false })
                }
            }
            .sheet(item: $scannedFood) { food in
                NavigationView {
                    ServingsAdjustmentSheet(food: food) { adjusted in
                        extraFoods.append(adjusted)
                        selectedFoodIds.insert(adjusted.id)
                        scannedFood = nil
                    }
                }
            }
            .sheet(item: $foodBeingEdited) { food in
                NavigationView {
                    ServingsAdjustmentSheet(food: food) { updated in
                        if let idx = extraFoods.firstIndex(where: { $0.id == food.id }) {
                            extraFoods[idx] = updated
                            selectedFoodIds.insert(updated.id)
                        }
                        foodBeingEdited = nil
                    }
                }
            }
        }
    }

    private func foodToggleRow(_ food: FoodItem) -> some View {
        Button {
            if selectedFoodIds.contains(food.id) {
                selectedFoodIds.remove(food.id)
            } else {
                selectedFoodIds.insert(food.id)
            }
        } label: {
            HStack {
                Image(systemName: selectedFoodIds.contains(food.id) ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(selectedFoodIds.contains(food.id) ? adaptiveTextColor : .secondary)
                Text(food.name).foregroundColor(.primary)
                Spacer()
                Text("\(Int(food.calories)) cal").font(.caption).foregroundColor(.secondary)
            }
        }
    }

    private func mealFoodEditRow(_ food: FoodItem) -> some View {
        HStack(spacing: 12) {
            Button {
                if selectedFoodIds.contains(food.id) {
                    selectedFoodIds.remove(food.id)
                } else {
                    selectedFoodIds.insert(food.id)
                }
            } label: {
                Image(systemName: selectedFoodIds.contains(food.id) ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(selectedFoodIds.contains(food.id) ? adaptiveTextColor : .secondary)
                    .font(.title3)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 2) {
                Text(food.name)
                    .font(.subheadline)
                    .foregroundColor(.primary)
                    .lineLimit(1)
                Text("\(food.servingSize) × \(food.servings, specifier: "%.1f")  ·  \(Int(food.calories)) cal")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Button {
                foodBeingEdited = food
            } label: {
                Image(systemName: "pencil.circle")
                    .font(.title3)
                    .foregroundColor(adaptiveTextColor)
            }
            .buttonStyle(.plain)
        }
    }

    private func lookupBarcode(_ barcode: String) {
        Task {
            if let food = try? await NutritionAPI.shared.lookupBarcode(barcode) {
                await MainActor.run { scannedFood = food }
            }
        }
    }
}

// MARK: - Food Search Sheet
struct FoodSearchSheet: View {
    let onSelect: (FoodItem) -> Void
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme
    private var adaptiveTextColor: Color { colorScheme == .dark ? .white : .blue }

    @State private var query = ""
    @State private var results: [FoodItem] = []
    @State private var isSearching = false
    @State private var hasSearched = false
    @State private var selectedFood: FoodItem?
    @State private var showServingsSheet = false

    private let api = NutritionAPI.shared

    // Debounce: only search after user stops typing
    @State private var searchTask: Task<Void, Never>?

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Search bar
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    TextField("Search foods (e.g. chicken, Big Mac...)", text: $query)
                        .textInputAutocapitalization(.never)
                        .disableAutocorrection(true)
                        .submitLabel(.search)
                        .onSubmit { performSearch() }
                        .tint(adaptiveTextColor)
                    if !query.isEmpty {
                        Button { query = ""; results = []; hasSearched = false } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding(12)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .padding(.horizontal)
                .padding(.top, 8)

                // Results
                if isSearching {
                    Spacer()
                    ProgressView("Searching...")
                    Spacer()
                } else if results.isEmpty && hasSearched {
                    Spacer()
                    VStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .font(.largeTitle)
                            .foregroundColor(.secondary)
                        Text("No results found")
                            .font(.headline)
                            .foregroundColor(.secondary)
                        Text("Try a different search term")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                } else if results.isEmpty {
                    Spacer()
                    VStack(spacing: 8) {
                        Image(systemName: "fork.knife")
                            .font(.largeTitle)
                            .foregroundColor(.secondary)
                        Text("Search for any food or product")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                } else {
                    List {
                        ForEach(results) { food in
                            Button {
                                selectedFood = food
                                showServingsSheet = true
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(food.name)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundColor(.primary)
                                        .lineLimit(2)
                                    Text(food.servingSize)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    HStack(spacing: 12) {
                                        Text("\(Int(food.calories)) cal")
                                            .font(.caption.bold())
                                        Text("P: \(Int(food.protein))g")
                                            .font(.caption)
                                        Text("C: \(Int(food.carbs))g")
                                            .font(.caption)
                                        Text("F: \(Int(food.fat))g")
                                            .font(.caption)
                                    }
                                    .foregroundColor(.secondary)
                                }
                                .padding(.vertical, 4)
                            }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationBarTitle("Search Food", displayMode: .inline)
            .navigationBarItems(leading: Button("Cancel") { dismiss() })
            .sheet(isPresented: $showServingsSheet) {
                if let food = selectedFood {
                    NavigationView {
                        ServingsAdjustmentSheet(food: food) { adjusted in
                            onSelect(adjusted)
                            showServingsSheet = false
                        }
                    }
                }
            }
            .onChange(of: query) { _ in
                // Debounce: wait 500ms after typing stops before searching
                searchTask?.cancel()
                guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    results = []
                    hasSearched = false
                    return
                }
                searchTask = Task {
                    try? await Task.sleep(nanoseconds: 500_000_000)
                    guard !Task.isCancelled else { return }
                    await MainActor.run { performSearch() }
                }
            }
        }
    }

    private func performSearch() {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        isSearching = true
        Task {
            do {
                let foods = try await api.searchFoods(trimmed)
                await MainActor.run {
                    results = foods
                    isSearching = false
                    hasSearched = true
                }
            } catch {
                await MainActor.run {
                    results = []
                    isSearching = false
                    hasSearched = true
                }
            }
        }
    }
}

// MARK: - Manual Food Entry Sheet
struct ManualFoodEntrySheet: View {
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme
    private var adaptiveTextColor: Color { colorScheme == .dark ? .white : .blue }
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
                    TextField("Food name", text: $name).tint(adaptiveTextColor)
                    TextField("Serving size (e.g. 1 cup, 100g)", text: $servingSize).tint(adaptiveTextColor)
                    TextField("Number of servings", text: $servings)
                        .keyboardType(.decimalPad).tint(adaptiveTextColor)
                }
                Section(header: Text("Nutrition per total servings")) {
                    TextField("Calories", text: $calories).keyboardType(.decimalPad).tint(adaptiveTextColor)
                    TextField("Protein (g)", text: $protein).keyboardType(.decimalPad).tint(adaptiveTextColor)
                    TextField("Carbs (g)", text: $carbs).keyboardType(.decimalPad).tint(adaptiveTextColor)
                    TextField("Fat (g)", text: $fat).keyboardType(.decimalPad).tint(adaptiveTextColor)
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
    @Environment(\.colorScheme) var colorScheme
    private var adaptiveTextColor: Color { colorScheme == .dark ? .white : .blue }

    @State private var servings: String = "1"
    @State private var editCalories: String = ""
    @State private var editProtein: String = ""
    @State private var editCarbs: String = ""
    @State private var editFat: String = ""

    private var baseCalories: Double { Double(editCalories) ?? food.calories }
    private var baseProtein: Double { Double(editProtein) ?? food.protein }
    private var baseCarbs: Double { Double(editCarbs) ?? food.carbs }
    private var baseFat: Double { Double(editFat) ?? food.fat }
    private var multiplier: Double { (Double(servings) ?? 1) / food.servings }

    private var dataLooksIncomplete: Bool {
        food.calories == 0 && food.protein == 0 && food.carbs == 0 && food.fat == 0
    }

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

            if dataLooksIncomplete {
                Section {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        Text("Nutrition data missing from database. You can enter values from the label below.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }

            Section(header: Text("How many servings?")) {
                TextField("Servings", text: $servings)
                    .keyboardType(.decimalPad)
                    .tint(adaptiveTextColor)

                HStack {
                    macroLiveCell(Int(baseCalories * multiplier), "cal",  adaptiveTextColor)
                    Spacer()
                    macroLiveCell(Int(baseProtein  * multiplier), "protein", .red)
                    Spacer()
                    macroLiveCell(Int(baseCarbs    * multiplier), "carbs",   .orange)
                    Spacer()
                    macroLiveCell(Int(baseFat      * multiplier), "fat",     .yellow)
                }
                .padding(.vertical, 4)
                .animation(.easeInOut(duration: 0.1), value: servings)
            }
            Section(header: Text(dataLooksIncomplete ? "Nutrition (per serving)" : "Nutrition (editable)")) {
                HStack {
                    Text("Calories")
                    Spacer()
                    TextField("0", text: $editCalories)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 80)
                        .tint(adaptiveTextColor)
                }
                HStack {
                    Text("Protein (g)")
                    Spacer()
                    TextField("0", text: $editProtein)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 80)
                        .tint(adaptiveTextColor)
                }
                HStack {
                    Text("Carbs (g)")
                    Spacer()
                    TextField("0", text: $editCarbs)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 80)
                        .tint(adaptiveTextColor)
                }
                HStack {
                    Text("Fat (g)")
                    Spacer()
                    TextField("0", text: $editFat)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 80)
                        .tint(adaptiveTextColor)
                }
            }
        }
        .scrollDismissesKeyboard(.immediately)
        .navigationBarTitle("Adjust Servings", displayMode: .inline)
        .navigationBarItems(
            leading: Button("Cancel") { dismiss() },
            trailing: Button("Add") {
                var adjusted = food
                let mult = multiplier
                adjusted.servings = Double(servings) ?? 1
                adjusted.calories = baseCalories * mult
                adjusted.protein = baseProtein * mult
                adjusted.carbs = baseCarbs * mult
                adjusted.fat = baseFat * mult
                onSave(adjusted)
            }
            .bold()
        )
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") {
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                }
            }
        }
        .onAppear {
            servings = "\(food.servings)"
            editCalories = food.calories > 0 ? "\(Int(food.calories))" : ""
            editProtein = food.protein > 0 ? "\(Int(food.protein))" : ""
            editCarbs = food.carbs > 0 ? "\(Int(food.carbs))" : ""
            editFat = food.fat > 0 ? "\(Int(food.fat))" : ""
        }
    }

    private func macroLiveCell(_ value: Int, _ label: String, _ color: Color) -> some View {
        VStack(spacing: 2) {
            Text("\(value)")
                .font(.subheadline.bold())
                .foregroundColor(color)
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
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

// MARK: - Add Food to Grocery List Sheet

struct AddFoodToGrocerySheet: View {
    let food: FoodItem

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    private var adaptiveTextColor: Color { colorScheme == .dark ? .white : .blue }

    @State private var groceryLists: [GroceryList] = []
    @State private var isLoading = true
    @State private var isAdding = false
    @State private var showNewListField = false
    @State private var newListName = ""
    @State private var successMessage: String?

    private var username: String { UserDefaults.standard.string(forKey: "loggedInUsername") ?? "" }

    var body: some View {
        NavigationView {
            Group {
                if let msg = successMessage {
                    VStack(spacing: 16) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 56))
                            .foregroundColor(.green)
                        Text(msg)
                            .font(.subheadline)
                            .multilineTextAlignment(.center)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if isLoading {
                    ProgressView("Loading lists…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        Section {
                            if showNewListField {
                                HStack {
                                    TextField("List name", text: $newListName)
                                        .tint(adaptiveTextColor)
                                    Button("Create") { createAndAdd() }
                                        .disabled(newListName.trimmingCharacters(in: .whitespaces).isEmpty || isAdding)
                                        .foregroundColor(adaptiveTextColor)
                                }
                            } else {
                                Button {
                                    newListName = food.name
                                    showNewListField = true
                                } label: {
                                    Label("New Grocery List", systemImage: "plus.circle.fill")
                                        .foregroundColor(adaptiveTextColor)
                                }
                            }
                        }

                        if !groceryLists.isEmpty {
                            Section("Existing Lists") {
                                ForEach(groceryLists) { list in
                                    Button {
                                        addToList(list)
                                    } label: {
                                        HStack {
                                            Image(systemName: "cart")
                                                .foregroundColor(adaptiveTextColor)
                                            Text(list.name).foregroundColor(.primary)
                                            Spacer()
                                            Text("\(list.items.count) item\(list.items.count == 1 ? "" : "s")")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                    .disabled(isAdding)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Add \"\(food.name)\"")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(leading: Button("Cancel") { dismiss() })
            .task { await loadLists() }
        }
    }

    private func loadLists() async {
        isLoading = true
        let lists = (try? await GroceryListAPI.getGroceryLists(username: username)) ?? []
        await MainActor.run { groceryLists = lists; isLoading = false }
    }

    private func addToList(_ list: GroceryList) {
        isAdding = true
        Task {
            let item = GroceryItem(listId: list.id, id: UUID(), name: food.name, quantity: 1, checked: false)
            try? await GroceryListAPI.addItem(listId: list.id.uuidString, item: item)
            await MainActor.run {
                isAdding = false
                successMessage = "Added to \"\(list.name)\""
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { dismiss() }
            }
        }
    }

    private func createAndAdd() {
        let name = newListName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        isAdding = true
        Task {
            do {
                let listId = try await GroceryListAPI.createGroceryList(name: name)
                let trimmedId = listId.trimmingCharacters(in: .whitespacesAndNewlines)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
                guard let listUUID = UUID(uuidString: trimmedId) else {
                    await MainActor.run { isAdding = false }
                    return
                }
                let item = GroceryItem(listId: listUUID, id: UUID(), name: food.name, quantity: 1, checked: false)
                try await GroceryListAPI.addItem(listId: trimmedId, item: item)
                await MainActor.run {
                    isAdding = false
                    successMessage = "Added to \"\(name)\""
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { dismiss() }
                }
            } catch {
                await MainActor.run { isAdding = false }
            }
        }
    }
}
