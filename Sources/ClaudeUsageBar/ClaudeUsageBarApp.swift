import SwiftUI

@main
struct ClaudeUsageBarApp: App {
    @StateObject private var service = UsageService()

    var body: some Scene {
        MenuBarExtra {
            PopoverView(service: service)
        } label: {
            Image(nsImage: service.isAuthenticated
                ? renderMenuBarIcon(pct5h: service.pct5h, pct7d: service.pct7d)
                : renderMenuBarIconUnauthenticated()
            )
            .task { service.startPolling() }
        }
        .menuBarExtraStyle(.window)
    }
}

// MARK: - Two-Row Compact Menu Bar Icon

private let iconHeight: CGFloat = 20
private let barW: CGFloat = 36
private let barH: CGFloat = 7
private let rowGap: CGFloat = 2
private let labelBarGap: CGFloat = 2.5
private let barPctGap: CGFloat = 2

private func renderMenuBarIcon(pct5h: Double, pct7d: Double) -> NSImage {
    let labelFont = NSFont.monospacedDigitSystemFont(ofSize: 7.5, weight: .semibold)
    let pctFont = NSFont.monospacedDigitSystemFont(ofSize: 7, weight: .medium)
    let labelAttrs: [NSAttributedString.Key: Any] = [
        .font: labelFont,
        .foregroundColor: NSColor.labelColor.withAlphaComponent(0.85),
    ]
    let pctAttrs: [NSAttributedString.Key: Any] = [
        .font: pctFont,
        .foregroundColor: NSColor.labelColor.withAlphaComponent(0.7),
    ]

    let label5h = NSAttributedString(string: "5h", attributes: labelAttrs)
    let label7d = NSAttributedString(string: "7d", attributes: labelAttrs)
    let pct5Str = NSAttributedString(string: "\(Int(round(pct5h * 100)))%", attributes: pctAttrs)
    let pct7Str = NSAttributedString(string: "\(Int(round(pct7d * 100)))%", attributes: pctAttrs)

    let labelW = max(label5h.size().width, label7d.size().width)
    let pctW = max(pct5Str.size().width, pct7Str.size().width)
    let totalWidth = labelW + labelBarGap + barW + barPctGap + pctW

    let size = NSSize(width: ceil(totalWidth), height: iconHeight)

    let image = NSImage(size: size, flipped: false) { _ in
        let topRowY = (iconHeight / 2) + (rowGap / 2)
        let botRowY = (iconHeight / 2) - rowGap / 2 - barH

        // Top row: 5h
        drawRow(
            y: topRowY, labelW: labelW, pctW: pctW,
            label: label5h, pctLabel: pct5Str, pct: pct5h
        )

        // Bottom row: 7d
        drawRow(
            y: botRowY, labelW: labelW, pctW: pctW,
            label: label7d, pctLabel: pct7Str, pct: pct7d
        )

        return true
    }
    image.isTemplate = false
    return image
}

private func renderMenuBarIconUnauthenticated() -> NSImage {
    let labelFont = NSFont.monospacedDigitSystemFont(ofSize: 7.5, weight: .semibold)
    let pctFont = NSFont.monospacedDigitSystemFont(ofSize: 7, weight: .medium)
    let labelAttrs: [NSAttributedString.Key: Any] = [
        .font: labelFont,
        .foregroundColor: NSColor.labelColor.withAlphaComponent(0.5),
    ]
    let pctAttrs: [NSAttributedString.Key: Any] = [
        .font: pctFont,
        .foregroundColor: NSColor.labelColor.withAlphaComponent(0.35),
    ]

    let label5h = NSAttributedString(string: "5h", attributes: labelAttrs)
    let label7d = NSAttributedString(string: "7d", attributes: labelAttrs)
    let dash = NSAttributedString(string: "--%", attributes: pctAttrs)

    let labelW = max(label5h.size().width, label7d.size().width)
    let pctW = dash.size().width
    let totalWidth = labelW + labelBarGap + barW + barPctGap + pctW

    let size = NSSize(width: ceil(totalWidth), height: iconHeight)

    let image = NSImage(size: size, flipped: false) { _ in
        let topRowY = (iconHeight / 2) + (rowGap / 2)
        let botRowY = (iconHeight / 2) - rowGap / 2 - barH

        drawRowEmpty(y: topRowY, labelW: labelW, pctW: pctW, label: label5h, pctLabel: dash)
        drawRowEmpty(y: botRowY, labelW: labelW, pctW: pctW, label: label7d, pctLabel: dash)

        return true
    }
    image.isTemplate = false
    return image
}

private func drawRow(y: CGFloat, labelW: CGFloat, pctW: CGFloat, label: NSAttributedString, pctLabel: NSAttributedString, pct: Double) {
    var x: CGFloat = 0
    let labelSize = label.size()
    let cy = y + barH / 2

    // Label (right-aligned within labelW)
    label.draw(at: NSPoint(x: x + labelW - labelSize.width, y: cy - labelSize.height / 2))
    x += labelW + labelBarGap

    // Bar track
    let barRect = NSRect(x: x, y: y, width: barW, height: barH)
    let trackPath = NSBezierPath(roundedRect: barRect, xRadius: barH / 2, yRadius: barH / 2)
    NSColor.labelColor.withAlphaComponent(0.1).setFill()
    trackPath.fill()

    // Bar fill with gradient
    let fillWidth = max(0, min(1, pct)) * barW
    if fillWidth > 1 {
        let fillRect = NSRect(x: x, y: y, width: fillWidth, height: barH)

        NSGraphicsContext.current?.saveGraphicsState()
        let clipPath = NSBezierPath(roundedRect: fillRect, xRadius: barH / 2, yRadius: barH / 2)
        clipPath.addClip()

        let (startColor, endColor) = gradientColors(for: pct)
        let gradient = NSGradient(starting: startColor, ending: endColor)!
        gradient.draw(in: fillRect, angle: 0)

        NSGraphicsContext.current?.restoreGraphicsState()
    }
    x += barW + barPctGap

    // Percentage
    let pctSize = pctLabel.size()
    pctLabel.draw(at: NSPoint(x: x, y: cy - pctSize.height / 2))
}

private func drawRowEmpty(y: CGFloat, labelW: CGFloat, pctW: CGFloat, label: NSAttributedString, pctLabel: NSAttributedString) {
    var x: CGFloat = 0
    let labelSize = label.size()
    let cy = y + barH / 2

    label.draw(at: NSPoint(x: x + labelW - labelSize.width, y: cy - labelSize.height / 2))
    x += labelW + labelBarGap

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
            NSColor(red: 1.0, green: 0.65, blue: 0.0, alpha: 1),
            NSColor(red: 0.95, green: 0.45, blue: 0.0, alpha: 1)
        )
    }
    return (
        NSColor(red: 0.25, green: 0.78, blue: 0.5, alpha: 1),
        NSColor(red: 0.15, green: 0.65, blue: 0.55, alpha: 1)
    )
}
