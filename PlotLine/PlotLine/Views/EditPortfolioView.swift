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
    /// the Stocks tab being edited (Brokerage or Roth IRA)
    let account: InvestmentQuizView.InvestmentAccount
    var onSaved: (() -> Void)? = nil
    @State var saving = false
    @State var saveError: String?

    var body: some View {
        ScrollView {
            VStack(spacing: PLSpacing.lg) {
                // Editable Pie Chart
                PieChartView(assets: $assets, editable: true, selectedAssetID: $selectedAssetID)
                    .frame(height: 280)
                    .plCard()

                VStack(spacing: PLSpacing.sm) {
                    PLSectionHeader(title: "Holdings · tap one to edit")
                    VStack(spacing: 0) {
                        ForEach(Array(assets.enumerated()), id: \.element.id) { index, asset in
                            if index > 0 { Divider() }
                            HStack {
                                Text(asset.name)
                                    .font(.body.weight(.semibold))
                                Spacer()
                                Text("\(asset.percentage, specifier: "%.0f")%")
                                    .foregroundColor(PLColor.textSecondary)
                                Text("$\(asset.amount, specifier: "%.2f")")
                                    .monospacedDigit()
                                    .frame(minWidth: 90, alignment: .trailing)
                            }
                            .padding(.vertical, 10)
                            .padding(.horizontal, 8)
                            .background(selectedAssetID == asset.id ? PLColor.accent.opacity(0.12) : Color.clear)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .contentShape(Rectangle())
                            .onTapGesture { selectedAssetID = asset.id }
                        }
                    }
                    .plCard()
                }

                if let selectedIndex = assets.firstIndex(where: { $0.id == selectedAssetID }) {
                    VStack(spacing: PLSpacing.sm) {
                        PLSectionHeader(title: "Edit \(assets[selectedIndex].name)")
                        VStack(spacing: 12) {
                            PLFieldRow(label: "Symbol", placeholder: "e.g. VTI", text: $assets[selectedIndex].name)
                            Divider()
                            HStack {
                                Text("Allocation")
                                Slider(value: $assets[selectedIndex].percentage, in: 0...100, onEditingChanged: { _ in
                                    normalizePercentages(editedIndex: selectedIndex)
                                })
                                Text("\(assets[selectedIndex].percentage, specifier: "%.0f")%")
                                    .monospacedDigit()
                                    .frame(width: 44, alignment: .trailing)
                            }
                        }
                        .plCard()
                    }
                }

                VStack(spacing: PLSpacing.sm) {
                    PLSectionHeader(title: "Investing plan")
                    VStack(spacing: 0) {
                        PLFieldRow(label: "How often", placeholder: "e.g. Monthly", text: $investmentFrequency)
                        Divider()
                        HStack(spacing: 12) {
                            Text("Amount")
                            TextField("Total amount", value: $totalAmount, formatter: NumberFormatter.currency)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .foregroundColor(PLColor.textSecondary)
                                .onChange(of: totalAmount) { _, _ in
                                    updateAmountsFromTotal()
                                }
                        }
                        .padding(.vertical, 6)
                    }
                    .plCard()
                }

                Button(saving ? "Saving…" : "Save Portfolio") {
                    saveUpdatedPortfolio()
                }
                .buttonStyle(PrimaryButton())
                .disabled(saving)
            }
            .padding(.horizontal, PLSpacing.lg)
            .padding(.vertical, PLSpacing.md)
        }
        .navigationTitle("Edit \(account.rawValue)")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            updateAmountsFromTotal()
        }
        .alert("Couldn't save your portfolio", isPresented: Binding(
            get: { saveError != nil },
            set: { if !$0 { saveError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(saveError ?? "")
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
            // the Stocks page reads symbols in capitals (VTI, BRK.B)
            let symbol = asset.name.trimmingCharacters(in: .whitespaces).uppercased()
            portfolioText += "**\(symbol)** - \(Int(asset.percentage.rounded()))% - $\(String(format: "%.2f", asset.amount))\n"
        }
        //portfolioText += "\nInvest: \(investmentFrequency)\nAmount: $\(String(format: "%.2f", totalAmount))"
        portfolioText += "\n### Investment Frequency and Amount\n"
        portfolioText += "- When to Invest: \(investmentFrequency)\n"
        portfolioText += "- Total Investment per Month: $\(String(format: "%.2f", totalAmount))"

        let payload = SavedPortfolioPayload(
                username: username,
                portfolio: portfolioText,
                riskTolerance: "Edited",
                account: account.apiValue
        )

        guard let jsonData = try? JSONEncoder().encode(payload),
              let url = URL(string: "\(BackendConfig.baseURLString)/api/llm/portfolio/save") else { return }

        var request = URLRequest(url: url)
        BackendConfig.addApiKey(to: &request)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = jsonData

        saving = true
        URLSession.shared.dataTask(with: request) { _, response, error in
            let ok = (response as? HTTPURLResponse).map { (200...299).contains($0.statusCode) } ?? false
            DispatchQueue.main.async {
                saving = false
                guard ok else {
                    // stay here so the edits aren't lost
                    saveError = error?.localizedDescription ?? "Your changes weren't saved. Try again in a moment."
                    return
                }
                onSaved?()
                presentationMode.wrappedValue.dismiss()
            }
        }.resume()
    }
}

struct SavedPortfolioPayload: Codable {
    let username: String
    let portfolio: String
    let riskTolerance: String
    let account: String
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
