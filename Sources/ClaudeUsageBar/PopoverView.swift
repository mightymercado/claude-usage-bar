import SwiftUI
import Charts

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
        .frame(width: 320)
    }

    // MARK: - Auth View

    private var authView: some View {
        VStack(spacing: 12) {
            Text("Claude Usage Bar")
                .font(.headline)

            if service.isAwaitingCode {
                codeEntryView
            } else {
                Text("Sign in to view your Claude usage.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                Button("Sign In with Claude") {
                    service.startOAuthFlow()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }

            if let error = service.lastError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Code Entry

    @State private var codeInput = ""

    private var codeEntryView: some View {
        VStack(spacing: 10) {
            Text("Paste Authorization Code")
                .font(.headline)

            Text("A browser window opened. After authorizing, paste the code below.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            HStack {
                TextField("code#state", text: $codeInput)
                    .textFieldStyle(.roundedBorder)

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
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    // MARK: - Usage View

    private var usageView: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header
            HStack {
                Text("Claude Usage")
                    .font(.headline)

                Text(service.isPeakHours ? "PEAK" : "OFF-PEAK")
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(service.isPeakHours ? Color.orange.opacity(0.2) : Color.blue.opacity(0.15))
                    .foregroundStyle(service.isPeakHours ? .orange : .blue)
                    .clipShape(Capsule())

                Spacer()
                if let email = service.accountEmail {
                    Text(email)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Divider()

            // 5-hour bucket
            if let bucket = service.usage?.fiveHour {
                UsageBucketRow(label: "5-Hour", bucket: bucket, etaHours: service.eta5hHours, willExceed: service.willExceed5h)
            }

            // 7-day bucket
            if let bucket = service.usage?.sevenDay {
                UsageBucketRow(label: "7-Day", bucket: bucket, etaHours: service.eta7dHours, willExceed: service.willExceed7d)
            }

            // Usage history chart
            if service.usageHistory.count >= 2 {
                Divider()
                UsageHistoryChart(history: service.usageHistory)
            }

            // Model breakdown
            if service.usage?.sevenDayOpus != nil || service.usage?.sevenDaySonnet != nil {
                Divider()
                Text("Per-Model (7-Day)")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let opus = service.usage?.sevenDayOpus {
                    UsageBucketRow(label: "Opus", bucket: opus)
                }
                if let sonnet = service.usage?.sevenDaySonnet {
                    UsageBucketRow(label: "Sonnet", bucket: sonnet)
                }
            }

            // Extra usage
            if let extra = service.usage?.extraUsage, extra.isEnabled {
                Divider()
                ExtraUsageRow(extra: extra)
            }

            Divider()

            // Footer
            HStack {
                if let lastUpdated = service.lastUpdated {
                    Text("Updated \(lastUpdated, style: .relative) ago")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                Spacer()

                Button {
                    Task { await service.fetchUsage() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .controlSize(.small)

                // Polling interval picker
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
                }
                .menuStyle(.borderlessButton)
                .frame(width: 20)

                Button("Sign Out") {
                    service.signOut()
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .foregroundStyle(.secondary)

                Button {
                    NSApplication.shared.terminate(nil)
                } label: {
                    Image(systemName: "xmark.circle")
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .foregroundStyle(.secondary)
                .help("Quit")
            }

            if let error = service.lastError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
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

    private var barColor: Color {
        if pct >= 0.9 { return .red }
        if pct >= 0.7 { return .orange }
        return .green
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .font(.subheadline.weight(.medium))
                Spacer()
                Text("\(Int(round(pct * 100)))%")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(barColor)
            }

            ProgressView(value: min(pct, 1.0))
                .tint(barColor)

            HStack(spacing: 0) {
                if let reset = bucket.resetsAtDate {
                    Text("Resets \(reset, style: .relative)")
                        .foregroundStyle(.tertiary)
                }

                if let eta = etaHours {
                    if bucket.resetsAtDate != nil { Text(" · ").foregroundStyle(.tertiary) }
                    Text(eta <= 0 ? "At limit" : "~\(Self.formatEta(eta)) to full")
                        .foregroundStyle(willExceed ? .orange : .secondary)
                }
            }
            .font(.caption2)

            if willExceed {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill")
                    Text("Will hit limit before reset")
                }
                .font(.caption2)
                .foregroundStyle(.orange)
            }
        }
    }

    static func formatEta(_ hours: Double) -> String {
        if hours < 1 {
            return "\(max(1, Int(round(hours * 60)))) min"
        } else if hours < 24 {
            return String(format: "%.1f hrs", hours)
        } else {
            return String(format: "%.1f days", hours / 24)
        }
    }
}

// MARK: - Extra Usage Row

struct ExtraUsageRow: View {
    let extra: ExtraUsage

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Extra Usage")
                    .font(.subheadline.weight(.medium))
                Spacer()
                if let used = extra.usedCreditsAmount {
                    Text(ExtraUsage.formatUSD(used))
                        .font(.subheadline.monospacedDigit())
                }
            }

            if let used = extra.usedCreditsAmount, let limit = extra.monthlyLimitAmount, limit > 0 {
                ProgressView(value: min(used / limit, 1.0))
                    .tint(.blue)

                Text("\(ExtraUsage.formatUSD(used)) / \(ExtraUsage.formatUSD(limit))")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

// MARK: - Usage History Chart

private struct ChartPoint: Identifiable {
    let id: String
    let date: Date
    let pct: Double
    let series: String
}

struct UsageHistoryChart: View {
    let history: [UsageSnapshot]

    private var chartData: [ChartPoint] {
        history.flatMap { entry in
            [
                ChartPoint(id: "5h-\(entry.date.timeIntervalSince1970)", date: entry.date, pct: entry.pct5h * 100, series: "5h"),
                ChartPoint(id: "7d-\(entry.date.timeIntervalSince1970)", date: entry.date, pct: entry.pct7d * 100, series: "7d"),
            ]
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Past 6 Hours")
                .font(.caption)
                .foregroundStyle(.secondary)

            Chart(chartData) { point in
                LineMark(
                    x: .value("Time", point.date),
                    y: .value("Usage", point.pct)
                )
                .foregroundStyle(by: .value("Bucket", point.series))
                .interpolationMethod(.monotone)
            }
            .chartYScale(domain: 0...100)
            .chartYAxis {
                AxisMarks(values: [0, 25, 50, 75, 100]) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2]))
                    AxisValueLabel {
                        if let v = value.as(Int.self) {
                            Text("\(v)%")
                                .font(.caption2)
                        }
                    }
                }
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                    AxisGridLine()
                    AxisValueLabel(format: .dateTime.hour().minute())
                }
            }
            .chartForegroundStyleScale([
                "5h": Color.green,
                "7d": Color.blue,
            ])
            .chartLegend(position: .top, alignment: .trailing)
            .frame(height: 100)
        }
    }
}
