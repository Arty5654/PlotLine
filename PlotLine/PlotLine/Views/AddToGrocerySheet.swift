//
//  AddToGrocerySheet.swift
//  PlotLine
//
//  Nutrition log → Add to Grocery List, for one food or a whole meal (a saved meal or a meal
//  photo). Foods go on the list as what you'd buy ("Pasta", not "Pasta, cooked"); the names can be
//  changed, and in a meal anything you already have can be unchecked.
//

import SwiftUI

/// what to add: one food, or a whole meal from the log
struct GroceryRequest: Identifiable {
    let id = UUID()
    let title: String   // the food's or the meal's name
    let foods: [FoodItem]
}

struct AddToGrocerySheet: View {
    let request: GroceryRequest

    struct Entry: Identifiable, Equatable {
        let id = UUID()
        let logged: String   // the name in the food log
        var name: String     // the name on the list
        var included = true
    }

    @Environment(\.dismiss) private var dismiss

    @State private var entries: [Entry]
    @State private var groceryLists: [GroceryList] = []
    @State private var isLoading = true
    @State private var isAdding = false
    @State private var showNewListField = false
    @State private var newListName = ""
    @State private var successMessage: String?

    init(request: GroceryRequest) {
        self.request = request
        _entries = State(initialValue: Self.entries(for: request.foods))
    }

    /// one entry per thing to buy: two foods that both shop as "Pasta" are one item
    static func entries(for foods: [FoodItem]) -> [Entry] {
        var seen = Set<String>()
        var result: [Entry] = []
        for food in foods {
            let name = GroceryName.forShopping(food)
            guard seen.insert(name.lowercased()).inserted else { continue }
            result.append(Entry(logged: food.name, name: name))
        }
        return result
    }

    private var isMeal: Bool { entries.count > 1 }
    private var username: String { UserDefaults.standard.string(forKey: "loggedInUsername") ?? "" }

    /// the entries that will be added, with their names trimmed
    private var toAdd: [Entry] {
        entries.compactMap { entry in
            let name = entry.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard entry.included, !name.isEmpty else { return nil }
            var e = entry
            e.name = name
            return e
        }
    }

    private var itemCountText: String { "\(toAdd.count) item\(toAdd.count == 1 ? "" : "s")" }

    var body: some View {
        NavigationStack {
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
                        if isMeal { mealItems } else { singleItem }
                        listChoices
                    }
                }
            }
            .navigationTitle("Add to Grocery List")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
            .task { await loadLists() }
        }
    }

    // MARK: - Items

    @ViewBuilder
    private var singleItem: some View {
        if let entry = $entries.first {
            Section {
                TextField("Item name", text: entry.name)
                    .tint(PLColor.tint)
                    .accessibilityLabel("Name on the list")
            } header: {
                Text("Name on the list")
            } footer: {
                if entry.wrappedValue.name != entry.wrappedValue.logged {
                    Text("Logged as \u{201C}\(entry.wrappedValue.logged)\u{201D}. Lists use what you'd buy at the store.")
                }
            }
        }
    }

    private var mealItems: some View {
        Section {
            ForEach($entries) { $entry in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Button { entry.included.toggle() } label: {
                        Image(systemName: entry.included ? "checkmark.circle.fill" : "circle")
                            .foregroundColor(entry.included ? PLColor.tint : .secondary)
                            .font(.title3)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(entry.included ? "Don't add \(entry.name)" : "Add \(entry.name)")

                    VStack(alignment: .leading, spacing: 2) {
                        TextField("Item name", text: $entry.name)
                            .tint(PLColor.tint)
                            .foregroundColor(entry.included ? .primary : .secondary)
                        if entry.name != entry.logged {
                            Text("Logged as \u{201C}\(entry.logged)\u{201D}")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
        } header: {
            Text("\(request.title) · \(itemCountText)")
        } footer: {
            Text("Uncheck anything you already have. Lists use what you'd buy at the store (\u{201C}Pasta\u{201D}, not \u{201C}Pasta, cooked\u{201D}).")
        }
    }

    // MARK: - Lists

    private var listChoices: some View {
        Group {
            Section {
                if showNewListField {
                    HStack {
                        TextField("List name", text: $newListName)
                            .tint(PLColor.tint)
                        Button("Create") { createAndAdd() }
                            .disabled(newListName.trimmingCharacters(in: .whitespaces).isEmpty || toAdd.isEmpty || isAdding)
                            .foregroundColor(PLColor.tint)
                    }
                } else {
                    Button {
                        newListName = isMeal ? request.title : (toAdd.first?.name ?? request.title)
                        showNewListField = true
                    } label: {
                        Label("New Grocery List", systemImage: "plus.circle.fill")
                            .foregroundColor(PLColor.tint)
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
                                    .foregroundColor(PLColor.tint)
                                Text(list.name).foregroundColor(.primary)
                                Spacer()
                                Text("\(list.items.count) item\(list.items.count == 1 ? "" : "s")")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .disabled(isAdding || toAdd.isEmpty)
                    }
                }
            }
        }
    }

    private func loadLists() async {
        isLoading = true
        do {
            let lists = try await GroceryListAPI.getGroceryLists(username: username)
            await MainActor.run { groceryLists = lists; isLoading = false }
        } catch {
            await MainActor.run { isLoading = false }
            AppBanner.report("load your grocery lists", error, retry: { Task { await loadLists() } })
        }
    }

    // MARK: - Adding

    private func addToList(_ list: GroceryList) {
        isAdding = true
        let added = "Added \(isMeal ? itemCountText + " " : "")to \u{201C}\(list.name)\u{201D}" // before items get unchecked
        Task {
            if await add(toAdd, listId: list.id, listName: list.name) { finish(added) }
        }
    }

    private func createAndAdd() {
        let name = newListName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        isAdding = true
        let added = "Added \(isMeal ? itemCountText + " " : "")to \u{201C}\(name)\u{201D}"
        Task {
            do {
                let listId = try await GroceryListAPI.createGroceryList(name: name)
                let trimmedId = listId.trimmingCharacters(in: .whitespacesAndNewlines)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
                guard let listUUID = UUID(uuidString: trimmedId) else {
                    await MainActor.run { isAdding = false }
                    AppBanner.report("create the list")
                    return
                }
                if await add(toAdd, listId: listUUID, listName: name) {
                    finish(added)
                } else {
                    // the list exists now: a retry should add the rest to it, not make another one
                    await loadLists()
                    await MainActor.run { showNewListField = false }
                }
            } catch {
                await MainActor.run { isAdding = false }
                AppBanner.report("create the list", error)
            }
        }
    }

    /// adds the items one by one; on a failure, the ones already added are unchecked so trying
    /// again doesn't add them twice
    private func add(_ items: [Entry], listId: UUID, listName: String) async -> Bool {
        for entry in items {
            let item = GroceryItem(listId: listId, id: UUID(), name: entry.name, quantity: 1, checked: false)
            do {
                try await GroceryListAPI.addItem(listId: listId.uuidString, item: item)
                await MainActor.run {
                    if isMeal, let i = entries.firstIndex(where: { $0.id == entry.id }) { entries[i].included = false }
                }
            } catch {
                await MainActor.run { isAdding = false } // the sheet stays open to try again
                AppBanner.report("add \(entry.name) to \(listName)", error)
                return false
            }
        }
        return true
    }

    private func finish(_ message: String) {
        Task { @MainActor in
            isAdding = false
            successMessage = message
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            dismiss()
        }
    }
}

#Preview("Meal") {
    let foods = [
        FoodItem(name: "Pasta, cooked", servingSize: "1 cup", servings: 1, calories: 220, protein: 8, carbs: 43, fat: 1, source: .search),
        FoodItem(name: "Beef, ground, 80% lean meat / 20% fat, raw", servingSize: "4 oz", servings: 1, calories: 287, protein: 19, carbs: 0, fat: 23, source: .search),
        FoodItem(name: "Marinara Sauce (Rao's)", servingSize: "1/2 cup", servings: 1, calories: 100, protein: 2, carbs: 6, fat: 7, source: .search, brand: "Rao's"),
    ]
    AddToGrocerySheet(request: GroceryRequest(title: "Spaghetti Night", foods: foods))
}
