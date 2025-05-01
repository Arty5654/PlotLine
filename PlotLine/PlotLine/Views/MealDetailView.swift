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
            VStack(alignment: .leading, spacing: 16) {
                Text(meal.mealName)
                    .font(.largeTitle)
                    .fontWeight(.bold)

                Text("Ingredients")
                    .font(.title2)
                    .fontWeight(.semibold)
                ForEach(meal.ingredients, id: \.self) { ingredient in
                    Text("• \(ingredient)")
                        .font(.body)
                }

                Text("Recipe")
                    .font(.title2)
                    .fontWeight(.semibold)
                ForEach(meal.recipe, id: \.self) { step in
                    Text("• \(step)")
                        .font(.body)
                }

                if !meal.optionalToppings.isEmpty {
                    Text("Optional Toppings")
                        .font(.title2)
                        .fontWeight(.semibold)
                    ForEach(meal.optionalToppings, id: \.self) { topping in
                        Text("• \(topping)")
                            .font(.body)
                    }
                }
            }
            .padding()
        }
        .navigationBarTitle(Text(meal.mealName), displayMode: .inline)
    }
}
