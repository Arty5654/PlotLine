//
//  IncomeRentView.swift
//  PlotLine
//
//  Created by Arteom Avetissian on 2/14/25.

import SwiftUI

struct IncomeRentView: View {
    @State private var income: String = ""
    @State private var rent: String = ""
    @State private var showWarning: Bool = false
    @Environment(\.presentationMode) var presentationMode

    var body: some View {
        VStack(spacing: 20) {
            Text("Enter Your Income & Rent")
                .font(.title2)
                .bold()

            TextField("Enter Monthly Income ($)", text: $income)
                .keyboardType(.decimalPad)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .padding()

            TextField("Enter Monthly Rent ($)", text: $rent)
                .keyboardType(.decimalPad)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .padding()

            if showWarning {
                Text("⚠️ Your rent exceeds 30% of your income.")
                    .foregroundColor(.red)
                    .bold()
            }

            Button(action: saveIncomeAndRent) {
                Text("Save")
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .cornerRadius(10)
            }
            .padding()

            Spacer()
        }
        .padding()
        .navigationTitle("Income & Rent")
    }

    private func saveIncomeAndRent() {
        guard let incomeValue = Double(income), let rentValue = Double(rent) else { return }
        
        if rentValue >= (incomeValue * 0.3) {
            showWarning = true
        } else {
            showWarning = false
        }

        // Backend API call to save income & rent
        let userIncomeData = ["income": incomeValue, "rent": rentValue]

        guard let jsonData = try? JSONSerialization.data(withJSONObject: userIncomeData) else { return }

        let url = URL(string: "https://localhost:8080/api/income")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = jsonData

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                print("Error saving data: \(error)")
                return
            }
            print("Data successfully saved")
        }.resume()

        presentationMode.wrappedValue.dismiss()
    }
}

// MARK: - Preview
#Preview {
    IncomeRentView()
}
