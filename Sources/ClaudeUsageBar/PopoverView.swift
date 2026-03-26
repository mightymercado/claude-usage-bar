import SwiftUI

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
                UsageBucketRow(label: "5-Hour", bucket: bucket)
            }

            // 7-day bucket
            if let bucket = service.usage?.sevenDay {
                UsageBucketRow(label: "7-Day", bucket: bucket)
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

            if let reset = bucket.resetsAtDate {
                Text("Resets \(reset, style: .relative)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
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
