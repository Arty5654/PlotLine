//
//  CreateGroceryListView.swift
//  PlotLine
//
//  Created by Yash Mehta on 2/22/25.
//

import SwiftUI

// Local tokens (scoped to this file)
private enum PLColor {
    static let surface       = Color(.secondarySystemBackground)
    static let cardBorder    = Color.black.opacity(0.08)
    static let textPrimary   = Color.primary
    static let textSecondary = Color.secondary
    static let accent        = Color.blue
}
private enum PLSpacing {
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

struct CreateGroceryListView: View {
    @Binding var newGroceryListName: String
    var onGroceryListCreated: () -> Void

    // Keep same alert-driven flow
    @State private var isShowingAlert = false
    @State private var alertMessage = ""
    @State private var alertTitle = ""

    // Small UX niceties
    @FocusState private var nameFocused: Bool
    @Environment(\.dismiss) private var dismiss

    private var isCreateDisabled: Bool {
        newGroceryListName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: PLSpacing.lg) {
                // Header
                VStack(alignment: .leading, spacing: 4) {
                    Text("New Grocery List")
                        .font(.title3).bold()
                        .foregroundColor(PLColor.textPrimary)
                    Text("Give your list a short, clear name. You can add items after creating it.")
                        .font(.subheadline)
                        .foregroundColor(PLColor.textSecondary)
                }
                .plCard()

                // Name field card
                VStack(alignment: .leading, spacing: PLSpacing.sm) {
                    Label("List Name", systemImage: "cart")
                        .font(.subheadline).foregroundColor(PLColor.textSecondary)

                    TextField("e.g., Weekly Meal Prep", text: $newGroceryListName)
                        .textFieldStyle(.roundedBorder)
                        .focused($nameFocused)
                        .submitLabel(.done)
                        .onSubmit {
                            // Keep logic the same; just call the same function
                            if !isCreateDisabled { createNewGroceryList() }
                        }

                    // tiny helper text
                    Text("You can rename it later.")
                        .font(.caption)
                        .foregroundColor(PLColor.textSecondary)
                }
                .plCard()

                // Create button
                Button {
                    createNewGroceryList()
                } label: {
                    Text("Create Grocery List")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryButton())
                .disabled(isCreateDisabled)
                .opacity(isCreateDisabled ? 0.6 : 1)

                Spacer()
            }
            .padding(.horizontal, PLSpacing.lg)
            .padding(.top, PLSpacing.lg)
            .navigationTitle("Create List")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .alert(isPresented: $isShowingAlert) {
                Alert(
                    title: Text(alertTitle),
                    message: Text(alertMessage),
                    dismissButton: .default(Text("OK")) {
                        // Preserve your existing success flow
                        if alertTitle == "Success" {
                            dismiss()
                            onGroceryListCreated()
                        }
                    }
                )
            }
        }
        .onAppear {
            newGroceryListName = ""   // preserve your original behavior
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                nameFocused = true
            }
        }
    }

    // MARK: - Network (unchanged logic)
    private func createNewGroceryList() {
        Task {
            do {
                _ = try await GroceryListAPI.createGroceryList(name: newGroceryListName)
                alertTitle = "Success"
                alertMessage = "Grocery list created: \(newGroceryListName)"
                isShowingAlert = true
            } catch {
                alertTitle = "Error"
                alertMessage = "Failed to create grocery list."
                isShowingAlert = true
            }
        }
    }
}
