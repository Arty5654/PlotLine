//
//  NutritionView.swift
//  PlotLine
//

import SwiftUI
import PhotosUI

// MARK: - Main View
struct NutritionView: View {
    @Environment(\.colorScheme) var colorScheme
    @State private var selectedDate = Date()
    @State private var entry: NutritionEntry?
    @State private var isLoading = false
    // Each save replaces the whole day (and the whole favorites list) on the server, so nothing
    // is saved until the real one has loaded; otherwise a failed load would wipe it.
    @State private var dayLoaded = false

    // User data (favorites & saved meals)
    @State private var userData = NutritionUserData(favorites: [], savedMeals: [])
    @State private var userDataLoaded = false

    // Meal type selection
    @State private var selectedMealType: FoodItem.MealType = Self.suggestedMealType()

    // Sheet states
    @State private var showFoodSearch = false
    @State private var showManualEntry = false
    @State private var showBarcodeScanner = false
    @State private var showCamera = false
    @State private var showPhotoPicker = false
    /// a meal photo waiting for its note and review (PhotoFoodSheet)
    @State private var photoToAnalyze: MealPhoto?
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
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var capturedImage: UIImage?

    // Copy/Move
    /// copying or moving a food (or a whole group) to another day
    struct CopyRequest: Identifiable {
        let id = UUID()
        let foods: [FoodItem]
        let title: String
        let move: Bool
    }
    @State private var copyRequest: CopyRequest?
    @State private var expandedGroups: Set<String> = []
    @State private var groupToDelete: [FoodItem] = []
    @State private var copyTargetDate = Date()

    // Edit logged food
    @State private var foodToEdit: FoodItem?

    // Add to grocery list
    @State private var groceryRequest: GroceryRequest?

    // Shop for meal
    @State private var isShoppingForMeal = false
    @State private var shopMealSuccess: String?
    @State private var showShopMealAlert = false

    // Edit saved meal
    @State private var mealToEdit: SavedMeal?

    // Adding a saved meal: confirm which meal it goes to, then say it was added
    @State private var mealToAdd: SavedMeal?
    @State private var favoriteToAdd: FoodItem?
    @State private var addedMessage: String?
    @State private var addedMessageTask: Task<Void, Never>?

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
        .overlay(alignment: .bottom) {
            if let addedMessage {
                Label(addedMessage, systemImage: "checkmark.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(PLColor.success, in: Capsule())
                    .shadow(radius: 6)
                    .padding(.bottom, PLSpacing.lg)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .accessibilityAddTraits(.isStaticText)
            }
        }
        .animation(.spring(duration: 0.3), value: addedMessage)
        .onAppear { loadEntry(); loadUserData() }
        .onChange(of: selectedDate) { _, _ in loadEntry() }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            loadEntry(); loadUserData()
        }
        .sheet(isPresented: $showFoodSearch) {
            FoodSearchSheet(addLabel: "Add to \(selectedMealType.displayName)") { food in
                addFoods([food], to: selectedMealType)
                showAdded("Added \(food.name) to \(selectedMealType.displayName)")
            }
        }
        .sheet(isPresented: $showManualEntry) { ManualFoodEntrySheet { food in addFood(food) } }
        .sheet(item: $foodToEdit) { food in
            NavigationStack {
                ServingsAdjustmentSheet(food: food) { updated in
                    updateFood(updated)
                    foodToEdit = nil
                }
            }
        }
        .sheet(isPresented: $showBarcodeScanner) { barcodeScannerSheet }
        .sheet(item: $scannedFood) { food in
            NavigationStack {
                ServingsAdjustmentSheet(food: food, barcode: lastScannedBarcode) { adjusted in
                    addFood(adjusted)
                    scannedFood = nil
                }
            }
        }
        .sheet(item: $photoToAnalyze) { photo in
            PhotoFoodSheet(image: photo.image, mealType: selectedMealType) { foods in
                addFoods(foods, to: selectedMealType, asGroup: Self.photoGroupName(foods))
                showAdded("Added \(foods.count) item\(foods.count == 1 ? "" : "s") to \(selectedMealType.displayName)")
            }
        }
        .sheet(isPresented: $showFavorites) { favoritesSheet }
        .sheet(isPresented: $showSavedMeals) { savedMealsSheet }
        .sheet(isPresented: $showCreateMeal) { createMealSheet }
        .sheet(item: $copyRequest) { request in copyDatePickerSheet(request) }
        .confirmationDialog("Delete \(groupToDelete.first?.groupName ?? "this meal") and its \(groupToDelete.count) foods?",
                            isPresented: Binding(get: { !groupToDelete.isEmpty }, set: { if !$0 { groupToDelete = [] } }),
                            titleVisibility: .visible) {
            Button("Delete Meal", role: .destructive) { deleteFoods(groupToDelete) }
        }
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
        // opened from the food itself: with a separate show flag the sheet could open before it saw
        // which food was picked, and showed up blank the first time
        .sheet(item: $groceryRequest) { request in
            AddToGrocerySheet(request: request)
        }
        .alert("Grocery List Created", isPresented: $showShopMealAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(shopMealSuccess ?? "")
        }
        .sheet(isPresented: $showCamera) { CameraPickerView { img in handleCapturedPhoto(img) } }
        .photosPicker(isPresented: $showPhotoPicker, selection: $selectedPhoto, matching: .images)
        .onChange(of: selectedPhoto) { _, item in
            guard let item = item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let img = UIImage(data: data) {
                    handleCapturedPhoto(img)
                } else {
                    AppBanner.report("open that photo")
                }
            }
        }
        .alert("Error", isPresented: $showBarcodeError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(barcodeError ?? "Something went wrong")
        }
        .overlay {
            if isLookingUpBarcode {
                ProgressView("Looking up product...")
                    .padding(24)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
    }


    private var datePicker: some View {
        HStack {
            Button { selectedDate = Calendar.current.date(byAdding: .day, value: -1, to: selectedDate) ?? selectedDate } label: {
                Image(systemName: "chevron.left").font(.title3.bold())
                    .foregroundColor(PLColor.tint)
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
                    .foregroundColor(PLColor.tint)
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
                        .foregroundColor(userData.goals != nil ? PLColor.tint : PLColor.textSecondary)
                }
            }

            if let goal = userData.goals {
                // Calorie ring + numbers
                let eaten = entry?.totalCalories ?? 0
                let remaining = max(0, goal.calorieGoal - eaten)
                let progress = min(eaten / goal.calorieGoal, 1.0)

                ZStack {
                    Circle()
                        .stroke(PLColor.tint.opacity(0.15), lineWidth: 10)
                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(eaten > goal.calorieGoal ? PLColor.danger : PLColor.accent, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(.easeInOut, value: progress)

                    VStack(spacing: 2) {
                        Text("\(Int(remaining))")
                            .font(.system(size: 32, weight: .bold, design: .rounded))
                            .foregroundColor(eaten > goal.calorieGoal ? PLColor.danger : PLColor.tint)
                        Text("remaining")
                            .font(.caption)
                            .foregroundColor(PLColor.textSecondary)
                    }
                }
                .frame(width: 130, height: 130)

                HStack(spacing: PLSpacing.lg) {
                    calorieInfoColumn(value: Int(eaten), label: "Eaten", color: PLColor.tint)
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
                    .foregroundColor(PLColor.tint)
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
                        .foregroundColor(PLColor.tint)
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
            .background(PLColor.tint.opacity(0.1))
            .foregroundColor(PLColor.tint)
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
            .background(PLColor.tint.opacity(0.1))
            .foregroundColor(PLColor.tint)
            .clipShape(RoundedRectangle(cornerRadius: PLRadius.md))
        }
    }

    // MARK: - Food Log
    private var foodLogSection: some View {
        VStack(spacing: PLSpacing.sm) {
            PLSectionHeader(title: "Food Log")
            foodLogCard
        }
    }

    private var foodLogCard: some View {
        VStack(alignment: .leading, spacing: PLSpacing.sm) {
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
                    .foregroundColor(PLColor.tint)
                Text(type.displayName)
                    .font(.subheadline.bold())
                    .foregroundColor(PLColor.tint)
                Spacer()
                let totalCal = foods.reduce(0) { $0 + $1.calories }
                Text("\(Int(totalCal)) cal")
                    .font(.caption.bold())
                    .foregroundColor(PLColor.textSecondary)
            }
            .padding(.top, 4)

            ForEach(Self.logRows(foods)) { row in
                switch row {
                case .food(let food): foodRow(food)
                case .group(let id, let items): groupRow(id: id, foods: items)
                }
            }

            Divider()
        }
    }

    /// a meal's foods in order, with each group's foods together under one row
    enum LogRow: Identifiable {
        case food(FoodItem)
        case group(id: String, foods: [FoodItem])
        var id: String {
            switch self {
            case .food(let f): return f.id
            case .group(let id, _): return "group-" + id
            }
        }
    }

    static func logRows(_ foods: [FoodItem]) -> [LogRow] {
        var rows: [LogRow] = []
        var seen: Set<String> = []
        for food in foods {
            guard let gid = food.groupId else { rows.append(.food(food)); continue }
            guard seen.insert(gid).inserted else { continue }
            rows.append(.group(id: gid, foods: foods.filter { $0.groupId == gid }))
        }
        return rows
    }

    static func photoGroupName(_ foods: [FoodItem]) -> String {
        guard let first = foods.first?.name else { return "Meal photo" }
        return foods.count == 1 ? first : "\(first) + \(foods.count - 1) more"
    }

    private func groupRow(id: String, foods: [FoodItem]) -> some View {
        let expanded = expandedGroups.contains(id)
        let name = foods.first?.groupName ?? "Meal"
        let mealType = foods.first?.mealType ?? .snack
        return VStack(alignment: .leading, spacing: 2) {
            HStack {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        if expanded { expandedGroups.remove(id) } else { expandedGroups.insert(id) }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .rotationEffect(.degrees(expanded ? 90 : 0))
                            .foregroundColor(PLColor.textSecondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(name).font(.subheadline.bold())
                            Text("\(foods.count) item\(foods.count == 1 ? "" : "s")")
                                .font(.caption)
                                .foregroundColor(PLColor.textSecondary)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint(expanded ? "Hides the foods" : "Shows the foods")

                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(Int(foods.reduce(0) { $0 + $1.calories })) cal")
                        .font(.subheadline.bold())
                    Text("P:\(Int(foods.reduce(0) { $0 + $1.protein })) C:\(Int(foods.reduce(0) { $0 + $1.carbs })) F:\(Int(foods.reduce(0) { $0 + $1.fat }))")
                        .font(.caption2)
                        .foregroundColor(PLColor.textSecondary)
                }

                Menu {
                    moveToMealMenu(current: mealType) { target in moveFoods(foods, to: target) }
                    Button {
                        startCopy(foods, title: name, move: false)
                    } label: { Label("Copy to Date", systemImage: "doc.on.doc") }
                    Button {
                        startCopy(foods, title: name, move: true)
                    } label: { Label("Move to Date", systemImage: "arrow.right.doc.on.clipboard") }
                    Button {
                        groceryRequest = GroceryRequest(title: name, foods: foods)
                    } label: { Label("Add to Grocery List", systemImage: "cart.badge.plus") }
                    Button { ungroup(foods) } label: { Label("Ungroup", systemImage: "square.split.1x2") }
                    Divider()
                    Button(role: .destructive) { groupToDelete = foods } label: {
                        Label("Delete Meal", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.subheadline)
                        .foregroundColor(PLColor.textSecondary)
                }
                .padding(.leading, 4)
                .accessibilityLabel("\(name) options")
            }

            if expanded {
                ForEach(foods) { food in
                    foodRow(food)
                        .padding(.leading, 18)
                        .overlay(alignment: .leading) {
                            Rectangle().fill(PLColor.textSecondary.opacity(0.3)).frame(width: 2).padding(.leading, 5)
                        }
                }
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func moveToMealMenu(current: FoodItem.MealType, move: @escaping (FoodItem.MealType) -> Void) -> some View {
        Menu {
            ForEach(FoodItem.MealType.allCases.filter { $0 != current }, id: \.self) { type in
                Button { move(type) } label: { Label(type.displayName, systemImage: type.icon) }
            }
        } label: {
            Label("Move to", systemImage: "arrow.up.arrow.down")
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
                    groceryRequest = GroceryRequest(title: food.name, foods: [food])
                } label: {
                    Label("Add to Grocery List", systemImage: "cart.badge.plus")
                }
                moveToMealMenu(current: food.mealType ?? .snack) { target in moveFoods([food], to: target) }
                Button {
                    startCopy([food], title: food.name, move: false)
                } label: {
                    Label("Copy to Date", systemImage: "doc.on.doc")
                }
                Button {
                    startCopy([food], title: food.name, move: true)
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
        NavigationStack {
            BarcodeScannerView { barcode in
                showBarcodeScanner = false
                lookupBarcode(barcode)
            }
            .navigationBarTitle("Scan Barcode", displayMode: .inline)
            .navigationBarItems(leading: Button("Cancel") { showBarcodeScanner = false })
        }
    }


    // MARK: - Photo Results Sheet
    // MARK: - Favorites Sheet
    private var favoritesSheet: some View {
        NavigationStack {
            List {
                if userData.favorites.isEmpty {
                    Text("No favorites yet. Tap the menu on any food to favorite it.")
                        .foregroundColor(.secondary)
                        .padding(.vertical)
                } else {
                    ForEach(userData.favorites) { food in
                        Button {
                            favoriteToAdd = food
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
            .alert("Add \"\(favoriteToAdd?.name ?? "")\" to \(selectedMealType.displayName)?",
                   isPresented: Binding(get: { favoriteToAdd != nil }, set: { if !$0 { favoriteToAdd = nil } }),
                   presenting: favoriteToAdd) { food in
                Button("Add to \(selectedMealType.displayName)") { addFavorite(food) }
                Button("Cancel", role: .cancel) { }
            } message: { food in
                Text("\(food.servingSize) · \(Int(food.calories)) cal")
            }
        }
    }

    // MARK: - Saved Meals Sheet
    private var savedMealsSheet: some View {
        NavigationStack {
            List {
                if userData.savedMeals.isEmpty {
                    Text("No saved meals yet. Create one with the \"New Meal\" button.")
                        .foregroundColor(.secondary)
                        .padding(.vertical)
                } else {
                    ForEach(userData.savedMeals) { meal in
                        Button {
                            mealToAdd = meal
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
            .alert("Add \"\(mealToAdd?.name ?? "")\" to \(selectedMealType.displayName)?",
                   isPresented: Binding(get: { mealToAdd != nil }, set: { if !$0 { mealToAdd = nil } }),
                   presenting: mealToAdd) { meal in
                Button("Add to \(selectedMealType.displayName)") { addSavedMeal(meal) }
                Button("Cancel", role: .cancel) { }
            } message: { meal in
                Text("\(meal.foods.count) item\(meal.foods.count == 1 ? "" : "s") · \(Int(meal.totalCalories)) cal")
            }
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
    private func copyDatePickerSheet(_ request: CopyRequest) -> some View {
        let isGroup = request.foods.count > 1
        return NavigationStack {
            Form {
                Section(header: Text(request.move ? "Move to Date" : "Copy to Date")) {
                    DatePicker("Target Date", selection: $copyTargetDate, displayedComponents: .date)
                        .tint(PLColor.tint)
                }
                Section(header: Text(isGroup ? "Meal" : "Food")) {
                    Text(request.title).font(.subheadline.bold())
                    Text("\(isGroup ? "\(request.foods.count) items · " : "")\(Int(request.foods.reduce(0) { $0 + $1.calories })) cal")
                        .font(.caption).foregroundColor(.secondary)
                }
            }
            .navigationBarTitle(request.move ? (isGroup ? "Move Meal" : "Move Food") : (isGroup ? "Copy Meal" : "Copy Food"),
                                displayMode: .inline)
            .navigationBarItems(
                leading: Button("Cancel") { copyRequest = nil },
                trailing: Button(request.move ? "Move" : "Copy") {
                    copyOrMoveFoods(request.foods, to: copyTargetDate, move: request.move)
                    copyRequest = nil
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
                        name: GroceryName.forShopping(food), // "Pasta", not "Pasta, cooked"
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
        dayLoaded = false
        let date = selectedDate
        Task {
            do {
                let fetched = try await api.fetchEntries(for: date) // nil: nothing logged that day yet
                await MainActor.run {
                    guard Calendar.current.isDate(date, inSameDayAs: selectedDate) else { return } // they moved on
                    entry = fetched ?? NutritionEntry(date: date, foods: [])
                    dayLoaded = true
                    isLoading = false
                    writeNutritionToWidget()
                }
            } catch {
                await MainActor.run {
                    guard Calendar.current.isDate(date, inSameDayAs: selectedDate) else { return }
                    if let current = entry, !Calendar.current.isDate(current.date, inSameDayAs: date) { entry = nil }
                    isLoading = false
                }
                AppBanner.report("load your food log", error, retry: { loadEntry() })
            }
        }
    }

    /// false (and explains why) when the day's log hasn't loaded, so a change can't overwrite it
    private func dayIsReady() -> Bool {
        if dayLoaded { return true }
        if isLoading {
            AppBanner.shared.show("Your food log is still loading. Try again in a moment.")
        } else {
            AppBanner.shared.show("Your food log for this day didn't load, so it can't be changed yet.", retry: { loadEntry() })
        }
        return false
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
            do {
                let data = try await api.fetchUserData()
                await MainActor.run {
                    userData = data
                    userDataLoaded = true
                    writeNutritionToWidget()
                }
            } catch {
                AppBanner.report("load your favorites and goals", error, retry: { loadUserData() })
            }
        }
    }

    private func addFood(_ food: FoodItem) {
        addFoods([food])
    }

    private func addFavorite(_ food: FoodItem) {
        let mealType = selectedMealType
        addFoods([food], to: mealType)
        showFavorites = false
        showAdded("Added \(food.name) to \(mealType.displayName)")
    }

    private func addSavedMeal(_ meal: SavedMeal) {
        let mealType = selectedMealType
        addFoods(meal.foods, to: mealType, asGroup: meal.name)
        showSavedMeals = false
        showAdded("Added \(meal.name) to \(mealType.displayName)")
    }

    // a short "Added …" message at the bottom of the page
    private func showAdded(_ text: String) {
        addedMessageTask?.cancel()
        addedMessage = text
        addedMessageTask = Task {
            try? await Task.sleep(for: .seconds(2.5))
            guard !Task.isCancelled else { return }
            addedMessage = nil
        }
    }

    // Appends all foods and saves exactly once — avoids the race condition where
    // looping addFood() fires concurrent PUTs that overwrite each other on the server.
    // `mealType` puts them all in that meal (saved meals and favorites remember the meal they
    // came from, which isn't necessarily the one being logged now).
    // `asGroup` names a group the foods are logged as (a saved meal, a meal photo); otherwise each
    // food stands alone (even if it came from a group, e.g. a favorite saved from a meal)
    private func addFoods(_ foods: [FoodItem], to mealType: FoodItem.MealType? = nil, asGroup groupName: String? = nil) {
        guard dayIsReady() else { return }
        if entry == nil {
            entry = NutritionEntry(date: selectedDate, foods: [])
        }
        let groupId = groupName != nil && foods.count > 1 ? UUID().uuidString : nil
        for food in foods {
            var f = food
            f.id = UUID().uuidString
            if let mealType { f.mealType = mealType } else if f.mealType == nil { f.mealType = selectedMealType }
            f.groupId = groupId
            f.groupName = groupId != nil ? groupName : nil
            entry?.foods.append(f)
        }
        saveEntry()
        writeNutritionToWidget()

        let username = UserDefaults.standard.string(forKey: "loggedInUsername") ?? ""
        Task { await ProfileAPI.incrementTrophy(username: username, trophyId: "nutrition-logger") }
        checkDailyNutritionTrophies()
    }

    private func deleteFood(_ food: FoodItem) {
        guard dayIsReady() else { return }
        entry?.foods.removeAll { $0.id == food.id }
        saveEntry()
        writeNutritionToWidget()
        checkDailyNutritionTrophies()
    }

    private func updateFood(_ updated: FoodItem) {
        guard dayIsReady(), let idx = entry?.foods.firstIndex(where: { $0.id == updated.id }) else { return }
        entry?.foods[idx] = updated
        saveEntry()
        writeNutritionToWidget()
        checkDailyNutritionTrophies()
    }

    private func saveEntry() {
        guard dayLoaded, let entry = entry else { return }
        Task {
            do {
                try await api.saveEntry(entry)
            } catch {
                // the change stays on screen; Try again sends the day as it is now
                AppBanner.report("save your food log", error, retry: { saveEntry() })
            }
        }
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
        guard userDataLoaded else {
            AppBanner.shared.show("Your favorites and goals didn't load, so changes can't be saved yet.", retry: { loadUserData() })
            return
        }
        let data = userData
        Task {
            do {
                try await api.saveUserData(data)
            } catch {
                AppBanner.report("save your favorites and goals", error, retry: { persistUserData() })
            }
        }
    }

    private func startCopy(_ foods: [FoodItem], title: String, move: Bool) {
        copyRequest = CopyRequest(foods: foods, title: title, move: move)
        copyTargetDate = selectedDate
    }

    private func copyOrMoveFoods(_ foods: [FoodItem], to targetDate: Date, move: Bool) {
        let what = foods.count > 1 ? "meal" : "food"
        Task {
            // the other day has to load first: saving replaces it, so a failed load would wipe it
            var targetEntry: NutritionEntry
            do {
                targetEntry = try await api.fetchEntries(for: targetDate) ?? NutritionEntry(date: targetDate, foods: [])
            } catch {
                AppBanner.report(move ? "move the \(what)" : "copy the \(what)", error)
                return
            }
            // a copied group is its own group on that day
            let newGroupId = foods.contains { $0.groupId != nil } ? UUID().uuidString : nil
            for food in foods {
                var newFood = food
                newFood.id = UUID().uuidString
                if food.groupId != nil { newFood.groupId = newGroupId }
                targetEntry.foods.append(newFood)
            }

            do {
                try await api.saveEntry(targetEntry)
                if move {
                    await MainActor.run { deleteFoods(foods) }
                }
            } catch {
                // Save failed — leave source untouched
                AppBanner.report(move ? "move the \(what)" : "copy the \(what)", error)
            }

            if Calendar.current.isDate(targetDate, inSameDayAs: selectedDate) {
                await MainActor.run { loadEntry() }
            }
        }
    }

    /// to another meal on the same day; a single food moved out of a group leaves the group
    private func moveFoods(_ foods: [FoodItem], to mealType: FoodItem.MealType) {
        guard dayIsReady(), var updated = entry?.foods else { return }
        let ids = Set(foods.map(\.id))
        let wholeGroup = foods.count > 1
        for i in updated.indices where ids.contains(updated[i].id) {
            updated[i].mealType = mealType
            if !wholeGroup { updated[i].groupId = nil; updated[i].groupName = nil }
        }
        entry?.foods = updated
        saveEntry()
        writeNutritionToWidget()
        showAdded("Moved \(wholeGroup ? (foods.first?.groupName ?? "meal") : (foods.first?.name ?? "food")) to \(mealType.displayName)")
    }

    private func ungroup(_ foods: [FoodItem]) {
        guard dayIsReady() else { return }
        let ids = Set(foods.map(\.id))
        for i in (entry?.foods.indices ?? 0..<0) where ids.contains(entry!.foods[i].id) {
            entry?.foods[i].groupId = nil
            entry?.foods[i].groupName = nil
        }
        saveEntry()
    }

    private func deleteFoods(_ foods: [FoodItem]) {
        guard dayIsReady() else { return }
        let ids = Set(foods.map(\.id))
        entry?.foods.removeAll { ids.contains($0.id) }
        saveEntry()
        writeNutritionToWidget()
        checkDailyNutritionTrophies()
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
        let fromCamera = showCamera
        showCamera = false
        showPhotoPicker = false
        // let the camera sheet finish closing before the photo sheet opens
        DispatchQueue.main.asyncAfter(deadline: .now() + (fromCamera ? 0.6 : 0.1)) {
            photoToAnalyze = MealPhoto(image: image)
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
        NavigationStack {
            Form {
                Section(header: Text("Meal Name")) {
                    TextField("e.g. Breakfast, Chicken Bowl", text: $mealName)
                        .tint(PLColor.tint)
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
                            .foregroundColor(PLColor.tint)
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
                FoodSearchSheet(addLabel: "Add to Meal") { food in
                    extraFoods.append(food)
                    selectedFoodIds.insert(food.id)
                }
            }
            .sheet(isPresented: $showAddBarcode) {
                NavigationStack {
                    BarcodeScannerView { barcode in
                        showAddBarcode = false
                        lookupBarcode(barcode)
                    }
                    .navigationBarTitle("Scan Barcode", displayMode: .inline)
                    .navigationBarItems(leading: Button("Cancel") { showAddBarcode = false })
                }
            }
            .sheet(item: $scannedFood) { food in
                NavigationStack {
                    ServingsAdjustmentSheet(food: food) { adjusted in
                        extraFoods.append(adjusted)
                        selectedFoodIds.insert(adjusted.id)
                        scannedFood = nil
                    }
                }
            }
            .sheet(item: $foodBeingEdited) { food in
                NavigationStack {
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
                    .foregroundColor(selectedFoodIds.contains(food.id) ? PLColor.tint : .secondary)
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
                    .foregroundColor(selectedFoodIds.contains(food.id) ? PLColor.tint : .secondary)
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
                    .foregroundColor(PLColor.tint)
            }
            .buttonStyle(.plain)
        }
    }

    private func lookupBarcode(_ barcode: String) {
        Task {
            do {
                if let food = try await NutritionAPI.shared.lookupBarcode(barcode) {
                    await MainActor.run { scannedFood = food }
                }
            } catch {
                AppBanner.report("look up that barcode", error)
            }
        }
    }
}

// MARK: - Manual Food Entry Sheet
struct ManualFoodEntrySheet: View {
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme
    let onSave: (FoodItem) -> Void

    @State private var name = ""
    @State private var servingSize = ""
    @State private var servings = "1"
    @State private var calories = ""
    @State private var protein = ""
    @State private var carbs = ""
    @State private var fat = ""

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Food Info")) {
                    TextField("Food name", text: $name).tint(PLColor.tint)
                    TextField("Serving size (e.g. 1 cup, 100g)", text: $servingSize).tint(PLColor.tint)
                    HStack {
                        Text("Servings")
                        TextField("1", text: $servings)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .tint(PLColor.tint)
                    }
                }
                Section(header: Text("Nutrition per total servings")) {
                    TextField("Calories", text: $calories).keyboardType(.decimalPad).tint(PLColor.tint)
                    TextField("Protein (g)", text: $protein).keyboardType(.decimalPad).tint(PLColor.tint)
                    TextField("Carbs (g)", text: $carbs).keyboardType(.decimalPad).tint(PLColor.tint)
                    TextField("Fat (g)", text: $fat).keyboardType(.decimalPad).tint(PLColor.tint)
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
                    .tint(PLColor.tint)

                HStack {
                    macroLiveCell(Int(baseCalories * multiplier), "cal",  PLColor.tint)
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
                        .tint(PLColor.tint)
                }
                HStack {
                    Text("Protein (g)")
                    Spacer()
                    TextField("0", text: $editProtein)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 80)
                        .tint(PLColor.tint)
                }
                HStack {
                    Text("Carbs (g)")
                    Spacer()
                    TextField("0", text: $editCarbs)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 80)
                        .tint(PLColor.tint)
                }
                HStack {
                    Text("Fat (g)")
                    Spacer()
                    TextField("0", text: $editFat)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 80)
                        .tint(PLColor.tint)
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

/// a picked or taken meal photo, for `.sheet(item:)`
struct MealPhoto: Identifiable {
    let id = UUID()
    let image: UIImage
}
