import SwiftUI

struct TrophyDetailPopup: View {
    let trophy: Trophy
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .center, spacing: 16) {
            
            HStack {
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title)
                        .foregroundColor(.gray)
                }
            }

            Text(trophy.name)
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(trophyColor(for: trophy.level))
                .multilineTextAlignment(.center)

            Text(trophy.description)
                .font(.subheadline)
                .multilineTextAlignment(.center)

            Text("Earned on \(formattedDate(trophy.earnedDate))")
                .font(.footnote)
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)

            Text("Level: \(levelName(for: trophy.level))")
                .font(.headline)
                .multilineTextAlignment(.center)

            // progress or max‑level message
            if let nextThreshold = nextLevelThreshold(for: trophy) {
                ProgressView(value: Float(trophy.progress),
                             total: Float(nextThreshold))
                    .accentColor(.green)
                Text("\(trophy.progress)/\(nextThreshold) until next level")
                    .font(.caption)
                    .multilineTextAlignment(.center)
            } else {
                ProgressView(value: 1.0)
                    .accentColor(.green)
                Text("No further upgrades!")
                    .font(.caption)
                    .foregroundColor(.green)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(radius: 10)
        .padding(40)
    }

    func levelName(for level: Int) -> String {
        switch level {
        case 1: return "Bronze"
        case 2: return "Silver"
        case 3: return "Gold"
        case 4: return "Diamond"
        default: return "Unranked"
        }
    }

    func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: date)
    }

    func nextLevelThreshold(for trophy: Trophy) -> Int? {
        if trophy.level >= 4 { return nil }
        return trophy.level < trophy.thresholds.count
            ? trophy.thresholds[trophy.level]
            : nil
    }

    func trophyColor(for level: Int) -> Color {
        switch level {
        case 1: return Color(red: 205/255, green: 127/255, blue: 50/255)
        case 2: return .gray
        case 3: return .yellow
        case 4: return .blue
        default: return .primary
        }
    }
}

