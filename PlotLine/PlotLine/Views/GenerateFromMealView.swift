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
    
    @FocusState private var fieldFocused: Bool
    
    var onGroceryListCreated: () -> Void
    
    private var disabled: Bool {
        mealName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isGenerating
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
                    
                    // Helper / safety note
                    Text("We’ll let you know if the meal conflicts with your dietary settings, and suggest safe tweaks when possible.")
                        .font(.footnote)
                        .foregroundColor(PLColor.textSecondary)
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
                // focus the field shortly after appear for smoother animation
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    fieldFocused = true
                }
            }
        }
    }

    // MARK: - Logic (unchanged)
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
