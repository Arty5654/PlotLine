//
//  ActiveGroceryListView.swift
//  PlotLine
//
//  Created by Yash Mehta on 2/27/25.
//

import SwiftUI

// --- Lightweight tokens (scoped to this file only) ---
private enum PLColor {
    static let surface       = Color(.secondarySystemBackground)
    static let cardBorder    = Color.black.opacity(0.06)
    static let textPrimary   = Color.primary
    static let textSecondary = Color.secondary
    static let accent        = Color.blue
    static let success       = Color.green
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

private struct PrimaryButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(PLColor.accent.opacity(configuration.isPressed ? 0.85 : 1))
            .clipShape(RoundedRectangle(cornerRadius: PLRadius.md))
    }
}
private struct SecondaryButton: ButtonStyle {
    let color: Color
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(color.opacity(configuration.isPressed ? 0.85 : 1))
            .clipShape(RoundedRectangle(cornerRadius: PLRadius.md))
    }
}

// MARK: - Small subviews (pure UI)

private struct GroceryActionBar: View {
    var onCreateTapped: () -> Void
    var onMealTapped: () -> Void
    var onPrefsTapped: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: PLSpacing.md) {
            Text("Grocery Lists")
                .font(.title3).bold()

            HStack(spacing: PLSpacing.sm) {
                Button(action: onCreateTapped) {
                    Label("New List", systemImage: "plus.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(SecondaryButton(color: PLColor.success))

                Button(action: onMealTapped) {
                    Label("From Meal", systemImage: "fork.knife")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryButton())
            }

            Button(action: onPrefsTapped) {
                HStack(spacing: 6) {
                    Image(systemName: "slider.horizontal.3")
                    Text("Preferences")
                }
                .font(.subheadline)
                .foregroundColor(PLColor.accent)
            }
            .buttonStyle(.plain)
        }
        .plCard()
    }
}

private struct GroceryLoadingState: View {
    var body: some View {
        VStack(spacing: PLSpacing.sm) {
            ProgressView()
            Text("Loading Active Lists…")
                .foregroundColor(PLColor.textSecondary)
                .font(.subheadline)
        }
        .frame(maxWidth: .infinity, minHeight: 220)
        .plCard()
    }
}

private struct GroceryEmptyState: View {
    var body: some View {
        VStack(spacing: PLSpacing.sm) {
            Image(systemName: "cart")
                .font(.largeTitle)
                .foregroundColor(PLColor.textSecondary)
            Text("No active grocery lists.")
                .foregroundColor(PLColor.textSecondary)
            Text("Create a new list or generate one from a meal.")
                .font(.footnote)
                .foregroundColor(PLColor.textSecondary)
        }
        .frame(maxWidth: .infinity, minHeight: 220)
        .plCard()
    }
}

private struct GroceryListRows: View {
    let lists: [GroceryList]

    var body: some View {
        List {
            ForEach(lists) { groceryList in
                NavigationLink(destination: GroceryListDetailView(groceryList: groceryList)) {
                    HStack(spacing: PLSpacing.md) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(groceryList.name)
                                .font(.headline)
                                .foregroundColor(PLColor.textPrimary)
                                .lineLimit(1)
                            if let mealName = groceryList.mealName, !mealName.isEmpty {
                                Text(mealName)
                                    .font(.caption)
                                    .foregroundColor(PLColor.textSecondary)
                                    .lineLimit(1)
                            }
                        }
                        Spacer()
                        if groceryList.isAI == true {
                            Image(systemName: "sparkles")
                                .foregroundColor(PLColor.accent)
                        }
                        Image(systemName: "chevron.right")
                            .font(.footnote)
                            .foregroundColor(PLColor.textSecondary)
                    }
                    .padding(.vertical, 6)
                }
            }
        }
        .listStyle(.insetGrouped)
    }
}

// MARK: - Main View (logic unchanged)

struct ActiveGroceryListView: View {
    @State private var groceryLists: [GroceryList] = []
    @State private var showingCreateGroceryList = false
    @State private var showingMealGenerator = false
    @State private var newGroceryListName: String = ""
    @State private var showSuccessMessage: Bool = false
    @State private var successMessage: String = ""
    @State private var username: String? = UserDefaults.standard.string(forKey: "loggedInUsername")
    @State private var isLoading: Bool = false
    @State private var navigateToPreferences = false
    @State private var dietaryRestrictions: DietaryRestrictions?

    var body: some View {
        VStack(spacing: PLSpacing.lg) {
            GroceryActionBar(
                onCreateTapped: { showingCreateGroceryList.toggle() },
                onMealTapped: { showingMealGenerator.toggle() },
                onPrefsTapped: { navigateToPreferencesScreen() }
            )
            .padding(.horizontal, PLSpacing.lg)
            .padding(.top, PLSpacing.sm)

            Group {
                if isLoading {
                    GroceryLoadingState()
                        .padding(.horizontal, PLSpacing.lg)
                } else if groceryLists.isEmpty {
                    GroceryEmptyState()
                        .padding(.horizontal, PLSpacing.lg)
                } else {
                    GroceryListRows(lists: groceryLists)
                }
            }
            .animation(.easeInOut, value: isLoading)
            .animation(.easeInOut, value: groceryLists.count)
        }
        .navigationTitle("Active Grocery Lists")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            Task {
                await fetchGroceryListsAndWait()
                fetchDietaryPreferences()
            }
        }
        .sheet(isPresented: $showingCreateGroceryList) {
            CreateGroceryListView(
                newGroceryListName: $newGroceryListName,
                onGroceryListCreated: {
                    Task { await fetchGroceryListsAndWait() }
                }
            )
        }
        .sheet(isPresented: $showingMealGenerator) {
            GenerateFromMealView(
                onGroceryListCreated: {
                    Task { await fetchGroceryListsAndWait() }
                }
            )
        }
        // Hidden navigation to preferences (same logic)
        .background(
            NavigationLink(
                destination: DietaryPreferencesView(
                    dietaryRestrictions: $dietaryRestrictions,
                    onClose: { navigateToPreferences = false }
                ),
                isActive: $navigateToPreferences
            ) { EmptyView() }
        )
    }

    // --- Logic below is unchanged ---

    private func createNewGroceryList() {
        guard !newGroceryListName.isEmpty else { return }
        Task {
            do {
                _ = try await GroceryListAPI.createGroceryList(name: newGroceryListName)
                await fetchGroceryListsAndWait()
                showingCreateGroceryList = false
                newGroceryListName = ""
            } catch {
                print("Failed to create grocery list: \(error)")
            }
        }
    }

    private func fetchGroceryListsAndWait() async {
        isLoading = true
        do {
            if let loggedInUsername = username {
                let lists = try await GroceryListAPI.getGroceryLists(username: loggedInUsername)
                groceryLists = lists
            } else {
                print("Username not found!")
            }
            isLoading = false
        } catch {
            print("Failed to load grocery lists: \(error)")
            isLoading = false
        }
    }

    private func fetchDietaryPreferences() {
        Task {
            if let loggedInUsername = username {
                DietaryRestrictionsAPI.shared.getDietaryRestrictions(username: loggedInUsername) { result in
                    switch result {
                    case .success(let restrictions):
                        dietaryRestrictions = restrictions
                    case .failure:
                        dietaryRestrictions = DietaryRestrictions(
                            username: loggedInUsername,
                            lactoseIntolerant: false,
                            vegetarian: false,
                            vegan: false,
                            glutenFree: false,
                            kosher: false,
                            dairyFree: false,
                            nutFree: false
                        )
                    }
                }
            } else {
                print("Username not found!")
            }
        }
    }

    private func navigateToPreferencesScreen() {
        if dietaryRestrictions != nil {
            navigateToPreferences = true
        } else {
            print("Dietary restrictions not available.")
        }
    }

    private func getLastCreatedGroceryList(listId: String) -> GroceryList? {
        let mostRecentList = groceryLists.first { $0.id == UUID(uuidString: listId) }
        return mostRecentList
    }
}

