import SwiftUI
import UIKit

// MARK: - View

struct GroceryListDetailView: View {
    var groceryList: GroceryList

    @Environment(\.colorScheme) var colorScheme
    @Environment(\.presentationMode) var presentationMode

    @State private var items: [GroceryItem] = []
    @State private var members: [String] = []
    @State private var listRemoved: Bool = false
    @State private var newItemName: String = ""
    @State private var newItemQuantity: Int = 1

    @State private var selectedItem: GroceryItem? = nil
    @State private var isEditPresented: Bool = false

    @State private var shareSuccess: Bool? = nil
    @State private var canArchiveList: Bool = false
    @State private var archiveSuccess: Bool? = nil

    private var totalItems: Int { items.count }
    private var purchasedItems: Int { items.filter { $0.checked }.count }
    private var completionRatio: Double {
        guard totalItems > 0 else { return 0 }
        return Double(purchasedItems) / Double(totalItems)
    }

    @State private var showShareSheet = false
    /// whether this account has a grocery budget (from the budget quiz); trips can only be added to spending with one
    @State private var hasGroceryBudget: Bool?
    @State private var isFinishing = false

    @State private var isGenerating: Bool = false
    // the list's recipe: made with the list ("From meal") or later with "Get Recipe"
    @State private var recipeMealID: String?
    @State private var openedRecipe: Meal?
    @State private var isOpeningRecipe = false
    @State private var errorMessage: String? = nil
    @State private var showError: Bool = false
    /// Price estimates run once per item, so the daily AI limit is only explained once per visit.
    @State private var shownAILimit = false
    @State private var dietaryMessage: String? = nil
    @State private var showDietaryInfo: Bool = false
    @State private var showMealCreatedAlert: Bool = false
    @State private var mealCreatedMessage: String = ""

    @State private var groceryBudget: Double? = nil
    @State private var weeklySpent: Double = 0
    @State private var showUpdateWeeklyDialog: Bool = false

    @StateObject private var locationManager = LocationManager()
    @State private var userLocation: String = "United States"

    @AppStorage private var savedEstimate: Double
    init(groceryList: GroceryList) {
        self.groceryList = groceryList
        // Seed with the items already carried by the list (canonical items for shared
        // lists) so they render immediately; getItems then keeps them fresh.
        _items = State(initialValue: groceryList.items)
        _members = State(initialValue: groceryList.members ?? [])
        _savedEstimate = AppStorage(wrappedValue: 0, "estimate-\(groceryList.id.uuidString)")
    }

    private var adaptiveTextColor: Color {
        colorScheme == .dark ? .white : .blue
    }
    private var itemText: String { totalItems == 1 ? "Item" : "Items" }

    private var currentUsername: String {
        UserDefaults.standard.string(forKey: "loggedInUsername") ?? ""
    }
    private var isOwner: Bool { groceryList.isOwned(by: currentUsername) }
    private var isShared: Bool { !members.isEmpty }
    private var memberCount: Int {
        // Owner + everyone the list is shared with
        members.count + 1
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: PLSpacing.lg) {

                    // Header card
                    HStack(alignment: .center, spacing: PLSpacing.md) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(groceryList.name)
                                .font(.title2).bold()
                            if let mealName = groceryList.mealName {
                                Label(mealName, systemImage: "fork.knife")
                                    .font(.subheadline)
                                    .foregroundColor(PLColor.textSecondary)
                                    .lineLimit(1)
                            } else {
                                Text("No meal attached")
                                    .font(.subheadline)
                                    .foregroundColor(PLColor.textSecondary)
                            }
                            if isShared {
                                Label(
                                    isOwner
                                        ? "Shared with \(memberCount - 1) friend\(memberCount - 1 == 1 ? "" : "s")"
                                        : "Shared by \(groceryList.ownerUsername ?? groceryList.username)",
                                    systemImage: "person.2.fill"
                                )
                                .font(.caption.bold())
                                .foregroundColor(adaptiveTextColor)
                                .padding(.vertical, 3)
                                .padding(.horizontal, 8)
                                .background(adaptiveTextColor.opacity(0.12))
                                .clipShape(Capsule())
                            }
                        }
                        Spacer()
                        if let budget = groceryBudget {
                            let checkedTotal = items.filter { $0.checked }.reduce(0.0) { $0 + ($1.price ?? 0.0) }
                            let remaining = budget - weeklySpent
                            let overBudget = checkedTotal > remaining
                            VStack(alignment: .trailing, spacing: 2) {
                                HStack(spacing: 4) {
                                    Image(systemName: "cart.fill")
                                    Text(String(format: "$%.2f", checkedTotal))
                                        .fontWeight(.semibold)
                                }
                                .font(.caption.bold())
                                Text(String(format: "$%.2f left", max(0, remaining)))
                                    .font(.caption2)
                                    .foregroundColor(overBudget ? PLColor.danger : PLColor.textSecondary)
                            }
                            .padding(.vertical, 6)
                            .padding(.horizontal, 10)
                            .background((overBudget ? PLColor.danger : PLColor.success).opacity(0.12))
                            .foregroundColor(overBudget ? PLColor.danger : PLColor.success)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        Menu {
                            // Only the list owner can invite/manage friends (owner-only sharing)
                            if isOwner {
                                Button {
                                    showShareSheet = true
                                } label: {
                                    Label("Share with Friend", systemImage: "person.badge.plus")
                                }
                            }
                            Button {
                                shareGroceryList()
                                shareSuccess = nil
                            } label: {
                                Label("Export as Text", systemImage: "square.and.arrow.up")
                            }
                        } label: {
                            Image(systemName: "square.and.arrow.up")
                                .font(.headline)
                                .foregroundColor(adaptiveTextColor)
                        }
                    }
                    .plCard()

                    // Progress + archive
                    if totalItems > 0 {
                        VStack(alignment: .leading, spacing: PLSpacing.sm) {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("\(purchasedItems) of \(totalItems) \(itemText) checked")
                                        .font(.subheadline)
                                        .foregroundColor(PLColor.textSecondary)
                                }
                                Spacer()
                                Button {
                                    archiveList()
                                } label: {
                                    HStack(spacing: 6) {
                                        Image(systemName: isOwner ? "archivebox.fill" : "person.badge.minus")
                                        Text(isOwner ? "Archive" : "Leave")
                                            .fontWeight(.semibold)
                                    }
                                    .font(.subheadline)
                                    .foregroundColor(.white)
                                    .padding(.vertical, 7)
                                    .padding(.horizontal, 12)
                                    // archive (or leave a shared list) anytime; the archive keeps what's checked
                                    .background(PLColor.success)
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                                }
                            }

                            ProgressView(value: completionRatio)
                                .tint(canArchiveList ? PLColor.success : adaptiveTextColor)
                        }
                        .plCard()
                    }

                    // Items list
                    if items.isEmpty {
                        VStack(spacing: PLSpacing.sm) {
                            Image(systemName: "cart")
                                .font(.system(size: 36))
                                .foregroundColor(PLColor.textSecondary)
                                .padding(.bottom, 4)
                            Text("No items yet")
                                .font(.headline)
                                .foregroundColor(PLColor.textSecondary)
                            Text("Add an item below to get started.")
                                .font(.caption)
                                .foregroundColor(PLColor.textSecondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)
                        .plCard()
                    } else {
                        VStack(spacing: 8) {
                            ForEach(items) { item in
                                HStack(spacing: PLSpacing.md) {
                                    Button {
                                        toggleChecked(item: item)
                                    } label: {
                                        Image(systemName: item.checked ? "checkmark.square.fill" : "square")
                                            .foregroundColor(item.checked ? PLColor.success : PLColor.textSecondary)
                                            .font(.title3)
                                    }

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(item.name)
                                            .font(.body)
                                            .strikethrough(item.checked, color: PLColor.success)
                                            .foregroundColor(item.checked ? PLColor.textSecondary : PLColor.textPrimary)
                                            .onTapGesture {
                                                selectedItem = item
                                                isEditPresented = true
                                            }
                                        HStack(spacing: 8) {
                                            Text("Qty: \(item.quantity)")
                                                .foregroundColor(PLColor.textSecondary)
                                                .font(.caption)
                                            if let store = item.store, !store.isEmpty {
                                                Text(store)
                                                    .font(.caption)
                                                    .foregroundColor(PLColor.textSecondary)
                                            }
                                        }
                                        if let price = item.price, price > 0 {
                                            Text("~$\(price, specifier: "%.2f") est.")
                                                .font(.caption.bold())
                                                .foregroundColor(item.checked ? PLColor.success : PLColor.textSecondary)
                                                .transition(.opacity.combined(with: .scale))
                                        }
                                        // On a shared list, show who checked the item off
                                        if isShared, item.checked, let by = item.checkedBy, !by.isEmpty {
                                            Label(
                                                by.lowercased() == currentUsername.lowercased() ? "Got by you" : "Got by \(by)",
                                                systemImage: "checkmark.seal.fill"
                                            )
                                            .font(.caption2)
                                            .foregroundColor(PLColor.success)
                                        }
                                    }
                                    Spacer()
                                    Button {
                                        deleteItem(item)
                                    } label: {
                                        Image(systemName: "trash")
                                            .foregroundColor(PLColor.danger)
                                    }
                                }
                                .padding(.vertical, 8)
                                .padding(.horizontal, PLSpacing.sm)
                                .background(Color(.systemBackground))
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                                .overlay(RoundedRectangle(cornerRadius: 10).stroke(PLColor.cardBorder))
                            }
                        }
                        .plCard()
                    }

                    // Action buttons
                    if !items.isEmpty || recipeAction == .view {
                        HStack(spacing: PLSpacing.md) {
                            recipeButton

                            if !items.isEmpty {
                                Button {
                                    showUpdateWeeklyDialog = true
                                } label: {
                                    HStack(spacing: 8) {
                                        if isFinishing { ProgressView().tint(.white) }
                                        Image(systemName: "checkmark.circle.fill")
                                        Text("Done Shopping")
                                    }
                                }
                                .buttonStyle(PrimaryButton(color: PLColor.success))
                                .disabled(isFinishing)
                            }
                        }
                        .plCard()
                    }

                    // Add item card
                    VStack(alignment: .leading, spacing: PLSpacing.sm) {
                        Label("Add Item", systemImage: "plus.circle")
                            .font(.headline)
                            .foregroundColor(adaptiveTextColor)

                        HStack(spacing: PLSpacing.sm) {
                            TextField("e.g., Eggs", text: $newItemName)
                                .textFieldStyle(.roundedBorder)
                                .tint(adaptiveTextColor)
                            Stepper(value: $newItemQuantity, in: 1...999) {
                                Text("Qty \(newItemQuantity)")
                                    .frame(minWidth: 60, alignment: .trailing)
                                    .font(.subheadline)
                            }
                        }
                        Button {
                            addItemToList()
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "plus.circle.fill")
                                Text("Add to List")
                                    .fontWeight(.semibold)
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(PrimaryButton())
                        .disabled(newItemName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .opacity(newItemName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.6 : 1)
                    }
                    .plCard()

                    if showDietaryInfo {
                        Text(dietaryMessage ?? "")
                            .foregroundColor(PLColor.danger)
                            .font(.caption)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                }
                .padding(.horizontal, PLSpacing.lg)
                .padding(.vertical, PLSpacing.lg)
            }
            .scrollDismissesKeyboard(.immediately)
            .refreshable { await syncItemsFromServer() }
        }
        // the item card, over the list (it used to sit below it in the VStack, squeezing the list)
        .overlay {
            if isEditPresented {
                ZStack {
                    Color.black.opacity(0.45)
                        .ignoresSafeArea()
                        .onTapGesture { isEditPresented = false }
                    GroceryItemInfoView(item: $selectedItem, onClose: {
                        isEditPresented = false
                    })
                }
                .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.2), value: isEditPresented)
        .navigationTitle(groceryList.name)
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $openedRecipe) { meal in
            MealDetailView(meal: meal)
        }
        .onAppear {
            if recipeMealID == nil { recipeMealID = groceryList.mealID }
            Task { hasGroceryBudget = await GroceryCosts.hasGroceryBudget() }
            fetchItems()
            fetchGroceryBudget()
            locationManager.requestLocation { city, state in
                if !city.isEmpty, !state.isEmpty {
                    userLocation = "\(city), \(state)"
                } else if !state.isEmpty {
                    userLocation = state
                }
                // else keep "United States" default
            }
        }
        .task {
            // Light polling so a friend's changes (checks, added/removed items) and the
            // shared-members badge stay current while the list is open. Auto-cancels on
            // disappear.
            await refreshListMeta()
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 5_000_000_000) // 5s
                if Task.isCancelled { break }
                await syncItemsFromServer()
                await refreshListMeta()
            }
        }
        .onChange(of: items) { _, _ in
            canArchiveList = isListCompleted()
        }
        .alert("Share Result", isPresented: .constant(shareSuccess != nil)) {
            Button("OK") { shareSuccess = nil }
        } message: {
            Text(shareSuccess == true ? "Your grocery list was shared successfully." : "There was an issue sharing the list.")
        }
        .alert("Archive Result", isPresented: .constant(archiveSuccess != nil)) {
            Button("OK") { archiveSuccess = nil }
        } message: {
            Text(archiveSuccess == true ? "Your grocery list was archived successfully." : "There was an issue archiving the list.")
        }
        .alert("Meal Created", isPresented: $showMealCreatedAlert) {
            Button("OK") { }
        } message: {
            Text(mealCreatedMessage)
        }
        .alert("Error", isPresented: $showError) {
            Button("OK") { }
        } message: {
            Text(errorMessage ?? "An unknown error occurred.")
        }
        .alert("List No Longer Available", isPresented: $listRemoved) {
            Button("OK") { presentationMode.wrappedValue.dismiss() }
        } message: {
            Text("This grocery list was deleted, or the owner stopped sharing it with you.")
        }
        .sheet(isPresented: $showShareSheet) {
            ShareGroceryListView(groceryList: groceryList) {
                showShareSheet = false
            }
        }
        .alert("Done Shopping?", isPresented: $showUpdateWeeklyDialog) {
            // Finishing always archives the list. Recording the spend is optional, only offered when
            // something is checked off, and only once there's a budget to add it to.
            let checkedCount = items.filter { $0.checked }.count
            if checkedCount > 0 && hasGroceryBudget == false {
                Button("Archive") { finishShopping(recordCost: false) }
                Button("Set Up Budget") {
                    NotificationCenter.default.post(name: .plotlineDeepLink, object: nil, userInfo: ["destination": "budget"])
                }
                Button("Cancel", role: .cancel) { }
            } else if checkedCount > 0 {
                Button("Add to Spending & Archive") { finishShopping(recordCost: true) }
                Button("Archive Only") { finishShopping(recordCost: false) }
                Button("Cancel", role: .cancel) { }
            } else {
                Button("Archive") { finishShopping(recordCost: false) }
                Button("Cancel", role: .cancel) { }
            }
        } message: {
            let checkedTotal = items.filter { $0.checked }.reduce(0.0) { $0 + ($1.price ?? 0.0) }
            let checkedCount = items.filter { $0.checked }.count
            if checkedCount == 0 {
                Text("Nothing is checked off. Archive this list now?")
            } else if hasGroceryBudget == false {
                Text("To add grocery trips to your spending, set up your budget first (Budget → take the quiz). You can still archive this list.")
            } else {
                Text("Add ~$\(checkedTotal, specifier: "%.2f") for \(checkedCount) checked item\(checkedCount == 1 ? "" : "s") to your grocery spending? Either way, this list will be archived.")
            }
        }
    }

    // MARK: - Logic (unchanged)

    func fetchItems() {
        Task {
            do {
                let listIdString = groceryList.id.uuidString
                let fetchedItems = try await GroceryListAPI.getItems(listId: listIdString)
                items = fetchedItems
                // Estimate prices for items that have no price (e.g. AI-generated lists).
                // Only the owner drives estimation so members opening a shared list don't
                // each re-run the same OpenAI estimates; the price persists for everyone.
                if isOwner {
                    for item in fetchedItems where (item.price ?? 0) == 0 {
                        estimateCostForNewItem(itemID: item.id, name: item.name, quantity: item.quantity)
                    }
                }
            } catch {
                AppBanner.report("load the list", error, retry: { fetchItems() })
            }
        }
    }

    // Re-fetch the canonical items from the backend and apply them only if they
    // changed. Used by pull-to-refresh and background polling so shared-list edits
    // made by friends appear here. Deliberately skips price re-estimation to avoid
    // hammering the estimate endpoint on every poll.
    @MainActor
    func syncItemsFromServer() async {
        do {
            let fetched = try await GroceryListAPI.getItems(listId: groceryList.id.uuidString)
            if fetched != items {
                items = fetched
            }
        } catch {
            // Silent: a failed poll shouldn't disrupt the UI
        }
    }

    // Refresh shared-list metadata (members) so the "Shared with N friends" badge stays
    // current — e.g. when a friend accepts or the owner removes someone elsewhere.
    @MainActor
    func refreshListMeta() async {
        do {
            let fresh = try await GroceryListAPI.getGroceryList(listId: groceryList.id.uuidString)
            if let mealID = fresh.mealID, mealID != recipeMealID { recipeMealID = mealID }
            let freshMembers = fresh.members ?? []
            if freshMembers != members {
                members = freshMembers
            }
        } catch GroceryListError.notFound {
            // The list was deleted by the owner, or we were removed from it
            listRemoved = true
        } catch {
            // Transient network error — leave the current state alone
        }
    }

    func isListCompleted() -> Bool {
        return !items.isEmpty && items.allSatisfy { $0.checked }
    }

    func addItemToList() {
        guard !newItemName.isEmpty else { return }
        Task {
            do {
                let listIdString = groceryList.id.uuidString
                let newItem = GroceryItem(listId: groceryList.id, id: UUID(), name: newItemName, quantity: newItemQuantity, checked: false, price: nil, store: "", notes: "")
                try await GroceryListAPI.addItem(listId: listIdString, item: newItem)
                items.append(newItem)
                estimateCostForNewItem(itemID: newItem.id, name: newItem.name, quantity: newItem.quantity)
                newItemName = ""
                newItemQuantity = 1
            } catch {
                AppBanner.report("add \(newItemName)", error) // the item stays typed in
            }
        }
    }

    func estimateCostForNewItem(itemID: UUID, name: String, quantity: Int) {
        let payload: [String: Any] = [
            "location": userLocation,
            "items": [["name": name, "quantity": quantity]]
        ]
        guard let jsonData = try? JSONSerialization.data(withJSONObject: payload),
              let url = URL(string: "\(BackendConfig.baseURLString)/api/groceryLists/estimate-grocery-cost-live")
        else { return }

        var request = URLRequest(url: url)
        BackendConfig.addApiKey(to: &request)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = jsonData

        URLSession.shared.dataTask(with: request) { data, response, _ in
            if let limit = AILimitError.from(data, response) {
                DispatchQueue.main.async {
                    guard !shownAILimit else { return }
                    shownAILimit = true
                    errorMessage = "Prices couldn't be estimated. \(limit.message)"
                    showError = true
                }
                return
            }
            guard let data = data,
                  let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode),
                  let estimatedCost = try? JSONDecoder().decode(Double.self, from: data),
                  estimatedCost > 0
            else {
                print("[GroceryEstimate] Could not estimate price for '\(name)'")
                return
            }
            DispatchQueue.main.async {
                if let idx = items.firstIndex(where: { $0.id == itemID }) {
                    items[idx].price = estimatedCost
                    savedEstimate = items.reduce(0.0) { $0 + ($1.price ?? 0.0) }
                    // Persist price to S3 so it won't be re-estimated on next open
                    let updated = items[idx]
                    Task {
                        try? await GroceryListAPI.updateItem(
                            listId: groceryList.id.uuidString,
                            itemId: itemID.uuidString,
                            updatedItem: updated
                        )
                    }
                }
            }
        }.resume()
    }

    func deleteItem(_ item: GroceryItem) {
        Task {
            do {
                let listIdString = groceryList.id.uuidString
                try await GroceryListAPI.deleteItem(listId: listIdString, itemId: item.id.uuidString)
                items.removeAll { $0.id == item.id }
            } catch {
                AppBanner.report("remove \(item.name)", error, retry: { deleteItem(item) })
            }
        }
    }

    func toggleChecked(item: GroceryItem) {
        Task {
            do {
                let listIdString = groceryList.id.uuidString
                let nowChecked = !item.checked
                // Optimistically record who checked it (mirrors the backend)
                let updatedItem = GroceryItem(
                    listId: groceryList.id, id: item.id, name: item.name, quantity: item.quantity,
                    checked: nowChecked, price: item.price, store: item.store, notes: item.notes,
                    checkedBy: nowChecked ? currentUsername : nil
                )
                try await GroceryListAPI.toggleChecked(listId: listIdString, itemId: item.id.uuidString)
                if let index = items.firstIndex(where: { $0.id == item.id }) {
                    items[index] = updatedItem
                }
            } catch {
                AppBanner.report("update \(item.name)", error)
            }
        }
    }

    func shareGroceryList() {
        let shareText = convertGroceryListToText(groceryList: groceryList)
        let activityViewController = UIActivityViewController(activityItems: [shareText], applicationActivities: nil)
        activityViewController.completionWithItemsHandler = { _, completed, _, _ in
            shareSuccess = completed
        }
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let topController = windowScene.windows.first?.rootViewController {
            topController.present(activityViewController, animated: true, completion: nil)
        }
    }

    func convertGroceryListToText(groceryList: GroceryList) -> String {
        var result = "Grocery List: \(groceryList.name)\n\n"
        for item in groceryList.items {
            if item.checked { result += "(PURCHASED) " }
            result += "\(item.quantity) x \(item.name)"
            if let price = item.price, price > 0 {
                result += " - $\(String(format: "%.2f", price))"
            }
            if let store = item.store, !store.isEmpty {
                result += " from \(store)"
            }
            if let notes = item.notes, !notes.isEmpty {
                result += " (\(notes))"
            }
            result += "\n"
        }
        return result
    }

    // Finish shopping: optionally record the checked-item spend, then archive the list
    // and return to the lists screen. Works even when nothing is checked off.
    func finishShopping(recordCost: Bool) {
        let total = items.filter { $0.checked }.reduce(0.0) { $0 + ($1.price ?? 0.0) }
        guard recordCost, total > 0, hasGroceryBudget != false else {
            archiveList()
            return
        }
        isFinishing = true
        Task {
            let date = GroceryCosts.today()
            do {
                try await GroceryCosts.record(total, on: date)
            } catch {
                isFinishing = false
                AppBanner.report("add this trip to your spending", error, retry: { finishShopping(recordCost: true) })
                return // the list stays open so nothing is lost
            }
            WidgetDataWriter.refreshFinancialData()
            // the archived list remembers it, so restoring can offer to take it back
            archiveList(spentAmount: total, spentDate: date)
        }
    }

    func archiveList(spentAmount: Double? = nil, spentDate: String? = nil) {
        let username: String? = UserDefaults.standard.string(forKey: "loggedInUsername")
        GroceryListAPI.archiveGroceryList(username: username ?? "", groceryList: groceryList,
                                          spentAmount: spentAmount, spentDate: spentDate) { result in
            DispatchQueue.main.async {
                isFinishing = false
                switch result {
                case .success:
                    // Return to the active lists screen once archived (or left, for shared lists)
                    presentationMode.wrappedValue.dismiss()
                case .failure(let error):
                    print("Failed to archive grocery list: \(error.localizedDescription)")
                    archiveSuccess = false
                }
            }
        }
    }

    static func isoDateString(_ date: Date) -> String {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone.current
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }

    // MARK: - Recipe

    private enum RecipeAction { case view, get, generate }

    /// Lists made from a meal (and older AI-made lists) have a recipe: "View Recipe", or "Get Recipe"
    /// to make it once if they don't yet. Lists you built yourself or from a goal keep "Generate Meal".
    private var recipeAction: RecipeAction {
        let fromMeal = (groceryList.isAI ?? false) && groceryList.source != "goal"
        guard fromMeal else { return .generate }
        return recipeMealID != nil ? .view : .get
    }

    @ViewBuilder
    private var recipeButton: some View {
        let busy = isGenerating || isOpeningRecipe
        Button {
            switch recipeAction {
            case .view: openRecipe()
            case .get: getRecipe()
            case .generate: generateMealFromListView()
            }
        } label: {
            HStack(spacing: 8) {
                if busy { ProgressView().tint(.white) }
                switch recipeAction {
                case .view:
                    Image(systemName: "book.pages")
                    Text("View Recipe")
                case .get:
                    Image(systemName: "sparkles")
                    Text(isGenerating ? "Making recipe…" : "Get Recipe")
                case .generate:
                    Image(systemName: "sparkles")
                    Text(isGenerating ? "Generating…" : "Generate Meal")
                }
            }
        }
        .buttonStyle(PrimaryButton())
        .disabled(busy)
        .opacity(busy ? 0.75 : 1)
    }

    private func openRecipe() {
        guard let mealID = recipeMealID else { return }
        isOpeningRecipe = true
        Task {
            do {
                let username = UserDefaults.standard.string(forKey: "loggedInUsername") ?? ""
                openedRecipe = try await MealViewModel.fetchMeal(username: username, mealID: mealID)
            } catch {
                AppBanner.report("open the recipe", error, retry: { openRecipe() })
            }
            isOpeningRecipe = false
        }
    }

    /// makes the recipe from the list's items once, then opens it
    private func getRecipe() {
        guard !items.isEmpty else { return }
        isGenerating = true
        Task {
            do {
                let result = try await GroceryListAPI.generateMealFromList(
                    listID: groceryList.id.uuidString, groceryListItems: items.map { ($0.name, $0.quantity) })
                if result.contains("\"incompatible\"") || result.hasPrefix("INCOMPATIBLE:") {
                    isGenerating = false
                    errorMessage = "Couldn't make a recipe from this list. Please try again."
                    showError = true
                    return
                }
                // the server saved the recipe and linked it to this list
                let fresh = try await GroceryListAPI.getGroceryList(listId: groceryList.id.uuidString)
                recipeMealID = fresh.mealID
                isGenerating = false
                openRecipe()
            } catch {
                isGenerating = false
                if let limit = error as? AILimitError {
                    errorMessage = limit.message
                    showError = true
                } else {
                    AppBanner.report("make the recipe", error, retry: { getRecipe() })
                }
            }
        }
    }

    @discardableResult
    func generateMealFromListView() -> [(name: String, quantity: Int)] {
        let listItems = items
        var items_short: [(name: String, quantity: Int)] = []
        listItems.forEach { item in items_short.append((item.name, item.quantity)) }
        generateMealFromList(groceryListItems: items_short)
        return items_short
    }

    func fetchGroceryBudget() {
        let username = UserDefaults.standard.string(forKey: "loggedInUsername") ?? "UnknownUser"

        // Fetch weekly grocery budget
        if let budgetURL = URL(string: "\(BackendConfig.baseURLString)/api/budget/\(username)/weekly/groceries") {
            var budgetReq = URLRequest(url: budgetURL)
            BackendConfig.addApiKey(to: &budgetReq)
            URLSession.shared.dataTask(with: budgetReq) { data, _, _ in
                guard let data = data,
                      let result = try? JSONSerialization.jsonObject(with: data) as? [String: Double],
                      let budget = result["Groceries"] else { return }
                DispatchQueue.main.async { groceryBudget = budget }
            }.resume()
        }

        // Fetch how much has already been spent this week on groceries
        if let spentURL = GroceryCosts.thisWeekURL(username: username) {
            var spentReq = URLRequest(url: spentURL)
            BackendConfig.addApiKey(to: &spentReq)
            URLSession.shared.dataTask(with: spentReq) { data, _, _ in
                guard let data = data,
                      let decoded = try? JSONDecoder().decode(WeeklyMonthlyCostResponse.self, from: data) else { return }
                DispatchQueue.main.async { weeklySpent = decoded.costs["Groceries"] ?? 0 }
            }.resume()
        }
    }

    private func generateMealFromList(groceryListItems: [(name: String, quantity: Int)]) {
        guard !groceryListItems.isEmpty else { return }
        isGenerating = true
        Task {
            do {
                let result = try await GroceryListAPI.generateMealFromList(listID: groceryList.id.uuidString, groceryListItems: groceryListItems)
                await MainActor.run {
                    isGenerating = false
                    if let incompatiblePrefix = result.range(of: "INCOMPATIBLE:") {
                        let json = String(result[incompatiblePrefix.upperBound...])
                        if let data = json.data(using: .utf8),
                           let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                           let reason = dict["reason"] as? String {
                            dietaryMessage = "This meal cannot be made with your dietary restrictions: \n\n \(reason)"
                            showDietaryInfo = true
                            errorMessage = "Cannot create meal: \(reason)"
                            showError = true
                        } else {
                            dietaryMessage = "This meal is not compatible with your dietary restrictions."
                            showDietaryInfo = true
                            errorMessage = "This meal is not compatible with your dietary restrictions."
                            showError = true
                        }
                    } else if let modPrefix = result.range(of: "MODIFIED:") {
                        let json = String(result[modPrefix.upperBound...])
                        if let data = json.data(using: .utf8),
                           let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                           let modifications = dict["modifications"] as? String {
                            dietaryMessage = "We've adjusted this recipe to match your dietary preferences: \n\n \(modifications)"
                            showDietaryInfo = true
                            mealCreatedMessage = "A new meal has been created with adjustments to match your dietary preferences."
                            showMealCreatedAlert = true
                        } else {
                            mealCreatedMessage = "A new meal has been created successfully!"
                            showMealCreatedAlert = true
                        }
                    } else {
                        mealCreatedMessage = "A new meal has been created successfully!"
                        showMealCreatedAlert = true
                    }
                }
            } catch {
                await MainActor.run {
                    isGenerating = false
                    errorMessage = error.localizedDescription
                    showError = true
                    print("Error generating meal: \(error)")
                }
            }
        }
    }
}
