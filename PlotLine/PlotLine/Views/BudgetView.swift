//
//  BudgetView.swift
//  PlotLine
//
//  Created by Arteom Avetissian on 2/13/25.
//

import SwiftUI
import Charts

struct BudgetView: View {
    @State private var selectedTab = "Budgeting" // Toggle between Budgeting & Stocks

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                // Toggle Button for Budgeting and Stocks
                Picker("View", selection: $selectedTab) {
                    Text("Budgeting").tag("Budgeting")
                    Text("Stocks").tag("Stocks")
                }
                .pickerStyle(SegmentedPickerStyle())
                .padding()

                if selectedTab == "Budgeting" {
                    BudgetSection()
                } else {
                    StockTrackingView()
                }

                Spacer()
            }
            .padding()
        }
    }
}

// MARK: - Budgeting Section
struct BudgetSection: View {
    @State private var selectedChartView = "Weekly"

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text("Budgeting")
                .font(.largeTitle)
                .bold()

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

            // Navigation Links to IncomeRentView and Other Input Views
            NavigationLink(destination: IncomeRentView()) {
                BudgetButtonLabel(title: "Input Recurring Income & Rent")
            }

            NavigationLink(destination: WeeklyMonthlyCostView()) {
                BudgetButtonLabel(title: "Input Estimated Weekly/Monthly Costs")
            }

            NavigationLink(destination: IncomeRentView()) {
                BudgetButtonLabel(title: "Create Weekly/Monthly Budget")
            }

            NavigationLink(destination: IncomeRentView()) {
                BudgetButtonLabel(title: "Input Spending for a Time Period")
            }
        }
        .padding()
        .background(Color.blue.opacity(0.1))
        .cornerRadius(15)
    }
}

// MARK: - Spending Chart View
struct SpendingChartView: View {
    let chartType: String

    var body: some View {
        VStack {
            if chartType == "Weekly" {
                Text("Weekly Spending Chart")
                    .font(.subheadline)
            } else {
                Text("Monthly Spending Chart")
                    .font(.subheadline)
            }
            Chart {
                BarMark(x: .value("Day", "Mon"), y: .value("Spending", 50))
                BarMark(x: .value("Day", "Tue"), y: .value("Spending", 30))
                BarMark(x: .value("Day", "Wed"), y: .value("Spending", 70))
                BarMark(x: .value("Day", "Thu"), y: .value("Spending", 40))
                BarMark(x: .value("Day", "Fri"), y: .value("Spending", 60))
            }
            .frame(height: 200)
        }
        .padding()
    }
}

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

            Text("Stock Information Coming Soon...")
                .font(.headline)
                .padding()
        }
        .frame(maxWidth: .infinity, minHeight: 300)
        .background(Color.green.opacity(0.1))
        .cornerRadius(15)
        .shadow(radius: 3)
    }
}

// MARK: - Preview
#Preview {
    BudgetView()
}
