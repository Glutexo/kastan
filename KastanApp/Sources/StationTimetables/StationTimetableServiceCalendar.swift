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

        /// Keeps a dated exclusion either unconditional or limited to IDOS's Monday-first weekdays.
        enum NonRunningCondition: Equatable {
            case dates(ClosedRange<Date>)
            case selectedWeekdays(Set<Int>, within: ClosedRange<Date>)

            var range: ClosedRange<Date> {
                switch self {
                case let .dates(range), let .selectedWeekdays(_, within: range):
                    return range
                }
            }
        }

        let subject: Subject
        let recurrence: Recurrence
        let operatingRange: ClosedRange<Date>
        let hasExplicitOperatingRange: Bool
        let additionalRunningRanges: [ClosedRange<Date>]
        let nonRunningConditions: [NonRunningCondition]
        let noteApplicabilityRange: NSRange?

        /// Exposes unconditional exclusions separately for concise calendar diagnostics and tests.
        var nonRunningRanges: [ClosedRange<Date>] {
            nonRunningConditions.compactMap { condition in
                guard case let .dates(range) = condition else { return nil }
                return range
            }
        }
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

        if rule.nonRunningConditions.contains(where: { condition in
            switch condition {
            case let .dates(range):
                return range.contains(day)
            case let .selectedWeekdays(weekdays, within: range):
                return range.contains(day) && weekdays.contains(Self.idosWeekday(for: day, calendar: calendar))
            }
        }) {
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

    /// Keeps the parsed weekdays together with the exact source text that should open a note calendar.
    private struct NumberedWeekdayCondition {
        let weekdays: Set<Int>
        let sourceRange: NSRange
    }

    /// Retains an interpreted date range's source position so a following weekday clause can scope it.
    private struct InterpretedDateRange {
        let range: ClosedRange<Date>
        let sourceRange: NSRange
    }

    /// Keeps both effective dates and the individual dates or ranges recognized in the IDOS note.
    private struct DateInterpretation {
        let dates: [Date]
        let datedRanges: [InterpretedDateRange]

        var ranges: [ClosedRange<Date>] {
            datedRanges.map(\.range)
        }
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
        let standaloneWeekdayCondition = numberedWeekdayCondition(in: note)
        guard hasPositiveRule || hasNegativeRule || standaloneWeekdayCondition != nil else { return nil }

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
        let positiveWeekdayCondition = numberedWeekdayCondition(in: positiveNote)
        let recurrence: Rule.Recurrence
        if positiveNormalized.range(of: workingDayPattern, options: .regularExpression) != nil {
            recurrence = .workingDays
        } else if let condition = positiveWeekdayCondition {
            recurrence = .selectedWeekdays(condition.weekdays)
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
        let nonRunningConditions = negativeNote.map { note in
            makeNonRunningConditions(
                from: dateInterpretation(
                    in: note,
                    validityStart: validityStart,
                    validityEnd: validityEnd
                ),
                weekdayConditions: numberedWeekdayConditions(in: note)
            )
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
        guard hasRecurringCondition || !additionalRunningRanges.isEmpty || !nonRunningConditions.isEmpty else {
            return nil
        }

        let rule = Rule(
            subject: hasPositiveRule || hasNegativeRule ? .serviceOperation : .noteApplicability,
            recurrence: recurrence,
            operatingRange: operatingRange,
            hasExplicitOperatingRange: hasExplicitOperatingRange,
            additionalRunningRanges: additionalRunningRanges,
            nonRunningConditions: nonRunningConditions,
            noteApplicabilityRange: hasPositiveRule || hasNegativeRule
                ? nil
                : standaloneWeekdayCondition?.sourceRange
        )
        var recognizedDateRanges = additionalRunningRanges + nonRunningConditions.map(\.range)
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

    /// Reads individual numbers and ranges in IDOS's Monday-first weekday notation and preserves their source range.
    private static func numberedWeekdayCondition(in note: String) -> NumberedWeekdayCondition? {
        numberedWeekdayConditions(in: note).first
    }

    /// Finds every weekday clause without consuming the leading number of a following date such as `30.VII.`.
    private static func numberedWeekdayConditions(in note: String) -> [NumberedWeekdayCondition] {
        let weekday = #"[1-7](?!\d|\s*\.)"#
        let element = weekday + #"(?:\s*[-–—]\s*"# + weekday + #")?"#
        let pattern = #"\b(?:v|on)\s+("# + element + #"(?:\s*,\s*"# + element + #")*)"#
        guard let expression = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
            return []
        }
        let source = note as NSString
        return expression.matches(
            in: note,
            range: NSRange(location: 0, length: source.length)
        ).compactMap { match in
            guard match.numberOfRanges >= 2 else { return nil }
            let values = source.substring(with: match.range(at: 1))
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
            guard !weekdays.isEmpty else { return nil }
            return NumberedWeekdayCondition(weekdays: weekdays, sourceRange: match.range)
        }
    }

    /// Applies each weekday clause to the closest dated range before it while preserving all other exclusions.
    private static func makeNonRunningConditions(
        from interpretation: DateInterpretation,
        weekdayConditions: [NumberedWeekdayCondition]
    ) -> [Rule.NonRunningCondition] {
        var weekdaysByRangeIndex: [Int: Set<Int>] = [:]
        for condition in weekdayConditions {
            guard let rangeIndex = interpretation.datedRanges.indices.last(where: {
                NSMaxRange(interpretation.datedRanges[$0].sourceRange) <= condition.sourceRange.location
            }) else { continue }
            weekdaysByRangeIndex[rangeIndex] = condition.weekdays
        }

        return interpretation.datedRanges.enumerated().map { index, datedRange in
            if let weekdays = weekdaysByRangeIndex[index] {
                return .selectedWeekdays(weekdays, within: datedRange.range)
            }
            return .dates(datedRange.range)
        }
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
        guard !tokens.isEmpty else { return DateInterpretation(dates: [], datedRanges: []) }

        var dates = Set<Date>()
        var datedRanges: [InterpretedDateRange] = []
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
                let endToken = tokens[index + 1]
                datedRanges.append(InterpretedDateRange(
                    range: start...end,
                    sourceRange: NSRange(
                        location: token.range.location,
                        length: NSMaxRange(endToken.range) - token.range.location
                    )
                ))
                index += 2
            } else if let relativeRange = validityRelativeRange(before: token, in: note),
                      let boundaryDate = tokenDates.first
            {
                let range = switch relativeRange {
                case .fromValidityStart:
                    validityStart...boundaryDate
                case .throughValidityEnd:
                    boundaryDate...validityEnd
                }
                dates.formUnion(Self.dates(
                    from: range.lowerBound,
                    through: range.upperBound,
                    calendar: calendar
                ))
                datedRanges.append(InterpretedDateRange(
                    range: range,
                    sourceRange: token.range
                ))
                index += 1
            } else {
                dates.formUnion(tokenDates)
                datedRanges.append(contentsOf: tokenDates.map {
                    InterpretedDateRange(range: $0...$0, sourceRange: token.range)
                })
                index += 1
            }
        }

        return DateInterpretation(dates: dates.sorted(), datedRanges: datedRanges)
    }

    /// Recognizes a boundary word immediately before a date not already paired into a closed range.
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

/// Keeps all notes in one selectable text flow while making dated and weekday-scoped conditions interactive.
struct ServiceNotesView: View {
    let notes: [String]
    let timetableValidity: IDOSTimetableValidity?
    @State private var presentedServiceCalendar: StationTimetableServiceCalendar?
    @State private var showsRecognizedConditions = false

    /// Keeps neighboring service-information rows visually distinct in the shared selectable text flow.
    static let informationLineSpacing: CGFloat = 8

    init(notes: [String], timetableValidity: IDOSTimetableValidity? = nil) {
        self.notes = notes
        self.timetableValidity = timetableValidity
    }

    var body: some View {
        Text(linkedContent)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .lineSpacing(Self.informationLineSpacing)
            .environment(\.openURL, OpenURLAction { url in
                openCalendarLink(url)
            })
            .popover(isPresented: calendarIsPresented, arrowEdge: .trailing) {
                if let presentedServiceCalendar {
                    StationTimetableServiceCalendarView(
                        serviceCalendar: presentedServiceCalendar,
                        showsRecognizedConditions: showsRecognizedConditions
                    )
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
    }

    /// Joins every visible row into one attributed value so a drag selection can cross line boundaries.
    var linkedContent: AttributedString {
        notes.enumerated().reduce(into: AttributedString()) { content, item in
            let (index, note) = item
            let serviceCalendar = serviceCalendar(for: note)
            content += AttributedString(
                "\(ServiceNoteEmoji.symbol(for: note, presentsCalendar: serviceCalendar != nil)) "
            )
            if let serviceCalendar {
                content += ServiceCalendarLink.content(
                    for: serviceCalendar,
                    destination: Self.calendarDestination(for: index)
                )
            } else {
                content += NoteText.linkedContent(note)
            }
            if index < notes.index(before: notes.endIndex) {
                content += AttributedString("\n")
            }
        }
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

    static func calendarDestination(for noteIndex: Int) -> URL {
        URL(string: "kastan-note-calendar://note/\(noteIndex)")!
    }

    private func openCalendarLink(_ url: URL) -> OpenURLAction.Result {
        guard url.scheme == "kastan-note-calendar",
              url.host == "note",
              let noteIndex = Int(url.lastPathComponent),
              notes.indices.contains(noteIndex),
              let serviceCalendar = serviceCalendar(for: notes[noteIndex])
        else { return .systemAction }

        showsRecognizedConditions = ServiceCalendarOpeningOptions.showsRecognizedConditions(
            for: NSEvent.modifierFlags
        )
        presentedServiceCalendar = serviceCalendar
        return .handled
    }

    private var calendarIsPresented: Binding<Bool> {
        Binding(
            get: { presentedServiceCalendar != nil },
            set: { isPresented in
                if !isPresented {
                    presentedServiceCalendar = nil
                }
            }
        )
    }
}

/// Assigns a concise visual meaning to every IDOS service note without replacing its readable text.
enum ServiceNoteEmoji {
    static func symbol(for note: String, presentsCalendar: Bool = false) -> String {
        let normalized = note
            .folding(
                options: [.diacriticInsensitive, .caseInsensitive],
                locale: Locale(identifier: "en_US_POSIX")
            )
            .lowercased()

        if normalized.contains("nahradni autobusova doprava") ||
            normalized.contains("replacement bus") ||
            normalized.contains("bus replacement")
        {
            return "🚌"
        }
        // Keep carrier legal forms from overriding information whose subject is the applicable fare.
        if (normalized.contains("tarif") &&
            (normalized.contains("prepravni podmink") ||
                normalized.contains("plati tarif") ||
                normalized.contains("tarif vyhlasen"))) ||
            ((normalized.contains("fare") || normalized.contains("tariff")) &&
                (normalized.contains("conditions of carriage") ||
                    normalized.contains("transport conditions") ||
                    normalized.contains("fare announced") ||
                    normalized.contains("tariff announced")))
        {
            return "🎫"
        }
        if normalized.contains("plati take jizdni doklady") ||
            (normalized.contains("integrated transport") &&
                normalized.range(of: #"\btickets?\b"#, options: .regularExpression) != nil)
        {
            return "🎟️"
        }
        if (normalized.contains("jizdenk") &&
            (normalized.contains("zakoup") || normalized.contains("predem"))) ||
            (normalized.range(of: #"\btickets?\b"#, options: .regularExpression) != nil &&
                (normalized.contains("purchase") ||
                    normalized.contains("bought in advance") ||
                    normalized.contains("pre-purchased")))
        {
            return "🎫"
        }
        if normalized.contains("stornopodmink") ||
            normalized.contains("cancellation conditions") ||
            normalized.contains("cancellation policy")
        {
            return "↩️"
        }
        if (normalized.contains("telefonick") && normalized.contains("rezervac")) ||
            normalized.contains("telephone reservation") ||
            normalized.contains("phone reservation")
        {
            return "📵"
        }
        if normalized.contains("vnitrostatni preprava") ||
            normalized.contains("domestic transport") ||
            normalized.contains("domestic carriage")
        {
            return "✅"
        }
        if (normalized.contains("neprepravuji") ||
            normalized.contains("not carried") ||
            normalized.contains("not transported")) &&
            (normalized.contains("zavazadl") ||
                normalized.contains("kocark") ||
                normalized.contains("zvirat") ||
                normalized.contains("baggage") ||
                normalized.contains("luggage") ||
                normalized.contains("stroller") ||
                normalized.contains("animal"))
        {
            return "🚫"
        }
        if normalized.contains("zavazadl") ||
            normalized.contains("baggage") ||
            normalized.contains("luggage")
        {
            return "🧳"
        }
        if normalized.contains("osoby opile") ||
            normalized.contains("podnapile") ||
            normalized.contains("autosedack") ||
            normalized.contains("intoxicated passenger") ||
            normalized.contains("car seat")
        {
            return "⚠️"
        }
        // Keep Deluxe sleeping compartments visually distinct from the general sleeping-car category.
        if (normalized.contains("oddil") && normalized.contains("deluxe")) ||
            (normalized.contains("deluxe") && normalized.contains("shower"))
        {
            return "🚿"
        }
        if (normalized.contains("luzkov") && normalized.contains("vuz")) ||
            normalized.contains("sleeping car") ||
            normalized.contains("sleeping coach") ||
            normalized.contains("sleeper car")
        {
            return "🛏️"
        }
        if (normalized.contains("lehatkov") && normalized.contains("vuz")) ||
            normalized.contains("couchette car") ||
            normalized.contains("couchette coach")
        {
            return "🛌"
        }
        if normalized.contains("primy vuz") ||
            normalized.contains("through coach") ||
            normalized.contains("through car")
        {
            return "🚃"
        }
        if (normalized.contains("k sezeni pouze") && normalized.contains("2. vozove tridy")) ||
            (normalized.contains("seating") &&
                (normalized.contains("2nd class only") || normalized.contains("second class only")))
        {
            return "2️⃣"
        }
        if normalized.contains("restauracni vuz") ||
            normalized.contains("bistrovuz") ||
            normalized.contains("restaurant car") ||
            normalized.contains("dining car") ||
            normalized.contains("bistro car")
        {
            return "🍽️"
        }
        if normalized.contains("obcerstveni") ||
            normalized.contains("refreshment") ||
            normalized.contains("snack service")
        {
            return "🥤"
        }
        if (normalized.contains("veskere informace") ||
            normalized.contains("all information")) &&
            (normalized.contains("www.") || normalized.contains("http"))
        {
            return "🌐"
        }
        if normalized.contains("palubni portal") ||
            normalized.contains("onboard portal") ||
            normalized.contains("on-board portal")
        {
            return "🌐"
        }
        if normalized.contains("wi-fi") ||
            normalized.contains("wifi") ||
            normalized.contains("wireless internet") ||
            (normalized.contains("bezdratov") && normalized.contains("internet"))
        {
            return "🛜"
        }
        if normalized.contains("230 v") ||
            normalized.contains("power socket") ||
            normalized.contains("power outlet") ||
            normalized.contains("electrical socket")
        {
            return "🔌"
        }
        if normalized.contains("tichy oddil") ||
            normalized.contains("quiet compartment") ||
            normalized.contains("quiet coach")
        {
            return "🤫"
        }
        if normalized.contains("detske kino") ||
            normalized.contains("children's cinema") ||
            normalized.contains("children cinema") ||
            normalized.contains("kids cinema")
        {
            return "📽️"
        }
        if normalized.contains("cestujici s detmi") ||
            normalized.contains("passengers with children") ||
            normalized.contains("family compartment") ||
            normalized.contains("family coach")
        {
            return "👶🏻"
        }
        if (normalized.contains("damsk") && normalized.contains("oddil")) ||
            (normalized.contains("samostatne cestujici") && normalized.contains("zen")) ||
            (normalized.contains("women") &&
                (normalized.contains("compartment") ||
                    normalized.contains("coach") ||
                    normalized.contains("travelling alone") ||
                    normalized.contains("traveling alone"))) ||
            (normalized.contains("ladies") &&
                (normalized.contains("compartment") || normalized.contains("coach")))
        {
            return "👩🏻"
        }
        // Keep place names such as Kolín from turning unrelated fare notes into bicycle services.
        let mentionsBicycle = normalized.range(
            of: #"\bjizdn\p{L}*\s+kol\p{L}*\b"#,
            options: .regularExpression
        ) != nil ||
            normalized.contains("bicycle") || normalized.contains("bike")
        if mentionsBicycle && (
            normalized.contains("vyloucen") ||
                normalized.contains("excluded") ||
                normalized.contains("not permitted") ||
                normalized.contains("not allowed") ||
                normalized.contains("prohibited")
        ) {
            return "🚳"
        }
        if mentionsBicycle {
            return "🚲"
        }
        if normalized.contains("cestujicich na voziku") || normalized.contains("wheelchair") {
            return "♿"
        }
        if normalized.contains("mistenk") ||
            normalized.contains("seat reservation") ||
            normalized.contains("place reservation") ||
            normalized.contains("places reservation") ||
            (normalized.contains("rezervac") && normalized.contains("mist"))
        {
            return "💺"
        }
        if (normalized.contains("neceka") && normalized.contains("pripoj")) ||
            (normalized.contains("zmeskan") &&
                normalized.contains("navazn") &&
                normalized.contains("spoj")) ||
            normalized.contains("does not wait for connection") ||
            normalized.contains("doesn't wait for connection") ||
            normalized.contains("will not wait for connection") ||
            normalized.contains("missed connection")
        {
            return "⏱️"
        }
        if normalized.contains("komercni riziko") ||
            normalized.contains("nabidkoveho rizeni") ||
            normalized.contains("commercial risk") ||
            normalized.contains("competitive tender")
        {
            return "💼"
        }
        if normalized.contains("pohranicni prechodovy bod") ||
            normalized.contains("border crossing") ||
            normalized.contains("border point")
        {
            return "🛂"
        }
        if normalized.contains("traffic restriction") ||
            normalized.contains("planned restriction") ||
            normalized.contains("planovane omezeni") ||
            normalized.contains("omezeni provozu") ||
            normalized.contains("vyluk")
        {
            return "🚧"
        }
        if presentsCalendar {
            return "📅"
        }
        if hasCarrierContactShape(normalized) {
            return "🏢"
        }
        if normalized.hasPrefix("linka ") ||
            normalized.hasPrefix("line ") ||
            hasRouteShape(note)
        {
            return "🛤️"
        }
        if normalized.contains("carrier:") ||
            normalized.contains("dopravce:") ||
            normalized.contains("a.s.") ||
            normalized.contains("a. s.") ||
            normalized.contains("s.r.o.") ||
            normalized.contains("s. r. o.") ||
            normalized.contains("k.s.") ||
            normalized.contains("k. s.") ||
            normalized.hasSuffix(" gmbh") ||
            normalized.hasSuffix(" ltd") ||
            normalized.hasSuffix(" ltd.")
        {
            return "🏢"
        }

        return "ℹ️"
    }

    /// Recognizes the IDOS carrier contact layout without maintaining a list of operator names.
    private static func hasCarrierContactShape(_ note: String) -> Bool {
        let fields = note
            .split(separator: ";", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard fields.count == 2 || fields.count == 3 else {
            return false
        }

        let name = fields[0]
        let address = fields[1]
        guard name.contains(where: \.isLetter), address.contains(where: \.isLetter) else {
            return false
        }

        if fields.count == 2 {
            return address.contains(where: \.isNumber)
        }

        return fields[2].filter(\.isNumber).count >= 6
    }

    /// Recognizes an IDOS itinerary without treating date ranges or one hyphenated name as a route.
    private static func hasRouteShape(_ note: String) -> Bool {
        note.range(
            of: #"\p{L}\s+[-–—]\s+\p{L}"#,
            options: .regularExpression
        ) != nil || note.range(
            of: #"^\p{Lu}[\p{L}\p{M}]{1,}\s*[-–—]\s*\p{Lu}[\p{L}\p{M}]{1,}$"#,
            options: .regularExpression
        ) != nil || note.range(
            of: #"\p{L}[-–—]\p{L}.*\p{L}[-–—]\p{L}"#,
            options: .regularExpression
        ) != nil
    }
}

/// Enables the calendar's interpretation details only for an intentional Option-click.
enum ServiceCalendarOpeningOptions {
    static func showsRecognizedConditions(for modifierFlags: NSEvent.ModifierFlags) -> Bool {
        modifierFlags.contains(.option)
    }
}

/// Links a complete operating rule or only the applicability clause inside the shared selectable text.
enum ServiceCalendarLink {
    static func content(
        for serviceCalendar: StationTimetableServiceCalendar,
        destination: URL
    ) -> AttributedString {
        guard serviceCalendar.rule.subject == .noteApplicability else {
            var result = AttributedString(serviceCalendar.note)
            result.link = destination
            return result
        }
        return noteApplicabilityContent(for: serviceCalendar, destination: destination)
    }

    /// Preserves the prose styling and links only the exact numbered-weekday clause recognized by the parser.
    static func noteApplicabilityContent(
        for serviceCalendar: StationTimetableServiceCalendar,
        destination: URL
    ) -> AttributedString {
        let note = serviceCalendar.note
        guard let sourceRange = serviceCalendar.rule.noteApplicabilityRange,
              let conditionRange = Range(sourceRange, in: note)
        else { return AttributedString(note) }

        var result = AttributedString(note[..<conditionRange.lowerBound])
        var linkedCondition = AttributedString(note[conditionRange])
        linkedCondition.link = destination
        result += linkedCondition
        result += AttributedString(note[conditionRange.upperBound...])
        return result
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
                ForEach(
                    Array(serviceCalendar.rule.nonRunningConditions.enumerated()),
                    id: \.offset
                ) { _, condition in
                    switch condition {
                    case let .dates(range):
                        Label(
                            AppLocalization.string("Does not run %@", recognizedRangeDescription(range)),
                            systemImage: "minus.circle"
                        )
                    case let .selectedWeekdays(weekdays, within: range):
                        Label(
                            AppLocalization.string(
                                "Does not run on days %@ within %@",
                                weekdays.sorted().map(String.init).joined(separator: ", "),
                                recognizedRangeDescription(range)
                            ),
                            systemImage: "minus.circle"
                        )
                    }
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
