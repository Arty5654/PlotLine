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
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemGroupedBackground)
                    .ignoresSafeArea()
                
                VStack(spacing: 16) {
                    Text("Trophy Hall")
                        .font(.custom("AvenirNext-Bold", size: 28))
                        .foregroundColor(.gold)
                        .padding(.top, 8)
                    
                    if trophies.isEmpty {
                        VStack {
                            Spacer()
                            Text("Keep using PlotLine to earn more!")
                                .font(.custom("AvenirNext-Bold", size: 24))
                                .foregroundColor(.blue)
                                .multilineTextAlignment(.center)
                                .padding()
                            Spacer()
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        ScrollView {
                            LazyVGrid(columns: columns, spacing: 20) {
                                ForEach(trophies) { trophy in
                                    VStack(spacing: 8) {
                                        Image(trophyImageName(for: trophy))
                                            .resizable()
                                            .scaledToFit()
                                            .frame(width: 80, height: 80)
                                        Text(trophy.name)
                                            .font(.caption)
                                            .fontWeight(.bold)
                                            .foregroundColor(trophyColor(for: trophy.level))
                                            .multilineTextAlignment(.center)
                                    }
                                    .padding()
                                    .background(Color(.systemBackground))
                                    .cornerRadius(12)
                                    .shadow(color: Color.black.opacity(0.1), radius: 5, x: 0, y: 2)
                                    .onTapGesture {
                                        withAnimation {
                                            selectedTrophy = trophy
                                        }
                                    }
                                }
                            }
                            .padding(.horizontal)
                        }
                    }

                }
                
                if let trophy = selectedTrophy {
                    // lighter dim layer
                    Color.black.opacity(0.2)
                        .ignoresSafeArea()
                        .transition(.opacity)
                        .onTapGesture {
                            withAnimation(.easeOut(duration: 0.2)) {
                                selectedTrophy = nil
                            }
                        }
                    
                    // smaller popup
                    TrophyDetailPopup(trophy: trophy) {
                        withAnimation(.easeOut(duration: 0.2)) {
                            selectedTrophy = nil
                        }
                    }
                    .transition(.scale.combined(with: .opacity))
                    .zIndex(1)
                }
            }
            .navigationBarHidden(true)
            .task { await loadTrophies() }
        }
    }
    
    func loadTrophies() async {
        do {
            let data = try await ProfileAPI.fetchTrophies(username: username)
            trophies = data.filter { $0.level > 0 }
        } catch {
            print("Failed to load trophies:", error)
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
