//
//  EditPortfolioView.swift
//  PlotLine
//
//  Created by Arteom Avetissian on 3/30/25.
//

import SwiftUI
import Charts

struct EditPortfolioView: View {
    @Environment(\.presentationMode) var presentationMode
    let username = UserDefaults.standard.string(forKey: "loggedInUsername") ?? "UnknownUser"

    @State var assets: [EditableAsset]
    @State var investmentFrequency: String
    @State var totalAmount: Double
    @State var selectedAssetID: UUID? = nil

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Text("Edit Your Portfolio")
                    .font(.title2)
                    .bold()

                // Editable Pie Chart
                PieChartView(assets: $assets, editable: true, selectedAssetID: $selectedAssetID)
                    .frame(height: 300)
                
                // Asset List: Tap to select
                ForEach(assets) { asset in
                    HStack {
                        Text(asset.name)
                        Spacer()
                        Text("\(asset.percentage, specifier: "%.0f")% - $\(asset.amount, specifier: "%.2f")")
                    }
                    .padding(.horizontal)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        selectedAssetID = asset.id
                    }
                    .background(selectedAssetID == asset.id ? Color.blue.opacity(0.1) : Color.clear)
                    .cornerRadius(8)
                }

                if let selectedIndex = assets.firstIndex(where: { $0.id == selectedAssetID }) {
                    VStack(spacing: 12) {
                        Text("Edit \(assets[selectedIndex].name)")
                            .font(.headline)

                        TextField("Stock Name", text: $assets[selectedIndex].name)

                        HStack {
                            Text("Allocation:")
                            Slider(value: $assets[selectedIndex].percentage, in: 0...100, onEditingChanged: { _ in
                                normalizePercentages(editedIndex: selectedIndex)
                            })
                            Text("\(assets[selectedIndex].percentage, specifier: "%.0f")%")
                        }
                    }
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(10)
                }

                Divider()

                VStack(spacing: 8) {
                    TextField("Investment Frequency (e.g., Monthly)", text: $investmentFrequency)
                    TextField("Total Investment Amount", value: $totalAmount, formatter: NumberFormatter.currency)
                        .keyboardType(.decimalPad)
                        .onChange(of: totalAmount) { _ in
                            updateAmountsFromTotal()
                        }
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(10)

                Button("Save Portfolio") {
                    saveUpdatedPortfolio()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
        }
        .navigationTitle("Edit Portfolio")
        .onAppear {
            updateAmountsFromTotal()
        }
    }

    func normalizePercentages(editedIndex: Int) {
        let totalBefore = assets.map { $0.percentage }.reduce(0, +)
        let delta = totalBefore - 100

        if abs(delta) < 0.01 { return }

        let otherIndices = assets.indices.filter { $0 != editedIndex }
        let totalOthers = otherIndices.map { assets[$0].percentage }.reduce(0, +)

        for i in otherIndices {
            let share = totalOthers > 0 ? assets[i].percentage / totalOthers : 1.0 / Double(otherIndices.count)
            assets[i].percentage -= share * delta
            assets[i].percentage = max(0, min(100, assets[i].percentage))
        }

        updateAmountsFromTotal()
    }

    func updateAmountsFromTotal() {
        for i in assets.indices {
            assets[i].amount = totalAmount * (assets[i].percentage / 100)
        }
    }

    func saveUpdatedPortfolio() {
        var portfolioText = "### Edited Portfolio:\n"
        for asset in assets {
            portfolioText += "**\(asset.name)** - \(Int(asset.percentage))% - $\(String(format: "%.2f", asset.amount))\n"
        }
        //portfolioText += "\nInvest: \(investmentFrequency)\nAmount: $\(String(format: "%.2f", totalAmount))"
        portfolioText += "\n### Investment Frequency and Amount\n"
        portfolioText += "- When to Invest: \(investmentFrequency)\n"
        portfolioText += "- Total Investment per Month: $\(String(format: "%.2f", totalAmount))"

        let payload = SavedPortfolioPayload(
                username: username,
                portfolio: portfolioText,
                riskTolerance: "Edited"
        )

        guard let jsonData = try? JSONEncoder().encode(payload),
              let url = URL(string: "http://localhost:8080/api/llm/portfolio/save") else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = jsonData

        URLSession.shared.dataTask(with: request) { _, _, _ in
            DispatchQueue.main.async {
                presentationMode.wrappedValue.dismiss()
            }
        }.resume()
    }
}

struct SavedPortfolioPayload: Codable {
    let username: String
    let portfolio: String
    let riskTolerance: String
}

struct EditableAsset: Identifiable {
    var id = UUID()
    var name: String
    var percentage: Double
    var amount: Double
}

extension NumberFormatter {
    static var currency: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.maximumFractionDigits = 2
        return formatter
    }
}
