// CaloriesWidget.swift — PlotLineWidgets target
// Shows today's calories and macros vs goals.

import WidgetKit
import SwiftUI

// MARK: - Entry

struct CaloriesEntry: TimelineEntry {
    let date: Date
    let data: NutritionWidgetData
}

// MARK: - Provider

struct CaloriesProvider: TimelineProvider {
    func placeholder(in context: Context) -> CaloriesEntry {
        CaloriesEntry(date: Date(), data: .empty)
    }

    func getSnapshot(in context: Context, completion: @escaping (CaloriesEntry) -> Void) {
        completion(CaloriesEntry(date: Date(), data: readNutritionData()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<CaloriesEntry>) -> Void) {
        let entry = CaloriesEntry(date: Date(), data: readNutritionData())
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 30, to: Date()) ?? Date()
        completion(Timeline(entries: [entry], policy: .after(nextUpdate)))
    }
}

// MARK: - Widget

struct CaloriesWidget: Widget {
    let kind = "CaloriesWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: CaloriesProvider()) { entry in
            CaloriesWidgetView(entry: entry)
                .widgetURL(URL(string: "plotline://nutrition"))
        }
        .configurationDisplayName("Daily Calories")
        .description("Track your daily calorie and macro intake.")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

// MARK: - Root View

struct CaloriesWidgetView: View {
    let entry: CaloriesEntry
    @Environment(\.widgetFamily) var family

    var body: some View {
        switch family {
        case .systemLarge: CaloriesLargeView(data: entry.data)
        default:           CaloriesMediumView(data: entry.data)
        }
    }
}

// MARK: - Medium

struct CaloriesMediumView: View {
    let data: NutritionWidgetData

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "flame.fill").foregroundColor(.orange)
                Text("Calories Today").font(.headline)
                Spacer()
                Text(todayLabel).font(.caption).foregroundColor(.secondary)
            }

            VStack(alignment: .leading, spacing: 4) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.gray.opacity(0.2))
                        Capsule()
                            .fill(calorieColor(data.calorieFraction))
                            .frame(width: geo.size.width * data.calorieFraction)
                    }
                }
                .frame(height: 10)

                HStack {
                    Text("\(Int(data.calories)) kcal").font(.subheadline.bold())
                    Spacer()
                    Text(data.calorieGoal > 0 ? "Goal: \(Int(data.calorieGoal))" : "No goal set")
                        .font(.caption).foregroundColor(.secondary)
                }
            }

            HStack(spacing: 0) {
                MacroChip(label: "P", value: data.protein, goal: data.proteinGoal, color: .blue)
                Spacer()
                MacroChip(label: "C", value: data.carbs,   goal: data.carbsGoal,   color: .green)
                Spacer()
                MacroChip(label: "F", value: data.fat,     goal: data.fatGoal,     color: .yellow)
            }
        }
        .padding()
        .containerBackground(.fill.tertiary, for: .widget)
    }
}

// MARK: - Large

struct CaloriesLargeView: View {
    let data: NutritionWidgetData

    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 6) {
                Image(systemName: "flame.fill").foregroundColor(.orange)
                Text("Calories Today").font(.headline)
                Spacer()
                Text(todayLabel).font(.caption).foregroundColor(.secondary)
            }

            ZStack {
                Circle()
                    .stroke(Color.gray.opacity(0.2), lineWidth: 16)
                Circle()
                    .trim(from: 0, to: data.calorieFraction)
                    .stroke(
                        calorieColor(data.calorieFraction),
                        style: StrokeStyle(lineWidth: 16, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))

                VStack(spacing: 2) {
                    Text("\(Int(data.calories))").font(.title2.bold())
                    Text("/ \(Int(data.calorieGoal))").font(.caption).foregroundColor(.secondary)
                    Text("kcal").font(.caption2).foregroundColor(.secondary)
                }
            }
            .frame(width: 130, height: 130)

            VStack(spacing: 10) {
                MacroBar(label: "Protein", value: data.protein, goal: data.proteinGoal, color: .blue)
                MacroBar(label: "Carbs",   value: data.carbs,   goal: data.carbsGoal,   color: .green)
                MacroBar(label: "Fat",     value: data.fat,     goal: data.fatGoal,     color: .yellow)
            }
        }
        .padding()
        .containerBackground(.fill.tertiary, for: .widget)
    }
}

// MARK: - Shared sub-views

struct MacroChip: View {
    let label: String
    let value: Double
    let goal: Double
    let color: Color

    var body: some View {
        VStack(spacing: 2) {
            Text(label).font(.caption2).foregroundColor(.secondary)
            Text("\(Int(value))g").font(.subheadline.bold()).foregroundColor(color)
            if goal > 0 {
                Text("/\(Int(goal))g").font(.caption2).foregroundColor(.secondary)
            }
        }
    }
}

struct MacroBar: View {
    let label: String
    let value: Double
    let goal: Double
    let color: Color

    var fraction: Double { goal > 0 ? min(value / goal, 1.0) : 0 }

    var body: some View {
        HStack(spacing: 8) {
            Text(label).font(.caption).frame(width: 50, alignment: .leading)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.gray.opacity(0.2))
                    Capsule().fill(color).frame(width: geo.size.width * fraction)
                }
            }
            .frame(height: 8)
            Text("\(Int(value))/\(Int(goal))g")
                .font(.caption).foregroundColor(.secondary)
                .frame(width: 72, alignment: .trailing)
        }
    }
}

// MARK: - Helpers

private var todayLabel: String {
    let f = DateFormatter(); f.dateFormat = "MMM d"; return f.string(from: Date())
}

private func calorieColor(_ fraction: Double) -> Color {
    if fraction > 1.0 { return .red }
    if fraction > 0.85 { return .orange }
    return .green
}
