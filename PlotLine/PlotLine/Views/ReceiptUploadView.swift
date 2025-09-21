//
//  ReceiptUploadView.swift
//  PlotLine
//
//  Created by Arteom Avetissian on 4/21/25.
//

import SwiftUI
import PhotosUI

struct ReceiptUploadView: View {
    @State private var selectedImage: UIImage? = nil
    @State private var imagePickerItem: PhotosPickerItem? = nil
    @State private var isUploading: Bool = false
    @State private var resultMessage: String? = nil
    @State private var showCategoryPrompt: Bool = false
    @State private var unmatchedItems: [ReceiptItem] = []
    @State private var userCorrections: [String: String] = [:]
    @State private var availableCategories: [String] = []

    private var username: String {
        UserDefaults.standard.string(forKey: "loggedInUsername") ?? "UnknownUser"
    }

    var body: some View {
        VStack(spacing: 20) {
            Text("Upload Receipt")
                .font(.largeTitle)
                .bold()

            if let image = selectedImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(height: 250)
            }

            PhotosPicker(selection: $imagePickerItem, matching: .images) {
                Text("Choose from Photos")
                    .foregroundColor(.white)
                    .padding()
                    .background(Color.blue)
                    .cornerRadius(8)
            }
            .onChange(of: imagePickerItem) { newItem in
                Task {
                    if let data = try? await newItem?.loadTransferable(type: Data.self),
                       let uiImage = UIImage(data: data) {
                        self.selectedImage = uiImage
                    }
                }
            }

            Button("Submit to AI") {
                uploadReceipt()
            }
            .disabled(selectedImage == nil || isUploading)

            if isUploading {
                ProgressView("Processing...")
            }

            if let result = resultMessage {
                Text(result)
                    .padding()
            }

            Spacer()
        }
        .padding()
        .navigationTitle("Receipt Scanner")
        // ReceiptUploadView.swift
        .sheet(isPresented: $showCategoryPrompt) {
          ManualCategoryAssignmentView(
            items: $unmatchedItems,
            corrections: $userCorrections,
            categories: $availableCategories
          ) {
            submitCorrections()
          }
        }
        .onAppear() {
            loadCategories()
        }
    }
    
    private func loadCategories() {
        // Fetch from 4 places and union them.
        let group = DispatchGroup()
        var buckets: [Set<String>] = []

        func add(_ arr: [String]?) {
            if let arr = arr { buckets.append(Set(arr)) }
        }

        // weekly budget
        group.enter()
        fetchCategoriesFromBudget(type: "weekly") { cats in
            add(cats)
            group.leave()
        }

        // monthly budget
        group.enter()
        fetchCategoriesFromBudget(type: "monthly") { cats in
            add(cats)
            group.leave()
        }

        // weekly costs
        group.enter()
        fetchCategoriesFromCosts(type: "weekly") { cats in
            add(cats)
            group.leave()
        }

        // monthly costs
        group.enter()
        fetchCategoriesFromCosts(type: "monthly") { cats in
            add(cats)
            group.leave()
        }

        group.notify(queue: .main) {
            var union = buckets.reduce(into: Set<String>()) { $0.formUnion($1) }

            // fallback if nothing found
            if union.isEmpty {
                union = [
                    "Rent","Groceries","Subscriptions","Eating Out","Entertainment",
                    "Utilities","Savings","Miscellaneous","Transportation","401(k)",
                    "Roth IRA","Car Insurance","Health Insurance","Brokerage"
                ]
            }

            self.availableCategories = Array(union).sorted()
        }
    }


    private func fetchCategoriesFromBudget(type: String, completion: @escaping ([String]?) -> Void) {
        let urlString = "http://localhost:8080/api/budget/\(username)/\(type)"
        guard let url = URL(string: urlString) else { completion(nil); return }
        URLSession.shared.dataTask(with: url) { data, _, _ in
            guard let data = data, let resp = try? JSONDecoder().decode(BudgetResponse.self, from: data) else {
                completion(nil); return
            }
            completion(Array(resp.budget.keys))
        }.resume()
    }

    private func fetchCategoriesFromCosts(type: String, completion: @escaping ([String]?) -> Void) {
        let urlString = "http://localhost:8080/api/costs/\(username)/\(type)"
        guard let url = URL(string: urlString) else { completion(nil); return }
        URLSession.shared.dataTask(with: url) { data, _, _ in
            guard let data = data, let resp = try? JSONDecoder().decode(WeeklyMonthlyCostResponse.self, from: data) else {
                completion(nil); return
            }
            completion(Array(resp.costs.keys))
        }.resume()
    }


    private func uploadReceipt() {
        guard let image = selectedImage,
              let imageData = image.jpegData(compressionQuality: 0.8) else { return }

        let boundary = UUID().uuidString
        var request = URLRequest(url: URL(string: "http://localhost:8080/api/costs/upload-receipt")!)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()

        // Image
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"image\"; filename=\"receipt.jpg\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: image/jpeg\r\n\r\n".data(using: .utf8)!)
        body.append(imageData)
        body.append("\r\n".data(using: .utf8)!)

        // Username
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"username\"\r\n\r\n".data(using: .utf8)!)
        body.append(username.data(using: .utf8)!)
        body.append("\r\n".data(using: .utf8)!)

        // Closing boundary
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)


        request.httpBody = body

        isUploading = true
        resultMessage = nil

        URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                self.isUploading = false
            }

            guard let data = data, error == nil else {
                DispatchQueue.main.async {
                    self.resultMessage = "Failed to upload receipt."
                }
                return
            }

            do {
                if let raw = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    var parsed: [String: [[String: Any]]] = [:]

                    for (key, value) in raw {
                        if key == "Unmatched", let array = value as? [[String: Any]] {
                            parsed[key] = array
                        } else if let amount = value as? Double {
                            parsed[key] = [["item": key, "amount": amount]]
                        }
                    }

                    DispatchQueue.main.async {
                        handleParsedReceipt(parsed)
                        print("Parsed from backend: \(parsed)")
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    self.resultMessage = "Failed to parse response."
                }
            }
        }.resume()
    }

    private func handleParsedReceipt(_ parsed: [String: [[String: Any]]]) {
        var finalMessage = ""
        unmatchedItems = []

        for (category, items) in parsed {
            for item in items {
                //let name = item["item"] as? String ?? "Unknown"
                let name = String(describing: item["item"] ?? "Unknown")
                //let amount = item["amount"] as? Double ?? 0.0
                //let amount = (item["amount"] as? NSNumber)?.doubleValue ?? 0.0
                let amount = (item["amount"] as? NSNumber)?.doubleValue ??
                             Double("\(item["amount"] ?? "")") ?? 0.0
                print("Item in category \(category):", item)

                if category == "Unmatched" {
                    if amount > 0 {
                        unmatchedItems.append(ReceiptItem(name: name, amount: amount))
                    } else {
                        print("Skipping unmatched item due to zero/invalid amount: \(name)")
                        finalMessage += "\(category): \(name) - $\(amount)\n"
                    }
                }
              
                    

            }
        }
        print("RAW unmatched array:", unmatchedItems)

        if !unmatchedItems.isEmpty {
            showCategoryPrompt = true
        } else {
            resultMessage = "Added:\n" + finalMessage
        }
    }
    
    // Upload to both weekly and monthly costs
    private func postMergeCosts(type: String, costs: [String: Double], completion: @escaping (Bool) -> Void) {
        let payload: [String: Any] = [
            "username": username,
            "type": type,
            "costs": costs
        ]

        guard let jsonData = try? JSONSerialization.data(withJSONObject: payload) else {
            completion(false)
            return
        }

        var request = URLRequest(url: URL(string: "http://localhost:8080/api/costs/merge")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = jsonData

        URLSession.shared.dataTask(with: request) { _, resp, err in
            completion(err == nil)
        }.resume()
    }


    private func submitCorrections() {
        var additions: [String: Double] = [:]

        for (itemName, category) in userCorrections {
            let amount = unmatchedItems.first(where: { $0.name == itemName })?.amount ?? 0.0
            additions[category, default: 0.0] += amount
        }

        // Send to both sheets
        let group = DispatchGroup()
        var okWeekly = false
        var okMonthly = false

        group.enter()
        postMergeCosts(type: "weekly", costs: additions) { ok in
            okWeekly = ok
            group.leave()
        }

        group.enter()
        postMergeCosts(type: "monthly", costs: additions) { ok in
            okMonthly = ok
            group.leave()
        }

        group.notify(queue: .main) {
            // Friendly result text
            self.resultMessage = """
            Uploaded to Weekly & Monthly:
            \(additions.map { "\($0.key): $\(String(format: "%.2f", $0.value))" }.joined(separator: "\n"))
            """
            self.showCategoryPrompt = false

            // Refresh the dropdown right away so new categories persist
            self.loadCategories()

            if !(okWeekly && okMonthly) {
                print("One of the merges failed (weekly:\(okWeekly), monthly:\(okMonthly))")
            }
        }
    }

}

struct ReceiptItem: Identifiable {
    let id = UUID()
    let name: String
    let amount: Double
}

struct ManualCategoryAssignmentView: View {
    @Binding var items: [ReceiptItem]
    @Binding var corrections: [String: String]
    @Binding var categories: [String]
    var onConfirm: () -> Void

    @State private var newCategoryName: String = ""

    var allChosen: Bool {
        // Ensure each item has a non-empty selection
        items.allSatisfy { corrections[$0.name]?.isEmpty == false }
    }

    var body: some View {
        NavigationView {
            VStack {
                if items.isEmpty {
                    Text("No unmatched items to categorize.")
                        .padding()
                } else {
                    Form {
                        Section(header: Text("Add New Category")) {
                            HStack {
                                TextField("New category name", text: $newCategoryName)
                                Button {
                                    let trimmed = newCategoryName.trimmingCharacters(in: .whitespacesAndNewlines)
                                    guard !trimmed.isEmpty else { return }
                                    if !categories.contains(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame }) {
                                        categories.append(trimmed)
                                        categories.sort()
                                    }
                                    newCategoryName = ""
                                } label: {
                                    Label("Add", systemImage: "plus.circle.fill")
                                }
                            }
                        }

                        ForEach(items) { item in
                            Section(header: Text("\(item.name) ($\(item.amount, specifier: "%.2f"))")) {
                                Picker("Category", selection: Binding(
                                    get: { corrections[item.name] ?? "" },
                                    set: { corrections[item.name] = $0 }
                                )) {
                                    Text("— Select —").tag("")
                                    ForEach(categories, id: \.self) { cat in
                                        Text(cat).tag(cat)
                                    }
                                }
                            }
                        }

                        Button("Confirm") {
                            onConfirm()
                        }
                        .disabled(!allChosen)
                    }
                }
            }
            .navigationTitle("Assign Categories")
        }
    }
}





#Preview {
    ReceiptUploadView()
}
