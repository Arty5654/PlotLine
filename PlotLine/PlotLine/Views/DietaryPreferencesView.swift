//
//  DietaryPreferencesView.swift
//  PlotLine
//
//  Created by Yash Mehta on 2/26/25.
//

import SwiftUI

struct DietaryPreferencesView: View {
    @Binding var dietaryRestrictions: DietaryRestrictions?
    var onClose: () -> Void
    
    // State variable to track whether we are editing
    @State private var isEditing = false
    
    @Environment(\.presentationMode) var presentationMode

    var body: some View {
        VStack {
            HStack {
                Text(isEditing ? "Edit Preferences" : "View Preferences")
                    .font(.title2)
                    .fontWeight(.bold)
                    .padding()
                    .frame(alignment: .leading)

                Spacer()

                Button(action: {
                    if isEditing {
                        // When Done is clicked, save changes
                        Task {
                            await updatePreferencesInBackend()
                        }
                    }
                    isEditing.toggle()
                }) {
                    Text(isEditing ? "Save" : "Edit")
                        .fontWeight(.bold)
                        .padding()
                        .background(Color.green)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                }
            }

            // Editable or non-editable form
            VStack(spacing: 20) {
                // Lactose Intolerant
                HStack {
                    Text("Lactose Intolerant:")
                        .frame(width: 180, alignment: .leading)
                    
                    if isEditing {
                        Toggle(isOn: Binding(
                            get: { dietaryRestrictions?.lactoseIntolerant ?? false },
                            set: { dietaryRestrictions?.lactoseIntolerant = $0 }
                        )) {
                            EmptyView()
                        }
                    } else {
                        Text(dietaryRestrictions?.lactoseIntolerant == true ? "Yes" : "No")
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                }
                .frame(height: 40)

                // Vegetarian
                HStack {
                    Text("Vegetarian:")
                        .frame(width: 180, alignment: .leading)
                    if isEditing {
                        Toggle(isOn: Binding(
                            get: { dietaryRestrictions?.vegetarian ?? false },
                            set: { dietaryRestrictions?.vegetarian = $0 }
                        )) {
                            EmptyView()
                        }
                    } else {
                        Text(dietaryRestrictions?.vegetarian == true ? "Yes" : "No")
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                }
                .frame(height: 40)

                // Vegan
                HStack {
                    Text("Vegan:")
                        .frame(width: 180, alignment: .leading)
                    if isEditing {
                        Toggle(isOn: Binding(
                            get: { dietaryRestrictions?.vegan ?? false },
                            set: { newValue in
                                        dietaryRestrictions?.vegan = newValue
                                        // If Vegan is selected, automatically select Vegetarian and Dairy Free
                                        if newValue {
                                            dietaryRestrictions?.vegetarian = true
                                            dietaryRestrictions?.dairyFree = true
                                        }
                                    }
                        )) {
                            EmptyView()
                        }
                    } else {
                        Text(dietaryRestrictions?.vegan == true ? "Yes" : "No")
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                }
                .frame(height: 40)

                // Gluten Free
                HStack {
                    Text("Gluten Free:")
                        .frame(width: 180, alignment: .leading)
                    if isEditing {
                        Toggle(isOn: Binding(
                            get: { dietaryRestrictions?.glutenFree ?? false },
                            set: { dietaryRestrictions?.glutenFree = $0 }
                        )) {
                            EmptyView()
                        }
                    } else {
                        Text(dietaryRestrictions?.glutenFree == true ? "Yes" : "No")
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                }
                .frame(height: 40)

                // Kosher
                HStack {
                    Text("Kosher:")
                        .frame(width: 180, alignment: .leading)
                    if isEditing {
                        Toggle(isOn: Binding(
                            get: { dietaryRestrictions?.kosher ?? false },
                            set: { dietaryRestrictions?.kosher = $0 }
                        )) {
                            EmptyView()
                        }
                    } else {
                        Text(dietaryRestrictions?.kosher == true ? "Yes" : "No")
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                }
                .frame(height: 40)

                // Dairy Free
                HStack {
                    Text("Dairy Free:")
                        .frame(width: 180, alignment: .leading)
                    if isEditing {
                        Toggle(isOn: Binding(
                            get: { dietaryRestrictions?.dairyFree ?? false },
                            set: { dietaryRestrictions?.dairyFree = $0 }
                        )) {
                            EmptyView()
                        }
                    } else {
                        Text(dietaryRestrictions?.dairyFree == true ? "Yes" : "No")
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                }
                .frame(height: 40)

                // Nut Free
                HStack {
                    Text("Nut Free:")
                        .frame(width: 180, alignment: .leading)
                    if isEditing {
                        Toggle(isOn: Binding(
                            get: { dietaryRestrictions?.nutFree ?? false },
                            set: { dietaryRestrictions?.nutFree = $0 }
                        )) {
                            EmptyView()
                        }
                    } else {
                        Text(dietaryRestrictions?.nutFree == true ? "Yes" : "No")
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                }
                .frame(height: 40)
            }

            Button(action: {
                onClose()
                presentationMode.wrappedValue.dismiss()
            }) {
                Text("Close")
                    .fontWeight(.bold)
                    .padding()
                    .background(Color.red)
                    .foregroundColor(.white)
                    .cornerRadius(10)
            }
            .padding()

            Spacer()
        }
        .padding()
        .frame(width: 350, height: 600) // Increased the size of the window
        .background(Color.white)
        .cornerRadius(20)
        .shadow(radius: 10)
        .padding(40)
    }

    // API call to update preferences
    func updatePreferencesInBackend() {
        guard let dietaryRestrictions = dietaryRestrictions else {
            return
        }
        
        // Proceed with the update API call without using `await` or `try`
        DietaryRestrictionsAPI.shared.updateDietaryRestrictions(
            username: dietaryRestrictions.username,
            dietaryRestrictions: dietaryRestrictions
        ) { result in
            switch result {
            case .success(let message):
                print("Dietary preferences updated successfully: \(message)")
            case .failure(let error):
                print(String(describing: error))
                print("Frontend Failed to update dietary preferences: \(error.localizedDescription)")
            }
        }
    }
}
