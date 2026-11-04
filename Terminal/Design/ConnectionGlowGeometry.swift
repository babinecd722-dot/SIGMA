import Foundation

/// Deterministic geometry shared by the native Canvas and the motion preview.
/// No timers, random state, or allocations proportional to terminal output.
enum ConnectionGlowGeometry {
    struct Stroke {
        let points: [CGPoint]
        let strength: Double
    }

    struct Frame {
        let strokes: [Stroke]
        let heads: [CGPoint]
        let glow: Double
    }

    static let duration = 3.6

    static func frame(time: Double, size: CGSize) -> Frame {
        guard size.width > 12, size.height > 12 else {
            return Frame(strokes: [], heads: [], glow: 0)
        }
        let phase = max(0, time) / duration
        let span = 0.24
        let points = (0...72).map { index in
            perimeter(phase + Double(index) / 72 * span, size: size)
        }
        return Frame(strokes: [Stroke(points: points, strength: 1)],
                     heads: [points[points.count / 2]], glow: 0.75)
    }

    private static func perimeter(_ progress: Double, size: CGSize) -> CGPoint {
        let inset = 3.0
        let width = max(1, Double(size.width) - inset * 2)
        let height = max(1, Double(size.height) - inset * 2)
        let radius = min(17, min(width, height) / 2)
        let horizontal = width - radius * 2
        let vertical = height - radius * 2
        let arc = .pi * radius / 2
        let lengths = [horizontal, arc, vertical, arc, horizontal, arc, vertical, arc]
        let total = lengths.reduce(0, +)
        var distance = (progress - floor(progress)) * total
        for (section, length) in lengths.enumerated() {
            if distance > length, section < 7 { distance -= length; continue }
            let f = length > 0 ? distance / length : 0
            let x: Double, y: Double
            switch section {
            case 0: (x, y) = (radius + distance, 0)
            case 2: (x, y) = (width, radius + distance)
            case 4: (x, y) = (width - radius - distance, height)
            case 6: (x, y) = (0, height - radius - distance)
            default:
                let angle = (Double(section - 1) / 2 - 1) * .pi / 2 + f * .pi / 2
                let cx = section == 1 || section == 3 ? width - radius : radius
                let cy = section == 1 || section == 7 ? radius : height - radius
                (x, y) = (cx + cos(angle) * radius, cy + sin(angle) * radius)
            }
            return CGPoint(x: x + inset, y: y + inset)
        }
        return .zero
    }
}
