import SwiftUI

@main
struct ClaudeUsageBarApp: App {
    @StateObject private var service = UsageService()

    var body: some Scene {
        MenuBarExtra {
            PopoverView(service: service)
        } label: {
            Image(nsImage: service.isAuthenticated
                ? renderMenuBarIcon(pct5h: service.pct5h, pct7d: service.pct7d, willExceed5h: service.willExceed5h, willExceed7d: service.willExceed7d, ytdCost: service.tokenStats?.totalCost)
                : renderMenuBarIconUnauthenticated()
            )
            .task { service.startPolling() }
        }
        .menuBarExtraStyle(.window)
    }
}

// MARK: - Menu Bar Icon (Finance Style)

private let iconHeight: CGFloat = 22
private let barW: CGFloat = 40
private let barH: CGFloat = 7
private let rowGap: CGFloat = 2
private let barPctGap: CGFloat = 2

private func renderMenuBarIcon(pct5h: Double, pct7d: Double, willExceed5h: Bool = false, willExceed7d: Bool = false, ytdCost: Double? = nil) -> NSImage {
    // Rounded bold font for percentages
    let pctFont = NSFont.systemFont(ofSize: 8, weight: .heavy)
        .withDesign(.rounded) ?? NSFont.monospacedDigitSystemFont(ofSize: 8, weight: .heavy)
    let (_, pct5Color) = gradientColors(for: pct5h)
    let (_, pct7Color) = gradientColors(for: pct7d)

    let pct5Str = NSAttributedString(string: "\(Int(round(pct5h * 100)))%", attributes: [
        .font: pctFont,
        .foregroundColor: pct5Color,
    ])
    let pct7Str = NSAttributedString(string: "\(Int(round(pct7d * 100)))%", attributes: [
        .font: pctFont,
        .foregroundColor: pct7Color,
    ])
    let pctW = max(pct5Str.size().width, pct7Str.size().width)

    // Cost label — big bold rounded
    let costGap: CGFloat = 5
    let costFont = NSFont.systemFont(ofSize: 12, weight: .heavy)
        .withDesign(.rounded) ?? NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .heavy)
    let costStr: NSAttributedString?
    if let cost = ytdCost, cost > 0.01 {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.maximumFractionDigits = 0
        let text = formatter.string(from: NSNumber(value: cost)) ?? String(format: "$%.0f", cost)
        // Green color for the cost
        costStr = NSAttributedString(string: text, attributes: [
            .font: costFont,
            .foregroundColor: NSColor(red: 0.15, green: 0.78, blue: 0.42, alpha: 1),
        ])
    } else {
        costStr = nil
    }
    let costW = costStr?.size().width ?? 0

    let totalWidth = barW + barPctGap + pctW + (costStr != nil ? costGap + costW : 0)
    let size = NSSize(width: ceil(totalWidth), height: iconHeight)

    let image = NSImage(size: size, flipped: false) { _ in
        let topRowY = (iconHeight / 2) + (rowGap / 2)
        let botRowY = (iconHeight / 2) - rowGap / 2 - barH

        drawRow(y: topRowY, pctW: pctW, pctLabel: pct5Str, pct: pct5h, willExceed: willExceed5h)
        drawRow(y: botRowY, pctW: pctW, pctLabel: pct7Str, pct: pct7d, willExceed: willExceed7d)

        if let costStr {
            let costSize = costStr.size()
            let costX = barW + barPctGap + pctW + costGap
            let costY = (iconHeight - costSize.height) / 2
            costStr.draw(at: NSPoint(x: costX, y: costY))
        }

        return true
    }
    image.isTemplate = false
    return image
}

private func renderMenuBarIconUnauthenticated() -> NSImage {
    let pctFont = NSFont.systemFont(ofSize: 8, weight: .heavy)
        .withDesign(.rounded) ?? NSFont.monospacedDigitSystemFont(ofSize: 8, weight: .heavy)
    let pctAttrs: [NSAttributedString.Key: Any] = [
        .font: pctFont,
        .foregroundColor: NSColor.labelColor.withAlphaComponent(0.3),
    ]

    let dash = NSAttributedString(string: "--%", attributes: pctAttrs)
    let pctW = dash.size().width
    let totalWidth = barW + barPctGap + pctW

    let size = NSSize(width: ceil(totalWidth), height: iconHeight)

    let image = NSImage(size: size, flipped: false) { _ in
        let topRowY = (iconHeight / 2) + (rowGap / 2)
        let botRowY = (iconHeight / 2) - rowGap / 2 - barH

        drawRowEmpty(y: topRowY, pctW: pctW, pctLabel: dash)
        drawRowEmpty(y: botRowY, pctW: pctW, pctLabel: dash)

        return true
    }
    image.isTemplate = false
    return image
}

// MARK: - Drawing Helpers

private func drawRow(y: CGFloat, pctW: CGFloat, pctLabel: NSAttributedString, pct: Double, willExceed: Bool = false) {
    var x: CGFloat = 0
    let cy = y + barH / 2

    // Track
    let barRect = NSRect(x: x, y: y, width: barW, height: barH)
    let trackPath = NSBezierPath(roundedRect: barRect, xRadius: barH / 2, yRadius: barH / 2)
    let trackColor = willExceed
        ? NSColor(red: 0.9, green: 0.2, blue: 0.2, alpha: 0.15)
        : NSColor.labelColor.withAlphaComponent(0.1)
    trackColor.setFill()
    trackPath.fill()

    // Fill gradient
    let fillWidth = max(0, min(1, pct)) * barW
    if fillWidth > 1 {
        let fillRect = NSRect(x: x, y: y, width: fillWidth, height: barH)
        NSGraphicsContext.current?.saveGraphicsState()
        let clipPath = NSBezierPath(roundedRect: fillRect, xRadius: barH / 2, yRadius: barH / 2)
        clipPath.addClip()
        let (startColor, endColor) = willExceed
            ? (NSColor(red: 0.95, green: 0.25, blue: 0.2, alpha: 1),
               NSColor(red: 0.85, green: 0.15, blue: 0.25, alpha: 1))
            : gradientColors(for: pct)
        let gradient = NSGradient(starting: startColor, ending: endColor)!
        gradient.draw(in: fillRect, angle: 0)
        NSGraphicsContext.current?.restoreGraphicsState()
    }

    x += barW + barPctGap

    // Percentage label
    let pctSize = pctLabel.size()
    pctLabel.draw(at: NSPoint(x: x, y: cy - pctSize.height / 2))
}

private func drawRowEmpty(y: CGFloat, pctW: CGFloat, pctLabel: NSAttributedString) {
    var x: CGFloat = 0
    let cy = y + barH / 2

    let barRect = NSRect(x: x, y: y, width: barW, height: barH)
    let trackPath = NSBezierPath(roundedRect: barRect, xRadius: barH / 2, yRadius: barH / 2)
    NSColor.labelColor.withAlphaComponent(0.08).setFill()
    trackPath.fill()
    x += barW + barPctGap

    let pctSize = pctLabel.size()
    pctLabel.draw(at: NSPoint(x: x, y: cy - pctSize.height / 2))
}

private func gradientColors(for pct: Double) -> (NSColor, NSColor) {
    if pct >= 0.9 {
        return (
            NSColor(red: 0.95, green: 0.25, blue: 0.2, alpha: 1),
            NSColor(red: 0.85, green: 0.15, blue: 0.25, alpha: 1)
        )
    }
    if pct >= 0.7 {
        return (
            NSColor(red: 1.0, green: 0.58, blue: 0.0, alpha: 1),
            NSColor(red: 0.95, green: 0.42, blue: 0.0, alpha: 1)
        )
    }
    return (
        NSColor(red: 0.15, green: 0.82, blue: 0.45, alpha: 1),
        NSColor(red: 0.08, green: 0.65, blue: 0.4, alpha: 1)
    )
}

// MARK: - NSFont Rounded Helper

extension NSFont {
    func withDesign(_ design: NSFontDescriptor.SystemDesign) -> NSFont? {
        guard let descriptor = fontDescriptor.withDesign(design) else { return nil }
        return NSFont(descriptor: descriptor, size: pointSize)
    }
}
