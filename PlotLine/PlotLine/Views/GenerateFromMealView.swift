//
//  GenerateFromMealView.swift
//  PlotLine
//
//  Created by Yash Mehta on 4/3/25.
//

import SwiftUI

// MARK: - Local design tokens (scoped)
private enum PLColor {
    static let surface       = Color(.secondarySystemBackground)
    static let cardBorder    = Color.black.opacity(0.08)
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

// MARK: - View
struct GenerateFromMealView: View {
    @Environment(\.presentationMode) var presentationMode
    @State private var mealName: String = ""
    @State private var isGenerating: Bool = false
    @State private var errorMessage: String? = nil
    @State private var showError: Bool = false
    @State private var dietaryMessage: String? = nil
    @State private var showDietaryInfo: Bool = false

    @State private var weeklyGroceryBudget: Double? = nil
    @State private var weeklyGrocerySpent: Double = 0
    @State private var dietaryRestrictions: DietaryRestrictions? = nil

    @FocusState private var fieldFocused: Bool

    var onGroceryListCreated: () -> Void

    private var disabled: Bool {
        mealName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isGenerating
    }

    private var activeRestrictionLabels: [String] {
        guard let d = dietaryRestrictions else { return [] }
        var list: [String] = []
        if d.vegan            { list.append("Vegan") }
        else if d.vegetarian  { list.append("Vegetarian") }
        if d.glutenFree       { list.append("Gluten-free") }
        if d.dairyFree        { list.append("Dairy-free") }
        else if d.lactoseIntolerant { list.append("Lactose-intolerant") }
        if d.nutFree          { list.append("Nut-free") }
        if d.kosher           { list.append("Kosher") }
        return list
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: PLSpacing.lg) {
                    
                    // Header card
                    VStack(alignment: .leading, spacing: PLSpacing.xs) {
                        Text("AI Meal Generator")
                            .font(.title3).bold()
                        Text("Type a meal (e.g., Lasagna). We’ll build a grocery list of ingredients—automatically adapted to your dietary preferences.")
                            .font(.subheadline)
                            .foregroundColor(PLColor.textSecondary)
                    }
                    .plCard()
                    
                    // Input card
                    VStack(alignment: .leading, spacing: PLSpacing.sm) {
                        Label("Meal Name", systemImage: "fork.knife")
                            .font(.subheadline)
                            .foregroundColor(PLColor.textSecondary)
                        
                        TextField("e.g., Lasagna", text: $mealName)
                            .textFieldStyle(.roundedBorder)
                            .focused($fieldFocused)
                            .submitLabel(.go)
                            .onSubmit { if !disabled { generateGroceryList() } }
                        
                        Text("Examples: \"Chicken Tikka\", \"Vegan Chili\", \"Gluten-free Pancakes\"")
                            .font(.caption)
                            .foregroundColor(PLColor.textSecondary)
                    }
                    .plCard()
                    
                    // Action button
                    Button {
                        generateGroceryList()
                    } label: {
                        HStack(spacing: 8) {
                            if isGenerating { ProgressView() }
                            Text(isGenerating ? "Generating…" : "Generate Grocery List")
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(PrimaryButton())
                    .disabled(disabled)
                    .opacity(disabled ? 0.6 : 1)

                    // Info caption: dietary preferences + budget
                    VStack(alignment: .leading, spacing: PLSpacing.sm) {
                        if dietaryRestrictions != nil {
                            HStack(alignment: .top, spacing: 6) {
                                Image(systemName: "leaf.fill")
                                    .foregroundColor(PLColor.success)
                                    .font(.caption)
                                    .padding(.top, 1)
                                Text(activeRestrictionLabels.isEmpty
                                     ? "No dietary restrictions — all ingredients included"
                                     : activeRestrictionLabels.joined(separator: " · "))
                                    .font(.caption)
                                    .foregroundColor(PLColor.textSecondary)
                            }
                        }

                        if let budget = weeklyGroceryBudget {
                            let remaining = budget - weeklyGrocerySpent
                            HStack(alignment: .top, spacing: 6) {
                                Image(systemName: "dollarsign.circle.fill")
                                    .foregroundColor(remaining >= 0 ? PLColor.success : .red)
                                    .font(.caption)
                                    .padding(.top, 1)
                                VStack(alignment: .leading, spacing: 2) {
                                    if remaining >= 0 {
                                        Text("Weekly grocery budget: $\(budget, specifier: "%.2f") · $\(remaining, specifier: "%.2f") remaining")
                                            .font(.caption)
                                            .foregroundColor(PLColor.textSecondary)
                                    } else {
                                        Text("Weekly grocery budget: $\(budget, specifier: "%.2f") · $\(abs(remaining), specifier: "%.2f") over")
                                            .font(.caption)
                                            .foregroundColor(.red)
                                    }
                                    Text("Estimated costs will appear in the list after it’s created.")
                                        .font(.caption2)
                                        .foregroundColor(PLColor.textSecondary)
                                }
                            }
                        }

                        HStack(spacing: 6) {
                            Image(systemName: "info.circle")
                                .font(.caption)
                            Text("We’ll flag any conflicts with your dietary settings and suggest safe substitutions.")
                                .font(.caption)
                        }
                        .foregroundColor(PLColor.textSecondary)
                    }
                    .padding(.horizontal, 2)
                }
                .padding(.horizontal, PLSpacing.lg)
                .padding(.top, PLSpacing.lg)
            }
            .navigationTitle("Generate from Meal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { presentationMode.wrappedValue.dismiss() }
                }
            }
            .alert(isPresented: $showError) {
                Alert(
                    title: Text("Error"),
                    message: Text(errorMessage ?? "An unknown error occurred."),
                    dismissButton: .default(Text("OK"))
                )
            }
            .alert(isPresented: $showDietaryInfo) {
                Alert(
                    title: Text("About your request"),
                    message: Text(dietaryMessage ?? ""),
                    dismissButton: .default(Text("OK")) {
                        // same behavior you had: refresh lists + dismiss
                        onGroceryListCreated()
                        presentationMode.wrappedValue.dismiss()
                    }
                )
            }
            .onAppear {
                fetchBudgetAndPrefs()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    fieldFocused = true
                }
            }
        }
    }

    // MARK: - Logic

    private func fetchBudgetAndPrefs() {
        guard let username = UserDefaults.standard.string(forKey: "loggedInUsername") else { return }

        DietaryRestrictionsAPI.shared.getDietaryRestrictions(username: username) { result in
            if case .success(let r) = result {
                DispatchQueue.main.async { dietaryRestrictions = r }
            }
        }

        if let budgetURL = URL(string: "\(BackendConfig.baseURLString)/api/budget/\(username)/weekly/groceries") {
            var req = URLRequest(url: budgetURL)
            BackendConfig.addApiKey(to: &req)
            URLSession.shared.dataTask(with: req) { data, _, _ in
                guard let data = data,
                      let result = try? JSONSerialization.jsonObject(with: data) as? [String: Double],
                      let budget = result["Groceries"] else { return }
                DispatchQueue.main.async { weeklyGroceryBudget = budget }
            }.resume()
        }

        if let spentURL = URL(string: "\(BackendConfig.baseURLString)/api/costs/\(username)/weekly") {
            URLSession.shared.dataTask(with: spentURL) { data, _, _ in
                guard let data = data,
                      let decoded = try? JSONDecoder().decode(WeeklyMonthlyCostResponse.self, from: data) else { return }
                DispatchQueue.main.async { weeklyGrocerySpent = decoded.costs["Groceries"] ?? 0 }
            }.resume()
        }
    }

    private func generateGroceryList() {
        guard !mealName.isEmpty else { return }

        isGenerating = true

        Task {
            do {
                let result = try await GroceryListAPI.generateGroceryListFromMeal(mealName: mealName)
                
                DispatchQueue.main.async {
                    isGenerating = false
                    
                    // INCOMPATIBLE: <json>
                    if let incompatiblePrefix = result.range(of: "INCOMPATIBLE:") {
                        let json = String(result[incompatiblePrefix.upperBound...])
                        if let data = json.data(using: .utf8),
                           let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                           let reason = dict["reason"] as? String {
                            dietaryMessage = "This meal cannot be made with your dietary restrictions:\n\n\(reason)"
                        } else {
                            dietaryMessage = "This meal is not compatible with your dietary restrictions."
                        }
                        showDietaryInfo = true
                    }
                    // MODIFIED: <json>
                    else if let modPrefix = result.range(of: "MODIFIED:") {
                        let json = String(result[modPrefix.upperBound...])
                        if let data = json.data(using: .utf8),
                           let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                           let modifications = dict["modifications"] as? String,
                           let _ = dict["listId"] as? String {
                            dietaryMessage = "We’ve adjusted this recipe to match your dietary preferences:\n\n\(modifications)"
                            showDietaryInfo = true
                        } else {
                            onGroceryListCreated()
                            presentationMode.wrappedValue.dismiss()
                        }
                    }
                    // Plain success
                    else {
                        onGroceryListCreated()
                        presentationMode.wrappedValue.dismiss()
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    isGenerating = false
                    errorMessage = error.localizedDescription
                    showError = true
                }
            }
        }
    }
}

#Preview {
    GenerateFromMealView(onGroceryListCreated: {})
}
