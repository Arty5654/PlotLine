//
//  BudgetView.swift
//  PlotLine
//
//  Created by Arteom Avetissian on 2/13/25.
//

import SwiftUI
import Charts
import Foundation

struct BudgetView: View {
    @State private var selectedTab = "Budgeting" // Toggle between Budgeting & Stocks
    
    @EnvironmentObject var viewModel: CalendarViewModel

    //@EnvironmentObject var calendarViewModel: CalendarViewModel
    @EnvironmentObject var friendVM: FriendsViewModel


    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Toggle Button for Budgeting and Stocks
                Picker("View", selection: $selectedTab) {
                    Text("Budgeting").tag("Budgeting")
                    Text("Stocks").tag("Stocks")
                }
                .pickerStyle(SegmentedPickerStyle())
                .padding()

                Divider()

                // Toggle between views
                Group {
                    if selectedTab == "Budgeting" {
                        ScrollView {
                            BudgetSection()
                                .environmentObject(viewModel)
                        }
                    } else {
                        InvestmentHomeView()
                        
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .navigationTitle("Dashboard")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

// MARK: - Budgeting Section
struct BudgetSection: View {
    @State private var selectedChartView = "Weekly"
    @EnvironmentObject var calendarVM: CalendarViewModel

    private var quizCompleted: Bool {
        UserDefaults.standard.bool(forKey: "budgetQuizCompleted")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text("Budgeting")
                .font(.largeTitle)
                .bold()

            if !quizCompleted {
                NavigationLink(destination: BudgetQuizView().environmentObject(calendarVM)) {
                    BudgetButtonLabel(title: "Take the AI Powered Budget Quiz")
                }
            } else {
                // Spending Trends Chart
                VStack {
                    Text("Spending Trends")
                        .font(.headline)

                    Picker("Chart Type", selection: $selectedChartView) {
                        Text("Weekly").tag("Weekly")
                        Text("Monthly").tag("Monthly")
                    }
                    .pickerStyle(SegmentedPickerStyle())

                    SpendingChartView(chartType: selectedChartView)
                }
                .padding()
                .background(Color(.systemBackground))
                .cornerRadius(10)
                .shadow(radius: 3)

                // Budgeting Tools
                Group {
                    NavigationLink(destination: BudgetQuizView().environmentObject(calendarVM)) {
                        BudgetButtonLabel(title: "Take the AI Powered Budget Quiz Again")
                    }
                    
                    NavigationLink(destination: IncomeRentView().environmentObject(calendarVM)) {
                        BudgetButtonLabel(title: "Input Recurring Income & Rent")
                    }

                    NavigationLink(destination: WeeklyMonthlyCostView().environmentObject(calendarVM)) {
                        BudgetButtonLabel(title: "Input Weekly/Monthly Costs")
                    }

                    NavigationLink(destination: BudgetInputView()) {
                        BudgetButtonLabel(title: "Create Weekly/Monthly Budget")
                    }

                    NavigationLink(destination: SpendingPeriodView()) {
                        BudgetButtonLabel(title: "Input Spending for a Time Period")
                    }
                }
            }
        }
        .padding()
        .background(Color.blue.opacity(0.1))
        .cornerRadius(15)
    }
}


// MARK: - Spending Chart View
struct SpendingChartView: View {
    @State private var spendingData: [SpendingEntry] = []
    @State private var totalBudget: Double = 0.0
    let chartType: String  // "Weekly" or "Monthly"
    private var username: String {
        return UserDefaults.standard.string(forKey: "loggedInUsername") ?? "UnknownUser"
    }

    var body: some View {
        VStack {
            Text("\(chartType) Spending Chart")
                .font(.subheadline)
            
            Chart {
                // Plot user spending (bar chart)
                ForEach(spendingData, id: \.category) { entry in
                    BarMark(
                        x: .value("Category", entry.category),
                        y: .value("Spending", entry.amount)
                    )
                    .foregroundStyle(.blue)
                }

                // Plot budget line
                RuleMark(y: .value("Total Budget", totalBudget))
                    .foregroundStyle(.red)
                    .lineStyle(StrokeStyle(lineWidth: 2, dash: [5])) // Dashed line for budget
                    .annotation(position: .top, alignment: .trailing) {
                        Text("Budget: $\(totalBudget, specifier: "%.2f")")
                            .font(.caption)
                            .foregroundColor(.red)
                    }
            }
            .frame(height: 250)
            .padding()
            .onAppear {
                fetchSpendingData()
                fetchBudgetData()
            }
            .onChange(of: chartType) {
                fetchSpendingData()
                fetchBudgetData()
            }
        }
    }

    // Fetch user spending data from backend
    private func fetchSpendingData() {
        guard let url = URL(string: "http://localhost:8080/api/costs/\(username)/\(chartType.lowercased())") else {
            print("❌ Invalid URL for spending data")
            return
        }

        print("📡 Fetching spending data for \(chartType)")

        URLSession.shared.dataTask(with: url) { data, response, error in
            if let error = error {
                print("Error fetching spending data: \(error.localizedDescription)")
                return
            }

            guard let data = data, !data.isEmpty else {
                print("No spending data found, initializing empty values.")
                DispatchQueue.main.async {
                    self.spendingData = []
                }
                return
            }

            do {
                let decodedResponse = try JSONDecoder().decode(WeeklyMonthlyCostResponse.self, from: data)
                DispatchQueue.main.async {
                    self.spendingData = decodedResponse.costs.map { SpendingEntry(category: $0.key, amount: $0.value) }
                }
            } catch {
                print("Failed to decode spending data:", error)
                DispatchQueue.main.async {
                    self.spendingData = []
                }
            }
        }.resume()
    }

    // Fetch user budget data from backend and calculate total sum
    private func fetchBudgetData() {
        guard let url = URL(string: "http://localhost:8080/api/budget/\(username)/\(chartType.lowercased())") else {
            print("Invalid URL for budget data")
            return
        }

        print("📡 Fetching budget data for \(chartType)")

        URLSession.shared.dataTask(with: url) { data, response, error in
            if let error = error {
                print("Error fetching budget data: \(error.localizedDescription)")
                return
            }

            guard let data = data, !data.isEmpty else {
                print("No budget data found, setting totalBudget to 0.")
                DispatchQueue.main.async {
                    self.totalBudget = 0.0
                }
                return
            }

            do {
                let decodedResponse = try JSONDecoder().decode(BudgetResponse.self, from: data)
                DispatchQueue.main.async {
                    self.totalBudget = decodedResponse.budget.values.reduce(0, +) // Sum all budget categories
                }
            } catch {
                print("Failed to decode budget data:", error)
                DispatchQueue.main.async {
                    self.totalBudget = 0.0
                }
            }
        }.resume()
    }
}

// Spending Entry Model
struct SpendingEntry {
    let category: String
    let amount: Double
}

// Decodable Response Model for Spending
//struct WeeklyMonthlyCostResponse: Codable {
//    let username: String
//    let type: String
//    let costs: [String: Double]
//}

// Decodable Response Model for Budget
//struct BudgetResponse: Codable {
//    let username: String
//    let type: String
//    let budget: [String: Double]
//}

// MARK: - Budget Button Label
struct BudgetButtonLabel: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.headline)
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color.blue)
            .cornerRadius(10)
            .shadow(radius: 3)
    }
}

// MARK: - Placeholder Stock Tracking Section
struct StockTrackingView: View {
    var body: some View {
        VStack {
            Text("Stock Tracking")
                .font(.largeTitle)
                .bold()
                .padding(.bottom, 10)
                .frame(maxWidth: .infinity, minHeight: 300)
                .background(Color.green.opacity(0.1))
                .cornerRadius(15)
                .shadow(radius: 3)
        }
    }
}

// MARK: - Preview
#Preview {
    BudgetView()
}
