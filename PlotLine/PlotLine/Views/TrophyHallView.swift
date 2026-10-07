import SwiftUI

extension Color {
    static let gold = Color(red: 212/255, green: 175/255, blue: 55/255)
}

struct TrophyHallView: View {
    let username: String
    @State private var trophies: [Trophy] = []
    @State private var selectedTrophy: Trophy?
    
    let columns = [
        GridItem(.flexible()),
        GridItem(.flexible())
    ]
    
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                ScrollView {
                    if trophies.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "trophy")
                                .font(.largeTitle)
                                .foregroundColor(.gold)
                            Text("No trophies yet")
                                .font(.headline)
                            Text("Keep using PlotLine (budget, log meals, reach goals) to earn them.")
                                .font(.subheadline)
                                .foregroundColor(PLColor.textSecondary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, PLSpacing.lg)
                        .plCard()
                        .padding(PLSpacing.lg)
                    } else {
                        LazyVGrid(columns: columns, spacing: PLSpacing.md) {
                            ForEach(trophies) { trophy in
                                VStack(spacing: 8) {
                                    Image(trophyImageName(for: trophy))
                                        .resizable()
                                        .scaledToFit()
                                        .frame(width: 72, height: 72)
                                    Text(trophy.name)
                                        .font(.footnote.weight(.semibold))
                                        .foregroundColor(trophyColor(for: trophy.level))
                                        .multilineTextAlignment(.center)
                                        .frame(maxWidth: .infinity)
                                }
                                .plCard()
                                .onTapGesture {
                                    withAnimation { selectedTrophy = trophy }
                                }
                            }
                        }
                        .padding(PLSpacing.lg)
                    }
                }

                if let trophy = selectedTrophy {
                    Color.black.opacity(0.3)
                        .ignoresSafeArea()
                        .transition(.opacity)
                        .onTapGesture {
                            withAnimation(.easeOut(duration: 0.2)) { selectedTrophy = nil }
                        }

                    TrophyDetailPopup(trophy: trophy) {
                        withAnimation(.easeOut(duration: 0.2)) { selectedTrophy = nil }
                    }
                    .transition(.scale.combined(with: .opacity))
                    .zIndex(1)
                }
            }
            .navigationTitle("Trophy Hall")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task { await loadTrophies() }
        }
    }
    
    func loadTrophies() async {
        do {
            let data = try await ProfileAPI.fetchTrophies(username: username)
            trophies = data.filter { $0.level > 0 }
        } catch {
            AppBanner.report("load your trophies", error)
        }
    }
    
    func trophyImageName(for trophy: Trophy) -> String {
        
        if trophy.id == "llm-investor" { return "llmTrophy" }
        if trophy.id == "first-profile-picture" { return "profilePicTrophy" }
        
        switch trophy.level {
            case 1: return "bronzeTrophy"
            case 2: return "silverTrophy"
            case 3: return "goldTrophy"
            case 4: return "diamondTrophy"
            default: return "bronzeTrophy"
        }
    }
    
    func trophyColor(for level: Int) -> Color {
        switch level {
            case 1: return Color(red: 205/255, green: 127/255, blue: 50/255)
            case 2: return .gray
            case 3: return .yellow
            case 4: return .mint
            default: return .primary
        }
    }
}
