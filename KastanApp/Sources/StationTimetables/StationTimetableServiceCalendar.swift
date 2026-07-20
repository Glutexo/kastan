import AppKit
import Kastan
import SwiftUI

/// Interprets one dated or recurring IDOS condition only within the validity of its current timetable.
struct StationTimetableServiceCalendar: Equatable {
    struct Rule: Equatable {
        enum Subject: Equatable {
            case serviceOperation
            case noteApplicability
        }

        enum Recurrence: Equatable {
            case none
            case everyDay
            case workingDays
            case selectedWeekdays(Set<Int>)
        }

        let subject: Subject
        let recurrence: Recurrence
        let operatingRange: ClosedRange<Date>
        let hasExplicitOperatingRange: Bool
        let additionalRunningRanges: [ClosedRange<Date>]
        let nonRunningRanges: [ClosedRange<Date>]
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
    let recognizedDateRanges: [ClosedRange<Date>]
    let rule: Rule

    /// Builds a calendar when IDOS supplied a complete validity interval and a dated or recurring condition.
    init?(note: String, allNotes: [String]) {
        guard let validity = Self.validity(in: allNotes) else { return nil }
        self.init(note: note, validityStart: validity.start, validityEnd: validity.end)
    }

    /// Builds a calendar from validity loaded separately from an IDOS connection timetable.
    init?(note: String, validityStart: Date, validityEnd: Date) {
        let calendar = Self.serviceCalendar
        let validityStart = calendar.startOfDay(for: validityStart)
        let validityEnd = calendar.startOfDay(for: validityEnd)
        guard validityStart <= validityEnd,
              let parsedRule = Self.parsedRule(
                  in: note,
                  validityStart: validityStart,
                  validityEnd: validityEnd
              )
        else { return nil }

        self.note = note
        self.validityStart = validityStart
        self.validityEnd = validityEnd
        listedDates = parsedRule.listedDates
        recognizedDateRanges = parsedRule.recognizedDateRanges
        rule = parsedRule.rule
    }

    /// Distinguishes matching days, non-matching days, and dates not covered by the current timetable.
    func status(on date: Date) -> DayStatus {
        let calendar = Self.serviceCalendar
        let day = calendar.startOfDay(for: date)
        guard day >= validityStart, day <= validityEnd else {
            return .outsideTimetableValidity
        }

        if rule.nonRunningRanges.contains(where: { $0.contains(day) }) {
            return .doesNotRun
        }
        if rule.additionalRunningRanges.contains(where: { $0.contains(day) }) {
            return .runs
        }
        guard rule.operatingRange.contains(day) else {
            return .doesNotRun
        }

        switch rule.recurrence {
        case .none:
            return .doesNotRun
        case .everyDay:
            return .runs
        case .workingDays:
            return Self.isCzechWorkingDay(day, calendar: calendar) ? .runs : .doesNotRun
        case let .selectedWeekdays(weekdays):
            return weekdays.contains(Self.idosWeekday(for: day, calendar: calendar))
                ? .runs
                : .doesNotRun
        }
    }

    /// Selects the current civil month when it is visible, or the nearest validity boundary otherwise.
    func initialVisibleMonth(on date: Date) -> Date {
        let calendar = Self.serviceCalendar
        guard let requestedMonth = calendar.date(
            from: calendar.dateComponents([.year, .month], from: date)
        ), let firstMonth = calendar.date(
            from: calendar.dateComponents([.year, .month], from: validityStart)
        ), let lastMonth = calendar.date(
            from: calendar.dateComponents([.year, .month], from: validityEnd)
        ) else {
            return validityStart
        }

        return min(max(requestedMonth, firstMonth), lastMonth)
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

    /// Keeps both effective dates and the individual dates or ranges recognized in the IDOS note.
    private struct DateInterpretation {
        let dates: [Date]
        let ranges: [ClosedRange<Date>]
    }

    /// Carries the composed operating rule together with the dates represented by the source note.
    private struct ParsedRule {
        let rule: Rule
        let listedDates: [Date]
        let recognizedDateRanges: [ClosedRange<Date>]
    }

    /// Describes a one-sided service range whose other boundary is the timetable validity interval.
    private enum ValidityRelativeRange {
        case fromValidityStart
        case throughValidityEnd
    }

    /// Fixed Czech holidays encoded as month × 100 + day for efficient calendar-cell evaluation.
    private static let fixedCzechHolidayCodes: Set<Int> = [
        101,
        501, 508,
        705, 706,
        928,
        1028,
        1117,
        1224, 1225, 1226,
    ]

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

    /// Composes the recurring rule, positive exceptions, and negative exceptions found in one IDOS note.
    private static func parsedRule(
        in note: String,
        validityStart: Date,
        validityEnd: Date
    ) -> ParsedRule? {
        let normalized = note
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "cs_CZ"))
            .lowercased()

        let positiveRunPattern = #"\bjede\b|(?<!not )\bruns?\b"#
        let negativeRunPattern = #"\bnejede\b|\bdoes\s+not\s+run\b"#
        let hasPositiveRule = normalized.range(of: positiveRunPattern, options: .regularExpression) != nil
        let hasNegativeRule = normalized.range(of: negativeRunPattern, options: .regularExpression) != nil
        let standaloneWeekdays = numberedWeekdays(in: normalized)
        guard hasPositiveRule || hasNegativeRule || standaloneWeekdays != nil else { return nil }

        let source = note as NSString
        let negativeMatch = try? NSRegularExpression(
            pattern: #"(?i)\bnejede\b|\bdoes\s+not\s+run\b"#
        ).firstMatch(in: note, range: NSRange(location: 0, length: source.length))
        let positiveNote: String
        let negativeNote: String?
        if let negativeMatch {
            positiveNote = source.substring(to: negativeMatch.range.location)
            negativeNote = source.substring(from: negativeMatch.range.location)
        } else {
            positiveNote = note
            negativeNote = nil
        }

        let positiveNormalized = positiveNote
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "cs_CZ"))
            .lowercased()
        let runsThroughBoundaryPattern = #"\bjede\s+do\b|(?<!not )\bruns?\s+(?:until|to)\b"#
        let runsThroughBoundary = positiveNormalized.range(
            of: runsThroughBoundaryPattern,
            options: .regularExpression
        ) != nil
        let workingDayPattern =
            #"\bjede\s+v\s+(?:x\b|pracovnich\s+dnech\b)|(?<!not )\bruns?\s+(?:on\s+)?(?:working\s+days?|weekdays?|workdays?)\b"#
        let recurrence: Rule.Recurrence
        if positiveNormalized.range(of: workingDayPattern, options: .regularExpression) != nil {
            recurrence = .workingDays
        } else if let weekdays = numberedWeekdays(in: positiveNormalized) {
            recurrence = .selectedWeekdays(weekdays)
        } else if runsThroughBoundary || !hasPositiveRule {
            recurrence = .everyDay
        } else {
            recurrence = .none
        }

        let positiveInterpretation = dateInterpretation(
            in: positiveNote,
            validityStart: validityStart,
            validityEnd: validityEnd
        )
        let nonRunningRanges = negativeNote.map {
            dateInterpretation(
                in: $0,
                validityStart: validityStart,
                validityEnd: validityEnd
            ).ranges
        } ?? []

        let operatingRange: ClosedRange<Date>
        let hasExplicitOperatingRange: Bool
        let additionalRunningRanges: [ClosedRange<Date>]
        if runsThroughBoundary,
           let boundaryToken = serviceDateTokens(in: positiveNote).first,
           let boundaryDate = resolvedDates(
               for: boundaryToken,
               validityStart: validityStart,
               validityEnd: validityEnd,
               calendar: serviceCalendar
           ).first
        {
            operatingRange = validityStart...boundaryDate
            hasExplicitOperatingRange = true
            additionalRunningRanges = Array(positiveInterpretation.ranges.dropFirst())
        } else {
            operatingRange = validityStart...validityEnd
            hasExplicitOperatingRange = false
            additionalRunningRanges = positiveInterpretation.ranges
        }

        let hasRecurringCondition: Bool
        switch recurrence {
        case .workingDays, .selectedWeekdays:
            hasRecurringCondition = true
        case .everyDay:
            hasRecurringCondition = hasExplicitOperatingRange
        case .none:
            hasRecurringCondition = false
        }
        guard hasRecurringCondition || !additionalRunningRanges.isEmpty || !nonRunningRanges.isEmpty else {
            return nil
        }

        let rule = Rule(
            subject: hasPositiveRule || hasNegativeRule ? .serviceOperation : .noteApplicability,
            recurrence: recurrence,
            operatingRange: operatingRange,
            hasExplicitOperatingRange: hasExplicitOperatingRange,
            additionalRunningRanges: additionalRunningRanges,
            nonRunningRanges: nonRunningRanges
        )
        var recognizedDateRanges = additionalRunningRanges + nonRunningRanges
        if hasExplicitOperatingRange {
            recognizedDateRanges.insert(operatingRange, at: 0)
        }
        let listedDates = Set(recognizedDateRanges.flatMap {
            dates(from: $0.lowerBound, through: $0.upperBound, calendar: serviceCalendar)
        }).sorted()
        return ParsedRule(
            rule: rule,
            listedDates: listedDates,
            recognizedDateRanges: recognizedDateRanges
        )
    }

    /// Reads individual numbers and ranges in IDOS's Monday-first weekday notation.
    private static func numberedWeekdays(in normalizedNote: String) -> Set<Int>? {
        let element = #"[1-7](?:\s*[-–—]\s*[1-7])?"#
        let pattern = #"\b(?:v|on)\s+("# + element + #"(?:\s*,\s*"# + element + #")*)(?!\d)"#
        guard let values = captures(pattern: pattern, in: normalizedNote).first?.first else {
            return nil
        }
        var weekdays = Set<Int>()
        let rangeSeparators = CharacterSet(charactersIn: "-–—")
        for element in values.split(separator: ",") {
            let bounds = element.components(separatedBy: rangeSeparators).compactMap { value in
                Int(value.trimmingCharacters(in: .whitespaces))
            }
            switch bounds.count {
            case 1:
                weekdays.insert(bounds[0])
            case 2 where bounds[0] <= bounds[1]:
                weekdays.formUnion(bounds[0]...bounds[1])
            default:
                continue
            }
        }
        return weekdays.isEmpty ? nil : weekdays
    }

    /// Converts Foundation's Sunday-first weekday number to the Monday-first notation printed by IDOS.
    private static func idosWeekday(for date: Date, calendar: Calendar) -> Int {
        let foundationWeekday = calendar.component(.weekday, from: date)
        return (foundationWeekday + 5) % 7 + 1
    }

    /// Treats the Czech `X` timetable symbol as Monday through Friday except Czech public holidays.
    private static func isCzechWorkingDay(_ date: Date, calendar: Calendar) -> Bool {
        let components = calendar.dateComponents([.year, .month, .day, .weekday], from: date)
        guard let year = components.year,
              let month = components.month,
              let day = components.day,
              let weekday = components.weekday,
              (2...6).contains(weekday)
        else {
            return false
        }

        let fixedHolidayCode = month * 100 + day
        guard !fixedCzechHolidayCodes.contains(fixedHolidayCode),
              let easterSunday = easterSunday(in: year, calendar: calendar),
              let goodFriday = calendar.date(byAdding: .day, value: -2, to: easterSunday),
              let easterMonday = calendar.date(byAdding: .day, value: 1, to: easterSunday)
        else {
            return false
        }

        let civilDate = calendar.startOfDay(for: date)
        return civilDate != goodFriday && civilDate != easterMonday
    }

    /// Calculates Easter Sunday so the two movable Czech holidays can be excluded from working days.
    private static func easterSunday(in year: Int, calendar: Calendar) -> Date? {
        guard year >= 1583 else { return nil }
        let a = year % 19
        let b = year / 100
        let c = year % 100
        let d = b / 4
        let e = b % 4
        let f = (b + 8) / 25
        let g = (b - f + 1) / 3
        let h = (19 * a + b - d - g + 15) % 30
        let i = c / 4
        let k = c % 4
        let l = (32 + 2 * e + 2 * i - h - k) % 7
        let m = (a + 11 * h + 22 * l) / 451
        let value = h + l - 7 * m + 114

        return calendar.date(from: DateComponents(
            timeZone: calendar.timeZone,
            year: year,
            month: value / 31,
            day: value % 31 + 1
        )).map(calendar.startOfDay(for:))
    }

    private static func dateInterpretation(
        in note: String,
        validityStart: Date,
        validityEnd: Date
    ) -> DateInterpretation {
        let calendar = serviceCalendar
        let tokens = serviceDateTokens(in: note)
        guard !tokens.isEmpty else { return DateInterpretation(dates: [], ranges: []) }

        if tokens.count == 1,
           let range = validityRelativeRange(before: tokens[0], in: note),
           let boundaryDate = resolvedDates(
               for: tokens[0],
               validityStart: validityStart,
               validityEnd: validityEnd,
               calendar: calendar
           ).first
        {
            switch range {
            case .fromValidityStart:
                return DateInterpretation(
                    dates: dates(from: validityStart, through: boundaryDate, calendar: calendar),
                    ranges: [validityStart...boundaryDate]
                )
            case .throughValidityEnd:
                return DateInterpretation(
                    dates: dates(from: boundaryDate, through: validityEnd, calendar: calendar),
                    ranges: [boundaryDate...validityEnd]
                )
            }
        }

        var dates = Set<Date>()
        var ranges: [ClosedRange<Date>] = []
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
                dates.formUnion(Self.dates(from: start, through: end, calendar: calendar))
                ranges.append(start...end)
                index += 2
            } else {
                dates.formUnion(tokenDates)
                ranges.append(contentsOf: tokenDates.map { $0...$0 })
                index += 1
            }
        }

        return DateInterpretation(dates: dates.sorted(), ranges: ranges)
    }

    /// Recognizes a boundary word immediately before the only concrete date in a service note.
    private static func validityRelativeRange(
        before token: ServiceDateToken,
        in note: String
    ) -> ValidityRelativeRange? {
        let prefix = (note as NSString).substring(
            with: NSRange(location: 0, length: token.range.location)
        )
        .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "cs_CZ"))
        .lowercased()

        if prefix.range(of: #"\b(?:do|until|to)\s*$"#, options: .regularExpression) != nil {
            return .fromValidityStart
        }
        if prefix.range(of: #"\b(?:od|from)\s*$"#, options: .regularExpression) != nil {
            return .throughValidityEnd
        }
        return nil
    }

    /// Expands an inclusive civil-date interval for display as individual operating states.
    private static func dates(from start: Date, through end: Date, calendar: Calendar) -> [Date] {
        guard start <= end else { return [] }
        var dates: [Date] = []
        var date = start
        while date <= end {
            dates.append(date)
            guard let next = calendar.date(byAdding: .day, value: 1, to: date) else { break }
            date = next
        }
        return dates
    }

    private static func serviceDateTokens(in note: String) -> [ServiceDateToken] {
        let monthPattern = #"XII|XI|IX|VIII|VII|VI|IV|V|X|III|II|I|\d{1,2}"#
        let pattern = #"(?i)(\d{1,2})\s*\.\s*("# + monthPattern + #")\s*\.?\s*(\d{4})?"#
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return [] }
        let source = note as NSString

        var tokens = expression.matches(
            in: note,
            range: NSRange(location: 0, length: source.length)
        ).compactMap { match -> ServiceDateToken? in
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

        let abbreviatedRangePattern =
            #"(?i)(\d{1,2})\s*\.\s*(?:až|do|to|-|–|—)\s*\d{1,2}\s*\.\s*("# +
            monthPattern + #")\s*\.?\s*(\d{4})?"#
        if let abbreviatedExpression = try? NSRegularExpression(pattern: abbreviatedRangePattern) {
            let inferredTokens = abbreviatedExpression.matches(
                in: note,
                range: NSRange(location: 0, length: source.length)
            ).compactMap { match -> ServiceDateToken? in
                guard let day = Int(source.substring(with: match.range(at: 1))),
                      let month = monthNumber(source.substring(with: match.range(at: 2))),
                      (1...31).contains(day)
                else {
                    return nil
                }
                let yearRange = match.range(at: 3)
                let year = yearRange.location == NSNotFound ? nil : Int(source.substring(with: yearRange))
                return ServiceDateToken(range: match.range(at: 1), day: day, month: month, year: year)
            }
            tokens.append(contentsOf: inferredTokens)
        }

        // IDOS can omit a shared month from leading dates, for example `18.,19.IX.`.
        let abbreviatedListPattern =
            #"(?i)(\d{1,2})\s*\.(?=\s*,\s*(?:\d{1,2}\s*\.\s*,\s*)*\d{1,2}\s*\.\s*("# +
            monthPattern + #")\s*\.?\s*(\d{4})?)"#
        if let abbreviatedExpression = try? NSRegularExpression(pattern: abbreviatedListPattern) {
            let inferredTokens = abbreviatedExpression.matches(
                in: note,
                range: NSRange(location: 0, length: source.length)
            ).compactMap { match -> ServiceDateToken? in
                guard let day = Int(source.substring(with: match.range(at: 1))),
                      let month = monthNumber(source.substring(with: match.range(at: 2))),
                      (1...31).contains(day)
                else {
                    return nil
                }
                let yearRange = match.range(at: 3)
                let year = yearRange.location == NSNotFound ? nil : Int(source.substring(with: yearRange))
                return ServiceDateToken(range: match.range(at: 1), day: day, month: month, year: year)
            }
            tokens.append(contentsOf: inferredTokens)
        }

        return tokens.sorted { $0.range.location < $1.range.location }
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
        let symbolicRangePattern = #"(?<!\d)[-–—](?!\d)"#
        return connector.range(of: symbolicRangePattern, options: .regularExpression) != nil ||
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

/// Keeps ordinary notes readable while making dated and weekday-scoped conditions interactive.
struct ServiceNotesView: View {
    let notes: [String]
    let timetableValidity: IDOSTimetableValidity?

    init(notes: [String], timetableValidity: IDOSTimetableValidity? = nil) {
        self.notes = notes
        self.timetableValidity = timetableValidity
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(notes.enumerated()), id: \.offset) { _, note in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("•")
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)
                        .frame(width: 8, alignment: .center)
                        .accessibilityHidden(true)

                    if let serviceCalendar = serviceCalendar(for: note) {
                        StationTimetableServiceCalendarButton(serviceCalendar: serviceCalendar)
                    } else {
                        NoteText(note)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }

    private func serviceCalendar(for note: String) -> StationTimetableServiceCalendar? {
        if let timetableValidity {
            return StationTimetableServiceCalendar(
                note: note,
                validityStart: timetableValidity.validFrom,
                validityEnd: timetableValidity.validThrough
            )
        }
        return StationTimetableServiceCalendar(note: note, allNotes: notes)
    }
}

/// Enables the calendar's interpretation details only for an intentional Option-click.
enum ServiceCalendarOpeningOptions {
    static func showsRecognizedConditions(for modifierFlags: NSEvent.ModifierFlags) -> Bool {
        modifierFlags.contains(.option)
    }
}

/// Preserves the IDOS note as the button label and reveals its date interpretation in a popover.
struct StationTimetableServiceCalendarButton: View {
    let serviceCalendar: StationTimetableServiceCalendar
    @State private var isPresented = false
    @State private var showsRecognizedConditions = false

    var body: some View {
        Button {
            showsRecognizedConditions = ServiceCalendarOpeningOptions.showsRecognizedConditions(
                for: NSEvent.modifierFlags
            )
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
            Text(calendarActionLabel) + Text(": ") + Text(serviceCalendar.note)
        )
        .help(calendarHelp)
        .popover(isPresented: $isPresented, arrowEdge: .trailing) {
            StationTimetableServiceCalendarView(
                serviceCalendar: serviceCalendar,
                showsRecognizedConditions: showsRecognizedConditions
            )
        }
    }

    private var calendarActionLabel: String {
        AppLocalization.string(
            serviceCalendar.rule.subject == .noteApplicability
                ? "Show note calendar"
                : "Show service calendar"
        )
    }

    private var calendarHelp: String {
        AppLocalization.string(
            serviceCalendar.rule.subject == .noteApplicability
                ? "Show note calendar; hold Option for recognized conditions"
                : "Show service calendar; hold Option for recognized conditions"
        )
    }
}

/// Shows every month touched by the current timetable and distinguishes matching, non-matching, and invalid days.
private struct StationTimetableServiceCalendarView: View {
    let serviceCalendar: StationTimetableServiceCalendar
    let showsRecognizedConditions: Bool

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(calendarTitle)
                .font(.headline)
            Text(serviceCalendar.note)
                .font(.subheadline)
            Text(validityDescription)
                .font(.caption)
                .foregroundStyle(.secondary)

            if showsRecognizedConditions {
                recognizedConditionsView
            }

            Divider()

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 20) {
                        ForEach(monthStarts, id: \.self) { month in
                            monthView(month)
                                .id(month)
                        }
                    }
                }
                .frame(maxHeight: 460)
                .onAppear {
                    proxy.scrollTo(serviceCalendar.initialVisibleMonth(on: Date()), anchor: .top)
                }
            }

            Divider()
            legend
        }
        .padding(18)
        .frame(width: 360)
    }

    private var recognizedConditionsView: some View {
        GroupBox("Recognized conditions") {
            VStack(alignment: .leading, spacing: 7) {
                Label(recognizedRuleDescription, systemImage: "checkmark.circle")
                if serviceCalendar.rule.hasExplicitOperatingRange {
                    Label(
                        recognizedRangeDescription(serviceCalendar.rule.operatingRange),
                        systemImage: "calendar"
                    )
                }
                ForEach(
                    Array(serviceCalendar.rule.additionalRunningRanges.enumerated()),
                    id: \.offset
                ) { _, range in
                    let description = recognizedRangeDescription(range)
                    if serviceCalendar.rule.recurrence == .none {
                        Label(description, systemImage: "calendar")
                    } else {
                        Label(
                            AppLocalization.string("Additionally runs %@", description),
                            systemImage: "plus.circle"
                        )
                    }
                }
                ForEach(Array(serviceCalendar.rule.nonRunningRanges.enumerated()), id: \.offset) { _, range in
                    Label(
                        AppLocalization.string("Does not run %@", recognizedRangeDescription(range)),
                        systemImage: "minus.circle"
                    )
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.caption)
        .textSelection(.enabled)
    }

    private var recognizedRuleDescription: String {
        if serviceCalendar.rule.subject == .noteApplicability,
           case let .selectedWeekdays(weekdays) = serviceCalendar.rule.recurrence
        {
            let values = weekdays.sorted().map(String.init).joined(separator: ", ")
            return AppLocalization.string(
                "Applies on days %@ throughout timetable validity",
                values
            )
        }

        switch serviceCalendar.rule.recurrence {
        case .none:
            return AppLocalization.string("Runs only on the listed dates")
        case .everyDay where serviceCalendar.rule.hasExplicitOperatingRange:
            return AppLocalization.string("Runs every day within the listed date range")
        case .everyDay:
            return AppLocalization.string("Runs throughout timetable validity except the listed dates")
        case .workingDays:
            return AppLocalization.string("Runs on working days except the listed dates")
        case let .selectedWeekdays(weekdays):
            let values = weekdays.sorted().map(String.init).joined(separator: ", ")
            return AppLocalization.string("Runs on days %@ within the listed date range", values)
        }
    }

    private var calendarTitle: String {
        AppLocalization.string(
            serviceCalendar.rule.subject == .noteApplicability
                ? "Note calendar"
                : "Service calendar"
        )
    }

    private func recognizedRangeDescription(_ range: ClosedRange<Date>) -> String {
        let start = dateFormatter.string(from: range.lowerBound)
        guard range.lowerBound != range.upperBound else { return start }
        return "\(start) – \(dateFormatter.string(from: range.upperBound))"
    }

    private var legend: some View {
        HStack(spacing: 14) {
            if serviceCalendar.rule.subject == .noteApplicability {
                legendItem("Applies", color: .green)
                legendItem("Does not apply", color: .red)
            } else {
                legendItem("Runs", color: .green)
                legendItem("Does not run", color: .red)
            }
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
            return serviceCalendar.rule.subject == .noteApplicability ? "Applies" : "Runs"
        case .doesNotRun:
            return serviceCalendar.rule.subject == .noteApplicability ? "Does not apply" : "Does not run"
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
