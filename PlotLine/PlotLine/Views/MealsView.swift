//
//  MealsView.swift
//  PlotLine
//
//  Created by Yash Mehta on 4/30/25.
//

import UIKit
import SwiftUI

struct MealsView: View {
    @StateObject private var viewModel = MealViewModel()
    @State private var username = UserDefaults.standard.string(forKey: "loggedInUsername") ?? ""
    @State private var searchText = ""
    
    var filteredMeals: [Meal] {
        if searchText.isEmpty {
            return viewModel.meals
        } else {
            return viewModel.meals.filter { meal in
                meal.mealName.localizedCaseInsensitiveContains(searchText)
            }
        }
    }
    
    var body: some View {
        VStack(spacing: PLSpacing.md) {
            // Search bar
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(PLColor.textSecondary)
                TextField("Search meals", text: $searchText)
                if !searchText.isEmpty {
                    Button { searchText = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(Color(.tertiaryLabel))
                    }
                    .accessibilityLabel("Clear")
                }
            }
            .padding(12)
            .background(PLColor.surface)
            .clipShape(RoundedRectangle(cornerRadius: PLRadius.md))
            .padding(.horizontal, PLSpacing.lg)
            .padding(.top, PLSpacing.sm)

            if !viewModel.meals.isEmpty {
                if filteredMeals.isEmpty {
                    Spacer()
                    Text("No meals match \"\(searchText)\".")
                        .font(.subheadline)
                        .foregroundColor(PLColor.textSecondary)
                    Spacer()
                } else {
                    List {
                        ForEach(filteredMeals) { meal in
                            NavigationLink(destination: MealDetailView(meal: meal)) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(meal.mealName)
                                        .font(.headline)
                                    Text("\(meal.ingredients.count) ingredients · \(meal.recipe.count) steps")
                                        .font(.subheadline)
                                        .foregroundColor(PLColor.textSecondary)
                                }
                                .padding(.vertical, 4)
                            }
                            .listRowBackground(PLColor.surface)
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    deleteMeal(meal)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                    .scrollContentBackground(.hidden)
                }
            } else {
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: "fork.knife")
                        .font(.largeTitle)
                        .foregroundColor(PLColor.textSecondary)
                    Text("No meals yet")
                        .font(.headline)
                    Text("Create a meal from a grocery list, and it shows up here.")
                        .font(.subheadline)
                        .foregroundColor(PLColor.textSecondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, PLSpacing.lg)
                Spacer()
            }
        }
        .onAppear {
            Task {
                do {
                    try await viewModel.fetchMeals(username: username)
                } catch {
                    AppBanner.report("load your meals", error)
                }
            }
        }
    }

    private func deleteMeal(_ meal: Meal) {
        viewModel.meals.removeAll { $0.id == meal.id }
        Task {
            do {
                try await viewModel.deleteMeal(username: username, mealID: meal.id)
            } catch {
                await MainActor.run {
                    viewModel.meals.append(meal)
                }
                AppBanner.report("delete the meal", error, retry: { deleteMeal(meal) })
            }
        }
    }
}

// Preview for SwiftUI canvas
struct MealsView_Previews: PreviewProvider {
    static var previews: some View {
        MealsView()
    }
}
