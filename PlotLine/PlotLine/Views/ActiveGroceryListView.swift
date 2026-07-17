//
//  ActiveGroceryListView.swift
//  PlotLine
//

import SwiftUI

private enum PLColor {
    static let surface       = Color(.secondarySystemBackground)
    static let cardBorder    = Color.black.opacity(0.06)
    static let textPrimary   = Color.primary
    static let textSecondary = Color.secondary
    static let success       = Color.green
    static let danger        = Color.red
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

// MARK: - Action Bar

private struct GroceryActionBar: View {
    let adaptiveTextColor: Color
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
                .buttonStyle(PrimaryButton(color: PLColor.success))

                Button(action: onMealTapped) {
                    Label("From Meal", systemImage: "fork.knife")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryButton(color: .blue))
            }

            Button(action: onPrefsTapped) {
                HStack(spacing: 6) {
                    Image(systemName: "slider.horizontal.3")
                    Text("Dietary Preferences")
                }
                .font(.subheadline)
                .foregroundColor(adaptiveTextColor)
            }
            .buttonStyle(.plain)
        }
        .plCard()
    }
}

// MARK: - Loading / Empty States

private struct GroceryLoadingState: View {
    var body: some View {
        VStack(spacing: PLSpacing.sm) {
            ProgressView()
            Text("Loading Active Lists…")
                .foregroundColor(PLColor.textSecondary)
                .font(.subheadline)
        }
        .frame(maxWidth: .infinity, minHeight: 200)
        .plCard()
    }
}

private struct GroceryEmptyState: View {
    var body: some View {
        VStack(spacing: PLSpacing.sm) {
            Image(systemName: "cart")
                .font(.system(size: 40))
                .foregroundColor(PLColor.textSecondary)
                .padding(.bottom, 4)
            Text("No active grocery lists")
                .font(.headline)
                .foregroundColor(PLColor.textPrimary)
            Text("Create a new list or generate one from a meal.")
                .font(.subheadline)
                .foregroundColor(PLColor.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 200)
        .plCard()
    }
}

// MARK: - List Rows
// Returns a ForEach so rows land directly inside the parent List,
// which is required for .swipeActions to work.

private struct GroceryListRows: View {
    let lists: [GroceryList]
    let adaptiveTextColor: Color
    var onArchive: (GroceryList) -> Void

    var body: some View {
        ForEach(lists) { groceryList in
            let estimate = UserDefaults.standard.double(forKey: "estimate-\(groceryList.id.uuidString)")
            NavigationLink(destination: GroceryListDetailView(groceryList: groceryList)) {
                HStack(spacing: PLSpacing.md) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 4) {
                            Text(groceryList.name)
                                .font(.headline)
                                .foregroundColor(PLColor.textPrimary)
                                .lineLimit(1)
                            if estimate > 0 {
                                Text("(~$\(estimate, specifier: "%.2f"))")
                                    .font(.caption)
                                    .foregroundColor(PLColor.textSecondary)
                                    .lineLimit(1)
                            }
                        }
                        if let mealName = groceryList.mealName, !mealName.isEmpty {
                            Text(mealName)
                                .font(.caption)
                                .foregroundColor(PLColor.textSecondary)
                                .lineLimit(1)
                        }
                    }
                    Spacer()
                    if groceryList.isShared {
                        Image(systemName: "person.2.fill")
                            .foregroundColor(adaptiveTextColor)
                            .font(.subheadline)
                    }
                    if groceryList.isAI == true {
                        Image(systemName: "sparkles")
                            .foregroundColor(adaptiveTextColor)
                            .font(.subheadline)
                    }
                }
            }
            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                Button {
                    onArchive(groceryList)
                } label: {
                    Label("Archive", systemImage: "archivebox")
                }
                .tint(.blue)
            }
            .listRowBackground(
                PLColor.surface
                    .clipShape(RoundedRectangle(cornerRadius: PLRadius.md))
                    .overlay(RoundedRectangle(cornerRadius: PLRadius.md).stroke(PLColor.cardBorder))
                    .padding(.vertical, 3)
            )
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: PLSpacing.xs, leading: PLSpacing.lg,
                                     bottom: PLSpacing.xs, trailing: PLSpacing.lg))
        }
    }
}

// MARK: - Main View

struct ActiveGroceryListView: View {
    @Environment(\.colorScheme) var colorScheme

    @State private var groceryLists: [GroceryList] = []
    @State private var showingCreateGroceryList = false
    @State private var showingMealGenerator = false
    @State private var newGroceryListName: String = ""
    @State private var username: String? = UserDefaults.standard.string(forKey: "loggedInUsername")
    @State private var isLoading: Bool = false
    @State private var navigateToPreferences = false
    @State private var dietaryRestrictions: DietaryRestrictions?

    @State private var weeklyGroceryBudget: Double? = nil
    @State private var weeklyGrocerySpent: Double = 0

    @State private var pendingInvites: [GroceryListInvite] = []
    @State private var respondingInviteIDs: Set<String> = []
    @State private var removedListNotice: String? = nil

    private var adaptiveTextColor: Color {
        colorScheme == .dark ? .white : .blue
    }

    // Shared row insets for non-list header items
    private var headerInsets: EdgeInsets {
        EdgeInsets(top: PLSpacing.sm, leading: PLSpacing.lg,
                   bottom: PLSpacing.sm, trailing: PLSpacing.lg)
    }

    var body: some View {
        List {
            // Action bar
            GroceryActionBar(
                adaptiveTextColor: adaptiveTextColor,
                onCreateTapped: { showingCreateGroceryList.toggle() },
                onMealTapped: { showingMealGenerator.toggle() },
                onPrefsTapped: { navigateToPreferencesScreen() }
            )
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: PLSpacing.lg, leading: PLSpacing.lg,
                                     bottom: PLSpacing.sm, trailing: PLSpacing.lg))

            // Pending shared-list invites
            if !pendingInvites.isEmpty {
                VStack(alignment: .leading, spacing: PLSpacing.sm) {
                    Label("Shared With You", systemImage: "person.badge.plus")
                        .font(.subheadline).bold()
                        .foregroundColor(adaptiveTextColor)

                    ForEach(pendingInvites) { invite in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(invite.listName)
                                        .font(.body).bold()
                                        .lineLimit(1)
                                    Text("from \(invite.fromUsername) · \(invite.items.count) item\(invite.items.count == 1 ? "" : "s")")
                                        .font(.caption)
                                        .foregroundColor(PLColor.textSecondary)
                                }
                                Spacer()
                                if respondingInviteIDs.contains(invite.id) {
                                    ProgressView().controlSize(.small)
                                } else {
                                    HStack(spacing: PLSpacing.xs) {
                                        Button("Decline") {
                                            respondToInvite(invite, accept: false)
                                        }
                                        .font(.caption).bold()
                                        .foregroundColor(PLColor.danger)
                                        .padding(.vertical, 5)
                                        .padding(.horizontal, 10)
                                        .background(PLColor.danger.opacity(0.1))
                                        .clipShape(Capsule())
                                        .buttonStyle(.plain)

                                        Button("Add") {
                                            respondToInvite(invite, accept: true)
                                        }
                                        .font(.caption).bold()
                                        .foregroundColor(.white)
                                        .padding(.vertical, 5)
                                        .padding(.horizontal, 10)
                                        .background(PLColor.success)
                                        .clipShape(Capsule())
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                        }
                        .padding(.vertical, 4)
                        if invite.id != pendingInvites.last?.id {
                            Divider()
                        }
                    }
                }
                .plCard()
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 0, leading: PLSpacing.lg,
                                         bottom: PLSpacing.sm, trailing: PLSpacing.lg))
            }

            // Weekly budget card
            if let budget = weeklyGroceryBudget {
                let overBudget = weeklyGrocerySpent > budget
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Label("Weekly Groceries", systemImage: "cart.fill")
                            .font(.subheadline).bold()
                        Spacer()
                        Text("$\(weeklyGrocerySpent, specifier: "%.2f") / $\(budget, specifier: "%.2f")")
                            .font(.subheadline.bold())
                            .foregroundColor(overBudget ? PLColor.danger : PLColor.success)
                    }
                    ProgressView(value: min(weeklyGrocerySpent / budget, 1.0))
                        .tint(overBudget ? PLColor.danger : PLColor.success)
                    if overBudget {
                        Text("Over budget by $\(weeklyGrocerySpent - budget, specifier: "%.2f")")
                            .font(.caption)
                            .foregroundColor(PLColor.danger)
                    } else {
                        Text("$\(budget - weeklyGrocerySpent, specifier: "%.2f") remaining this week")
                            .font(.caption)
                            .foregroundColor(PLColor.textSecondary)
                    }
                }
                .plCard()
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(headerInsets)
            }

            // Content: loading / empty / rows
            if isLoading {
                GroceryLoadingState()
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(headerInsets)
            } else if groceryLists.isEmpty {
                GroceryEmptyState()
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(headerInsets)
            } else {
                GroceryListRows(lists: groceryLists, adaptiveTextColor: adaptiveTextColor) { list in
                    archiveGroceryList(list)
                }
            }
        }
        .listStyle(.plain)
        .animation(.easeInOut, value: isLoading)
        .animation(.easeInOut, value: groceryLists.count)
        .navigationTitle("Active Lists")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            Task {
                await fetchGroceryListsAndWait()
                fetchDietaryPreferences()
                await fetchWeeklyGroceryData()
                await fetchPendingInvites()
            }
        }
        .task {
            // Poll for incoming share invites and for shared lists being removed while
            // this screen is open. Auto-cancels when the view disappears.
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 12_000_000_000) // 12s
                if Task.isCancelled { break }
                await fetchPendingInvites()
                await pollSharedLists()
            }
        }
        .alert("List Removed", isPresented: Binding(
            get: { removedListNotice != nil },
            set: { if !$0 { removedListNotice = nil } }
        )) {
            Button("OK") { removedListNotice = nil }
        } message: {
            Text(removedListNotice ?? "")
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

    // MARK: - Logic

    private func fetchWeeklyGroceryData() async {
        guard let user = username else { return }

        if let url = URL(string: "\(BackendConfig.baseURLString)/api/costs/\(user)/weekly") {
            var req = URLRequest(url: url)
            BackendConfig.addApiKey(to: &req)
            if let (data, _) = try? await URLSession.shared.data(for: req),
               let decoded = try? JSONDecoder().decode(WeeklyMonthlyCostResponse.self, from: data) {
                weeklyGrocerySpent = decoded.costs["Groceries"] ?? 0
            }
        }

        if let url = URL(string: "\(BackendConfig.baseURLString)/api/budget/\(user)/weekly/groceries") {
            var req = URLRequest(url: url)
            BackendConfig.addApiKey(to: &req)
            if let (data, _) = try? await URLSession.shared.data(for: req),
               let result = try? JSONDecoder().decode([String: Double].self, from: data) {
                weeklyGroceryBudget = result["Groceries"]
            }
        }
    }

    private func archiveGroceryList(_ list: GroceryList) {
        groceryLists.removeAll { $0.id == list.id }
        GroceryListAPI.archiveGroceryList(username: username ?? "", groceryList: list) { result in
            DispatchQueue.main.async {
                if case .failure(let error) = result {
                    groceryLists.append(list)
                    print("Failed to archive grocery list: \(error)")
                }
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

    private func fetchPendingInvites() async {
        guard let user = username else { return }
        if let invites = try? await GroceryListAPI.getPendingInvites(username: user) {
            pendingInvites = invites
        }
    }

    // Background refresh that also notices when a list shared *with* me disappears
    // (owner deleted it or removed me), so it doesn't just silently vanish.
    private func pollSharedLists() async {
        guard let user = username else { return }
        guard let fresh = try? await GroceryListAPI.getGroceryLists(username: user) else { return }

        let freshIDs = Set(fresh.map { $0.id })
        let vanishedShared = groceryLists.filter { !$0.isOwned(by: user) && !freshIDs.contains($0.id) }
        if let gone = vanishedShared.first {
            removedListNotice = "\"\(gone.name)\" is no longer shared with you."
        }
        groceryLists = fresh
    }

    private func respondToInvite(_ invite: GroceryListInvite, accept: Bool) {
        guard let user = username else { return }
        respondingInviteIDs.insert(invite.id)
        Task {
            do {
                try await GroceryListAPI.respondToShare(
                    recipientUsername: user,
                    inviteId: invite.id,
                    accept: accept
                )
                pendingInvites.removeAll { $0.id == invite.id }
                respondingInviteIDs.remove(invite.id)
                if accept {
                    await fetchGroceryListsAndWait()
                }
            } catch {
                respondingInviteIDs.remove(invite.id)
                print("Failed to respond to invite: \(error)")
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
}
