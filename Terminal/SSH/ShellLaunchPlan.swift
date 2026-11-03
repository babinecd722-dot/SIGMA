import Foundation

/// Startup belongs to the SSH exec request, before interactive input exists.
/// It must never be typed into a login shell or filtered from remote output.
struct ShellLaunchPlan {
    let command: String?
    let usesTmux: Bool

    init(sessionID: UUID, useTmux: Bool, shellOverride: String) {
        let words = shellOverride.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        let shell = words.isEmpty ? nil : "exec " + words.map(Self.quote).joined(separator: " ")
        usesTmux = useTmux
        guard useTmux else {
            command = shell
            return
        }
        let name = "term-\(sessionID.uuidString)"
        let target = Self.quote("=" + name)
        let customShell = shell.map { " " + Self.quote($0) } ?? ""
        command = "if ! tmux has-session -t \(target) 2>/dev/null; then "
            + "tmux new-session -d -s \(Self.quote(name))\(customShell) || exit; fi; "
            + "tmux set-option -t \(target) status off; "
            + "exec tmux attach-session -d -t \(target)"
    }

    private static func quote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
