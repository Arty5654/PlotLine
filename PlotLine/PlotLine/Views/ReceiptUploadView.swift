//
//  ReceiptUploadView.swift
//  PlotLine
//
//  Created by Arteom Avetissian on 4/21/25.
//

import SwiftUI
import PhotosUI

// MARK: - Design tokens
private enum PLColor {
    static let surface        = Color(.secondarySystemBackground)
    static let cardBorder     = Color.black.opacity(0.06)
    static let textPrimary    = Color.primary
    static let textSecondary  = Color.secondary
    static let accent         = Color.blue
    static let danger         = Color.red
    static let success        = Color.green
}
private enum PLSpacing {
    static let xs: CGFloat = 6
    static let sm: CGFloat = 10
    static let md: CGFloat = 16
    static let lg: CGFloat = 20
}
private enum PLRadius {
    static let md: CGFloat = 12
}
private struct CardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(PLSpacing.md)
            .background(PLColor.surface)
            .clipShape(RoundedRectangle(cornerRadius: PLRadius.md))
            .overlay(
                RoundedRectangle(cornerRadius: PLRadius.md)
                    .stroke(PLColor.cardBorder)
            )
    }
}
private extension View { func plCard() -> some View { modifier(CardModifier()) } }

private struct PrimaryButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(PLColor.accent.opacity(configuration.isPressed ? 0.85 : 1))
            .clipShape(RoundedRectangle(cornerRadius: PLRadius.md))
    }
}
private struct OutlineButton: ButtonStyle {
    let tint: Color
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundColor(tint)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .overlay(
                RoundedRectangle(cornerRadius: PLRadius.md)
                    .stroke(tint.opacity(configuration.isPressed ? 0.6 : 1))
            )
            .clipShape(RoundedRectangle(cornerRadius: PLRadius.md))
    }
}

// MARK: - View
struct ReceiptUploadView: View {
    @State private var selectedImage: UIImage? = nil
    @State private var imagePickerItem: PhotosPickerItem? = nil
    @State private var isUploading: Bool = false
    @State private var resultMessage: String? = nil
    @State private var showCategoryPrompt: Bool = false
    @State private var unmatchedItems: [ReceiptItem] = []
    @State private var userCorrections: [String: String] = [:]
    @State private var availableCategories: [String] = []
    @State private var errorText: String? = nil
    
    private var username: String {
        UserDefaults.standard.string(forKey: "loggedInUsername") ?? "UnknownUser"
    }

    var body: some View {
        ScrollView {
            VStack(spacing: PLSpacing.lg) {
                // Header
                VStack(alignment: .leading, spacing: PLSpacing.xs) {
                    Text("Receipt Scanner")
                        .font(.headline).bold()
                    Text("Snap or pick a receipt. We’ll categorize it and add to your weekly (and monthly) costs.")
                        .font(.subheadline)
                        .foregroundColor(PLColor.textSecondary)
                }
                .plCard()
                
                // Dropzone / Preview
                VStack(spacing: PLSpacing.sm) {
                    if let image = selectedImage {
                        ZStack {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFit()
                                .clipShape(RoundedRectangle(cornerRadius: PLRadius.md))
                                .overlay(
                                    RoundedRectangle(cornerRadius: PLRadius.md)
                                        .stroke(PLColor.cardBorder)
                                )
                            
                            if isUploading {
                                Color.black.opacity(0.25)
                                    .clipShape(RoundedRectangle(cornerRadius: PLRadius.md))
                                ProgressView("Processing…")
                                    .padding(12)
                                    .background(.ultraThinMaterial)
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                            }
                        }
                        
                        HStack(spacing: PLSpacing.sm) {
                            PhotosPicker(selection: $imagePickerItem, matching: .images) {
                                Label("Retake", systemImage: "arrow.counterclockwise")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(OutlineButton(tint: PLColor.accent))
                            
                            Button {
                                uploadReceipt()
                            } label: {
                                Label("Submit to AI", systemImage: "sparkles")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(PrimaryButton())
                            .disabled(isUploading)
                        }
                    } else {
                        VStack(spacing: PLSpacing.md) {
                            ZStack {
                                RoundedRectangle(cornerRadius: PLRadius.md)
                                    .stroke(style: StrokeStyle(lineWidth: 1, dash: [6]))
                                    .foregroundColor(PLColor.cardBorder)
                                    .frame(maxWidth: .infinity, minHeight: 160)
                                VStack(spacing: 8) {
                                    Image(systemName: "photo.on.rectangle.angled")
                                        .font(.system(size: 36, weight: .regular))
                                        .foregroundColor(PLColor.textSecondary)
                                    Text("Add a photo of your receipt")
                                        .font(.subheadline)
                                        .foregroundColor(PLColor.textSecondary)
                                }
                            }
                            PhotosPicker(selection: $imagePickerItem, matching: .images) {
                                Label("Choose from Photos", systemImage: "photo")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(PrimaryButton())
                        }
                    }
                }
                .plCard()
                
                // Result banner
                if let result = resultMessage, !result.isEmpty {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(PLColor.success)
                        Text(result)
                            .font(.subheadline)
                            .foregroundColor(PLColor.textPrimary)
                        Spacer(minLength: 0)
                    }
                    .padding(PLSpacing.md)
                    .background(PLColor.success.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: PLRadius.md))
                    .overlay(
                        RoundedRectangle(cornerRadius: PLRadius.md)
                            .stroke(PLColor.success.opacity(0.2))
                    )
                }
                
                // Error banner
                if let err = errorText {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(PLColor.danger)
                        Text(err)
                            .font(.subheadline)
                            .foregroundColor(PLColor.textPrimary)
                        Spacer(minLength: 0)
                    }
                    .padding(PLSpacing.md)
                    .background(PLColor.danger.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: PLRadius.md))
                    .overlay(
                        RoundedRectangle(cornerRadius: PLRadius.md)
                            .stroke(PLColor.danger.opacity(0.2))
                    )
                }
                
                Spacer(minLength: 0)
            }
            .padding(.horizontal, PLSpacing.lg)
            .padding(.vertical, PLSpacing.lg)
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) { Text("Receipt Scanner").font(.headline) }
        }
        .tint(PLColor.accent)
        .sheet(isPresented: $showCategoryPrompt) {
            ManualCategoryAssignmentSheet(
                items: $unmatchedItems,
                corrections: $userCorrections,
                categories: $availableCategories,
                onConfirm: submitCorrections
            )
        }
        .onChange(of: imagePickerItem) { newItem in
            Task {
                guard let newItem else { return }
                if let data = try? await newItem.loadTransferable(type: Data.self),
                   let uiImage = UIImage(data: data) {
                    self.selectedImage = uiImage
                    self.resultMessage = nil
                    self.errorText = nil
                }
            }
        }
        .onAppear { loadCategories() }
    }
}

// MARK: - Networking / Logic (unchanged except tiny UX tweaks)
extension ReceiptUploadView {
    private func loadCategories() {
        let group = DispatchGroup()
        var buckets: [Set<String>] = []
        func add(_ arr: [String]?) { if let arr { buckets.append(Set(arr)) } }

        group.enter()
        fetchCategoriesFromBudget(type: "weekly") { cats in add(cats); group.leave() }
        group.enter()
        fetchCategoriesFromBudget(type: "monthly") { cats in add(cats); group.leave() }
        group.enter()
        fetchCategoriesFromCosts(type: "weekly") { cats in add(cats); group.leave() }
        group.enter()
        fetchCategoriesFromCosts(type: "monthly") { cats in add(cats); group.leave() }

        group.notify(queue: .main) {
            var union = buckets.reduce(into: Set<String>()) { $0.formUnion($1) }
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
        let urlString = "\(BackendConfig.baseURLString)/api/budget/\(username)/\(type)"
        guard let url = URL(string: urlString) else { completion(nil); return }
        URLSession.shared.dataTask(with: url) { data, _, _ in
            guard let data,
                  let resp = try? JSONDecoder().decode(BudgetResponse.self, from: data) else { completion(nil); return }
            completion(Array(resp.budget.keys))
        }.resume()
    }

    private func fetchCategoriesFromCosts(type: String, completion: @escaping ([String]?) -> Void) {
        let urlString = "\(BackendConfig.baseURLString)/api/costs/\(username)/\(type)"
        guard let url = URL(string: urlString) else { completion(nil); return }
        URLSession.shared.dataTask(with: url) { data, _, _ in
            guard let data,
                  let resp = try? JSONDecoder().decode(WeeklyMonthlyCostResponse.self, from: data) else { completion(nil); return }
            completion(Array(resp.costs.keys))
        }.resume()
    }

    private func uploadReceipt() {
        guard let image = selectedImage,
              let imageData = image.jpegData(compressionQuality: 0.8) else { return }

        let boundary = UUID().uuidString
        var request = URLRequest(url: URL(string: "\(BackendConfig.baseURLString)/api/costs/upload-receipt")!)
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
        // Close
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        request.httpBody = body

        isUploading = true
        resultMessage = nil
        errorText = nil

        URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async { self.isUploading = false }

            guard error == nil, let data = data else {
                DispatchQueue.main.async { self.errorText = "Failed to upload receipt." }
                return
            }
            // Optional: check status code
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                DispatchQueue.main.async { self.errorText = "Server error (\(http.statusCode))." }
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
                    }
                } else {
                    DispatchQueue.main.async { self.errorText = "Unexpected response format." }
                }
            } catch {
                DispatchQueue.main.async { self.errorText = "Failed to parse response." }
            }
        }.resume()
    }

    private func handleParsedReceipt(_ parsed: [String: [[String: Any]]]) {
        var finalMessage = ""
        unmatchedItems = []

        for (category, items) in parsed {
            for item in items {
                let name = String(describing: item["item"] ?? "Unknown")
                let amount = (item["amount"] as? NSNumber)?.doubleValue ??
                             Double("\(item["amount"] ?? "")") ?? 0.0

                if category == "Unmatched" {
                    if amount > 0 {
                        unmatchedItems.append(ReceiptItem(name: name, amount: amount))
                    }
                } else {
                    finalMessage += "\(category): \(name) - $\(String(format: "%.2f", amount))\n"
                }
            }
        }

        if !unmatchedItems.isEmpty {
            userCorrections = [:]
            showCategoryPrompt = true
        }
        resultMessage = finalMessage.isEmpty ? nil : "Added:\n" + finalMessage
    }
    
    // Upload to both weekly and monthly costs (for unmatched user corrections)
    private func postMergeCosts(type: String, costs: [String: Double], completion: @escaping (Bool) -> Void) {
        let payload: [String: Any] = [
            "username": username,
            "type": type,
            "costs": costs
        ]
        guard let jsonData = try? JSONSerialization.data(withJSONObject: payload) else {
            completion(false); return
        }
        var request = URLRequest(url: URL(string: "\(BackendConfig.baseURLString)/api/costs/merge")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = jsonData
        URLSession.shared.dataTask(with: request) { _, _, err in
            completion(err == nil)
        }.resume()
    }

    private func submitCorrections() {
        var additions: [String: Double] = [:]
        for (itemName, category) in userCorrections {
            let amount = unmatchedItems.first(where: { $0.name == itemName })?.amount ?? 0.0
            additions[category, default: 0.0] += amount
        }

        let group = DispatchGroup()
        var okWeekly = false
        var okMonthly = false

        group.enter()
        postMergeCosts(type: "weekly", costs: additions) { ok in okWeekly = ok; group.leave() }
        group.enter()
        postMergeCosts(type: "monthly", costs: additions) { ok in okMonthly = ok; group.leave() }

        group.notify(queue: .main) {
            self.resultMessage = """
            Uploaded to Weekly & Monthly:
            \(additions.map { "\($0.key): $\(String(format: "%.2f", $0.value))" }.joined(separator: "\n"))
            """
            self.showCategoryPrompt = false
            self.loadCategories()
            if !(okWeekly && okMonthly) { print("One of the merges failed (weekly:\(okWeekly), monthly:\(okMonthly))") }
        }
    }
}

// MARK: - Sheet: Assign categories (no Form; compact + sticky confirm)
private struct ManualCategoryAssignmentSheet: View {
    @Binding var items: [ReceiptItem]
    @Binding var corrections: [String: String]
    @Binding var categories: [String]
    var onConfirm: () -> Void
    
    @Environment(\.dismiss) var dismiss
    @State private var newCategoryName: String = ""
    
    private var allChosen: Bool {
        items.allSatisfy { !(corrections[$0.name] ?? "").isEmpty }
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: PLSpacing.lg) {
                if items.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "checkmark.seal")
                        Text("No unmatched items 🎉")
                            .font(.headline)
                        Text("Everything was categorized automatically.")
                            .font(.subheadline)
                            .foregroundColor(PLColor.textSecondary)
                    }
                    .padding()
                } else {
                    // Add category
                    VStack(alignment: .leading, spacing: PLSpacing.sm) {
                        Text("Add New Category")
                            .font(.headline)
                        HStack(spacing: PLSpacing.sm) {
                            TextField("New category name", text: $newCategoryName)
                                .textFieldStyle(.roundedBorder)
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
                            .tint(.green)
                        }
                    }
                    .plCard()
                    
                    // Items
                    ScrollView {
                        VStack(spacing: PLSpacing.sm) {
                            ForEach(items) { item in
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack {
                                        Text(item.name)
                                            .font(.headline)
                                        Spacer()
                                        Text("$\(item.amount, specifier: "%.2f")")
                                            .font(.subheadline).bold()
                                    }
                                    Picker("Category", selection: Binding(
                                        get: { corrections[item.name] ?? "" },
                                        set: { corrections[item.name] = $0 }
                                    )) {
                                        Text("— Select —").tag("")
                                        ForEach(categories, id: \.self) { cat in
                                            Text(cat).tag(cat)
                                        }
                                    }
                                    .pickerStyle(.menu)
                                }
                                .plCard()
                            }
                        }
                        .padding(.bottom, 80) // space for sticky button
                    }
                }
            }
            .padding(.horizontal, PLSpacing.lg)
            .padding(.top, PLSpacing.lg)
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 0) {
                    Divider()
                    HStack(spacing: PLSpacing.sm) {
                        Button("Cancel") { dismiss() }
                            .buttonStyle(OutlineButton(tint: PLColor.accent))
                        Button("Confirm") { onConfirm() }
                            .buttonStyle(PrimaryButton())
                            .disabled(!allChosen)
                    }
                    .padding(.horizontal, PLSpacing.lg)
                    .padding(.vertical, PLSpacing.md)
                    .background(.regularMaterial)
                }
            }
            .navigationTitle("Assign Categories")
            .navigationBarTitleDisplayMode(.inline)
            .tint(PLColor.accent)
        }
    }
}

// MARK: - Models used here
struct ReceiptItem: Identifiable {
    let id = UUID()
    let name: String
    let amount: Double
}
