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
    @State private var showCameraPicker: Bool = false
    @State private var isUploading: Bool = false
    @State private var resultMessage: String? = nil
    @State private var showCategoryPrompt: Bool = false
    @State private var unmatchedItems: [ReceiptItem] = []
    @State private var userCorrections: [String: String] = [:]
    @State private var availableCategories: [String] = []
    @State private var errorText: String? = nil

    // For Undo/Edit functionality
    @State private var lastAddedCosts: [String: Double] = [:]
    @State private var lastAddedDate: String = ""
    @State private var showEditSheet: Bool = false
    @State private var editableCosts: [String: Double] = [:]
    @State private var isUndoing: Bool = false

    private var canUndoOrEdit: Bool {
        !lastAddedCosts.isEmpty && resultMessage != nil
    }

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
                                 showCameraPicker = true
                             } label: {
                                 Label("Take Photo", systemImage: "camera")
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
                            
                            Button {
                                showCameraPicker = true
                            } label: {
                                Label("Take Photo", systemImage: "camera")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(OutlineButton(tint: PLColor.accent))
                        }
                    }
                }
                .plCard()
                
                // Result banner
                if let result = resultMessage, !result.isEmpty {
                    VStack(spacing: PLSpacing.sm) {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(PLColor.success)
                            Text(result)
                                .font(.subheadline)
                                .foregroundColor(PLColor.textPrimary)
                            Spacer(minLength: 0)
                        }

                        // Undo and Edit buttons
                        if canUndoOrEdit {
                            HStack(spacing: PLSpacing.sm) {
                                Button {
                                    undoLastReceipt()
                                } label: {
                                    Label(isUndoing ? "Undoing..." : "Undo", systemImage: "arrow.uturn.backward")
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(OutlineButton(tint: PLColor.danger))
                                .disabled(isUndoing)

                                Button {
                                    editableCosts = lastAddedCosts
                                    showEditSheet = true
                                } label: {
                                    Label("Edit", systemImage: "pencil")
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(OutlineButton(tint: PLColor.accent))
                            }
                        }
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
        .sheet(isPresented: $showEditSheet) {
            EditReceiptCostsSheet(
                costs: $editableCosts,
                categories: $availableCategories,
                onSave: { updatedCosts in
                    applyEditedCosts(updatedCosts)
                }
            )
        }
        .sheet(isPresented: $showCameraPicker) {
            CameraPicker(image: $selectedImage)
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
        .onChange(of: selectedImage) { _ in
            resultMessage = nil
            errorText = nil
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
        // Local date (user's timezone)
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let localDate = formatter.string(from: Date())
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"date\"\r\n\r\n".data(using: .utf8)!)
        body.append(localDate.data(using: .utf8)!)
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

                    // Extract metadata for undo/edit
                    var addedCosts: [String: Double] = [:]
                    var addedDate: String = ""

                    if let costs = raw["_addedCosts"] as? [String: Any] {
                        for (key, value) in costs {
                            if let num = value as? Double {
                                addedCosts[key] = num
                            } else if let num = value as? Int {
                                addedCosts[key] = Double(num)
                            }
                        }
                    }
                    if let date = raw["_date"] as? String {
                        addedDate = date
                    }

                    for (key, value) in raw {
                        // Skip metadata keys
                        if key.hasPrefix("_") { continue }

                        if key == "Unmatched", let array = value as? [[String: Any]] {
                            parsed[key] = array
                        } else if let amount = value as? Double {
                            parsed[key] = [["item": key, "amount": amount]]
                        }
                    }

                    DispatchQueue.main.async {
                        self.lastAddedCosts = addedCosts
                        self.lastAddedDate = addedDate
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

    // MARK: - Undo Receipt
    private func undoLastReceipt() {
        guard !lastAddedCosts.isEmpty else { return }

        isUndoing = true

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let localDate = formatter.string(from: Date())

        let payload: [String: Any] = [
            "username": username,
            "date": lastAddedDate.isEmpty ? localDate : lastAddedDate,
            "costs": lastAddedCosts
        ]

        guard let jsonData = try? JSONSerialization.data(withJSONObject: payload) else {
            isUndoing = false
            errorText = "Failed to create undo request"
            return
        }

        var request = URLRequest(url: URL(string: "\(BackendConfig.baseURLString)/api/costs/undo-receipt")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = jsonData

        URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                self.isUndoing = false

                if let error = error {
                    self.errorText = "Undo failed: \(error.localizedDescription)"
                    return
                }

                if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                    self.errorText = "Undo failed (status \(http.statusCode))"
                    return
                }

                // Success - clear the state
                self.resultMessage = "Receipt costs undone successfully"
                self.lastAddedCosts = [:]
                self.lastAddedDate = ""
                self.selectedImage = nil
            }
        }.resume()
    }

    // MARK: - Apply Edited Costs
    private func applyEditedCosts(_ updatedCosts: [String: Double]) {
        // First undo the original costs, then add the new ones
        guard !lastAddedCosts.isEmpty else {
            errorText = "No costs to edit"
            return
        }

        isUploading = true

        // Step 1: Undo original costs
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let localDate = formatter.string(from: Date())

        let undoPayload: [String: Any] = [
            "username": username,
            "date": lastAddedDate.isEmpty ? localDate : lastAddedDate,
            "costs": lastAddedCosts
        ]

        guard let undoData = try? JSONSerialization.data(withJSONObject: undoPayload) else {
            isUploading = false
            errorText = "Failed to create undo request"
            return
        }

        var undoRequest = URLRequest(url: URL(string: "\(BackendConfig.baseURLString)/api/costs/undo-receipt")!)
        undoRequest.httpMethod = "POST"
        undoRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        undoRequest.httpBody = undoData

        URLSession.shared.dataTask(with: undoRequest) { _, _, error in
            if error != nil {
                DispatchQueue.main.async {
                    self.isUploading = false
                    self.errorText = "Failed to undo before edit"
                }
                return
            }

            // Step 2: Add new costs using merge-dated
            let addPayload: [String: Any] = [
                "username": self.username,
                "type": "weekly",
                "date": localDate,
                "costs": updatedCosts
            ]

            guard let addData = try? JSONSerialization.data(withJSONObject: addPayload) else {
                DispatchQueue.main.async {
                    self.isUploading = false
                    self.errorText = "Failed to create add request"
                }
                return
            }

            var addRequest = URLRequest(url: URL(string: "\(BackendConfig.baseURLString)/api/costs/add-dated")!)
            addRequest.httpMethod = "POST"
            addRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
            addRequest.httpBody = addData

            let group = DispatchGroup()
            var weeklyOk = false
            var monthlyOk = false

            // Add to weekly
            group.enter()
            URLSession.shared.dataTask(with: addRequest) { _, resp, _ in
                if let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode) {
                    weeklyOk = true
                }
                group.leave()
            }.resume()

            // Add to monthly
            var monthlyPayload = addPayload
            monthlyPayload["type"] = "monthly"
            if let monthlyData = try? JSONSerialization.data(withJSONObject: monthlyPayload) {
                var monthlyRequest = addRequest
                monthlyRequest.httpBody = monthlyData
                group.enter()
                URLSession.shared.dataTask(with: monthlyRequest) { _, resp, _ in
                    if let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode) {
                        monthlyOk = true
                    }
                    group.leave()
                }.resume()
            }

            group.notify(queue: .main) {
                self.isUploading = false
                self.showEditSheet = false

                if weeklyOk && monthlyOk {
                    self.lastAddedCosts = updatedCosts
                    self.resultMessage = "Updated costs:\n" + updatedCosts.map { "\($0.key): $\(String(format: "%.2f", $0.value))" }.joined(separator: "\n")
                } else {
                    self.errorText = "Failed to save edited costs"
                }
            }
        }.resume()
    }
}

// MARK: - Camera Picker
struct CameraPicker: UIViewControllerRepresentable {
    @Binding var image: UIImage?

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.delegate = context.coordinator
        if UIImagePickerController.isSourceTypeAvailable(.camera) {
            picker.sourceType = .camera
        } else {
            picker.sourceType = .photoLibrary
        }
        picker.allowsEditing = false
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker
        init(_ parent: CameraPicker) {
            self.parent = parent
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            picker.dismiss(animated: true)
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            if let img = info[.originalImage] as? UIImage {
                parent.image = img
            }
            picker.dismiss(animated: true)
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

// MARK: - Edit Receipt Costs Sheet
private struct EditReceiptCostsSheet: View {
    @Binding var costs: [String: Double]
    @Binding var categories: [String]
    var onSave: ([String: Double]) -> Void

    @Environment(\.dismiss) var dismiss
    @State private var editedCosts: [EditableCost] = []
    @State private var newCategoryName: String = ""
    @State private var newCategoryAmount: String = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: PLSpacing.lg) {
                // Add new category section
                VStack(alignment: .leading, spacing: PLSpacing.sm) {
                    Text("Add Category")
                        .font(.headline)
                    HStack(spacing: PLSpacing.sm) {
                        Picker("Category", selection: $newCategoryName) {
                            Text("— Select —").tag("")
                            ForEach(categories.filter { cat in !editedCosts.contains { $0.category == cat } }, id: \.self) { cat in
                                Text(cat).tag(cat)
                            }
                        }
                        .pickerStyle(.menu)

                        TextField("Amount", text: $newCategoryAmount)
                            .keyboardType(.decimalPad)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 100)

                        Button {
                            guard !newCategoryName.isEmpty,
                                  let amount = Double(newCategoryAmount), amount > 0 else { return }
                            editedCosts.append(EditableCost(category: newCategoryName, amount: amount))
                            newCategoryName = ""
                            newCategoryAmount = ""
                        } label: {
                            Image(systemName: "plus.circle.fill")
                        }
                        .tint(.green)
                    }
                }
                .plCard()

                // Existing costs
                ScrollView {
                    VStack(spacing: PLSpacing.sm) {
                        ForEach($editedCosts) { $cost in
                            HStack {
                                Text(cost.category)
                                    .font(.headline)
                                Spacer()
                                Text("$")
                                TextField("Amount", value: $cost.amount, format: .number)
                                    .keyboardType(.decimalPad)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 80)
                                Button {
                                    editedCosts.removeAll { $0.id == cost.id }
                                } label: {
                                    Image(systemName: "trash")
                                        .foregroundColor(PLColor.danger)
                                }
                            }
                            .plCard()
                        }
                    }
                    .padding(.bottom, 80)
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
                        Button("Save Changes") {
                            var result: [String: Double] = [:]
                            for cost in editedCosts where cost.amount > 0 {
                                result[cost.category] = cost.amount
                            }
                            onSave(result)
                        }
                        .buttonStyle(PrimaryButton())
                        .disabled(editedCosts.isEmpty)
                    }
                    .padding(.horizontal, PLSpacing.lg)
                    .padding(.vertical, PLSpacing.md)
                    .background(.regularMaterial)
                }
            }
            .navigationTitle("Edit Receipt Costs")
            .navigationBarTitleDisplayMode(.inline)
            .tint(PLColor.accent)
            .onAppear {
                editedCosts = costs.map { EditableCost(category: $0.key, amount: $0.value) }
            }
        }
    }
}

private struct EditableCost: Identifiable {
    let id = UUID()
    var category: String
    var amount: Double
}
