import SwiftUI

struct CalendarPanel: View {
    @ObservedObject var service: CalendarService

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 7)

    var body: some View {
        if service.authorized {
            HStack(spacing: 16) {
                monthGrid.frame(width: 232)
                Divider().overlay(Color.white.opacity(0.08)).padding(.vertical, 4)
                agenda
            }
        } else {
            permissionPrompt
        }
    }

    private var monthGrid: some View {
        VStack(spacing: 6) {
            HStack {
                Text(service.monthTitle)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .contentTransition(.numericText())
                Spacer()
                HStack(spacing: 2) {
                    iconButton("chevron.left") { withAnimation(Theme.content) { service.shiftMonth(by: -1) } }
                    iconButton("circle.fill", size: 6) { withAnimation(Theme.content) { service.goToToday() } }
                    iconButton("chevron.right") { withAnimation(Theme.content) { service.shiftMonth(by: 1) } }
                }
            }

            HStack(spacing: 2) {
                ForEach(Array(service.weekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                    Text(symbol)
                        .font(.system(size: 8.5, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.32))
                        .frame(maxWidth: .infinity)
                }
            }

            LazyVGrid(columns: columns, spacing: 2) {
                ForEach(service.days) { day in
                    DayCell(day: day,
                            isSelected: Calendar.current.isDate(day.date, inSameDayAs: service.selectedDate))
                        .onTapGesture { withAnimation(Theme.content) { service.select(day.date) } }
                }
            }
        }
    }

    private var agenda: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(Self.agendaTitle(service.selectedDate))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
                Spacer()
                Button { service.openCalendarApp() } label: {
                    Image(systemName: "arrow.up.forward.app")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Theme.secondaryText)
                }
                .buttonStyle(.plain)
            }

            if service.events.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "calendar.badge.checkmark")
                        .font(.system(size: 20, weight: .light))
                        .foregroundStyle(.white.opacity(0.28))
                    Text("Nothing scheduled")
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.secondaryText)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 5) {
                        ForEach(service.events) { event in
                            EventRow(event: event)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var permissionPrompt: some View {
        VStack(spacing: 10) {
            Image(systemName: "calendar.badge.exclamationmark")
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(.white.opacity(0.5))
            Text(service.denied ? "Calendar access is off" : "Calendar access needed")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
            Text(service.denied
                 ? "Enable LephorNotch under Privacy & Security › Calendars."
                 : "LephorNotch shows your day in the notch.")
                .font(.system(size: 10))
                .foregroundStyle(Theme.secondaryText)
                .multilineTextAlignment(.center)
            Button(service.denied ? "Open System Settings" : "Grant access") {
                if service.denied {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars")!)
                } else {
                    service.requestAccess()
                }
            }
            .buttonStyle(.plain)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.black)
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(Capsule().fill(.white))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func iconButton(_ symbol: String, size: CGFloat = 9, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .bold))
                .foregroundStyle(Theme.secondaryText)
                .frame(width: 20, height: 18)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private static func agendaTitle(_ date: Date) -> String {
        if Calendar.current.isDateInToday(date) { return "Today" }
        if Calendar.current.isDateInTomorrow(date) { return "Tomorrow" }
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE d MMM"
        return formatter.string(from: date)
    }
}

private struct DayCell: View {
    let day: CalendarDay
    let isSelected: Bool

    @State private var hovering = false

    var body: some View {
        VStack(spacing: 1.5) {
            Text("\(Calendar.current.component(.day, from: day.date))")
                .font(.system(size: 10.5, weight: day.isToday ? .bold : .medium, design: .rounded))
                .foregroundStyle(foreground)
            // One dot per event, capped at three, so a busy day reads at a glance.
            HStack(spacing: 1.5) {
                ForEach(0..<min(day.eventCount, 3), id: \.self) { _ in
                    Circle()
                        .fill(isSelected ? Color.black.opacity(0.6) : Theme.accent)
                        .frame(width: 2.5, height: 2.5)
                }
            }
            .frame(height: 3)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 26)
        .background {
            if isSelected {
                RoundedRectangle(cornerRadius: 7, style: .continuous).fill(.white)
            } else if day.isToday {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(Theme.accent.opacity(0.8), lineWidth: 1)
            } else if hovering {
                RoundedRectangle(cornerRadius: 7, style: .continuous).fill(.white.opacity(0.1))
            }
        }
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .animation(Theme.content, value: hovering)
    }

    private var foreground: Color {
        if isSelected { return .black }
        if !day.isCurrentMonth { return .white.opacity(0.22) }
        if day.isToday { return Theme.accent }
        return .white.opacity(0.82)
    }
}

private struct EventRow: View {
    let event: CalendarEntry
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(event.color)
                .frame(width: 3)
                .frame(maxHeight: .infinity)

            VStack(alignment: .leading, spacing: 1) {
                Text(event.title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                HStack(spacing: 4) {
                    Text(event.timeText)
                    if let location = event.location {
                        Text("·")
                        Text(location).lineLimit(1)
                    }
                }
                .font(.system(size: 9))
                .foregroundStyle(Theme.secondaryText)
            }

            Spacer(minLength: 0)

            if event.isNow {
                Text("NOW")
                    .font(.system(size: 7.5, weight: .black))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(event.color))
            }
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 7)
        .frame(height: 38)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous)
            .fill(.white.opacity(hovering ? 0.10 : 0.05)))
        .onHover { hovering = $0 }
        .animation(Theme.content, value: hovering)
    }
}
