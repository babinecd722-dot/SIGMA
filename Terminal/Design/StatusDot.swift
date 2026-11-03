import SwiftUI

/// Session state dot: color + a connecting pulse, plus a spoken label
/// for VoiceOver — the state is never conveyed by color alone.
struct StatusDot: View {
    enum State: Equatable {
        case connecting, online, reconnecting, offline, failed

        var accessibilityText: String {
            switch self {
            case .connecting: return String(localized: "Connecting")
            case .online: return String(localized: "Connected")
            case .reconnecting: return String(localized: "Reconnecting")
            case .offline: return String(localized: "Offline")
            case .failed: return String(localized: "Failed")
            }
        }
    }

    let state: State
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(state: State) {
        self.state = state
    }

    private var color: Color {
        switch state {
        case .online: return .terminalAccent
        case .connecting, .reconnecting: return .orange
        case .failed: return .red
        case .offline: return .gray.opacity(0.5)
        }
    }

    var body: some View {
        Group {
            if animates {
                dot.phaseAnimator([false, true]) { content, dimmed in
                    content.opacity(dimmed ? 0.4 : 1)
                } animation: { _ in .easeInOut(duration: 0.9) }
            } else {
                dot
            }
        }
            .accessibilityLabel(Text("Status"))
            .accessibilityValue(Text(state.accessibilityText))
    }

    private var dot: some View {
        Circle().fill(color).frame(width: 8, height: 8)
    }

    /// Pulse only while establishing a connection — steady states don't
    /// need motion, and neither does the user's Reduce Motion setting.
    private var animates: Bool {
        !reduceMotion && (state == .connecting || state == .reconnecting)
    }
}

extension StatusDot.State {
    init(_ sessionState: TerminalSession.State) {
        switch sessionState {
        case .connecting: self = .connecting
        case .online: self = .online
        case .reconnecting: self = .reconnecting
        case .offline: self = .offline
        case .failed: self = .failed
        }
    }
}

extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
