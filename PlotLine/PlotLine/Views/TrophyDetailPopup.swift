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
                        .font(.title2)
                        .foregroundColor(Color(.tertiaryLabel))
                }
                .accessibilityLabel("Close")
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
                .foregroundColor(PLColor.textSecondary)
                .multilineTextAlignment(.center)

            Text(levelName(for: trophy.level))
                .font(.footnote.weight(.semibold))
                .foregroundColor(trophyColor(for: trophy.level))
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(trophyColor(for: trophy.level).opacity(0.15))
                .clipShape(Capsule())

            // progress or max‑level message
            if let nextThreshold = nextLevelThreshold(for: trophy) {
                ProgressView(value: Float(trophy.progress),
                             total: Float(nextThreshold))
                    .tint(PLColor.success)
                Text("\(trophy.progress)/\(nextThreshold) until next level")
                    .font(.caption)
                    .multilineTextAlignment(.center)
            } else {
                ProgressView(value: 1.0)
                    .tint(PLColor.success)
                Text("No further upgrades!")
                    .font(.caption)
                    .foregroundColor(PLColor.success)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(PLSpacing.lg)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .shadow(color: .black.opacity(0.2), radius: 20)
        .padding(32)
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

