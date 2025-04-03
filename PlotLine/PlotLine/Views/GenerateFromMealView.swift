//
//  GenerateFromMealView.swift
//  PlotLine
//
//  Created by Yash Mehta on 4/3/25.
//


import SwiftUI

struct GenerateFromMealView: View {
    @Environment(\.presentationMode) var presentationMode
    @State private var mealName: String = ""
    @State private var isGenerating: Bool = false
    @State private var errorMessage: String? = nil
    @State private var showError: Bool = false
    
    var onGroceryListCreated: () -> Void
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Text("Generate a Grocery List From a Meal")
                    .font(.headline)
                    .padding(.top)
                
                TextField("Enter meal name (e.g., Lasagna)", text: $mealName)
                    .padding()
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                
                Text("We'll create a grocery list with all the ingredients you need!")
                    .font(.subheadline)
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                
                Button(action: {
                    generateGroceryList()
                }) {
                    if isGenerating {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle())
                    } else {
                        Text("Generate Grocery List")
                            .font(.title2)
                            .foregroundColor(.white)
                            .padding()
                            .frame(maxWidth: .infinity)
                            .background(mealName.isEmpty ? Color.gray : Color.green)
                            .cornerRadius(10)
                    }
                }
                .disabled(mealName.isEmpty || isGenerating)
                .padding()
                
                Spacer()
            }
            .padding()
            .navigationTitle("AI Meal Generator")
            .navigationBarItems(
                trailing: Button("Cancel") {
                    presentationMode.wrappedValue.dismiss()
                }
            )
            .alert(isPresented: $showError, content: {
                Alert(
                    title: Text("Error"),
                    message: Text(errorMessage ?? "An unknown error occurred."),
                    dismissButton: .default(Text("OK"))
                )
            })
        }
    }

    private func generateGroceryList() {
        guard !mealName.isEmpty else { return }

        isGenerating = true

        Task {
            do {
                // Call the API function to generate a grocery list from the meal name
                let _ = try await GroceryListAPI.generateGroceryListFromMeal(mealName: mealName)

                // On success, dismiss this view and refresh the grocery lists
                DispatchQueue.main.async {
                    isGenerating = false
                    onGroceryListCreated()
                    presentationMode.wrappedValue.dismiss()
                }
            } catch {
                // Handle any errors
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
