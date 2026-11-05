import UIKit

/// SVG path (the `d` attribute) -> UIBezierPath. Supports M L H V C S Q T A Z (absolute + relative).
enum SVGPath {
    private struct Reader {
        let chars: [Character]
        var i = 0

        init(_ s: String) { chars = Array(s) }

        var atEnd: Bool { return i >= chars.count }

        mutating func skipSeparators() {
            while i < chars.count {
                let c = chars[i]
                if c == " " || c == "," || c == "\n" || c == "\t" || c == "\r" { i += 1 } else { break }
            }
        }

        mutating func startsNumber() -> Bool {
            skipSeparators()
            guard i < chars.count else { return false }
            let c = chars[i]
            return c == "-" || c == "+" || c == "." || (c >= "0" && c <= "9")
        }

        mutating func number() -> CGFloat? {
            skipSeparators()
            var s = ""
            var seenDot = false
            var seenExp = false
            if i < chars.count, chars[i] == "-" || chars[i] == "+" {
                s.append(chars[i])
                i += 1
            }
            while i < chars.count {
                let c = chars[i]
                if c >= "0" && c <= "9" {
                    s.append(c)
                    i += 1
                } else if c == "." && !seenDot && !seenExp {
                    seenDot = true
                    s.append(c)
                    i += 1
                } else if (c == "e" || c == "E") && !seenExp && !s.isEmpty {
                    seenExp = true
                    s.append(c)
                    i += 1
                    if i < chars.count, chars[i] == "-" || chars[i] == "+" {
                        s.append(chars[i])
                        i += 1
                    }
                } else {
                    break
                }
            }
            guard let d = Double(s) else { return nil }
            return CGFloat(d)
        }

        /// Arc flags may be written without separators ("a1 1 0 011 1").
        mutating func flag() -> Bool? {
            skipSeparators()
            guard i < chars.count else { return nil }
            let c = chars[i]
            if c == "0" || c == "1" {
                i += 1
                return c == "1"
            }
            return nil
        }
    }

    static func parse(_ d: String) -> UIBezierPath {
        let path = UIBezierPath()
        var r = Reader(d)
        var cur = CGPoint.zero
        var start = CGPoint.zero
        var lastCubicCtrl: CGPoint?
        var lastQuadCtrl: CGPoint?
        var cmd: Character = "M"

        while true {
            r.skipSeparators()
            if r.atEnd { break }
            let c = r.chars[r.i]
            if c.isLetter {
                cmd = c
                r.i += 1
                if cmd == "Z" || cmd == "z" {
                    path.close()
                    cur = start
                    lastCubicCtrl = nil
                    lastQuadCtrl = nil
                    continue
                }
            } else if !r.startsNumber() {
                break
            }
            let rel = cmd.isLowercase
            let ox = rel ? cur.x : 0
            let oy = rel ? cur.y : 0
            var ok = true

            switch cmd {
            case "M", "m":
                if let x = r.number(), let y = r.number() {
                    cur = CGPoint(x: x + ox, y: y + oy)
                    start = cur
                    path.move(to: cur)
                    cmd = rel ? "l" : "L"
                } else { ok = false }
                lastCubicCtrl = nil
                lastQuadCtrl = nil
            case "L", "l":
                if let x = r.number(), let y = r.number() {
                    cur = CGPoint(x: x + ox, y: y + oy)
                    path.addLine(to: cur)
                } else { ok = false }
                lastCubicCtrl = nil
                lastQuadCtrl = nil
            case "H", "h":
                if let x = r.number() {
                    cur = CGPoint(x: x + ox, y: cur.y)
                    path.addLine(to: cur)
                } else { ok = false }
                lastCubicCtrl = nil
                lastQuadCtrl = nil
            case "V", "v":
                if let y = r.number() {
                    cur = CGPoint(x: cur.x, y: y + oy)
                    path.addLine(to: cur)
                } else { ok = false }
                lastCubicCtrl = nil
                lastQuadCtrl = nil
            case "C", "c":
                if let x1 = r.number(), let y1 = r.number(), let x2 = r.number(), let y2 = r.number(),
                   let x = r.number(), let y = r.number() {
                    let c1 = CGPoint(x: x1 + ox, y: y1 + oy)
                    let c2 = CGPoint(x: x2 + ox, y: y2 + oy)
                    cur = CGPoint(x: x + ox, y: y + oy)
                    path.addCurve(to: cur, controlPoint1: c1, controlPoint2: c2)
                    lastCubicCtrl = c2
                } else { ok = false }
                lastQuadCtrl = nil
            case "S", "s":
                if let x2 = r.number(), let y2 = r.number(), let x = r.number(), let y = r.number() {
                    var c1 = cur
                    if let lc = lastCubicCtrl { c1 = CGPoint(x: 2 * cur.x - lc.x, y: 2 * cur.y - lc.y) }
                    let c2 = CGPoint(x: x2 + ox, y: y2 + oy)
                    cur = CGPoint(x: x + ox, y: y + oy)
                    path.addCurve(to: cur, controlPoint1: c1, controlPoint2: c2)
                    lastCubicCtrl = c2
                } else { ok = false }
                lastQuadCtrl = nil
            case "Q", "q":
                if let x1 = r.number(), let y1 = r.number(), let x = r.number(), let y = r.number() {
                    let c1 = CGPoint(x: x1 + ox, y: y1 + oy)
                    cur = CGPoint(x: x + ox, y: y + oy)
                    path.addQuadCurve(to: cur, controlPoint: c1)
                    lastQuadCtrl = c1
                } else { ok = false }
                lastCubicCtrl = nil
            case "T", "t":
                if let x = r.number(), let y = r.number() {
                    var c1 = cur
                    if let lq = lastQuadCtrl { c1 = CGPoint(x: 2 * cur.x - lq.x, y: 2 * cur.y - lq.y) }
                    cur = CGPoint(x: x + ox, y: y + oy)
                    path.addQuadCurve(to: cur, controlPoint: c1)
                    lastQuadCtrl = c1
                } else { ok = false }
                lastCubicCtrl = nil
            case "A", "a":
                if let rx = r.number(), let ry = r.number(), let rot = r.number(),
                   let large = r.flag(), let sweep = r.flag(),
                   let x = r.number(), let y = r.number() {
                    let end = CGPoint(x: x + ox, y: y + oy)
                    addArc(path, from: cur, rx: rx, ry: ry, rotation: rot, large: large, sweep: sweep, to: end)
                    cur = end
                } else { ok = false }
                lastCubicCtrl = nil
                lastQuadCtrl = nil
            default:
                ok = false
            }
            if !ok { break }
        }
        return path
    }

    /// SVG elliptical arc -> cubic Bezier segments (SVG spec, appendix F.6).
    private static func addArc(_ path: UIBezierPath, from p0: CGPoint, rx rxIn: CGFloat, ry ryIn: CGFloat,
                               rotation: CGFloat, large: Bool, sweep: Bool, to p1: CGPoint) {
        var rx = abs(rxIn)
        var ry = abs(ryIn)
        if rx == 0 || ry == 0 || (p0.x == p1.x && p0.y == p1.y) {
            path.addLine(to: p1)
            return
        }
        let phi = rotation * .pi / 180
        let cosPhi = cos(phi)
        let sinPhi = sin(phi)
        let dx2 = (p0.x - p1.x) / 2
        let dy2 = (p0.y - p1.y) / 2
        let x1p = cosPhi * dx2 + sinPhi * dy2
        let y1p = -sinPhi * dx2 + cosPhi * dy2
        let lambda = (x1p * x1p) / (rx * rx) + (y1p * y1p) / (ry * ry)
        if lambda > 1 {
            let s = sqrt(lambda)
            rx *= s
            ry *= s
        }
        let rx2 = rx * rx
        let ry2 = ry * ry
        var num = rx2 * ry2 - rx2 * y1p * y1p - ry2 * x1p * x1p
        let den = rx2 * y1p * y1p + ry2 * x1p * x1p
        if den == 0 {
            path.addLine(to: p1)
            return
        }
        if num < 0 { num = 0 }
        var coef = sqrt(num / den)
        if large == sweep { coef = -coef }
        let cxp = coef * (rx * y1p / ry)
        let cyp = coef * (-ry * x1p / rx)
        let cx = cosPhi * cxp - sinPhi * cyp + (p0.x + p1.x) / 2
        let cy = sinPhi * cxp + cosPhi * cyp + (p0.y + p1.y) / 2

        func angle(_ ux: CGFloat, _ uy: CGFloat, _ vx: CGFloat, _ vy: CGFloat) -> CGFloat {
            let dot = ux * vx + uy * vy
            let len = sqrt(ux * ux + uy * uy) * sqrt(vx * vx + vy * vy)
            if len == 0 { return 0 }
            var a = acos(max(-1, min(1, dot / len)))
            if ux * vy - uy * vx < 0 { a = -a }
            return a
        }
        let theta1 = angle(1, 0, (x1p - cxp) / rx, (y1p - cyp) / ry)
        var dtheta = angle((x1p - cxp) / rx, (y1p - cyp) / ry, (-x1p - cxp) / rx, (-y1p - cyp) / ry)
        if !sweep && dtheta > 0 { dtheta -= 2 * .pi }
        if sweep && dtheta < 0 { dtheta += 2 * .pi }

        let segs = max(1, Int(ceil(abs(dtheta) / (.pi / 2))))
        let delta = dtheta / CGFloat(segs)
        let t = 4.0 / 3.0 * tan(delta / 4)

        func map(_ u: CGFloat, _ v: CGFloat) -> CGPoint {
            return CGPoint(x: cx + rx * u * cosPhi - ry * v * sinPhi,
                           y: cy + rx * u * sinPhi + ry * v * cosPhi)
        }
        var th = theta1
        for _ in 0..<segs {
            let c1 = cos(th)
            let s1 = sin(th)
            let c2 = cos(th + delta)
            let s2 = sin(th + delta)
            let cp1 = map(c1 - t * s1, s1 + t * c1)
            let cp2 = map(c2 + t * s2, s2 - t * c2)
            let end = map(c2, s2)
            path.addCurve(to: end, controlPoint1: cp1, controlPoint2: cp2)
            th += delta
        }
    }
}

/// Material icons rendered from path data as template images (tint with `tintColor`).
enum Icons {
    private static var cache: [String: UIImage] = [:]
    private static let lock = NSLock()

    /// `name` is a key of `IconData.paths`; append "_outline" for the outlined variant.
    static func image(_ name: String, size: CGFloat = 24) -> UIImage {
        let key = "\(name)@\(size)"
        lock.lock()
        if let hit = cache[key] {
            lock.unlock()
            return hit
        }
        lock.unlock()

        let img: UIImage
        if name == "shorts" || name == "shorts_outline" {
            img = drawShorts(filled: name == "shorts", size: size)
        } else if let d = IconData.paths[name] ?? IconData.paths[name.replacingOccurrences(of: "_outline", with: "")] {
            img = render(path: SVGPath.parse(d), viewBox: 24, size: size)
        } else {
            img = UIImage()
        }
        let templ = img.withRenderingMode(.alwaysTemplate)
        lock.lock()
        cache[key] = templ
        lock.unlock()
        return templ
    }

    private static func render(path: UIBezierPath, viewBox: CGFloat, size: CGFloat) -> UIImage {
        let fmt = UIGraphicsImageRendererFormat.default()
        fmt.opaque = false
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: size, height: size), format: fmt)
        return renderer.image { _ in
            let s = size / viewBox
            path.apply(CGAffineTransform(scaleX: s, y: s))
            UIColor.black.setFill()
            path.fill()
        }
    }

    /// Shorts logo-ish glyph: portrait rounded rectangle with a play triangle.
    private static func drawShorts(filled: Bool, size: CGFloat) -> UIImage {
        let fmt = UIGraphicsImageRendererFormat.default()
        fmt.opaque = false
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: size, height: size), format: fmt)
        return renderer.image { ctx in
            let u = size / 24
            let body = UIBezierPath(roundedRect: CGRect(x: 5.5 * u, y: 2.5 * u, width: 13 * u, height: 19 * u), cornerRadius: 4 * u)
            let tri = UIBezierPath()
            tri.move(to: CGPoint(x: 10 * u, y: 8.5 * u))
            tri.addLine(to: CGPoint(x: 10 * u, y: 15.5 * u))
            tri.addLine(to: CGPoint(x: 16 * u, y: 12 * u))
            tri.close()
            UIColor.black.setFill()
            UIColor.black.setStroke()
            if filled {
                body.fill()
                // punch the triangle out of the filled body
                ctx.cgContext.setBlendMode(.clear)
                tri.fill()
            } else {
                body.lineWidth = 2 * u
                body.stroke()
                tri.fill()
            }
        }
    }

    /// The in-app logo mark (red rounded play button) used in the top bar.
    static func logoMark(height: CGFloat) -> UIImage {
        let w = height * 1.42
        let fmt = UIGraphicsImageRendererFormat.default()
        fmt.opaque = false
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: w, height: height), format: fmt)
        return renderer.image { _ in
            let rect = CGRect(x: 0, y: 0, width: w, height: height)
            let body = UIBezierPath(roundedRect: rect, cornerRadius: height * 0.28)
            Theme.red.setFill()
            body.fill()
            let tri = UIBezierPath()
            let cx = w / 2 + height * 0.04
            let cy = height / 2
            tri.move(to: CGPoint(x: cx - height * 0.17, y: cy - height * 0.24))
            tri.addLine(to: CGPoint(x: cx - height * 0.17, y: cy + height * 0.24))
            tri.addLine(to: CGPoint(x: cx + height * 0.25, y: cy))
            tri.close()
            UIColor.white.setFill()
            tri.fill()
        }
    }
}
