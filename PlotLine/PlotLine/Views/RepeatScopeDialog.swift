//
//  RepeatScopeDialog.swift
//  PlotLine
//
//  "This is a repeating event. Delete This Event Only / Delete All Events"
//

import SwiftUI

/// an action on an event waiting for the answer "this date, or every date?"
struct RepeatChoice: Identifiable {
    let id = UUID()
    let verb: String          // "Delete"
    let destructive: Bool
    let perform: (CalendarViewModel.RepeatScope) -> Void
}

extension View {
    /// asks whether `choice` is for this date of a repeating event or all of them
    func repeatScopeDialog(_ choice: Binding<RepeatChoice?>) -> some View {
        confirmationDialog("This is a repeating event.",
                           isPresented: Binding(get: { choice.wrappedValue != nil },
                                                set: { if !$0 { choice.wrappedValue = nil } }),
                           titleVisibility: .visible,
                           presenting: choice.wrappedValue) { c in
            Button("\(c.verb) This Event Only", role: c.destructive ? .destructive : nil) { c.perform(.thisEvent) }
            Button("\(c.verb) All Events", role: c.destructive ? .destructive : nil) { c.perform(.allEvents) }
            Button("Cancel", role: .cancel) {}
        }
    }
}

extension CalendarViewModel {
    /// Delete, asking first for a repeating event. Imported events are deleted in Apple/Google Calendar.
    @MainActor
    func requestDelete(_ event: Event, ask: (RepeatChoice) -> Void) {
        guard event.importedFrom == nil else { return }
        if event.isRepeating {
            ask(RepeatChoice(verb: "Delete", destructive: true) { [weak self] scope in self?.delete(event, scope: scope) })
        } else {
            delete(event)
        }
    }

    /// Moves one date to another day, keeping its time. For a repeating event only that date moves.
    @MainActor
    func move(_ event: Event, to newDate: Date) {
        let cal = Calendar.current
        let time = cal.dateComponents([.hour, .minute], from: event.startDate)
        var day = cal.dateComponents([.year, .month, .day], from: newDate)
        day.hour = time.hour
        day.minute = time.minute
        guard let newStart = cal.date(from: day) else { return }
        var moved = event
        moved.startDate = newStart
        moved.endDate = newStart.addingTimeInterval(event.endDate.timeIntervalSince(event.startDate))
        saveEdit(original: event, edited: moved, scope: .thisEvent)
    }

    /// Duplicates onto another day, keeping the time.
    @MainActor
    func duplicate(_ event: Event, to newDate: Date) {
        let cal = Calendar.current
        let time = cal.dateComponents([.hour, .minute], from: event.startDate)
        var day = cal.dateComponents([.year, .month, .day], from: newDate)
        day.hour = time.hour
        day.minute = time.minute
        guard let newStart = cal.date(from: day) else { return }
        duplicate(event, start: newStart)
    }
}
