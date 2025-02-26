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
            Image(systemName: "globe")
                .imageScale(.large)
                .foregroundStyle(.tint)
            Text("PlotLine - \(username)")
        }
        .padding()
        
        Spacer()
        
        NavigationLink(destination: BudgetView()) {
            Text("Go to budget page")
                .foregroundColor(.white)
                .padding()
                .frame(maxWidth: .infinity)
                .background(Color(.red)) // Green theme color
                .cornerRadius(8)
                
        }
        .padding()
        
        Spacer()
        
        NavigationLink(destination: MainGroceryListView()) {
            Text("Go to Grocery Lists Page")
                .foregroundColor(.white)
                .padding()
                .frame(maxWidth: .infinity)
                .background(Color(.green)) // Green theme color
                .cornerRadius(8)
                
        }
        .padding()
        
        Spacer()
        
        NavigationLink(destination: ProfileView()) {
            Text("Go to profile page")
                .foregroundColor(.white)
                .padding()
                .frame(maxWidth: .infinity)
                .background(Color(.green)) // Green theme color
                .cornerRadius(8)
                
        }
        .padding()
        
        
        Spacer()
        
        NavigationLink(destination: WeeklyGoalsView()) {
            Text("Go to Goals page")
                .foregroundColor(.white)
                .padding()
                .frame(maxWidth: .infinity)
                .background(Color(.green)) // Green theme color
                .cornerRadius(8)
                
        }
        .padding()
        
        
        Spacer()
        
        Button(action: {
            //todo call auth function
            
            session.signOut()
        }) {
            Text("Sign Out")
                .foregroundColor(.white)
                .padding()
                .frame(maxWidth: .infinity)
                .background(Color(.red)) // Green theme color
                .cornerRadius(8)
        }
        .padding(.horizontal)
    }
}

#Preview {
    ContentView()
        .environmentObject(AuthViewModel())
}
