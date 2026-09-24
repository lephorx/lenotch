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
    /// Start of the day whose events are shown.
    private(set) var selectedDay = Calendar.current.startOfDay(for: Date())

    /// Shows the events of `day`.
    func select(_ day: Date) {
        let day = Calendar.current.startOfDay(for: day)
        guard day != selectedDay else { return }
        selectedDay = day
        if access == .granted { load() }
    }

    @ObservationIgnored private var store: EKEventStore?
    @ObservationIgnored private var changeObserver: NSObjectProtocol?

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
        }
    }

    func openCalendarApp() {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.iCal") {
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

        events = store.events(matching: store.predicateForEvents(withStart: selectedDay, end: endOfDay, calendars: nil))
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
    }
}
