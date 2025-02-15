//
//  IncomeRentView.swift
//  PlotLine
//
//  Created by Arteom Avetissian on 2/13/25.
//

import SwiftUI

struct IncomeRentView: View {
    @State private var income: String = ""
    @State private var rent: String = ""
    @State private var showWarning: Bool = false
    @State private var showAlert: Bool = false
    @State private var proceedWithSave: Bool = false // Flag to save after alert
    @Environment(\.presentationMode) var presentationMode
    
    // Fetch logged-in username
    private var username: String {
        return UserDefaults.standard.string(forKey: "loggedInUsername") ?? "UnknownUser"
    }

    var body: some View {
        VStack(spacing: 20) {
            Text("Enter Your Income & Rent")
                .font(.title2)
                .bold()

            TextField("Enter Monthly Income (Pre-Tax)", text: $income)
                .keyboardType(.decimalPad)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .padding()

            TextField("Enter Monthly Rent", text: $rent)
                .keyboardType(.decimalPad)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .padding()

            Button(action: checkRentThreshold) {
                Text("Save")
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .cornerRadius(10)
            }
            .padding()
            .alert(isPresented: $showAlert) {
                Alert(
                    title: Text("Warning"),
                    message: Text("⚠️ Your rent exceeds 30% of your income."),
                    primaryButton: .default(Text("OK"), action: {
                        proceedWithSave = true
                        saveToBackend() // Save data after alert dismissal
                    }),
                    secondaryButton: .cancel()
                )
            }

            Spacer()
        }
        .padding()
        .navigationTitle("Income & Rent")
    }

    // Check if rent is too high before saving
    private func checkRentThreshold() {
        guard let incomeValue = Double(income), let rentValue = Double(rent) else { return }

        if rentValue >= (incomeValue * 0.3) {
            showWarning = true
            showAlert = true
        } else {
            proceedWithSave = true
            saveToBackend()
        }
    }

    // Save Data to Backend
    private func saveToBackend() {
        guard proceedWithSave, let incomeValue = Double(income), let rentValue = Double(rent) else { return }

        let userIncomeData: [String: Any] = [
            "username": username,
            "income": incomeValue,
            "rent": rentValue
        ]

        guard let jsonData = try? JSONSerialization.data(withJSONObject: userIncomeData) else { return }

        let url = URL(string: "http://localhost:8080/api/income")!
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
