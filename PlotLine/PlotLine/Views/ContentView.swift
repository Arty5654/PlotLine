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
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack {
                    Image("PlotLineLogo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 150, height: 150) // Adjust size as needed
                        .padding(.bottom, 0)
                    
                    // Title
                    Text("PlotLine")
                        .font(.custom("AvenirNext-Bold", size: 36))
                        .foregroundColor(Color(.blue))
                        .padding(.bottom, 10)
                    
                    // Today's Events Widget
                    CalendarWidget()
                        .environmentObject(calendarVM)
                        .padding(.horizontal)

                    Spacer()

                    // Main Buttons
                    VStack(spacing: 15) {
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
            .ignoresSafeArea(edges: .bottom) // Prevents content from being cut off
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    NavigationLink(destination: ProfileView().environmentObject(session)) {
                        Image(systemName: "person.circle.fill")
                            .resizable()
                            .frame(width: 28, height: 28)
                            .foregroundColor(.blue)
                    }
                }
            }
        }
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
                                        .foregroundColor(.yellow)
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
