import AppKit
import Foundation

struct Theme {
    let name: String
    let backgroundTop: NSColor
    let backgroundBottom: NSColor
    let atmosphere: NSColor
    let outerTop: NSColor
    let outerBottom: NSColor
    let lowerTop: NSColor
    let lowerBottom: NSColor
    let innerTop: NSColor
    let innerBottom: NSColor
    let outline: NSColor
    let rimLight: NSColor
    let softShadow: NSColor
}

let canvasSize = NSSize(width: 1024, height: 1024)
let repoRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let imagesetURL = repoRoot
    .appendingPathComponent("antios10/Assets.xcassets/WaterDropLogo.imageset", isDirectory: true)
let previewURL = repoRoot
    .appendingPathComponent("design/ios26-logo-preview", isDirectory: true)

func color(_ hex: Int, alpha: CGFloat = 1.0) -> NSColor {
    let red = CGFloat((hex >> 16) & 0xff) / 255.0
    let green = CGFloat((hex >> 8) & 0xff) / 255.0
    let blue = CGFloat(hex & 0xff) / 255.0
    return NSColor(calibratedRed: red, green: green, blue: blue, alpha: alpha)
}

func point(in rect: NSRect, _ x: CGFloat, _ y: CGFloat) -> NSPoint {
    NSPoint(x: rect.minX + rect.width * x, y: rect.minY + rect.height * y)
}

func fillBlurredEllipse(in rect: NSRect, color: NSColor, blur: CGFloat) {
    let shadow = NSShadow()
    shadow.shadowBlurRadius = blur
    shadow.shadowOffset = .zero
    shadow.shadowColor = color

    NSGraphicsContext.saveGraphicsState()
    shadow.set()
    color.setFill()
    NSBezierPath(ovalIn: rect).fill()
    NSGraphicsContext.restoreGraphicsState()
}

func outerDropletPath(in rect: NSRect) -> NSBezierPath {
    let path = NSBezierPath()
    path.move(to: point(in: rect, 0.52, 0.96))
    path.curve(
        to: point(in: rect, 0.20, 0.42),
        controlPoint1: point(in: rect, 0.44, 0.82),
        controlPoint2: point(in: rect, 0.23, 0.60)
    )
    path.curve(
        to: point(in: rect, 0.36, 0.11),
        controlPoint1: point(in: rect, 0.16, 0.29),
        controlPoint2: point(in: rect, 0.21, 0.12)
    )
    path.curve(
        to: point(in: rect, 0.70, 0.09),
        controlPoint1: point(in: rect, 0.49, 0.02),
        controlPoint2: point(in: rect, 0.62, 0.01)
    )
    path.curve(
        to: point(in: rect, 0.82, 0.32),
        controlPoint1: point(in: rect, 0.79, 0.12),
        controlPoint2: point(in: rect, 0.88, 0.23)
    )
    path.curve(
        to: point(in: rect, 0.73, 0.64),
        controlPoint1: point(in: rect, 0.78, 0.42),
        controlPoint2: point(in: rect, 0.80, 0.56)
    )
    path.curve(
        to: point(in: rect, 0.52, 0.96),
        controlPoint1: point(in: rect, 0.64, 0.75),
        controlPoint2: point(in: rect, 0.55, 0.89)
    )
    path.close()
    return path
}

func lowerWavePath(in rect: NSRect) -> NSBezierPath {
    let path = NSBezierPath()
    path.move(to: point(in: rect, 0.42, 0.47))
    path.curve(
        to: point(in: rect, 0.73, 0.56),
        controlPoint1: point(in: rect, 0.51, 0.63),
        controlPoint2: point(in: rect, 0.69, 0.66)
    )
    path.curve(
        to: point(in: rect, 0.83, 0.38),
        controlPoint1: point(in: rect, 0.86, 0.50),
        controlPoint2: point(in: rect, 0.89, 0.41)
    )
    path.curve(
        to: point(in: rect, 0.72, 0.17),
        controlPoint1: point(in: rect, 0.78, 0.25),
        controlPoint2: point(in: rect, 0.80, 0.14)
    )
    path.curve(
        to: point(in: rect, 0.40, 0.18),
        controlPoint1: point(in: rect, 0.62, 0.10),
        controlPoint2: point(in: rect, 0.49, 0.11)
    )
    path.curve(
        to: point(in: rect, 0.29, 0.33),
        controlPoint1: point(in: rect, 0.34, 0.22),
        controlPoint2: point(in: rect, 0.28, 0.26)
    )
    path.curve(
        to: point(in: rect, 0.42, 0.47),
        controlPoint1: point(in: rect, 0.31, 0.40),
        controlPoint2: point(in: rect, 0.36, 0.46)
    )
    path.close()
    return path
}

func innerPocketPath(in rect: NSRect) -> NSBezierPath {
    let path = NSBezierPath()
    path.move(to: point(in: rect, 0.52, 0.81))
    path.curve(
        to: point(in: rect, 0.35, 0.58),
        controlPoint1: point(in: rect, 0.49, 0.72),
        controlPoint2: point(in: rect, 0.40, 0.67)
    )
    path.curve(
        to: point(in: rect, 0.47, 0.43),
        controlPoint1: point(in: rect, 0.30, 0.51),
        controlPoint2: point(in: rect, 0.33, 0.43)
    )
    path.curve(
        to: point(in: rect, 0.66, 0.54),
        controlPoint1: point(in: rect, 0.58, 0.43),
        controlPoint2: point(in: rect, 0.68, 0.47)
    )
    path.curve(
        to: point(in: rect, 0.52, 0.81),
        controlPoint1: point(in: rect, 0.62, 0.66),
        controlPoint2: point(in: rect, 0.56, 0.75)
    )
    path.close()
    return path
}

func glossStrokePath(in rect: NSRect) -> NSBezierPath {
    let path = NSBezierPath()
    path.move(to: point(in: rect, 0.37, 0.80))
    path.curve(
        to: point(in: rect, 0.29, 0.44),
        controlPoint1: point(in: rect, 0.31, 0.69),
        controlPoint2: point(in: rect, 0.24, 0.59)
    )
    return path
}

func crestStrokePath(in rect: NSRect) -> NSBezierPath {
    let path = NSBezierPath()
    path.move(to: point(in: rect, 0.53, 0.90))
    path.curve(
        to: point(in: rect, 0.68, 0.58),
        controlPoint1: point(in: rect, 0.58, 0.80),
        controlPoint2: point(in: rect, 0.70, 0.69)
    )
    return path
}

func innerArcStrokePath(in rect: NSRect) -> NSBezierPath {
    let path = NSBezierPath()
    path.move(to: point(in: rect, 0.34, 0.38))
    path.curve(
        to: point(in: rect, 0.72, 0.30),
        controlPoint1: point(in: rect, 0.45, 0.28),
        controlPoint2: point(in: rect, 0.60, 0.22)
    )
    return path
}

func pngData(from image: NSImage) -> Data? {
    guard let tiff = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff) else {
        return nil
    }
    return bitmap.representation(using: .png, properties: [:])
}

func writePNG(_ image: NSImage, to url: URL) throws {
    guard let data = pngData(from: image) else {
        throw NSError(domain: "logo-export", code: 1, userInfo: [NSLocalizedDescriptionKey: "PNG export failed"])
    }
    try data.write(to: url)
}

func render(theme: Theme) throws -> NSImage {
    let image = NSImage(size: canvasSize)
    image.lockFocus()

    let fullRect = NSRect(origin: .zero, size: canvasSize)
    let background = NSGradient(starting: theme.backgroundTop, ending: theme.backgroundBottom)
    background?.draw(in: fullRect, angle: -90)

    fillBlurredEllipse(
        in: NSRect(x: 212, y: 200, width: 600, height: 570),
        color: theme.atmosphere.withAlphaComponent(0.18),
        blur: 88
    )
    fillBlurredEllipse(
        in: NSRect(x: 308, y: 650, width: 230, height: 190),
        color: theme.rimLight.withAlphaComponent(0.10),
        blur: 42
    )
    fillBlurredEllipse(
        in: NSRect(x: 175, y: 92, width: 674, height: 120),
        color: theme.softShadow,
        blur: 32
    )

    let dropletRect = NSRect(x: 214, y: 135, width: 600, height: 760)
    let outer = outerDropletPath(in: dropletRect)
    let lower = lowerWavePath(in: dropletRect)
    let inner = innerPocketPath(in: dropletRect)

    let dropShadow = NSShadow()
    dropShadow.shadowBlurRadius = 38
    dropShadow.shadowOffset = NSSize(width: 0, height: -22)
    dropShadow.shadowColor = theme.softShadow
    NSGraphicsContext.saveGraphicsState()
    dropShadow.set()
    color(0x000000, alpha: 0.01).setFill()
    outer.fill()
    NSGraphicsContext.restoreGraphicsState()

    NSGraphicsContext.saveGraphicsState()
    outer.addClip()
    let outerGradient = NSGradient(starting: theme.outerTop, ending: theme.outerBottom)
    outerGradient?.draw(in: outer.bounds, angle: -90)
    fillBlurredEllipse(
        in: NSRect(x: dropletRect.minX + 86, y: dropletRect.minY + 378, width: 254, height: 268),
        color: color(0xFFFFFF, alpha: 0.14),
        blur: 24
    )
    fillBlurredEllipse(
        in: NSRect(x: dropletRect.minX + 66, y: dropletRect.minY + 470, width: 118, height: 226),
        color: color(0xFFFFFF, alpha: 0.18),
        blur: 18
    )
    fillBlurredEllipse(
        in: NSRect(x: dropletRect.minX + 245, y: dropletRect.minY + 146, width: 228, height: 202),
        color: theme.atmosphere.withAlphaComponent(0.13),
        blur: 22
    )
    NSGraphicsContext.restoreGraphicsState()

    NSGraphicsContext.saveGraphicsState()
    lower.addClip()
    let lowerGradient = NSGradient(starting: theme.lowerTop, ending: theme.lowerBottom)
    lowerGradient?.draw(in: lower.bounds, angle: -60)
    fillBlurredEllipse(
        in: NSRect(x: dropletRect.minX + 260, y: dropletRect.minY + 195, width: 160, height: 120),
        color: color(0xFFFFFF, alpha: 0.12),
        blur: 18
    )
    NSGraphicsContext.restoreGraphicsState()

    NSGraphicsContext.saveGraphicsState()
    inner.addClip()
    let innerGradient = NSGradient(starting: theme.innerTop, ending: theme.innerBottom)
    innerGradient?.draw(in: inner.bounds, angle: -90)
    fillBlurredEllipse(
        in: NSRect(x: dropletRect.minX + 160, y: dropletRect.minY + 430, width: 170, height: 220),
        color: color(0xFFFFFF, alpha: 0.14),
        blur: 16
    )
    NSGraphicsContext.restoreGraphicsState()

    theme.outline.setStroke()
    outer.lineWidth = 8
    outer.lineJoinStyle = .round
    outer.stroke()

    let echo = outerDropletPath(in: dropletRect.insetBy(dx: 34, dy: 52))
    theme.rimLight.withAlphaComponent(0.18).setStroke()
    echo.lineWidth = 5
    echo.lineJoinStyle = .round
    echo.stroke()

    theme.outline.withAlphaComponent(0.62).setStroke()
    lower.lineWidth = 6
    lower.lineJoinStyle = .round
    lower.stroke()

    theme.outline.withAlphaComponent(0.52).setStroke()
    inner.lineWidth = 5
    inner.lineJoinStyle = .round
    inner.stroke()

    let gloss = glossStrokePath(in: dropletRect)
    gloss.lineWidth = 12
    gloss.lineCapStyle = .round
    theme.rimLight.withAlphaComponent(0.64).setStroke()
    gloss.stroke()

    let crest = crestStrokePath(in: dropletRect)
    crest.lineWidth = 9
    crest.lineCapStyle = .round
    theme.rimLight.withAlphaComponent(0.30).setStroke()
    crest.stroke()

    let innerArc = innerArcStrokePath(in: dropletRect)
    innerArc.lineWidth = 8
    innerArc.lineCapStyle = .round
    theme.rimLight.withAlphaComponent(0.26).setStroke()
    innerArc.stroke()

    fillBlurredEllipse(
        in: NSRect(x: dropletRect.minX + 184, y: dropletRect.minY + 28, width: 246, height: 38),
        color: theme.rimLight.withAlphaComponent(0.07),
        blur: 10
    )

    image.unlockFocus()
    return image
}

func buildPreview(light: NSImage, dark: NSImage) throws -> NSImage {
    let previewSize = NSSize(width: 2240, height: 1260)
    let image = NSImage(size: previewSize)
    image.lockFocus()

    let leftRect = NSRect(x: 0, y: 0, width: 1120, height: 1260)
    let rightRect = NSRect(x: 1120, y: 0, width: 1120, height: 1260)

    let leftGradient = NSGradient(starting: color(0xFAFDFF), ending: color(0xE9F5FB))
    leftGradient?.draw(in: leftRect, angle: -90)

    let rightGradient = NSGradient(starting: color(0x051118), ending: color(0x0C2733))
    rightGradient?.draw(in: rightRect, angle: -90)

    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .center

    let titleAttrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 42, weight: .semibold),
        .paragraphStyle: paragraph
    ]
    let leftAttrs = titleAttrs.merging([.foregroundColor: color(0x174154)], uniquingKeysWith: { _, new in new })
    let rightAttrs = titleAttrs.merging([.foregroundColor: color(0xDAFBFF)], uniquingKeysWith: { _, new in new })

    NSString(string: "iOS 26 Light").draw(in: NSRect(x: 240, y: 1090, width: 640, height: 54), withAttributes: leftAttrs)
    NSString(string: "iOS 26 Dark").draw(in: NSRect(x: 1360, y: 1090, width: 640, height: 54), withAttributes: rightAttrs)

    light.draw(in: NSRect(x: 178, y: 120, width: 764, height: 764))
    dark.draw(in: NSRect(x: 1298, y: 120, width: 764, height: 764))

    image.unlockFocus()
    return image
}

let lightTheme = Theme(
    name: "light",
    backgroundTop: color(0xF8FDFF),
    backgroundBottom: color(0xE7F4FA),
    atmosphere: color(0x41D6F4),
    outerTop: color(0xD9FFFF, alpha: 0.92),
    outerBottom: color(0x0B91A9, alpha: 0.96),
    lowerTop: color(0x50E7FB, alpha: 0.94),
    lowerBottom: color(0x08758E, alpha: 0.96),
    innerTop: color(0xF0FFFF, alpha: 0.88),
    innerBottom: color(0x8CE2ED, alpha: 0.90),
    outline: color(0x0C8BA5, alpha: 0.76),
    rimLight: color(0xFFFFFF, alpha: 0.88),
    softShadow: color(0x123A49, alpha: 0.12)
)

let darkTheme = Theme(
    name: "dark",
    backgroundTop: color(0x06121A),
    backgroundBottom: color(0x0B2733),
    atmosphere: color(0x1FD6FF),
    outerTop: color(0xA0FDFF, alpha: 0.98),
    outerBottom: color(0x026F87, alpha: 1.0),
    lowerTop: color(0x39EAFF, alpha: 0.98),
    lowerBottom: color(0x005E76, alpha: 1.0),
    innerTop: color(0xE2FEFF, alpha: 0.90),
    innerBottom: color(0x4AD5E4, alpha: 0.95),
    outline: color(0x7BF7FF, alpha: 0.70),
    rimLight: color(0xF8FFFF, alpha: 0.82),
    softShadow: color(0x000000, alpha: 0.30)
)

let fileManager = FileManager.default
try fileManager.createDirectory(at: imagesetURL, withIntermediateDirectories: true)
try fileManager.createDirectory(at: previewURL, withIntermediateDirectories: true)

let lightImage = try render(theme: lightTheme)
let darkImage = try render(theme: darkTheme)
let previewImage = try buildPreview(light: lightImage, dark: darkImage)

let lightOutput = imagesetURL.appendingPathComponent("water_drop_light.png")
let darkOutput = imagesetURL.appendingPathComponent("water_drop_dark.png")
let previewOutput = previewURL.appendingPathComponent("water_drop_variants.png")

try writePNG(lightImage, to: lightOutput)
try writePNG(darkImage, to: darkOutput)
try writePNG(previewImage, to: previewOutput)

let contentsJSON = """
{
  "images" : [
    {
      "filename" : "water_drop_light.png",
      "idiom" : "universal"
    },
    {
      "appearances" : [
        {
          "appearance" : "luminosity",
          "value" : "dark"
        }
      ],
      "filename" : "water_drop_dark.png",
      "idiom" : "universal"
    }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
"""

try contentsJSON.write(
    to: imagesetURL.appendingPathComponent("Contents.json"),
    atomically: true,
    encoding: .utf8
)

print(lightOutput.path)
print(darkOutput.path)
print(previewOutput.path)
