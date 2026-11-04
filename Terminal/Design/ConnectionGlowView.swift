import SwiftUI

/// One smooth green line follows the card; the label and icon never move.
/// Only connecting rows own a clock, capped at 30 fps and stopped off-scene.
struct ConnectionGlowView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var started = Date()

    var body: some View {
        Group {
            if reduceMotion || scenePhase != .active {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(Color.terminalAccent.opacity(0.65), lineWidth: 1)
                    .background(Color.terminalAccent.opacity(0.05), in: RoundedRectangle(cornerRadius: 20))
            } else {
                TimelineView(.animation(minimumInterval: 1.0 / 30)) { timeline in
                    Canvas(rendersAsynchronously: true) { context, size in
                        let frame = ConnectionGlowGeometry.frame(time: timeline.date.timeIntervalSince(started), size: size)
                        let bounds = CGRect(origin: .zero, size: size)
                        let outline = Path(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), cornerRadius: 20)
                        var wash = context
                        wash.clip(to: outline)
                        for head in frame.heads {
                            wash.fill(Path(bounds), with: .radialGradient(
                                Gradient(colors: [.terminalAccent.opacity(0.14 * frame.glow), .clear]),
                                center: head, startRadius: 0, endRadius: size.width * 0.6))
                        }
                        for stroke in frame.strokes {
                            guard let first = stroke.points.first else { continue }
                            var path = Path()
                            path.move(to: first)
                            stroke.points.dropFirst().forEach { path.addLine(to: $0) }
                            var halo = context
                            halo.addFilter(.blur(radius: 5))
                            halo.stroke(path, with: .color(.terminalAccent.opacity(stroke.strength * 0.75)),
                                        style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
                            context.stroke(path, with: .color(Color(red: 0.26, green: 1, blue: 0.53).opacity(stroke.strength)),
                                           style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
                        }
                    }
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

struct ServerConnectionDecoration: View {
    @ObservedObject var session: TerminalSession

    var body: some View {
        if session.state == .connecting || session.state == .reconnecting {
            ConnectionGlowView()
        }
    }
}
