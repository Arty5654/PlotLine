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
            corrections: $userCorrections
          ) {
            submitCorrections()
          }
        }
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

    private func submitCorrections() {
        var additions: [String: Double] = [:]

        for (itemName, category) in userCorrections {
            let amount = unmatchedItems.first(where: { $0.name == itemName })?.amount ?? 0.0
            additions[category, default: 0.0] += amount
        }

        let payload: [String: Any] = [
            "username": username,
            "type": "weekly",
            "costs": additions
        ]

        guard let jsonData = try? JSONSerialization.data(withJSONObject: payload) else { return }

        var request = URLRequest(url: URL(string: "http://localhost:8080/api/costs/merge")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = jsonData

        URLSession.shared.dataTask(with: request).resume()

        resultMessage = "Uploaded:\n" + additions.map { "\($0.key): $\(String(format: "%.2f", $0.value))" }.joined(separator: "\n")
        showCategoryPrompt = false
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
  var onConfirm: () -> Void

  var body: some View {
    NavigationView {
      VStack {
        if items.isEmpty {
          Text("No unmatched items to categorize.")
            .padding()
        } else {
          Form {
            ForEach(items) { item in
              Section(header: Text("\(item.name) ($\(item.amount, specifier: "%.2f"))")) {
                TextField("Assign category", text: Binding(
                  get: { corrections[item.name] ?? "" },
                  set: { corrections[item.name] = $0 }
                ))
              }
            }

            Button("Confirm") {
              onConfirm()
            }
            .disabled(corrections.count < items.count)
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
