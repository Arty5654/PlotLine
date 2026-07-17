//
//  ArchivedGroceryListsView.swift
//  PlotLine
//

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

struct ArchivedGroceryListsView: View {
    let username: String

    @Environment(\.colorScheme) var colorScheme

    @State private var archivedLists: [GroceryList] = []
    @State private var searchText: String = ""
    @State private var isLoading: Bool = false
    @State private var errorMessage: String? = nil
    @State private var restoringIDs: Set<UUID> = []
    @State private var showDeleteAllConfirm = false
    @State private var isDeletingAll = false
    @State private var alertMessage: String = ""
    @State private var showAlert = false

    private var adaptiveTextColor: Color {
        colorScheme == .dark ? .white : .blue
    }

    private var filteredLists: [GroceryList] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return archivedLists }
        return archivedLists.filter { $0.name.localizedCaseInsensitiveContains(q) }
    }

    var body: some View {
        Group {
            if isLoading && archivedLists.isEmpty {
                List {
                    ForEach(0..<5, id: \.self) { _ in rowSkeleton }
                }
                .listStyle(.insetGrouped)
                .disabled(true)
            } else if let errorMessage {
                VStack(spacing: PLSpacing.md) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 40))
                        .foregroundColor(PLColor.danger)
                    Text("Couldn't load archived lists")
                        .font(.headline)
                    Text(errorMessage)
                        .font(.subheadline)
                        .foregroundColor(PLColor.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, PLSpacing.lg)
                    Button {
                        fetchArchivedGroceryLists()
                    } label: {
                        Text("Try Again")
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color.blue)
                            .clipShape(RoundedRectangle(cornerRadius: PLRadius.md))
                    }
                    .padding(.horizontal, PLSpacing.lg)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                .padding()
            } else if filteredLists.isEmpty {
                VStack(spacing: PLSpacing.md) {
                    Image(systemName: "archivebox")
                        .font(.system(size: 40))
                        .foregroundColor(PLColor.textSecondary)
                    Text(searchText.isEmpty ? "No archived lists" : "No matches")
                        .font(.headline)
                    Text(searchText.isEmpty
                         ? "Swipe left on an active list to archive it. You can restore it anytime."
                         : "Try a different search term.")
                        .font(.subheadline)
                        .foregroundColor(PLColor.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, PLSpacing.lg)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            } else {
                List {
                    Section {
                        ForEach(filteredLists) { list in
                            NavigationLink(destination: ArchivedGroceryListDetailView(groceryList: list)) {
                                row(for: list)
                            }
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    permanentlyDelete(list)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                                Button {
                                    restoreList(list)
                                } label: {
                                    Label("Restore", systemImage: "arrow.counterclockwise")
                                }
                                .tint(.blue)
                                .disabled(restoringIDs.contains(list.id))
                            }
                        }
                    } footer: {
                        Text("\(filteredLists.count) archived \(filteredLists.count == 1 ? "list" : "lists")")
                            .foregroundStyle(PLColor.textSecondary)
                    }
                }
                .listStyle(.insetGrouped)
                .refreshable { fetchArchivedGroceryLists() }
            }
        }
        .navigationTitle("Archived Lists")
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always))
        .toolbar {
            if !archivedLists.isEmpty {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(role: .destructive) {
                        showDeleteAllConfirm = true
                    } label: {
                        Label("Delete All", systemImage: "trash")
                            .foregroundColor(.red)
                    }
                    .disabled(isDeletingAll)
                }
            }
        }
        .confirmationDialog(
            "Delete All Archived Lists?",
            isPresented: $showDeleteAllConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete All", role: .destructive) { deleteAllArchived() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This permanently removes all \(archivedLists.count) archived lists. This cannot be undone.")
        }
        .alert("Status", isPresented: $showAlert) {
            Button("OK") { }
        } message: {
            Text(alertMessage)
        }
        .onAppear { fetchArchivedGroceryLists() }
    }

    // MARK: - Row

    private func row(for groceryList: GroceryList) -> some View {
        HStack(spacing: PLSpacing.md) {
            VStack(alignment: .leading, spacing: 2) {
                Text(groceryList.name)
                    .font(.body)
                    .foregroundColor(PLColor.textPrimary)
                    .lineLimit(1)
                if groceryList.items.count > 0 {
                    Text("\(groceryList.items.count) item\(groceryList.items.count == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundColor(PLColor.textSecondary)
                }
            }

            Spacer(minLength: PLSpacing.sm)

            if restoringIDs.contains(groceryList.id) {
                ProgressView().controlSize(.small)
            } else {
                Button {
                    restoreList(groceryList)
                } label: {
                    Text("Restore")
                        .font(.subheadline).bold()
                        .padding(.vertical, 6)
                        .padding(.horizontal, 12)
                        .background(adaptiveTextColor.opacity(0.12))
                        .foregroundColor(adaptiveTextColor)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 4)
    }

    private var rowSkeleton: some View {
        HStack {
            RoundedRectangle(cornerRadius: 4).fill(PLColor.cardBorder).frame(width: 200, height: 14)
            Spacer()
            RoundedRectangle(cornerRadius: 16).fill(PLColor.cardBorder).frame(width: 78, height: 28)
        }
        .redacted(reason: .placeholder)
        .padding(.vertical, 4)
    }

    // MARK: - Actions

    private func fetchArchivedGroceryLists() {
        isLoading = true
        errorMessage = nil
        GroceryListAPI.getArchivedGroceryLists(username: username) { result in
            DispatchQueue.main.async {
                isLoading = false
                switch result {
                case .success(let lists):
                    archivedLists = lists
                case .failure(let error):
                    errorMessage = "Failed to load archived lists: \(error.localizedDescription)"
                }
            }
        }
    }

    private func restoreList(_ groceryList: GroceryList) {
        restoringIDs.insert(groceryList.id)
        GroceryListAPI.restoreGroceryList(username: username, groceryList: groceryList) { result in
            DispatchQueue.main.async {
                restoringIDs.remove(groceryList.id)
                switch result {
                case .success:
                    archivedLists.removeAll { $0.id == groceryList.id }
                case .failure(let error):
                    alertMessage = "Failed to restore: \(error.localizedDescription)"
                    showAlert = true
                }
            }
        }
    }

    private func permanentlyDelete(_ list: GroceryList) {
        archivedLists.removeAll { $0.id == list.id }
        Task {
            do {
                try await GroceryListAPI.deleteArchivedGroceryList(username: username, listId: list.id.uuidString)
            } catch {
                await MainActor.run {
                    archivedLists.append(list)
                    alertMessage = "Failed to delete: \(error.localizedDescription)"
                    showAlert = true
                }
            }
        }
    }

    private func deleteAllArchived() {
        isDeletingAll = true
        Task {
            do {
                try await GroceryListAPI.deleteAllArchivedGroceryLists(username: username)
                await MainActor.run {
                    archivedLists.removeAll()
                    isDeletingAll = false
                }
            } catch {
                await MainActor.run {
                    isDeletingAll = false
                    alertMessage = "Failed to delete all: \(error.localizedDescription)"
                    showAlert = true
                }
            }
        }
    }
}
