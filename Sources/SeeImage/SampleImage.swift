import AppKit

/// Procedural artwork used by the snapshot renderer (CI / README) so the
/// repository does not have to ship a copyrighted sample photo.
enum SampleImage {
    private struct Ridge {
        let base: CGFloat
        let amplitude: CGFloat
        let phase: CGFloat
        let color: NSColor
    }

    static func make(size: NSSize, variant: Int) -> NSImage {
        NSImage(size: size, flipped: false) { rect in
            draw(in: rect, variant: variant)
            return true
        }
    }

    private static func draw(in rect: NSRect, variant: Int) {
        let width = rect.width
        let height = rect.height

        let palettes: [[NSColor]] = [
            [
                NSColor(calibratedRed: 0.09, green: 0.13, blue: 0.28, alpha: 1),
                NSColor(calibratedRed: 0.42, green: 0.33, blue: 0.55, alpha: 1),
                NSColor(calibratedRed: 0.95, green: 0.58, blue: 0.46, alpha: 1),
            ],
            [
                NSColor(calibratedRed: 0.05, green: 0.22, blue: 0.30, alpha: 1),
                NSColor(calibratedRed: 0.15, green: 0.47, blue: 0.53, alpha: 1),
                NSColor(calibratedRed: 0.85, green: 0.90, blue: 0.77, alpha: 1),
            ],
        ]
        let colors = palettes[variant % palettes.count]

        NSGradient(colors: colors)?.draw(in: rect, angle: 90)

        let sunRadius = width * 0.085
        let sunCenter = NSPoint(
            x: width * (variant % 2 == 0 ? 0.68 : 0.30),
            y: height * 0.63
        )
        let sunRect = NSRect(
            x: sunCenter.x - sunRadius,
            y: sunCenter.y - sunRadius,
            width: sunRadius * 2,
            height: sunRadius * 2
        )
        NSColor(calibratedRed: 1.0, green: 0.92, blue: 0.76, alpha: 0.92).setFill()
        NSBezierPath(ovalIn: sunRect).fill()

        let ridges: [Ridge] = [
            Ridge(
                base: 0.44,
                amplitude: 0.055,
                phase: 0.4,
                color: NSColor(calibratedRed: 0.22, green: 0.24, blue: 0.34, alpha: 0.55)
            ),
            Ridge(
                base: 0.32,
                amplitude: 0.075,
                phase: 2.1,
                color: NSColor(calibratedRed: 0.15, green: 0.17, blue: 0.26, alpha: 0.75)
            ),
            Ridge(
                base: 0.18,
                amplitude: 0.05,
                phase: 4.3,
                color: NSColor(calibratedRed: 0.08, green: 0.09, blue: 0.15, alpha: 0.94)
            ),
        ]

        for ridge in ridges {
            let path = NSBezierPath()
            path.move(to: NSPoint(x: 0, y: 0))
            path.line(to: NSPoint(x: 0, y: height * ridge.base))
            let steps = 96
            for step in 0...steps {
                let progress = CGFloat(step) / CGFloat(steps)
                let x = width * progress
                let y = height * ridge.base
                    + height * ridge.amplitude * sin(progress * 7.2 + ridge.phase)
                    + height * ridge.amplitude * 0.35 * sin(progress * 18 + ridge.phase * 1.7)
                path.line(to: NSPoint(x: x, y: y))
            }
            path.line(to: NSPoint(x: width, y: 0))
            path.close()
            ridge.color.setFill()
            path.fill()
        }

        let mist = NSBezierPath(
            roundedRect: NSRect(
                x: 0,
                y: height * 0.33,
                width: width,
                height: height * 0.10
            ),
            xRadius: width * 0.05,
            yRadius: height * 0.05
        )
        NSColor.white.withAlphaComponent(0.10).setFill()
        mist.fill()
    }
}
