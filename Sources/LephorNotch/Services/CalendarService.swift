import EventKit
import SwiftUI

struct CalendarDay: Identifiable {
    var id: Date { date }
    let date: Date
    let isToday: Bool
    let isCurrentMonth: Bool
    let eventCount: Int
}

struct CalendarEntry: Identifiable {
    let id: String
    let title: String
    let start: Date
    let end: Date
    let isAllDay: Bool
    let color: Color
    let location: String?
    let calendarName: String

    var timeText: String {
        if isAllDay { return "All day" }
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: start)
    }

    var isNow: Bool {
        let now = Date()
        return start <= now && end >= now
    }
}

@MainActor
final class CalendarService: ObservableObject {
    @Published private(set) var authorized = false
    @Published private(set) var denied = false
    @Published private(set) var events: [CalendarEntry] = []
    @Published private(set) var days: [CalendarDay] = []
    @Published var selectedDate = Calendar.current.startOfDay(for: Date())
    @Published var displayedMonth = Date()

    private let store = EKEventStore()
    private var refreshTimer: Timer?

    init() {
        NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged, object: store, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.reload() }
            }
        requestAccess()

        let timer = Timer(timeInterval: 300, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.reload() }
        }
        RunLoop.main.add(timer, forMode: .common)
        refreshTimer = timer
    }

    func requestAccess() {
        Task {
            do {
                let granted = try await store.requestFullAccessToEvents()
                authorized = granted
                denied = !granted
                if granted { reload() }
            } catch {
                authorized = false
                denied = true
            }
        }
    }

    func openCalendarApp() {
        NSWorkspace.shared.open(URL(string: "ical://")!)
    }

    func select(_ date: Date) {
        selectedDate = Calendar.current.startOfDay(for: date)
        reload()
    }

    func shiftMonth(by delta: Int) {
        guard let next = Calendar.current.date(byAdding: .month, value: delta, to: displayedMonth) else { return }
        displayedMonth = next
        reload()
    }

    func goToToday() {
        displayedMonth = Date()
        selectedDate = Calendar.current.startOfDay(for: Date())
        reload()
    }

    func reload() {
        guard authorized else { return }
        buildMonthGrid()
        buildEvents()
    }

    private func buildEvents() {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: selectedDate)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return }

        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        events = store.events(matching: predicate)
            .sorted { ($0.startDate ?? .distantPast) < ($1.startDate ?? .distantPast) }
            .map { event in
                CalendarEntry(
                    id: event.eventIdentifier ?? UUID().uuidString,
                    title: event.title ?? "Untitled",
                    start: event.startDate ?? start,
                    end: event.endDate ?? start,
                    isAllDay: event.isAllDay,
                    color: Color(nsColor: event.calendar.color ?? .systemBlue),
                    location: event.location?.isEmpty == false ? event.location : nil,
                    calendarName: event.calendar.title)
            }
    }

    private func buildMonthGrid() {
        var calendar = Calendar.current
        calendar.firstWeekday = 2 // Monday, matching the macOS default in most locales.

        guard let monthInterval = calendar.dateInterval(of: .month, for: displayedMonth) else { return }
        let firstWeekday = calendar.component(.weekday, from: monthInterval.start)
        let leading = (firstWeekday - calendar.firstWeekday + 7) % 7
        guard let gridStart = calendar.date(byAdding: .day, value: -leading, to: monthInterval.start) else { return }

        // Count events for the whole grid in one query rather than 42 separate ones.
        guard let gridEnd = calendar.date(byAdding: .day, value: 42, to: gridStart) else { return }
        let predicate = store.predicateForEvents(withStart: gridStart, end: gridEnd, calendars: nil)
        var counts: [Date: Int] = [:]
        for event in store.events(matching: predicate) {
            guard let start = event.startDate else { continue }
            let day = calendar.startOfDay(for: start)
            counts[day, default: 0] += 1
        }

        let today = calendar.startOfDay(for: Date())
        days = (0..<42).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: offset, to: gridStart) else { return nil }
            let day = calendar.startOfDay(for: date)
            return CalendarDay(date: day,
                               isToday: day == today,
                               isCurrentMonth: calendar.isDate(day, equalTo: displayedMonth, toGranularity: .month),
                               eventCount: counts[day] ?? 0)
        }
    }

    var monthTitle: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: displayedMonth)
    }

    var weekdaySymbols: [String] {
        var calendar = Calendar.current
        calendar.firstWeekday = 2
        let symbols = calendar.veryShortWeekdaySymbols
        let shift = calendar.firstWeekday - 1
        return Array(symbols[shift...] + symbols[..<shift])
    }
}
