//
//  ArticleTimeCapsule.swift
//  FeedReader
//
//  Time Capsule for articles — "bury" articles now and have them
//  resurface at a future date you choose. Great for:
//  - Predictions: save an article, revisit it in 6 months to see
//    if the prediction came true
//  - Slow reads: park dense articles for a quieter week
//  - Nostalgia: bury a favorite and relive it next year
//  - Learning: schedule revisits for spaced understanding
//
//  Each capsule has a message ("why I'm burying this"), an open date,
//  and optional tags. Capsules can be in sealed, ready, or opened state.
//
//  Persistence: JSON file in Documents directory.
//  Fully offline — no network, no dependencies beyond Foundation.
//

import Foundation

// MARK: - Notifications

extension Notification.Name {
    /// Posted when capsules are created, opened, or deleted.
    static let timeCapsuleDidChange = Notification.Name("TimeCapsuleDidChangeNotification")
    /// Posted when capsules become ready to open.
    static let timeCapsuleReady = Notification.Name("TimeCapsuleReadyNotification")
}

// MARK: - CapsuleState

/// Lifecycle state of a time capsule.
enum CapsuleState: String, Codable, CaseIterable {
    case sealed   // Buried, not yet ready
    case ready    // Open date has arrived
    case opened   // User has opened it

    var emoji: String {
        switch self {
        case .sealed: return "🔒"
        case .ready:  return "📬"
        case .opened: return "📭"
        }
    }

    var label: String {
        switch self {
        case .sealed: return "Sealed"
        case .ready:  return "Ready to Open"
        case .opened: return "Opened"
        }
    }
}

// MARK: - TimeCapsulePreset

/// Quick-pick durations for burying articles.
enum TimeCapsulePreset: String, CaseIterable {
    case oneWeek     = "1 Week"
    case oneMonth    = "1 Month"
    case threeMonths = "3 Months"
    case sixMonths   = "6 Months"
    case oneYear     = "1 Year"
    case twoYears    = "2 Years"
    case fiveYears   = "5 Years"

    /// Returns the open date relative to the given bury date.
    func openDate(from buryDate: Date, calendar: Calendar = .current) -> Date {
        switch self {
        case .oneWeek:     return calendar.date(byAdding: .day, value: 7, to: buryDate)!
        case .oneMonth:    return calendar.date(byAdding: .month, value: 1, to: buryDate)!
        case .threeMonths: return calendar.date(byAdding: .month, value: 3, to: buryDate)!
        case .sixMonths:   return calendar.date(byAdding: .month, value: 6, to: buryDate)!
        case .oneYear:     return calendar.date(byAdding: .year, value: 1, to: buryDate)!
        case .twoYears:    return calendar.date(byAdding: .year, value: 2, to: buryDate)!
        case .fiveYears:   return calendar.date(byAdding: .year, value: 5, to: buryDate)!
        }
    }
}

// MARK: - TimeCapsuleItem

/// A single buried article with metadata.
struct TimeCapsuleItem: Codable, Identifiable {
    /// Unique capsule ID.
    let id: String
    /// Article URL.
    let articleLink: String
    /// Article title at burial time.
    let articleTitle: String
    /// Feed/source name.
    let feedName: String
    /// When the capsule was created.
    let buriedDate: Date
    /// When the capsule can be opened.
    let openDate: Date
    /// User's message to their future self.
    let message: String
    /// Optional tags for organization.
    var tags: [String]
    /// Current state.
    var state: CapsuleState
    /// When it was actually opened (nil if sealed/ready).
    var openedDate: Date?
    /// User's reflection after opening (optional).
    var reflection: String?

    /// Days until the capsule can be opened (negative = overdue).
    var daysUntilOpen: Int {
        Calendar.current.dateComponents([.day], from: Date(), to: openDate).day ?? 0
    }

    /// Total duration from burial to open date in days.
    var totalDurationDays: Int {
        Calendar.current.dateComponents([.day], from: buriedDate, to: openDate).day ?? 0
    }

    /// Progress toward opening (0.0 to 1.0, can exceed 1.0 if overdue).
    var progress: Double {
        guard totalDurationDays > 0 else { return 1.0 }
        let elapsed = Calendar.current.dateComponents([.day], from: buriedDate, to: Date()).day ?? 0
        return Double(elapsed) / Double(totalDurationDays)
    }

    /// Whether the open date has passed.
    var isReady: Bool {
        Date() >= openDate
    }
}

// MARK: - CapsuleStats

/// Aggregate statistics about the user's time capsule collection.
struct CapsuleStats {
    let totalCapsules: Int
    let sealedCount: Int
    let readyCount: Int
    let openedCount: Int
    let oldestBurialDate: Date?
    let nearestOpenDate: Date?
    let averageDurationDays: Double
    let topTags: [(tag: String, count: Int)]
    let reflectionRate: Double  // % of opened capsules with reflections

    var summary: String {
        var lines: [String] = []
        lines.append("📦 Time Capsule Stats")
        lines.append("  Total: \(totalCapsules)")
        lines.append("  🔒 Sealed: \(sealedCount)")
        lines.append("  📬 Ready: \(readyCount)")
        lines.append("  📭 Opened: \(openedCount)")
        if averageDurationDays > 0 {
            lines.append("  ⏱ Avg duration: \(Int(averageDurationDays)) days")
        }
        if openedCount > 0 {
            lines.append("  📝 Reflection rate: \(Int(reflectionRate * 100))%")
        }
        if !topTags.isEmpty {
            let tagStr = topTags.prefix(5).map { "\($0.tag) (\($0.count))" }.joined(separator: ", ")
            lines.append("  🏷 Top tags: \(tagStr)")
        }
        if let nearest = nearestOpenDate {
            let days = Calendar.current.dateComponents([.day], from: Date(), to: nearest).day ?? 0
            if days > 0 {
                lines.append("  ⏳ Next capsule opens in \(days) day\(days == 1 ? "" : "s")")
            } else {
                lines.append("  📬 You have capsule(s) ready to open!")
            }
        }
        return lines.joined(separator: "\n")
    }
}

// MARK: - ArticleTimeCapsule

/// Manages time capsule creation, storage, and retrieval.
class ArticleTimeCapsule {

    // MARK: - Properties

    /// Maximum capsules a user can have sealed at once.
    var maxSealedCapsules: Int = 100

    /// Auto-check for ready capsules and post notifications.
    var autoCheckEnabled: Bool = true

    private var capsules: [TimeCapsuleItem] = []
    private let fileURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    // MARK: - Init

    init(directory: URL? = nil) {
        let dir = directory ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        self.fileURL = dir.appendingPathComponent("time_capsules.json")

        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        load()
        refreshStates()
    }

    // MARK: - Burying

    /// Bury an article in a time capsule.
    @discardableResult
    func bury(
        articleLink: String,
        articleTitle: String,
        feedName: String,
        message: String,
        openDate: Date,
        tags: [String] = []
    ) -> TimeCapsuleItem? {
        let sealedCount = capsules.filter { $0.state == .sealed }.count
        guard sealedCount < maxSealedCapsules else { return nil }
        guard openDate > Date() else { return nil }

        let item = TimeCapsuleItem(
            id: UUID().uuidString,
            articleLink: articleLink,
            articleTitle: articleTitle,
            feedName: feedName,
            buriedDate: Date(),
            openDate: openDate,
            message: message,
            tags: tags.map { $0.lowercased().trimmingCharacters(in: .whitespaces) },
            state: .sealed,
            openedDate: nil,
            reflection: nil
        )

        capsules.append(item)
        save()
        NotificationCenter.default.post(name: .timeCapsuleDidChange, object: self)
        return item
    }

    /// Bury using a preset duration.
    @discardableResult
    func bury(
        articleLink: String,
        articleTitle: String,
        feedName: String,
        message: String,
        preset: TimeCapsulePreset,
        tags: [String] = []
    ) -> TimeCapsuleItem? {
        let date = preset.openDate(from: Date())
        return bury(
            articleLink: articleLink,
            articleTitle: articleTitle,
            feedName: feedName,
            message: message,
            openDate: date,
            tags: tags
        )
    }

    // MARK: - Opening

    /// Open a capsule that is ready. Returns the opened item or nil.
    @discardableResult
    func open(capsuleId: String) -> TimeCapsuleItem? {
        guard let idx = capsules.firstIndex(where: { $0.id == capsuleId }) else { return nil }
        guard capsules[idx].state == .ready || capsules[idx].isReady else { return nil }

        capsules[idx].state = .opened
        capsules[idx].openedDate = Date()
        save()
        NotificationCenter.default.post(name: .timeCapsuleDidChange, object: self)
        return capsules[idx]
    }

    /// Add a reflection to an opened capsule.
    func addReflection(capsuleId: String, reflection: String) -> Bool {
        guard let idx = capsules.firstIndex(where: { $0.id == capsuleId }) else { return false }
        guard capsules[idx].state == .opened else { return false }

        capsules[idx].reflection = reflection
        save()
        NotificationCenter.default.post(name: .timeCapsuleDidChange, object: self)
        return true
    }

    // MARK: - Queries

    /// All capsules in a given state.
    func capsules(in state: CapsuleState) -> [TimeCapsuleItem] {
        refreshStates()
        return capsules.filter { $0.state == state }
    }

    /// All capsules, optionally filtered by tag.
    func allCapsules(tag: String? = nil) -> [TimeCapsuleItem] {
        refreshStates()
        if let tag = tag?.lowercased() {
            return capsules.filter { $0.tags.contains(tag) }
        }
        return capsules
    }

    /// Capsules ready to open right now.
    func readyCapsules() -> [TimeCapsuleItem] {
        refreshStates()
        return capsules.filter { $0.state == .ready }
    }

    /// Capsules opening within the next N days.
    func upcomingCapsules(withinDays days: Int = 7) -> [TimeCapsuleItem] {
        refreshStates()
        let cutoff = Calendar.current.date(byAdding: .day, value: days, to: Date())!
        return capsules.filter { $0.state == .sealed && $0.openDate <= cutoff }
            .sorted { $0.openDate < $1.openDate }
    }

    /// Get a single capsule by ID.
    func capsule(id: String) -> TimeCapsuleItem? {
        refreshStates()
        return capsules.first { $0.id == id }
    }

    /// Search capsules by title or message text.
    func search(query: String) -> [TimeCapsuleItem] {
        let q = query.lowercased()
        return capsules.filter {
            $0.articleTitle.lowercased().contains(q) ||
            $0.message.lowercased().contains(q) ||
            $0.tags.contains(q)
        }
    }

    // MARK: - Management

    /// Delete a capsule (any state).
    @discardableResult
    func delete(capsuleId: String) -> Bool {
        guard let idx = capsules.firstIndex(where: { $0.id == capsuleId }) else { return false }
        capsules.remove(at: idx)
        save()
        NotificationCenter.default.post(name: .timeCapsuleDidChange, object: self)
        return true
    }

    /// Extend the open date for a sealed capsule.
    func extend(capsuleId: String, newOpenDate: Date) -> Bool {
        guard let idx = capsules.firstIndex(where: { $0.id == capsuleId }) else { return false }
        guard capsules[idx].state == .sealed else { return false }
        guard newOpenDate > capsules[idx].openDate else { return false }

        capsules[idx] = TimeCapsuleItem(
            id: capsules[idx].id,
            articleLink: capsules[idx].articleLink,
            articleTitle: capsules[idx].articleTitle,
            feedName: capsules[idx].feedName,
            buriedDate: capsules[idx].buriedDate,
            openDate: newOpenDate,
            message: capsules[idx].message,
            tags: capsules[idx].tags,
            state: .sealed,
            openedDate: nil,
            reflection: nil
        )
        save()
        NotificationCenter.default.post(name: .timeCapsuleDidChange, object: self)
        return true
    }

    /// Add tags to an existing capsule.
    func addTags(capsuleId: String, tags: [String]) -> Bool {
        guard let idx = capsules.firstIndex(where: { $0.id == capsuleId }) else { return false }
        let newTags = tags.map { $0.lowercased().trimmingCharacters(in: .whitespaces) }
        let combined = Array(Set(capsules[idx].tags + newTags))
        capsules[idx].tags = combined
        save()
        return true
    }

    /// Remove all opened capsules older than the given number of days.
    func purgeOpened(olderThanDays days: Int = 365) -> Int {
        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date())!
        let before = capsules.count
        capsules.removeAll { $0.state == .opened && ($0.openedDate ?? Date()) < cutoff }
        let removed = before - capsules.count
        if removed > 0 {
            save()
            NotificationCenter.default.post(name: .timeCapsuleDidChange, object: self)
        }
        return removed
    }

    // MARK: - Statistics

    /// Compute aggregate stats.
    func stats() -> CapsuleStats {
        refreshStates()

        let sealed = capsules.filter { $0.state == .sealed }
        let ready = capsules.filter { $0.state == .ready }
        let opened = capsules.filter { $0.state == .opened }

        let avgDuration: Double
        if !capsules.isEmpty {
            let totalDays = capsules.map { Double($0.totalDurationDays) }.reduce(0, +)
            avgDuration = totalDays / Double(capsules.count)
        } else {
            avgDuration = 0
        }

        // Tag frequency
        var tagCounts: [String: Int] = [:]
        for c in capsules {
            for t in c.tags { tagCounts[t, default: 0] += 1 }
        }
        let topTags = tagCounts.sorted { $0.value > $1.value }
            .prefix(10)
            .map { (tag: $0.key, count: $0.value) }

        let reflectionRate: Double
        if opened.isEmpty {
            reflectionRate = 0
        } else {
            reflectionRate = Double(opened.filter { $0.reflection != nil }.count) / Double(opened.count)
        }

        let nearestOpen = sealed.map(\.openDate).min() ?? ready.first?.openDate

        return CapsuleStats(
            totalCapsules: capsules.count,
            sealedCount: sealed.count,
            readyCount: ready.count,
            openedCount: opened.count,
            oldestBurialDate: capsules.map(\.buriedDate).min(),
            nearestOpenDate: nearestOpen,
            averageDurationDays: avgDuration,
            topTags: topTags,
            reflectionRate: reflectionRate
        )
    }

    // MARK: - Export

    /// Export capsules as Markdown.
    func exportMarkdown(states: [CapsuleState]? = nil) -> String {
        refreshStates()
        let items = states != nil ? capsules.filter { states!.contains($0.state) } : capsules
        let df = DateFormatter()
        df.dateStyle = .medium
        df.timeStyle = .none

        var md = "# 📦 Time Capsules\n\n"
        md += "Generated: \(df.string(from: Date()))\n\n"

        let grouped = Dictionary(grouping: items) { $0.state }
        for state in CapsuleState.allCases {
            guard let group = grouped[state], !group.isEmpty else { continue }
            md += "## \(state.emoji) \(state.label) (\(group.count))\n\n"
            for c in group.sorted(by: { $0.openDate < $1.openDate }) {
                md += "### \(c.articleTitle)\n"
                md += "- **Link:** \(c.articleLink)\n"
                md += "- **Feed:** \(c.feedName)\n"
                md += "- **Buried:** \(df.string(from: c.buriedDate))\n"
                md += "- **Opens:** \(df.string(from: c.openDate))\n"
                if !c.message.isEmpty {
                    md += "- **Message:** \(c.message)\n"
                }
                if !c.tags.isEmpty {
                    md += "- **Tags:** \(c.tags.joined(separator: ", "))\n"
                }
                if let opened = c.openedDate {
                    md += "- **Opened:** \(df.string(from: opened))\n"
                }
                if let reflection = c.reflection {
                    md += "- **Reflection:** \(reflection)\n"
                }
                md += "\n"
            }
        }
        return md
    }

    /// Export capsules as JSON data.
    func exportJSON() -> Data? {
        refreshStates()
        return try? encoder.encode(capsules)
    }

    // MARK: - Private

    /// Transition sealed capsules to ready if their open date has passed.
    private func refreshStates() {
        var changed = false
        for i in capsules.indices {
            if capsules[i].state == .sealed && capsules[i].isReady {
                capsules[i].state = .ready
                changed = true
            }
        }
        if changed {
            save()
            if autoCheckEnabled {
                NotificationCenter.default.post(name: .timeCapsuleReady, object: self)
            }
        }
    }

    private func load() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        guard let data = try? Data(contentsOf: fileURL) else { return }
        capsules = (try? decoder.decode([TimeCapsuleItem].self, from: data)) ?? []
    }

    private func save() {
        guard let data = try? encoder.encode(capsules) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
