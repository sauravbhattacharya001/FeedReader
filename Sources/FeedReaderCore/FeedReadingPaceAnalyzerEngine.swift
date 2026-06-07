import Foundation

public final class FeedReadingPaceAnalyzer: @unchecked Sendable {
    private let now: () -> Date
    private static let defaultWPM: Double = 238.0
    private static let minTrendSessions = 3
    private static let minProfileSessions = 2

    public init(now: @escaping () -> Date = { Date() }) { self.now = now }

    public func analyze(sessions: [PaceSession]) -> PaceReport? {
        let valid = sessions.filter { $0.wordCount > 0 && $0.readingSeconds > 0 }
        guard !valid.isEmpty else { return nil }
        let wpms = valid.map { $0.wpm }
        let overallWPM = wpms.reduce(0, +) / Double(wpms.count)
        let medianWPM = Self.median(wpms)
        let dominantPace = ReadingPace.classify(medianWPM)
        var dist: [ReadingPace: Int] = [:]; for p in ReadingPace.allCases { dist[p] = 0 }
        for s in valid { dist[s.pace, default: 0] += 1 }
        let totalWords = valid.reduce(0) { $0 + $1.wordCount }
        let totalSecs = valid.reduce(0.0) { $0 + $1.readingSeconds }
        let topicProfiles = buildProfiles(valid, kp: \.topic)
        let feedProfiles = buildProfiles(valid, kp: \.feedName)
        let trends = buildTrends(valid)
        let anomalies = detectAnomalies(valid, avg: overallWPM, tp: topicProfiles)
        let recs = buildRecs(anomalies: anomalies, pace: dominantPace, n: valid.count)
        let grade = computeGrade(anomalies: anomalies, pace: dominantPace)
        let ins = buildInsights(avg: overallWPM, pace: dominantPace, anomalies: anomalies,
                                tp: topicProfiles, trends: trends, n: valid.count)
        let aCnt = anomalies.count
        let note = aCnt > 0 ? " -- \(aCnt) anomal\(aCnt == 1 ? "y" : "ies") detected" : ""
        let headline = "Grade \(grade): \(Int(overallWPM)) WPM (\(dominantPace.label))\(note)"
        return PaceReport(totalSessions: valid.count,
            overallWPM: round(overallWPM * 10) / 10, medianWPM: round(medianWPM * 10) / 10,
            dominantPace: dominantPace, paceDistribution: dist,
            totalWordsRead: totalWords, totalReadingSeconds: round(totalSecs * 10) / 10,
            trends: trends, topicProfiles: topicProfiles, feedProfiles: feedProfiles,
            anomalies: anomalies.sorted { $0.severityScore > $1.severityScore },
            recommendations: recs.sorted { $0.priority < $1.priority },
            paceGrade: grade, headline: headline, insights: ins.sorted())
    }

    public func estimateReadingTime(wordCount: Int, topic: String? = nil,
                                     feedName: String? = nil,
                                     sessions: [PaceSession] = []) -> ReadingTimeEstimate {
        guard wordCount > 0 else {
            return ReadingTimeEstimate(estimatedMinutes: 0, estimatedWPM: Self.defaultWPM,
                                       confidence: 1.0, source: "default")
        }
        let valid = sessions.filter { $0.wordCount > 0 && $0.readingSeconds > 0 }
        if let t = topic {
            let ts = valid.filter { $0.topic.lowercased() == t.lowercased() }
            if ts.count >= Self.minProfileSessions {
                let w = Self.median(ts.map { $0.wpm })
                return ReadingTimeEstimate(estimatedMinutes: round(Double(wordCount)/w*10)/10,
                    estimatedWPM: round(w*10)/10,
                    confidence: max(0.3, min(1.0, Double(ts.count)/20.0)), source: "topic")
            }
        }
        if let f = feedName {
            let fs = valid.filter { $0.feedName.lowercased() == f.lowercased() }
            if fs.count >= Self.minProfileSessions {
                let w = Self.median(fs.map { $0.wpm })
                return ReadingTimeEstimate(estimatedMinutes: round(Double(wordCount)/w*10)/10,
                    estimatedWPM: round(w*10)/10,
                    confidence: max(0.25, min(1.0, Double(fs.count)/20.0)), source: "feed")
            }
        }
        if !valid.isEmpty {
            let w = Self.median(valid.map { $0.wpm })
            return ReadingTimeEstimate(estimatedMinutes: round(Double(wordCount)/w*10)/10,
                estimatedWPM: round(w*10)/10,
                confidence: max(0.15, min(1.0, Double(valid.count)/30.0)), source: "global")
        }
        return ReadingTimeEstimate(estimatedMinutes: round(Double(wordCount)/Self.defaultWPM*10)/10,
            estimatedWPM: Self.defaultWPM, confidence: 0.1, source: "default")
    }

    private func buildProfiles(_ s: [PaceSession], kp: KeyPath<PaceSession, String>) -> [PaceProfile] {
        var g: [String: [PaceSession]] = [:]
        for x in s { g[x[keyPath: kp], default: []].append(x) }
        return g.compactMap { name, grp -> PaceProfile? in
            guard grp.count >= Self.minProfileSessions else { return nil }
            let w = grp.map { $0.wpm }; let a = w.reduce(0,+)/Double(w.count); let m = Self.median(w)
            return PaceProfile(name: name, sessionCount: grp.count,
                averageWPM: round(a*10)/10, medianWPM: round(m*10)/10,
                fastestWPM: round((w.max() ?? 0)*10)/10, slowestWPM: round((w.min() ?? 0)*10)/10,
                dominantPace: ReadingPace.classify(m),
                totalWordsRead: grp.reduce(0){$0+$1.wordCount},
                totalSeconds: round(grp.reduce(0.0){$0+$1.readingSeconds}*10)/10)
        }.sorted { $0.sessionCount > $1.sessionCount }
    }

    private func buildTrends(_ sessions: [PaceSession]) -> [PaceTrend] {
        guard sessions.count >= Self.minTrendSessions else { return [] }
        let sorted = sessions.sorted { $0.readAt < $1.readAt }
        let cur = now(); var trends: [PaceTrend] = []
        for (label, iv) in [("last_7_days", 7.0*86400), ("last_30_days", 30.0*86400)] {
            let cutoff = cur.addingTimeInterval(-iv)
            let prevCut = cur.addingTimeInterval(-iv*2)
            let recent = sorted.filter { $0.readAt >= cutoff }
            let prev = sorted.filter { $0.readAt >= prevCut && $0.readAt < cutoff }
            guard recent.count >= Self.minTrendSessions else { continue }
            let rWPM = recent.map{$0.wpm}.reduce(0,+)/Double(recent.count)
            var chg = 0.0; var dir: PaceTrend.Direction = .stable
            if !prev.isEmpty {
                let pWPM = prev.map{$0.wpm}.reduce(0,+)/Double(prev.count)
                if pWPM > 0 { chg = ((rWPM-pWPM)/pWPM)*100 }
                if chg > 10 { dir = .improving } else if chg < -10 { dir = .declining }
            }
            trends.append(PaceTrend(window: label, sessionCount: recent.count,
                averageWPM: round(rWPM*10)/10, changePercent: round(chg*10)/10, direction: dir))
        }
        return trends
    }

    private func detectAnomalies(_ sessions: [PaceSession], avg: Double, tp: [PaceProfile]) -> [PaceAnomaly] {
        var a: [PaceAnomaly] = []
        for s in sessions {
            if s.wordCount > 800 && s.wpm > 500 {
                a.append(PaceAnomaly(kind: .rushingLongContent,
                    severityScore: min(100, Int(40+(s.wpm-500)/5)),
                    articleId: s.articleId, topic: s.topic, feedName: s.feedName,
                    detail: "Read \(s.wordCount)-word article at \(Int(s.wpm)) WPM"))
            }
            if s.wordCount < 150 && s.wpm < 120 && s.readingSeconds > 60 {
                a.append(PaceAnomaly(kind: .dwellingShortContent,
                    severityScore: min(80, Int(30+(120-s.wpm)/2)),
                    articleId: s.articleId, topic: s.topic, feedName: s.feedName,
                    detail: "Spent \(Int(s.readingSeconds))s on \(s.wordCount)-word article"))
            }
            if avg > 0 && s.wpm > avg*2 {
                let r = s.wpm/avg
                a.append(PaceAnomaly(kind: .paceSpike, severityScore: min(90, Int(30+r*10)),
                    articleId: s.articleId, topic: s.topic, feedName: s.feedName,
                    detail: "\(Int(s.wpm)) WPM is \(String(format:"%.1f",r))x your average"))
            }
            if avg > 0 && s.wpm < avg*0.3 && s.wpm > 0 {
                let r = avg/s.wpm
                a.append(PaceAnomaly(kind: .paceDrop, severityScore: min(85, Int(35+r*5)),
                    articleId: s.articleId, topic: s.topic, feedName: s.feedName,
                    detail: "\(Int(s.wpm)) WPM is \(String(format:"%.1f",r))x slower than average"))
            }
        }
        let sorted = sessions.sorted { $0.readAt < $1.readAt }
        if sorted.count >= 5 {
            let tail = Array(sorted.suffix(5)); let w = tail.map{$0.wpm}
            var dec = true; for i in 1..<w.count { if w[i]>=w[i-1] { dec=false; break } }
            if dec { let dp=((w[0]-w[4])/max(w[0],1))*100
                if dp > 15 { a.append(PaceAnomaly(kind: .fatiguePattern,
                    severityScore: min(75, Int(40+dp/2)),
                    detail: "Speed dropped \(Int(dp))% over last 5 sessions")) }
            }
        }
        for p in tp {
            if avg > 0 && p.averageWPM > 0 && p.averageWPM < avg*0.5 && p.sessionCount >= 3 {
                let r = avg/p.averageWPM
                a.append(PaceAnomaly(kind: .topicStruggle, severityScore: min(70, Int(30+r*10)),
                    topic: p.name, detail: "\(p.name) at \(Int(p.averageWPM)) vs \(Int(avg)) WPM"))
            }
        }
        return a
    }

    private func buildRecs(anomalies: [PaceAnomaly], pace: ReadingPace, n: Int) -> [PaceRecommendation] {
        var recs: [PaceRecommendation] = []; var ids: Set<String> = []
        func add(_ r: PaceRecommendation) { guard !ids.contains(r.id) else { return }; ids.insert(r.id); recs.append(r) }
        let rush = anomalies.filter{$0.kind == .rushingLongContent}.count
        if rush >= 2 { add(PaceRecommendation(id: "slow_down_long_articles", priority: .p0,
            label: "Slow Down on Long Articles", reason: "\(rush) instances of skimming long articles.",
            relatedTopics: Array(Set(anomalies.filter{$0.kind == .rushingLongContent}.compactMap{$0.topic})))) }
        if anomalies.contains(where:{$0.kind == .fatiguePattern}) {
            add(PaceRecommendation(id: "take_reading_breaks", priority: .p0,
                label: "Take Reading Breaks", reason: "Consistent speed decline detected.")) }
        let str = anomalies.filter{$0.kind == .topicStruggle}
        if !str.isEmpty { add(PaceRecommendation(id: "review_difficult_topics", priority: .p1,
            label: "Review Difficult Topics", reason: "Significantly slower on some topics.",
            relatedTopics: str.compactMap{$0.topic})) }
        if pace == .skimming { add(PaceRecommendation(id: "reduce_skimming", priority: .p1,
            label: "Reduce Skimming", reason: "Most articles read at >600 WPM.")) }
        let sp = anomalies.filter{$0.kind == .paceSpike}.count
        if sp >= 2 { add(PaceRecommendation(id: "stabilize_pace", priority: .p2,
            label: "Stabilize Reading Pace", reason: "\(sp) pace spikes detected.")) }
        if pace == .deepReading && n >= 5 { add(PaceRecommendation(id: "increase_reading_speed",
            priority: .p2, label: "Consider Speed Reading Techniques",
            reason: "Consistent deep-reading pace (<100 WPM).")) }
        if anomalies.isEmpty { add(PaceRecommendation(id: "maintain_pace", priority: .p3,
            label: "Maintain Current Pace", reason: "Reading pace is consistent and healthy.")) }
        return recs
    }

    private func computeGrade(anomalies: [PaceAnomaly], pace: ReadingPace) -> String {
        let hi = anomalies.filter{$0.severityScore >= 67}.count
        let med = anomalies.filter{$0.severityScore >= 34 && $0.severityScore < 67}.count
        let pen = hi*20 + med*8 + anomalies.count*2
        let bonus: Int; switch pace { case .normal: bonus=10; case .fast,.slow: bonus=5; default: bonus=0 }
        let sc = max(0, 100-pen+bonus)
        if sc >= 85 { return "A" }; if sc >= 70 { return "B" }
        if sc >= 55 { return "C" }; if sc >= 40 { return "D" }; return "F"
    }

    private func buildInsights(avg: Double, pace: ReadingPace, anomalies: [PaceAnomaly],
                                tp: [PaceProfile], trends: [PaceTrend], n: Int) -> [String] {
        var ins = ["average_wpm_\(Int(avg))", "dominant_pace_\(pace.rawValue)"]
        if anomalies.isEmpty { ins.append("no_anomalies_detected") }
        else { ins.append("anomalies_detected_\(anomalies.count)") }
        if tp.count >= 2, let mx = tp.map({$0.averageWPM}).max(),
           let mn = tp.map({$0.averageWPM}).min(), mx > 0, (mx-mn)/mx > 0.4 {
            ins.append("high_topic_pace_variance")
        }
        for t in trends {
            if t.direction == .declining { ins.append("pace_declining_\(t.window)") }
            else if t.direction == .improving { ins.append("pace_improving_\(t.window)") }
        }
        if n < 10 { ins.append("limited_data_\(n)_sessions") }
        return ins
    }

    private static func median(_ v: [Double]) -> Double {
        guard !v.isEmpty else { return 0 }
        let s = v.sorted(); let m = s.count/2
        return s.count % 2 == 0 ? (s[m-1]+s[m])/2.0 : s[m]
    }
}
