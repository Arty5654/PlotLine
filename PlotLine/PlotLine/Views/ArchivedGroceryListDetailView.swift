//
//  ArchivedGroceryListDetailView.swift
//  PlotLine
//

import SwiftUI

struct ArchivedGroceryListDetailView: View {
    let groceryList: GroceryList

    private var checkedCount: Int { groceryList.items.filter { $0.checked }.count }
    private var totalEstimate: Double { groceryList.items.reduce(0) { $0 + ($1.price ?? 0) } }

    var body: some View {
        List {
            if !groceryList.items.isEmpty {
                Section {
                    ForEach(groceryList.items) { item in
                        HStack(spacing: 12) {
                            Image(systemName: item.checked ? "checkmark.circle.fill" : "circle")
                                .foregroundColor(item.checked ? .green : .secondary)
                                .font(.title3)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.name)
                                    .strikethrough(item.checked, color: .green)
                                    .foregroundColor(item.checked ? .secondary : .primary)
                                Text("Qty: \(item.quantity)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }

                            Spacer()

                            if let price = item.price, price > 0 {
                                Text("~$\(price, specifier: "%.2f")")
                                    .font(.caption.bold())
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                } header: {
                    Text("\(groceryList.items.count) item\(groceryList.items.count == 1 ? "" : "s") · \(checkedCount) checked")
                } footer: {
                    if totalEstimate > 0 {
                        Text("Estimated total: ~$\(totalEstimate, specifier: "%.2f")")
                    }
                }
            } else {
                Text("No items in this list.")
                    .foregroundColor(.secondary)
            }
        }
        .navigationTitle(groceryList.name)
        .navigationBarTitleDisplayMode(.inline)
        .listStyle(.insetGrouped)
    }
}
