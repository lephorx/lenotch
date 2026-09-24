import AppKit
import EventKit
import SwiftUI

/// Calendar and reminder sources are identified by EventKit IDs, so lists with
/// the same displayed name can be selected independently.
struct CalendarSettings: View {
    @Bindable var settings: AppSettings
    let permissions: PermissionCenter

    @State private var sources: [Source] = []
    @State private var reminderLists: [Source] = []
    @State private var store = EKEventStore()

    private struct Source: Identifiable {
        let id: String
        let name: String
        let color: Color
    }

    var body: some View {
        Form {
            Section {
                permissions.toggle("Show the calendar", isEnabled: $settings.showCalendar, calendar: .events)
            } footer: {
                Text("Your events next to the music. Switching it on asks for calendar access.")
            }
            Section {
                Picker("Layout", selection: $settings.expandedCalendarStyle) {
                    ForEach(ExpandedCalendarStyle.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
            } header: {
                Text("Big calendar")
            } footer: {
                Text("When the music player is off, the calendar fills the tab: a month grid with the day's events beside it, or the scrolling day strip.")
            }
            Section("Events") {
                permissions.toggle("Show reminders", isEnabled: $settings.showReminders, calendar: .reminders)
                Toggle("Auto scroll to next event", isOn: $settings.autoScrollCalendar)
                Toggle("Always show full event titles", isOn: $settings.showFullEventTitles)
            }

            Section("Calendars") {
                switch permissions.calendar {
                case .granted:
                    if sources.isEmpty {
                        Text("No calendars found").foregroundStyle(.secondary)
                    } else {
                        ForEach(sources) { source in
                            sourceRow(source, hidden: $settings.hiddenCalendarIDs)
                        }
                    }
                case .notAsked:
                    Button("Allow Calendar Access", action: permissions.requestCalendar)
                case .denied, .needsAppOpen:
                    Button("Open Calendar Privacy Settings") {
                        permissions.openPrivacySettings("Privacy_Calendars")
                    }
                }
            }

            Section {
                switch permissions.reminders {
                case .granted:
                    if reminderLists.isEmpty {
                        Text("No reminder lists found").foregroundStyle(.secondary)
                    } else {
                        ForEach(reminderLists) { source in
                            sourceRow(source, hidden: $settings.hiddenReminderListIDs)
                        }
                    }
                case .notAsked:
                    Button("Allow Reminders Access", action: permissions.requestReminders)
                case .denied, .needsAppOpen:
                    Button("Open Reminders Privacy Settings") {
                        permissions.openPrivacySettings("Privacy_Reminders")
                    }
                }
            } header: {
                Text("Reminders")
            } footer: {
                Text("Incomplete reminders due on the selected day appear below calendar events. Reminders access is requested only when you click Allow.")
            }
        }
        .formStyle(.grouped)
        .onAppear(perform: refresh)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in refresh() }
        .onChange(of: permissions.calendar) { _, _ in refresh() }
        .onChange(of: permissions.reminders) { _, _ in refresh() }
    }

    private func sourceRow(_ source: Source, hidden: Binding<Set<String>>) -> some View {
        Toggle(isOn: Binding(
            get: { !hidden.wrappedValue.contains(source.id) },
            set: { enabled in
                if enabled { hidden.wrappedValue.remove(source.id) }
                else { hidden.wrappedValue.insert(source.id) }
            }
        )) {
            HStack(spacing: 9) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(source.color)
                    .frame(width: 13, height: 13)
                Text(source.name)
            }
        }
    }

    private func refresh() {
        permissions.refresh()
        sources = permissions.calendar == .granted
            ? store.calendars(for: .event).map { Source(id: $0.calendarIdentifier, name: $0.title,
                                                       color: Color(nsColor: $0.color)) }
                .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            : []
        reminderLists = permissions.reminders == .granted
            ? store.calendars(for: .reminder).map { Source(id: $0.calendarIdentifier, name: $0.title,
                                                          color: Color(nsColor: $0.color)) }
                .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            : []
    }
}
