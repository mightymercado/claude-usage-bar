import Foundation

// MARK: - Pricing (per 1M tokens, API rates)

enum ModelTier: String, Codable, CaseIterable {
    case opus, sonnet, haiku

    var inputCostPerMTok: Double {
        switch self {
        case .opus:   return 15.0
        case .sonnet: return 3.0
        case .haiku:  return 0.80
        }
    }
    var outputCostPerMTok: Double {
        switch self {
        case .opus:   return 75.0
        case .sonnet: return 15.0
        case .haiku:  return 4.0
        }
    }
    var cacheWriteCostPerMTok: Double {
        switch self {
        case .opus:   return 18.75
        case .sonnet: return 3.75
        case .haiku:  return 1.0
        }
    }
    var cacheReadCostPerMTok: Double {
        switch self {
        case .opus:   return 1.50
        case .sonnet: return 0.30
        case .haiku:  return 0.08
        }
    }

    static func from(model: String) -> ModelTier {
        if model.contains("opus")   { return .opus }
        if model.contains("haiku")  { return .haiku }
        return .sonnet
    }
}

// MARK: - Data Models

struct TierTokens: Codable {
    var inputTokens: Int64 = 0
    var outputTokens: Int64 = 0
    var cacheCreationTokens: Int64 = 0
    var cacheReadTokens: Int64 = 0

    func cost(tier: ModelTier) -> Double {
        let i = Double(inputTokens) * tier.inputCostPerMTok
        let o = Double(outputTokens) * tier.outputCostPerMTok
        let cw = Double(cacheCreationTokens) * tier.cacheWriteCostPerMTok
        let cr = Double(cacheReadTokens) * tier.cacheReadCostPerMTok
        return (i + o + cw + cr) / 1_000_000
    }
}

struct MonthlyTokens: Codable {
    var byTier: [String: TierTokens] = [:]

    var totalCost: Double {
        byTier.reduce(0) { sum, entry in
            let tier = ModelTier(rawValue: entry.key) ?? .sonnet
            return sum + entry.value.cost(tier: tier)
        }
    }

    mutating func add(tier: ModelTier, input: Int64, output: Int64, cacheCreate: Int64, cacheRead: Int64) {
        var t = byTier[tier.rawValue] ?? TierTokens()
        t.inputTokens += input
        t.outputTokens += output
        t.cacheCreationTokens += cacheCreate
        t.cacheReadTokens += cacheRead
        byTier[tier.rawValue] = t
    }
}

struct TokenStats: Codable {
    var year: Int
    var byTier: [String: TierTokens] = [:]
    var monthly: [String: MonthlyTokens] = [:]  // "01"…"12"

    var totalCost: Double {
        byTier.reduce(0) { sum, entry in
            let tier = ModelTier(rawValue: entry.key) ?? .sonnet
            return sum + entry.value.cost(tier: tier)
        }
    }

    mutating func add(tier: ModelTier, month: String, input: Int64, output: Int64, cacheCreate: Int64, cacheRead: Int64) {
        var t = byTier[tier.rawValue] ?? TierTokens()
        t.inputTokens += input
        t.outputTokens += output
        t.cacheCreationTokens += cacheCreate
        t.cacheReadTokens += cacheRead
        byTier[tier.rawValue] = t

        var m = monthly[month] ?? MonthlyTokens()
        m.add(tier: tier, input: input, output: output, cacheCreate: cacheCreate, cacheRead: cacheRead)
        monthly[month] = m
    }

    private static let costFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        f.maximumFractionDigits = 2
        return f
    }()

    static func formatCost(_ amount: Double) -> String {
        if amount >= 1000 {
            costFormatter.maximumFractionDigits = 0
        } else {
            costFormatter.maximumFractionDigits = 2
        }
        return costFormatter.string(from: NSNumber(value: amount)) ?? String(format: "$%.2f", amount)
    }

    static func formatCount(_ n: Int64) -> String {
        let d = Double(n)
        switch d {
        case 1_000_000_000...: return String(format: "%.1fB", d / 1_000_000_000)
        case 1_000_000...:     return String(format: "%.1fM", d / 1_000_000)
        case 1_000...:         return String(format: "%.1fK", d / 1_000)
        default:               return "\(n)"
        }
    }
}

/// Persisted state: YTD + all-time stats with shared watermarks
struct AccumulatorState: Codable {
    var ytd: TokenStats
    var allTime: TokenStats
    var fileWatermarks: [String: Int64] = [:]  // shared across both
}

// MARK: - Accumulator

actor TokenAccumulator {
    private static let projectsDir: URL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".claude/projects")
    private static let stateFile: URL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".config/claude-usage-bar/token-accumulation.json")

    private var state: AccumulatorState

    init() {
        let currentYear = Calendar.current.component(.year, from: Date())
        if var loaded = Self.loadState() {
            // Reset YTD if year rolled over
            if loaded.ytd.year != currentYear {
                loaded.ytd = TokenStats(year: currentYear)
                // Watermarks stay valid for all-time, but YTD needs re-scan
                // Easiest: clear watermarks and re-scan everything
                loaded.fileWatermarks = [:]
                loaded.allTime = TokenStats(year: 0)
            }
            state = loaded
        } else {
            state = AccumulatorState(
                ytd: TokenStats(year: currentYear),
                allTime: TokenStats(year: 0)
            )
        }
    }

    func scan() async -> (ytd: TokenStats, allTime: TokenStats) {
        let fm = FileManager.default

        var jsonlFiles: [(url: URL, relativePath: String, fileSize: Int64)] = []
        let projectsPath = Self.projectsDir.path

        guard let topEnum = fm.enumerator(
            at: Self.projectsDir,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return (state.ytd, state.allTime) }

        while let url = topEnum.nextObject() as? URL {
                guard url.pathExtension == "jsonl" else { continue }
                let relativePath = url.path.replacingOccurrences(of: projectsPath + "/", with: "")
                let fileSize: Int64
                do {
                    let vals = try url.resourceValues(forKeys: [.fileSizeKey])
                    fileSize = Int64(vals.fileSize ?? 0)
                } catch { continue }

                let watermark = state.fileWatermarks[relativePath] ?? 0
                guard fileSize > watermark else { continue }
                jsonlFiles.append((url, relativePath, fileSize))
        }

        let currentYear = Calendar.current.component(.year, from: Date())
        if state.ytd.year != currentYear {
            state = AccumulatorState(
                ytd: TokenStats(year: currentYear),
                allTime: TokenStats(year: 0)
            )
        }

        var calendar = Calendar.current
        calendar.timeZone = TimeZone.current

        let needle = Data("\"input_tokens\"".utf8)
        var filesProcessed = 0

        for (url, relativePath, fileSize) in jsonlFiles {
            let watermark = state.fileWatermarks[relativePath] ?? 0

            guard let handle = try? FileHandle(forReadingFrom: url) else { continue }
            defer { try? handle.close() }

            if watermark > 0 {
                try? handle.seek(toOffset: UInt64(watermark))
            }

            let newData = handle.readDataToEndOfFile()

            // Fast scan: split on newlines at the Data level, skip lines without "input_tokens"
            newData.withUnsafeBytes { buffer in
                guard let base = buffer.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return }
                let len = buffer.count
                var lineStart = 0

                while lineStart < len {
                    // Find end of line
                    var lineEnd = lineStart
                    while lineEnd < len && base[lineEnd] != 0x0A { lineEnd += 1 }

                    let lineLen = lineEnd - lineStart
                    if lineLen > 20 { // skip trivially short lines
                        let lineData = Data(bytes: base + lineStart, count: lineLen)

                        // Fast check: does this line contain "input_tokens"?
                        if lineData.range(of: needle) != nil {
                            if let entry = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                               let message = entry["message"] as? [String: Any],
                               let usage = message["usage"] as? [String: Any] {

                                if let date = self.parseDate(from: entry["timestamp"]) {
                                    let year = calendar.component(.year, from: date)
                                    let monthNum = calendar.component(.month, from: date)
                                    let modelName = (message["model"] as? String) ?? "unknown"
                                    let tier = ModelTier.from(model: modelName)

                                    let input = self.int64(from: usage["input_tokens"])
                                    let output = self.int64(from: usage["output_tokens"])
                                    let cacheCreate = self.int64(from: usage["cache_creation_input_tokens"])
                                    let cacheRead = self.int64(from: usage["cache_read_input_tokens"])

                                    let allTimeMonth = String(format: "%04d-%02d", year, monthNum)
                                    self.state.allTime.add(tier: tier, month: allTimeMonth, input: input, output: output, cacheCreate: cacheCreate, cacheRead: cacheRead)

                                    if year == currentYear {
                                        let month = String(format: "%02d", monthNum)
                                        self.state.ytd.add(tier: tier, month: month, input: input, output: output, cacheCreate: cacheCreate, cacheRead: cacheRead)
                                    }
                                }
                            }
                        }
                    }

                    lineStart = lineEnd + 1
                }
            }

            state.fileWatermarks[relativePath] = fileSize
            filesProcessed += 1

            // Save progress every 100 files
            if filesProcessed % 100 == 0 {
                Self.saveState(state)
            }
        }

        Self.saveState(state)
        return (state.ytd, state.allTime)
    }

    // MARK: - Persistence

    private static func loadState() -> AccumulatorState? {
        guard let data = try? Data(contentsOf: stateFile) else { return nil }
        return try? JSONDecoder().decode(AccumulatorState.self, from: data)
    }

    private static func saveState(_ state: AccumulatorState) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        let dir = stateFile.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? data.write(to: stateFile, options: .atomic)
    }

    private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let isoFormatterNoFrac: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private func parseDate(from value: Any?) -> Date? {
        switch value {
        case let s as String:
            return Self.isoFormatter.date(from: s) ?? Self.isoFormatterNoFrac.date(from: s)
        case let n as NSNumber:
            let ms = n.doubleValue
            return ms > 0 ? Date(timeIntervalSince1970: ms / 1000) : nil
        default:
            return nil
        }
    }

    private func int64(from value: Any?) -> Int64 {
        switch value {
        case let n as NSNumber: return n.int64Value
        case let n as Int: return Int64(n)
        case let n as Int64: return n
        case let n as Double: return Int64(n)
        default: return 0
        }
    }
}
