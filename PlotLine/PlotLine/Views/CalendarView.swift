//
//  CalendarView.swift
//  PlotLine
//
//  Created by Alex Younkers on 3/5/25.
//

import SwiftUI

struct CalendarView: View {
    
    @EnvironmentObject var viewModel: CalendarViewModel
    
    @State private var showingAddEventSheet = false
    // 7 columns for the 7 days of the week
    private let monthColumns = Array(repeating: GridItem(.flexible()), count: 7)
    
    var body: some View {
        
        NavigationView {
            ScrollView {
                VStack(alignment: .leading) {
                    
                    HStack {
                        if viewModel.displayMode == .month {
                            Button(action: { viewModel.previousMonth() }) {
                                Image(systemName: "chevron.left")
                            }
                            
                            Text(monthTitle(for: viewModel.currentDate))
                                .font(.headline)
                            
                            Button(action: { viewModel.nextMonth() }) {
                                Image(systemName: "chevron.right")
                            }
                        } else {
                            
                            Button(action: { viewModel.previousWeek() }) {
                                Image(systemName: "chevron.left")
                            }
                            
                            Text(weekTitle(for: viewModel.currentDate))
                                .font(.headline)
                            
                            Button(action: { viewModel.nextWeek() }) {
                                Image(systemName: "chevron.right")
                            }
                        }
                        
                        Spacer()
                        
                        Button(action: {
                            if viewModel.displayMode == .month {
                                viewModel.showWeekView()
                            } else {
                                viewModel.showMonthView()
                            }
                        }) {
                            Text(viewModel.displayMode == .month ? "Week View" : "Month View")
                        }
                    }
                    .padding()
                    
                    if viewModel.displayMode == .month {
                        MonthContent(viewModel: viewModel, monthColumns: monthColumns)
                    } else {
                        // Weekly view
                        WeekContent(viewModel: viewModel)
                    }
                    
                    Button(action: {
                        showingAddEventSheet = true
                    }) {
                        Text("Add Event")
                            .font(.headline)
                            .padding()
                            .frame(maxWidth: .infinity)
                            .foregroundColor(.white)
                            .background(Color.blue)
                            .cornerRadius(10)
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 12)
                    
                }
                .onAppear {
                    // on first appearance, fetch events
                    //viewModel.fetchEvents()
                }
            }
            .sheet(isPresented: $showingAddEventSheet) {
                AddEventSheet(defaultDate: viewModel.selectedDay ?? viewModel.currentDate) { title, description, start, end, recurrence in
                    viewModel.createEvent(
                        title: title,
                        description: description,
                        startDate: start,
                        endDate: end,
                        eventType: "user",
                        recurrence: recurrence
                    )
                }
            }
        }
    }
    
    private func monthTitle(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "LLLL yyyy"
        return formatter.string(from: date)
    }
    
    private func weekTitle(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "'Week of' MMM d, yyyy"
        return formatter.string(from: startOfWeek(for: date))
    }
    
    private func dayNumber(_ date: Date) -> String {
        let day = Calendar.current.component(.day, from: date)
        return String(day)
    }
    
    private func shortWeekdayName(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "E"
        return formatter.string(from: date)
    }
    
    private func startOfWeek(for date: Date) -> Date {
        var calendar = Calendar.current
        // If you want Monday to be the very start of the week:
        // calendar.firstWeekday = 2
        calendar.firstWeekday = 1
        let components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return calendar.date(from: components) ?? date
    }
}


struct MonthContent: View {
    @ObservedObject var viewModel: CalendarViewModel
    let monthColumns: [GridItem]

    var body: some View {
        VStack(alignment: .leading) {
            // Day names
            let dayNames = ["Sun","Mon","Tue","Wed","Thu","Fri","Sat"]
            HStack {
                ForEach(dayNames, id: \.self) { dayName in
                    Text(dayName)
                        .font(.subheadline)
                        .foregroundColor(.gray)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 8)
            
            // Month grid
            let daysInMonth = viewModel.daysInCurrentMonth()
            if let firstDayOfMonth = daysInMonth.first {
                let calendar = Calendar.current
                let firstWeekday = calendar.component(.weekday, from: firstDayOfMonth)
                let offset = firstWeekday - 1
                
                LazyVGrid(columns: monthColumns, spacing: 20) {
                    ForEach(0..<offset, id: \.self) { _ in
                        Text("")
                    }
                    ForEach(daysInMonth, id: \.self) { day in
                        NavigationLink(destination: DayView(day: day, viewModel: viewModel)) {
                            Text(dayNumber(day))
                                .foregroundColor(.primary)
                                .frame(width: 30, height: 30)
                                .background(
                                    colorForDay(day)
                                )
                                .clipShape(Circle())
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.bottom)
            }
        }
    }
    
    // helpers for month
    private func dayNumber(_ date: Date) -> String {
        let day = Calendar.current.component(.day, from: date)
        return String(day)
    }
    
    private func colorForDay(_ day: Date) -> Color {
        // Get all events for this day
        let dayEvents = viewModel.eventsOnDay(day)
        if dayEvents.isEmpty {
            return .clear
        }

        if dayEvents.contains(where: { $0.eventType == "rent" }) {
            // on rent due dates, color red
            return Color.red.opacity(0.2)
        } else if dayEvents.contains(where: { $0.eventType.lowercased().starts(with: "subscription") }) {
            // on subscription due dates, color yellow
            return Color.yellow.opacity(0.2)
        } else {
            return Color.blue.opacity(0.2)
        }
    }
}

struct WeekContent: View {
    @ObservedObject var viewModel: CalendarViewModel
    
    var body: some View {
        let start = startOfWeek(for: viewModel.currentDate)
        
        ForEach(0..<7, id: \.self) { offset in
            let day = Calendar.current.date(byAdding: .day, value: offset, to: start)!
            
            VStack(alignment: .leading, spacing: 4) {
                
                HStack {
                    Text(shortWeekdayName(for: day))
                        .font(.subheadline)
                        .foregroundColor(.gray)
                    Text(dayNumber(day))
                        .font(.headline)
                }
                
                let dayEvents = viewModel.eventsOnDay(day)
                if dayEvents.isEmpty {
                    Text("No events")
                        .foregroundColor(.secondary)
                        .font(.caption)
                } else {
                    ForEach(dayEvents) { event in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text("•")
                            Text(event.title)
                                .fontWeight(.bold)
                        }
                        .font(.body)
                    }
                }
            }
            .padding(.vertical, 8)
            .padding(.horizontal)
            .background(
                viewModel.hasEvent(on: day) ? Color.blue.opacity(0.1) : Color.clear
            )
            .cornerRadius(8)
            .padding(.horizontal)
        }
    }
    
    // Helpers
    private func dayNumber(_ date: Date) -> String {
        let day = Calendar.current.component(.day, from: date)
        return String(day)
    }
    
    private func shortWeekdayName(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "E"
        return formatter.string(from: date)
    }
    
    private func startOfWeek(for date: Date) -> Date {
        var calendar = Calendar.current
        calendar.firstWeekday = 1
        let components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return calendar.date(from: components) ?? date
    }
    

}





#Preview {
    CalendarView()
}

