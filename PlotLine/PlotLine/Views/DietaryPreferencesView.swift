//
//  DietaryPreferencesView.swift
//  PlotLine
//

import SwiftUI

private struct DietaryRow: View {
    let icon: String
    let label: String
    let color: Color
    let isEditing: Bool
    @Binding var value: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(color)
                .frame(width: 28)

            Text(label)

            Spacer()

            if isEditing {
                Toggle("", isOn: $value)
                    .labelsHidden()
            } else {
                Text(value ? "Yes" : "No")
                    .font(.subheadline)
                    .foregroundColor(value ? color : .secondary)
                    .fontWeight(value ? .semibold : .regular)
            }
        }
    }
}

struct DietaryPreferencesView: View {
    @Binding var dietaryRestrictions: DietaryRestrictions?
    var onClose: () -> Void

    @State private var isEditing = false
    @State private var isSaving = false

    // Local editable copy
    @State private var lactoseIntolerant = false
    @State private var vegetarian = false
    @State private var vegan = false
    @State private var glutenFree = false
    @State private var kosher = false
    @State private var dairyFree = false
    @State private var nutFree = false

    var body: some View {
        Form {
                Section {
                    activeBadges
                } header: {
                    Text("Active Restrictions")
                }

                Section {
                    DietaryRow(icon: "drop.fill",        label: "Lactose Intolerant", color: .blue,   isEditing: isEditing, value: $lactoseIntolerant)
                    DietaryRow(icon: "leaf.fill",        label: "Vegetarian",          color: .green,  isEditing: isEditing, value: $vegetarian)
                    DietaryRow(icon: "leaf.circle.fill", label: "Vegan",               color: .green,  isEditing: isEditing, value: veganBinding)
                    DietaryRow(icon: "allergens",        label: "Gluten Free",         color: .orange, isEditing: isEditing, value: $glutenFree)
                    DietaryRow(icon: "star.fill",        label: "Kosher",              color: .purple, isEditing: isEditing, value: $kosher)
                    DietaryRow(icon: "cup.and.saucer.fill", label: "Dairy Free",       color: .cyan,   isEditing: isEditing, value: $dairyFree)
                    DietaryRow(icon: "exclamationmark.triangle.fill", label: "Nut Free", color: .red,  isEditing: isEditing, value: $nutFree)
                } header: {
                    Text("Preferences")
                } footer: {
                    if isEditing {
                        Text("Enabling Vegan automatically enables Vegetarian and Dairy Free.")
                    }
                }
            }
            .navigationTitle("Dietary Preferences")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button(isEditing ? "Save" : "Edit") {
                            if isEditing {
                                commitChanges()
                                Task { await updatePreferencesInBackend() }
                            } else {
                                startEditing()
                            }
                            isEditing.toggle()
                        }
                        .fontWeight(.semibold)
                    }
                }
            }
            .onAppear { loadFromBinding() }
    }

    // MARK: - Active Badges

    @ViewBuilder
    private var activeBadges: some View {
        let active = activeList
        if active.isEmpty {
            Text("None set")
                .foregroundColor(.secondary)
                .font(.subheadline)
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(active, id: \.label) { item in
                        Label(item.label, systemImage: item.icon)
                            .font(.caption.bold())
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(item.color.opacity(0.15))
                            .foregroundColor(item.color)
                            .clipShape(Capsule())
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    private struct ActiveItem { let label: String; let icon: String; let color: Color }

    private var activeList: [ActiveItem] {
        var list: [ActiveItem] = []
        if lactoseIntolerant { list.append(.init(label: "Lactose Free",  icon: "drop.fill",        color: .blue))   }
        if vegetarian        { list.append(.init(label: "Vegetarian",    icon: "leaf.fill",        color: .green))  }
        if vegan             { list.append(.init(label: "Vegan",         icon: "leaf.circle.fill", color: .green))  }
        if glutenFree        { list.append(.init(label: "Gluten Free",   icon: "allergens",        color: .orange)) }
        if kosher            { list.append(.init(label: "Kosher",        icon: "star.fill",        color: .purple)) }
        if dairyFree         { list.append(.init(label: "Dairy Free",    icon: "cup.and.saucer.fill", color: .cyan)) }
        if nutFree           { list.append(.init(label: "Nut Free",      icon: "exclamationmark.triangle.fill", color: .red)) }
        return list
    }

    // MARK: - Vegan cascades to vegetarian + dairy free

    private var veganBinding: Binding<Bool> {
        Binding(
            get: { vegan },
            set: { newValue in
                vegan = newValue
                if newValue { vegetarian = true; dairyFree = true }
            }
        )
    }

    // MARK: - Sync helpers

    private func loadFromBinding() {
        lactoseIntolerant = dietaryRestrictions?.lactoseIntolerant ?? false
        vegetarian        = dietaryRestrictions?.vegetarian        ?? false
        vegan             = dietaryRestrictions?.vegan             ?? false
        glutenFree        = dietaryRestrictions?.glutenFree        ?? false
        kosher            = dietaryRestrictions?.kosher            ?? false
        dairyFree         = dietaryRestrictions?.dairyFree         ?? false
        nutFree           = dietaryRestrictions?.nutFree           ?? false
    }

    private func startEditing() {
        loadFromBinding()
    }

    private func commitChanges() {
        dietaryRestrictions?.lactoseIntolerant = lactoseIntolerant
        dietaryRestrictions?.vegetarian        = vegetarian
        dietaryRestrictions?.vegan             = vegan
        dietaryRestrictions?.glutenFree        = glutenFree
        dietaryRestrictions?.kosher            = kosher
        dietaryRestrictions?.dairyFree         = dairyFree
        dietaryRestrictions?.nutFree           = nutFree
    }

    // MARK: - API

    func updatePreferencesInBackend() async {
        guard let restrictions = dietaryRestrictions else { return }
        await MainActor.run { isSaving = true }
        DietaryRestrictionsAPI.shared.updateDietaryRestrictions(
            username: restrictions.username,
            dietaryRestrictions: restrictions
        ) { result in
            DispatchQueue.main.async { isSaving = false }
        }
    }
}
