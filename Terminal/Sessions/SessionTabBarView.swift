import SwiftUI

/// Floating strip over the terminal: one pill per live session,
/// plus create / overview affordances. State is glyph-only.
struct SessionTabBarView<MenuContent: View>: View {
    @EnvironmentObject private var engine: SessionEngine
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let onNewSession: () -> Void
    private let menu: MenuContent

    init(onNewSession: @escaping () -> Void, @ViewBuilder menu: () -> MenuContent) {
        self.onNewSession = onNewSession
        self.menu = menu()
    }

    var body: some View {
        HStack(spacing: 4) {
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 2) {
                        ForEach(engine.sessions) { session in
                            SessionPillView(session: session)
                                .id(session.id)
                        }
                    }
                    .padding(.horizontal, 6)
                }
                .onAppear {
                    if let id = engine.activeSessionID { proxy.scrollTo(id, anchor: .center) }
                }
                .onChange(of: engine.activeSessionID) { _, id in
                    guard let id else { return }
                    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) {
                        proxy.scrollTo(id, anchor: .center)
                    }
                }
            }

            HStack(spacing: 0) {
                menu
                Button {
                    Haptics.tap()
                    onNewSession()
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 17, weight: .medium))
                        .frame(width: 40, height: 40)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("New session")
            }
            .padding(.trailing, 4)
        }
        .frame(height: 40)
        .terminalGlass(cornerRadius: 20)
        .padding(.horizontal, 8)
        .accessibilityIdentifier("sessionTabBar")
    }
}

/// One session pill: status dot + title. Tap activates, long-press
/// offers reconnect / close.
private struct SessionPillView: View {
    @ObservedObject var session: TerminalSession
    @EnvironmentObject private var engine: SessionEngine

    private var isActive: Bool {
        engine.activeSessionID == session.id
    }

    var body: some View {
        Button {
            Haptics.select()
            engine.activeSessionID = session.id
        } label: {
            HStack(spacing: 7) {
                StatusDot(state: StatusDot.State(session.state))
                    .accessibilityHidden(true)
                Text(session.title)
                    .font(.system(.caption, weight: isActive ? .semibold : .regular))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: 160)
            }
            .padding(.horizontal, 12)
            .frame(height: 32)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.primary.opacity(isActive ? 0.16 : 0))
            )
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .foregroundStyle(isActive ? .primary : .secondary)
        .accessibilityAddTraits(isActive ? .isSelected : [])
        .accessibilityLabel(Text(session.title))
        .accessibilityValue(Text(StatusDot.State(session.state).accessibilityText))
        .accessibilityIdentifier(isActive ? "activeSessionStatus" : "session-\(session.id)")
        .contextMenu {
            Button {
                session.reconnect()
            } label: {
                Label("Reconnect", systemImage: "arrow.clockwise")
            }
            Button(role: .destructive) {
                engine.closeSession(session)
            } label: {
                Label("Close", systemImage: "xmark")
            }
        }
    }
}
