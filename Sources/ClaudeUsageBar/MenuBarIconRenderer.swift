import AppKit

private let labelWidth: CGFloat = 14
private let barWidth: CGFloat = 24
private let barHeight: CGFloat = 6
private let barSpacing: CGFloat = 2
private let iconHeight: CGFloat = 18
private let sectionGap: CGFloat = 4

private struct CachedLabel {
    let string: NSAttributedString
    let size: CGSize
}

private let cachedLabels: [String: CachedLabel] = {
    let font = NSFont.monospacedSystemFont(ofSize: 8, weight: .medium)
    var result: [String: CachedLabel] = [:]
    for label in ["5h", "7d"] {
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.white]
        let str = NSAttributedString(string: label, attributes: attrs)
        let size = str.size()
        result[label] = CachedLabel(string: str, size: size)
    }
    return result
}()

func renderIcon(pct5h: Double, pct7d: Double) -> NSImage {
    let totalWidth = labelWidth + barWidth + sectionGap + labelWidth + barWidth
    let size = NSSize(width: totalWidth, height: iconHeight)
    let image = NSImage(size: size, flipped: false) { rect in
        let yCenter = rect.midY

        // 5h section
        var x: CGFloat = 0
        if let label = cachedLabels["5h"] {
            let labelY = yCenter - label.size.height / 2
            label.string.draw(at: NSPoint(x: x, y: labelY))
        }
        x += labelWidth
        drawBar(at: NSPoint(x: x, y: yCenter + barSpacing / 2), width: barWidth, height: barHeight, fill: pct5h)

        // 7d section
        x += barWidth + sectionGap
        if let label = cachedLabels["7d"] {
            let labelY = yCenter - label.size.height / 2
            label.string.draw(at: NSPoint(x: x, y: labelY))
        }
        x += labelWidth
        drawBar(at: NSPoint(x: x, y: yCenter + barSpacing / 2), width: barWidth, height: barHeight, fill: pct7d)

        return true
    }
    image.isTemplate = true
    return image
}

func renderUnauthenticatedIcon() -> NSImage {
    let totalWidth = labelWidth + barWidth + sectionGap + labelWidth + barWidth
    let size = NSSize(width: totalWidth, height: iconHeight)
    let image = NSImage(size: size, flipped: false) { rect in
        let yCenter = rect.midY
        var x: CGFloat = 0
        if let label = cachedLabels["5h"] {
            let labelY = yCenter - label.size.height / 2
            label.string.draw(at: NSPoint(x: x, y: labelY))
        }
        x += labelWidth
        drawDashedBar(at: NSPoint(x: x, y: yCenter + barSpacing / 2), width: barWidth, height: barHeight)

        x += barWidth + sectionGap
        if let label = cachedLabels["7d"] {
            let labelY = yCenter - label.size.height / 2
            label.string.draw(at: NSPoint(x: x, y: labelY))
        }
        x += labelWidth
        drawDashedBar(at: NSPoint(x: x, y: yCenter + barSpacing / 2), width: barWidth, height: barHeight)

        return true
    }
    image.isTemplate = true
    return image
}

private func drawBar(at origin: NSPoint, width: CGFloat, height: CGFloat, fill: Double) {
    let bgRect = NSRect(x: origin.x, y: origin.y, width: width, height: height)
    let bgPath = NSBezierPath(roundedRect: bgRect, xRadius: 2, yRadius: 2)
    NSColor.white.withAlphaComponent(0.3).setFill()
    bgPath.fill()

    let fillWidth = max(0, min(1, fill)) * width
    if fillWidth > 0 {
        let fillRect = NSRect(x: origin.x, y: origin.y, width: fillWidth, height: height)
        let fillPath = NSBezierPath(roundedRect: fillRect, xRadius: 2, yRadius: 2)
        NSColor.white.setFill()
        fillPath.fill()
    }
}

private func drawDashedBar(at origin: NSPoint, width: CGFloat, height: CGFloat) {
    let rect = NSRect(x: origin.x, y: origin.y, width: width, height: height)
    let path = NSBezierPath(roundedRect: rect, xRadius: 2, yRadius: 2)
    let dashPattern: [CGFloat] = [3, 2]
    path.setLineDash(dashPattern, count: 2, phase: 0)
    NSColor.white.withAlphaComponent(0.5).setStroke()
    path.lineWidth = 1
    path.stroke()
}
