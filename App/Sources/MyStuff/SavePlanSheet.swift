// App/Sources/MyStuff/SavePlanSheet.swift
//
// Saves the Planner's current state as a plan, with an optional reminder (local
// notification) and calendar event.

import PlannerKit
import SwiftData
import SwiftUI

struct SavePlanSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(PlannerState.self) private var planner
    @AppStorage(PlannerOpticsKeys.camera) private var cameraID = ""
    @AppStorage(SettingsKeys.clockStyle) private var clock: ClockStyle = .twentyFourHour
    @State private var name = ""
    @State private var notes = ""
    @State private var reminder = 0
    @State private var addToCalendar = false
    @State private var saving = false
    @State private var problem: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                        .accessibilityIdentifier("plan.name")
                    TextField("Notes", text: $notes, axis: .vertical)
                        .lineLimit(2...5)
                }
                Section {
                    let zone = planner.session.timeZone
                    ValueRow("Place", planner.session.location.name)
                    ValueRow("When", planner.session.instant.formatted(Date.FormatStyle(date: .abbreviated, time: .omitted,
                                                                                       timeZone: zone))
                                     + " " + Formatting.clockTime(planner.session.instant, timeZone: zone, style: clock))
                    if planner.target != nil { ValueRow("Target pin", String(localized: "Included")) }
                }
                Section {
                    Picker("Reminder", selection: $reminder) {
                        Text("None").tag(0)
                        Text("15 minutes before").tag(15)
                        Text("30 minutes before").tag(30)
                        Text("1 hour before").tag(60)
                        Text("2 hours before").tag(120)
                        Text("1 day before").tag(1440)
                    }
                    Toggle("Add to Calendar", isOn: $addToCalendar)
                } footer: {
                    SectionLabel {
                        if let problem { Text(problem).foregroundStyle(.critical) }
                    }
                }
            }
            .navigationTitle("Save plan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(saving)
                        .accessibilityIdentifier("plan.save")
                }
            }
            .onAppear {
                if name.isEmpty { name = String(localized: "\(planner.session.location.name) plan") }
            }
        }
    }

    private func save() {
        saving = true
        let plan = planner.plan(named: name.trimmingCharacters(in: .whitespacesAndNewlines), notes: notes,
                                cameraID: cameraID.isEmpty ? nil : cameraID, reminderMinutes: reminder == 0 ? nil : reminder)
        let record = PlanRecord(plan)
        context.insert(record)
        try? context.save()
        Task {
            record.thumbnail = await PlanThumbnail.make(for: plan)
            var problems: [String] = []
            if plan.reminderMinutes != nil, await !PlanReminders.schedule(plan) {
                problems.append(String(localized: "Notifications are off for Lumora, so no reminder was set."))
            }
            if addToCalendar, await !PlanCalendar.add(plan) {
                problems.append(String(localized: "Calendar access was not given, so no event was added."))
            }
            saving = false
            if problems.isEmpty { dismiss() } else { problem = problems.joined(separator: " ") }
        }
    }
}
