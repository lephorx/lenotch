import AppKit
import SwiftUI

/// Scrollable day strip with the selected day's events underneath, shown to the
/// right of the music.
struct CalendarPanel: View {
    let model: NotchViewModel
    let width: CGFloat
    /// When the calendar has the tab to itself: a month grid with the day's events beside it.
    var expanded = false

    private var calendar: CalendarService { model.calendar }

    var body: some View {
        TimelineView(.everyMinute) { context in
            if expanded {
                HStack(alignment: .top, spacing: 26) {
                    MonthGrid(calendar: calendar)
                        .frame(width: 250)
                    VStack(alignment: .leading, spacing: 8) {
                        Text(calendar.selectedDay, format: .dateTime.weekday(.wide).day().month(.wide))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.85))
                        content(now: context.date)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Text(calendar.selectedDay, format: .dateTime.month(.wide).year())
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.75))
                        .contentTransition(.numericText())
                        .animation(.easeOut(duration: 0.2), value: calendar.selectedDay)
                    DayStrip(calendar: calendar, width: width)
                        .onHover { model.isOverHorizontalScroller = $0 }
                    content(now: context.date)
                }
            }
        }
        .frame(width: width, alignment: .leading)
        .frame(maxHeight: .infinity, alignment: .top)
        // Reload while visible only; the task stops when the notch closes.
        .task {
            calendar.select(Date())
            while !Task.isCancelled {
                calendar.refresh()
                try? await Task.sleep(for: .seconds(60))
            }
        }
        .onChange(of: model.settings.hiddenCalendarIDs) { _, _ in calendar.refresh() }
        .onChange(of: model.settings.hiddenReminderListIDs) { _, _ in calendar.refresh() }
        .onDisappear {
            model.isOverHorizontalScroller = false
            model.isOverVerticalScroller = false
        }
    }

    /// Reminders only when switched on in Settings (they also need permission to load).
    private var shownReminders: [CalendarReminder] {
        model.settings.showReminders ? calendar.reminders : []
    }

    @ViewBuilder
    private func content(now: Date) -> some View {
        switch calendar.access {
        case .unknown:
            EmptyView()
        case .notAsked:
            // Nothing is asked for until the user wants their events here.
            Button {
                calendar.refresh(askIfNeeded: true)
            } label: {
                Label("Show my events", systemImage: "calendar.badge.plus")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.85))
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
        case .denied:
            VStack(alignment: .leading, spacing: 4) {
                Text("Calendar access is off")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.6))
                Button("Allow in Settings", action: calendar.openPrivacySettings)
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.85))
            }
        case .granted:
            if calendar.events.isEmpty && shownReminders.isEmpty {
                Text(Calendar.current.isDateInToday(calendar.selectedDay) ? "No more events or reminders today" : "No events or reminders")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.5))
                    .padding(.top, 4)
            } else {
                ScrollViewReader { proxy in
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(calendar.events) { event in
                                Button(action: calendar.openCalendarApp) {
                                    EventRow(event: event, now: now,
                                             fullTitle: model.settings.showFullEventTitles)
                                }
                                .buttonStyle(.plain)
                                .id(event.id)
                            }
                            ForEach(shownReminders) { reminder in
                                Button(action: calendar.openRemindersApp) {
                                    ReminderRow(reminder: reminder,
                                                fullTitle: model.settings.showFullEventTitles)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .onHover { model.isOverVerticalScroller = $0 }
                    .onAppear { scrollToNextEvent(proxy: proxy) }
                    .onChange(of: calendar.events.map(\.id)) { _, _ in scrollToNextEvent(proxy: proxy) }
                    .onChange(of: model.settings.autoScrollCalendar) { _, enabled in
                        if enabled { scrollToNextEvent(proxy: proxy) }
                    }
                }
                .id(calendar.selectedDay)
                .transition(.opacity)
            }
        }
    }

    private func scrollToNextEvent(proxy: ScrollViewProxy) {
        guard model.settings.autoScrollCalendar,
              Calendar.current.isDateInToday(calendar.selectedDay),
              let next = calendar.events.first(where: { !$0.isAllDay }) else { return }
        DispatchQueue.main.async { proxy.scrollTo(next.id, anchor: .top) }
    }
}

/// Horizontally scrolling days that snap to the centre.
private struct DayStrip: View {
    let calendar: CalendarService
    let width: CGFloat

    @State private var centered: Date?

    private static let cellWidth: CGFloat = 30
    private static let spacing: CGFloat = 6
    /// Days before and after today that can be scrolled to.
    private static let range = -7...14

    private let days: [Date] = {
        let today = Calendar.current.startOfDay(for: Date())
        return range.compactMap { Calendar.current.date(byAdding: .day, value: $0, to: today) }
    }()

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Self.spacing) {
                ForEach(days, id: \.self) { day in
                    DayCell(day: day, isSelected: day == calendar.selectedDay)
                        .id(day)
                        .onTapGesture {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { centered = day }
                        }
                }
            }
            .scrollTargetLayout()
        }
        .contentMargins(.horizontal, (width - Self.cellWidth) / 2, for: .scrollContent)
        .scrollTargetBehavior(.viewAligned)
        .scrollPosition(id: $centered, anchor: .center)
        .frame(width: width, height: 40)
        // Fade the days out towards the edges.
        .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.18),
                                     .init(color: .black, location: 0.82), .init(color: .clear, location: 1)],
                             startPoint: .leading, endPoint: .trailing))
        .onAppear { centered = calendar.selectedDay }
        .onChange(of: calendar.selectedDay) { _, day in
            if centered != day { centered = day }
        }
        .onChange(of: centered) { _, day in
            guard let day else { return }
            guard day != calendar.selectedDay else { return }
            withAnimation(.easeOut(duration: 0.15)) { calendar.select(day) }
            NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
        }
    }
}

private struct DayCell: View {
    let day: Date
    let isSelected: Bool

    private var isToday: Bool { Calendar.current.isDateInToday(day) }

    var body: some View {
        VStack(spacing: 2) {
            Text(day, format: .dateTime.weekday(.narrow))
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(isSelected ? .white.opacity(0.85) : .white.opacity(0.45))
            Text(day, format: .dateTime.day())
                .font(.system(size: 14, weight: .bold).monospacedDigit())
                .foregroundStyle(isSelected ? .white : isToday ? .red : .white.opacity(0.75))
        }
        .frame(width: 30, height: 38)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isSelected ? (isToday ? Color.red : Color.white.opacity(0.18)) : .clear)
        }
        .contentShape(Rectangle())
        .animation(.easeOut(duration: 0.15), value: isSelected)
    }
}

private struct EventRow: View {
    let event: CalendarEvent
    let now: Date
    let fullTitle: Bool

    var body: some View {
        HStack(spacing: 8) {
            Capsule()
                .fill(event.color)
                .frame(width: 3, height: 26)
            VStack(alignment: .leading, spacing: 1) {
                Text(event.title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(fullTitle ? nil : 1)
                HStack(spacing: 4) {
                    if event.isHappening(at: now), !event.isAllDay {
                        Text("Now")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(event.color)
                    }
                    Text(timeText)
                        .font(.system(size: 11, weight: .medium).monospacedDigit())
                        .foregroundStyle(.white.opacity(0.5))
                }
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
    }

    private var timeText: String {
        if event.isAllDay { return "All day" }
        let time = Date.FormatStyle(date: .omitted, time: .shortened)
        return "\(event.start.formatted(time)) – \(event.end.formatted(time))"
    }
}

private struct ReminderRow: View {
    let reminder: CalendarReminder
    let fullTitle: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "checklist")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(reminder.color)
                .frame(width: 12)
            VStack(alignment: .leading, spacing: 1) {
                Text(reminder.title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(fullTitle ? nil : 1)
                Text(reminder.hasTime ? reminder.due.formatted(date: .omitted, time: .shortened) : "Due today")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.5))
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
    }
}
