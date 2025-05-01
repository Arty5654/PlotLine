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
        NavigationView {
            VStack {
                // Search bar
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.gray)
                    
                    TextField("Search meals...", text: $searchText)
                        .padding(8)
                        .background(Color(.systemGray6))
                        .cornerRadius(10)
                        .padding(.trailing, 8)
                    
                    if !searchText.isEmpty {
                        Button(action: {
                            searchText = ""
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.gray)
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.top, 10)
                
                if !viewModel.meals.isEmpty {
                    if filteredMeals.isEmpty {
                        VStack {
                            Spacer()
                            Text("No meals match your search")
                                .font(.headline)
                                .foregroundColor(.gray)
                            Spacer()
                        }
                    } else {
                        List {
                            ForEach(filteredMeals) { meal in
                                NavigationLink(destination: MealDetailView(meal: meal)) {
                                    Text(meal.mealName)
                                        .font(.headline)
                                }
                            }
                        }
                        .listStyle(PlainListStyle())
                    }
                } else {
                    Spacer()
                    Text("No meals yet!")
                        .font(.headline)
                        .padding()
                    Spacer()
                }
            }
            .onAppear {
                Task {
                    do {
                        try await viewModel.fetchMeals(username: username)
                    } catch {
                        print("Error fetching meals: \(error)")
                    }
                }
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
