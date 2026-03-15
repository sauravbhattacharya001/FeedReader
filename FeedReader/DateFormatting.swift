import Foundation

/// Shared date formatters to avoid repeated allocations.
///
/// `DateFormatter` initialisation is expensive (~4× slower than a `String`
/// allocation).  Re-using static instances across the app eliminates
/// redundant work and keeps formatting consistent.
///
/// Usage:
///     let key = DateFormatting.isoDate.string(from: date)
///     let label = DateFormatting.mediumDateTime.string(from: date)
enum DateFormatting {

    // MARK: - Date-only

    /// "2026-03-09"
    static let isoDate: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    /// "Mar 9, 2026" — medium date, no time
    static let mediumDate: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f
    }()

    /// "March 9, 2026"
    static let longDate: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMMM d, yyyy"
        return f
    }()

    // MARK: - Date + Time

    /// "Mar 9, 2026, 2:05 PM" — medium date, short time
    static let mediumDateTime: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    // MARK: - Time-only

    /// "2:05 PM" — short time, no date
    static let shortTime: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .none
        f.timeStyle = .short
        return f
    }()

    // MARK: - Period keys

    /// "2026-03" (year-month key)
    static let yearMonth: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    /// "2026-W10" (ISO week key)
    ///
    /// Uses the ISO 8601 calendar so that week numbers match the ISO
    /// standard (weeks start on Monday, week 1 contains the first
    /// Thursday of the year). Without this, locales where the week
    /// starts on Sunday (e.g. en_US) produce different week numbers.
    static let yearWeek: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .iso8601)
        f.dateFormat = "YYYY-'W'ww"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    /// "Mar 2026" (month label)
    static let monthYear: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM yyyy"
        return f
    }()

    // MARK: - Day-of-week

    /// "Mon" (abbreviated weekday)
    static let shortWeekday: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEE"
        return f
    }()

    /// "Monday" (full weekday)
    static let fullWeekday: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEEE"
        return f
    }()

    // MARK: - Misc

    /// "Mar 9" (short month + day)
    static let monthDay: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f
    }()

    /// "Mar 9, 2026" (dateFormat-based variant)
    static let monthDayYear: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d, yyyy"
        return f
    }()

    /// "2026" (year only)
    static let yearOnly: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    /// RFC 2822: "Mon, 09 Mar 2026 14:05:00 -0700"
    static let rfc2822: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()
}
