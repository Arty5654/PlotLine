//
//  MealDetailView.swift
//  PlotLine
//
//  Created by Yash Mehta on 5/1/25.
//

import SwiftUI

struct MealDetailView: View {
    var meal: Meal

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: PLSpacing.lg) {
                Text(meal.mealName)
                    .font(.title.weight(.bold))
                    .padding(.horizontal, 4)

                VStack(spacing: PLSpacing.sm) {
                    PLSectionHeader(title: "Ingredients (\(meal.ingredients.count))")
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(meal.ingredients, id: \.self) { ingredient in
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: "circle.fill")
                                    .font(.system(size: 6))
                                    .foregroundColor(PLColor.success)
                                    .padding(.top, 7)
                                Text(ingredient)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .plCard()
                }

                VStack(spacing: PLSpacing.sm) {
                    PLSectionHeader(title: "Recipe")
                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(Array(meal.recipe.enumerated()), id: \.offset) { index, step in
                            HStack(alignment: .top, spacing: 12) {
                                Text("\(index + 1)")
                                    .font(.footnote.weight(.bold))
                                    .foregroundColor(.white)
                                    .frame(width: 24, height: 24)
                                    .background(PLColor.accent)
                                    .clipShape(Circle())
                                Text(step)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .plCard()
                }

                if !meal.optionalToppings.isEmpty {
                    VStack(spacing: PLSpacing.sm) {
                        PLSectionHeader(title: "Optional toppings")
                        Text(meal.optionalToppings.joined(separator: " · "))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .plCard()
                    }
                }
            }
            .padding(.horizontal, PLSpacing.lg)
            .padding(.vertical, PLSpacing.md)
        }
        .navigationBarTitle(Text(meal.mealName), displayMode: .inline)
    }
}
