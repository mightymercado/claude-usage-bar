import SwiftUI
import Charts

// MARK: - Finance-style fonts & colors

private let fin = FinanceTheme.self

enum FinanceTheme {
    // Fonts
    static let heroNum    = Font.system(size: 28, weight: .heavy, design: .rounded).monospacedDigit()
    static let bigNum     = Font.system(size: 18, weight: .bold, design: .rounded).monospacedDigit()
    static let medNum     = Font.system(size: 13, weight: .bold, design: .rounded).monospacedDigit()
    static let smallNum   = Font.system(size: 11, weight: .semibold, design: .rounded).monospacedDigit()
    static let tinyNum    = Font.system(size: 10, weight: .semibold, design: .rounded).monospacedDigit()

    static let sectionLabel = Font.system(size: 9, weight: .bold, design: .rounded)
    static let label        = Font.system(size: 11, weight: .semibold, design: .rounded)
    static let sublabel     = Font.system(size: 10, weight: .medium, design: .rounded)
    static let micro        = Font.system(size: 9, weight: .medium, design: .rounded)

    // Colors
    static let green     = Color(red: 0.15, green: 0.82, blue: 0.45)
    static let darkGreen = Color(red: 0.08, green: 0.62, blue: 0.32)
    static let red       = Color(red: 0.95, green: 0.25, blue: 0.22)
    static let orange    = Color(red: 1.0, green: 0.58, blue: 0.0)
    static let cyan      = Color(red: 0.2, green: 0.75, blue: 0.95)
    static let gold      = Color(red: 0.95, green: 0.75, blue: 0.2)
    static let dimText   = Color.primary.opacity(0.4)
    static let faintText = Color.primary.opacity(0.25)

    static let greenGradient = LinearGradient(
        colors: [Color(red: 0.2, green: 0.88, blue: 0.45), Color(red: 0.08, green: 0.65, blue: 0.35)],
        startPoint: .leading, endPoint: .trailing
    )

    static func pctColor(for pct: Double) -> Color {
        if pct >= 0.9 { return red }
        if pct >= 0.7 { return orange }
        return green
    }
}

// MARK: - Main View

struct PopoverView: View {
    @ObservedObject var service: UsageService

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !service.isAuthenticated {
                authView
            } else if service.isAwaitingCode {
                codeEntryView
            } else {
                usageView
            }
        }
        .padding(16)
        .frame(width: 340)
        .background(.ultraThinMaterial)
    }

    // MARK: - Auth View

    private var authView: some View {
        VStack(spacing: 12) {
            Text("CLAUDE USAGE")
                .font(fin.sectionLabel)
                .tracking(2)
                .foregroundStyle(fin.dimText)

            Text("Sign in to view your usage.")
                .font(fin.sublabel)
                .foregroundStyle(.secondary)

            Button("Sign In with Claude") {
                service.startOAuthFlow()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            if let error = service.lastError {
                Text(error).font(fin.micro).foregroundStyle(fin.red)
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Code Entry

    @State private var codeInput = ""

    private var codeEntryView: some View {
        VStack(spacing: 10) {
            Text("AUTHORIZATION")
                .font(fin.sectionLabel)
                .tracking(2)
                .foregroundStyle(fin.dimText)

            Text("Paste the code from the browser window.")
                .font(fin.micro)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            HStack {
                TextField("code#state", text: $codeInput)
                    .textFieldStyle(.roundedBorder)
                    .font(fin.sublabel)

                Button("Paste") {
                    if let clip = NSPasteboard.general.string(forType: .string) {
                        codeInput = clip
                    }
                }
                .controlSize(.small)
            }

            HStack {
                Button("Cancel") {
                    service.isAwaitingCode = false
                    codeInput = ""
                }
                .controlSize(.small)
                Spacer()
                Button("Submit") {
                    let code = codeInput
                    codeInput = ""
                    Task { await service.submitOAuthCode(code) }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(codeInput.isEmpty)
            }

            if let error = service.lastError {
                Text(error).font(fin.micro).foregroundStyle(fin.red)
            }
        }
    }

    // MARK: - Usage View

    private var usageView: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header
            HStack(alignment: .firstTextBaseline) {
                Text("CLAUDE")
                    .font(fin.sectionLabel)
                    .tracking(3)
                    .foregroundStyle(.primary.opacity(0.7))

                Text(service.isPeakHours ? "PEAK" : "OFF-PEAK")
                    .font(.system(size: 8, weight: .heavy, design: .rounded))
                    .tracking(1)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(service.isPeakHours ? fin.orange.opacity(0.15) : fin.cyan.opacity(0.1))
                    .foregroundStyle(service.isPeakHours ? fin.orange : fin.cyan)
                    .clipShape(RoundedRectangle(cornerRadius: 3))

                Spacer()
                if let email = service.accountEmail {
                    Text(email)
                        .font(fin.micro)
                        .foregroundStyle(fin.dimText)
                        .lineLimit(1)
                }
            }

            Divider().opacity(0.3)

            // Rate limit buckets
            if let bucket = service.usage?.fiveHour {
                UsageBucketRow(label: "5H", bucket: bucket, etaHours: service.eta5hHours, willExceed: service.willExceed5h)
            }

            if let bucket = service.usage?.sevenDay {
                UsageBucketRow(label: "7D", bucket: bucket, etaHours: service.eta7dHours, willExceed: service.willExceed7d)
            }

            // Model breakdown (Opus only)
            if let opus = service.usage?.sevenDayOpus {
                UsageBucketRow(label: "OPUS 7D", bucket: opus)
            }

            // Cost chart
            if let stats = service.tokenStats, stats.monthly.count >= 2 {
                Divider().opacity(0.3)
                CostChart(stats: stats)
            }

            // Extra usage
            if let extra = service.usage?.extraUsage, extra.isEnabled {
                Divider().opacity(0.3)
                ExtraUsageRow(extra: extra)
            }

            // YTD cost section
            if let stats = service.tokenStats, stats.totalCost > 0.01 {
                Divider().opacity(0.3)
                TokenStatsRow(stats: stats, allTimeStats: service.allTimeTokenStats)
            }

            Divider().opacity(0.3)

            // Footer
            HStack(spacing: 8) {
                if let lastUpdated = service.lastUpdated {
                    Text("UPD \(lastUpdated, style: .relative)")
                        .font(fin.micro)
                        .foregroundStyle(fin.faintText)
                }
                Spacer()

                Button {
                    Task { await service.fetchUsage() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 10, weight: .semibold))
                }
                .buttonStyle(.borderless)
                .foregroundStyle(fin.dimText)

                Menu {
                    ForEach(UsageService.pollingOptions, id: \.self) { mins in
                        Button {
                            service.updatePollingInterval(mins)
                        } label: {
                            HStack {
                                Text(mins < 60 ? "\(mins)m" : "1h")
                                if mins == service.pollingMinutes {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    Image(systemName: "timer")
                        .font(.system(size: 10, weight: .semibold))
                }
                .menuStyle(.borderlessButton)
                .frame(width: 20)

                Button("Sign Out") { service.signOut() }
                    .font(fin.micro)
                    .buttonStyle(.borderless)
                    .foregroundStyle(fin.dimText)

                Button {
                    NSApplication.shared.terminate(nil)
                } label: {
                    Image(systemName: "xmark.circle")
                        .font(.system(size: 10, weight: .semibold))
                }
                .buttonStyle(.borderless)
                .foregroundStyle(fin.faintText)
                .help("Quit")
            }

            if let error = service.lastError {
                Text(error).font(fin.micro).foregroundStyle(fin.red)
            }
        }
    }
}

// MARK: - Usage Bucket Row

struct UsageBucketRow: View {
    let label: String
    let bucket: UsageBucket
    var etaHours: Double? = nil
    var willExceed: Bool = false

    private var pct: Double { (bucket.utilization ?? 0) / 100.0 }
    private var barColor: Color { fin.pctColor(for: pct) }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline) {
                Text(label)
                    .font(fin.sectionLabel)
                    .tracking(1)
                    .foregroundStyle(fin.dimText)
                Spacer()
                Text("\(Int(round(pct * 100)))%")
                    .font(fin.bigNum)
                    .foregroundStyle(barColor)
            }

            ProgressView(value: min(pct, 1.0))
                .tint(barColor)
                .scaleEffect(y: 1.5, anchor: .center)

            HStack(spacing: 0) {
                if let reset = bucket.resetsAtDate {
                    Text("Resets \(reset, style: .relative)")
                        .foregroundStyle(fin.faintText)
                }
                if let eta = etaHours {
                    if bucket.resetsAtDate != nil { Text(" · ").foregroundStyle(fin.faintText) }
                    Text(eta <= 0 ? "AT LIMIT" : "~\(Self.formatEta(eta)) to full")
                        .foregroundStyle(willExceed ? fin.orange : fin.dimText)
                }
            }
            .font(fin.micro)

            if willExceed {
                HStack(spacing: 3) {
                    Image(systemName: "exclamationmark.triangle.fill")
                    Text("WILL HIT LIMIT BEFORE RESET")
                }
                .font(.system(size: 8, weight: .bold, design: .rounded))
                .tracking(0.5)
                .foregroundStyle(fin.orange)
            }
        }
    }

    static func formatEta(_ hours: Double) -> String {
        if hours < 1 {
            return "\(max(1, Int(round(hours * 60))))m"
        } else if hours < 24 {
            return String(format: "%.1fh", hours)
        } else {
            return String(format: "%.1fd", hours / 24)
        }
    }
}

// MARK: - Extra Usage Row

struct ExtraUsageRow: View {
    let extra: ExtraUsage

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline) {
                Text("EXTRA USAGE")
                    .font(fin.sectionLabel)
                    .tracking(1)
                    .foregroundStyle(fin.dimText)
                Spacer()
                if let used = extra.usedCreditsAmount {
                    Text(ExtraUsage.formatUSD(used))
                        .font(fin.medNum)
                        .foregroundStyle(fin.cyan)
                }
            }

            if let used = extra.usedCreditsAmount, let limit = extra.monthlyLimitAmount, limit > 0 {
                ProgressView(value: min(used / limit, 1.0))
                    .tint(fin.cyan)
                    .scaleEffect(y: 1.5, anchor: .center)

                Text("\(ExtraUsage.formatUSD(used)) / \(ExtraUsage.formatUSD(limit))")
                    .font(fin.micro)
                    .foregroundStyle(fin.faintText)
            }
        }
    }
}

// MARK: - Token Stats Row

struct TokenStatsRow: View {
    let stats: TokenStats
    let allTimeStats: TokenStats?
    @State private var showBreakdown = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Header
            HStack(alignment: .firstTextBaseline) {
                Text("EST. API COST")
                    .font(fin.sectionLabel)
                    .tracking(2)
                    .foregroundStyle(fin.dimText)
                Spacer()
                Text("\(String(stats.year)) YTD")
                    .font(fin.micro)
                    .foregroundStyle(fin.faintText)
            }

            // Hero number
            Text(TokenStats.formatCost(stats.totalCost))
                .font(fin.heroNum)
                .foregroundStyle(FinanceTheme.greenGradient)

            // Per-tier
            HStack(spacing: 14) {
                ForEach(ModelTier.allCases, id: \.rawValue) { tier in
                    if let t = stats.byTier[tier.rawValue], t.cost(tier: tier) > 0.01 {
                        VStack(spacing: 2) {
                            Text(TokenStats.formatCost(t.cost(tier: tier)))
                                .font(fin.medNum)
                                .foregroundStyle(tierColor(tier))
                            Text(tier.rawValue.uppercased())
                                .font(.system(size: 8, weight: .bold, design: .rounded))
                                .tracking(1)
                                .foregroundStyle(fin.faintText)
                        }
                    }
                }
            }

            // All-time
            if let allTime = allTimeStats, allTime.totalCost > stats.totalCost + 0.01 {
                HStack {
                    Text("ALL TIME")
                        .font(.system(size: 8, weight: .bold, design: .rounded))
                        .tracking(1)
                        .foregroundStyle(fin.faintText)
                    Spacer()
                    Text(TokenStats.formatCost(allTime.totalCost))
                        .font(fin.smallNum)
                        .foregroundStyle(fin.dimText)
                }
            }

            // Details toggle
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { showBreakdown.toggle() }
            } label: {
                HStack(spacing: 3) {
                    Text(showBreakdown ? "LESS" : "DETAILS")
                        .font(.system(size: 8, weight: .bold, design: .rounded))
                        .tracking(1)
                    Image(systemName: showBreakdown ? "chevron.up" : "chevron.down")
                        .font(.system(size: 7, weight: .bold))
                }
                .foregroundStyle(fin.dimText)
            }
            .buttonStyle(.borderless)

            if showBreakdown {
                VStack(alignment: .leading, spacing: 4) {
                    let months = stats.monthly.keys.sorted()
                    if !months.isEmpty {
                        Text("MONTHLY")
                            .font(.system(size: 8, weight: .bold, design: .rounded))
                            .tracking(1.5)
                            .foregroundStyle(fin.faintText)

                        ForEach(months, id: \.self) { month in
                            if let m = stats.monthly[month] {
                                HStack {
                                    Text(monthName(month).uppercased())
                                        .font(fin.micro)
                                        .foregroundStyle(fin.dimText)
                                        .frame(width: 30, alignment: .leading)
                                    ProgressView(value: monthFraction(m, in: stats))
                                        .tint(fin.cyan.opacity(0.7))
                                    Text(TokenStats.formatCost(m.totalCost))
                                        .font(fin.tinyNum)
                                        .foregroundStyle(.primary.opacity(0.6))
                                        .frame(width: 65, alignment: .trailing)
                                }
                            }
                        }
                    }

                    if let allTime = allTimeStats, allTime.totalCost > 0.01 {
                        Divider().opacity(0.2).padding(.vertical, 2)

                        Text("ALL TIME BY MODEL")
                            .font(.system(size: 8, weight: .bold, design: .rounded))
                            .tracking(1.5)
                            .foregroundStyle(fin.faintText)

                        ForEach(ModelTier.allCases, id: \.rawValue) { tier in
                            if let t = allTime.byTier[tier.rawValue], t.cost(tier: tier) > 0.01 {
                                HStack {
                                    Text(tier.rawValue.uppercased())
                                        .font(fin.micro)
                                        .foregroundStyle(fin.dimText)
                                        .frame(width: 55, alignment: .leading)
                                    Spacer()
                                    Text(TokenStats.formatCost(t.cost(tier: tier)))
                                        .font(fin.tinyNum)
                                        .foregroundStyle(tierColor(tier))
                                }
                            }
                        }

                        HStack {
                            Text("TOTAL")
                                .font(.system(size: 9, weight: .heavy, design: .rounded))
                                .foregroundStyle(fin.dimText)
                            Spacer()
                            Text(TokenStats.formatCost(allTime.totalCost))
                                .font(fin.smallNum)
                                .foregroundStyle(.primary)
                        }
                    }
                }
                .padding(.top, 2)
            }
        }
    }

    private func tierColor(_ tier: ModelTier) -> Color {
        switch tier {
        case .opus:   return fin.gold
        case .sonnet: return fin.cyan
        case .haiku:  return fin.green
        }
    }

    private func monthName(_ key: String) -> String {
        let monthNum = Int(key) ?? 0
        let names = ["", "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
        return monthNum > 0 && monthNum <= 12 ? names[monthNum] : key
    }

    private func monthFraction(_ m: MonthlyTokens, in stats: TokenStats) -> Double {
        let maxTotal = stats.monthly.values.map(\.totalCost).max() ?? 1
        guard maxTotal > 0 else { return 0 }
        return m.totalCost / maxTotal
    }
}

// MARK: - Cost Chart

private struct CostPoint: Identifiable {
    let id: String
    let label: String
    let cost: Double
    let cumulative: Double
}

struct CostChart: View {
    let stats: TokenStats

    private var chartData: [CostPoint] {
        let months = stats.monthly.keys.sorted()
        var cumulative = 0.0
        return months.compactMap { key in
            guard let m = stats.monthly[key] else { return nil }
            cumulative += m.totalCost
            let monthNum = Int(key) ?? 0
            let names = ["", "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
            let label = monthNum > 0 && monthNum <= 12 ? names[monthNum] : key
            return CostPoint(id: key, label: label, cost: m.totalCost, cumulative: cumulative)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("SPEND")
                .font(fin.sectionLabel)
                .tracking(2)
                .foregroundStyle(fin.dimText)

            Chart(chartData) { point in
                BarMark(
                    x: .value("Month", point.label),
                    y: .value("Cost", point.cost)
                )
                .foregroundStyle(fin.cyan.opacity(0.5))
                .cornerRadius(2)

                LineMark(
                    x: .value("Month", point.label),
                    y: .value("Cumulative", point.cumulative)
                )
                .foregroundStyle(FinanceTheme.greenGradient)
                .interpolationMethod(.monotone)
                .lineStyle(StrokeStyle(lineWidth: 2.5))

                PointMark(
                    x: .value("Month", point.label),
                    y: .value("Cumulative", point.cumulative)
                )
                .foregroundStyle(fin.green)
                .symbolSize(16)
            }
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.3, dash: [3]))
                        .foregroundStyle(fin.faintText)
                    AxisValueLabel {
                        if let v = value.as(Double.self) {
                            Text(v >= 1000 ? "$\(Int(v / 1000))k" : "$\(Int(v))")
                                .font(fin.micro)
                                .foregroundStyle(fin.faintText)
                        }
                    }
                }
            }
            .chartXAxis {
                AxisMarks { _ in
                    AxisValueLabel()
                        .font(fin.micro)
                        .foregroundStyle(fin.dimText)
                }
            }
            .frame(height: 110)
        }
    }
}
