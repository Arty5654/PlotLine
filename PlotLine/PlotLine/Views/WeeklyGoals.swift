//
//  WeeklyGoals.swift
//  PlotLine
//
//  Created by Allen Chang on 2/25/25.
//

import SwiftUI

struct WeeklyGoalsView: View {
    @State private var tasks: [TaskItem] = []
    @State private var newTask: String = ""

    var body: some View {
        NavigationView {
            VStack {
                Text("Weekly Checklist")
                    .font(.largeTitle)
                    .bold()
                    .padding()

                HStack {
                    TextField("Enter a new task", text: $newTask)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .padding()
                    
                    Button(action: addTask) {
                        Image(systemName: "plus.circle.fill")
                            .font(.title)
                            .foregroundColor(.blue)
                    }
                    .padding()
                }

                List {
                    ForEach(tasks) { task in
                        HStack {
                            Text(task.name)
                                .strikethrough(task.isCompleted)
                                .foregroundColor(task.isCompleted ? .gray : .primary)

                            Spacer()

                            Button(action: {
                                toggleTaskCompletion(task: task)
                            }) {
                                Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                                    .foregroundColor(task.isCompleted ? .green : .gray)
                                    .font(.title2)
                            }
                        }
                    }
                    .onDelete(perform: deleteTask)
                }
                .listStyle(PlainListStyle())
            }
            .navigationBarTitle("Checklist", displayMode: .inline)
        }
    }

    private func addTask() {
        guard !newTask.isEmpty else { return }
        tasks.append(TaskItem(id: UUID(), name: newTask, isCompleted: false))
        newTask = ""
    }

    private func toggleTaskCompletion(task: TaskItem) {
        if let index = tasks.firstIndex(where: { $0.id == task.id }) {
            tasks[index].isCompleted.toggle()
        }
    }

    private func deleteTask(at offsets: IndexSet) {
        tasks.remove(atOffsets: offsets)
    }
}

struct TaskItem: Identifiable {
    let id: UUID
    var name: String
    var isCompleted: Bool
}

struct WeeklyGoalsView_Previews: PreviewProvider {
    static var previews: some View {
        WeeklyGoalsView()
    }
}


#Preview {
    WeeklyGoalsView()
}

