import XCTest
@testable import Terminal

final class ShellLaunchPlanTests: XCTestCase {
    func testDefaultUsesSSHLoginShell() {
        let launch = ShellLaunchPlan(sessionID: UUID(), useTmux: false, shellOverride: " \n")
        XCTAssertNil(launch.command)
        XCTAssertFalse(launch.usesTmux)
    }

    func testCustomShellUsesExecWithoutTypingACommand() {
        let launch = ShellLaunchPlan(sessionID: UUID(), useTmux: false, shellOverride: "/bin/zsh -l")
        XCTAssertEqual(launch.command, "exec '/bin/zsh' '-l'")
    }

    func testTmuxReusesOnlyItsOwnExactSessionAndHonorsCustomShell() {
        let id = UUID()
        let launch = ShellLaunchPlan(sessionID: id, useTmux: true, shellOverride: "/bin/zsh -l")
        let command = launch.command ?? ""
        XCTAssertTrue(launch.usesTmux)
        XCTAssertTrue(command.contains("has-session -t '=term-\(id.uuidString)'"))
        XCTAssertTrue(command.contains("status off"))
        XCTAssertTrue(command.contains("exec tmux attach-session"))
        XCTAssertFalse(command.contains("\r"))
        XCTAssertFalse(command.contains("\n"))
        XCTAssertFalse(command.contains("|| exec")) // exit must not respawn a shell
    }

    func testShellMetacharactersRemainQuotedArguments() {
        let launch = ShellLaunchPlan(sessionID: UUID(), useTmux: false, shellOverride: "sh -l;touch /tmp/unwanted 'x'")
        XCTAssertEqual(launch.command, "exec 'sh' '-l;touch' '/tmp/unwanted' ''\\''x'\\'''" )
    }
}
