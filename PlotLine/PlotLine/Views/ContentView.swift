//
//  ContentView.swift
//  PlotLine
//
//  Created by Alex Younkers on 2/4/25.
//

import SwiftUI

struct ContentView: View {
    
    @EnvironmentObject var session: AuthViewModel
    
    let username = UserDefaults.standard.string(forKey: "loggedInUsername") ?? "Guest"
    
    var body: some View {
        VStack {
            // Header Section with Username
            HStack {
                Text("Welcome to PlotLine, \(username)!")
                    .font(.title)
                    .fontWeight(.bold)
            }
            .padding(.top, 40)
            
            Spacer()
            
            // Buttons with icons
            VStack(spacing: 20) {
                NavigationLink(destination: ProfileView()) {
                    Label("Profile", systemImage: "person.circle.fill")
                        .font(.headline)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color(.blue))
                        .cornerRadius(8)
                        .foregroundColor(.white)
                }
                
                NavigationLink(destination: BudgetView()) {
                    Label("Budget", systemImage: "creditcard.fill")
                        .font(.headline)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color(.green))
                        .cornerRadius(8)
                        .foregroundColor(.white)
                }
                
                NavigationLink(destination: TopGroceryListView()) {
                    Label("Grocery Lists", systemImage: "cart.fill")
                        .font(.headline)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color(.green))
                        .cornerRadius(8)
                        .foregroundColor(.white)
                }
                
                NavigationLink(destination: WeeklyGoalsView()) {
                    Label("Goals", systemImage: "list.bullet.rectangle.fill")
                        .font(.headline)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color(.green))
                        .cornerRadius(8)
                        .foregroundColor(.white)
                }
            }
            .padding([.horizontal, .bottom])
            
            Spacer()
            
            // Sign out button
            Button(action: {
                // TODO: Call auth function
                session.signOut()
            }) {
                Label("Sign Out", systemImage: "arrow.backward.circle.fill")
                    .font(.headline)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color(.red))
                    .cornerRadius(8)
                    .foregroundColor(.white)
            }
            .padding([.horizontal, .bottom])
        }
        .padding()
    }
}

#Preview {
    ContentView()
        .environmentObject(AuthViewModel())
}
