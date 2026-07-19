import Kastan
import SwiftUI

/// Interprets one dated IDOS service note only within the validity printed for its station timetable.
struct StationTimetableServiceCalendar: Equatable {
    enum Rule: Equatable {
        case runsOnlyOnListedDates
        case doesNotRunOnListedDates
    }

    enum DayStatus: Equatable {
        case runs
        case doesNotRun
        case outsideTimetableValidity
    }

    let note: String
    let validityStart: Date
    let validityEnd: Date
    let listedDates: [Date]
    let rule: Rule

    /// Builds a calendar only when IDOS supplied a complete validity interval and concrete service dates.
    init?(note: String, allNotes: [String]) {
        guard let validity = Self.validity(in: allNotes),
              let rule = Self.rule(in: note)
        else {
            return nil
        }

        let dates = Self.listedDates(
            in: note,
            validityStart: validity.start,
            validityEnd: validity.end
        )
        guard !dates.isEmpty else { return nil }

        self.note = note
        validityStart = validity.start
        validityEnd = validity.end
        listedDates = dates
        self.rule = rule
    }

    /// Distinguishes service days, non-service days, and dates not covered by the current timetable.
    func status(on date: Date) -> DayStatus {
        let calendar = Self.serviceCalendar
        let day = calendar.startOfDay(for: date)
        guard day >= validityStart, day <= validityEnd else {
            return .outsideTimetableValidity
        }

        let isListed = listedDates.contains(day)
        switch rule {
        case .runsOnlyOnListedDates:
            return isListed ? .runs : .doesNotRun
        case .doesNotRunOnListedDates:
            return isListed ? .doesNotRun : .runs
        }
    }

    /// Uses the transport network's civil timezone so service dates do not move when the Mac is elsewhere.
    static var serviceCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = TimeZone(identifier: "Europe/Prague")!
        return calendar
    }

    private struct ServiceDateToken {
        let range: NSRange
        let day: Int
        let month: Int
        let year: Int?
    }

    private static func validity(in notes: [String]) -> (start: Date, end: Date)? {
        let calendar = serviceCalendar

        for note in notes {
            let normalized = note
                .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "cs_CZ"))
                .lowercased()
            guard normalized.contains("plati od") || normalized.contains("valid from") else {
                continue
            }

            let components = captures(
                pattern: #"(\d{1,2})\s*\.\s*(\d{1,2})\s*\.\s*(\d{4})"#,
                in: note
            )
            guard components.count >= 2,
                  let start = numericDate(components[0], calendar: calendar),
                  let end = numericDate(components[1], calendar: calendar),
                  start <= end
            else {
                continue
            }
            return (calendar.startOfDay(for: start), calendar.startOfDay(for: end))
        }

        return nil
    }

    private static func rule(in note: String) -> Rule? {
        let normalized = note
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "cs_CZ"))
            .lowercased()

        if normalized.range(of: #"\bnejede\b|\bdoes\s+not\s+run\b"#, options: .regularExpression) != nil {
            return .doesNotRunOnListedDates
        }
        if normalized.range(of: #"\bjede\b|\bruns?\b"#, options: .regularExpression) != nil {
            return .runsOnlyOnListedDates
        }
        return nil
    }

    private static func listedDates(
        in note: String,
        validityStart: Date,
        validityEnd: Date
    ) -> [Date] {
        let calendar = serviceCalendar
        let tokens = serviceDateTokens(in: note)
        guard !tokens.isEmpty else { return [] }

        var dates = Set<Date>()
        var index = 0
        while index < tokens.count {
            let token = tokens[index]
            let tokenDates = resolvedDates(
                for: token,
                validityStart: validityStart,
                validityEnd: validityEnd,
                calendar: calendar
            )

            if index + 1 < tokens.count,
               isRangeConnector(between: token, and: tokens[index + 1], in: note),
               let start = tokenDates.first,
               let end = resolvedDates(
                   for: tokens[index + 1],
                   validityStart: validityStart,
                   validityEnd: validityEnd,
                   calendar: calendar
               ).first,
               start <= end
            {
                var date = start
                while date <= end {
                    dates.insert(date)
                    guard let next = calendar.date(byAdding: .day, value: 1, to: date) else { break }
                    date = next
                }
                index += 2
            } else {
                dates.formUnion(tokenDates)
                index += 1
            }
        }

        return dates.sorted()
    }

    private static func serviceDateTokens(in note: String) -> [ServiceDateToken] {
        let pattern = #"(?i)(\d{1,2})\s*\.\s*(XII|XI|IX|VIII|VII|VI|IV|V|X|III|II|I|\d{1,2})\s*\.?\s*(\d{4})?"#
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return [] }
        let source = note as NSString

        return expression.matches(in: note, range: NSRange(location: 0, length: source.length)).compactMap { match in
            guard match.numberOfRanges >= 3,
                  let day = Int(source.substring(with: match.range(at: 1))),
                  let month = monthNumber(source.substring(with: match.range(at: 2))),
                  (1...31).contains(day)
            else {
                return nil
            }

            let yearRange = match.range(at: 3)
            let year = yearRange.location == NSNotFound ? nil : Int(source.substring(with: yearRange))
            return ServiceDateToken(range: match.range, day: day, month: month, year: year)
        }
    }

    private static func resolvedDates(
        for token: ServiceDateToken,
        validityStart: Date,
        validityEnd: Date,
        calendar: Calendar
    ) -> [Date] {
        let firstYear = calendar.component(.year, from: validityStart)
        let lastYear = calendar.component(.year, from: validityEnd)
        let years = token.year.map { [$0] } ?? Array(firstYear...lastYear)

        return years.compactMap { year in
            calendar.date(from: DateComponents(
                timeZone: calendar.timeZone,
                year: year,
                month: token.month,
                day: token.day
            )).map(calendar.startOfDay(for:))
        }.filter { $0 >= validityStart && $0 <= validityEnd }
    }

    private static func isRangeConnector(
        between start: ServiceDateToken,
        and end: ServiceDateToken,
        in note: String
    ) -> Bool {
        let source = note as NSString
        let location = NSMaxRange(start.range)
        let length = end.range.location - location
        guard length >= 0 else { return false }
        let connector = source.substring(with: NSRange(location: location, length: length))
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "cs_CZ"))
            .lowercased()
        return connector.contains("-") || connector.contains("–") || connector.contains("—") ||
            connector.range(of: #"\b(?:az|do|to)\b"#, options: .regularExpression) != nil
    }

    private static func monthNumber(_ value: String) -> Int? {
        if let numeric = Int(value), (1...12).contains(numeric) {
            return numeric
        }
        return [
            "I": 1, "II": 2, "III": 3, "IV": 4, "V": 5, "VI": 6,
            "VII": 7, "VIII": 8, "IX": 9, "X": 10, "XI": 11, "XII": 12,
        ][value.uppercased()]
    }

    private static func numericDate(_ values: [String], calendar: Calendar) -> Date? {
        guard values.count == 3,
              let day = Int(values[0]),
              let month = Int(values[1]),
              let year = Int(values[2])
        else {
            return nil
        }
        return calendar.date(from: DateComponents(
            timeZone: calendar.timeZone,
            year: year,
            month: month,
            day: day
        ))
    }

    private static func captures(pattern: String, in value: String) -> [[String]] {
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return [] }
        let source = value as NSString
        return expression.matches(in: value, range: NSRange(location: 0, length: source.length)).map { match in
            (1..<match.numberOfRanges).compactMap { index in
                let range = match.range(at: index)
                return range.location == NSNotFound ? nil : source.substring(with: range)
            }
        }
    }
}

/// Keeps ordinary notes readable while making only date-based service rules interactive.
struct StationTimetableNotesView: View {
    let notes: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(notes.enumerated()), id: \.offset) { _, note in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("•")
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)
                        .frame(width: 8, alignment: .center)
                        .accessibilityHidden(true)

                    if let serviceCalendar = StationTimetableServiceCalendar(note: note, allNotes: notes) {
                        StationTimetableServiceCalendarButton(serviceCalendar: serviceCalendar)
                    } else {
                        Text(note)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }
}

/// Preserves the IDOS note as the button label and reveals its date interpretation in a popover.
struct StationTimetableServiceCalendarButton: View {
    let serviceCalendar: StationTimetableServiceCalendar
    @State private var isPresented = false

    var body: some View {
        Button {
            isPresented = true
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(serviceCalendar.note)
                    .fixedSize(horizontal: false, vertical: true)
                Image(systemName: "calendar")
                    .font(.caption)
                    .accessibilityHidden(true)
            }
            .foregroundStyle(Color.accentColor)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            Text("Show service calendar") + Text(": ") + Text(serviceCalendar.note)
        )
        .help("Show service calendar")
        .popover(isPresented: $isPresented, arrowEdge: .trailing) {
            StationTimetableServiceCalendarView(serviceCalendar: serviceCalendar)
        }
    }
}

/// Shows every month touched by the current timetable and distinguishes operating, non-operating, and invalid days.
private struct StationTimetableServiceCalendarView: View {
    let serviceCalendar: StationTimetableServiceCalendar

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Service calendar")
                .font(.headline)
            Text(serviceCalendar.note)
                .font(.subheadline)
            Text(validityDescription)
                .font(.caption)
                .foregroundStyle(.secondary)

            Divider()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 20) {
                    ForEach(monthStarts, id: \.self) { month in
                        monthView(month)
                    }
                }
            }
            .frame(maxHeight: 460)

            Divider()
            legend
        }
        .padding(18)
        .frame(width: 360)
    }

    private var legend: some View {
        HStack(spacing: 14) {
            legendItem("Runs", color: .green)
            legendItem("Does not run", color: .red)
            legendItem("Outside timetable validity", color: .secondary)
        }
        .font(.caption)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func legendItem(_ label: LocalizedStringKey, color: Color) -> some View {
        HStack(spacing: 5) {
            Circle()
                .fill(color.opacity(0.8))
                .frame(width: 7, height: 7)
                .accessibilityHidden(true)
            Text(label)
        }
    }

    private func monthView(_ month: Date) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(monthFormatter.string(from: month))
                .font(.subheadline.bold())

            LazyVGrid(columns: columns, spacing: 5) {
                ForEach(weekdaySymbols, id: \.self) { symbol in
                    Text(symbol)
                        .font(.caption2.bold())
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .accessibilityHidden(true)
                }
                ForEach(Array(monthCells(for: month).enumerated()), id: \.offset) { _, date in
                    if let date {
                        dayView(date)
                    } else {
                        Color.clear.frame(height: 28)
                    }
                }
            }
        }
    }

    private func dayView(_ date: Date) -> some View {
        let status = serviceCalendar.status(on: date)
        return Text(String(calendar.component(.day, from: date)))
            .font(.caption.monospacedDigit())
            .frame(maxWidth: .infinity, minHeight: 28)
            .foregroundStyle(foregroundColor(for: status))
            .background(backgroundColor(for: status), in: Circle())
            .accessibilityLabel(
                Text(accessibilityDateFormatter.string(from: date)) + Text(", ") + Text(statusLabel(status))
            )
    }

    private func foregroundColor(for status: StationTimetableServiceCalendar.DayStatus) -> Color {
        switch status {
        case .runs:
            return .green
        case .doesNotRun:
            return .red
        case .outsideTimetableValidity:
            return .secondary
        }
    }

    private func backgroundColor(for status: StationTimetableServiceCalendar.DayStatus) -> Color {
        switch status {
        case .runs:
            return .green.opacity(0.16)
        case .doesNotRun:
            return .red.opacity(0.13)
        case .outsideTimetableValidity:
            return .clear
        }
    }

    private func statusLabel(_ status: StationTimetableServiceCalendar.DayStatus) -> LocalizedStringKey {
        switch status {
        case .runs:
            return "Runs"
        case .doesNotRun:
            return "Does not run"
        case .outsideTimetableValidity:
            return "Outside timetable validity"
        }
    }

    private var validityDescription: String {
        AppLocalization.string(
            "Timetable valid %@ – %@",
            dateFormatter.string(from: serviceCalendar.validityStart),
            dateFormatter.string(from: serviceCalendar.validityEnd)
        )
    }

    private var monthStarts: [Date] {
        guard let firstMonth = calendar.date(
            from: calendar.dateComponents([.year, .month], from: serviceCalendar.validityStart)
        ), let lastMonth = calendar.date(
            from: calendar.dateComponents([.year, .month], from: serviceCalendar.validityEnd)
        ) else {
            return []
        }

        var result: [Date] = []
        var month = firstMonth
        while month <= lastMonth {
            result.append(month)
            guard let next = calendar.date(byAdding: .month, value: 1, to: month) else { break }
            month = next
        }
        return result
    }

    private func monthCells(for month: Date) -> [Date?] {
        guard let dayRange = calendar.range(of: .day, in: .month, for: month) else { return [] }
        let weekday = calendar.component(.weekday, from: month)
        let leadingCount = (weekday - calendar.firstWeekday + 7) % 7
        let leading: [Date?] = Array(repeating: nil, count: leadingCount)
        let days = dayRange.compactMap { day -> Date? in
            calendar.date(bySetting: .day, value: day, of: month)
        }.map(Optional.some)
        return leading + days
    }

    private var weekdaySymbols: [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let start = calendar.firstWeekday - 1
        return Array(symbols[start...]) + Array(symbols[..<start])
    }

    private var calendar: Calendar {
        var calendar = StationTimetableServiceCalendar.serviceCalendar
        calendar.locale = presentationLocale
        calendar.firstWeekday = 2
        return calendar
    }

    private var presentationLocale: Locale {
        AppLanguagePreference.idosLanguage == .czech
            ? Locale(identifier: "cs_CZ")
            : Locale(identifier: "en_GB")
    }

    private var dateFormatter: DateFormatter {
        formatter(dateStyle: .medium)
    }

    private var accessibilityDateFormatter: DateFormatter {
        formatter(dateStyle: .full)
    }

    private var monthFormatter: DateFormatter {
        let formatter = formatter(dateStyle: .none)
        formatter.setLocalizedDateFormatFromTemplate("LLLL yyyy")
        return formatter
    }

    private func formatter(dateStyle: DateFormatter.Style) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = presentationLocale
        formatter.timeZone = calendar.timeZone
        formatter.dateStyle = dateStyle
        return formatter
    }
}
