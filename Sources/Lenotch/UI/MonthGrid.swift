import SwiftUI

/// A month at a glance: weekday letters, six weeks of days with the neighbouring
/// months dimmed, today filled, the selected day ringed and up to three event dots
/// per day in their calendars' colours. Clicking a day selects it.
struct MonthGrid: View {
    let calendar: CalendarService

    private static let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)

    private var weekdaySymbols: [String] {
        let system = Calendar.current
        let symbols = system.veryShortStandaloneWeekdaySymbols
        let first = system.firstWeekday - 1
        return Array(symbols[first...] + symbols[..<first])
    }

    var body: some View {
        VStack(spacing: 4) {
            header
            HStack(spacing: 0) {
                ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                    Text(symbol)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.4))
                        .frame(maxWidth: .infinity)
                }
            }
            LazyVGrid(columns: Self.columns, spacing: 1) {
                ForEach(CalendarService.gridDays(for: calendar.displayedMonth), id: \.self) { day in
                    DayCell(day: day,
                            inMonth: Calendar.current.isDate(day, equalTo: calendar.displayedMonth, toGranularity: .month),
                            isSelected: day == calendar.selectedDay,
                            dots: calendar.monthDots[day] ?? [])
                        .onTapGesture {
                            withAnimation(.easeOut(duration: 0.15)) { calendar.select(day) }
                        }
                }
            }
            .id(calendar.displayedMonth)
            .transition(.opacity)
        }
        .animation(.easeOut(duration: 0.2), value: calendar.displayedMonth)
    }

    private var header: some View {
        HStack(spacing: 6) {
            Text(calendar.displayedMonth, format: .dateTime.month(.wide))
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.white)
            Text(calendar.displayedMonth, format: .dateTime.year())
                .font(.system(size: 11, weight: .semibold).monospacedDigit())
                .foregroundStyle(.white.opacity(0.75))
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background(Capsule().fill(.white.opacity(0.14)))
            Spacer(minLength: 0)
            monthButton("chevron.left") { calendar.showMonth(offset: -1) }
            monthButton("chevron.right") { calendar.showMonth(offset: 1) }
        }
    }

    private func monthButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white.opacity(0.6))
                .frame(width: 22, height: 20)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct DayCell: View {
    let day: Date
    let inMonth: Bool
    let isSelected: Bool
    let dots: [Color]

    private var isToday: Bool { Calendar.current.isDateInToday(day) }

    var body: some View {
        VStack(spacing: 1) {
            Text(day, format: .dateTime.day())
                .font(.system(size: 12, weight: .semibold).monospacedDigit())
                .foregroundStyle(isToday ? .white : .white.opacity(inMonth ? 0.9 : 0.3))
                .frame(width: 22, height: 22)
                .background {
                    if isToday {
                        Circle().fill(Color.blue)
                    } else if isSelected {
                        Circle().strokeBorder(Color.blue, lineWidth: 1.5)
                    }
                }
            HStack(spacing: 2) {
                ForEach(Array(dots.enumerated()), id: \.offset) { _, color in
                    Circle().fill(color).frame(width: 4, height: 4)
                }
            }
            .frame(height: 4)
            .opacity(inMonth ? 1 : 0.4)
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
    }
}
