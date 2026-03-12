//
//  NutritionGoalView.swift
//  PlotLine
//

import SwiftUI

struct NutritionGoalView: View {
    @Binding var goals: NutritionGoals?
    let onSave: (NutritionGoals) -> Void
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme

    // Adaptive color: white in dark mode, blue in light mode
    private var adaptiveTextColor: Color {
        colorScheme == .dark ? .white : .blue
    }

    // Quiz fields
    @State private var weightLbs = ""
    @State private var heightFeet = 5
    @State private var heightInches = 8
    @State private var age = ""
    @State private var gender: QuizData.Gender = .male
    @State private var activityLevel: QuizData.ActivityLevel = .moderatelyActive
    @State private var weightGoal: QuizData.WeightGoal = .maintain

    // Quiz result
    @State private var quizResult: QuizData?
    @State private var showQuizResult = false

    // Edit mode (only available after a goal exists)
    @State private var isEditing = false
    @State private var editCalories = ""
    @State private var editProtein = ""
    @State private var editCarbs = ""
    @State private var editFat = ""

    // Retake quiz from existing goal
    @State private var showRetakeQuiz = false

    var body: some View {
        NavigationView {
            Group {
                if let existing = goals, existing.calorieGoal > 0, !showRetakeQuiz {
                    // Has a goal — show it with edit capability
                    existingGoalView(existing)
                } else {
                    // No goal or retaking quiz — show quiz
                    quizView
                }
            }
            .navigationBarTitle(goals != nil && goals!.calorieGoal > 0 && !showRetakeQuiz ? "Your Goal" : "Calorie Quiz", displayMode: .inline)
            .navigationBarItems(
                leading: Button(showRetakeQuiz ? "Back" : "Cancel") {
                    if showRetakeQuiz {
                        showRetakeQuiz = false
                    } else {
                        dismiss()
                    }
                },
                trailing: trailingButton
            )
            .sheet(isPresented: $showQuizResult) {
                if let data = quizResult {
                    quizResultSheet(data)
                }
            }
        }
    }

    // MARK: - Trailing Nav Button

    @ViewBuilder
    private var trailingButton: some View {
        if showRetakeQuiz || (goals == nil || goals!.calorieGoal <= 0) {
            // Quiz mode
            Button("Calculate") { calculateQuiz() }
                .bold()
                .disabled(!quizFieldsValid)
        } else if isEditing {
            Button("Save") { saveEditedGoal() }
                .bold()
                .disabled(!editFieldsValid)
        } else {
            // Viewing existing goal — no trailing button needed
            EmptyView()
        }
    }

    // MARK: - Existing Goal View

    private func existingGoalView(_ existing: NutritionGoals) -> some View {
        Form {
            // Current goal display / edit
            if isEditing {
                editSection(existing)
            } else {
                displaySection(existing)
            }

            // Actions
            Section {
                Button {
                    // Pre-fill quiz fields from existing quiz data if available
                    if let quiz = existing.quizData {
                        weightLbs = String(format: "%.0f", quiz.weightLbs)
                        heightFeet = quiz.heightFeet
                        heightInches = quiz.heightInches
                        age = "\(quiz.age)"
                        gender = quiz.gender
                        activityLevel = quiz.activityLevel
                        weightGoal = quiz.weightGoal
                    }
                    showRetakeQuiz = true
                } label: {
                    Label("Retake Quiz", systemImage: "arrow.counterclockwise")
                }

                Button(role: .destructive) {
                    onSave(NutritionGoals(calorieGoal: 0, proteinGoal: 0, carbsGoal: 0, fatGoal: 0, source: .manual))
                    dismiss()
                } label: {
                    Label("Remove Goal", systemImage: "trash")
                }
            }
        }
    }

    private func displaySection(_ existing: NutritionGoals) -> some View {
        Group {
            Section {
                VStack(spacing: 16) {
                    Text("\(Int(existing.calorieGoal))")
                        .font(.system(size: 48, weight: .bold, design: .rounded))
                        .foregroundColor(.blue)
                    Text("calories / day")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    HStack(spacing: 12) {
                        macroPreview("Protein", grams: existing.proteinGoal, color: .red)
                        macroPreview("Carbs", grams: existing.carbsGoal, color: .orange)
                        macroPreview("Fat", grams: existing.fatGoal, color: .yellow)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .listRowBackground(Color.clear)
            }

            if let quiz = existing.quizData {
                Section(header: Text("Based On")) {
                    detailRow("BMR", value: "\(Int(quiz.bmr)) cal")
                    detailRow("TDEE", value: "\(Int(quiz.tdee)) cal")
                    detailRow("Goal", value: quiz.weightGoal.displayName)
                    detailRow("Activity", value: quiz.activityLevel.displayName)
                }
            }

            Section {
                Button {
                    editCalories = "\(Int(existing.calorieGoal))"
                    editProtein = "\(Int(existing.proteinGoal))"
                    editCarbs = "\(Int(existing.carbsGoal))"
                    editFat = "\(Int(existing.fatGoal))"
                    isEditing = true
                } label: {
                    Label("Edit Goal", systemImage: "pencil")
                }
            }
        }
    }

    private func editSection(_ existing: NutritionGoals) -> some View {
        Group {
            Section(header: Text("Calories")) {
                HStack {
                    Text("Daily Goal")
                    Spacer()
                    TextField("cal", text: $editCalories)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 100)
                        .accentColor(adaptiveTextColor)
                }
            }

            Section(header: Text("Macros (grams)")) {
                HStack {
                    Text("Protein")
                    Spacer()
                    TextField("g", text: $editProtein)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 80)
                        .accentColor(adaptiveTextColor)
                }
                HStack {
                    Text("Carbs")
                    Spacer()
                    TextField("g", text: $editCarbs)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 80)
                        .accentColor(adaptiveTextColor)
                }
                HStack {
                    Text("Fat")
                    Spacer()
                    TextField("g", text: $editFat)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 80)
                        .accentColor(adaptiveTextColor)
                }
            }

            Section {
                Button("Cancel") {
                    isEditing = false
                }
                .foregroundColor(.red)
            }
        }
    }

    private var editFieldsValid: Bool {
        guard let cal = Double(editCalories), cal > 0 else { return false }
        guard let p = Double(editProtein), p >= 0 else { return false }
        guard let c = Double(editCarbs), c >= 0 else { return false }
        guard let f = Double(editFat), f >= 0 else { return false }
        return true
    }

    private func saveEditedGoal() {
        guard let cal = Double(editCalories),
              let p = Double(editProtein),
              let c = Double(editCarbs),
              let f = Double(editFat) else { return }

        let goal = NutritionGoals(
            calorieGoal: cal,
            proteinGoal: p,
            carbsGoal: c,
            fatGoal: f,
            source: .manual,
            quizData: goals?.quizData // preserve quiz data for reference
        )
        onSave(goal)
        isEditing = false
    }

    // MARK: - Quiz

    private var quizFieldsValid: Bool {
        guard let w = Double(weightLbs), w > 0 else { return false }
        guard let a = Int(age), a > 0, a < 120 else { return false }
        return true
    }

    private var quizView: some View {
        Form {
            Section(header: Text("About You")) {
                Picker("Gender", selection: $gender) {
                    ForEach(QuizData.Gender.allCases, id: \.self) { g in
                        Text(g.displayName).tag(g)
                    }
                }
                .pickerStyle(.segmented)

                HStack {
                    Text("Age")
                    Spacer()
                    TextField("years", text: $age)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 80)
                        .accentColor(adaptiveTextColor)
                }

                HStack {
                    Text("Weight")
                    Spacer()
                    TextField("lbs", text: $weightLbs)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 80)
                        .accentColor(adaptiveTextColor)
                }

                HStack {
                    Text("Height")
                    Spacer()
                    Picker("ft", selection: $heightFeet) {
                        ForEach(3...7, id: \.self) { ft in
                            Text("\(ft) ft").tag(ft)
                        }
                    }
                    .pickerStyle(.menu)
                    .accentColor(adaptiveTextColor)
                    Picker("in", selection: $heightInches) {
                        ForEach(0...11, id: \.self) { inch in
                            Text("\(inch) in").tag(inch)
                        }
                    }
                    .pickerStyle(.menu)
                    .accentColor(adaptiveTextColor)
                }
            }

            Section(header: Text("Activity Level")) {
                ForEach(QuizData.ActivityLevel.allCases, id: \.self) { level in
                    Button {
                        activityLevel = level
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(level.displayName)
                                    .font(.subheadline)
                                    .foregroundColor(.primary)
                                Text(level.detail)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            if activityLevel == level {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.blue)
                            }
                        }
                    }
                }
            }

            Section(header: Text("Weight Goal")) {
                ForEach(QuizData.WeightGoal.allCases, id: \.self) { goal in
                    Button {
                        weightGoal = goal
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(goal.displayName)
                                    .font(.subheadline)
                                    .foregroundColor(.primary)
                                Text(goal.detail)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            if weightGoal == goal {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.blue)
                            }
                        }
                    }
                }
            }
        }
    }

    private func calculateQuiz() {
        guard let w = Double(weightLbs), let a = Int(age) else { return }
        let data = QuizData(
            weightLbs: w,
            heightFeet: heightFeet,
            heightInches: heightInches,
            age: a,
            gender: gender,
            activityLevel: activityLevel,
            weightGoal: weightGoal
        )
        quizResult = data
        showQuizResult = true
    }

    // MARK: - Quiz Result Sheet

    private func quizResultSheet(_ data: QuizData) -> some View {
        let cal = data.targetCalories
        let macros = NutritionGoals.macrosFrom(calories: cal, weightGoal: data.weightGoal)

        return NavigationView {
            VStack(spacing: 24) {
                Spacer()

                Text("Your Recommended Goal")
                    .font(.headline)
                    .foregroundColor(.secondary)

                Text("\(Int(cal))")
                    .font(.system(size: 56, weight: .bold, design: .rounded))
                    .foregroundColor(.blue)
                Text("calories / day")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                HStack(spacing: 20) {
                    macroPreview("Protein", grams: macros.protein, color: .red)
                    macroPreview("Carbs", grams: macros.carbs, color: .orange)
                    macroPreview("Fat", grams: macros.fat, color: .yellow)
                }
                .padding(.horizontal)

                VStack(alignment: .leading, spacing: 8) {
                    detailRow("BMR", value: "\(Int(data.bmr)) cal")
                    detailRow("TDEE", value: "\(Int(data.tdee)) cal")
                    detailRow("Goal", value: data.weightGoal.displayName)
                    detailRow("Activity", value: data.activityLevel.displayName)
                }
                .padding()
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal)

                Text("You can edit these values later.")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Spacer()

                Button {
                    let goal = NutritionGoals(
                        calorieGoal: cal,
                        proteinGoal: macros.protein,
                        carbsGoal: macros.carbs,
                        fatGoal: macros.fat,
                        source: .quiz,
                        quizData: data
                    )
                    onSave(goal)
                    showQuizResult = false
                    showRetakeQuiz = false
                    dismiss()
                } label: {
                    Text("Use This Goal")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .padding(.horizontal)
                .padding(.bottom)
            }
            .navigationBarTitle("Quiz Results", displayMode: .inline)
            .navigationBarItems(leading: Button("Back") { showQuizResult = false })
        }
    }

    // MARK: - Helpers

    private func macroPreview(_ label: String, grams: Double, color: Color) -> some View {
        VStack(spacing: 4) {
            Text("\(Int(grams))g")
                .font(.system(.title3, design: .rounded).bold())
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(color.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func detailRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .bold()
        }
    }
}
