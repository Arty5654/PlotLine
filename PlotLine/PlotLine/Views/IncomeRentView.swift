import SwiftUI

struct IncomeRentView: View {
    @State private var income: String = ""
    @State private var rent: String = ""
    @State private var rentDueDate: Date = firstOfNextMonth()
    
    @State private var activeAlert: ActiveAlert? = nil
    
    @State private var shouldSave: Bool = false
    
    private var username: String {
        return UserDefaults.standard.string(forKey: "loggedInUsername") ?? "UnknownUser"
    }
    
    @EnvironmentObject var calendarViewModel: CalendarViewModel
    
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
            
            DatePicker("Next Rent Due Date", selection: $rentDueDate, displayedComponents: .date)
            
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
            
            Spacer()
        }
        .padding()
        .navigationTitle("Income & Rent")
        
        .alert(item: $activeAlert) { alertType in
            switch alertType {
                
            case .warning(let rentPercentage):
                return Alert(
                    title: Text("⚠️ High Rent Warning"),
                    message: Text(
                        "Your rent is **\(String(format: "%.1f", rentPercentage))%** of your income, which exceeds the recommended 30%."
                    ),
                    primaryButton: .default(Text("Proceed Anyway"), action: {
                        print("🔄 User confirmed warning, proceeding with save.")
                        DispatchQueue.main.async {
                            shouldSave = true
                            saveToBackend()
                        }
                    }),
                    secondaryButton: .cancel()
                )
                
            case .success:
                return Alert(
                    title: Text("✅ Success"),
                    message: Text("Your income and rent data has been saved successfully."),
                    dismissButton: .default(Text("OK"))
                )
            }
        }
        .onAppear {
            fetchIncomeData()
        }
    }
    
    // MARK: - Fetch Income & Rent from Database
    private func fetchIncomeData() {
        guard let url = URL(string: "http://localhost:8080/api/income/\(username)") else {
            print("❌ Invalid URL")
            return
        }
        
        //print("📡 Fetching income data for user:", username)
        
        URLSession.shared.dataTask(with: url) { data, response, error in
            if let error = error {
                //print("❌ Error fetching income data:", error.localizedDescription)
                return
            }
            
            guard let data = data, !data.isEmpty else {
                //print("⚠️ No data received from backend. Initializing default values.")
                DispatchQueue.main.async {
                    self.income = ""
                    self.rent = ""
                }
                return
            }
            
            do {
                let decodedData = try JSONDecoder().decode(IncomeRentResponse.self, from: data)
                //print("✅ Decoded Data:", decodedData)
                
                DispatchQueue.main.async {
                    self.income = String(decodedData.income)
                    self.rent = String(decodedData.rent)
                }
            } catch {
                //print("❌ Failed to decode JSON:", error)
                DispatchQueue.main.async {
                    self.income = ""
                    self.rent = ""
                }
            }
        }.resume()
    }
    
    // MARK: - Check if rent exceeds 30% before saving
    private func checkRentThreshold() {
        guard let incomeValue = Double(income),
              let rentValue = Double(rent),
              incomeValue > 0 else {
            //print("❌ Invalid numeric input. Income: \(income), Rent: \(rent)")
            return
        }
        
        let rentPercentage = (rentValue / incomeValue) * 100
        print("📊 Rent Percentage:", rentPercentage)
        
        if rentPercentage >= 30 {
            //print("⚠️ Rent exceeds 30%, showing warning alert.")
            DispatchQueue.main.async {
                shouldSave = false  // Ensure it doesn't save prematurely
                self.activeAlert = .warning(rentPercentage)
            }
        } else {
            //print("✅ Rent is under 30%, saving directly.")
            DispatchQueue.main.async {
                shouldSave = true
                saveToBackend()
            }
        }
    }
    
    // MARK: - Save Data to Backend
    private func saveToBackend() {
        guard shouldSave,
              let incomeValue = Double(income),
              let rentValue = Double(rent) else {
           // print("❌ Save aborted. Condition not met.")
            return
        }
        
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
        
       // print("📡 Sending save request...")
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                print("❌ Error saving data: \(error)")
                return
            }
            
           // print("✅ Data successfully saved!")
            
            
            DispatchQueue.main.async {
                // Once saved successfully, show success alert
                
                // create rent calendar event
                calendarViewModel.createEvent(
                    title: "Rent Payment",
                    description: "Monthly rent of $\(rent)",
                    startDate: rentDueDate,
                    endDate: rentDueDate,
                    eventType: "rent",
                    recurrence: "monthly",
                    invitedFriends: []
                )
                
                self.activeAlert = .success
                UserDefaults.standard.set(self.income, forKey: "userIncome")
                UserDefaults.standard.set(self.rent, forKey: "userRent")
            }
        }.resume()
    }
    
    static func firstOfNextMonth() -> Date {
        let cal = Calendar.current
        let today = Date()
        
        guard let nextMonth = cal.date(byAdding: .month, value: 1, to: today) else {
            return today
        }
        
        //extract month and year
        let comps = cal.dateComponents([.year, .month], from: nextMonth)
        return cal.date(from: DateComponents(year: comps.year, month: comps.month, day: 1)) ?? nextMonth
    }
}

// MARK: - ActiveAlert Enum
/// This enum uniquely identifies which alert should appear.
enum ActiveAlert: Identifiable {
    case warning(Double)  // Pass the rent percentage
    case success
    
    var id: String {
        switch self {
        case .warning(let percentage):
            return "warning-\(percentage)"
        case .success:
            return "success"
        }
    }
}



// MARK: - Response Model
struct IncomeRentResponse: Codable {
    let username: String
    let income: Double
    let rent: Double
}

// MARK: - Preview
#Preview {
    IncomeRentView()
}
