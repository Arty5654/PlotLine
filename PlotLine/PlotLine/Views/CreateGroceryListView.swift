//
//  CreateGroceryListView.swift
//  PlotLine
//

import SwiftUI

struct CreateGroceryListView: View {
    @Binding var newGroceryListName: String
    var onGroceryListCreated: () -> Void

    @Environment(\.colorScheme) var colorScheme
    @Environment(\.dismiss) private var dismiss

    @State private var isShowingAlert = false
    @State private var alertMessage = ""
    @State private var alertTitle = ""
    @FocusState private var nameFocused: Bool

    private var adaptiveTextColor: Color {
        colorScheme == .dark ? .white : .blue
    }

    private var isCreateDisabled: Bool {
        newGroceryListName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: PLSpacing.lg) {
                    // Header card
                    VStack(alignment: .leading, spacing: 6) {
                        Label("New Grocery List", systemImage: "cart.badge.plus")
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
                            .font(.subheadline)
                            .foregroundColor(PLColor.textSecondary)

                        TextField("e.g., Weekly Meal Prep", text: $newGroceryListName)
                            .textFieldStyle(.roundedBorder)
                            .tint(adaptiveTextColor)
                            .focused($nameFocused)
                            .submitLabel(.done)
                            .onSubmit {
                                if !isCreateDisabled { createNewGroceryList() }
                            }

                        Text("You can rename it later.")
                            .font(.caption)
                            .foregroundColor(PLColor.textSecondary)
                    }
                    .plCard()

                    Button {
                        createNewGroceryList()
                    } label: {
                        Text("Create Grocery List")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(PrimaryButton())
                    .disabled(isCreateDisabled)
                    .opacity(isCreateDisabled ? 0.6 : 1)
                }
                .padding(.horizontal, PLSpacing.lg)
                .padding(.top, PLSpacing.lg)
            }
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
                        if alertTitle == "Success" {
                            dismiss()
                            onGroceryListCreated()
                        }
                    }
                )
            }
        }
        .onAppear {
            newGroceryListName = ""
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                nameFocused = true
            }
        }
    }

    // MARK: - Network (logic unchanged)

    private func createNewGroceryList() {
        Task {
            do {
                _ = try await GroceryListAPI.createGroceryList(name: newGroceryListName)
                alertTitle = "Success"
                alertMessage = "Grocery list created: \(newGroceryListName)"
                isShowingAlert = true
            } catch {
                alertTitle = "Error"
                alertMessage = error.localizedDescription
                isShowingAlert = true
            }
        }
    }
}
