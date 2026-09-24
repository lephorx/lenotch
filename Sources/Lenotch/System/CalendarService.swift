import AppKit
import EventKit
import Observation
import SwiftUI

struct CalendarEvent: Identifiable, Equatable {
    let id: String
    let title: String
    let start: Date
    let end: Date
    let isAllDay: Bool
    let color: Color

    func isHappening(at date: Date) -> Bool { start <= date && date < end }
}

struct CalendarReminder: Identifiable {
    let id: String
    let title: String
    let due: Date
    let hasTime: Bool
    let color: Color
}

/// Events of one selected day from the Calendar database (for today, only
/// the ones that haven't ended yet).
///
/// The event store is created on first use, so nothing is loaded unless the
/// calendar is actually shown.
@Observable
final class CalendarService {
    enum Access { case unknown, notAsked, granted, denied }

    private(set) var access: Access = .unknown
    private(set) var events: [CalendarEvent] = []
    private(set) var reminders: [CalendarReminder] = []
    /// Start of the day whose events are shown.
    private(set) var selectedDay = Calendar.current.startOfDay(for: Date())
    /// First day of the month shown in the month grid.
    private(set) var displayedMonth = CalendarService.startOfMonth(Date())
    /// Colours of the calendars with events on each day of the month grid (at most three per day).
    private(set) var monthDots: [Date: [Color]] = [:]

    static func startOfMonth(_ date: Date) -> Date {
        let calendar = Calendar.current
        return calendar.date(from: calendar.dateComponents([.year, .month], from: date)) ?? calendar.startOfDay(for: date)
    }

    /// The 42 days (six weeks) the month grid shows, starting on the locale's first weekday.
    static func gridDays(for month: Date) -> [Date] {
        let calendar = Calendar.current
        let weekday = calendar.component(.weekday, from: month)
        let leading = (weekday - calendar.firstWeekday + 7) % 7
        guard let start = calendar.date(byAdding: .day, value: -leading, to: month) else { return [] }
        return (0..<42).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }

    /// Shows another month in the grid (e.g. -1 / +1).
    func showMonth(offset: Int) {
        guard let month = Calendar.current.date(byAdding: .month, value: offset, to: displayedMonth) else { return }
        displayedMonth = month
        if access == .granted { loadMonth() }
    }

    /// Shows the events of `day`.
    func select(_ day: Date) {
        let day = Calendar.current.startOfDay(for: day)
        guard day != selectedDay else { return }
        selectedDay = day
        let month = Self.startOfMonth(day)
        if month != displayedMonth {
            displayedMonth = month
            if access == .granted { loadMonth() }
        }
        if access == .granted { load() }
    }

    @ObservationIgnored private let settings: AppSettings
    @ObservationIgnored private var store: EKEventStore?
    @ObservationIgnored private var changeObserver: NSObjectProtocol?
    @ObservationIgnored private var reminderFetchVersion = 0

    init(settings: AppSettings) { self.settings = settings }

    deinit {
        if let changeObserver { NotificationCenter.default.removeObserver(changeObserver) }
    }

    /// Reloads the events. Only asks macOS for access when `askIfNeeded` (a user's click).
    func refresh(askIfNeeded: Bool = false) {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess:
            access = .granted
            load()
        case .notDetermined:
            guard askIfNeeded else {
                access = .notAsked
                return
            }
            let store = makeStore()
            store.requestFullAccessToEvents { granted, _ in
                DispatchQueue.main.async {
                    self.access = granted ? .granted : .denied
                    if granted { self.load() }
                }
            }
        default:
            access = .denied
            events = []
            reminders = []
        }
    }

    func openCalendarApp() {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.iCal") {
            NSWorkspace.shared.openApplication(at: url, configuration: .init())
        }
    }

    func openRemindersApp() {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.reminders") {
            NSWorkspace.shared.openApplication(at: url, configuration: .init())
        }
    }

    func openPrivacySettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars")!)
    }

    private func makeStore() -> EKEventStore {
        if let store { return store }
        let store = EKEventStore()
        self.store = store
        changeObserver = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged, object: store, queue: .main
        ) { [weak self] _ in self?.load() }
        return store
    }

    private func load() {
        let store = makeStore()
        let calendar = Calendar.current
        let now = Date()
        guard let endOfDay = calendar.date(byAdding: .day, value: 1, to: selectedDay) else { return }
        let isToday = calendar.isDateInToday(selectedDay)

        let calendars = store.calendars(for: .event)
            .filter { !settings.hiddenCalendarIDs.contains($0.calendarIdentifier) }
        events = (calendars.isEmpty ? [] : store.events(matching:
            store.predicateForEvents(withStart: selectedDay, end: endOfDay, calendars: calendars)))
            .filter { !isToday || $0.endDate > now }
            .sorted { ($0.isAllDay ? 0 : 1, $0.startDate) < ($1.isAllDay ? 0 : 1, $1.startDate) }
            .map { event in
                CalendarEvent(id: event.eventIdentifier ?? UUID().uuidString,
                              title: event.title ?? "Untitled",
                              start: event.startDate,
                              end: event.endDate,
                              isAllDay: event.isAllDay,
                              color: Color(nsColor: event.calendar?.color ?? .systemBlue))
            }
        loadReminders(endOfDay: endOfDay)
        loadMonth()
    }

    private func loadMonth() {
        let store = makeStore()
        let calendar = Calendar.current
        let days = Self.gridDays(for: displayedMonth)
        guard let first = days.first, let last = days.last,
              let end = calendar.date(byAdding: .day, value: 1, to: last) else { return }
        let calendars = store.calendars(for: .event)
            .filter { !settings.hiddenCalendarIDs.contains($0.calendarIdentifier) }
        guard !calendars.isEmpty else {
            monthDots = [:]
            return
        }
        var dots: [Date: [Color]] = [:]
        var seen: [Date: Set<String>] = [:]
        for event in store.events(matching: store.predicateForEvents(withStart: first, end: end, calendars: calendars)) {
            let id = event.calendar?.calendarIdentifier ?? ""
            var day = max(calendar.startOfDay(for: event.startDate), first)
            // Multi-day events get a dot on every day they cover (end is exclusive).
            while day < min(event.endDate, end) {
                if (dots[day]?.count ?? 0) < 3, seen[day, default: []].insert(id).inserted {
                    dots[day, default: []].append(Color(nsColor: event.calendar?.color ?? .systemBlue))
                }
                guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
                day = next
            }
        }
        monthDots = dots
    }

    private func loadReminders(endOfDay: Date) {
        reminderFetchVersion += 1
        let version = reminderFetchVersion
        guard EKEventStore.authorizationStatus(for: .reminder) == .fullAccess else {
            reminders = []
            return
        }
        let store = makeStore()
        let lists = store.calendars(for: .reminder)
            .filter { !settings.hiddenReminderListIDs.contains($0.calendarIdentifier) }
        guard !lists.isEmpty else {
            reminders = []
            return
        }
        let predicate = store.predicateForIncompleteReminders(
            withDueDateStarting: selectedDay, ending: endOfDay, calendars: lists)
        store.fetchReminders(matching: predicate) { [weak self] results in
            DispatchQueue.main.async {
                guard let self, self.reminderFetchVersion == version else { return }
                self.reminders = (results ?? []).compactMap { reminder in
                    guard let components = reminder.dueDateComponents,
                          let due = Calendar.current.date(from: components),
                          due >= self.selectedDay, due < endOfDay else { return nil }
                    return CalendarReminder(id: reminder.calendarItemIdentifier,
                                            title: reminder.title ?? "Untitled",
                                            due: due,
                                            hasTime: components.hour != nil,
                                            color: Color(nsColor: reminder.calendar.color))
                }
                .sorted { $0.due < $1.due }
            }
        }
    }
}
