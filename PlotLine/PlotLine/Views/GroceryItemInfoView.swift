import SwiftUI

private enum PLColor {
    static let surface       = Color(.secondarySystemBackground)
    static let cardBorder    = Color.black.opacity(0.06)
    static let textPrimary   = Color.primary
    static let textSecondary = Color.secondary
    static let danger        = Color.red
}
private enum PLSpacing {
    static let xs: CGFloat = 6
    static let sm: CGFloat = 10
    static let md: CGFloat = 16
    static let lg: CGFloat = 20
}
private enum PLRadius { static let md: CGFloat = 12 }

private struct CardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(PLSpacing.md)
            .background(PLColor.surface)
            .clipShape(RoundedRectangle(cornerRadius: PLRadius.md))
            .overlay(RoundedRectangle(cornerRadius: PLRadius.md).stroke(PLColor.cardBorder))
    }
}
private extension View { func plCard() -> some View { modifier(CardModifier()) } }

private struct PrimaryButton: ButtonStyle {
    let adaptiveColor: Color
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(Color.blue.opacity(configuration.isPressed ? 0.85 : 1))
            .clipShape(RoundedRectangle(cornerRadius: PLRadius.md))
    }
}

// MARK: - View

struct GroceryItemInfoView: View {
    @Binding var item: GroceryItem?
    var onClose: () -> Void

    @Environment(\.colorScheme) var colorScheme

    @State private var isEditing = false
    @State private var nameText: String = ""
    @State private var quantityText: String = ""
    @State private var priceText: String = ""
    @State private var storeText: String = ""
    @State private var notesText: String = ""
    @State private var priceWarning = ""
    @State private var quantityWarning = ""

    private var adaptiveTextColor: Color {
        colorScheme == .dark ? .white : .blue
    }

    private var isSaveDisabled: Bool { !priceWarning.isEmpty || !quantityWarning.isEmpty || !hasChanges }

    private var hasChanges: Bool {
        guard let it = item else { return false }
        let qOrig = it.quantity
        let pOrig = it.price ?? 0
        let qNew  = Int(quantityText) ?? qOrig
        let pNew  = Double(priceText) ?? pOrig
        return nameText != it.name
            || qNew != qOrig
            || pNew != pOrig
            || storeText != (it.store ?? "")
            || notesText != (it.notes ?? "")
    }

    private var priceFormatter: NumberFormatter {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.minimumFractionDigits = 2
        f.maximumFractionDigits = 2
        return f
    }

    var body: some View {
        VStack(spacing: PLSpacing.lg) {
            // Header
            HStack(spacing: PLSpacing.sm) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(isEditing ? "Edit Item" : "Item Details")
                        .font(.title3).bold()
                    Text(item?.name ?? "—")
                        .font(.subheadline)
                        .foregroundColor(PLColor.textSecondary)
                        .lineLimit(1)
                }
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundColor(PLColor.textSecondary)
                }
                .buttonStyle(.plain)
            }

            if let it = item {
                VStack(spacing: PLSpacing.md) {
                    Row(label: "Name") {
                        if isEditing {
                            TextField("Item name", text: $nameText)
                                .textFieldStyle(.roundedBorder)
                                .tint(adaptiveTextColor)
                        } else {
                            Text(it.name.isEmpty ? "—" : it.name)
                        }
                    }

                    Row(label: "Quantity") {
                        if isEditing {
                            TextField("Qty", text: Binding(
                                get: { quantityText },
                                set: { new in
                                    quantityText = new.filter { "0123456789".contains($0) }
                                    validateQuantity()
                                }
                            ))
                            .keyboardType(.numberPad)
                            .textFieldStyle(.roundedBorder)
                            .tint(adaptiveTextColor)
                        } else {
                            Text("\(it.quantity)")
                        }
                    }

                    Row(label: "Price") {
                        if isEditing {
                            TextField("0.00", text: Binding(
                                get: { priceText },
                                set: { new in
                                    priceText = filterPriceInput(new)
                                    validatePrice()
                                }
                            ))
                            .keyboardType(.decimalPad)
                            .textFieldStyle(.roundedBorder)
                            .tint(adaptiveTextColor)
                        } else {
                            let priceValue = it.price ?? 0
                            let s = priceValue == 0 ? "—" : (priceFormatter.string(from: NSNumber(value: priceValue)) ?? "—")
                            Text(s)
                        }
                    }

                    Row(label: "Store") {
                        if isEditing {
                            TextField("Optional", text: $storeText)
                                .textFieldStyle(.roundedBorder)
                                .tint(adaptiveTextColor)
                        } else {
                            Text((it.store?.isEmpty ?? true) ? "—" : (it.store ?? "—"))
                        }
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Notes")
                            .font(.subheadline)
                            .foregroundColor(PLColor.textSecondary)
                        if isEditing {
                            TextField("Optional notes", text: $notesText, axis: .vertical)
                                .textFieldStyle(.roundedBorder)
                                .tint(adaptiveTextColor)
                                .lineLimit(3, reservesSpace: true)
                        } else {
                            Text((it.notes?.isEmpty ?? true) ? "—" : (it.notes ?? "—"))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .plCard()

                // Warnings
                VStack(spacing: 4) {
                    if !quantityWarning.isEmpty { WarningRow(text: quantityWarning) }
                    if !priceWarning.isEmpty    { WarningRow(text: priceWarning) }
                }
                .frame(minHeight: 18)

                // Actions
                HStack(spacing: PLSpacing.sm) {
                    if isEditing {
                        Button("Cancel") {
                            loadFromItem()
                            priceWarning = ""; quantityWarning = ""
                            isEditing = false
                        }
                        .buttonStyle(.bordered)

                        Button("Save") {
                            Task { await saveEdits() }
                        }
                        .buttonStyle(PrimaryButton(adaptiveColor: adaptiveTextColor))
                        .disabled(isSaveDisabled)
                    } else {
                        Button {
                            isEditing = true
                        } label: {
                            Label("Edit", systemImage: "pencil")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(PrimaryButton(adaptiveColor: adaptiveTextColor))
                    }
                }

                Button("Close") { onClose() }
                    .font(.subheadline)
                    .foregroundColor(PLColor.textSecondary)
                    .padding(.top, 2)
            } else {
                VStack(spacing: PLSpacing.sm) {
                    Image(systemName: "cart")
                        .font(.largeTitle)
                        .foregroundColor(PLColor.textSecondary)
                    Text("No item selected")
                        .foregroundColor(PLColor.textSecondary)
                }
                .plCard()
                .frame(maxWidth: .infinity, minHeight: 220)
            }

            Spacer(minLength: 0)
        }
        .padding(PLSpacing.lg)
        .frame(width: 360, height: 520)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .shadow(radius: 10)
        .onAppear(perform: loadFromItem)
        .onChange(of: item) { _ in loadFromItem() }
    }

    // MARK: - Load / Save (logic unchanged)

    private func loadFromItem() {
        guard let it = item else { return }
        nameText     = it.name
        quantityText = String(it.quantity)
        priceText    = (it.price ?? 0) == 0 ? "" : String(format: "%.2f", it.price ?? 0)
        storeText    = it.store ?? ""
        notesText    = it.notes ?? ""
        priceWarning = ""; quantityWarning = ""
    }

    private func saveEdits() async {
        guard var it = item else { return }
        validateQuantity()
        validatePrice()
        guard priceWarning.isEmpty, quantityWarning.isEmpty else { return }

        it.name     = nameText.trimmingCharacters(in: .whitespacesAndNewlines)
        it.quantity = Int(quantityText) ?? it.quantity
        it.price    = priceText.isEmpty ? nil : Double(priceText)
        let trimmedStore = storeText.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedNotes = notesText.trimmingCharacters(in: .whitespacesAndNewlines)
        it.store    = trimmedStore.isEmpty ? nil : trimmedStore
        it.notes    = trimmedNotes.isEmpty ? nil : trimmedNotes

        do {
            try await GroceryListAPI.updateItem(listId: it.listId.uuidString, itemId: it.id.uuidString, updatedItem: it)
            self.item = it
            isEditing = false
        } catch {
            print("Failed to update item: \(error)")
        }
    }

    private func validatePrice() {
        guard !priceText.isEmpty else { priceWarning = ""; return }
        let regex = #"^[0-9]*\.?[0-9]{0,2}$"#
        let ok = NSPredicate(format: "SELF MATCHES %@", regex).evaluate(with: priceText)
        priceWarning = ok ? "" : "Enter a valid price (up to two decimals)."
    }

    private func validateQuantity() {
        guard !quantityText.isEmpty else { quantityWarning = ""; return }
        if let v = Int(quantityText), v >= 0 {
            quantityWarning = ""
        } else {
            quantityWarning = "Quantity must be a non-negative whole number."
        }
    }

    private func filterPriceInput(_ input: String) -> String {
        let allowed = input.filter { "0123456789.".contains($0) }
        let parts = allowed.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)
        if parts.count == 2 {
            return String(parts[0]) + "." + String(parts[1].prefix(2))
        }
        return String(allowed)
    }
}

// MARK: - Small Subviews

private struct Row<Content: View>: View {
    let label: String
    @ViewBuilder var content: () -> Content
    var body: some View {
        HStack(spacing: PLSpacing.md) {
            Text(label)
                .font(.subheadline)
                .foregroundColor(PLColor.textSecondary)
                .frame(width: 90, alignment: .leading)
            content()
            Spacer(minLength: PLSpacing.sm)
        }
    }
}

private struct WarningRow: View {
    let text: String
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
            Text(text).fixedSize(horizontal: false, vertical: true)
        }
        .font(.caption)
        .foregroundColor(PLColor.danger)
    }
}
