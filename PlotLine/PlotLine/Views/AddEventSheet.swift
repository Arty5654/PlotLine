//
//  AddEventSheet.swift
//  PlotLine
//
//  Created by Alex Younkers on 3/5/25.
//
import SwiftUI

struct AddEventSheet: View {
    
    @Environment(\.presentationMode) var presentationMode
    
    let defaultDate: Date
    
    @State private var title: String = ""
    @State private var description: String = ""
    @State private var startDate: Date
    @State private var endDate: Date
    
    @State private var isRecurring: Bool = false
    @State private var recurrence: String = "none"
    
    @State private var isRange: Bool = false
    
    let onSave: (String, String, Date, Date, String) -> Void
    
    // add new event initializer
    init(defaultDate: Date, onSave: @escaping (String, String, Date, Date, String) -> Void) {
        self.defaultDate = defaultDate
        self.onSave = onSave
        
        // Initialize our @State properties
        _title = State(initialValue: "")
        _description = State(initialValue: "")
        _startDate = State(initialValue: defaultDate)
        _endDate = State(initialValue: defaultDate)
        
        _recurrence = State(initialValue: "none")
        
    }
    
    // update event initializer
    init(existingEvent: Event, onSave: @escaping (String, String, Date, Date, String) -> Void) {
        self.defaultDate = existingEvent.startDate // Not used if you rely on the event’s actual dates
        self.onSave = onSave

        // Initialize @State variables with the existing event’s data
        _title = State(initialValue: existingEvent.title)
        _description = State(initialValue: existingEvent.description)
        _startDate = State(initialValue: existingEvent.startDate)
        _endDate = State(initialValue: existingEvent.endDate)
        
        _isRange = State(
            initialValue: !Calendar.current.isDate(existingEvent.startDate, inSameDayAs: existingEvent.endDate)
        )
        _isRecurring = State(
            initialValue: existingEvent.recurrence != "none"
        )
        
        _recurrence = State(initialValue: existingEvent.recurrence)

    }

    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Event Details")) {
                    TextField("Title", text: $title)
                    TextField("Description", text: $description)
                }
                
                Section(header: Text("Dates")) {
                    Toggle("Multiple Days?", isOn: $isRange)
                    
                    DatePicker("Start Date", selection: $startDate, displayedComponents: .date)
                    
                    if isRange {
                        DatePicker("End Date", selection: $endDate, displayedComponents: .date)
                    }
                }
                
                Section(header: Text("Repeat")) {
                    Toggle("Recurring Event?", isOn: $isRecurring)
                                    
                    if isRecurring {
                        Picker("Frequency", selection: $recurrence) {
                            Text("Never (Default)").tag("none")
                            Text("Every Week").tag("weekly")
                            Text("Every other week").tag("biweekly")
                            Text("Every Month").tag("monthly")
                        }
                    }
                }
            }
            .navigationBarTitle("Add Event", displayMode: .inline)
            .navigationBarItems(
                leading: Button("Cancel") {
                    presentationMode.wrappedValue.dismiss()
                },
                trailing: Button("Save") {
                    let finalEndDate = isRange ? endDate : startDate
                    onSave(title, description, startDate, finalEndDate, recurrence)
                    presentationMode.wrappedValue.dismiss()
                }
            )
        }
    }
}
