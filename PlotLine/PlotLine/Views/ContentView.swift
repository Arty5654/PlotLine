//
//  ContentView.swift
//  PlotLine
//
//  Created by Alex Younkers on 2/4/25.
//

import SwiftUI

struct ContentView: View {
    
    @EnvironmentObject var session: AuthViewModel
    @EnvironmentObject var calendarVM: CalendarViewModel
    
    let username = UserDefaults.standard.string(forKey: "loggedInUsername") ?? "Guest"
    @State private var isProfilePresented = false

    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack() {
                    
                    //logo
                    logoImage
                        .padding(.bottom, 20)
                    Spacer()
                    
                    // widgets
                    VStack(spacing: 25) {
                        
                        // Today's Events Widget
                        CalendarWidget()
                            .environmentObject(calendarVM)
                            .padding(.horizontal)
                        
                        
                        NavigationLink(destination: BudgetView().environmentObject(calendarVM)) {
                            Label("Budget", systemImage: "creditcard.fill")
                                .font(.headline)
                                .padding()
                                .frame(maxWidth: .infinity)
                                .background(Color.green)
                                .cornerRadius(8)
                                .foregroundColor(.white)
                        }

                        NavigationLink(destination: TopGroceryListView()) {
                            Label("Grocery Lists", systemImage: "cart.fill")
                                .font(.headline)
                                .padding()
                                .frame(maxWidth: .infinity)
                                .background(Color.green)
                                .cornerRadius(8)
                                .foregroundColor(.white)
                        }

                        NavigationLink(destination: WeeklyGoalsView()) {
                            Label("Goals", systemImage: "list.bullet.rectangle.fill")
                                .font(.headline)
                                .padding()
                                .frame(maxWidth: .infinity)
                                .background(Color.green)
                                .cornerRadius(8)
                                .foregroundColor(.white)
                        }
                    }
                    .padding([.horizontal, .bottom])
                    
                }
                .padding()
            }
            .ignoresSafeArea(edges: .bottom)
            .navigationBarItems(
                leading: friendPageButton,
                trailing: profileButton
            )
            .sheet(isPresented: $isProfilePresented) {
                ProfileView().environmentObject(session)
            }
        }
    }
    
    private var profileButton: some View {
            Button(action: {
                isProfilePresented = true
            }) {
                Image(systemName: "person.circle.fill")
                    .resizable()
                    .frame(width: 28, height: 28)
                    .foregroundColor(.blue)
            }
        }
    
    private var friendPageButton: some View {
        Button(action: {
            // TODO: make friends page
        }) {
            Image(systemName: "person.2.fill")
                .resizable()
                .frame(width: 28, height: 28)
                .foregroundColor(.blue)
        }
    }

    
    private var logoImage: some View {
        Image("PlotLineLogo")
            .resizable()
            .scaledToFit()
            .frame(width: 100, height: 100)
    }
}


struct CalendarWidget: View {
    
    @EnvironmentObject var viewModel: CalendarViewModel

    var body: some View {
        NavigationLink(destination: CalendarView().environmentObject(viewModel)) {
            VStack(alignment: .leading, spacing: 8) {
                ZStack {
                    Text("Today's Events")
                        .font(.custom("AvenirNext-Bold", size: 18))
                        .foregroundColor(.blue)
                                    
                    HStack {
                        Spacer()
                        Image(systemName: "calendar")
                            .foregroundColor(.green)
                            .font(.title3)
                    }
                }
                                .padding(.horizontal)
                let todayEvents = viewModel.eventsOnDay(Date())

                if todayEvents.isEmpty {
                    Text("No events today")
                        .foregroundColor(.gray)
                        .italic()
                        .frame(maxWidth: .infinity, alignment: .center)
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(todayEvents) { event in
                            HStack {
                                // Bullet point and event title
                                Text("• \(event.title)")
                                    .font(.body)
                                    .bold()
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                
                                if (event.eventType == "rent") {
                                    
                                    Text("Due Today!")
                                        .font(.subheadline)
                                        .foregroundColor(.red)
                                        .frame(alignment: .trailing)
                                    
                                } else if (event.eventType.lowercased().starts(with: "subscription")) {
                                    Text("Billed Today!")
                                        .font(.subheadline)
                                        .foregroundColor(.orange)
                                        .frame(alignment: .trailing)
                                } else if (event.startDate != event.endDate) {
                                    Text("Through \(formattedEndDate(event.endDate))")
                                        .font(.subheadline)
                                        .foregroundColor(.gray)
                                        .frame(alignment: .trailing)
                                }
                                
                            }
                        }
                    }
                }
            }
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(12)
            .shadow(color: Color.black.opacity(0.2), radius: 6, x: 0, y: 3)
        }
        .buttonStyle(PlainButtonStyle())
    }


    private func formattedEndDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM dd"
        return formatter.string(from: date)
    }
}






#Preview {
    ContentView()
        .environmentObject(AuthViewModel())
        .environmentObject(CalendarViewModel())
}
