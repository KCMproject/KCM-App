import SwiftUI

struct EggShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let scaleX = rect.width / 110
        let scaleY = rect.height / 130
        let transform = CGAffineTransform(scaleX: scaleX, y: scaleY)
            .translatedBy(x: rect.minX / scaleX, y: rect.minY / scaleY)

        path.move(to: CGPoint(x: 55, y: 6))
        path.addCurve(to: CGPoint(x: 14, y: 68), control1: CGPoint(x: 28, y: 6), control2: CGPoint(x: 14, y: 36))
        path.addCurve(to: CGPoint(x: 55, y: 122), control1: CGPoint(x: 14, y: 100), control2: CGPoint(x: 32, y: 122))
        path.addCurve(to: CGPoint(x: 96, y: 68), control1: CGPoint(x: 78, y: 122), control2: CGPoint(x: 96, y: 100))
        path.addCurve(to: CGPoint(x: 55, y: 6), control1: CGPoint(x: 96, y: 36), control2: CGPoint(x: 82, y: 6))
        path.closeSubpath()

        return path.applying(transform)
    }
}

struct EggHalf: Shape {
    let isLeft: Bool

    func path(in rect: CGRect) -> Path {
        let eggPath = EggShape().path(in: rect)
        var path = Path()
        let width = rect.width
        let height = rect.height

        if isLeft {
            path.addRect(CGRect(x: 0, y: 0, width: width / 2, height: height))
        } else {
            path.addRect(CGRect(x: width / 2, y: 0, width: width / 2, height: height))
        }

        return eggPath.intersection(path)
    }
}

struct EggCracks: Shape {
    let level: Int

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let scaleX = rect.width / 110
        let scaleY = rect.height / 130
        let transform = CGAffineTransform(scaleX: scaleX, y: scaleY)

        let cracks: [(Int, String)] = [
            (1, "M52 48 L58 58 L53 65"),
            (2, "M58 58 L66 54 L70 62 M52 48 L46 44 L42 52"),
            (3, "M55 65 L59 76 L54 83 M42 52 L36 57 L40 64 M70 62 L76 66 L72 74"),
            (4, "M47 38 L42 32 L48 28 M64 40 L70 34 M46 95 L40 103 M66 92 L72 100 L68 108")
        ]

        for (minLevel, d) in cracks where level >= minLevel {
            path.addPath(parseSVGPath(d).applying(transform))
        }

        return path
    }

    private func parseSVGPath(_ d: String) -> Path {
        var path = Path()
        var current = CGPoint.zero
        var index = d.startIndex

        func parseNumber() -> CGFloat? {
            while index < d.endIndex && (d[index] == " " || d[index] == ",") {
                d.formIndex(after: &index)
            }
            guard index < d.endIndex else { return nil }

            let start = index
            if d[index] == "-" {
                d.formIndex(after: &index)
            }
            var hasDigit = false
            var hasDot = false
            while index < d.endIndex {
                let c = d[index]
                if c.isNumber {
                    hasDigit = true
                    d.formIndex(after: &index)
                } else if c == "." && !hasDot {
                    hasDot = true
                    d.formIndex(after: &index)
                } else {
                    break
                }
            }
            guard hasDigit else { return nil }
            let numStr = String(d[start..<index])
            return CGFloat(Double(numStr) ?? 0)
        }

        var currentCommand: Character = " "

        while index < d.endIndex {
            while index < d.endIndex && d[index] == " " {
                d.formIndex(after: &index)
            }
            guard index < d.endIndex else { break }

            if d[index].isLetter {
                currentCommand = d[index]
                d.formIndex(after: &index)
            }

            guard let x = parseNumber(), let y = parseNumber() else { break }

            switch currentCommand {
            case "M":
                current = CGPoint(x: x, y: y)
                path.move(to: current)
                currentCommand = "L"
            case "L", "l":
                current = CGPoint(x: x, y: y)
                path.addLine(to: current)
            default:
                break
            }
        }

        return path
    }
}
